class_name DKCellGrid
extends RefCounted
## The single source of truth: a 2D grid of cells in packed arrays.
## Pure logic (no nodes, no rendering, no physics), so it runs headless and
## gives identical results for identical input. Rendering and collision are
## derived views that adapters rebuild from the dirty chunks.

const FLAG_SCAR := 1        ## cell was destroyed by damage (adapters draw broken edges)
const FLAG_PROTECTED := 2   ## cell ignores damage (scripted / level-design spine)
const FLAG_RUBBLE := 4      ## cell was written back by a landed falling piece
const SNAPSHOT_VERSION := 1

var width := 0
var height := 0
var cell_px := 8
var chunk_cells := 16
## Treat cells outside the grid as solid walls.
var outside_solid := true
var materials: DKMaterialSet

var mat := PackedByteArray()
var hp := PackedInt32Array()
var flags := PackedByteArray()

var _dirty: Dictionary = {}  # Vector2i chunk -> true


func setup(w: int, h: int, p_cell_px: int, p_chunk_cells: int, p_materials: DKMaterialSet) -> void:
	assert(w > 0 and h > 0 and p_cell_px > 0 and p_chunk_cells > 0)
	width = w
	height = h
	cell_px = p_cell_px
	chunk_cells = p_chunk_cells
	materials = p_materials
	mat = PackedByteArray()
	mat.resize(w * h)
	hp = PackedInt32Array()
	hp.resize(w * h)
	flags = PackedByteArray()
	flags.resize(w * h)
	_dirty.clear()


## Fills the grid from text rows; `legend` maps a character to a material id.
## Unknown characters become empty air.
func load_rows(rows: PackedStringArray, legend: Dictionary) -> void:
	for y in mini(rows.size(), height):
		var row := rows[y]
		for x in mini(row.length(), width):
			var mid: StringName = legend.get(row[x], &"empty")
			set_cell(Vector2i(x, y), materials.index_of(mid))
	_dirty.clear()


# — Access —

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func index(c: Vector2i) -> int:
	return c.y * width + c.x


func coord(i: int) -> Vector2i:
	return Vector2i(i % width, i / width)


func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / cell_px), floori(p.y / cell_px))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * cell_px, (c.y + 0.5) * cell_px)


func mat_index(c: Vector2i) -> int:
	return mat[index(c)] if in_bounds(c) else -1


func material_at_cell(c: Vector2i) -> DKMaterial:
	return materials.at(mat[index(c)]) if in_bounds(c) else null


func is_solid(c: Vector2i) -> bool:
	if not in_bounds(c):
		return outside_solid
	return materials.at(mat[index(c)]).solid


func is_scarred(c: Vector2i) -> bool:
	return in_bounds(c) and (flags[index(c)] & FLAG_SCAR) != 0


func set_protected(c: Vector2i, on: bool) -> void:
	if not in_bounds(c):
		return
	var i := index(c)
	flags[i] = (flags[i] | FLAG_PROTECTED) if on else (flags[i] & ~FLAG_PROTECTED)


## Sets one cell to a material (full hp, scar cleared) and marks its chunk dirty.
func set_cell(c: Vector2i, mat_i: int) -> void:
	if not in_bounds(c) or mat_i < 0:
		return
	var i := index(c)
	mat[i] = mat_i
	hp[i] = materials.at(mat_i).hp
	flags[i] = flags[i] & ~FLAG_SCAR
	_dirty[chunk_of(c)] = true


func solid_count() -> int:
	var n := 0
	for i in mat.size():
		if mat[i] != 0:
			n += 1
	return n


# — Shapes —

