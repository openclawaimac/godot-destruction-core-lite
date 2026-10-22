# AGENTS.md: Godot Destruction Core Lite

## What this is
Godot Destruction Core Lite is a free, MIT-licensed **2D destruction addon for Godot 4** (typed GDScript, Godot 4.6+, tested on 4.7.2): destructible cell terrain, damage shapes, single detonations and structural collapse. The paid Pro edition adds chain reactions, fire and the "Fire Sale" demo with the same API: https://huginhelm.itch.io/godot-destruction-core
Website: https://openclawaimac.github.io/godot-destruction-core/

## Structure
- `addons/godot_destruction_core/lite/dk_world.gd`: DKWorld (Node2D): setup, load_rows, apply_damage, detonate, tick, snapshot/restore, state_digest, signals
- `addons/godot_destruction_core/lite/dk_cell_grid.gd`: DKCellGrid: packed cell grid, apply(damage) -> DKReport, digest
- `addons/godot_destruction_core/lite/dk_material.gd`: DKMaterial: hp, resistances, anchor, rubble, blast and fire data
- `addons/godot_destruction_core/lite/dk_material_set.gd`: DKMaterialSet: ordered materials, index 0 = air
- `addons/godot_destruction_core/lite/dk_damage.gd`: DKDamage: circle, rect, line, cell, cells shapes with falloff and instigator
- `addons/godot_destruction_core/lite/dk_report.gd`: DKReport: destroyed/damaged cells, by material, instigator
- `addons/godot_destruction_core/lite/dk_scheduler.gd`: DKScheduler: budgeted per-frame work queues, never drops work
- `addons/godot_destruction_core/lite/dk_support.gd`: DKSupport: resumable support flood fill (collapse detection)
- `addons/godot_destruction_core/lite/dk_pieces.gd`: DKPieces: falling pieces, rubble, crush damage
- `addons/godot_destruction_core/lite/dk_debris.gd`: DKDebris: capped debris/dust pool (cosmetic, hash-driven)
- `addons/godot_destruction_core/lite/dk_feel.gd`: DKFeel: shake, once-per-chain hitstop, reduced motion
- `addons/godot_destruction_core/lite/dk_tile_renderer.gd`: DKTileRenderer (TileMapLayer): draws the grid and falling pieces
- `addons/godot_destruction_core/lite/dk_chunk_collision.gd`: DKChunkCollision: StaticBody2D per chunk with merged rectangles
- `addons/godot_destruction_core/plugin.cfg`: addon entry and version
- `demos/common/`: shared demo UI (MIT): pixel font, UI atlas, HUD, callouts
- `demos/lite_collapse/`: "Collapse" demo (Lite classes only) + art generator
- `tests/`: headless runner (tests/run_tests.gd) and suites

## Run the tests
```bash
godot --headless --path . --import          # once, and after adding a class_name
bash tools/run_tests.sh /path/to/godot       # must end with "CI: all green" (82 tests)
godot --headless --path . -s res://tests/run_tests.gd -- --filter=collapse   # one suite
GODOT=/path/to/godot bash ci/export_web.sh       # web build(s) into .build/web
```
The runner fails on any test failure, `SCRIPT ERROR`, parse error or leaked object.

## How to extend
- New materials: `DKMaterial.make(id, hp, {...})` in a `DKMaterialSet`; fire and blast behaviour is material data.
- Game logic listens to `DKWorld` signals (`cells_destroyed`, `detonated`, `piece_moved`, `piece_landed`); never edit the grid behind the world's back.
- Custom state that must be saved/hashed: `world.add_extension(name, obj)` with `snapshot_state()`, `restore_state(d)`, `digest()`.
- New tests: a `test_*()` function in a file under `tests/lite/`; the runner finds it.

## Rules
- Determinism: integer state only, no global RNG, no hash-order iteration. `state_digest()` must match between runs.
- Lite never references Pro (`tests/lite/test_layering.gd` enforces it); Pro may use Lite.
- Typed GDScript; class prefix `DK`. No AI-generated art or audio; list every asset in `demos/*/ASSETS.md`.
