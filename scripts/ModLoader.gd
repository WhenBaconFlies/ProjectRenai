## ModLoader
##
## Global singleton (autoload) that provides the v1 modding seam:
##   1. Discover mod folders under res://mods/ AND user://mods/ (or explicit
##      roots, for tests), with bundled content scanned first.
##   2. Validate each mod's mod.json manifest.
##   3. Resolve dependencies in topological order, rejecting cycles.
##   4. Load each mod's content resources into typed ID -> Resource registries.
##   5. Honour enable/disable flags from SettingsManager and skip invalid mods
##      with a log, never crash. The v1 res:// .disabled marker is no longer a
##      disable source (ticket 029); player toggles live in user://settings.cfg.
##
## The registries live here (no separate autoload): later tickets (NPC spawning,
## dialogue filtering, save linkage) look resources up by stable ID through
## get_resource()/get_all(). v1 is add-only — duplicate IDs are never overridden.
##
## Authored base characters under res://resources/characters/ are registered into
## the `character` bucket first (ticket 012), so NPC spawning has a single
## resolution path for both base and modded templates. Ticket 021 adds the
## `greeting` and `response` buckets for the two new dialogue resource types;
## they follow the same add-only rules as `dialogue`. Ticket 022 adds authored
## traits (res://resources/traits/) to the existing `trait` bucket so every
## piece of content, not just dialogue, loads through one base-registration path.
##
## Ticket 029 adds a second scan root. The add-only rule still applies across
## both roots, so a duplicate id in user://mods/ is skipped rather than allowed
## to override a bundled mod. Disabled mods are filtered out before dependency
## resolution so they neither satisfy dependencies nor take part in cycles.
extends Node

## --- Registry bucket names -------------------------------------------------
const TYPE_CHARACTER: String = "character"
const TYPE_TRAIT: String = "trait"
const TYPE_ITEM: String = "item"
const TYPE_MAP: String = "map"
const TYPE_DIALOGUE: String = "dialogue"
const TYPE_GREETING: String = "greeting"
const TYPE_RESPONSE: String = "response"

## --- Filesystem conventions ------------------------------------------------
const DEFAULT_MODS_ROOT: String = "res://mods/"
## User-writable root for mods installed without editing the game directory. In
## an exported build res:// is read-only, so this is where the Mods Menu's mods
## live and where enable/disable flags are meaningful.
const USER_MODS_ROOT: String = "user://mods/"
## Scan order is significant: bundled content registers first, so add-only
## conflict resolution can never let a user mod silently override a bundled id.
const DEFAULT_MODS_ROOTS: Array = [DEFAULT_MODS_ROOT, USER_MODS_ROOT]
const MANIFEST_FILE: String = "mod.json"

## Authored (non-mod) character templates loaded directly from res://. They are
## registered before mod content so v1's add-only rule lets mods add new ids but
## never silently override a base id.
const BASE_CHARACTERS_DIR: String = "res://resources/characters/"

## Authored traits (ticket 022). Registered before mod content so mods can add
## new trait ids but never silently override a base trait. Character templates
## continue to reference these files directly via ext_resource.
const BASE_TRAITS_DIR: String = "res://resources/traits/"

## Authored dialogue topics (ticket 014). Registered alongside base characters
## so every eligible topic — base or mod — comes from the same registry.
const BASE_DIALOGUES_DIR: String = "res://resources/dialogue/"

## Authored greetings and responses (ticket 021). Kept in their own folders so
## the three dialogue resource types stay distinguishable in the editor, while
## each still flows through the same add-only registry as base dialogue topics.
const BASE_GREETINGS_DIR: String = "res://resources/dialogue/greetings/"
const BASE_RESPONSES_DIR: String = "res://resources/dialogue/responses/"

const BASE_OWNER: String = "base"

