class_name DKWorld
extends Node2D
## Game-facing node: owns the cell grid and the budgeted scheduler, exposes
## the damage API and emits signals. Adapters (render, collision, debris,
## feel) listen to the signals; they never own state.
##
## Collapse (Lite): destroyed cells seed an incremental, budgeted support
## check (DKSupport). Regions no longer connected to an anchor are lifted out
## as falling pieces (DKPieces) that land as rubble and crush what they hit;
## the crush damage carries the instigator id of whoever cut them loose.
##
## Positions in this API are in the DKWorld node's LOCAL space (put the node
## at the level origin, or convert with to_local()).
##
## Detonations: in the core a detonation fires immediately. An optional
## "detonation router" (the Pro chain module) can take them over to add fuses,
## chains and budgets. The core only knows the duck-typed router interface:
##   route_detonation(det: Dictionary) -> Dictionary
##   world_tick() -> void
##   snapshot_state() -> Dictionary ; restore_state(d: Dictionary) -> bool
##   digest() -> String

signal cells_damaged(report: DKReport)
signal cells_destroyed(report: DKReport)
signal cells_painted(shape: DKDamage, material_id: StringName, count: int)
signal detonated(det: Dictionary, report: DKReport)
signal chunk_rebuild_requested(chunk: Vector2i)
signal budget_overflow(queue_name: StringName, pending: int)
signal ticked(tick: int)
## A region lost its support and was lifted out of the grid as a piece.
signal piece_detached(piece: Dictionary)
## A falling piece moved this tick (pixel rects, local space). Use it to crush
## game entities under the piece (piece["instigator_id"] = who caused it).
signal piece_moved(piece: Dictionary, from_rect: Rect2, to_rect: Rect2)
## A piece hit the ground and was written back. `crush` is the damage applied
## to the cells below it (power 0 = soft landing), `impact` its speed (1/256 cells/tick).
signal piece_landed(piece: Dictionary, crush: DKDamage, impact: int)
## A piece fell out of the grid (only when grid.outside_solid is false).
signal piece_lost(piece: Dictionary)

## Addon version (matches plugin.cfg).
const VERSION := "0.2.2"
const Q_REBUILD := &"rebuild"
const SNAPSHOT_VERSION := 2

@export var materials: DKMaterialSet
@export var grid_size := Vector2i(64, 32)
@export var cell_px := 8
@export var chunk_cells := 16
## Chunk rebuild requests per tick (count budget: deterministic).
@export var rebuild_budget := 4
## Tick automatically in _physics_process. Turn off to step manually.
@export var auto_tick := true
## Unsupported regions fall (DKSupport + DKPieces).
@export var collapse_enabled := true
## Support-check cell visits per tick (deterministic count budget).
@export var support_budget := 4096
## Solid cells on the bottom row count as ground.
@export var bottom_is_ground := true
## Other grid edges that count as ground (DKSupport.EDGE_LEFT | EDGE_RIGHT | EDGE_TOP).
@export var ground_edges := 0

var grid: DKCellGrid
var scheduler: DKScheduler
var support: DKSupport
var pieces: DKPieces
var tick_count := 0
## Per-instigator totals: {id: {"destroyed": n, "damaged": n, "detonations": n}}.
var instigator_stats: Dictionary = {}

var _router: Object = null
## Extension modules with their own state (e.g. Pro fire): [[name, object]],
## sorted by name. Each provides snapshot_state() -> Dictionary,
## restore_state(d) -> bool and digest() -> String; the world includes them
## in snapshot(), restore() and state_digest().
var _extensions: Array = []


func _ready() -> void:
	if grid == null and materials != null:
		setup(grid_size.x, grid_size.y, cell_px, chunk_cells, materials)


func _physics_process(_delta: float) -> void:
	if auto_tick and grid != null:
		tick()


## Creates the grid. Call before use when not configured in the inspector.
func setup(w: int, h: int, p_cell_px: int, p_chunk_cells: int, p_materials: DKMaterialSet) -> void:
	materials = p_materials
	grid_size = Vector2i(w, h)
	cell_px = p_cell_px
	chunk_cells = p_chunk_cells
	grid = DKCellGrid.new()
	grid.setup(w, h, p_cell_px, p_chunk_cells, p_materials)
	scheduler = DKScheduler.new()
	scheduler.add_queue(Q_REBUILD, func(c: Vector2i) -> void: chunk_rebuild_requested.emit(c), rebuild_budget)
	support = DKSupport.new()
	support.setup(grid)
	support.budget = support_budget
	support.bottom_is_ground = bottom_is_ground
	support.ground_edges = ground_edges
	pieces = DKPieces.new()
	pieces.setup(grid)
	tick_count = 0
	instigator_stats.clear()


