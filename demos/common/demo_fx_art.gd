class_name DemoFxArt
extends RefCounted
## Pixel-art FX sprites shared by the demos: smoke puffs, fireball blobs and
## shock rings. Built at runtime from integer maths and cached; every sprite
## has hard alpha (each pixel is either fully opaque or fully clear) and fades
## out by ordered (Bayer) dithering instead of translucency, so the effects
## sit on the same pixel grid as the tiles. Draw them at whole-pixel
## positions with `draw()` / `draw_ring()`.
## Original work made for Godot Destruction Core (MIT, like the Lite demo).
## No image files, no AI art, no third-party assets.

const BAYER := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
## Fade is quantised to this many dither levels (0 = solid, FADE_STEPS = gone).
const FADE_STEPS := 8
## Lumpy outline shapes per radius (picked by `salt`).
const SHAPES := 4

## Palettes: [shadow, base, light].
const SMOKE := [Color("3b3340"), Color("544a58"), Color("71667a")]
## Pale distant smoke for daytime backdrops.
const SMOKE_LIGHT := [Color("c3cfdc"), Color("dbe4ee"), Color("f1f5f9")]
const FIRE := [Color("d8452b"), Color("ff8a3d"), Color("ffd36b")]
const FLASH := [Color("ffd36b"), Color("fff1a8"), Color("fffbea")]

## Sprite cache; cleared when it grows past CACHE_MAX entries.
const CACHE_MAX := 3000
var _cache: Dictionary = {}


## Bayer threshold in [0, 1) for a pixel.
static func dither(x: int, y: int) -> float:
	return (float(BAYER[posmod(y, 4)][posmod(x, 4)]) + 0.5) / 16.0


## Quantises a 0..1 fade to a dither level (0..FADE_STEPS).
static func fade_level(fade: float) -> int:
	return clampi(int(floor(clampf(fade, 0.0, 1.0) * FADE_STEPS + 0.5)), 0, FADE_STEPS)


## Lumpy puff of radius `r` px: a few overlapping lobes (a cloud, not a
## circle), lit from the top left in three tones (FIRE and FLASH: a hot core
## stepping out to a dark rim), dithered away by `fade`.
## `density` < 1 thins the puff with a dither even when not fading.
func puff(r: int, fade: float, pal: Array = SMOKE, salt: int = 0, density: float = 1.0) -> ImageTexture:
	r = maxi(r, 1)
	var fl := fade_level(fade)
	var shape := posmod(salt, SHAPES)
	var dq := int(round(clampf(density, 0.0, 1.0) * 8.0))
	var key := "p%d:%d:%d:%d:%d" % [r, fl, shape, dq, pal.hash()]
	if _cache.has(key):
		return _cache[key]
	var lobes := _lobes(r, shape)
	var s := r * 2 + 4
	var c := float(s) / 2.0
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var keep := (1.0 - float(fl) / FADE_STEPS) * float(dq) / 8.0
	var hot := pal == FIRE or pal == FLASH
	for y in s:
		for x in s:
			var px := float(x) + 0.5 - c
			var py := float(y) + 0.5 - c
			if not _inside(lobes, px, py):
				continue
			if dither(x, y) >= keep:
				continue
			var tone := 1
			if hot:
				# Fireballs: hot core, base, dark rim, stepped with the dither.
				var e := 1.0 if not _inside(lobes, px * 1.25, py * 1.25) else sqrt(px * px + py * py) / float(r)
				var t := clampf(e * 2.6, 0.0, 2.999)
				# Flat bands with a narrow dithered seam between them.
				var seam := clampf((fmod(t, 1.0) - 0.6) / 0.4, 0.0, 1.0)
				tone = 2 - (int(t) + int(seam > dither(x + 1, y + 2)))
				tone = clampi(tone, 0, 2)
			# Smoke, lit from the top left: light rim where the pixel up-left
			# is outside, shadow where the pixel down-right is outside.
			elif not _inside(lobes, px + 1.6, py + 1.6) or py > r * 0.45:
				tone = 0
			elif not _inside(lobes, px - 1.6, py - 1.6) or (px + py < -r * 0.9):
				tone = 2
			img.set_pixel(x, y, pal[tone])
	return _store(key, img)


## Pixel shock ring: a 1-2 px band at radius `r`, two tones, broken up by
## dithering (and a few hashed gaps) as it fades.
func ring(r: int, fade: float, col: Color, salt: int = 0) -> ImageTexture:
	r = maxi(r, 2)
	var fl := fade_level(fade)
	var key := "r%d:%d:%d:%s" % [r, fl, posmod(salt, 2), col.to_html()]
	if _cache.has(key):
		return _cache[key]
	var s := r * 2 + 3
	var c := float(s) / 2.0
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var keep := 1.0 - float(fl) / FADE_STEPS
	var width := 2.0 if r >= 8 and fl < FADE_STEPS * 3 / 4 else 1.0
	var edge := col.darkened(0.35)
	for y in s:
		for x in s:
			var px := float(x) + 0.5 - c
			var py := float(y) + 0.5 - c
			var d := sqrt(px * px + py * py)
			if d > float(r) + 0.5 or d < float(r) + 0.5 - width:
				continue
			# Gaps: 16 arc segments, a few drop out once the ring fades.
			var seg := int(floor((atan2(py, px) + PI) / TAU * 16.0)) % 16
			if fl >= 2 and _h(seg, posmod(salt, 2), r) % 5 == 0:
				continue
			if dither(x, y) >= keep:
				continue
			img.set_pixel(x, y, col if d >= float(r) - 0.5 or width < 2.0 else edge)
	return _store(key, img)


## Draws a sprite from this atlas centred on `pos`, snapped to whole pixels,
## optionally scaled by an integer (`px` = 2 for backdrop-resolution art).
static func draw(ci: CanvasItem, tex: Texture2D, pos: Vector2, px: int = 1) -> void:
	var sz := tex.get_size() * px
	ci.draw_texture_rect(tex, Rect2(snap_origin(pos, sz, px), sz), false)


## Top-left corner for a sprite of size `sz` centred on `pos`, on the
## `px`-pixel grid (whole pixels for px = 1).
static func snap_origin(pos: Vector2, sz: Vector2, px: int = 1) -> Vector2:
	return ((pos - sz / 2.0) / float(px)).round() * px


func _store(key: String, img: Image) -> ImageTexture:
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Number of cached sprites (tests).
func cached() -> int:
	return _cache.size()


func _lobes(r: int, shape: int) -> Array:
	# Centre lobe plus 3-4 smaller ones around it; the outline stays inside
	# radius r so the sprite size is predictable.
	var fr := float(r)
	var out: Array = [Vector3(0.0, fr * 0.08, fr * 0.72)]
	var n := 3 + shape % 2
	for i in n:
		var a := TAU * (float(i) + 0.35 * float(shape)) / float(n) + float(_h(i, shape, r) % 100) / 160.0
		var lr := fr * (0.42 + float(_h(i, shape, r + 7) % 20) / 100.0)
		var dist := fr - lr
		out.append(Vector3(cos(a) * dist, sin(a) * dist * 0.85, lr))
	return out


static func _inside(lobes: Array, x: float, y: float) -> bool:
	for l: Vector3 in lobes:
		var dx := x - l.x
		var dy := y - l.y
		if dx * dx + dy * dy <= l.z * l.z:
			return true
	return false


static func _h(a: int, b: int, c: int) -> int:
	var x := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	x &= 0x7fffffff
	x = ((x >> 16) ^ x) * 0x45d9f3b & 0x7fffffff
	return ((x >> 16) ^ x) & 0x7fffffff
