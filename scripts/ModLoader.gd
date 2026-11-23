## ModLoader
##
## Global singleton (autoload) that provides the v1 modding seam:
##   1. Discover mod folders under res://mods/ (or another root, for tests).
##   2. Validate each mod's mod.json manifest.
##   3. Resolve dependencies in topological order, rejecting cycles.
##   4. Load each mod's content resources into typed ID -> Resource registries.
##   5. Honour enable/disable flags and skip invalid mods with a log, never crash.
##
## The registries live here (no separate autoload): later tickets (NPC spawning,
## dialogue filtering, save linkage) look resources up by stable ID through
## get_resource()/get_all(). v1 is add-only — duplicate IDs are never overridden.
##
## Authored base characters under res://resources/characters/ are registered into
## the `character` bucket first (ticket 012), so NPC spawning has a single
## resolution path for both base and modded templates.
extends Node

## --- Registry bucket names -------------------------------------------------
const TYPE_CHARACTER: String = "character"
const TYPE_TRAIT: String = "trait"
const TYPE_ITEM: String = "item"
const TYPE_MAP: String = "map"
const TYPE_DIALOGUE: String = "dialogue"

## --- Filesystem conventions ------------------------------------------------
const DEFAULT_MODS_ROOT: String = "res://mods/"
const MANIFEST_FILE: String = "mod.json"
const DISABLED_MARKER: String = ".disabled"

## Authored (non-mod) character templates loaded directly from res://. They are
## registered before mod content so v1's add-only rule lets mods add new ids but
## never silently override a base id.
const BASE_CHARACTERS_DIR: String = "res://resources/characters/"
const BASE_OWNER: String = "base"

## bucket name -> { stable id (String) -> Resource }
var _registries: Dictionary = {}

## "bucket:id" -> mod id (String). Tracks ownership for diagnostics.
var _owners: Dictionary = {}

## Mod ids that loaded successfully, in load (topological) order.
var _loaded_mods: Array[String] = []

## Diagnostics for the most recent load_mods() call.
## Each entry: { "mod": String, "status": "loaded"|"skipped", "reason": String }
var _last_report: Array = []

## The root path scanned by the most recent load_mods() call.
var _mods_root: String = DEFAULT_MODS_ROOT

## True while load_mods() is running. Entry hooks receive this autoload, so a
## re-entrant load_mods() call must not wipe registries mid-load.
var _is_loading: bool = false


func _ready() -> void:
	_reset_registries()
	load_mods()


## --- Public registry API ---------------------------------------------------

## Register a resource into the bucket for `type`. Returns false (with a log)
## for unsupported types, missing ids, or add-only ID conflicts.
func register_resource(type: String, resource: Resource, mod_id: String = "") -> bool:
	if not _registries.has(type):
		_log("WARN: unknown registry type '%s' (from mod '%s')" % [type, mod_id])
		return false
	if resource == null:
		_log("WARN: mod '%s' tried to register a null resource" % mod_id)
		return false

	var id: String = str(resource.get("id"))
	if id.is_empty():
		_log("WARN: mod '%s' resource has no id; not registered" % mod_id)
		return false

	var bucket: Dictionary = _registries[type]
	if bucket.has(id):
		_log("WARN: add-only conflict for '%s:%s' (mod '%s'): already owned by mod '%s'; skipping" % [type, id, mod_id, str(_owners.get(type + ":" + id, "unknown"))])
		return false

	bucket[id] = resource
	_owners[type + ":" + id] = mod_id
	return true


## Look up a resource by bucket + stable id. Returns null when absent.
func get_resource(type: String, id: String) -> Resource:
	if _registries.has(type) and (_registries[type] as Dictionary).has(id):
		return _registries[type][id] as Resource
	return null


## True when a resource with this id exists in the bucket.
func has_resource(type: String, id: String) -> bool:
	return get_resource(type, id) != null


## All resources in a bucket (values, in insertion order). Empty array if unknown.
func get_all(type: String) -> Array:
	if _registries.has(type):
		return (_registries[type] as Dictionary).values()
	return []


## A copy of a bucket (id -> Resource) for safe read-only inspection.
func get_registry(type: String) -> Dictionary:
	if _registries.has(type):
		return (_registries[type] as Dictionary).duplicate()
	return {}


