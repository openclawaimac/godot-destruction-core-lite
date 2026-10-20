class_name DKSupport
extends RefCounted
## Incremental, budgeted, unbounded connectivity ("is this still attached to
## the ground?"). Pure logic over a DKCellGrid.
##
## When cells are destroyed, their solid neighbours become *seeds*. Each seed
## starts a flood fill over solid cells (4-neighbourhood, depth first with
## "down" explored first so ground is usually found quickly). A fill that
## reaches an anchor cell is *supported* and stops. A fill that runs out of
## cells without finding one is an *unsupported region*: the world detaches
## it as falling pieces.
##
## - Frame-budgeted: at most `budget` cell visits per step(); a fill is
##   resumable, so a region of any size is found over several ticks (there is
##   no size cap that would treat big regions as anchored).
## - Deterministic: seeds are FIFO in the order the grid reported them, the
##   neighbour order is fixed, no hashing order or RNG is involved.
## - Multi-instigator: every seed carries the instigator id of the damage that
##   created it; a detached region is credited to its seed's instigator.
##
## Anchors: cells whose material is `anchor` or does not `falls`, and (when
## `bottom_is_ground`) every solid cell on the bottom row; `ground_edges`
## adds other grid edges (EDGE_LEFT | EDGE_RIGHT | EDGE_TOP).
## Only `solid` materials connect: non-solid cells (decor, ladders, background
## walls) neither hold anything up nor fall.

const EDGE_BOTTOM := 1
const EDGE_LEFT := 2
const EDGE_RIGHT := 4
const EDGE_TOP := 8

const NEIGHBOURS := [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]  # last = popped first

var grid: DKCellGrid
## Cell visits per step (deterministic count budget).
var budget := 4096
var bottom_is_ground := true
## Extra grid edges that count as ground (bit mask of EDGE_*).
var ground_edges := 0

var visits_last_step := 0

var _seeds := PackedInt32Array()
var _seed_inst := PackedInt32Array()
var _seed_head := 0
## Per-cell stamp of the fill that last visited it (0 = never).
var _stamp := PackedInt32Array()
var _next_stamp := 1
## Stamps >= this belong to the current pass (no destruction since).
var _pass_start := 1
var _supported: Dictionary = {}  # stamp -> true (current pass only)
## Fills that ended unsupported this step (their cells are about to be lifted).
var _dead: Dictionary = {}  # stamp -> true

var _job_active := false
var _job_stamp := 0
var _job_seed := -1
var _job_inst := 0
var _job_stack := PackedInt32Array()
var _job_cells := PackedInt32Array()
var _solid := PackedByteArray()  # material index -> 1 if solid


func setup(p_grid: DKCellGrid) -> void:
	grid = p_grid
	reset()


## Drops all pending work (after loading a level or restoring a snapshot
## without support state).
func reset() -> void:
	_seeds = PackedInt32Array()
	_seed_inst = PackedInt32Array()
	_seed_head = 0
	_stamp = PackedInt32Array()
	_stamp.resize(grid.width * grid.height if grid != null else 0)
	_next_stamp = 1
	_pass_start = 1
	_supported.clear()
	_abort_job()
	_build_solid_lut()


func is_idle() -> bool:
	return not _job_active and _seed_head >= _seeds.size()


func pending_seeds() -> int:
	return _seeds.size() - _seed_head


## Cells were destroyed: their solid neighbours need a check. Starts a new
## pass (earlier "supported" results may no longer hold).
func add_destroyed(cells: PackedInt32Array, instigator_id: int) -> void:
	if cells.is_empty():
		return
	_new_pass()
	# Hot path (a big blast destroys thousands of cells): index maths, local
	# arrays. Same neighbour order as NEIGHBOURS (up, left, right, down).
	var gm := grid.mat
	var solid := _solid
	var w := grid.width
	var last_row := (grid.height - 1) * w
	for i in cells:
		var x := i % w
		if i >= w and solid[gm[i - w]] == 1:
			_seeds.append(i - w)
			_seed_inst.append(instigator_id)
		if x > 0 and solid[gm[i - 1]] == 1:
			_seeds.append(i - 1)
			_seed_inst.append(instigator_id)
		if x < w - 1 and solid[gm[i + 1]] == 1:
			_seeds.append(i + 1)
			_seed_inst.append(instigator_id)
		if i < last_row and solid[gm[i + w]] == 1:
			_seeds.append(i + w)
			_seed_inst.append(instigator_id)


