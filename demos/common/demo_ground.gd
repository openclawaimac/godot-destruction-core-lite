class_name DemoGround
extends Node2D
## Fills the strip between the bottom of the world grid and the bottom of the
## screen with the same seamless bedrock tiles the renderer uses, so the
## ground continues to the screen edge (no backdrop showing below the world).
## Static after setup: one draw.

var renderer: DKTileRenderer
var material_id := &"bedrock"
var rows := 8
var margin := 4


## Adds an underlay to `world` below its grid, deep enough for `view_h`.
static func attach(world: DKWorld, r: DKTileRenderer, view_h: float, mat_id := &"bedrock") -> DemoGround:
	var g := DemoGround.new()
	g.name = "GroundUnderlay"
	g.renderer = r
	g.material_id = mat_id
	var bottom := world.position.y + world.grid.height * world.cell_px
	g.rows = maxi(1, ceili((view_h - bottom) / float(world.cell_px)) + 2)
	world.add_child(g)
	world.move_child(g, 0)
	return g


func _draw() -> void:
	var w := renderer.world
	var mi := w.materials.index_of(material_id)
	var row := int(renderer.material_rows.get(material_id, -1))
	if mi < 0 or row < 0 or renderer.atlas == null:
		return
	var tp := float(renderer.tile_px)
	var cell := float(w.cell_px)
	for y in range(w.grid.height, w.grid.height + rows):
		for x in range(-margin, w.grid.width + margin):
			var col := renderer.variant_for(mi, x, y) * 32 + 15  # interior mask
			draw_texture_rect_region(renderer.atlas, Rect2(x * cell, y * cell, cell, cell),
				Rect2(col * tp, row * tp, tp, tp))
