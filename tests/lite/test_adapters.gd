extends DKTest
## Lite adapters: debris pool, feel (shake / hitstop / reduced motion),
## tile renderer and chunk collision.


func _world(w := 32, h := 16) -> DKWorld:
	var world := DKFixtures.filled(self, w, h, &"dirt")
	return world


# — Debris —

func _debris(world: DKWorld, cap := 64) -> DKDebris:
	var d := DKDebris.new()
	d.capacity = cap
	d.auto_step = false
	track(d)
	d.bind_world(world)
	return d


func test_debris_pool_is_hard_capped() -> void:
	var w := _world(64, 32)
	var d := _debris(w, 50)
	d.max_per_event = 1000
	w.apply_damage(DKDamage.circle(Vector2(256, 128), 80.0, 99, &"blast", 1))
	ok(d.spawned_total > 50, "big blast asked for more than the cap (%d)" % d.spawned_total)
	ok(d.alive <= 50, "never more than capacity alive (%d)" % d.alive)
	for i in 200:
		d.step()
	eq(d.alive, 0, "all expired")


func test_debris_per_event_cap() -> void:
	var w := _world(64, 32)
	var d := _debris(w, 1000)
	d.max_per_event = 30
	var n := d.spawn_for_report(w.apply_damage(DKDamage.circle(Vector2(256, 128), 80.0, 99, &"blast", 1)))
	ok(n <= 30, "per-event cap (%d)" % n)


func test_debris_is_deterministic() -> void:
	var digests: Array = []
	for run in 2:
		var w := _world(48, 24)
		var d := _debris(w, 200)
		w.apply_damage(DKDamage.circle(Vector2(100, 60), 30.0, 99, &"blast", 1))
		for i in 10:
			d.step()
		w.apply_damage(DKDamage.circle(Vector2(250, 90), 24.0, 99, &"blast", 2))
		for i in 25:
			d.step()
		digests.append(d.digest())
	eq(digests[0], digests[1], "same input, same particles")


func test_debris_reduced_motion_spawns_less() -> void:
	var counts: Array = []
	for rm in [false, true]:
		var w := _world(48, 24)
		var d := _debris(w, 1000)
		d.reduced_motion = rm
		w.apply_damage(DKDamage.circle(Vector2(190, 90), 40.0, 99, &"blast", 1))
		counts.append(d.spawned_total)
	ok(counts[1] < counts[0] / 2, "reduced motion: %d vs %d" % [counts[1], counts[0]])


# — Feel —

func _feel() -> DKFeel:
	var f := DKFeel.new()
	f.auto_process = false
	f.use_time_scale = false
	track(f)
	return f


func test_hitstop_once_per_chain_and_capped() -> void:
	var f := _feel()
	ok(f.request_hitstop(500.0, 7), "first in chain 7")
	ok(f.hitstop_left_ms <= f.hitstop_max_ms, "capped at max")
	f.advance(1000.0)
	ok(not f.request_hitstop(50.0, 7), "chain 7 never again")
	ok(f.request_hitstop(50.0, 8), "another chain")
	ok(not f.request_hitstop(50.0, 9), "cooldown blocks stacking")
	f.advance(1000.0)
	ok(f.request_hitstop(50.0, 9), "after cooldown")
	eq(f.hitstops_granted, 3, "granted count")


func test_shake_decays_and_reduced_motion_disables_feel() -> void:
	var f := _feel()
	f.add_trauma(0.8)
	f.advance(16.0)
	ok(f.trauma > 0.0, "trauma")
	f.advance(5000.0)
	eq(f.trauma, 0.0, "decayed")
	eq(f.offset, Vector2.ZERO, "still")
	f.set_reduced_motion(true)
	f.add_trauma(1.0)
	f.advance(16.0)
	eq(f.offset, Vector2.ZERO, "no shake with reduced motion")
	ok(not f.request_hitstop(50.0, 1), "no hitstop with reduced motion")


func test_feel_reacts_to_world_events() -> void:
	var w := _world(64, 32)
	var f := _feel()
	f.bind_world(w)
	w.detonate(Vector2(100, 100), 30.0, 99, &"blast", 1)
	ok(f.trauma > 0.0, "blast shakes")
	ok(f.is_in_hitstop(), "blast hitstops")
	w.detonate(Vector2(300, 100), 30.0, 99, &"blast", 2)
	eq(f.hitstops_granted, 1, "second blast in the same moment does not stack")


