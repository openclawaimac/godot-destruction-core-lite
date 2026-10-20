extends DKTest
## Lite must never depend on Pro: no Pro paths or class names in Lite addon
## files (recursively, so future Lite subfolders are covered) or in the Lite
## test suite and its shared helpers (they ship/run without Pro).

const LITE := "res://addons/godot_destruction_core/lite"
const PRO := "res://addons/godot_destruction_core/pro"
const LITE_TESTS := "res://tests/lite"
const SHARED_TEST_FILES := ["res://tests/dk_test.gd", "res://tests/dk_fixtures.gd"]


## Pro class names, read from the Pro folder when present. The fallback list
## keeps the check meaningful in a Lite-only checkout (Pro folder deleted).
func _pro_class_names() -> PackedStringArray:
	var out := PackedStringArray(["DKChainReactor"])
	for path in _gd_files(PRO):
		var text := FileAccess.get_file_as_string(path)
		for line in text.split("\n"):
			if line.begins_with("class_name "):
				var n := line.trim_prefix("class_name ").strip_edges()
				if not out.has(n):
					out.append(n)
	return out


func _gd_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir + "/" + d))
	return out


func _check(files: PackedStringArray, names: PackedStringArray) -> void:
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for n in names:
			ok(not text.contains(n), "%s must not mention %s" % [path, n])


func test_lite_files_do_not_reference_pro() -> void:
	var names := _pro_class_names()
	names.append("godot_destruction_core/pro")
	var files := _gd_files(LITE)
	ok(files.size() > 0, "lite has files")
	_check(files, names)


func test_lite_tests_do_not_reference_pro() -> void:
	var names := _pro_class_names()
	names.append("godot_destruction_core/pro")
	var files := PackedStringArray()
	for path in _gd_files(LITE_TESTS):
		if path.get_file() != "test_layering.gd":  # this file names Pro on purpose
			files.append(path)
	files.append_array(PackedStringArray(SHARED_TEST_FILES))
	ok(files.size() > 2, "lite tests found")
	_check(files, names)


func test_lite_demo_does_not_reference_pro() -> void:
	var names := _pro_class_names()
	names.append("godot_destruction_core/pro")
	var files := _gd_files("res://demos/lite_collapse")
	ok(files.size() > 0, "lite demo found")
	_check(files, names)
