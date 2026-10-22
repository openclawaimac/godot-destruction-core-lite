extends DKTest
## Pixel FX (demos/common/demo_fx_art.gd, MIT, ships with Lite): smoke puffs,
## fireballs and shock rings are hard-edged pixel sprites on the tile grid
## (no anti-aliased or translucent circles), fade by dithering, have a lumpy
## silhouette rather than a disc, and are drawn at whole-pixel positions.


static func _opaque(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				n += 1
	return n


static func _alphas_and_colours(img: Image) -> Array:
	var alphas := {}
	var cols := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			alphas[snappedf(c.a, 0.001)] = true
			if c.a > 0.0:
				cols[Color(c.r, c.g, c.b).to_html(false)] = true
	return [alphas.keys(), cols.keys()]


func test_puffs_are_pixel_snapped_hard_alpha() -> void:
	var fx := DemoFxArt.new()
	for pal: Array in [DemoFxArt.SMOKE, DemoFxArt.FIRE, DemoFxArt.FLASH, DemoFxArt.SMOKE_LIGHT]:
		for r in [2, 5, 11, 24]:
			for fade in [0.0, 0.4, 0.8]:
				var img := fx.puff(r, fade, pal, r).get_image()
				var ac := _alphas_and_colours(img)
				ok((ac[0] as Array).all(func(a: float) -> bool: return a == 0.0 or a == 1.0),
					"puff r%d fade %.1f: every pixel fully opaque or clear (%s)" % [r, fade, ac[0]])
				var allowed := pal.map(func(c: Color) -> String: return c.to_html(false))
				ok((ac[1] as Array).all(func(h: String) -> bool: return allowed.has(h)),
					"puff r%d uses only its 3-tone palette" % r)
				ok(img.get_width() == r * 2 + 4 and img.get_height() == r * 2 + 4, "sprite size is whole pixels")
	var ring := fx.ring(20, 0.3, Color("fff1d6")).get_image()
	var rac := _alphas_and_colours(ring)
	ok((rac[0] as Array).all(func(a: float) -> bool: return a == 0.0 or a == 1.0), "ring has hard alpha")
	ok((rac[1] as Array).size() <= 2, "ring uses at most two tones")


func test_fade_is_dithered_not_translucent() -> void:
	var fx := DemoFxArt.new()
	var prev := 1 << 30
	for i in DemoFxArt.FADE_STEPS + 1:
		var n := _opaque(fx.puff(12, float(i) / DemoFxArt.FADE_STEPS, DemoFxArt.SMOKE, 1).get_image())
		ok(n <= prev, "fade step %d drops pixels (%d <= %d)" % [i, n, prev])
		prev = n
	eq(prev, 0, "fully faded puff is empty")
	var solid := _opaque(fx.puff(12, 0.0, DemoFxArt.SMOKE, 1).get_image())
	var half := _opaque(fx.puff(12, 0.5, DemoFxArt.SMOKE, 1).get_image())
	ok(half > solid * 0.3 and half < solid * 0.7, "half fade keeps about half the pixels (%d of %d)" % [half, solid])
	ok(_opaque(fx.ring(20, 0.0, Color.WHITE).get_image()) > _opaque(fx.ring(20, 0.75, Color.WHITE).get_image()),
		"rings break up as they fade")
	eq(DemoFxArt.fade_level(-1.0), 0, "fade clamps low")
	eq(DemoFxArt.fade_level(2.0), DemoFxArt.FADE_STEPS, "fade clamps high")


func test_puff_silhouette_is_not_a_circle() -> void:
	var fx := DemoFxArt.new()
	for salt in DemoFxArt.SHAPES:
		var r := 14
		var img := fx.puff(r, 0.0, DemoFxArt.SMOKE, salt).get_image()
		var c := float(img.get_width()) / 2.0
		# Best-fit disc of the same area, centred on the silhouette's centroid.
		var n := 0
		var cen := Vector2.ZERO
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.0:
					n += 1
					cen += Vector2(x + 0.5, y + 0.5)
		cen /= float(n)
		var rr := sqrt(float(n) / PI)
		var mismatch := 0
		for y in img.get_height():
			for x in img.get_width():
				var in_disc := Vector2(x + 0.5, y + 0.5).distance_to(cen) <= rr
				if in_disc != (img.get_pixel(x, y).a > 0.0):
					mismatch += 1
		ok(float(mismatch) / float(n) > 0.08, "shape %d is lumpy, not a disc (%.0f%% off the best-fit circle)" % [salt, 100.0 * mismatch / n])
		ok(n < PI * r * r, "lobes stay inside the radius")
		ok(c > 0.0, "centred sprite")
	ok(fx.cached() > 0, "sprites are cached")
	var a := fx.puff(9, 0.0, DemoFxArt.SMOKE, 0)
	eq(fx.puff(9, 0.01, DemoFxArt.SMOKE, 0), a, "same dither level reuses the cached sprite")


func test_draw_positions_snap_to_the_pixel_grid() -> void:
	for pos: Vector2 in [Vector2(10.3, 7.7), Vector2(-3.5, 101.49), Vector2(250.51, 0.02)]:
		for sz: Vector2 in [Vector2(8, 8), Vector2(13, 13), Vector2(31, 31)]:
			var o := DemoFxArt.snap_origin(pos, sz)
			eq(o, o.round(), "origin %s is on whole pixels" % o)
			ok(absf(o.x + sz.x / 2.0 - pos.x) <= 0.5 + 0.001, "stays centred within half a pixel")
			var o2 := DemoFxArt.snap_origin(pos, sz * 2.0, 2)
			eq(Vector2(fposmod(o2.x, 2.0), fposmod(o2.y, 2.0)), Vector2.ZERO, "2x backdrop sprites land on the 2 px grid")


func test_demos_draw_no_smooth_circles() -> void:
	# The pixel FX replace every runtime circle/arc in the demo sources.
	var files: Array[String] = []
	_files("res://demos", files)
	ok(files.size() >= 6, "scanned %d demo files" % files.size())
	for path in files:
		if path.contains("/art_src/"):
			continue  # offline generators write pixels directly
		var src := FileAccess.get_file_as_string(path)
		for b in ["draw_circle(", "draw_arc(", "antialiased"]:
			ok(not src.contains(b), "%s has no '%s'" % [path.get_file(), b])


func test_lite_demo_uses_pixel_fx() -> void:
	var d: Node = load("res://demos/lite_collapse/demo.tscn").instantiate()
	d.manual = true
	tree().root.add_child(d)
	track(d)
	ok(d.fx_art is DemoFxArt, "Lite demo owns a DemoFxArt")
	for _i in 60:
		d.step_tick()
	ok(d._smoke.size() > 0, "blasts made smoke")
	var src := FileAccess.get_file_as_string("res://demos/lite_collapse/demo.gd")
	ok(src.contains("fx_art.puff(") and src.contains("fx_art.ring("), "smoke, fireballs and rings are pixel sprites")


static func _files(dir: String, out: Array[String]) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for sub in da.get_directories():
		_files(dir.path_join(sub), out)
