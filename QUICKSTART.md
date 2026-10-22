# Quickstart: Godot Destruction Core

Requires Godot 4.6 or newer (tested on 4.7.2). Pure GDScript, no GDExtension, Web-export safe.

## 1. Run the demos and tests

```bash
godot --headless --path . --import          # once: registers the DK* classes
bash tools/run_tests.sh /path/to/godot       # 82 tests, must end with "CI: all green"
godot --path . res://demos/lite_collapse/demo.tscn     # Lite demo: "Collapse"
```

## 2. Add it to your game

Copy `addons/godot_destruction_core/` into your project (`lite/`).

```gdscript
# A destructible world: 160x90 cells of 8 px, chunks of 16 cells.
var mats := DKMaterialSet.make([
	DKMaterial.make(&"dirt", 300, {"rubble_into": &"dirt"}),
	DKMaterial.make(&"brick", 900, {"resist": {&"blast": 25}}),
	DKMaterial.make(&"bedrock", 1, {"anchor": true}),
])
var world := DKWorld.new()
add_child(world)
world.setup(160, 90, 8, 16, mats)
world.load_rows(level_rows, {".": &"empty", "d": &"dirt", "b": &"brick", "#": &"bedrock"})
world.check_all_support()

# Draw and collide (optional adapters).
var tiles := DKTileRenderer.new()   # a TileMapLayer: set atlas, tile_px and material_rows first
add_child(tiles)
tiles.bind_world(world)
var collision := DKChunkCollision.new()
add_child(collision)
collision.bind_world(world)

# Blow something up; player 1 gets the credit.
world.detonate(Vector2(320, 200), 24.0, 600, &"blast", 1)
```

`world.tick()` runs automatically with `auto_tick = true`; collapse, falling pieces and crush damage happen over
the next ticks. Listen to `piece_moved` / `piece_landed` to crush your own entities.

## 3. Determinism and saves

`world.snapshot()` / `world.restore(bytes)` cover the grid, support work and falling pieces.
`world.state_digest()` gives a SHA-256 you can compare between two peers or two replays.

See `README.md` for the full API.
