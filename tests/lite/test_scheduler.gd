extends DKTest


func test_count_budget_fifo_and_overflow() -> void:
	var s := DKScheduler.new()
	var seen: Array = []
	s.add_queue(&"q", func(x: Variant) -> void: seen.append(x), 3)
	for i in 8:
		s.push(&"q", i)
	var r := s.tick()
	eq(r[&"q"], 3, "3 per tick")
	eq(seen, [0, 1, 2], "FIFO")
	eq(r["overflow"], {&"q": 5}, "overflow reported")
	s.tick()
	r = s.tick()
	eq(seen, [0, 1, 2, 3, 4, 5, 6, 7], "all processed in order")
	ok((r["overflow"] as Dictionary).is_empty(), "no overflow at the end")
	eq(s.stats(&"q")["processed"], 8, "stats")
	eq(s.stats(&"q")["overflow_ticks"], 2, "two ticks overflowed")


func test_dedupe() -> void:
	var s := DKScheduler.new()
	var seen: Array = []
	s.add_queue(&"q", func(x: Variant) -> void: seen.append(x), 10)
	ok(s.push(&"q", Vector2i(1, 1)), "first push")
	ok(not s.push(&"q", Vector2i(1, 1)), "duplicate refused")
	ok(s.push(&"q", Vector2i(1, 1), false), "dedupe off allows it")
	s.tick()
	eq(seen.size(), 2, "two items")
	ok(s.push(&"q", Vector2i(1, 1)), "can push again after processing")


func test_queues_run_in_registration_order() -> void:
	var s := DKScheduler.new()
	var log: Array = []
	s.add_queue(&"b", func(x: Variant) -> void: log.append("b%s" % x), 5)
	s.add_queue(&"a", func(x: Variant) -> void: log.append("a%s" % x), 5)
	s.push(&"a", 1)
	s.push(&"b", 1)
	s.tick()
	eq(log, ["b1", "a1"], "registration order, not name order")


func test_deterministic_mode_ignores_time_budget() -> void:
	var s := DKScheduler.new()
	var n: Array = [0]
	s.add_queue(&"slow", func(_x: Variant) -> void:
		OS.delay_usec(300)
		n[0] += 1, 5, 100)
	for i in 10:
		s.push(&"slow", i)
	s.tick()
	eq(n[0], 5, "count budget only, even though the time budget ran out")


func test_time_budget_in_cosmetic_mode() -> void:
	var s := DKScheduler.new()
	s.deterministic = false
	var n: Array = [0]
	s.add_queue(&"slow", func(_x: Variant) -> void:
		OS.delay_usec(2000)
		n[0] += 1, 50, 1000)
	for i in 10:
		s.push(&"slow", i)
	s.tick()
	ok(n[0] >= 1 and n[0] < 10, "time budget stops early but makes progress (%d)" % n[0])


func test_flush_and_clear() -> void:
	var s := DKScheduler.new()
	var n: Array = [0]
	s.add_queue(&"q", func(_x: Variant) -> void: n[0] += 1, 1)
	for i in 6:
		s.push(&"q", i)
	s.flush()
	eq(n[0], 6, "flush ignores budgets")
	for i in 3:
		s.push(&"q", i)
	s.clear()
	eq(s.total_pending(), 0, "cleared")
	ok(s.push(&"q", 0), "dedupe keys cleared too")