## Mod ids that loaded successfully, in topological order (copy).
func get_loaded_mods() -> Array[String]:
	return _loaded_mods.duplicate()


## Diagnostics from the most recent load_mods() call (deep copy).
func get_last_report() -> Array:
	return _last_report.duplicate(true)


## Root path used by the most recent scan.
func get_mods_root() -> String:
	return _mods_root


## --- Loading pipeline ------------------------------------------------------

## (Re)load all mods from `root_path`. Clears every registry first so the
## function is idempotent and testable (tests can point it at user:// trees).
func load_mods(root_path: String = DEFAULT_MODS_ROOT) -> void:
	# An entry hook is handed `self`; without this guard it could call
	# load_mods() again and clear registries while the outer load is running.
	if _is_loading:
		_log("WARN: load_mods() called while already loading; ignoring re-entrant request")
		return
	_is_loading = true
	_reset_registries()
	_register_base_content()
	_mods_root = root_path

	var mods: Dictionary = _discover_mods(root_path)
	var resolution: Dictionary = _resolve_order(mods)
	var order: Array = resolution["order"]

	for mod_id in order:
		_load_one_mod(str(mod_id), mods)

	_is_loading = false
	_log("Loaded %d mod(s); %d resource(s) registered." % [_loaded_mods.size(), _resource_count()])


func _reset_registries() -> void:
	_registries = {
		TYPE_CHARACTER: {},
		TYPE_TRAIT: {},
		TYPE_ITEM: {},
		TYPE_MAP: {},
		TYPE_DIALOGUE: {},
	}
	_owners.clear()
	_loaded_mods.clear()
	_last_report.clear()


## Register authored base character templates into the `character` registry.
## Runs on every load_mods() (after the clear) so re-scans restore base content.
## A missing directory is a soft warning, never a crash — gameplay can still run
## from mod content alone.
func _register_base_content() -> void:
	var dir: DirAccess = DirAccess.open(BASE_CHARACTERS_DIR)
	if dir == null:
		_log("WARN: cannot open base characters directory '%s' (error %d)" % [BASE_CHARACTERS_DIR, DirAccess.get_open_error()])
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.ends_with(".tres") or entry.ends_with(".res"):
			var path: String = _join(BASE_CHARACTERS_DIR, entry)
			var resource: Resource = ResourceLoader.load(path)
			if resource is CharacterTemplate:
				register_resource(TYPE_CHARACTER, resource, BASE_OWNER)
			else:
				_log("WARN: base content '%s' is not a CharacterTemplate; skipping" % path)
		entry = dir.get_next()
	dir.list_dir_end()


## Scan `root_path` for direct subfolders that are mod candidates.
## Returns { mod id -> validated manifest Dictionary }.
func _discover_mods(root_path: String) -> Dictionary:
	var mods: Dictionary = {}
	var dir: DirAccess = DirAccess.open(root_path)
	if dir == null:
		_log("WARN: cannot open mods directory '%s' (error %d); skipping mod scan" % [root_path, DirAccess.get_open_error()])
		return mods

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != ".." and dir.current_is_dir():
			var folder: String = _join(root_path, entry)
			var manifest_path: String = _join(folder, MANIFEST_FILE)
			if not FileAccess.file_exists(manifest_path):
				_log("SKIP mod folder '%s': missing %s" % [entry, MANIFEST_FILE])
				_add_report(entry, "skipped", "missing %s" % MANIFEST_FILE, folder)
			else:
				var parsed: Variant = _read_json(manifest_path)
				var validation: Dictionary = _validate_manifest(parsed, entry)
				if not bool(validation.get("ok", false)):
					# Validation reasons already name the folder.
					_log("SKIP: %s" % str(validation.get("reason", "invalid manifest")))
					_add_report(entry, "skipped", str(validation.get("reason", "invalid manifest")), folder)
				else:
					var manifest: Dictionary = validation["manifest"]
					var mod_id: String = str(manifest.get("id", entry))
					if mod_id.is_empty():
						mod_id = entry
					if mods.has(mod_id):
						_log("SKIP mod '%s': duplicate id (folder '%s')" % [mod_id, entry])
						# Composite key keeps this skip distinct from the surviving
						# mod's report entry, which uses the bare `mod_id`.
						_add_report("%s@%s" % [mod_id, entry], "skipped", "duplicate mod id", folder)
					else:
						manifest["_folder_path"] = folder
						mods[mod_id] = manifest
		entry = dir.get_next()
	dir.list_dir_end()
	return mods


