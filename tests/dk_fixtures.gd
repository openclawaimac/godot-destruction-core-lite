class_name DKFixtures
extends RefCounted
## Shared test materials and helpers.


static func materials() -> DKMaterialSet:
	return DKMaterialSet.make([
		DKMaterial.make(&"dirt", 10, {"density": 2, "strength": 5}),
		DKMaterial.make(&"rock", 30, {"density": 3, "strength": 20, "resist": {&"blast": 50}}),
		DKMaterial.make(&"steel", 50, {"density": 5, "strength": 50, "resist": {&"blast": 100, &"pierce": 20}}),
		DKMaterial.make(&"bedrock", 1, {"anchor": true, "falls": false}),
		DKMaterial.make(&"fuel", 5, {"blast_radius": 20.0, "blast_power": 40}),
		DKMaterial.make(&"glass", 1, {"solid": true}),
	])


static func legend() -> Dictionary:
	return {"#": &"dirt", "R": &"rock", "S": &"steel", "X": &"bedrock", "F": &"fuel", "G": &"glass"}


## A w×h world filled with one material (8 px cells, 8-cell chunks).
static func filled(t: DKTest, w: int, h: int, mat_id: StringName) -> DKWorld:
	var world := t.make_world(w, h, materials())
	var rows := PackedStringArray()
	var ch := ""
	for k: String in legend():
		if legend()[k] == mat_id:
			ch = k
	for y in h:
		rows.append(ch.repeat(w))
	world.load_rows(rows, legend())
	world.flush()
	return world


## A scripted sequence of mixed ops driven by a seeded RNG (for determinism tests).
static func run_script(world: DKWorld, seed_value: int, steps: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var size := Vector2(world.grid.width * world.cell_px, world.grid.height * world.cell_px)
	for i in steps:
		var p := Vector2(rng.randf_range(0, size.x), rng.randf_range(0, size.y))
		var who := rng.randi_range(1, 3)
		match rng.randi_range(0, 4):
			0: world.apply_damage(DKDamage.circle(p, rng.randf_range(4, 40), rng.randi_range(1, 30), &"blast", who).with_falloff(rng.randi_range(20, 100)))
			1: world.apply_damage(DKDamage.rect(p, Vector2(rng.randf_range(4, 30), rng.randf_range(4, 30)), rng.randi_range(1, 30), &"dig", who))
			2: world.apply_damage(DKDamage.line(p, p + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60)), 6.0, 15, &"pierce", who))
			3: world.paint(DKDamage.circle(p, rng.randf_range(4, 16), 0), [&"dirt", &"rock", &"fuel"][rng.randi_range(0, 2)])
			4: world.detonate(p, rng.randf_range(8, 30), rng.randi_range(5, 40), &"blast", who)
		if i % 3 == 0:
			world.tick()
