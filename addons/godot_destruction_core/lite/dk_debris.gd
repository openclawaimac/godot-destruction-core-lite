class_name DKDebris
extends Node2D
## Capped, deterministic debris pool (cosmetic). Bind it to a DKWorld and it
## spawns chips for destroyed cells and dust for landing pieces.
##
## - Hard cap: `capacity` particles in packed arrays; when full the oldest
##   slot is reused (ring buffer), so a huge blast never allocates.
## - Per-event cap: at most `max_per_event` particles per damage report.
## - Deterministic: velocities come from an integer hash of (cell, tick, k),
##   never from a global RNG, and the simulation is a fixed step; `digest()`
##   lets tests compare two runs.
## - `reduced_motion` spawns a fraction of the particles and no dust.
##
## Draw as part of the world (add as a child of the DKWorld so positions match).

@export var capacity := 600
@export var max_per_event := 120
## Gravity in px per tick².
@export var gravity := 0.35
## Lifetime in ticks.
@export var life_ticks := 70
@export var reduced_motion := false
## Fraction of particles kept with reduced motion (0..1).
@export var reduced_motion_scale := 0.25
## Step automatically in _physics_process.
@export var auto_step := true
## Particle size in px.
@export var chip_size := 2.0

const KIND_CHIP := 0
const KIND_DUST := 1

var world: DKWorld
var alive := 0
var spawned_total := 0

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedInt32Array()
var _kind := PackedByteArray()
var _color := PackedColorArray()
var _next := 0  # ring cursor


func _init() -> void:
	_alloc()


func _alloc() -> void:
	_pos.resize(capacity)
	_vel.resize(capacity)
	_life.resize(capacity)
	_kind.resize(capacity)
	_color.resize(capacity)
	_life.fill(0)
	alive = 0
	_next = 0


## Connects to the world's signals (destroyed cells, landings).
func bind_world(w: DKWorld) -> void:
	if world != null:
		world.cells_destroyed.disconnect(_on_destroyed)
		world.piece_landed.disconnect(_on_landed)
	world = w
	if capacity != _pos.size():
		_alloc()
	world.cells_destroyed.connect(_on_destroyed)
	world.piece_landed.connect(_on_landed)


func _physics_process(_delta: float) -> void:
	if auto_step:
		step()


## Advances all particles one tick.
func step() -> void:
	if alive == 0:
		return
	var n := 0
	for i in capacity:
		if _life[i] <= 0:
			continue
		_life[i] -= 1
		if _life[i] <= 0:
			continue
		n += 1
		var v := _vel[i]
		if _kind[i] == KIND_DUST:
			v *= 0.92
			v.y -= 0.02
		else:
			v.y += gravity
		var p := _pos[i] + v
		if _kind[i] == KIND_CHIP and world != null and world.is_solid_at(p):
			# Bounce off terrain: kill vertical speed, damp horizontal.
			v = Vector2(v.x * 0.5, -v.y * 0.25)
			p = _pos[i] + Vector2(v.x, 0)
			if world.is_solid_at(p):
				p = _pos[i]
				v = Vector2.ZERO
		_pos[i] = p
		_vel[i] = v
	alive = n
	queue_redraw()