# — Tile renderer —

func _renderer(w: DKWorld) -> DKTileRenderer:
	var r := DKTileRenderer.new()
	var img := Image.create(8 * 32, 8 * 6, false, Image.FORMAT_RGBA8)
	r.atlas = ImageTexture.create_from_image(img)
	r.tile_px = 8
	r.material_rows = {&"dirt": 0, &"rock": 1, &"steel": 2, &"fuel": 3, &"glass": 4}
	track(r)
	r.bind_world(w)
	return r


func test_renderer_masks_and_damage_columns() -> void:
	var w := make_world(6, 6, DKFixtures.materials())
	w.load_rows(PackedStringArray(["......", ".#....", "......", "..###.", "..###.", "..###."]), DKFixtures.legend())
	var r := _renderer(w)
	w.flush()
	eq(r.atlas_coords_for(Vector2i(1, 1)), Vector2i(0, 0), "lone cell = mask 0")
	eq(r.atlas_coords_for(Vector2i(3, 4)), Vector2i(15, 0), "interior = mask 15")
	eq(r.atlas_coords_for(Vector2i(3, 3)), Vector2i(2 + 4 + 8, 0), "top edge: right+down+left")
	eq(r.atlas_coords_for(Vector2i(3, 5)).x & 4, 4, "floor edge counts as solid below")
	w.apply_damage(DKDamage.cell(Vector2(28, 36), 6, &"dig", 1))  # dirt hp 10 -> 4
	eq(r.atlas_coords_for(Vector2i(3, 4)), Vector2i(31, 0), "damaged interior = column 16 + 15")
	eq(r.get_used_cells().size(), 10, "every solid cell is tiled")


func test_renderer_follows_chunk_rebuilds() -> void:
	var w := _world(32, 16)
	var r := _renderer(w)
	r.rebuild_all()  # the fixture flushed before the renderer was bound
	var before := r.get_used_cells().size()
	eq(before, w.grid.solid_count(), "all tiled")
	w.apply_damage(DKDamage.circle(Vector2(128, 64), 20.0, 99, &"blast", 1))
	w.flush()
	eq(r.get_used_cells().size(), w.grid.solid_count(), "tiles follow the grid")
	for c in r.get_used_cells():
		eq(r.get_cell_atlas_coords(c), r.atlas_coords_for(c), "cell %s matches" % c)
		if r.get_cell_atlas_coords(c) != r.atlas_coords_for(c):
			break


# — Chunk collision —

func _covered(g: DKCellGrid, rects: Array) -> Dictionary:
	var got: Dictionary = {}
	for rr: Rect2i in rects:
		for y in range(rr.position.y, rr.end.y):
			for x in range(rr.position.x, rr.end.x):
				got[y * g.width + x] = int(got.get(y * g.width + x, 0)) + 1
	return got


func test_merge_rects_cover_exactly_the_solid_cells() -> void:
	var w := DKFixtures.filled(self, 40, 24, &"dirt")
	DKFixtures.run_script(w, 7, 40)
	var g := w.grid
	var cc := g.chunk_count()
	var all: Array = []
	for cy in cc.y:
		for cx in cc.x:
			var rs := DKChunkCollision.merge_rects(g, Vector2i(cx, cy))
			eq(rs, DKChunkCollision.merge_rects(g, Vector2i(cx, cy)), "deterministic")
			all.append_array(rs)
	var got := _covered(g, all)
	var solid := 0
	var bad := 0
	for i in g.mat.size():
		var is_solid := g.mat[i] != 0 and g.materials.at(g.mat[i]).solid
		if is_solid:
			solid += 1
		if (is_solid and int(got.get(i, 0)) != 1) or (not is_solid and got.has(i)):
			bad += 1
	eq(bad, 0, "every solid cell covered exactly once, nothing else")
	ok(all.size() < solid / 3, "rectangles are merged (%d for %d cells)" % [all.size(), solid])


func test_chunk_collision_rebuilds_shapes() -> void:
	var w := _world(32, 16)
	var col := DKChunkCollision.new()
	track(col)
	col.bind_world(w)
	col.rebuild_all()
	var n0 := col.shape_count
	ok(n0 > 0, "shapes built")
	w.apply_damage(DKDamage.circle(Vector2(128, 64), 20.0, 99, &"blast", 1))
	w.flush()
	ok(col.shape_count > n0, "a crater splits rectangles (%d -> %d)" % [n0, col.shape_count])
