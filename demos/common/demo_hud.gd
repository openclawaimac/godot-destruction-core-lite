class_name DemoHud
extends Control
## Styled demo HUD: a title plate (icon, pixel-font title, edition badge,
## subtitle), a plate of stat chips (icon, value, label) and a key-cap hint
## bar. Everything is drawn from DemoUIArt (9-slice plates, icons) and
## DemoPixelFont; nothing else. Values that change flash briefly.

var font: DemoPixelFont
var art: DemoUIArt
var style := &"pro"
var title := ""
var subtitle := ""
var badge := ""
var title_icon := &"star"
## [{icon, value, label, tint}] (tint colours the value; icons keep their art).
var stats: Array = []
## [[keys, action], ...]; keys separated by spaces each get their own cap.
var keys: Array = []
var margin := 6

var _flash: Dictionary = {}  # stat index -> frames left
var _frame := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(p_font: DemoPixelFont, p_art: DemoUIArt, p_style: StringName) -> void:
	font = p_font
	art = p_art
	style = p_style


func set_stat(i: int, value: String) -> void:
	if i < 0 or i >= stats.size():
		return
	var s: Dictionary = stats[i]
	if String(s.get("value", "")) != value:
		if String(s.get("value", "")) != "":
			_flash[i] = 10
		s["value"] = value
		queue_redraw()


func _process(_delta: float) -> void:
	_frame += 1
	if not _flash.is_empty():
		for k: int in _flash.keys():
			_flash[k] = int(_flash[k]) - 1
			if int(_flash[k]) <= 0:
				_flash.erase(k)
		queue_redraw()


## 9-slice draw of an atlas plate.
func plate(kind: StringName, r: Rect2, mod := Color.WHITE) -> void:
	var name := kind if kind == &"key" or kind == &"bubble" else StringName(String(kind) + "_" + String(style))
	nine(self, art, name, int(DemoUIArt.MARGINS[kind]), r, mod)


static func nine(ci: CanvasItem, a: DemoUIArt, name: StringName, m: int, r: Rect2, mod := Color.WHITE) -> void:
	var src: Rect2 = a.region(name)
	var tex := a.texture
	var xs := [0.0, float(m), src.size.x - m, src.size.x]
	var ys := [0.0, float(m), src.size.y - m, src.size.y]
	var dx := [r.position.x, r.position.x + m, r.end.x - m, r.end.x]
	var dy := [r.position.y, r.position.y + m, r.end.y - m, r.end.y]
	for j in 3:
		for i in 3:
			var s := Rect2(src.position + Vector2(xs[i], ys[j]), Vector2(xs[i + 1] - xs[i], ys[j + 1] - ys[j]))
			var d := Rect2(Vector2(dx[i], dy[j]), Vector2(dx[i + 1] - dx[i], dy[j + 1] - dy[j]))
			if d.size.x > 0.0 and d.size.y > 0.0:
				ci.draw_texture_rect_region(tex, d, s, mod)


func icon(n: StringName, at: Vector2, scale := 2.0) -> void:
	draw_texture_rect_region(art.texture, Rect2(at.round(), Vector2(11, 11) * scale), art.region(StringName("icon_" + n)))


func _draw() -> void:
	if font == null or art == null:
		return
	var st: Dictionary = DemoUIArt.STYLES[style]
	var vw := get_viewport_rect().size.x
	var vh := get_viewport_rect().size.y
	# Title plate.
	var tw := font.measure(title) * 2
	var bw := font.measure(badge) + 10 if badge != "" else 0
	var sw := font.measure(subtitle)
	var inner := maxf(tw + (bw + 6 if bw > 0 else 0), sw)
	var tr := Rect2(margin, margin, 12 + 22 + 8 + inner + 12, 40)
	plate(&"panel", tr)
	icon(title_icon, tr.position + Vector2(11, 8))
	var tx := tr.position.x + 11 + 22 + 8
	font.draw(self, Vector2(tx, tr.position.y + 9), title, 2.0, st["trim_hi"], DemoUIArt.INK, st["trim"])
	if bw > 0:
		var br := Rect2(tx + tw + 6, tr.position.y + 9, bw, 13)
		plate(&"badge", br)
		font.draw(self, br.position + Vector2(5, 3), badge, 1.0, DemoUIArt.INK, Color(0, 0, 0, 0))
	font.draw(self, Vector2(tx, tr.position.y + 27), subtitle, 1.0, Color("c9d6ea"), Color(0, 0, 0, 0))
	# Stat plate, right-aligned.
	if not stats.is_empty():
		var widths: Array[float] = []
		var total := 0.0
		for s: Dictionary in stats:
			var w := 6.0 + 22.0 + 5.0 + maxf(font.measure(String(s.get("value", "0"))) * 2.0, font.measure(String(s.get("label", "")))) + 7.0
			widths.append(w)
			total += w + 4.0
		var sr := Rect2(vw - margin - (total - 4.0 + 16.0), margin, total - 4.0 + 16.0, 40)
		plate(&"panel", sr)
		var x := sr.position.x + 8.0
		for i in stats.size():
			var s: Dictionary = stats[i]
			var cr := Rect2(x, sr.position.y + 6, widths[i], 28)
			var flash := int(_flash.get(i, 0))
			plate(&"chip", cr, Color(1.6, 1.4, 1.1) if flash > 6 else Color.WHITE)
			icon(s.get("icon", &"star"), cr.position + Vector2(4, 3))
			var tint: Color = s.get("tint", Color.WHITE)
			if flash > 0:
				tint = tint.lerp(st["trim_hi"], 0.7)
			font.draw(self, cr.position + Vector2(6 + 22 + 3, 3 - (1 if flash > 6 else 0)), String(s.get("value", "")), 2.0, tint, DemoUIArt.INK)
			font.draw(self, cr.position + Vector2(6 + 22 + 3, 19), String(s.get("label", "")), 1.0, Color("8f9bb3"), Color(0, 0, 0, 0))
			x += widths[i] + 4.0
	# Key-cap hint bar, centred at the bottom.
	if not keys.is_empty():
		var parts: Array = []
		var w := 0.0
		for k: Array in keys:
			var caps: PackedStringArray = String(k[0]).split(" ")
			for c in caps:
				w += font.measure(c) + 7.0 + 2.0
			w += 3.0 + font.measure(String(k[1])) + 12.0
			parts.append([caps, String(k[1])])
		w -= 12.0
		var br := Rect2(roundf((vw - w - 20.0) / 2.0), vh - margin - 25.0, w + 20.0, 25.0)
		plate(&"panel", br)
		var x := br.position.x + 10.0
		for p: Array in parts:
			for c: String in p[0]:
				var kw := font.measure(c) + 7.0
				plate(&"key", Rect2(x, br.position.y + 6, kw, 13))
				font.draw(self, Vector2(x + 4, br.position.y + 8), c, 1.0, DemoUIArt.INK, Color(0, 0, 0, 0))
				x += kw + 2.0
			x += 3.0
			font.draw(self, Vector2(x, br.position.y + 9), String(p[1]), 1.0, Color("e9e3d2"), DemoUIArt.INK)
			x += font.measure(String(p[1])) + 12.0