## Fills the grid from text rows (`legend`: character -> material id) and
## requests a rebuild of every chunk.
func load_rows(rows: PackedStringArray, legend: Dictionary) -> void:
	grid.load_rows(rows, legend)
	grid.mark_all_dirty()
	support.reset()
	pieces.clear()
	_enqueue_dirty()


## Installs (or removes with null) the detonation router.
func set_detonation_router(router: Object) -> void:
	_router = router


func add_extension(ext_name: StringName, obj: Object) -> void:
	remove_extension(obj)
	_extensions.append([ext_name, obj])
	_extensions.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))


func remove_extension(obj: Object) -> void:
	for k in range(_extensions.size() - 1, -1, -1):
		if _extensions[k][1] == obj:
			_extensions.remove_at(k)


func get_extension(ext_name: StringName) -> Object:
	for e: Array in _extensions:
		if e[0] == ext_name:
			return e[1]
	return null


func get_detonation_router() -> Object:
	return _router


# — Ticking —

## One fixed step: router (if any) fires due detonations, then the scheduler
## runs its budgets.
func tick() -> void:
	tick_count += 1
	if _router != null:
		_router.world_tick()
	if collapse_enabled:
		_step_collapse()
	_enqueue_dirty()
	var res := scheduler.tick()
	var overflow: Dictionary = res["overflow"]
	for qn: StringName in overflow:
		budget_overflow.emit(qn, int(overflow[qn]))
	ticked.emit(tick_count)


## Runs all queued work now (loading, tests).
func flush() -> void:
	_enqueue_dirty()
	scheduler.flush()


# — Damage API —

func apply_damage(d: DKDamage) -> DKReport:
	var rep := grid.apply(d)
	_account(d.instigator_id, rep)
	if collapse_enabled and rep.destroyed.size() > 0:
		support.add_destroyed(rep.destroyed, d.instigator_id)
	if rep.damaged > 0:
		cells_damaged.emit(rep)
	if rep.destroyed.size() > 0:
		cells_destroyed.emit(rep)
	_enqueue_dirty()
	return rep


## Builds a detonation description (a plain Dictionary, easy to log/replay).
static func make_detonation(pos: Vector2, radius: float, power: int, type: StringName = &"blast",
		instigator_id: int = 0, fuse_ticks: int = 0) -> Dictionary:
	return {"pos": pos, "radius": radius, "power": power, "type": type,
		"instigator_id": instigator_id, "fuse_ticks": fuse_ticks, "falloff_min_pct": 100,
		"chain": -1, "depth": 0, "tag": &""}


## A blast. Without a router it fires now (fuse_ticks is ignored); with the
## Pro chain module installed it is scheduled with fuses and chain rules.
## Returns the detonation (with "report" set when it fired immediately).
func detonate(pos: Vector2, radius: float, power: int, type: StringName = &"blast",
		instigator_id: int = 0, fuse_ticks: int = 0) -> Dictionary:
	var det := make_detonation(pos, radius, power, type, instigator_id, fuse_ticks)
	if _router != null:
		return _router.route_detonation(det)
	det["report"] = execute_detonation(det)
	return det


## Fires a detonation right now (used by routers when a fuse runs out).
func execute_detonation(det: Dictionary) -> DKReport:
	var d := DKDamage.circle(det["pos"], float(det["radius"]), int(det["power"]),
		det.get("type", &"blast"), int(det.get("instigator_id", 0)))
	d.falloff_min_pct = int(det.get("falloff_min_pct", 100))
	d.tag = det.get("tag", &"")
	var st := _stats_for(d.instigator_id)
	st["detonations"] += 1
	var rep := apply_damage(d)
	detonated.emit(det, rep)
	return rep


## Fills a shape with a material. Returns the number of cells changed.
func paint(shape: DKDamage, material_id: StringName) -> int:
	var mi := materials.index_of(material_id)
	assert(mi >= 0, "DKWorld.paint: unknown material %s" % material_id)
	var covered := grid.cells_in(shape) if collapse_enabled else PackedInt32Array()
	var n := grid.paint(shape, mi)
	if collapse_enabled and n > 0:
		if materials.at(mi).solid and mi != 0:
			support.on_cells_added()
		else:
			support.add_destroyed(covered, shape.instigator_id)
	_enqueue_dirty()
	cells_painted.emit(shape, material_id, n)
	return n


# — Queries —

func is_solid_at(pos: Vector2) -> bool:
	return grid.is_solid(grid.world_to_cell(pos))


## Material id at a position (&"empty" for air, &"" outside the grid).
func material_at(pos: Vector2) -> StringName:
	var m := grid.material_at_cell(grid.world_to_cell(pos))
	return m.id if m != null else &""


