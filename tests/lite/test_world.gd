extends DKTest
## DKWorld: API, signals, budgets, instigators, snapshot/restore, determinism.


func test_apply_damage_emits_signals() -> void:
	var w := DKFixtures.filled(self, 16, 16, &"dirt")
	var got := {"damaged": 0, "destroyed": 0}
	w.cells_damaged.connect(func(_r: DKReport) -> void: got["damaged"] += 1)
	w.cells_destroyed.connect(func(_r: DKReport) -> void: got["destroyed"] += 1)
	var r := w.apply_damage(DKDamage.circle(Vector2(64, 64), 16.0, 5))
	eq(r.destroyed.size(), 0, "dirt (10 hp) survives 5")
	eq(got, {"damaged": 1, "destroyed": 0}, "only cells_damaged")
	w.apply_damage(DKDamage.circle(Vector2(64, 64), 16.0, 5))
	eq(got, {"damaged": 2, "destroyed": 1}, "second hit destroys")
	w.apply_damage(DKDamage.circle(Vector2(-900, 0), 4.0, 5))
	eq(got["damaged"], 2, "no signal when nothing was hit")


func test_detonate_without_router_is_immediate() -> void:
	var w := DKFixtures.filled(self, 16, 16, &"dirt")
	var fired: Array = []
	w.detonated.connect(func(det: Dictionary, rep: DKReport) -> void: fired.append([det["pos"], rep.destroyed.size()]))
	var det := w.detonate(Vector2(64, 64), 20.0, 50, &"blast", 3, 10)
	eq(fired.size(), 1, "fired now, fuse ignored in the core")
	ok((det["report"] as DKReport).destroyed.size() > 0, "report attached")
	ok(not w.is_solid_at(Vector2(64, 64)), "hole at the centre")
	eq(w.material_at(Vector2(64, 64)), &"empty", "air")
	eq(w.material_at(Vector2(2, 2)), &"dirt", "far cell untouched")
	eq(w.material_at(Vector2(-5, 2)), &"", "outside grid")
	eq(w.instigator_stats[3]["detonations"], 1, "detonation counted for instigator 3")


func test_paint_signal_and_queries() -> void:
	var w := DKFixtures.filled(self, 8, 8, &"dirt")
	var got: Array = []
	w.cells_painted.connect(func(_s: DKDamage, id: StringName, n: int) -> void: got.append([id, n]))
	var n := w.paint(DKDamage.rect(Vector2.ZERO, Vector2(16, 16), 0), &"steel")
	eq(n, 4, "2x2 cells")
	eq(got, [[&"steel", 4]], "signal")
	eq(w.material_at(Vector2(4, 4)), &"steel", "painted")


func test_rebuild_requests_respect_budget() -> void:
	var w := DKFixtures.filled(self, 64, 64, &"dirt")  # 8x8 chunks of 8 cells
	w.rebuild_budget = 3
	w.scheduler.set_budget(DKWorld.Q_REBUILD, 3)
	var per_tick: Array = []
	var count: Array = [0]
	w.chunk_rebuild_requested.connect(func(_c: Vector2i) -> void: count[0] += 1)
	var overflows: Array = []
	w.budget_overflow.connect(func(q: StringName, p: int) -> void: overflows.append([q, p]))
	w.apply_damage(DKDamage.circle(Vector2(256, 256), 200.0, 99))
	var total_dirty := w.scheduler.pending(DKWorld.Q_REBUILD)
	ok(total_dirty > 6, "big blast dirtied many chunks (%d)" % total_dirty)
	while w.scheduler.total_pending() > 0:
		var before: int = count[0]
		w.tick()
		per_tick.append(count[0] - before)
	for n in per_tick:
		ok(n <= 3, "never more than the budget per tick")
	eq(count[0], total_dirty, "every dirty chunk requested exactly once")
	ok(overflows.size() > 0 and overflows[0][0] == DKWorld.Q_REBUILD, "overflow signalled")


