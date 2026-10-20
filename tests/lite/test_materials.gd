extends DKTest


func test_index_zero_is_empty_air() -> void:
	var s := DKFixtures.materials()
	eq(s.at(0).id, &"empty", "index 0 is empty")
	ok(not s.at(0).solid, "air is not solid")
	eq(s.index_of(&"dirt"), 1, "first material gets index 1")
	eq(s.index_of(&"nope"), -1, "unknown id")
	eq(s.size(), 7, "6 materials + air")


func test_resistance_is_integer_percent() -> void:
	var s := DKFixtures.materials()
	var rock := s.at(s.index_of(&"rock"))
	eq(rock.damage_after_resist(30, &"blast"), 15, "50% blast resist")
	eq(rock.damage_after_resist(31, &"blast"), 15, "integer division floors")
	eq(rock.damage_after_resist(30, &"dig"), 30, "missing type = full damage")
	var steel := s.at(s.index_of(&"steel"))
	eq(steel.damage_after_resist(999, &"blast"), 0, "100% = immune")
	eq(steel.damage_after_resist(10, &"pierce"), 8, "20% pierce resist")
	var odd := DKMaterial.make(&"odd", 5, {"resist": {&"blast": 250, &"dig": -40}})
	eq(odd.damage_after_resist(10, &"blast"), 0, "resist clamped to 100")
	eq(odd.damage_after_resist(10, &"dig"), 10, "negative resist clamped to 0")


func test_make_sets_fields() -> void:
	var m := DKMaterial.make(&"x", 7, {"density": 4, "strength": 9, "anchor": true, "blast_radius": 12.0})
	eq(m.id, &"x", "id")
	eq(m.hp, 7, "hp")
	eq(m.density, 4, "density")
	eq(m.strength, 9, "strength")
	ok(m.anchor, "anchor")
	eq(m.blast_radius, 12.0, "blast radius")


func test_material_set_rebuilds_after_edit() -> void:
	var s := DKMaterialSet.make([DKMaterial.make(&"a", 1)])
	eq(s.index_of(&"a"), 1, "a")
	var list: Array[DKMaterial] = [DKMaterial.make(&"b", 1), DKMaterial.make(&"a", 1)]
	s.materials = list
	eq(s.index_of(&"b"), 1, "rebuilt: b first")
	eq(s.index_of(&"a"), 2, "rebuilt: a second")
