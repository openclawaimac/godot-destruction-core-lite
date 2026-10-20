extends DKTest
## Lite collapse: incremental budgeted support check, falling pieces, rubble,
## crush damage with instigators, determinism and snapshots.


func _mats() -> DKMaterialSet:
	return DKMaterialSet.make([
		DKMaterial.make(&"dirt", 10, {"density": 2}),
		DKMaterial.make(&"brick", 20, {"density": 3, "rubble_into": &"rubble"}),
		DKMaterial.make(&"rubble", 6, {"density": 2}),
		DKMaterial.make(&"bedrock", 1, {"anchor": true, "falls": false}),
	])


const LEGEND := {"#": &"dirt", "B": &"brick", "X": &"bedrock", "r": &"rubble"}


func _world(rows: Array) -> DKWorld:
	var w := make_world((rows[0] as String).length(), rows.size(), _mats())
	w.load_rows(PackedStringArray(rows), LEGEND)
	w.flush()
	return w


## Tower: a brick cap on a 2-wide pillar, standing on a dirt floor over bedrock.
const TOWER := [
	"................",
	"................",
	"....BBBBBBBB....",
	"....BBBBBBBB....",
	".......BB.......",
	".......BB.......",
	".......BB.......",
	".......BB.......",
	".......BB.......",
	"................",
	"................",
	"................",
	"................",
	"................",
	"################",
	"XXXXXXXXXXXXXXXX",
]


func _count(w: DKWorld, mat_id: StringName) -> int:
	var mi := w.materials.index_of(mat_id)
	var n := 0
	for m in w.grid.mat:
		if m == mi:
			n += 1
	return n


func _cut_pillar(w: DKWorld, instigator: int, x := 60.0) -> DKReport:
	return w.apply_damage(DKDamage.rect(Vector2(x - 10, 40), Vector2(20, 32), 99, &"blast", instigator))  # rows 5-8


func test_cut_pillar_drops_the_top_as_a_piece_that_lands_as_rubble() -> void:
	var w := _world(TOWER)
	# The pillar hangs in the air (rows 12-13 empty): it is unsupported already,
	# so check the level first; the whole tower falls.
	var detached: Array = []
	var landed: Array = []
	w.piece_detached.connect(func(p: Dictionary) -> void: detached.append(p))
	w.piece_landed.connect(func(p: Dictionary, c: DKDamage, imp: int) -> void: landed.append([p, c, imp]))
	var bricks := _count(w, &"brick")
	w.check_all_support()
	w.tick()
	eq(detached.size(), 1, "floating tower detached as one piece")
	eq((detached[0]["cells"] as PackedInt32Array).size(), bricks, "piece holds every brick")
	eq(_count(w, &"brick"), 0, "lifted out of the grid")
	ok(landed.is_empty(), "still falling after one tick")
	var ticks := w.settle()
	ok(ticks > 2 and ticks < 200, "fell over several ticks (%d)" % ticks)
	ok(landed.size() >= 1, "landed (crushing the floor may let it settle again)")
	var rub := _count(w, &"rubble")
	ok(rub > 0 and rub <= bricks, "written back as rubble (%d)" % rub)
	# The lowest rubble cell of the pillar rests on something solid.
	var lowest := -1
	for y in 16:
		if w.grid.mat_index(Vector2i(7, y)) == w.materials.index_of(&"rubble"):
			lowest = y
	ok(lowest >= 12, "pillar came down (lowest rubble row %d)" % lowest)
	ok(w.grid.mat_index(Vector2i(7, lowest + 1)) > 0, "rests on solid ground")
	ok((w.grid.flags[w.grid.index(Vector2i(7, lowest))] & DKCellGrid.FLAG_RUBBLE) != 0, "rubble flag set")
	ok(w.support.is_idle() and w.pieces.pieces.is_empty(), "settled")