func test_multiple_instigators_are_attributed() -> void:
	# Local co-op: two players and the environment damage the same world.
	var w := DKFixtures.filled(self, 32, 16, &"dirt")
	var reports: Array = []
	w.cells_destroyed.connect(func(r: DKReport) -> void: reports.append(r))
	var r1 := w.apply_damage(DKDamage.circle(Vector2(40, 64), 20.0, 99, &"blast", 1))
	var r2 := w.apply_damage(DKDamage.circle(Vector2(200, 64), 12.0, 99, &"blast", 2))
	var r_env := w.apply_damage(DKDamage.rect(Vector2(120, 0), Vector2(16, 16), 99, &"crush"))
	# Overlap: player 2 hits cells player 1 already cleared plus new ones.
	var r2b := w.apply_damage(DKDamage.circle(Vector2(56, 64), 20.0, 99, &"blast", 2))
	eq(r1.instigator_id, 1, "report carries instigator 1")
	eq(r2.instigator_id, 2, "report carries instigator 2")
	eq(r_env.instigator_id, 0, "environment is 0")
	eq(w.instigator_stats[1]["destroyed"], r1.destroyed.size(), "p1 total")
	eq(w.instigator_stats[2]["destroyed"], r2.destroyed.size() + r2b.destroyed.size(), "p2 total")
	eq(w.instigator_stats[0]["destroyed"], r_env.destroyed.size(), "env total")
	var overlap := 0
	for i in r2b.destroyed:
		if r1.destroyed.has(i):
			overlap += 1
	eq(overlap, 0, "a cell is credited to whoever destroyed it first, never twice")
	var all_ids: Array = []
	for r: DKReport in reports:
		all_ids.append(r.instigator_id)
	eq(all_ids, [1, 2, 0, 2], "signals in call order with their instigators")


func test_snapshot_restore_roundtrip() -> void:
	var w := DKFixtures.filled(self, 32, 32, &"rock")
	DKFixtures.run_script(w, 11, 30)
	var snap := w.snapshot()
	var h := w.state_hash()
	var stats: Dictionary = w.instigator_stats.duplicate(true)
	DKFixtures.run_script(w, 12, 30)
	ok(w.state_hash() != h, "world changed")
	ok(w.restore(snap), "restore ok")
	eq(w.state_hash(), h, "hash back to snapshot")
	eq(w.instigator_stats, stats, "stats restored")
	ok(not w.restore(PackedByteArray([1, 2, 3])), "garbage rejected")
	ok(not w.restore(var_to_bytes({"v": 1, "grid": {"v": 1, "w": 2, "h": 2}})), "wrong size rejected")
	eq(w.state_hash(), h, "failed restore changed nothing")


func test_replay_after_restore_is_identical() -> void:
	var w := DKFixtures.filled(self, 32, 32, &"dirt")
	DKFixtures.run_script(w, 5, 20)
	var snap := w.snapshot()
	DKFixtures.run_script(w, 6, 40)
	var end_a := w.state_digest()
	w.restore(snap)
	DKFixtures.run_script(w, 6, 40)
	eq(w.state_digest(), end_a, "same commands after restore -> same end state")


func test_two_worlds_same_script_same_hash() -> void:
	var a := DKFixtures.filled(self, 40, 30, &"rock")
	var b := DKFixtures.filled(self, 40, 30, &"rock")
	DKFixtures.run_script(a, 99, 80)
	DKFixtures.run_script(b, 99, 80)
	eq(a.state_digest(), b.state_digest(), "deterministic")
	eq(a.tick_count, b.tick_count, "same ticks")
	eq(a.instigator_stats, b.instigator_stats, "same per-instigator attribution")
	ok(a.instigator_stats.size() >= 3, "script used several instigators")
	var c := DKFixtures.filled(self, 40, 30, &"rock")
	DKFixtures.run_script(c, 100, 80)
	ok(a.state_digest() != c.state_digest(), "different script, different state")


func test_tick_counts_and_signal() -> void:
	var w := DKFixtures.filled(self, 8, 8, &"dirt")
	var ticks: Array = []
	w.ticked.connect(func(t: int) -> void: ticks.append(t))
	w.tick()
	w.tick()
	eq(ticks, [1, 2], "ticked signal")
	eq(w.tick_count, 2, "tick count")
