extends SceneTree
## Generates the Lite demo's pixel art procedurally (original work, no AI, no
## third-party assets). Re-run after changing this file:
##   godot --headless --path . -s res://demos/lite_collapse/art_src/gen_art.gd
## Output (res://demos/lite_collapse/art/):
##   tiles.png       8x8 tiles; one row per material, VARIANTS x 32 columns
##                   (16 neighbour masks intact + 16 damaged) per variant
##   background.png  480x270 sunset parallax backdrop (drawn at 2x)
## Everything is derived from integer hashes, so the output is reproducible.

const T := 8
const VARIANTS := 16
const OUT := "res://demos/lite_collapse/art/"
## Row order must match demo.gd MATERIAL_ROWS.
const MATS := [&"dirt", &"rock", &"brick", &"wood", &"steel", &"bedrock", &"rubble"]

const UP := 1
const RIGHT := 2
const DOWN := 4
const LEFT := 8

var C := {
	"outline": Color("1a1423"),
	"dirt": [Color("4f3224"), Color("6b4430"), Color("86583b"), Color("a5744c"), Color("c39566")],
	"grass": [Color("23502d"), Color("357a36"), Color("54a43f"), Color("8ccf4d"), Color("c8ec74")],
	"rock": [Color("2f3345"), Color("464d65"), Color("5f6982"), Color("7d89a2"), Color("a9b5c8")],
	"brick": [Color("3a2229"), Color("7d2f2b"), Color("9c4232"), Color("bb5a3c"), Color("d8835a")],
	"wood": [Color("3d2418"), Color("5e3922"), Color("7f522f"), Color("a06e3e"), Color("c79559")],
	"steel": [Color("242a3a"), Color("3d4860"), Color("5b6b88"), Color("8394b2"), Color("c9d6ea")],
	"bedrock": [Color("140f1c"), Color("221a2e"), Color("30263f"), Color("43365a"), Color("7a5ca8")],
	"rubble": [Color("2a2125"), Color("4d3a37"), Color("6e554a"), Color("8f7462"), Color("b0937a")],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var tiles := _tiles()
	tiles.save_png(ProjectSettings.globalize_path(OUT + "tiles.png"))
	var bg := _background()
	bg.save_png(ProjectSettings.globalize_path(OUT + "background.png"))
	print("art: tiles %dx%d, background %dx%d" % [tiles.get_width(), tiles.get_height(), bg.get_width(), bg.get_height()])
	quit(0)


static func h3(a: int, b: int, c: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h &= 0x7fffffff
	h = ((h >> 16) ^ h) * 0x45d9f3b & 0x7fffffff
	h = ((h >> 16) ^ h) * 0x45d9f3b & 0x7fffffff
	return ((h >> 16) ^ h) & 0x7fffffff


# — Tiles —

func _tiles() -> Image:
	var img := Image.create(T * 32 * VARIANTS, T * MATS.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for row in MATS.size():
		for v in VARIANTS:
			for dmg in 2:
				for mask in 16:
					var col := v * 32 + dmg * 16 + mask
					var tile := _tile(MATS[row], mask, dmg == 1, v)
					img.blit_rect(tile, Rect2i(0, 0, T, T), Vector2i(col * T, row * T))
	return img


func _tile(mat: StringName, mask: int, damaged: bool, v: int) -> Image:
	var t := Image.create(T, T, false, Image.FORMAT_RGBA8)
	var seed := MATS.find(mat) * 1000 + v * 37
	for y in T:
		for x in T:
			t.set_pixel(x, y, _macro_base(mat, x, y, v) if MACRO.has(mat) else _base(mat, x, y, v, seed))
	_edges(t, mat, mask, v, seed)
	if damaged:
		_cracks(t, mat, mask, v, seed)
	return t


func _base(mat: StringName, x: int, y: int, v: int, seed: int) -> Color:
	var h := h3(x + seed, y, v)
	match mat:
		&"dirt":
			var p: Array = C["dirt"]
			var c: Color = p[2] if ((x + y * 3 + (h & 3)) % 4) != 0 else p[1]
			if h % 13 == 0:
				c = p[3]  # pebble
			elif h % 17 == 0:
				c = p[0]
			return c
		&"rock":
			var p: Array = C["rock"]
			# Two stone faces split by a seam that moves per variant.
			var seam := 3 + v
			var face := 0 if (y < seam and x < 6 - v) else 1
			var c: Color = p[2] if face == 0 else p[1 + int((h % 5) == 0)]
			if (y == seam and x < 6 - v) or (x == 6 - v and y < seam):
				c = p[0]
			elif (y == 0 or x == 0) and face == 0:
				c = p[3]
			elif (y == seam + 1 and x < 7) and face == 1:
				c = p[3] if (h % 3) else p[2]
			if h % 23 == 0:
				c = p[4]
			return c
		&"brick":
			var p: Array = C["brick"]
			var band := y / 4
			var off := 0 if band == 0 else 4
			var bx := (x + off) % 8
			if y % 4 == 3 or bx == 0:
				return p[0]  # mortar
			var brick_id := ((x + off) / 8) + band * 2
			var tone := 2 + int(h3(brick_id, v, seed) % 3 == 0) - int(h3(brick_id, v + 9, seed) % 4 == 0)
			var c: Color = p[clampi(tone, 1, 3)]
			if y % 4 == 0:
				c = c.lightened(0.12)
			if bx == 7:
				c = c.darkened(0.12)
			return c
		&"wood":
			var p: Array = C["wood"]
			var py := y % 4
			if py == 3:
				return p[0]
			var c: Color = p[2]
			if py == 0:
				c = p[3]
			if (h3(x / 3 + v, y, seed) % 5) == 0:
				c = p[1]  # grain
			if (x == 1 or x == 6) and py == 1 and (y / 4 + v) % 2 == 0:
				c = p[0]  # nail
			return c
		&"steel":
			var p: Array = C["steel"]
			if x == 7 or y == 7:
				return p[0]
			if x == 0 or y == 0:
				return p[3]
			if (x == 1 or x == 6) and (y == 1 or y == 6):
				return p[4]  # rivet
			var c: Color = p[2]
			if (x + y + v) % 5 == 0:
				c = p[1]  # brushed diagonal
			return c
		&"bedrock":
			var p: Array = C["bedrock"]
			var c: Color = p[1 + int((h % 3) == 0)]
			if ((x + y) % 4 == 0 and h % 2 == 0):
				c = p[0]
			if h % 41 == 0:
				c = p[4]  # crystal glint
			elif h % 11 == 0:
				c = p[3]
			return c
		&"rubble":
			var p: Array = C["rubble"]
			var blk := h3(x / 2 + seed, y / 2, v)
			var c: Color = p[1 + blk % 4]
			if blk % 7 == 0:
				c = (C["brick"] as Array)[2]
			elif blk % 9 == 0:
				c = (C["rock"] as Array)[3]
			if (x % 2 == 1 and y % 2 == 1 and h % 2 == 0):
				c = p[0]  # gaps between chunks
			return c
	return Color.MAGENTA



# — Seamless macro textures —
# Rock and bedrock are drawn from one wrap-around texture of
# (period.x * T) x (period.y * T) pixels; variant v is the slice at
# (v % period.x, v / period.x). The renderer picks variants by position for
# these materials (DKTileRenderer.macro_tiles), so neighbouring cells continue
# the same stones/strata and no tile edge lines up on a grid.

const MACRO := {&"rock": Vector2i(4, 4), &"bedrock": Vector2i(8, 2)}
var _macro_cache := {}


func _macro_base(mat: StringName, x: int, y: int, v: int) -> Color:
	var per: Vector2i = MACRO[mat]
	if not _macro_cache.has(mat):
		_macro_cache[mat] = _cobbles(per.x * T, per.y * T) if mat == &"rock" else _strata(per.x * T, per.y * T)
	var tex: Image = _macro_cache[mat]
	return tex.get_pixel((v % per.x) * T + x, (v / per.x) * T + y)


## Irregular cobbles: wrapped Voronoi over a staggered, jittered point set,
## dark mortar where two stones meet, light top-left / dark bottom-right rims.
func _cobbles(w: int, h: int) -> Image:
	var p: Array = C["rock"]
	var pts: Array[Vector2] = []
	var rows := 6
	var cols := 5
	for r in rows:
		for c in cols:
			var jx := float(h3(r, c, 11) % 100) / 100.0 - 0.5
			var jy := float(h3(r, c, 12) % 100) / 100.0 - 0.5
			var px := (float(c) + (0.5 if r % 2 else 0.0) + jx * 0.55) * float(w) / cols
			var py := (float(r) + 0.5 + jy * 0.45) * float(h) / rows
			pts.append(Vector2(fposmod(px, w), fposmod(py, h)))
	var id := PackedInt32Array()
	id.resize(w * h)
	var edge := PackedByteArray()
	edge.resize(w * h)
	for y in h:
		for x in w:
			var d1 := 1e9
			var d2 := 1e9
			var best := 0
			for i in pts.size():
				var dx := absf(x + 0.5 - pts[i].x)
				var dy := absf(y + 0.5 - pts[i].y)
				dx = minf(dx, w - dx) * 0.85  # stones a bit wider than tall
				dy = minf(dy, h - dy)
				var d := sqrt(dx * dx + dy * dy)
				if d < d1:
					d2 = d1
					d1 = d
					best = i
				elif d < d2:
					d2 = d
			id[y * w + x] = best
			edge[y * w + x] = 1 if d2 - d1 < 0.9 else 0
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var k := y * w + x
			var hh := h3(x, y, 4242)
			if edge[k]:
				img.set_pixel(x, y, p[0])
				continue
			var s := id[k]
			var tone := 2 if h3(s, 3, 77) % 3 else 1
			var c: Color = p[tone]
			var ul := (posmod(y - 1, h)) * w + posmod(x - 1, w)
			var up := (posmod(y - 1, h)) * w + x
			var dn := (posmod(y + 1, h)) * w + x
			var rt := y * w + posmod(x + 1, w)
			if edge[up] or edge[ul] or id[up] != s:
				c = p[tone + 1]
			elif edge[dn] or edge[rt] or id[dn] != s:
				c = p[maxi(tone - 1, 1)] if tone == 2 else (p[0] as Color).lerp(p[1], 0.5)
			elif hh % 9 == 0:
				c = p[tone + 1] if hh % 2 else p[maxi(tone - 1, 1)]
			if hh % 37 == 0:
				c = p[4]
			img.set_pixel(x, y, c)
	return img


## Bedrock: wrapped value noise (4 px lattice) with dark veins and rare
## crystal glints; continuous across tiles.
func _strata(w: int, h: int) -> Image:
	var p: Array = C["bedrock"]
	var lw := w / 4
	var lh := h / 4
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var fx := (x + 0.5) / 4.0
			var fy := (y + 0.5) / 4.0
			var ix := int(floor(fx))
			var iy := int(floor(fy))
			var tx := fx - ix
			var ty := fy - iy
			var n00 := float(h3(posmod(ix, lw), posmod(iy, lh), 91) % 1000) / 1000.0
			var n10 := float(h3(posmod(ix + 1, lw), posmod(iy, lh), 91) % 1000) / 1000.0
			var n01 := float(h3(posmod(ix, lw), posmod(iy + 1, lh), 91) % 1000) / 1000.0
			var n11 := float(h3(posmod(ix + 1, lw), posmod(iy + 1, lh), 91) % 1000) / 1000.0
			var n := lerpf(lerpf(n00, n10, tx), lerpf(n01, n11, tx), ty)
			var hh := h3(x, y, 5151)
			n += (float(hh % 100) / 100.0 - 0.5) * 0.25
			var c: Color = p[1]
			if n < 0.3:
				c = p[0]
			elif n > 0.68:
				c = p[2]
			if n > 0.6 and hh % 13 == 0:
				c = p[3]
			if hh % 97 == 0:
				c = p[4]  # crystal glint
			img.set_pixel(x, y, c)
	return img


func _edges(t: Image, mat: StringName, mask: int, v: int, seed: int) -> void:
	var o: Color = C["outline"]
	var open_up := (mask & UP) == 0
	var open_down := (mask & DOWN) == 0
	var open_left := (mask & LEFT) == 0
	var open_right := (mask & RIGHT) == 0
	var pal: Array = C[String(mat)]
	# Exposed sides: dark outline, light rim inside the top.
	for i in T:
		if open_left:
			t.set_pixel(0, i, o)
		if open_right:
			t.set_pixel(T - 1, i, o)
		if open_down:
			t.set_pixel(i, T - 1, o)
	if open_up:
		if mat == &"dirt":
			_grass(t, mask, v, seed)
		else:
			for i in T:
				t.set_pixel(i, 0, o)
				if t.get_pixel(i, 1) != o:
					t.set_pixel(i, 1, (pal[4] as Color) if mat != &"bedrock" else (pal[3] as Color))
	# Rounded corners where two exposed sides meet.
	var clear := Color(0, 0, 0, 0)
	if open_up and open_left:
		t.set_pixel(0, 0, clear)
		t.set_pixel(1, 1, o) if mat != &"dirt" else null
	if open_up and open_right:
		t.set_pixel(T - 1, 0, clear)
	if open_down and open_left:
		t.set_pixel(0, T - 1, clear)
	if open_down and open_right:
		t.set_pixel(T - 1, T - 1, clear)


func _grass(t: Image, mask: int, v: int, seed: int) -> void:
	var g: Array = C["grass"]
	var o: Color = C["outline"]
	var clear := Color(0, 0, 0, 0)
	for x in T:
		var h := h3(x + seed, 77, v)
		var tuft := h % 3 == 0
		# Row 0: blades on transparent sky; rows 1-2 turf; row 3 dark fringe.
		t.set_pixel(x, 0, (g[3] as Color) if tuft else clear)
		t.set_pixel(x, 1, g[3] if (h % 2 == 0) else g[2])
		t.set_pixel(x, 2, g[2] if (h % 4 != 0) else g[4])
		var drip := (h >> 3) % 3 == 0
		t.set_pixel(x, 3, g[1] if drip else g[0])
		if drip and (h >> 5) % 2 == 0:
			t.set_pixel(x, 4, g[0])
	if (mask & LEFT) == 0:
		for y in range(1, 4):
			t.set_pixel(0, y, o)
	if (mask & RIGHT) == 0:
		for y in range(1, 4):
			t.set_pixel(T - 1, y, o)


func _cracks(t: Image, mat: StringName, mask: int, v: int, seed: int) -> void:
	var o: Color = C["outline"]
	var pal: Array = C[String(mat)]
	var x := 1 + h3(seed, v, 5) % 5
	var y := 1
	# A jagged crack from top to bottom.
	while y < T - 1:
		t.set_pixel(x, y, o)
		if y + 1 < T - 1 and h3(x, y, seed + v) % 3 == 0:
			t.set_pixel(clampi(x + 1, 1, T - 2), y, (pal[0] as Color))
		var step := h3(x, y, v) % 3 - 1
		x = clampi(x + step, 1, T - 2)
		y += 1
	# Chipped exposed edges.
	var clear := Color(0, 0, 0, 0)
	if (mask & UP) == 0:
		t.set_pixel(2 + h3(seed, v, 1) % 4, 0, clear)
	if (mask & RIGHT) == 0:
		t.set_pixel(T - 1, 2 + h3(seed, v, 2) % 4, clear)


# — Background —

const BAYER := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


func _background() -> Image:
	var w := 480
	var h := 270
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var sky := [Color("1c1f45"), Color("2f2e63"), Color("4d3a78"), Color("7a4380"),
		Color("ad5577"), Color("d9736a"), Color("f19a68"), Color("f7c27a")]
	for y in h:
		var f := clampf(float(y) / 190.0, 0.0, 0.999) * (sky.size() - 1)
		var i0 := int(f)
		var frac := f - i0
		for x in w:
			var thr := (float(BAYER[y % 4][x % 4]) + 0.5) / 16.0
			img.set_pixel(x, y, sky[mini(i0 + int(frac > thr), sky.size() - 1)])
	# Stars in the upper sky.
	for k in 70:
		var sx := h3(k, 1, 7) % w
		var sy := h3(k, 2, 7) % 80
		img.set_pixel(sx, sy, Color("fff1d6") if k % 5 else Color("9fb4ff"))
	# Sun with a dithered halo.
	var sun := Vector2(330, 112)
	for y in range(70, 160):
		for x in range(270, 390):
			var d := Vector2(x, y).distance_to(sun)
			if d < 22.0:
				img.set_pixel(x, y, Color("ffe7a6") if d < 20.0 else Color("ffd27f"))
			elif d < 34.0:
				var thr := (float(BAYER[y % 4][x % 4]) + 0.5) / 16.0
				if (34.0 - d) / 12.0 > thr:
					img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color("ffc27a"), 0.55))
	# Clouds: flat-bottomed pixel blobs, lit from the sun side.
	for k in 9:
		var cx := h3(k, 3, 9) % (w + 60) - 30
		var cy := 40 + h3(k, 4, 9) % 110
		var cw := 30 + h3(k, 5, 9) % 50
		_cloud(img, cx, cy, cw, k)
	# Mountain layers (far to near).
	_ridge(img, 150, 40, Color("6d4a86"), 1, 0.012, Color("8a5f96"))
	_ridge(img, 180, 34, Color("4a3466"), 2, 0.02, Color("5f4479"))
	_ridge(img, 205, 26, Color("2c2242"), 3, 0.035, Color("3a2d55"))
	_trees(img, 205, 26, 3, Color("1f1830"))
	return img


func _cloud(img: Image, cx: int, cy: int, cw: int, k: int) -> void:
	var lit := Color("f6b38f")
	var mid := Color("d9837a")
	var dark := Color("9c5a78")
	for x in range(cx, cx + cw):
		var t := float(x - cx) / float(cw)
		var top := int(sin(t * PI) * (6.0 + h3(k, x / 6, 3) % 5))
		for y in range(cy - top, cy + 2):
			if x < 0 or x >= img.get_width() or y < 0 or y >= img.get_height():
				continue
			var c := mid
			if y >= cy:
				c = dark
			elif y <= cy - top + 1:
				c = lit
			img.set_pixel(x, y, c)


func _ridge(img: Image, base: int, amp: int, col: Color, layer: int, freq: float, rim: Color) -> void:
	var w := img.get_width()
	var prev := -1
	for x in w:
		var fx := float(x)
		var n := sin(fx * freq + layer) * 0.5 + sin(fx * freq * 2.3 + layer * 3.1) * 0.3 \
			+ sin(fx * freq * 5.7 + layer) * 0.15 + float(h3(x / 3, layer, 11) % 3) * 0.03
		var top := base - int(n * amp) - amp / 2
		for y in range(top, img.get_height()):
			img.set_pixel(x, y, col)
		img.set_pixel(x, top, rim)
		if prev >= 0 and absi(prev - top) > 1:
			for y in range(mini(prev, top), maxi(prev, top)):
				img.set_pixel(x, y, rim if y < top else col)
		prev = top


func _trees(img: Image, base: int, amp: int, layer: int, col: Color) -> void:
	var w := img.get_width()
	var freq := 0.035
	var x := 4
	while x < w:
		var fx := float(x)
		var n := sin(fx * freq + layer) * 0.5 + sin(fx * freq * 2.3 + layer * 3.1) * 0.3 \
			+ sin(fx * freq * 5.7 + layer) * 0.15
		var top := base - int(n * amp) - amp / 2
		var th := 6 + h3(x, 5, 13) % 7
		for dy in th:
			var half := dy / 2
			for dx in range(-half, half + 1):
				var px := x + dx
				var py := top - th + dy + 1
				if px >= 0 and px < w and py >= 0:
					img.set_pixel(px, py, col)
		x += 5 + h3(x, 6, 13) % 9
