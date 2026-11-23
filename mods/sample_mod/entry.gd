extends RefCounted

## Sample mod entry point.
##
## ModLoader validates and loads this script, then calls register(loader) after
## the mod's `content` resources have been registered. This hook is for any
## mod-specific setup that cannot be expressed as a static content list.
## No custom setup is needed for the sample mod; we only log a confirmation so
## the entry hook is observably exercised in verification runs.


func register(loader) -> void:
	var character = loader.get_resource(loader.TYPE_CHARACTER, "char:mod_sample")
	if character == null:
		push_warning("[SampleMod] register(): sample character was not registered")
		return
	print("[SampleMod] register(): '%s' registered by sample_mod" % character.display_name)
