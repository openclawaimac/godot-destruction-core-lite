# Quickstart: Godot Destruction Core

Requires Godot 4.6 or newer (tested on 4.7.2). Pure GDScript, no GDExtension, Web-export safe.

## 1. Run the demos and tests

```bash
godot --headless --path . --import          # once: registers the DK* classes
bash tools/run_tests.sh /path/to/godot       # Pro: 128 tests, Lite: 72 tests, must end with "CI: all green"
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

## 3. Pro: chain reactions, fire, stress, replay

```gdscript
var reactor := DKChainReactor.new()
reactor.attach(world)                        # world.detonate() now goes through the reactor
var barrel := reactor.register_trigger(Vector2(400, 210), 20.0, 500, &"blast", 4)

var fire := DKFire.new()
fire.attach(world, reactor)                  # flames light barrels, fuel cells explode
fire.ignite_circle(Vector2(300, 180), 10.0, 1)
reactor.chain_finished.connect(func(stats): print("chain fired ", stats.fired, " blasts"))
```

Flammability is plain material data: `burn_ticks`, `ignite_pct`, `ash_into`.

```gdscript
var stress := DKStress.new()
stress.attach(world)                         # beams snap, overloaded columns crush (material strength/density)

var log := DKCommandLog.new()
log.attach(world)
log.start_recording()
log.execute(&"detonate", [Vector2(320, 200), 24.0, 600, &"blast", 1, 0])   # instead of world.detonate()
for i in 120: log.step()                     # instead of world.tick()
log.stop_recording()
# fresh_world: built like the original (same level, same modules attached), then:
var result := log.replay(fresh_world)        # {ok, reason, mismatch_tick, final_digest, expected}
```

Debug overlays: add a `DKDebugOverlay` next to the world and `attach(world, reactor, stress, inspector)`
(chain graph, stress heat map, "why did this fall?" via `DKFallInspector`), and a `DKBudgetHud` for frame cost.
In the Fire Sale demo, press `O`.

## 3. Determinism and saves

`world.snapshot()` / `world.restore(bytes)` cover the grid, support work and falling pieces.
`world.state_digest()` gives a SHA-256 you can compare between two peers or two replays.

See `README.md` for the full API.
