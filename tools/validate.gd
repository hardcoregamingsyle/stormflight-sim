extends SceneTree
## Headless validation: force-load every script in the project and report
## parse/compile failures. Run: godot --headless --script tools/validate.gd

func _init() -> void:
	var failures := 0
	var scripts := _find_scripts("res://")
	print("Validating %d scripts..." % scripts.size())
	for path in scripts:
		var s := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_REPLACE)
		if s == null:
			printerr("LOAD FAILED: %s" % path)
			failures += 1
			continue
		var scr := s as GDScript
		if scr and not scr.can_instantiate():
			# Autoload-extending scripts can't instantiate standalone; reload to check compile
			var err := scr.reload()
			if err != OK:
				printerr("COMPILE FAILED: %s (error %d)" % [path, err])
				failures += 1
	print("RESULT: %d failures out of %d scripts" % [failures, scripts.size()])
	quit(1 if failures > 0 else 0)

func _find_scripts(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := dir_path.path_join(f)
		if dir.current_is_dir():
			if not f.begins_with(".") and f != "docs" and f != "builds":
				out.append_array(_find_scripts(full))
		elif f.ends_with(".gd"):
			out.append(full)
		f = dir.get_next()
	dir.list_dir_end()
	return out
