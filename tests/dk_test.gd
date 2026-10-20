class_name DKTest
extends RefCounted
## Minimal assert base for the headless runner (no external test framework).

var assert_count := 0
var failures: Array[String] = []
var current := ""
var _nodes: Array[Node] = []


func before_each() -> void: pass
func after_each() -> void: pass


## Creates a DKWorld (not in a tree) and frees it after the test.
func make_world(w: int, h: int, mats: DKMaterialSet, cell_px := 8, chunk := 8) -> DKWorld:
	var world := DKWorld.new()
	world.auto_tick = false
	world.setup(w, h, cell_px, chunk, mats)
	_nodes.append(world)
	return world


## Frees `n` after the test. Returns it for chaining.
func track(n: Node) -> Node:
	_nodes.append(n)
	return n


## The running SceneTree (tests that need nodes inside the tree).
func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _cleanup() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func ok(cond: bool, msg: String) -> void:
	assert_count += 1
	if not cond:
		failures.append("[%s] %s" % [current, msg])


func eq(got: Variant, want: Variant, msg: String) -> void:
	assert_count += 1
	if typeof(got) != typeof(want) and not (typeof(got) in [TYPE_INT, TYPE_FLOAT] and typeof(want) in [TYPE_INT, TYPE_FLOAT]):
		failures.append("[%s] %s: got %s (%s), want %s (%s)" % [current, msg, got, type_string(typeof(got)), want, type_string(typeof(want))])
	elif got != want:
		failures.append("[%s] %s: got %s, want %s" % [current, msg, got, want])
