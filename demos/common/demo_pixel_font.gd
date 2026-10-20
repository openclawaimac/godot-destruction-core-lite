class_name DemoPixelFont
extends RefCounted
## Create one per demo (`DemoPixelFont.new()`) and share it.
## "Core Block": the demos' own bitmap pixel font, hand-authored glyph by
## glyph below (5x7 cell, proportional advance, 1 px spacing). Original work
## made for Godot Destruction Core, MIT like the Lite demo. No font files and
## no third-party glyphs: the atlas is built from these strings at runtime.
##
## Lower case is drawn as upper case. Text helpers draw with a 1 px pixel
## outline (pre-baked silhouettes, so the outline stays crisp at any integer
## scale) and an optional second fill colour for the lower half (a two-tone
## "comic" look for callouts).

const H := 7
const SPACING := 1
const SPACE_ADVANCE := 3

const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
	"J": ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", ".#.#.", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": [".#.", "##.", ".#.", ".#.", ".#.", ".#.", "###"],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
	".": [".", ".", ".", ".", ".", ".", "#"],
	",": ["..", "..", "..", "..", "..", ".#", "#."],
	":": [".", ".", "#", ".", ".", "#", "."],
	";": ["..", "..", ".#", "..", "..", ".#", "#."],
	"!": ["#", "#", "#", "#", "#", ".", "#"],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	"'": ["#", "#", ".", ".", ".", ".", "."],
	"\"": ["#.#", "#.#", "...", "...", "...", "...", "..."],
	"-": ["....", "....", "....", "####", "....", "....", "...."],
	"+": [".....", ".....", "..#..", "..#..", "#####", "..#..", "..#.."],
	"=": ["....", "....", "####", "....", "####", "....", "...."],
	"/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
	"(": [".#", "#.", "#.", "#.", "#.", "#.", ".#"],
	")": ["#.", ".#", ".#", ".#", ".#", ".#", "#."],
	"[": ["##", "#.", "#.", "#.", "#.", "#.", "##"],
	"]": ["##", ".#", ".#", ".#", ".#", ".#", "##"],
	"%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
	"#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
	"&": [".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#"],
	"*": [".....", "#.#.#", ".###.", "#####", ".###.", "#.#.#", "....."],
	"<": ["...#", "..#.", ".#..", "#...", ".#..", "..#.", "...#"],
	">": ["#...", ".#..", "..#.", "...#", "..#.", ".#..", "#..."],
	"_": ["....", "....", "....", "....", "....", "....", "####"],
	"·": [".", ".", ".", "#", ".", ".", "."],
	"x": ["...", "...", "#.#", ".#.", "#.#", "...", "..."],
	"^": [".#.", "#.#", "...", "...", "...", "...", "..."],
}

var _atlas: ImageTexture
var _outline: ImageTexture
## char -> Rect2i in the atlas (the outline atlas uses the same rect grown by 1).
var _rects: Dictionary = {}


func _init() -> void:
	ensure()


func ensure() -> void:
	if _atlas != null:
		return
	var keys: Array = GLYPHS.keys()
	var w := 0
	for k: String in keys:
		w += (GLYPHS[k][0] as String).length() + 2 + 1
	var img := Image.create(w, H + 2, false, Image.FORMAT_RGBA8)
	var out := Image.create(w, H + 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	out.fill(Color(0, 0, 0, 0))
	var x := 0
	for k: String in keys:
		var rows: Array = GLYPHS[k]
		var gw := (rows[0] as String).length()
		for y in H:
			var row: String = rows[y]
			for i in gw:
				if row[i] == "#":
					img.set_pixel(x + 1 + i, y + 1, Color.WHITE)
					for oy in range(-1, 2):
						for ox in range(-1, 2):
							out.set_pixel(x + 1 + i + ox, y + 1 + oy, Color.WHITE)
		_rects[k] = Rect2i(x + 1, 1, gw, H)
		x += gw + 3
	_atlas = ImageTexture.create_from_image(img)
	_outline = ImageTexture.create_from_image(out)


static func glyph_key(ch: String) -> String:
	if GLYPHS.has(ch):
		return ch
	var up := ch.to_upper()
	return up if GLYPHS.has(up) else ""


## Width in font pixels (multiply by the draw scale for screen pixels).
func measure(text: String) -> int:
	ensure()
	var w := 0
	for i in text.length():
		var k := glyph_key(text[i])
		if k == "":
			w += SPACE_ADVANCE + SPACING
		else:
			w += (_rects[k] as Rect2i).size.x + SPACING
	return maxi(0, w - SPACING)


## Draws `text` with its top-left at `pos` on `ci`, `scale` screen pixels per
## font pixel. `outline` alpha 0 = no outline. `fill_b` (alpha > 0) colours
## the lower half of every glyph.
func draw(ci: CanvasItem, pos: Vector2, text: String, scale: float, fill: Color,
		outline := Color("1a1423"), fill_b := Color(0, 0, 0, 0), shadow := false) -> void:
	ensure()
	var p := pos.round()
	if outline.a > 0.0:
		_pass(ci, p + (Vector2(scale, scale) if shadow else Vector2.ZERO), text, scale, outline, true)
		if shadow:
			_pass(ci, p, text, scale, outline, true)
	_pass(ci, p, text, scale, fill, false)
	if fill_b.a > 0.0:
		_pass(ci, p, text, scale, fill_b, false, 4)


func _pass(ci: CanvasItem, p: Vector2, text: String, scale: float, col: Color, outlined: bool,
		from_row := 0) -> void:
	var x := 0.0
	for i in text.length():
		var k := glyph_key(text[i])
		if k == "":
			x += (SPACE_ADVANCE + SPACING) * scale
			continue
		var r: Rect2i = _rects[k]
		if outlined:
			var src := Rect2(r.position - Vector2i.ONE, r.size + Vector2i(2, 2))
			ci.draw_texture_rect_region(_outline, Rect2(p + Vector2(x - scale, -scale), src.size * scale), src, col)
		else:
			var src := Rect2(r.position + Vector2i(0, from_row), r.size - Vector2i(0, from_row))
			ci.draw_texture_rect_region(_atlas, Rect2(p + Vector2(x, from_row * scale), src.size * scale), src, col)
		x += (r.size.x + SPACING) * scale


## The glyph atlas as an image (docs/previews).
func atlas_image() -> Image:
	ensure()
	return _atlas.get_image()