## Cells covered by a shape, in row-major order (deterministic). A cell is
## covered when its centre is inside the shape.
func cells_in(d: DKDamage) -> PackedInt32Array:
	var out := PackedInt32Array()
	match d.shape:
		DKDamage.Shape.CELL:
			var c := world_to_cell(d.pos)
			if in_bounds(c):
				out.append(index(c))
		DKDamage.Shape.CELLS:
			var n := width * height
			var tmp := d.cell_list.duplicate()
			tmp.sort()
			var last := -1
			for i in tmp:
				if i >= 0 and i < n and i != last:
					out.append(i)
					last = i
		DKDamage.Shape.CIRCLE:
			# Hot path: inlined (no per-cell Callable).
			var r2 := d.radius * d.radius
			var c0 := world_to_cell(d.pos - Vector2(d.radius, d.radius))
			var c1 := world_to_cell(d.pos + Vector2(d.radius, d.radius))
			var cp := float(cell_px)
			for y in range(maxi(c0.y, 0), mini(c1.y, height - 1) + 1):
				var dy := (y + 0.5) * cp - d.pos.y
				var dy2 := dy * dy
				if dy2 > r2:
					continue
				for x in range(maxi(c0.x, 0), mini(c1.x, width - 1) + 1):
					var dx := (x + 0.5) * cp - d.pos.x
					if dx * dx + dy2 <= r2:
						out.append(y * width + x)
		DKDamage.Shape.RECT:
			var r := Rect2(d.pos, d.size).abs()
			var c0 := world_to_cell(r.position)
			var c1 := world_to_cell(r.end)
			for y in range(maxi(c0.y, 0), mini(c1.y, height - 1) + 1):
				for x in range(maxi(c0.x, 0), mini(c1.x, width - 1) + 1):
					if r.has_point(Vector2((x + 0.5) * cell_px, (y + 0.5) * cell_px)):
						out.append(y * width + x)
		DKDamage.Shape.LINE:
			var hw := d.width * 0.5
			var lo := Vector2(minf(d.pos.x, d.to.x), minf(d.pos.y, d.to.y)) - Vector2(hw, hw)
			var hi := Vector2(maxf(d.pos.x, d.to.x), maxf(d.pos.y, d.to.y)) + Vector2(hw, hw)
			var hw2 := hw * hw
			_scan(lo, hi, out, func(p: Vector2) -> bool:
				return Geometry2D.get_closest_point_to_segment(p, d.pos, d.to).distance_squared_to(p) <= hw2)
	return out


func _scan(lo: Vector2, hi: Vector2, out: PackedInt32Array, inside: Callable) -> void:
	var c0 := world_to_cell(lo)
	var c1 := world_to_cell(hi)
	for y in range(maxi(c0.y, 0), mini(c1.y, height - 1) + 1):
		for x in range(maxi(c0.x, 0), mini(c1.x, width - 1) + 1):
			if inside.call(Vector2((x + 0.5) * cell_px, (y + 0.5) * cell_px)):
				out.append(y * width + x)


# — Damage and paint —

## Applies damage. Integer maths only after shape coverage, so the same input
## always destroys the same cells.
func apply(d: DKDamage) -> DKReport:
	var rep := DKReport.new()
	rep.instigator_id = d.instigator_id
	rep.damage_type = d.type
	rep.tag = d.tag
	var use_falloff := d.shape == DKDamage.Shape.CIRCLE and d.falloff_min_pct < 100 and d.radius > 0.0
	var r_milli := int(d.radius * 1000.0)
	# Hot path: per-material lookups once per call, plain local arrays in the loop.
	var nmat := materials.size()
	var mats: Array[DKMaterial] = []
	var anchor_lut := PackedByteArray()
	anchor_lut.resize(nmat)
	var eff_lut := PackedInt32Array()
	eff_lut.resize(nmat)
	for k in nmat:
		var md := materials.at(k)
		mats.append(md)
		anchor_lut[k] = 1 if md.anchor else 0
		eff_lut[k] = md.damage_after_resist(d.power, d.type)
	var counts := PackedInt32Array()
	counts.resize(nmat)
	var destroyed := PackedInt32Array()
	var destroyed_mat := PackedByteArray()
	var damaged_cells := PackedInt32Array()
	var damaged := 0
	var blocked := 0
	var w := width
	var cc := chunk_cells
	var last_chunk := -1
	for i in cells_in(d):
		var m := mat[i]
		if m == 0:
			continue
		if anchor_lut[m] == 1 or (flags[i] & FLAG_PROTECTED) != 0:
			blocked += 1
			continue
		var eff := eff_lut[m]
		if use_falloff:
			var dist_milli := int(cell_center(coord(i)).distance_to(d.pos) * 1000.0)
			var drop := (100 - d.falloff_min_pct) * mini(dist_milli, r_milli) / maxi(r_milli, 1)
			eff = mats[m].damage_after_resist(d.power * (100 - drop) / 100, d.type)
		if eff <= 0:
			blocked += 1
			continue
		damaged += 1
		var left := hp[i] - eff
		if left <= 0:
			mat[i] = 0
			hp[i] = 0
			flags[i] = flags[i] | FLAG_SCAR
			destroyed.append(i)
			destroyed_mat.append(m)
			counts[m] += 1
			var cx := (i % w) / cc
			var cy := (i / w) / cc
			var ck := cy * 65536 + cx
			if ck != last_chunk:
				_dirty[Vector2i(cx, cy)] = true
				last_chunk = ck
		else:
			hp[i] = left
			damaged_cells.append(i)
	rep.destroyed = destroyed
	rep.destroyed_mat = destroyed_mat
	rep.damaged_cells = damaged_cells
	rep.damaged = damaged
	rep.blocked = blocked
	for k in nmat:
		if counts[k] > 0:
			rep.by_material[mats[k].id] = counts[k]
	return rep


