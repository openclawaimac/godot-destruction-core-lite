extends DKTest
## The Lite demo scene: builds, renders, collides, collapses, credits both
## players, stays deterministic, honours reduced motion, ships its art.

const DEMO := "res://demos/lite_collapse/demo.tscn"


func _demo() -> Node:
	var d: Node = load(DEMO).instantiate()
	d.manual = true
	tree().root.add_child(d)
	track(d)
	return d


func test_art_is_present_and_sized() -> void:
	var tiles: Texture2D = load("res://demos/lite_collapse/art/tiles.png")
	var bg: Texture2D = load("res://demos/lite_collapse/art/background.png")
	ok(tiles != null and bg != null, "art loads")
	eq(tiles.get_size(), Vector2(8 * 32 * 16, 8 * 7), "tile atlas: 16 variants x 32 columns, 7 materials")
	eq(bg.get_size(), Vector2(480, 270), "backdrop")
	var img := tiles.get_image()
	var colours: Dictionary = {}
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			colours[img.get_pixel(x, y).to_html()] = true
	ok(colours.size() > 40, "real pixel art, not flat placeholders (%d colours)" % colours.size())


func test_demo_builds_tiles_and_collision() -> void:
	var d := _demo()
	var w: DKWorld = d.world
	eq(w.grid.width, 120, "grid")
	eq(d.renderer.get_used_cells().size(), w.grid.solid_count(), "every cell tiled")
	var area := 0
	for body in d.collision.get_children():
		for cs in body.get_children():
			var s := ((cs as CollisionShape2D).shape as RectangleShape2D).size / 8.0
			area += int(s.x * s.y)
	eq(area, w.grid.solid_count(), "collision covers every solid cell")
	ok(d.collision.shape_count < w.grid.solid_count() / 4, "merged collision (%d shapes)" % d.collision.shape_count)


func _run_autoplay(ticks: int) -> Array:
	var d := _demo()
	d.simulate(ticks)
	d.world.flush()
	return [d, d.world.state_digest(), d.debris.digest(), d.crush_log.duplicate(true)]


func test_autoplay_collapses_and_credits_both_players() -> void:
	var r := _run_autoplay(420)
	var d: Node = r[0]
	var w: DKWorld = d.world
	ok(d.pieces_detached >= 3, "keep, bridge and tower came loose (%d)" % d.pieces_detached)
	ok(d.pieces_landed >= 3, "and landed (%d)" % d.pieces_landed)
	var crushers: Dictionary = {}
	for e in d.crush_log:
		eq(e[0], e[1], "crush damage carries the piece's instigator")
		if int(e[2]) > 0:
			crushers[int(e[1])] = true
	eq(crushers.keys().size(), 2, "both players crushed something: %s" % [crushers.keys()])
	ok(int(w.instigator_stats[1]["destroyed"]) > 0 and int(w.instigator_stats[2]["destroyed"]) > 0, "both players credited")
	ok(d.debris.alive <= d.debris.capacity, "debris capped")
	var mism := 0
	for c in d.renderer.get_used_cells():
		if d.renderer.get_cell_atlas_coords(c) != d.renderer.atlas_coords_for(c):
			mism += 1
	eq(mism, 0, "tiles match the grid after the collapse")
	eq(d.renderer.get_used_cells().size(), w.grid.solid_count(), "no stale tiles")


func test_demo_is_deterministic() -> void:
	var a := _run_autoplay(300)
	var b := _run_autoplay(300)
	eq(a[1], b[1], "same world")
	eq(a[2], b[2], "same debris")
	eq(a[3], b[3], "same landings and crushes")


func test_reduced_motion_in_demo() -> void:
	var d := _demo()
	d.autoplay = false
	d.set_reduced_motion(true)
	d.charge(Vector2(200, 360), 1)
	d.simulate(2)
	eq(d.feel.offset, Vector2.ZERO, "no shake")
	eq(d.feel.hitstops_granted, 0, "no hitstop")
	d.set_reduced_motion(false)
	d.charge(Vector2(880, 380), 2)
	d.simulate(2)
	ok(d.feel.hitstops_granted == 1, "feel back on")


## Mean colour step across tile boundaries vs inside tiles for a material's
## interior tiles laid out by the renderer's variant pick (cells cx..cx+n).
static func seam_ratio(r: DKTileRenderer, img: Image, mat: StringName, row: int) -> float:
	var mi := r.world.materials.index_of(mat)
	var across := 0.0
	var inside := 0.0
	var n := 0
	for gy in range(0, 4):
		for gx in range(0, 12):
			var a := r.variant_for(mi, gx, gy) * 32 + 15
			var b := r.variant_for(mi, gx + 1, gy) * 32 + 15
			for y in 8:
				var ca := img.get_pixel(a * 8 + 7, row * 8 + y)
				var cb := img.get_pixel(b * 8, row * 8 + y)
				across += absf(ca.get_luminance() - cb.get_luminance())
				var c3 := img.get_pixel(a * 8 + 3, row * 8 + y)
				var c4 := img.get_pixel(a * 8 + 4, row * 8 + y)
				inside += absf(c3.get_luminance() - c4.get_luminance())
				n += 1
	return across / maxf(inside, 0.0001)


func test_rock_and_bedrock_tiles_are_seamless() -> void:
	var d := _demo()
	var r: DKTileRenderer = d.renderer
	eq(r.variants, 16, "16 variant blocks")
	var mi: int = d.world.materials.index_of(&"rock")
	eq(r.variant_for(mi, 5, 6), 1 + 4 * 2, "rock picks its variant by position (4x4 macro)")
	eq(r.variant_for(mi, 9, 10), r.variant_for(mi, 5, 6), "macro texture repeats every 4 cells")
	var img: Image = (load("res://demos/lite_collapse/art/tiles.png") as Texture2D).get_image()
	for m: StringName in [&"rock", &"bedrock"]:
		var q := seam_ratio(r, img, m, int(d.MATERIAL_ROWS[m]))
		ok(q < 1.3, "%s: tile edges blend like the interior (ratio %.2f)" % [m, q])
	var under: Node = d.world.get_node_or_null("GroundUnderlay")
	ok(under is DemoGround, "bedrock continues below the grid to the screen edge")
	var bottom: float = d.world.position.y + (d.world.grid.height + under.rows) * d.world.cell_px
	ok(bottom >= 540.0, "underlay reaches the bottom of the view (%d px)" % bottom)
