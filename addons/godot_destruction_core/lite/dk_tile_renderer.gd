class_name DKTileRenderer
extends TileMapLayer
## Thin render adapter: mirrors a DKWorld's grid into this TileMapLayer, one
## chunk at a time when the world requests a rebuild (budgeted by the world),
## and draws falling pieces with the same tiles.
##
## Atlas layout (one row per material, `tile_px` square tiles):
##   columns 0..15  intact cell, column = neighbour mask
##   columns 16..31 damaged cell (hp below `damaged_below_pct`), same masks
## Neighbour mask bits (set when that neighbour is solid):
##   1 = up, 2 = right, 4 = down, 8 = left
## so column 15 is an interior cell and column 0 a lone cell. Exposed edges
## can carry outlines, grass, highlights: the art decides.
## With `variants` > 1 the 32-column block repeats per variant and each cell
## picks one from a hash of its position (breaks up visible tiling).
## Materials listed in `macro_tiles` pick by position instead: with period
## (px, py) the variant is (x mod px) + px * (y mod py), so the art can slice
## one seamless (px*tile) x (py*tile) texture into variants and neighbouring
## cells line up with no seams. Needs px * py <= `variants`.

const MASK_UP := 1
const MASK_RIGHT := 2
const MASK_DOWN := 4
const MASK_LEFT := 8

@export var atlas: Texture2D
@export var tile_px := 8
## Material id -> atlas row, e.g. {&"dirt": 0, &"rock": 1}. Unmapped
## materials are not drawn.
@export var material_rows: Dictionary = {}
@export var damaged_below_pct := 50
## Number of 32-column variant blocks in the atlas.
@export var variants := 1
## Material id -> Vector2i period for position-sliced variants, e.g.
## {&"rock": Vector2i(4, 4)}. See the class notes.
@export var macro_tiles: Dictionary = {}

var world: DKWorld
var chunks_rebuilt := 0

var _row_of_index := PackedInt32Array()  # material index -> atlas row (-1 = none)
var _macro_of_index: Array[Vector2i] = []  # material index -> period (0,0 = hashed)
var _pieces_layer: Node2D


func bind_world(w: DKWorld) -> void:
	world = w
	_build_tile_set()
	_row_of_index = PackedInt32Array()
	_macro_of_index.clear()
	for i in w.materials.size():
		var m := w.materials.at(i)
		_row_of_index.append(int(material_rows.get(m.id, material_rows.get(String(m.id), -1))) if i > 0 else -1)
		var per: Vector2i = macro_tiles.get(m.id, macro_tiles.get(String(m.id), Vector2i.ZERO))
		if per.x <= 0 or per.y <= 0 or per.x * per.y > variants:
			if per != Vector2i.ZERO:
				push_warning("DKTileRenderer: macro_tiles period %s for %s needs %d variants" % [per, m.id, per.x * per.y])
			per = Vector2i.ZERO
		_macro_of_index.append(per)
	w.chunk_rebuild_requested.connect(rebuild_chunk)
	if _pieces_layer == null:
		_pieces_layer = Node2D.new()
		_pieces_layer.name = "Pieces"
		add_child(_pieces_layer)
		_pieces_layer.draw.connect(_draw_pieces)
	w.piece_detached.connect(func(_p: Dictionary) -> void: _pieces_layer.queue_redraw())
	w.piece_moved.connect(func(_p: Dictionary, _a: Rect2, _b: Rect2) -> void: _pieces_layer.queue_redraw())
	w.piece_landed.connect(func(_p: Dictionary, _c: DKDamage, _i: int) -> void: _pieces_layer.queue_redraw())
	w.piece_lost.connect(func(_p: Dictionary) -> void: _pieces_layer.queue_redraw())
	scale = Vector2.ONE * (float(w.cell_px) / float(tile_px))


## Redraws every cell (after loading or restoring).
func rebuild_all() -> void:
	var cc := world.grid.chunk_count()
	for y in cc.y:
		for x in cc.x:
			rebuild_chunk(Vector2i(x, y))


