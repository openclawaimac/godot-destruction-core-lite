extends DKTest
## DKCellGrid: shapes, damage, paint, chunks, hash and snapshots.


func _grid(w := 16, h := 16, fill := &"dirt") -> DKCellGrid:
	var g := DKCellGrid.new()
	g.setup(w, h, 8, 8, DKFixtures.materials())
	var mi := g.materials.index_of(fill)
	for y in h:
		for x in w:
			g.set_cell(Vector2i(x, y), mi)
	g.take_dirty_chunks()
	return g


func test_setup_and_rows() -> void:
	var g := DKCellGrid.new()
	g.setup(4, 2, 8, 8, DKFixtures.materials())
	g.load_rows(PackedStringArray(["#RS?", "XF"]), DKFixtures.legend())
	eq(g.material_at_cell(Vector2i(0, 0)).id, &"dirt", "#")
	eq(g.material_at_cell(Vector2i(1, 0)).id, &"rock", "R")
	eq(g.material_at_cell(Vector2i(2, 0)).id, &"steel", "S")
	eq(g.material_at_cell(Vector2i(3, 0)).id, &"empty", "unknown char = air")
	eq(g.material_at_cell(Vector2i(0, 1)).id, &"bedrock", "X")
	eq(g.material_at_cell(Vector2i(2, 1)).id, &"empty", "short row = air")
	eq(g.hp[g.index(Vector2i(1, 0))], 30, "hp from material")
	ok(not g.has_dirty(), "loading does not leave dirty chunks")


func test_coordinates() -> void:
	var g := _grid()
	eq(g.world_to_cell(Vector2(0, 0)), Vector2i(0, 0), "origin")
	eq(g.world_to_cell(Vector2(7.9, 8.0)), Vector2i(0, 1), "cell edges")
	eq(g.world_to_cell(Vector2(-0.1, -8.1)), Vector2i(-1, -2), "negative floors")
	eq(g.cell_center(Vector2i(2, 3)), Vector2(20, 28), "centre")
	ok(g.is_solid(Vector2i(-1, 0)), "outside is solid by default")
	g.outside_solid = false
	ok(not g.is_solid(Vector2i(99, 0)), "outside can be open")


func test_circle_covers_exactly_centres_in_radius() -> void:
	var g := _grid()
	var d := DKDamage.circle(Vector2(64, 64), 12.0, 1)
	var got := g.cells_in(d)
	var want := PackedInt32Array()
	for y in g.height:
		for x in g.width:
			if g.cell_center(Vector2i(x, y)).distance_to(Vector2(64, 64)) <= 12.0:
				want.append(g.index(Vector2i(x, y)))
	eq(got, want, "brute-force set, row-major order")
	ok(got.size() > 0, "non-empty")


func test_rect_line_cell_shapes() -> void:
	var g := _grid()
	eq(g.cells_in(DKDamage.rect(Vector2(0, 0), Vector2(16, 8), 1)), PackedInt32Array([0, 1]), "rect 2x1 cells")
	eq(g.cells_in(DKDamage.rect(Vector2(16, 8), Vector2(-16, -8), 1)), PackedInt32Array([0, 1]), "negative size normalised")
	eq(g.cells_in(DKDamage.cell(Vector2(9, 1), 1)), PackedInt32Array([1]), "single cell")
	eq(g.cells_in(DKDamage.cell(Vector2(-5, 1), 1)).size(), 0, "cell outside grid")
	var line := g.cells_in(DKDamage.line(Vector2(4, 4), Vector2(124, 4), 2.0, 1))
	eq(line.size(), 16, "horizontal line through a whole row")
	for i in line:
		eq(g.coord(i).y, 0, "line stays in row 0")


func test_shapes_clip_at_edges() -> void:
	var g := _grid()
	var c := g.cells_in(DKDamage.circle(Vector2(-20, -20), 40.0, 1))
	for i in c:
		ok(i >= 0 and i < g.width * g.height, "index in range")
	ok(c.size() > 0, "corner circle still hits")
	eq(g.cells_in(DKDamage.circle(Vector2(-500, -500), 10.0, 1)).size(), 0, "fully outside")


func test_damage_subtracts_hp_and_destroys() -> void:
	var g := _grid(4, 1, &"rock")
	var d := DKDamage.cell(Vector2(4, 4), 20, &"dig")
	var r1 := g.apply(d)
	eq(r1.damaged, 1, "one cell hit")
	eq(r1.destroyed.size(), 0, "not yet")
	eq(r1.damaged_cells, PackedInt32Array([0]), "surviving damaged cell listed")
	eq(g.hp[0], 10, "30 - 20")
	var r2 := g.apply(d)
	eq(r2.destroyed, PackedInt32Array([0]), "second hit destroys")
	eq(r2.destroyed_mat, PackedByteArray([g.materials.index_of(&"rock")]), "lost material recorded")
	eq(r2.by_material, {&"rock": 1}, "per-material count")
	eq(r2.damaged_cells.size(), 0, "destroyed cells are not in damaged_cells")
	eq(g.mat[0], 0, "now air")
	ok(g.is_scarred(Vector2i(0, 0)), "scar flag set")
	eq(g.apply(d).damaged, 0, "air takes no damage")


