class_name DemoUIArt
extends RefCounted
## Procedural UI art shared by the demos: 9-slice panels, stat chips, key
## caps, speech bubbles, badges and 11x11 pixel icons, all built at runtime
## from the shapes and the hand-authored icon maps below. Original work made
## for Godot Destruction Core (MIT, like the Lite demo). No image files, no
## AI art, no third-party assets.

## Accent styles: plate fill, trim, trim highlight.
const STYLES := {
	&"pro": {"plate": Color("231a2c"), "plate_hi": Color("33263f"), "plate_lo": Color("160f1c"),
		"trim": Color("e0913a"), "trim_hi": Color("ffd27a"), "trim_lo": Color("8a4a1c")},
	&"lite": {"plate": Color("16212e"), "plate_hi": Color("223246"), "plate_lo": Color("0d151f"),
		"trim": Color("3fb8a8"), "trim_hi": Color("9cf0d8"), "trim_lo": Color("1f6b66")},
}
const INK := Color("120d18")

const PAL := {
	"o": Color("1a1423"), "w": Color("ffffff"), "y": Color("ffd84a"), "Y": Color("fff1a8"),
	"r": Color("ff7b2e"), "R": Color("c23a30"), "D": Color("7a1f1f"), "b": Color("b57a40"), "B": Color("6a3f22"),
	"g": Color("a9b5c8"), "G": Color("5f6982"), "k": Color("332c36"), "K": Color("1f1a22"),
	"s": Color("f2b48a"), "S": Color("c98263"), "h": Color("5f8f3a"), "H": Color("3e6326"),
	"n": Color("c8634a"), "N": Color("7d2f2b"), "m": Color("d9c3a5"), "u": Color("6fb2ff"), "U": Color("3a6fc2"),
}

const ICONS := {
	&"fire": [
		"....oo.....",
		"...oyo.....",
		"...oyyo.o..",
		"..oyYyoorro",
		"..oyYYyoryo",
		".oryYYyyryo",
		".oryYYYyyro",
		"oryyYYYYyro",
		"orryYYYyrro",
		".orryyyyro.",
		"..oooooooo.",
	],
	&"barrel": [
		"..ooooooo..",
		".oRRRRRRRo.",
		".oBBBBBBBo.",
		".oRRRRRRRo.",
		".oRwwRwwRo.",
		".oRRwRwRRo.",
		".oRRwRwRRo.",
		".oRRRRRRRo.",
		".oBBBBBBBo.",
		".oDDDDDDDo.",
		"..ooooooo..",
	],
	&"chain": [
		"...........",
		"..oooo.....",
		".oggggo....",
		".ogoogo....",
		".oggoooooo.",
		"..ooggggggo",
		"....ooogogo",
		".....ogggo.",
		"......ooo..",
		"...........",
		"...........",
	],
	&"goon": [
		"...ooooo...",
		"..ohhhhho..",
		".ohHHHHHho.",
		"ooooooooooo",
		".ossssssso.",
		".oswosswso.",
		".ossssssso.",
		".ossssssso.",
		".osoRRRoso.",
		"..osoooso..",
		"...ooooo...",
	],
	&"wreck": [
		"ooooooooooo",
		"onnmNnnnmno",
		"ommmomomomo",
		"onmnnonmnno",
		"omomoommmoo",
		"onnoo..onno",
		"ommo....mmo",
		"onno.o..nno",
		"omo..oo.omo",
		"oo...o...oo",
		"o.........o",
	],
	&"burnt": [
		"...........",
		"......r....",
		".....ryr...",
		"...ooooooo.",
		"..okkkKkkko",
		".okKkkkkKko",
		".okkkrkkkko",
		".oKkkkkKkko",
		"..okkkkkko.",
		"...ooooooo.",
		"...........",
	],
	&"hero": [
		"...ooooo...",
		"..oRRRRRo..",
		".oRRRRRRRo.",
		".oooooooooR",
		".ossssssoRR",
		".osoossoso.",
		".ossssssso.",
		".osSssssSo.",
		"..osoooso..",
		"...osssoo..",
		"....ooo....",
	],
	&"falling": [
		"..ooooooo..",
		"..obbbbbo..",
		"..obBBBbo..",
		"..ooooooo..",
		"...........",
		"....oyo....",
		"....oyo....",
		"..oooyooo..",
		"...oyyyo...",
		"....oyo....",
		".....o.....",
	],
	&"landed": [
		"...........",
		"..o.....o..",
		".o..ooo..o.",
		"...obbbo...",
		"..obBBBbo..",
		"..ooooooo..",
		"..ogggggo..",
		".ogGGGGGgo.",
		"ogggggggggo",
		"ooooooooooo",
		"...........",
	],
	&"debris": [
		"...........",
		".oo....o...",
		"obbo..oyo..",
		".oo....o...",
		"....oo.....",
		"...ogGo..o.",
		"....oo..obo",
		".o.......o.",
		"oro..oo....",
		".o..obbo...",
		".....oo....",
	],
	&"star": [
		".....o.....",
		"....oyo....",
		"....oyo....",
		"oooooYyoooo",
		"oyyyYYYyyyo",
		".oyyYYYyyo.",
		"..oyyyyyo..",
		"..oyyoyyo..",
		".oyyo.oyyo.",
		".oyo...oyo.",
		".oo.....oo.",
	],
	&"dot": [
		"...........",
		"...ooooo...",
		"..owwwwwo..",
		".owwwwwwwo.",
		".owwwwwwwo.",
		".owwwwwwwo.",
		".owwwwwwwo.",
		".owwwwwwwo.",
		"..owwwwwo..",
		"...ooooo...",
		"...........",
	],
}