## Add-only conflicts are resolved by source priority, not by incidental load
## order: base content outranks every root, earlier roots outrank later roots,
## and ad-hoc register_resource() calls from outside a load rank last. Lower
## numbers win. This keeps bundled content authoritative even when a dependency
## forces a bundled mod to load after an independent user mod.
const BASE_PRIORITY: int = -1
const EXTERNAL_PRIORITY: int = 999

## bucket name -> { stable id (String) -> Resource }
var _registries: Dictionary = {}

## "bucket:id" -> mod id (String). Tracks ownership for diagnostics.
var _owners: Dictionary = {}

## "bucket:id" -> source priority (int). Used to settle cross-root conflicts.
var _priorities: Dictionary = {}

## Priority applied to registrations made during the current loading step.
var _current_priority: int = EXTERNAL_PRIORITY

## Mod ids that loaded successfully, in load (topological) order.
var _loaded_mods: Array[String] = []

## Diagnostics for the most recent load_mods() call.
## Each entry: { "mod": String, "status": "loaded"|"skipped", "reason": String }
var _last_report: Array = []

## Ticket 031: read-only snapshot of every discovered mod (valid or invalid),
## built from discovery + validation + the load report. The Mods Menu consumes
## this instead of parsing mod.json a second time.
var _installed_mods: Array = []

## Discovery-stage skips (missing/invalid manifest, duplicate id) collected
## while scanning the roots, so they can appear in _installed_mods too.
var _discovery_skips: Array = []

## Root paths scanned by the most recent load_mods() call, in scan order.
var _mods_roots: Array[String] = [DEFAULT_MODS_ROOT, USER_MODS_ROOT]

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
	var key: String = type + ":" + id
	if bucket.has(id):
		var existing_priority: int = int(_priorities.get(key, EXTERNAL_PRIORITY))
		if _current_priority >= existing_priority:
			_log("WARN: add-only conflict for '%s:%s' (mod '%s'): already owned by mod '%s'; skipping" % [type, id, mod_id, str(_owners.get(key, "unknown"))])
			return false
		# An earlier root (or base content) registered late because of dependency
		# order. Keep its resource and reject the later-root claim instead.
		_log("WARN: add-only conflict for '%s:%s' (mod '%s'): later/higher-index source rejected in favour of mod '%s'" % [type, id, mod_id, str(_owners.get(key, "unknown"))])
		bucket[id] = resource
		_priorities[key] = _current_priority
		_owners[key] = mod_id
		return true

	bucket[id] = resource
	_priorities[key] = _current_priority
	_owners[key] = mod_id
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


## Ticket 031: read-only snapshot of every discovered mod, in scan order. One
## entry per mod: { id, name, version, author, dependencies, author_enabled,
## settings_enabled, enabled, status, reason, root, folder }. Invalid mods are
## included with blank metadata and their diagnostic reason. Deep copy so a UI
## consumer can never mutate the loader's view of the install.
func get_installed_mods() -> Array:
	return _installed_mods.duplicate(true)


## First root used by the most recent scan. Kept for v1 callers; new code should
## use get_mods_roots() because the default scan now covers two roots.
func get_mods_root() -> String:
	return _mods_roots[0] if not _mods_roots.is_empty() else ""


## All roots used by the most recent scan, in scan order (copy).
func get_mods_roots() -> Array[String]:
	return _mods_roots.duplicate()


## --- Loading pipeline ------------------------------------------------------

## (Re)load mods. With no argument both DEFAULT_MODS_ROOTS are scanned (the v2
## default). Passing a single path keeps the v1 test seam: only that one root is
## scanned, so a harness can point ModLoader at a synthetic user:// tree.
func load_mods(root_path: String = "") -> void:
	if root_path.is_empty():
		load_mods_from_roots(DEFAULT_MODS_ROOTS)
	else:
		load_mods_from_roots([root_path])