## Fills a shape with a material (building, repair, deposits). Protected cells
## are left alone. Returns the number of cells changed.
func paint(d: DKDamage, mat_i: int) -> int:
	var n := 0
	for i in cells_in(d):
		if (flags[i] & FLAG_PROTECTED) != 0:
			continue
		if mat[i] == mat_i and hp[i] == materials.at(mat_i).hp:
			continue
		set_cell(coord(i), mat_i)
		n += 1
	return n


# — Chunks —

func chunk_of(c: Vector2i) -> Vector2i:
	return Vector2i(c.x / chunk_cells, c.y / chunk_cells)


func chunk_count() -> Vector2i:
	return Vector2i(ceili(float(width) / chunk_cells), ceili(float(height) / chunk_cells))


func has_dirty() -> bool:
	return not _dirty.is_empty()


## Dirty chunks in deterministic order (row-major), then cleared.
func take_dirty_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k: Vector2i in _dirty:
		out.append(k)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	_dirty.clear()
	return out


func mark_all_dirty() -> void:
	var cc := chunk_count()
	for y in cc.y:
		for x in cc.x:
			_dirty[Vector2i(x, y)] = true


# — Hash / snapshot —

## SHA-256 over size + cells (materials, hp, flags). Stable across runs.
func digest() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(PackedInt32Array([width, height, cell_px, chunk_cells]).to_byte_array())
	ctx.update(mat)
	ctx.update(hp.to_byte_array())
	ctx.update(flags)
	return ctx.finish().hex_encode()


## 60-bit integer form of digest() for quick comparisons.
func state_hash() -> int:
	return digest().substr(0, 15).hex_to_int()


func to_dict() -> Dictionary:
	return {"v": SNAPSHOT_VERSION, "w": width, "h": height, "cell_px": cell_px,
		"chunk": chunk_cells, "mat": mat.duplicate(), "hp": hp.duplicate(),
		"flags": flags.duplicate()}


## Restores cells from to_dict(). The material set must be the same one.
## Returns false (and changes nothing) if the snapshot doesn't fit.
func from_dict(s: Dictionary) -> bool:
	if int(s.get("v", -1)) != SNAPSHOT_VERSION or int(s.get("w", -1)) != width \
			or int(s.get("h", -1)) != height:
		return false
	var m: PackedByteArray = s["mat"]
	var h: PackedInt32Array = s["hp"]
	var f: PackedByteArray = s["flags"]
	if m.size() != width * height or h.size() != m.size() or f.size() != m.size():
		return false
	mat = m.duplicate()
	hp = h.duplicate()
	flags = f.duplicate()
	mark_all_dirty()
	return true
