class_name DKPieces
extends RefCounted
## Falling pieces: unsupported regions lifted out of the grid, moved down by
## an integer (fixed-point) kinematic fall, and written back as rubble when
## they hit something. Pure logic; DKWorld drives it and turns landings into
## crush damage.
##
## Positions are cell based. `fy` is the vertical offset from the piece's
## origin row in 1/256 cells, `vy` its speed in 1/256 cells per tick, so the
## fall is identical on every machine. Pieces fall straight down; collision
## is swept cell by cell against the grid (never tunnels). Pieces do not
## collide with each other while airborne (the first to land becomes ground
## for the others).

const SUB := 256

## Added to vy every tick (1/256 cells per tick²).
var gravity := 22
## Terminal speed (1/256 cells per tick).
var max_speed := 640
## Landing slower than this (≈ a drop of under two cells) does no crush
## damage and does not break the piece into rubble.
var crush_min_speed := 200
var crush_max_power := 250
## Ticks a detached piece holds still (shaking, "creaking") before it falls.
var hold_ticks := 0

var grid: DKCellGrid
## Live pieces, ordered by id (deterministic update order).
var pieces: Array[Dictionary] = []
var _next_id := 1


func setup(p_grid: DKCellGrid) -> void:
	grid = p_grid
	pieces.clear()
	_next_id = 1