## Spawns chips for the destroyed cells of a report (fling away from the
## centre of the destroyed area). Returns the number spawned.
func spawn_for_report(rep: DKReport) -> int:
	if world == null or rep.destroyed.is_empty():
		return 0
	var g := world.grid
	var centre := Vector2.ZERO
	for i in rep.destroyed:
		centre += g.cell_center(g.coord(i))
	centre /= rep.destroyed.size()
	var budget := max_per_event
	if reduced_motion:
		budget = int(budget * reduced_motion_scale)
	var made := 0
	var tick := world.tick_count
	for k in rep.destroyed.size():
		if made >= budget:
			break
		var i := rep.destroyed[k]
		var m := world.materials.at(rep.destroyed_mat[k])
		var count := m.debris_count
		if reduced_motion:
			count = mini(count, 1) if (_hash(i, tick, 99) % 4) == 0 else 0
		var cpos := g.cell_center(g.coord(i))
		for c in count:
			if made >= budget:
				break
			var h := _hash(i, tick, c)
			var dir := (cpos - centre)
			if dir.length_squared() < 0.01:
				dir = Vector2(0, -1)
			dir = dir.normalized()
			var spread := (float(h & 1023) / 1023.0 - 0.5) * 1.6
			var speed := 1.2 + float((h >> 10) & 1023) / 1023.0 * 2.8
			var v := dir.rotated(spread) * speed + Vector2(0, -1.6)
			var shade := 0.75 + float((h >> 20) & 255) / 255.0 * 0.35
			var col := Color(m.debris_color.r * shade, m.debris_color.g * shade, m.debris_color.b * shade, 1.0)
			_emit(cpos + Vector2(float((h >> 4) & 7) - 3.5, float((h >> 7) & 7) - 3.5), v, col, KIND_CHIP,
				life_ticks - int((h >> 12) & 15))
			made += 1
	return made


## Dust along the bottom of a landed piece.
func spawn_dust(piece: Dictionary, impact: int) -> int:
	if world == null or reduced_motion:
		return 0
	var r := world.pieces.piece_rect_px(piece)
	var n := clampi(int(piece["w"]) * impact / 256, 2, 24)
	var made := 0
	for k in n:
		var h := _hash(int(piece["id"]), world.tick_count, k)
		var x := r.position.x + float(h % 1000) / 1000.0 * r.size.x
		var v := Vector2((float((h >> 10) & 255) / 255.0 - 0.5) * 2.4, -0.2 - float((h >> 18) & 63) / 63.0 * 0.6)
		_emit(Vector2(x, r.end.y - 1.0), v, Color(0.85, 0.8, 0.7, 0.55), KIND_DUST, 40 + (h & 15))
		made += 1
	return made


## SHA-256 over the live particles (determinism checks).
func digest() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(PackedInt32Array([alive, spawned_total, _next]).to_byte_array())
	ctx.update(_life.to_byte_array())
	ctx.update(_pos.to_byte_array())
	return ctx.finish().hex_encode()


func clear() -> void:
	_life.fill(0)
	alive = 0
	queue_redraw()


func _draw() -> void:
	if alive == 0:
		return
	var s := Vector2(chip_size, chip_size)
	for i in capacity:
		if _life[i] <= 0:
			continue
		var p := _pos[i].floor()
		if _kind[i] == KIND_DUST:
			var a := clampf(float(_life[i]) / 40.0, 0.0, 1.0) * _color[i].a
			var rad := 1.0 + (40.0 - minf(float(_life[i]), 40.0)) * 0.08
			draw_rect(Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0).abs(), Color(_color[i], a))
		else:
			draw_rect(Rect2(p, s), _color[i])


# — internals —

func _on_destroyed(rep: DKReport) -> void:
	spawn_for_report(rep)


func _on_landed(piece: Dictionary, _crush: DKDamage, impact: int) -> void:
	spawn_dust(piece, impact)


func _emit(p: Vector2, v: Vector2, col: Color, kind: int, life: int) -> void:
	var i := _next
	_next = (_next + 1) % capacity
	if _life[i] <= 0:
		alive += 1
	_pos[i] = p
	_vel[i] = v
	_color[i] = col
	_kind[i] = kind
	_life[i] = maxi(life, 1)
	spawned_total += 1
	queue_redraw()


## 31-bit integer hash (xorshift-multiply), identical on every platform.
static func _hash(a: int, b: int, c: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h &= 0x7fffffff
	h = ((h >> 16) ^ h) * 0x45d9f3b & 0x7fffffff
	h = ((h >> 16) ^ h) * 0x45d9f3b & 0x7fffffff
	h = (h >> 16) ^ h
	return h & 0x7fffffff