var texture: ImageTexture
## name -> Rect2 in `texture`.
var regions: Dictionary = {}
## Nine-slice margins per panel kind.
const MARGINS := {&"panel": 8, &"chip": 4, &"key": 4, &"bubble": 4, &"badge": 4}

var _img: Image
var _cursor := Vector2i.ZERO
var _row_h := 0


func _init() -> void:
	_img = Image.create(256, 128, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	for style: StringName in STYLES:
		_panel(style)
		_chip(style)
		_badge(style)
	_key()
	_bubble()
	for n: StringName in ICONS:
		_icon(n)
	texture = ImageTexture.create_from_image(_img)


func region(name: StringName) -> Rect2:
	return regions[name]


func image() -> Image:
	return _img


func _alloc(name: StringName, w: int, h: int) -> Vector2i:
	if _cursor.x + w > _img.get_width():
		_cursor = Vector2i(0, _cursor.y + _row_h + 1)
		_row_h = 0
	var at := _cursor
	regions[name] = Rect2(at, Vector2(w, h))
	_cursor.x += w + 1
	_row_h = maxi(_row_h, h)
	return at


func _px(at: Vector2i, x: int, y: int, c: Color) -> void:
	_img.set_pixel(at.x + x, at.y + y, c)


## 24x24 plate: ink outline with cut corners, trim ring with a lit top-left,
## ink inner line, plate with highlight/shade rows, four rivets.
func _panel(style: StringName) -> void:
	var s: Dictionary = STYLES[style]
	var n := 24
	var at := _alloc(StringName("panel_" + style), n, n)
	for y in n:
		for x in n:
			var edge := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			var corner := (x == 0 or x == n - 1) and (y == 0 or y == n - 1)
			var c := Color(0, 0, 0, 0)
			if corner:
				pass
			elif edge == 0:
				c = INK
			elif edge == 1:
				c = s["trim_hi"] if (x == 1 or y == 1) and x < n - 2 and y < n - 2 else s["trim"]
				if x == n - 2 or y == n - 2:
					c = s["trim_lo"]
			elif edge == 2:
				c = INK
			else:
				c = s["plate"]
				if y == 3:
					c = s["plate_hi"]
				elif y == n - 4:
					c = s["plate_lo"]
			if c.a > 0.0:
				_px(at, x, y, c)
	for r in [Vector2i(4, 4), Vector2i(n - 5, 4), Vector2i(4, n - 5), Vector2i(n - 5, n - 5)]:
		_px(at, r.x, r.y, s["trim_hi"])
		_px(at, r.x + 1, r.y + 1, s["trim_lo"])
		_px(at, r.x + 1, r.y, s["trim"])
		_px(at, r.x, r.y + 1, s["trim"])


## 12x12 inset chip for a stat: dark well, top shadow, lit bottom edge.
func _chip(style: StringName) -> void:
	var s: Dictionary = STYLES[style]
	var n := 12
	var at := _alloc(StringName("chip_" + style), n, n)
	for y in n:
		for x in n:
			var edge := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			var corner := (x == 0 or x == n - 1) and (y == 0 or y == n - 1)
			if corner:
				continue
			var c: Color = INK if edge == 0 else (s["plate_lo"] as Color).darkened(0.25)
			if edge == 1 and y == 1:
				c = INK.lerp(s["plate_lo"], 0.3)
			if edge == 1 and y == n - 2:
				c = (s["trim_lo"] as Color)
			_px(at, x, y, c)


## 12x12 badge (PRO / LITE): solid trim with a highlight and a dark rim.
func _badge(style: StringName) -> void:
	var s: Dictionary = STYLES[style]
	var n := 12
	var at := _alloc(StringName("badge_" + style), n, n)
	for y in n:
		for x in n:
			var edge := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			if (x == 0 or x == n - 1) and (y == 0 or y == n - 1):
				continue
			var c: Color = INK if edge == 0 else s["trim"]
			if edge == 1 and y == 1:
				c = s["trim_hi"]
			if edge >= 1 and y >= n - 3:
				c = s["trim_lo"] if edge > 0 and y < n - 1 else c
			_px(at, x, y, c)


## 12x13 key cap: light face, bright top rim, two-pixel side/bottom depth.
func _key() -> void:
	var w := 12
	var h := 13
	var at := _alloc(&"key", w, h)
	for y in h:
		for x in w:
			if (x == 0 or x == w - 1) and (y == 0 or y == h - 1):
				continue
			var c := Color("e9e3d2")
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				c = INK
			elif y >= h - 3:
				c = Color("8f8676")
			elif y == 1:
				c = Color("ffffff")
			elif x == w - 2:
				c = Color("c4bba8")
			_px(at, x, y, c)


## 12x12 rounded speech bubble + a 7x5 tail under it.
func _bubble() -> void:
	var n := 12
	var at := _alloc(&"bubble", n, n)
	for y in n:
		for x in n:
			var cx := x - (n - 1) / 2.0
			var cy := y - (n - 1) / 2.0
			var corner := (absf(cx) > 4.0 and absf(cy) > 4.0)
			var edge := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			if corner and (x + y == 1 or x + (n - 1 - y) == 1 or (n - 1 - x) + y == 1 or (n - 1 - x) + (n - 1 - y) == 1):
				_px(at, x, y, INK)
				continue
			if corner and (x == 0 or y == 0 or x == n - 1 or y == n - 1):
				continue
			var c := Color("ffffff") if edge > 0 else INK
			if edge > 0 and y == n - 2:
				c = Color("d8dde8")
			_px(at, x, y, c)
	var tat := _alloc(&"bubble_tail", 7, 5)
	var rows := ["owwwwwo", ".owwwo.", ".owwo..", "..owo..", "..oo..."]
	for y in rows.size():
		for x in 7:
			var ch: String = rows[y][x]
			if ch == "o":
				_px(tat, x, y, INK)
			elif ch == "w":
				_px(tat, x, y, Color("ffffff"))


func _icon(n: StringName) -> void:
	var rows: Array = ICONS[n]
	var at := _alloc(StringName("icon_" + n), 11, 11)
	for y in 11:
		var row: String = rows[y]
		for x in mini(11, row.length()):
			var ch := row[x]
			if PAL.has(ch):
				_px(at, x, y, PAL[ch])