## Re-tiles one chunk plus a one-cell border (neighbour masks change there).
func rebuild_chunk(chunk: Vector2i) -> void:
	var g := world.grid
	var n := g.chunk_cells
	for y in range(maxi(chunk.y * n - 1, 0), mini((chunk.y + 1) * n + 1, g.height)):
		for x in range(maxi(chunk.x * n - 1, 0), mini((chunk.x + 1) * n + 1, g.width)):
			_update_cell(Vector2i(x, y))
	chunks_rebuilt += 1


## Atlas coordinates for a grid cell (Vector2i(-1, -1) = draw nothing).
func atlas_coords_for(c: Vector2i) -> Vector2i:
	var g := world.grid
	var i := g.index(c)
	var mi := g.mat[i]
	if mi == 0 or mi >= _row_of_index.size() or _row_of_index[mi] < 0:
		return Vector2i(-1, -1)
	var mask := 0
	if _solid(c + Vector2i(0, -1)): mask |= MASK_UP
	if _solid(c + Vector2i(1, 0)): mask |= MASK_RIGHT
	if _solid(c + Vector2i(0, 1)): mask |= MASK_DOWN
	if _solid(c + Vector2i(-1, 0)): mask |= MASK_LEFT
	var full := world.materials.at(mi).hp
	var damaged := full > 1 and g.hp[i] * 100 < full * damaged_below_pct
	return Vector2i(variant_for(mi, c.x, c.y) * 32 + mask + (16 if damaged else 0), _row_of_index[mi])


## Atlas variant block for material index `mi` at cell (x, y).
func variant_for(mi: int, x: int, y: int) -> int:
	if mi >= 0 and mi < _macro_of_index.size():
		var per := _macro_of_index[mi]
		if per.x > 0:
			return posmod(x, per.x) + per.x * posmod(y, per.y)
	return _variant(x, y)


func _variant(x: int, y: int) -> int:
	if variants <= 1:
		return 0
	var h := (x * 73856093) ^ (y * 19349663)
	h = ((h >> 13) ^ h) * 0x45d9f3b & 0x7fffffff
	return ((h >> 16) ^ h) % variants


func _update_cell(c: Vector2i) -> void:
	var a := atlas_coords_for(c)
	if a.x < 0:
		erase_cell(c)
	else:
		set_cell(c, 0, a)


func _solid(c: Vector2i) -> bool:
	var g := world.grid
	if not g.in_bounds(c):
		return c.y >= g.height  # the floor edge counts, side/top edges stay open
	return g.mat[g.index(c)] != 0


func _build_tile_set() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_px, tile_px)
	var src := TileSetAtlasSource.new()
	src.texture = atlas
	src.texture_region_size = Vector2i(tile_px, tile_px)
	if atlas != null:
		var cols := atlas.get_width() / tile_px
		var rows := atlas.get_height() / tile_px
		for y in rows:
			for x in cols:
				src.create_tile(Vector2i(x, y))
	ts.add_source(src, 0)
	tile_set = ts


func _draw_pieces() -> void:
	if world == null or atlas == null:
		return
	var tp := float(tile_px)
	for p in world.pieces.pieces:
		var w: int = p["w"]
		var cells: PackedInt32Array = p["cells"]
		var mats: PackedByteArray = p["mats"]
		var local: Dictionary = {}
		for li in cells:
			local[li] = true
		var oy := float(p["fy"]) / DKPieces.SUB
		for k in cells.size():
			var li := cells[k]
			var mi := mats[k]
			if mi >= _row_of_index.size() or _row_of_index[mi] < 0:
				continue
			var lx := li % w
			var ly := li / w
			var mask := 0
			if ly > 0 and local.has(li - w): mask |= MASK_UP
			if lx < w - 1 and local.has(li + 1): mask |= MASK_RIGHT
			if local.has(li + w): mask |= MASK_DOWN
			if lx > 0 and local.has(li - 1): mask |= MASK_LEFT
			var gx := int(p["x0"]) + lx
			var gy := int(p["y0"]) + ly
			var dst := Rect2(gx * tp, (gy + oy) * tp, tp, tp)
			var col := variant_for(mi, gx, gy) * 32 + mask
			_pieces_layer.draw_texture_rect_region(atlas, dst, Rect2(col * tp, _row_of_index[mi] * tp, tp, tp))