func test_supported_ground_does_not_fall() -> void:
	var w := _world(TOWER)
	var detached: Array = []
	w.piece_detached.connect(func(p: Dictionary) -> void: detached.append(p))
	w.apply_damage(DKDamage.circle(Vector2(30, 112), 10.0, 99, &"blast", 1))  # crater in the floor
	w.settle()
	ok(detached.is_empty(), "floor attached to bedrock stays")


func _standing_tower() -> DKWorld:
	var rows: Array = TOWER.duplicate()
	for y in range(9, 14):
		rows[y] = ".......BB......."
	return _world(rows)


func test_cut_standing_tower_and_crush_credits_the_cutter() -> void:
	var w := _standing_tower()
	var landed: Array = []
	w.piece_landed.connect(func(p: Dictionary, c: DKDamage, imp: int) -> void: landed.append([p, c, imp]))
	w.settle()
	ok(landed.is_empty(), "standing tower is stable")
	_cut_pillar(w, 7)
	w.settle()
	ok(landed.size() >= 1, "top fell and landed (crushing may let it settle again)")
	var p: Dictionary = landed[0][0]
	var crush: DKDamage = landed[0][1]
	eq(int(p["instigator_id"]), 7, "piece credited to the cutter")
	eq(crush.instigator_id, 7, "crush damage carries the instigator")
	eq(crush.type, &"crush", "crush type")
	ok(int(landed[0][2]) > 0, "impact speed reported")
	ok(crush.power > 0, "a real fall crushes (%d)" % crush.power)
	ok(int(w.instigator_stats[7]["damaged"]) > 0, "crush hits credited to player 7")


func test_unbounded_region_is_found_over_several_budgeted_ticks() -> void:
	# A 120x30 slab (3600 cells) on one thin column: no size cap, budget 500.
	var rows: Array = []
	for y in 50:
		if y < 5:
			rows.append(".".repeat(120))
		elif y < 35:
			rows.append("#".repeat(120))
		elif y < 49:
			rows.append(".".repeat(60) + "#" + ".".repeat(59))
		else:
			rows.append("X".repeat(120))
	var w := _world(rows)
	w.support_budget = 500
	var detached: Array = []
	w.piece_detached.connect(func(p: Dictionary) -> void: detached.append(p))
	w.apply_damage(DKDamage.rect(Vector2(480, 320), Vector2(8, 8), 99, &"blast", 3))
	var ticks := 0
	while detached.is_empty() and ticks < 100:
		w.tick()
		ticks += 1
		ok(w.support.visits_last_step <= 500, "budget respected")
	ok(ticks >= 3600 / 500, "took several ticks (%d)" % ticks)
	eq(detached.size(), 1, "slab detached")
	eq((detached[0]["cells"] as PackedInt32Array).size(), 3600 + 5, "whole slab plus the column stub above the cut")
	eq(int(detached[0]["instigator_id"]), 3, "credited")


func test_two_instigators_two_pieces() -> void:
	var rows: Array = []
	for y in 16:
		if y == 15:
			rows.append("X".repeat(32))
		elif y == 14:
			rows.append("#".repeat(32))
		elif y < 4:
			rows.append("..BBBBBB" + ".".repeat(14) + "BBBBBB..")
		else:
			rows.append("....BB" + ".".repeat(18) + "BB....")
	var w := _world(rows)
	var by_id: Dictionary = {}
	w.piece_landed.connect(func(p: Dictionary, c: DKDamage, _i: int) -> void:
		by_id[int(p["instigator_id"])] = c.instigator_id)
	w.apply_damage(DKDamage.rect(Vector2(32, 80), Vector2(16, 8), 99, &"blast", 1))
	w.apply_damage(DKDamage.rect(Vector2(192, 80), Vector2(16, 8), 99, &"blast", 2))
	w.settle()
	eq(by_id, {1: 1, 2: 2}, "each piece and its crush belong to the player who cut it")