func test_resistance_anchor_and_protected_block() -> void:
	var g := DKCellGrid.new()
	g.setup(4, 1, 8, 8, DKFixtures.materials())
	g.load_rows(PackedStringArray(["SXR#"]), DKFixtures.legend())
	g.set_protected(Vector2i(3, 0), true)
	var r := g.apply(DKDamage.rect(Vector2.ZERO, Vector2(32, 8), 1000, &"blast"))
	eq(r.destroyed, PackedInt32Array([2]), "only rock (50% resist) breaks")
	eq(r.blocked, 3, "steel immune, bedrock anchor, dirt protected")
	g.set_protected(Vector2i(3, 0), false)
	eq(g.apply(DKDamage.cell(Vector2(28, 4), 100)).destroyed.size(), 1, "unprotected dirt breaks")


func test_falloff_weakens_edges() -> void:
	var g := _grid(32, 1, &"rock")
	var r := g.apply(DKDamage.circle(Vector2(128, 4), 64.0, 60, &"dig").with_falloff(0))
	# Centre takes ~60 (destroyed: rock has 30 hp); edges take ~0.
	ok(r.destroyed.size() > 0, "centre destroyed")
	ok(r.destroyed.size() < r.damaged, "edge cells survive")
	var flat := _grid(32, 1, &"rock")
	var rf := flat.apply(DKDamage.circle(Vector2(128, 4), 64.0, 60, &"dig"))
	eq(rf.destroyed.size(), rf.damaged, "flat power destroys everything it hits")


func test_paint_and_protection() -> void:
	var g := _grid(4, 4, &"dirt")
	g.set_protected(Vector2i(0, 0), true)
	var n := g.paint(DKDamage.rect(Vector2.ZERO, Vector2(32, 32), 0), g.materials.index_of(&"rock"))
	eq(n, 15, "all but the protected cell")
	eq(g.material_at_cell(Vector2i(0, 0)).id, &"dirt", "protected kept")
	eq(g.paint(DKDamage.rect(Vector2.ZERO, Vector2(32, 32), 0), g.materials.index_of(&"rock")), 0, "repainting full-hp rock is a no-op")
	g.apply(DKDamage.cell(Vector2(12, 4), 5))
	eq(g.paint(DKDamage.cell(Vector2(12, 4), 0), g.materials.index_of(&"rock")), 1, "repair restores damaged hp")


func test_conservation() -> void:
	var g := _grid(32, 32)
	var before := g.solid_count()
	var destroyed := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		destroyed += g.apply(DKDamage.circle(Vector2(rng.randf_range(0, 256), rng.randf_range(0, 256)), rng.randf_range(4, 30), 10)).destroyed.size()
	eq(g.solid_count() + destroyed, before, "destroyed + remaining = initial")


func test_dirty_chunks_sorted_and_cleared() -> void:
	var g := _grid(32, 32)
	g.apply(DKDamage.circle(Vector2(200, 200), 6.0, 99))
	g.apply(DKDamage.circle(Vector2(10, 10), 6.0, 99))
	g.apply(DKDamage.circle(Vector2(200, 10), 6.0, 99))
	var d := g.take_dirty_chunks()
	eq(d, [Vector2i(0, 0), Vector2i(3, 0), Vector2i(3, 3)] as Array[Vector2i], "row-major order")
	ok(not g.has_dirty(), "cleared")
	g.mark_all_dirty()
	eq(g.take_dirty_chunks().size(), 16, "4x4 chunks")


func test_digest_is_stable_and_sensitive() -> void:
	var a := _grid()
	var b := _grid()
	eq(a.digest(), b.digest(), "same grid, same digest")
	eq(a.state_hash(), b.state_hash(), "same int hash")
	b.apply(DKDamage.cell(Vector2(4, 4), 1))
	ok(a.digest() != b.digest(), "hp change changes digest")
	ok(a.state_hash() > 0, "hash positive")


func test_dict_roundtrip_and_rejection() -> void:
	var g := _grid()
	g.apply(DKDamage.circle(Vector2(40, 40), 20.0, 7))
	var snap := g.to_dict()
	var h := g.digest()
	g.apply(DKDamage.circle(Vector2(80, 80), 30.0, 99))
	ok(g.digest() != h, "changed")
	ok(g.from_dict(snap), "restore ok")
	eq(g.digest(), h, "back to snapshot")
	eq(g.take_dirty_chunks().size(), 4, "restore marks every chunk dirty")
	var other := DKCellGrid.new()
	other.setup(8, 8, 8, 8, DKFixtures.materials())
	ok(not other.from_dict(snap), "size mismatch rejected")
	ok(not g.from_dict({"v": 99}), "bad version rejected")
	eq(g.digest(), h, "rejected restore changes nothing")
