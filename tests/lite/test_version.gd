extends DKTest
## One version everywhere: plugin.cfg, DKWorld.VERSION, README and CHANGELOG.


func test_version_is_consistent() -> void:
	var cfg := ConfigFile.new()
	eq(cfg.load("res://addons/godot_destruction_core/plugin.cfg"), OK, "plugin.cfg loads")
	var v := String(cfg.get_value("plugin", "version", ""))
	eq(v, "0.2.1", "plugin.cfg version")
	eq(DKWorld.VERSION, v, "DKWorld.VERSION matches plugin.cfg")
	ok(FileAccess.get_file_as_string("res://README.md").contains("Version %s" % v), "README states the version")
	var log := FileAccess.get_file_as_string("res://CHANGELOG.md")
	var first := log.find("\n## ")
	ok(first >= 0 and log.substr(first + 4, v.length()) == v, "CHANGELOG's newest entry is %s" % v)
	var script: Script = load("res://addons/godot_destruction_core/" + String(cfg.get_value("plugin", "script", "")))
	ok(script != null, "plugin script exists")