## Cells were added or landed: check them too (a landed piece may rest on
## something that is itself about to fall).
func add_cells(cells: PackedInt32Array, instigator_id: int) -> void:
	for i in cells:
		if _solid[grid.mat[i]] == 1:
			_push_seed(i, instigator_id)


## Solid cells were added somewhere (painting/building). A fill in progress
## could now be wrong about "unsupported", so it restarts from its seed.
## "Supported" results stay valid (adding cells never removes support).
func on_cells_added() -> void:
	if _job_active:
		var seed_cell := _job_seed
		var inst := _job_inst
		_abort_job()
		# Re-queue at the front so order stays deterministic.
		_seed_head -= 1
		if _seed_head < 0:
			_seed_head = 0
			_seeds.insert(0, seed_cell)
			_seed_inst.insert(0, inst)
		else:
			_seeds[_seed_head] = seed_cell
			_seed_inst[_seed_head] = inst


## Every solid cell becomes a seed (e.g. to settle a freshly loaded level).
func check_all(instigator_id: int = 0) -> void:
	_new_pass()
	for i in grid.mat.size():
		if _solid[grid.mat[i]] == 1:
			_push_seed(i, instigator_id)


## Runs up to `budget` cell visits. Returns the unsupported regions found:
## [{"cells": PackedInt32Array (row-major), "instigator_id": int}].
func step() -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	var left := budget
	_dead.clear()
	while left > 0:
		if not _job_active:
			if not _start_next_job():
				break
		var result := _run_job(left)
		left -= int(result[0])
		match int(result[1]):
			1:  # supported
				_supported[_job_stamp] = true
				_abort_job()
			2:  # unsupported
				var cells := PackedInt32Array()
				for i in _job_cells:
					if _solid[grid.mat[i]] == 1:
						cells.append(i)
				cells.sort()
				_dead[_job_stamp] = true
				if not cells.is_empty():
					regions.append({"cells": cells, "instigator_id": _job_inst})
				_abort_job()
	visits_last_step = budget - left
	# Compact the consumed part of the seed queue now and then.
	if _seed_head > 1024 and _seed_head * 2 > _seeds.size():
		_seeds = _seeds.slice(_seed_head)
		_seed_inst = _seed_inst.slice(_seed_head)
		_seed_head = 0
	return regions


func is_anchor_cell(i: int) -> bool:
	var m := grid.materials.at(grid.mat[i])
	if m.anchor or not m.falls:
		return true
	var y := i / grid.width
	if bottom_is_ground and y == grid.height - 1:
		return true
	if ground_edges == 0:
		return false
	var x := i % grid.width
	return ((ground_edges & EDGE_BOTTOM) != 0 and y == grid.height - 1) \
		or ((ground_edges & EDGE_TOP) != 0 and y == 0) \
		or ((ground_edges & EDGE_LEFT) != 0 and x == 0) \
		or ((ground_edges & EDGE_RIGHT) != 0 and x == grid.width - 1)


# — Snapshot / digest —

func to_dict() -> Dictionary:
	return {"seeds": _seeds.slice(_seed_head), "inst": _seed_inst.slice(_seed_head),
		"stamp": _stamp.duplicate(), "next": _next_stamp, "pass": _pass_start,
		"supported": _supported.keys(), "job": _job_active, "job_stamp": _job_stamp,
		"job_seed": _job_seed, "job_inst": _job_inst, "stack": _job_stack.duplicate(),
		"cells": _job_cells.duplicate(), "budget": budget, "bottom": bottom_is_ground,
		"edges": ground_edges}