## Validate the parsed manifest. Returns
## { "ok": bool, "manifest": Dictionary, "reason": String }.
func _validate_manifest(parsed: Variant, folder_name: String) -> Dictionary:
	var label: String = "mod folder '%s'" % folder_name

	if not (parsed is Dictionary):
		return {"ok": false, "reason": "%s: %s is not a JSON object" % [label, MANIFEST_FILE]}

	var manifest: Dictionary = parsed

	for field: String in ["name", "version", "author", "entry"]:
		if not manifest.has(field) or not (manifest[field] is String) or (manifest[field] as String).is_empty():
			return {"ok": false, "reason": "%s: missing or empty required field '%s'" % [label, field]}

	for field: String in ["dependencies", "content"]:
		if not manifest.has(field) or not (manifest[field] is Array):
			return {"ok": false, "reason": "%s: missing required array field '%s'" % [label, field]}
		for element in manifest[field]:
			if not (element is String):
				return {"ok": false, "reason": "%s: field '%s' must contain only strings" % [label, field]}

	if manifest.has("id") and not (manifest["id"] is String):
		return {"ok": false, "reason": "%s: optional field 'id' must be a string" % label}
	if manifest.has("enabled") and not (manifest["enabled"] is bool):
		return {"ok": false, "reason": "%s: optional field 'enabled' must be a boolean" % label}

	return {"ok": true, "manifest": manifest, "reason": ""}


## Kahn topological sort over discovered mods. Returns
## { "order": Array[String], "cycles": Array[String] }.
## Mods left unprocessed are in (or depend on) a cycle and are rejected.
func _resolve_order(mods: Dictionary) -> Dictionary:
	var indegree: Dictionary = {}
	var dependents: Dictionary = {}
	for id in mods.keys():
		indegree[id] = 0
		dependents[id] = []

	for id in mods.keys():
		for dep in mods[id].get("dependencies", []):
			if mods.has(str(dep)):
				indegree[id] = int(indegree[id]) + 1
				dependents[str(dep)].append(str(id))
			# Unknown deps are reported at load time as "missing dependency".

	var queue: Array[String] = []
	for id in mods.keys():
		if int(indegree[id]) == 0:
			queue.append(str(id))

	var order: Array[String] = []
	while not queue.is_empty():
		var id: String = queue.pop_front()
		order.append(id)
		for dependent in dependents[id]:
			indegree[dependent] = int(indegree[dependent]) - 1
			if int(indegree[dependent]) == 0:
				queue.append(str(dependent))

	var cycles: Array[String] = []
	if order.size() < mods.size():
		for id in mods.keys():
			if not order.has(str(id)):
				cycles.append(str(id))
		# The leftover set mixes cycle members with mods that merely depend on
		# one; word both the log and the report so neither is mislabeled.
		_log("SKIP cyclic dependency (mod(s) in or depending on a cycle): %s" % ", ".join(cycles))
		for id in cycles:
			_add_report(id, "skipped", "cyclic dependency (member or dependent)", str(mods[id].get("_folder_path", "")))

	return {"order": order, "cycles": cycles}


