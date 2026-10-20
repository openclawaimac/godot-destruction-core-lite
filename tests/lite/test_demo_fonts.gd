extends DKTest
## No plain / engine-default-font text anywhere in the demos: every string on
## screen goes through the kit's own pixel font (DemoPixelFont). Scans the
## demo sources (and Pro demos when present) for engine text paths, checks
## the speech bubbles use the callout style, and walks the live Lite scene
## for text Controls.

const BANNED := ["draw_string(", "draw_multiline_string(", "draw_char(", "fallback_font",
	"get_theme_default_font", "get_theme_font(", "SystemFont", "FontFile", "FontVariation",
	"Label.new", "RichTextLabel", "Button.new", "LineEdit", "TextEdit", "type=\"Label\"",
	"type=\"Button\"", "type=\"RichTextLabel\"", "ThemeDB"]
const TEXT_CONTROLS := ["Label", "RichTextLabel", "Button", "LineEdit", "TextEdit", "Label3D",
	"OptionButton", "CheckBox", "MenuButton", "LinkButton", "TooltipPanel"]


static func _files(dir: String, out: Array[String]) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for sub in da.get_directories():
		_files(dir.path_join(sub), out)


func test_demo_sources_have_no_engine_text_paths() -> void:
	var files: Array[String] = []
	_files("res://demos", files)
	ok(files.size() >= 6, "scanned %d demo files" % files.size())
	for path in files:
		var src := FileAccess.get_file_as_string(path)
		for b: String in BANNED:
			ok(not src.contains(b), "%s has no '%s'" % [path.get_file(), b])


func test_speech_bubbles_use_callout_style() -> void:
	var src := FileAccess.get_file_as_string("res://demos/common/demo_callouts.gd")
	var i := src.find("static func draw_bubble(")
	ok(i >= 0, "draw_bubble exists")
	var body := src.substr(i)
	ok(not body.contains("DemoHud.nine("), "no plain white plate behind the bubble text")
	ok(body.contains("pop_scale(age)"), "bubble pops in like the callouts")
	ok(body.contains("DemoUIArt.INK") and body.contains(", true)"), "ink outline and shadow")


func test_lite_scene_has_no_text_controls() -> void:
	var d: Node = load("res://demos/lite_collapse/demo.tscn").instantiate()
	d.manual = true
	tree().root.add_child(d)
	track(d)
	for _i in 120:
		d.step_tick()
	eq(_text_nodes(d), [], "no engine text nodes in the Lite demo")


static func _text_nodes(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c.get_class() in TEXT_CONTROLS:
			out.append(str(c.get_path()))
		out.append_array(_text_nodes(c))
	return out