func _scripted_collapse() -> Array:
	var w := _standing_tower()
	var log: Array = []
	w.piece_detached.connect(func(p: Dictionary) -> void: log.append(["d", w.tick_count, p["id"], (p["cells"] as PackedInt32Array).size()]))
	w.piece_landed.connect(func(p: Dictionary, c: DKDamage, imp: int) -> void: log.append(["l", w.tick_count, p["id"], imp, c.power, c.cell_list]))
	_cut_pillar(w, 1)
	w.apply_damage(DKDamage.circle(Vector2(36, 24), 6.0, 99, &"blast", 2))
	w.settle()
	return [log, w.state_digest(), w.instigator_stats.duplicate(true)]


func test_collapse_is_deterministic() -> void:
	var a := _scripted_collapse()
	var b := _scripted_collapse()
	ok((a[0] as Array).size() >= 2, "something fell")
	eq(a[0], b[0], "same detach/land log")
	eq(a[1], b[1], "same end state")
	eq(a[2], b[2], "same per-instigator stats")


func test_snapshot_mid_fall_replays_identically() -> void:
	var w := _standing_tower()
	_cut_pillar(w, 4)
	for i in 4:
		w.tick()
	ok(w.pieces.pieces.size() == 1, "piece in the air")
	var snap := w.snapshot()
	w.settle()
	var end_a := w.state_digest()
	ok(w.restore(snap), "restore")
	eq(w.pieces.pieces.size(), 1, "falling piece restored")
	w.settle()
	eq(w.state_digest(), end_a, "same landing after restore")


func test_painting_a_support_mid_check_keeps_the_region_up() -> void:
	var rows: Array = []
	for y in 40:
		if y < 10:
			rows.append("#".repeat(60))
		elif y < 39:
			rows.append(".".repeat(30) + "#" + ".".repeat(29))
		else:
			rows.append("X".repeat(60))
	var w := _world(rows)
	w.support_budget = 64
	var detached: Array = []
	w.piece_detached.connect(func(p: Dictionary) -> void: detached.append(p))
	w.apply_damage(DKDamage.rect(Vector2(240, 160), Vector2(8, 8), 99, &"blast", 1))
	w.tick()
	ok(detached.is_empty() and not w.support.is_idle(), "check still running")
	w.paint(DKDamage.rect(Vector2(0, 80), Vector2(8, 232), 0), &"dirt")  # new wall to the ground
	w.settle()
	eq(detached.size(), 0, "the new wall holds the slab: the restarted fill finds ground")


func test_fast_piece_never_tunnels_through_a_thin_floor() -> void:
	var rows: Array = []
	for y in 80:
		if y < 3:
			rows.append("..BBBB..")
		elif y == 70:
			rows.append("XXXXXXXX")
		elif y == 79:
			rows.append("XXXXXXXX")
		else:
			rows.append("........")
	var w := _world(rows)
	w.pieces.max_speed = 4 * DKPieces.SUB  # 4 cells per tick
	w.pieces.crush_max_power = 0
	w.check_all_support()
	w.settle()
	eq(w.grid.mat_index(Vector2i(2, 69)), w.materials.index_of(&"rubble"), "landed on the thin floor")
	eq(w.grid.mat_index(Vector2i(2, 71)), 0, "nothing below the floor")


func test_piece_lost_when_world_bottom_is_open() -> void:
	var w := _world(["..BB", "..BB", "....", "...."])
	w.grid.outside_solid = false
	w.bottom_is_ground = false
	var lost: Array = []
	w.piece_lost.connect(func(p: Dictionary) -> void: lost.append(p))
	w.check_all_support()
	w.settle()
	eq(lost.size(), 1, "fell out of the grid")
	eq(w.grid.solid_count(), 0, "nothing written back")


func test_cells_damage_shape_dedupes_and_sorts() -> void:
	var w := _world(["####", "####"])
	var r := w.apply_damage(DKDamage.cells(PackedInt32Array([5, 1, 5, 99, -1]), 99, &"crush", 4))
	eq(r.destroyed, PackedInt32Array([1, 5]), "valid unique cells in order")
	eq(r.instigator_id, 4, "instigator")