## Load and register a single mod (already validated and topologically ordered).
func _load_one_mod(mod_id: String, mods: Dictionary) -> void:
	var manifest: Dictionary = mods[mod_id]
	var folder: String = str(manifest.get("_folder_path", ""))

	# 1. Enable/disable flag.
	if manifest.has("enabled") and manifest["enabled"] == false:
		_log("SKIP mod '%s': disabled (enabled=false)" % mod_id)
		_add_report(mod_id, "skipped", "disabled", folder)
		return
	if FileAccess.file_exists(_join(folder, DISABLED_MARKER)):
		_log("SKIP mod '%s': disabled (%s marker)" % [mod_id, DISABLED_MARKER])
		_add_report(mod_id, "skipped", "disabled", folder)
		return

	# 2. Dependencies must have loaded earlier in topological order.
	for dep in manifest.get("dependencies", []):
		var dep_id: String = str(dep)
		if not _loaded_mods.has(dep_id):
			_log("SKIP mod '%s': missing/unavailable dependency '%s'" % [mod_id, dep_id])
			_add_report(mod_id, "skipped", "missing dependency '%s'" % dep_id, folder)
			return

	# 3. Entry script must be loadable (validated before content so an invalid
	#    entry never leaves partially registered resources behind).
	var entry_path: String = _resolve_path(str(manifest["entry"]), folder)
	if not ResourceLoader.exists(entry_path):
		_log("SKIP mod '%s': unloadable entry script '%s' (not found)" % [mod_id, entry_path])
		_add_report(mod_id, "skipped", "unloadable entry script", folder)
		return
	var script: Resource = ResourceLoader.load(entry_path)
	if script == null or not (script is Script):
		_log("SKIP mod '%s': unloadable entry script '%s'" % [mod_id, entry_path])
		_add_report(mod_id, "skipped", "unloadable entry script", folder)
		return

	# 4. Content resources: load by path, auto-register by class + stable id.
	for content in manifest.get("content", []):
		var content_path: String = _resolve_path(str(content), folder)
		if not ResourceLoader.exists(content_path):
			_log("WARN mod '%s': content '%s' not found; skipping resource" % [mod_id, content_path])
			continue
		var resource: Resource = ResourceLoader.load(content_path)
		if resource == null:
			_log("WARN mod '%s': could not load content '%s'; skipping resource" % [mod_id, content_path])
			continue
		var type: String = _type_of(resource)
		if type.is_empty():
			_log("WARN mod '%s': unsupported content type '%s' (%s); skipping resource" % [mod_id, resource.get_class(), content_path])
			continue
		register_resource(type, resource, mod_id)

	# 5. Entry hook: instantiate and call register(loader) for custom setup.
	#    v1 convention is `extends RefCounted`; Nodes are freed after the call.
	var instance: Object = (script as Script).new()
	if instance == null:
		_log("SKIP mod '%s': could not instantiate entry script '%s'" % [mod_id, entry_path])
		_add_report(mod_id, "skipped", "entry script could not be instantiated", folder)
		return
	if instance.has_method("register"):
		instance.call("register", self)
	if instance is Node:
		(instance as Node).free()

	_loaded_mods.append(mod_id)
	_add_report(mod_id, "loaded", "", folder)
	_log("Loaded mod '%s' (%s v%s) from '%s'" % [mod_id, str(manifest["name"]), str(manifest["version"]), folder])


## --- Helpers ---------------------------------------------------------------

## Map a resource instance to its registry bucket, or "" when unsupported.
func _type_of(resource: Resource) -> String:
	if resource is CharacterTemplate:
		return TYPE_CHARACTER
	if resource is Trait:
		return TYPE_TRAIT
	if resource is Item:
		return TYPE_ITEM
	if resource is Map:
		return TYPE_MAP
	if resource is DialogueTopic:
		return TYPE_DIALOGUE
	return ""


## Resolve an absolute res://user:// path as-is; otherwise relative to `folder`.
func _resolve_path(path: String, folder: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	return _join(folder, path)


func _join(base: String, child: String) -> String:
	if base.is_empty():
		return child
	if base.ends_with("/"):
		return base + child
	return base + "/" + child


func _read_json(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_log("WARN: cannot read '%s' (error %d)" % [path, FileAccess.get_open_error()])
		return null
	var text: String = file.get_as_text()
	file.close()
	return JSON.parse_string(text)


## Add a diagnostic entry. `folder` disambiguates entries that share a mod id
## (e.g. a duplicate-id skip and the surviving mod's load).
func _add_report(mod: String, status: String, reason: String, folder: String = "") -> void:
	_last_report.append({"mod": mod, "status": status, "reason": reason, "folder": folder})


func _resource_count() -> int:
	var total: int = 0
	for bucket in _registries.values():
		total += (bucket as Dictionary).size()
	return total


func _log(message: String) -> void:
	print("[ModLoader] " + message)