## Lifts `cells` (an unsupported region) out of the grid. The region is split
## into 4-connected components, one piece each, in deterministic order.
## Returns the new pieces.
func extract(cells: PackedInt32Array, instigator_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var in_set: Dictionary = {}
	for i in cells:
		if grid.mat[i] != 0:
			in_set[i] = true
	var w := grid.width
	var sorted := cells.duplicate()
	sorted.sort()
	for start in sorted:
		if not in_set.has(start):
			continue
		var comp := PackedInt32Array([start])
		in_set.erase(start)
		var k := 0
		while k < comp.size():
			var c := comp[k]
			k += 1
			var cx := c % w
			for n in [c - w, c - 1 if cx > 0 else -1, c + 1 if cx < w - 1 else -1, c + w]:
				if n >= 0 and in_set.has(n):
					in_set.erase(n)
					comp.append(n)
		comp.sort()
		out.append(_make_piece(comp, instigator_id))
	return out


## Advances every piece one tick. Returns
## {"moved": [[piece, from_px: Rect2, to_px: Rect2]], "landed": [[piece, impact_speed]], "lost": [piece]}.
## Landed pieces are removed from `pieces`; call write_back() for them.
func step() -> Dictionary:
	var moved: Array = []
	var landed: Array = []
	var lost: Array = []
	var keep: Array[Dictionary] = []
	for p in pieces:
		var from_rect := piece_rect_px(p)
		if int(p.get("hold", 0)) > 0:
			p["hold"] = int(p["hold"]) - 1
			keep.append(p)
			continue
		var vy := mini(int(p["vy"]) + gravity, max_speed)
		var fy := int(p["fy"])
		var target := fy + vy
		var steps := (target / SUB) - (fy / SUB)
		var hit := false
		var gone := false
		var off := fy / SUB
		for s in steps:
			var blocked := _blocked_below(p, off)
			if blocked == 2:
				gone = true
				break
			if blocked == 1:
				hit = true
				break
			off += 1
		if not hit and not gone and steps == 0 and _blocked_below(p, off) == 1 and vy > 0:
			# Resting on something that appeared under it.
			hit = true
		p["vy"] = vy
		if gone:
			lost.append(p)
			continue
		if hit:
			p["fy"] = off * SUB
			landed.append([p, vy])
			continue
		p["fy"] = target
		keep.append(p)
		var to_rect := piece_rect_px(p)
		if to_rect != from_rect:
			moved.append([p, from_rect, to_rect])
	pieces = keep
	return {"moved": moved, "landed": landed, "lost": lost}


## Writes a landed piece back into the grid (cells already occupied are
## skipped). `rubble_of(mat_index) -> mat_index` picks the landed material;
## the material's `rubble_pct` decides (deterministically) which cells use it.
## Returns [written cell indices (row-major), crush target cell indices].
func write_back(p: Dictionary, rubble_of: Callable, impact_speed: int = 1 << 20) -> Array:
	var written := PackedInt32Array()
	var crush := PackedInt32Array()
	var w: int = p["w"]
	var off := int(p["fy"]) / SUB
	var cells: PackedInt32Array = p["cells"]
	var mats: PackedByteArray = p["mats"]
	var hps: PackedInt32Array = p["hps"]
	var bottom_set: Dictionary = {}
	for b in (p["bottom"] as PackedInt32Array):
		bottom_set[b] = true
	for k in cells.size():
		var c := Vector2i(int(p["x0"]) + cells[k] % w, int(p["y0"]) + off + cells[k] / w)
		if not grid.in_bounds(c) or grid.mat[grid.index(c)] != 0:
			continue  # occupied (even by non-solid decor): the cell is lost
		var m: int = rubble_of.call(mats[k]) if impact_speed >= crush_min_speed else mats[k]
		var pct := grid.materials.at(mats[k]).rubble_pct
		var keep_own := m != mats[k] and not bottom_set.has(cells[k]) \
			and _hash2(int(p["id"]), cells[k]) % 100 >= pct
		if keep_own:
			m = mats[k]
		grid.set_cell(c, m)
		var i := grid.index(c)
		if keep_own:
			grid.hp[i] = maxi(1, mini(hps[k], grid.hp[i] / 2))
		elif m == mats[k]:
			grid.hp[i] = mini(hps[k], grid.hp[i])
		grid.flags[i] = grid.flags[i] | DKCellGrid.FLAG_RUBBLE
		written.append(i)
	for k in (p["bottom"] as PackedInt32Array):
		var b := Vector2i(int(p["x0"]) + k % w, int(p["y0"]) + off + k / w + 1)
		if grid.in_bounds(b) and _is_solid_cell(grid.index(b)):
			crush.append(grid.index(b))
	written.sort()
	crush.sort()
	return [written, crush]


## Crush power for a landing: speed × (base + mass), integer, capped.
func crush_power(p: Dictionary, impact_speed: int) -> int:
	if impact_speed < crush_min_speed:
		return 0
	var mass := mini(int(p["mass"]), 512)
	return mini(crush_max_power, impact_speed * (16 + mass / 4) / SUB)


## Piece bounds in grid pixels (local to the DKWorld).
func piece_rect_px(p: Dictionary) -> Rect2:
	var cp := float(grid.cell_px)
	return Rect2(float(p["x0"]) * cp, float(p["y0"]) * cp + float(p["fy"]) * cp / SUB,
		float(p["w"]) * cp, float(p["h"]) * cp)


func clear() -> void:
	pieces.clear()


func to_dict() -> Dictionary:
	var arr: Array = []
	for p in pieces:
		arr.append(p.duplicate(true))
	return {"pieces": arr, "next": _next_id, "g": gravity, "max": max_speed, "hold": hold_ticks}


func from_dict(d: Dictionary) -> bool:
	if not d.has("pieces"):
		return false
	pieces.clear()
	for p in d["pieces"]:
		pieces.append((p as Dictionary).duplicate(true))
	_next_id = int(d["next"])
	gravity = int(d.get("g", gravity))
	max_speed = int(d.get("max", max_speed))
	hold_ticks = int(d.get("hold", hold_ticks))
	return true


func digest_bytes() -> PackedByteArray:
	var out := PackedInt32Array([pieces.size(), _next_id]).to_byte_array()
	for p in pieces:
		out.append_array(PackedInt32Array([p["id"], p["x0"], p["y0"], p["w"], p["h"], p["fy"], p["vy"], p["instigator_id"], int(p.get("hold", 0))]).to_byte_array())
		out.append_array((p["cells"] as PackedInt32Array).to_byte_array())
		out.append_array(p["mats"] as PackedByteArray)
	return out


# — internals —

static func _hash2(a: int, b: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663)
	h = ((h >> 16) ^ h) * 0x45d9f3b & 0x7fffffff
	return ((h >> 16) ^ h) & 0x7fffffff


func _make_piece(comp: PackedInt32Array, instigator_id: int) -> Dictionary:
	var w := grid.width
	var x0 := w
	var y0 := grid.height
	var x1 := -1
	var y1 := -1
	for i in comp:
		x0 = mini(x0, i % w)
		x1 = maxi(x1, i % w)
		y0 = mini(y0, i / w)
		y1 = maxi(y1, i / w)
	var pw := x1 - x0 + 1
	var cells := PackedInt32Array()
	var mats := PackedByteArray()
	var hps := PackedInt32Array()
	var local: Dictionary = {}
	var mass := 0
	for i in comp:
		var li := (i / w - y0) * pw + (i % w - x0)
		cells.append(li)
		mats.append(grid.mat[i])
		hps.append(grid.hp[i])
		local[li] = true
		mass += grid.materials.at(grid.mat[i]).density
		grid.set_cell(grid.coord(i), 0)
	var bottom := PackedInt32Array()
	for li in cells:
		if not local.has(li + pw):
			bottom.append(li)
	var p := {"id": _next_id, "x0": x0, "y0": y0, "w": pw, "h": y1 - y0 + 1,
		"cells": cells, "mats": mats, "hps": hps, "bottom": bottom,
		"fy": 0, "vy": 0, "mass": mass, "instigator_id": instigator_id, "hold": hold_ticks}
	_next_id += 1
	pieces.append(p)
	return p


## 0 = free, 1 = blocked by a solid cell, 2 = would leave the grid (lost).
func _blocked_below(p: Dictionary, off: int) -> int:
	var w: int = p["w"]
	for k in (p["bottom"] as PackedInt32Array):
		var c := Vector2i(int(p["x0"]) + k % w, int(p["y0"]) + off + k / w + 1)
		if not grid.in_bounds(c):
			if c.y >= grid.height and not grid.outside_solid:
				return 2
			return 1
		if _is_solid_cell(grid.index(c)):
			return 1
	return 0


func _is_solid_cell(i: int) -> bool:
	var m := grid.mat[i]
	return m != 0 and grid.materials.at(m).solid
