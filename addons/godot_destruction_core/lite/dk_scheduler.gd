class_name DKScheduler
extends RefCounted
## Budgeted per-tick work queues. Expensive follow-up work (collision and
## render rebuilds, support checks, ...) is queued and spread over ticks so a
## big blast never spikes one frame.
##
## Each queue has a COUNT budget (items per tick) and an optional TIME budget
## in microseconds. Count budgets are deterministic. Time budgets depend on the
## machine, so they only apply when `deterministic` is false and should be
## used for cosmetic work only (never for anything that changes gameplay).

## When true (default), time budgets are ignored: same input, same result.
var deterministic := true

var _order: Array[StringName] = []
var _queues: Dictionary = {}  # name -> {fn, count, usec, items, keys, stats}


## Registers a queue. `fn(item)` processes one item.
func add_queue(queue_name: StringName, fn: Callable, count_budget: int, usec_budget: int = 0) -> void:
	assert(not _queues.has(queue_name), "DKScheduler: queue exists: %s" % queue_name)
	_order.append(queue_name)
	_queues[queue_name] = {"fn": fn, "count": maxi(count_budget, 1), "usec": maxi(usec_budget, 0),
		"items": [], "keys": {}, "processed": 0, "overflow_ticks": 0, "last_tick": 0}


func has_queue(queue_name: StringName) -> bool:
	return _queues.has(queue_name)


func set_budget(queue_name: StringName, count_budget: int, usec_budget: int = 0) -> void:
	var q: Dictionary = _queues[queue_name]
	q["count"] = maxi(count_budget, 1)
	q["usec"] = maxi(usec_budget, 0)


## Adds an item (FIFO). If `dedupe` is true, an item already waiting is not
## added again. Returns true if added.
func push(queue_name: StringName, item: Variant, dedupe := true) -> bool:
	var q: Dictionary = _queues[queue_name]
	if dedupe:
		if (q["keys"] as Dictionary).has(item):
			return false
		q["keys"][item] = true
	(q["items"] as Array).append(item)
	return true


func pending(queue_name: StringName) -> int:
	return (_queues[queue_name]["items"] as Array).size()


func total_pending() -> int:
	var n := 0
	for k in _order:
		n += pending(k)
	return n


## Processes each queue (in registration order) within its budget.
## Returns {queue_name: processed_this_tick}; queues left with work are listed
## in `overflow` (name -> pending).
func tick() -> Dictionary:
	var done: Dictionary = {}
	var overflow: Dictionary = {}
	for qn in _order:
		var q: Dictionary = _queues[qn]
		var items: Array = q["items"]
		var keys: Dictionary = q["keys"]
		var limit: int = q["count"]
		var usec: int = q["usec"]
		var t0 := Time.get_ticks_usec()
		var n := 0
		while n < limit and not items.is_empty():
			if usec > 0 and not deterministic and n > 0 and Time.get_ticks_usec() - t0 >= usec:
				break
			var item: Variant = items.pop_front()
			keys.erase(item)
			(q["fn"] as Callable).call(item)
			n += 1
		q["processed"] = int(q["processed"]) + n
		q["last_tick"] = n
		done[qn] = n
		if not items.is_empty():
			q["overflow_ticks"] = int(q["overflow_ticks"]) + 1
			overflow[qn] = items.size()
	done["overflow"] = overflow
	return done


## Runs everything now, ignoring budgets (loading screens, tests).
func flush() -> void:
	for qn in _order:
		var q: Dictionary = _queues[qn]
		var items: Array = q["items"]
		while not items.is_empty():
			var item: Variant = items.pop_front()
			(q["keys"] as Dictionary).erase(item)
			(q["fn"] as Callable).call(item)
			q["processed"] = int(q["processed"]) + 1


func clear() -> void:
	for qn in _order:
		(_queues[qn]["items"] as Array).clear()
		(_queues[qn]["keys"] as Dictionary).clear()


func stats(queue_name: StringName) -> Dictionary:
	var q: Dictionary = _queues[queue_name]
	return {"pending": (q["items"] as Array).size(), "processed": q["processed"],
		"overflow_ticks": q["overflow_ticks"], "last_tick": q["last_tick"],
		"count_budget": q["count"], "usec_budget": q["usec"]}
