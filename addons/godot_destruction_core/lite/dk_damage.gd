class_name DKDamage
extends RefCounted
## A damage (or paint) request: shape + power + type + who caused it.
## Every request carries an instigator id: there is no global "player", so
## local co-op and AI sources are attributed the same way. 0 = environment.

enum Shape { CIRCLE, RECT, LINE, CELL, CELLS }

var shape: Shape = Shape.CIRCLE
## World position (circle centre, rect corner, line start, cell point).
var pos := Vector2.ZERO
var radius := 0.0
var size := Vector2.ZERO
var to := Vector2.ZERO
var width := 0.0
## Explicit cell indices (Shape.CELLS), e.g. the cells under a landing piece.
var cell_list := PackedInt32Array()
## Integer power subtracted from cell hp (after resistance).
var power := 1
var type: StringName = &"blast"
## Power at the edge of a circle in percent of `power` (100 = flat).
var falloff_min_pct := 100
var instigator_id := 0
## Free-form tag for game code (weapon id, etc.).
var tag: StringName = &""


static func circle(p_pos: Vector2, p_radius: float, p_power: int, p_type := &"blast", p_instigator := 0) -> DKDamage:
	var d := DKDamage.new()
	d.shape = Shape.CIRCLE
	d.pos = p_pos
	d.radius = p_radius
	d.power = p_power
	d.type = p_type
	d.instigator_id = p_instigator
	return d


static func rect(p_pos: Vector2, p_size: Vector2, p_power: int, p_type := &"blast", p_instigator := 0) -> DKDamage:
	var d := DKDamage.new()
	d.shape = Shape.RECT
	d.pos = p_pos
	d.size = p_size
	d.power = p_power
	d.type = p_type
	d.instigator_id = p_instigator
	return d


static func line(p_from: Vector2, p_to: Vector2, p_width: float, p_power: int, p_type := &"pierce", p_instigator := 0) -> DKDamage:
	var d := DKDamage.new()
	d.shape = Shape.LINE
	d.pos = p_from
	d.to = p_to
	d.width = p_width
	d.power = p_power
	d.type = p_type
	d.instigator_id = p_instigator
	return d


static func cell(p_pos: Vector2, p_power: int, p_type := &"dig", p_instigator := 0) -> DKDamage:
	var d := DKDamage.new()
	d.shape = Shape.CELL
	d.pos = p_pos
	d.power = p_power
	d.type = p_type
	d.instigator_id = p_instigator
	return d


## Damage to an explicit list of cell indices (crush under a landed piece).
static func cells(p_cells: PackedInt32Array, p_power: int, p_type := &"crush", p_instigator := 0) -> DKDamage:
	var d := DKDamage.new()
	d.shape = Shape.CELLS
	d.cell_list = p_cells.duplicate()
	d.power = p_power
	d.type = p_type
	d.instigator_id = p_instigator
	return d


func with_falloff(min_pct: int) -> DKDamage:
	falloff_min_pct = clampi(min_pct, 0, 100)
	return self