## (Re)load all mods from `root_paths`, in the given order. Clears every registry
## first so the function is idempotent and testable.
func load_mods_from_roots(root_paths: Array) -> void:
	# An entry hook is handed `self`; without this guard it could call
	# load_mods() again and clear registries while the outer load is running.
	if _is_loading:
		_log("WARN: load_mods() called while already loading; ignoring re-entrant request")
		return
	_is_loading = true
	_reset_registries()
	_register_base_content()
	_mods_roots.clear()
	for path in root_paths:
		_mods_roots.append(str(path))

	# Discovery merges every root into one id -> manifest map. A duplicate id in
	# a later root is rejected here, preserving the bundled root's mod.
	var mods: Dictionary = {}
	for root_index in _mods_roots.size():
		_discover_mods(_mods_roots[root_index], mods, root_index)

	# Player toggles live in SettingsManager. Filtering before the sort keeps a
	# disabled mod out of cycles and out of dependency satisfaction entirely.
	var enabled_mods: Dictionary = _enabled_mods(mods)
	var resolution: Dictionary = _resolve_order(enabled_mods)
	var order: Array = resolution["order"]

	for mod_id in order:
		_load_one_mod(str(mod_id), enabled_mods)

	_build_installed_mods(mods)
	_is_loading = false
	_log("Loaded %d mod(s); %d resource(s) registered from %d root(s)." % [
		_loaded_mods.size(), _resource_count(), _mods_roots.size()
	])


func _reset_registries() -> void:
	_registries = {
		TYPE_CHARACTER: {},
		TYPE_TRAIT: {},
		TYPE_ITEM: {},
		TYPE_MAP: {},
		TYPE_DIALOGUE: {},
		TYPE_GREETING: {},
		TYPE_RESPONSE: {},
	}
	_owners.clear()
	_priorities.clear()
	_current_priority = EXTERNAL_PRIORITY
	_loaded_mods.clear()
	_last_report.clear()
	_installed_mods.clear()
	_discovery_skips.clear()


## Register authored base resources (characters, traits, dialogue topics,
## greetings, responses) into their registries. Runs on every load_mods() (after
## the clear) so re-scans restore base content. A missing directory is a soft
## warning, never a crash — gameplay can still run from mod content alone.
func _register_base_content() -> void:
	# Base content is authoritative: even a bundled mod must not shadow it.
	_current_priority = BASE_PRIORITY
	for path in _base_resource_paths(BASE_CHARACTERS_DIR):
		var resource: Resource = ResourceLoader.load(path)
		if resource is CharacterTemplate:
			register_resource(TYPE_CHARACTER, resource, BASE_OWNER)
		else:
			_log("WARN: base content '%s' is not a CharacterTemplate; skipping" % path)

	for path in _base_resource_paths(BASE_TRAITS_DIR):
		var resource: Resource = ResourceLoader.load(path)
		if resource is Trait:
			register_resource(TYPE_TRAIT, resource, BASE_OWNER)
		else:
			_log("WARN: base content '%s' is not a Trait; skipping" % path)

	for path in _base_resource_paths(BASE_DIALOGUES_DIR):
		var resource: Resource = ResourceLoader.load(path)
		if resource is DialogueTopic:
			register_resource(TYPE_DIALOGUE, resource, BASE_OWNER)
		else:
			_log("WARN: base content '%s' is not a DialogueTopic; skipping" % path)

	for path in _base_resource_paths(BASE_GREETINGS_DIR):
		var resource: Resource = ResourceLoader.load(path)
		if resource is DialogueGreeting:
			register_resource(TYPE_GREETING, resource, BASE_OWNER)
		else:
			_log("WARN: base content '%s' is not a DialogueGreeting; skipping" % path)

	for path in _base_resource_paths(BASE_RESPONSES_DIR):
		var resource: Resource = ResourceLoader.load(path)
		if resource is DialogueResponse:
			register_resource(TYPE_RESPONSE, resource, BASE_OWNER)
		else:
			_log("WARN: base content '%s' is not a DialogueResponse; skipping" % path)
	_current_priority = EXTERNAL_PRIORITY


