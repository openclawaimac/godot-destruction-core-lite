class_name DKChunkCollision
extends Node2D
## Thin collision adapter: one StaticBody2D per chunk, rebuilt when the world
## requests it, with the chunk's solid cells merged greedily into as few
## rectangles as possible (deterministic). Falling pieces have no collision
## here; use DKWorld.piece_moved to crush entities under them.

@export_flags_2d_physics var collision_layer := 1
@export_flags_2d_physics var collision_mask := 0

var world: DKWorld
var shape_count := 0

var _bodies: Dictionary = {}  # Vector2i chunk -> StaticBody2D


func bind_world(w: DKWorld) -> void:
	world = w
	w.chunk_rebuild_requested.connect(rebuild_chunk)


func rebuild_all() -> void:
	var cc := world.grid.chunk_count()
	for y in cc.y:
		for x in cc.x:
			rebuild_chunk(Vector2i(x, y))


func rebuild_chunk(chunk: Vector2i) -> void:
	var body: StaticBody2D = _bodies.get(chunk)
	if body == null:
		body = StaticBody2D.new()
		body.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
		body.collision_layer = collision_layer
		body.collision_mask = collision_mask
		add_child(body)
		_bodies[chunk] = body
	for ch in body.get_children():
		shape_count -= 1
		body.remove_child(ch)
		ch.free()
	var cp := float(world.grid.cell_px)
	for r in merge_rects(world.grid, chunk):
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(r.size) * cp
		cs.shape = rs
		cs.position = (Vector2(r.position) + Vector2(r.size) * 0.5) * cp
		body.add_child(cs)
		shape_count += 1


## Rectangles (in cells) covering exactly the solid cells of a chunk: grow
## right, then down, in row-major order. Pure and deterministic.
static func merge_rects(g: DKCellGrid, chunk: Vector2i) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var n := g.chunk_cells
	var x0 := chunk.x * n
	var y0 := chunk.y * n
	var x1 := mini(x0 + n, g.width)
	var y1 := mini(y0 + n, g.height)
	var used: Dictionary = {}
	for y in range(y0, y1):
		for x in range(x0, x1):
			if used.has(y * g.width + x) or not _solid(g, x, y):
				continue
			var w := 1
			while x + w < x1 and _solid(g, x + w, y) and not used.has(y * g.width + x + w):
				w += 1
			var h := 1
			var grow := true
			while grow and y + h < y1:
				for k in w:
					if not _solid(g, x + k, y + h) or used.has((y + h) * g.width + x + k):
						grow = false
						break
				if grow:
					h += 1
			for yy in range(y, y + h):
				for xx in range(x, x + w):
					used[yy * g.width + xx] = true
			out.append(Rect2i(x, y, w, h))
	return out


static func _solid(g: DKCellGrid, x: int, y: int) -> bool:
	var m := g.mat[y * g.width + x]
	return m != 0 and g.materials.at(m).solid
