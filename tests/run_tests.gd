extends SceneTree
## Headless test runner.
##   godot --headless --path . -s res://tests/run_tests.gd [-- --lite-only] [-- --filter=x]
## Runs every test_*() in tests/lite/*.gd and tests/pro/*.gd (pro is skipped
## when the Pro addon folder is absent or --lite-only is given). Exit code 0 = green.

const PRO_ADDON := "res://addons/godot_destruction_core/pro"


var _started := false


## Tests run on the first frame (not in _initialize) so nodes added to the
## tree get _ready() before a test uses them (demo scene tests).
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	var lite_only := false
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a == "--lite-only":
			lite_only = true
		elif a.begins_with("--filter="):
			filter = a.trim_prefix("--filter=")
	var dirs := ["res://tests/lite"]
	if not lite_only and DirAccess.dir_exists_absolute(PRO_ADDON):
		dirs.append("res://tests/pro")
	var tests := 0
	var asserts := 0
	var fails: Array[String] = []
	var t0 := Time.get_ticks_msec()
	print("Godot Destruction Core tests (%s)%s" % [Engine.get_version_info()["string"], " [lite only]" if dirs.size() == 1 else ""])
	for dir_path in dirs:
		var files := Array(DirAccess.get_files_at(dir_path))
		files.sort()
		for f: String in files:
			if not (f.begins_with("test_") and f.ends_with(".gd")):
				continue
			var path: String = dir_path + "/" + f
			if filter != "" and not path.contains(filter):
				continue
			var script: GDScript = load(path)
			if script == null or not script.can_instantiate():
				fails.append("could not load " + path)
				continue
			var methods: Array[String] = []
			for m in script.get_script_method_list():
				var n: String = m["name"]
				if n.begins_with("test_") and not methods.has(n):
					methods.append(n)
			methods.sort()
			print("-- %s (%d)" % [path.trim_prefix("res://tests/"), methods.size()])
			for mname in methods:
				var inst: DKTest = script.new()
				inst.current = mname
				inst.before_each()
				inst.call(mname)
				inst.after_each()
				inst._cleanup()
				tests += 1
				asserts += inst.assert_count
				print("  %s %s" % ["ok  " if inst.failures.is_empty() else "FAIL", mname])
				fails.append_array(inst.failures)
	print("== %d tests, %d asserts, %d failures (%d ms) ==" % [tests, asserts, fails.size(), Time.get_ticks_msec() - t0])
	for f in fails:
		printerr("  " + f)
	quit(0 if fails.is_empty() and tests > 0 else 1)