## Resource file paths in one authored base directory, sorted for stable order.
func _base_resource_paths(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		_log("WARN: cannot open base content directory '%s' (error %d)" % [dir_path, DirAccess.get_open_error()])
		return paths

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.ends_with(".tres") or entry.ends_with(".res"):
			paths.append(_join(dir_path, entry))
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


## Scan `root_path` for direct subfolders that are mod candidates and merge the
## validated manifests into `mods`. Scan order is the caller's responsibility:
## an id already present is skipped, so the earlier (bundled) root wins.
func _discover_mods(root_path: String, mods: Dictionary, root_index: int = 0) -> void:
	if not DirAccess.dir_exists_absolute(root_path):
		if root_path.begins_with("user://"):
			# A fresh install has no user mods yet. Create the folder so there is
			# an obvious install location, and do not warn about an empty root.
			var made: int = DirAccess.make_dir_recursive_absolute(root_path)
			if made != OK:
				_log("WARN: cannot create mods directory '%s' (error %d); skipping this root" % [root_path, made])
				return
		else:
			# A missing bundled root is a packaging problem, not an empty install.
			_log("WARN: cannot open mods directory '%s'; skipping this root" % root_path)
			return

	var dir: DirAccess = DirAccess.open(root_path)
	if dir == null:
		# Genuine open failures (permissions, etc.) still get a diagnostic.
		_log("WARN: cannot open mods directory '%s' (error %d); skipping this root" % [root_path, DirAccess.get_open_error()])
		return

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != ".." and dir.current_is_dir():
			var folder: String = _join(root_path, entry)
			var manifest_path: String = _join(folder, MANIFEST_FILE)
			if not FileAccess.file_exists(manifest_path):
				_log("SKIP mod folder '%s': missing %s" % [entry, MANIFEST_FILE])
				_add_report(entry, "skipped", "missing %s" % MANIFEST_FILE, folder)
				_note_discovery_skip(entry, folder, "missing %s" % MANIFEST_FILE, root_index, {})
			else:
				var parsed: Variant = _read_json(manifest_path)
				var validation: Dictionary = _validate_manifest(parsed, entry)
				if not bool(validation.get("ok", false)):
					# Validation reasons already name the folder.
					var reason: String = str(validation.get("reason", "invalid manifest"))
					_log("SKIP: %s" % reason)
					_add_report(entry, "skipped", reason, folder)
					_note_discovery_skip(entry, folder, reason, root_index, {})
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
						_note_discovery_skip(mod_id, folder, "duplicate mod id", root_index, manifest)
					else:
						manifest["_folder_path"] = folder
						manifest["_root_index"] = root_index
						mods[mod_id] = manifest
		entry = dir.get_next()
	dir.list_dir_end()


## Return only the mods the player/author has enabled. Disabled mods get a
## report entry here so the diagnostics still explain why they did not load.
func _enabled_mods(mods: Dictionary) -> Dictionary:
	var enabled: Dictionary = {}
	for id in mods.keys():
		var mod_id: String = str(id)
		var manifest: Dictionary = mods[id]
		var reason: String = ""
		if manifest.has("enabled") and manifest["enabled"] == false:
			reason = "disabled (manifest enabled=false)"
		elif not _mod_enabled_from_settings(mod_id):
			reason = "disabled (settings flag)"
		if reason.is_empty():
			enabled[mod_id] = manifest
		else:
			_log("SKIP mod '%s': %s" % [mod_id, reason])
			_add_report(mod_id, "skipped", reason, str(manifest.get("_folder_path", "")))
	return enabled


## Player toggle source. get_node_or_null keeps a missing or not-yet-ready
## SettingsManager autoload a soft "enabled" instead of a hard failure; project
## autoload order puts SettingsManager before ModLoader on the normal path.
func _mod_enabled_from_settings(mod_id: String) -> bool:
	var settings: Node = get_node_or_null("/root/SettingsManager")
	if settings == null or not settings.has_method("get_mod_enabled"):
		return true
	return bool(settings.call("get_mod_enabled", mod_id))


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

	# 1. Enable/disable was already applied by _enabled_mods() before the sort.
	#    The v1 .disabled marker is deliberately not consulted (ticket 029).

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
	#    The root index travels with the manifest so conflicts are settled by
	#    source priority rather than by this topological load position.
	_current_priority = int(manifest.get("_root_index", EXTERNAL_PRIORITY))
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
		_current_priority = EXTERNAL_PRIORITY
		_log("SKIP mod '%s': could not instantiate entry script '%s'" % [mod_id, entry_path])
		_add_report(mod_id, "skipped", "entry script could not be instantiated", folder)
		return
	if instance.has_method("register"):
		instance.call("register", self)
	if instance is Node:
		(instance as Node).free()
	_current_priority = EXTERNAL_PRIORITY

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
	if resource is DialogueGreeting:
		return TYPE_GREETING
	if resource is DialogueResponse:
		return TYPE_RESPONSE
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


## Record a discovery-stage skip so the Mods Menu can show it alongside loaded
## mods. `manifest` is empty when validation never produced a usable one.
func _note_discovery_skip(id: String, folder: String, reason: String,
		root_index: int, manifest: Dictionary) -> void:
	var deps: Array = []
	var author_enabled: bool = true
	if not manifest.is_empty():
		deps = (manifest.get("dependencies", []) as Array).duplicate()
		author_enabled = manifest.get("enabled", true) != false
	var settings_enabled: bool = _mod_enabled_from_settings(id)
	_discovery_skips.append({
		"id": id,
		"name": str(manifest.get("name", "")),
		"version": str(manifest.get("version", "")),
		"author": str(manifest.get("author", "")),
		"dependencies": deps,
		"author_enabled": author_enabled,
		"settings_enabled": settings_enabled,
		"enabled": false,
		"togglable": false,
		"status": "skipped",
		"reason": reason,
		"root": _root_at(root_index),
		"folder": folder,
	})


## Build the ticket-031 snapshot from the last load's manifests + diagnostics.
func _build_installed_mods(mods: Dictionary) -> void:
	_installed_mods.clear()
	for id in mods.keys():
		var mod_id: String = str(id)
		var manifest: Dictionary = mods[id]
		var folder: String = str(manifest.get("_folder_path", ""))
		var report: Dictionary = _report_entry(mod_id, folder)
		var author_enabled: bool = manifest.get("enabled", true) != false
		var settings_enabled: bool = _mod_enabled_from_settings(mod_id)
		_installed_mods.append({
			"id": mod_id,
			"name": str(manifest.get("name", "")),
			"version": str(manifest.get("version", "")),
			"author": str(manifest.get("author", "")),
			"dependencies": (manifest.get("dependencies", []) as Array).duplicate(),
			"author_enabled": author_enabled,
			"settings_enabled": settings_enabled,
			"enabled": author_enabled and settings_enabled,
			"togglable": author_enabled,
			"status": str(report.get("status", "skipped")),
			"reason": str(report.get("reason", "")),
			"root": _root_at(int(manifest.get("_root_index", 0))),
			"folder": folder,
		})
	for skip_variant in _discovery_skips:
		_installed_mods.append((skip_variant as Dictionary).duplicate(true))


## Find the load report entry for a valid mod, preferring an exact folder match.
func _report_entry(mod_id: String, folder: String) -> Dictionary:
	for entry_variant in _last_report:
		var entry: Dictionary = entry_variant
		if str(entry.get("mod", "")) == mod_id and str(entry.get("folder", "")) == folder:
			return entry
	for entry_variant in _last_report:
		var entry: Dictionary = entry_variant
		if str(entry.get("mod", "")) == mod_id:
			return entry
	return {}


func _root_at(index: int) -> String:
	if index >= 0 and index < _mods_roots.size():
		return _mods_roots[index]
	return ""


func _resource_count() -> int:
	var total: int = 0
	for bucket in _registries.values():
		total += (bucket as Dictionary).size()
	return total


func _log(message: String) -> void:
	print("[ModLoader] " + message)