func _decor_mats() -> DKMaterialSet:
	return DKMaterialSet.make([
		DKMaterial.make(&"dirt", 10, {"density": 2}),
		DKMaterial.make(&"wallpaper", 5, {"solid": false, "falls": false}),
		DKMaterial.make(&"bedrock", 1, {"anchor": true, "falls": false}),
	])


func _decor_world(rows: Array) -> DKWorld:
	var w := make_world((rows[0] as String).length(), rows.size(), _decor_mats())
	w.load_rows(PackedStringArray(rows), {"#": &"dirt", "w": &"wallpaper", "X": &"bedrock"})
	w.flush()
	return w


func test_non_solid_decor_neither_supports_nor_falls() -> void:
	# A dirt block hangs from bedrock only through background wallpaper.
	var w := _decor_world([
		"XXXXXXXX",
		"...ww...",
		"...ww...",
		"..####..",
		"........",
		"........",
		"........",
		"XXXXXXXX",
	])
	var detached: Array = []
	w.piece_detached.connect(func(p: Dictionary) -> void: detached.append(p))
	w.check_all_support()
	w.tick()
	eq(detached.size(), 1, "dirt is not held up by non-solid wallpaper")
	if detached.size() == 1:
		eq((detached[0]["cells"] as PackedInt32Array).size(), 4, "only the solid cells left")
	eq(w.grid.mat[w.grid.index(Vector2i(3, 1))], w.materials.index_of(&"wallpaper"), "wallpaper stays in place")
	w.settle()
	eq(w.grid.mat[w.grid.index(Vector2i(2, 6))], w.materials.index_of(&"dirt"), "dirt landed on the floor")


func test_piece_falling_through_decor_is_not_blocked_by_it() -> void:
	var w := _decor_world([
		"........",
		"..##....",
		"........",
		"..wwww..",
		"..wwww..",
		"........",
		"XXXXXXXX",
	])
	w.check_all_support()
	w.settle()
	eq(w.grid.mat[w.grid.index(Vector2i(2, 5))], w.materials.index_of(&"dirt"), "fell past wallpaper to the floor")


func test_ground_edges_anchor_side_walls() -> void:
	var rows := [
		"........",
		"########",
		"........",
		"........",
		"........",
		"XXXXXXXX",
	]
	var w := _decor_world(rows)
	var detached: Array = []
	w.piece_detached.connect(func(p: Dictionary) -> void: detached.append(p))
	w.ground_edges = DKSupport.EDGE_LEFT
	w.check_all_support()
	w.tick()
	ok(detached.is_empty(), "beam touching the left edge is grounded")
	w.apply_damage(DKDamage.cells(PackedInt32Array([w.grid.index(Vector2i(3, 1))]), 99, &"blast", 2))
	w.tick()
	eq(detached.size(), 1, "the part cut off from the left edge falls")
	eq(int(detached[0]["instigator_id"]), 2, "credited to the cutter")


func test_hold_ticks_delay_the_fall() -> void:
	var w := _decor_world([
		"..##....",
		"........",
		"........",
		"........",
		"XXXXXXXX",
	])
	w.pieces.hold_ticks = 5
	var moved: Array = []
	w.piece_moved.connect(func(p: Dictionary, _a: Rect2i, _b: Rect2i) -> void: moved.append(w.tick_count))
	w.check_all_support()
	for i in 5:  # the detach tick counts as the first hold tick
		w.tick()
	ok(moved.is_empty(), "piece holds still during hold_ticks")
	w.tick()
	eq(moved.size(), 1, "moves on the tick right after the hold")
	for i in 10:
		w.tick()
	ok(not moved.is_empty(), "then falls")
	var a := w.state_digest()
	var s := w.snapshot()
	ok(w.restore(s), "restored")
	eq(w.state_digest(), a, "hold survives snapshot round-trip")
