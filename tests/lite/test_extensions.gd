extends DKTest
## DKWorld extension hook: extension state rides along in snapshot(),
## restore() and state_digest().


class Counter extends RefCounted:
	var n := 0
	func snapshot_state() -> Dictionary:
		return {"n": n}
	func restore_state(d: Dictionary) -> bool:
		n = int(d["n"])
		return true
	func digest() -> String:
		return str(n)


func test_extension_state_in_snapshot_and_digest() -> void:
	var world := DKFixtures.filled(self, 16, 8, &"dirt")
	var d0 := world.state_digest()
	var a := Counter.new()
	var b := Counter.new()
	world.add_extension(&"b", b)
	world.add_extension(&"a", a)
	eq(world.get_extension(&"a"), a, "lookup")
	eq(world.get_extension(&"zzz"), null, "unknown")
	var d1 := world.state_digest()
	ok(d1 != d0, "extensions enter the digest")
	var snap := world.snapshot()
	a.n = 5
	ok(world.state_digest() != d1, "extension change changes the digest")
	ok(world.restore(snap), "restore")
	eq(a.n, 0, "extension state restored")
	eq(world.state_digest(), d1, "digest back")
	world.remove_extension(a)
	world.remove_extension(b)
	eq(world.state_digest(), d0, "removed")