func from_dict(d: Dictionary) -> bool:
	var st: PackedInt32Array = d.get("stamp", PackedInt32Array())
	if st.size() != grid.width * grid.height:
		return false
	_seeds = (d["seeds"] as PackedInt32Array).duplicate()
	_seed_inst = (d["inst"] as PackedInt32Array).duplicate()
	_seed_head = 0
	_stamp = st.duplicate()
	_next_stamp = int(d["next"])
	_pass_start = int(d["pass"])
	_supported.clear()
	for k in d["supported"]:
		_supported[int(k)] = true
	_job_active = bool(d["job"])
	_job_stamp = int(d["job_stamp"])
	_job_seed = int(d["job_seed"])
	_job_inst = int(d["job_inst"])
	_job_stack = (d["stack"] as PackedInt32Array).duplicate()
	_job_cells = (d["cells"] as PackedInt32Array).duplicate()
	budget = int(d.get("budget", budget))
	bottom_is_ground = bool(d.get("bottom", bottom_is_ground))
	ground_edges = int(d.get("edges", ground_edges))
	_build_solid_lut()
	return true


## Hash input for the world digest (pending work only, not the stamp cache).
func digest_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(_seeds.slice(_seed_head).to_byte_array())
	out.append_array(_seed_inst.slice(_seed_head).to_byte_array())
	out.append_array(PackedInt32Array([int(_job_active), _job_seed, _job_inst, _job_stack.size(), _job_cells.size()]).to_byte_array())
	return out


# — internals —

func _build_solid_lut() -> void:
	_solid = PackedByteArray()
	if grid == null or grid.materials == null:
		return
	_solid.resize(256)
	for k in grid.materials.size():
		_solid[k] = 1 if (k > 0 and grid.materials.at(k).solid) else 0


func _new_pass() -> void:
	_pass_start = _next_stamp
	_supported.clear()


func _push_seed(i: int, inst: int) -> void:
	_seeds.append(i)
	_seed_inst.append(inst)


func _abort_job() -> void:
	_job_active = false
	_job_stack = PackedInt32Array()
	_job_cells = PackedInt32Array()
	_job_seed = -1


func _start_next_job() -> bool:
	while _seed_head < _seeds.size():
		var i := _seeds[_seed_head]
		var inst := _seed_inst[_seed_head]
		_seed_head += 1
		var s := _stamp[i]
		if _solid[grid.mat[i]] == 0 or _dead.has(s) or (s >= _pass_start and _supported.has(s)) or is_anchor_cell(i):
			continue  # gone, known supported this pass, or ground itself
		_job_active = true
		_job_stamp = _next_stamp
		_next_stamp += 1
		_job_seed = i
		_job_inst = inst
		_stamp[i] = _job_stamp
		_job_stack = PackedInt32Array([i])
		_job_cells = PackedInt32Array([i])
		return true
	return false


## Returns [visits, state] with state 0 = budget used up, 1 = supported,
## 2 = unsupported (fill exhausted).
func _run_job(max_visits: int) -> Array:
	var visits := 0
	var w := grid.width
	var h := grid.height
	while visits < max_visits:
		if _job_stack.is_empty():
			return [visits, 2]
		var c := _job_stack[_job_stack.size() - 1]
		_job_stack.resize(_job_stack.size() - 1)
		visits += 1
		if _solid[grid.mat[c]] == 0:
			continue  # destroyed while the fill was running
		if is_anchor_cell(c):
			return [visits, 1]
		var cx := c % w
		var cy := c / w
		for k in 4:
			var d: Vector2i = NEIGHBOURS[k]
			var nx := cx + d.x
			var ny := cy + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var n := ny * w + nx
			if _solid[grid.mat[n]] == 0:
				continue
			var s := _stamp[n]
			if s == _job_stamp:
				continue
			if s >= _pass_start and _supported.has(s):
				return [visits, 1]  # touches a region already known to be supported
			_stamp[n] = _job_stamp
			_job_stack.append(n)
			_job_cells.append(n)
	return [visits, 0]