# — Determinism: hash, snapshot, restore —

## SHA-256 over grid, tick and router state.
func state_digest() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(grid.digest().to_utf8_buffer())
	ctx.update(str(tick_count).to_utf8_buffer())
	if _router != null:
		ctx.update(str(_router.digest()).to_utf8_buffer())
	ctx.update(support.digest_bytes())
	ctx.update(pieces.digest_bytes())
	for e: Array in _extensions:
		ctx.update(("%s:%s" % [e[0], e[1].digest()]).to_utf8_buffer())
	return ctx.finish().hex_encode()


func state_hash() -> int:
	return state_digest().substr(0, 15).hex_to_int()


func snapshot() -> PackedByteArray:
	var s := {"v": SNAPSHOT_VERSION, "grid": grid.to_dict(), "tick": tick_count,
		"stats": instigator_stats.duplicate(true), "support": support.to_dict(),
		"pieces": pieces.to_dict()}
	if _router != null:
		s["router"] = _router.snapshot_state()
	if not _extensions.is_empty():
		var ext: Dictionary = {}
		for e: Array in _extensions:
			ext[String(e[0])] = e[1].snapshot_state()
		s["ext"] = ext
	return var_to_bytes(s)


## Restores a snapshot taken from this world (same size and material set).
## Pending scheduler work is dropped and every chunk is re-requested.
func restore(bytes: PackedByteArray) -> bool:
	if bytes.size() < 8:
		return false
	var s: Variant = bytes_to_var(bytes)
	if typeof(s) != TYPE_DICTIONARY or int((s as Dictionary).get("v", -1)) != SNAPSHOT_VERSION:
		return false
	if not grid.from_dict(s["grid"]):
		return false
	if not support.from_dict(s.get("support", {})) or not pieces.from_dict(s.get("pieces", {})):
		return false
	if _router != null and (s as Dictionary).has("router"):
		if not _router.restore_state(s["router"]):
			return false
	var ext: Dictionary = (s as Dictionary).get("ext", {})
	for e: Array in _extensions:
		if ext.has(String(e[0])) and not e[1].restore_state(ext[String(e[0])]):
			return false
	tick_count = int(s["tick"])
	instigator_stats = (s["stats"] as Dictionary).duplicate(true)
	scheduler.clear()
	_enqueue_dirty()
	return true


## Settles the whole level: every solid cell is checked for support
## (use after loading a level that may contain floating parts).
func check_all_support(instigator_id: int = 0) -> void:
	support.check_all(instigator_id)


## Ticks until no support work and no falling pieces are left (tests,
## loading). Returns the ticks used.
func settle(max_ticks: int = 2000) -> int:
	var t := 0
	while t < max_ticks and (not support.is_idle() or not pieces.pieces.is_empty()):
		tick()
		t += 1
	return t


# — internals —

func _step_collapse() -> void:
	support.budget = support_budget
	support.bottom_is_ground = bottom_is_ground
	support.ground_edges = ground_edges
	for region in support.step():
		for p in pieces.extract(region["cells"], int(region["instigator_id"])):
			piece_detached.emit(p)
	var res := pieces.step()
	for m in res["moved"]:
		piece_moved.emit(m[0], m[1], m[2])
	for p in res["lost"]:
		piece_lost.emit(p)
	for l in res["landed"]:
		var p: Dictionary = l[0]
		var impact: int = l[1]
		var wb := pieces.write_back(p, _rubble_of, impact)
		var inst := int(p["instigator_id"])
		support.add_cells(wb[0], inst)
		var crush := DKDamage.cells(wb[1], pieces.crush_power(p, impact), &"crush", inst)
		crush.tag = &"piece"
		if crush.power > 0 and not (wb[1] as PackedInt32Array).is_empty():
			apply_damage(crush)
		piece_landed.emit(p, crush, impact)


func _rubble_of(mat_i: int) -> int:
	var m := materials.at(mat_i)
	if m.rubble_into == &"":
		return mat_i
	var r := materials.index_of(m.rubble_into)
	return r if r >= 0 else mat_i


func _enqueue_dirty() -> void:
	if not grid.has_dirty():
		return
	for c in grid.take_dirty_chunks():
		scheduler.push(Q_REBUILD, c)


func _stats_for(id: int) -> Dictionary:
	if not instigator_stats.has(id):
		instigator_stats[id] = {"destroyed": 0, "damaged": 0, "detonations": 0}
	return instigator_stats[id]


func _account(id: int, rep: DKReport) -> void:
	if rep.damaged == 0:
		return
	var st := _stats_for(id)
	st["destroyed"] += rep.destroyed.size()
	st["damaged"] += rep.damaged
