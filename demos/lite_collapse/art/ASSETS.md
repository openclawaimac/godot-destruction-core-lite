# Lite demo assets: sources and licences

Policy: no AI-generated art, ever. Every asset is original and generated procedurally by a script in
this repo, or CC0 (none used yet). Kits are resold, so every file is listed here with its source.

| File | What | Source | AI? | Author / owner | Licence | SHA-256 (first 16) |
|---|---|---|---|---|---|---|
| `tiles.png` (4096x56) | 8x8 terrain tiles: dirt+grass, rock, brick, wood, steel, bedrock, rubble; 16 neighbour masks x intact/damaged x 16 variants; rock (wrapped-Voronoi cobbles) and bedrock (wrapped noise) are seamless macro textures sliced into position-picked variants (no visible tile grid) | Procedural, `art_src/gen_art.gd` (integer hashes, hand-picked palette; no input images) | No | Joey Vice (original work) | Ships under the kit's licence (Lite: MIT, see `addons/godot_destruction_core/lite/LICENSE`) | `c4ed6e7578d55482` |
| `background.png` (480x270, drawn at 2x) | Sunset sky, stars, sun, clouds, three mountain ridges, pine silhouettes | Procedural, `art_src/gen_art.gd` | No | Joey Vice (original work) | as above | `ce0518abd27b4a04` |
| `art_src/gen_art.gd` | The generator (re-run: `godot --headless --path . -s res://demos/lite_collapse/art_src/gen_art.gd`) | Written for this repo | No | Joey Vice | as above | `89cf19e780f437ef` |
| Explosion flash, fireball, ring, smoke, crosshair | Drawn at runtime with `draw_circle/draw_arc/draw_line` in `demo.gd` | Code, no files | No | Joey Vice | as above | n/a |
| HUD, callouts, pixel font "Core Block", UI icons | Shared demo UI in `demos/common/` (drawn from code, no font or image files; see `demos/common/ASSETS.md`) | Written for this repo | No | Joey Vice (original work) | MIT | see there |

No third-party fonts: the HUD uses the kit's own bitmap font "Core Block".
Screenshots in `docs/screenshots/` and `/workspace/deliver/godot-destruction-core/lite-demo/` are renders of the demo (same ownership).
