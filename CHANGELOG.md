# Changelog (Lite)

All notable changes to Godot Destruction Core. Versions follow semantic versioning (0.x: API may change).

## 0.2.2 (2026-10-21)

Polish release for the demo; the addon API is unchanged.

### Added (demos)
- `DemoFxArt` (`demos/common/demo_fx_art.gd`, MIT): runtime pixel FX sprites. Smoke puffs and fireballs are lumpy
  multi-lobe shapes in three tones, shock rings are 1-2 px pixel bands; every pixel is fully opaque or fully clear
  and the fade is an ordered (Bayer) dither, so the effects sit on the same pixel grid as the tiles. Sprites are
  cached per radius and dither level and drawn at whole-pixel positions (`snap_origin`).

### Changed (demos)
- The Collapse demo draws smoke, explosion flashes, fireballs and shock rings with `DemoFxArt` instead of smooth
  anti-aliased / translucent `draw_circle` and `draw_arc` circles.

### Tests
- New `tests/lite/test_demo_fx.gd`: puff and ring sprites have hard alpha and only their palette colours, fades drop
  pixels by dithering, puff silhouettes are not discs, draw positions snap to the pixel grid, and no demo source
  draws circles or arcs at runtime.
- Totals: 82 headless tests, all green on Godot 4.7.2 and 4.6.

## 0.2.1 (2026-10-20)

### Added (Lite)
- `DKTileRenderer.macro_tiles {id: Vector2i(px, py)}`: materials listed there pick their variant by position
  ((x mod px) + px * (y mod py)) instead of a hash, so the art can slice one seamless texture into variants
  and neighbouring cells line up with no visible tile grid. `variant_for(mi, x, y)` exposes the pick.

### Changed (demos)
- Rock and bedrock in the Collapse demo are seamless macro textures (wrapped-Voronoi cobbles, wrapped noise);
  atlases now carry 16 variants. Bedrock continues below the world grid to the screen edge (`DemoGround`).
- New test guards against engine/default-font text in the demos.

## 0.2.0 (2026-10-20)

### Added (demos)
- Shared MIT demo UI (`demos/common/`): own bitmap pixel font "Core Block", 9-slice/icon atlas, styled HUD,
  pop/scale callouts that stack instead of overlapping. The Collapse demo uses it (no third-party font any more).
- Web export preset for the Collapse demo, `ci/export_web.sh`, and a headless-Chrome smoke test `ci/web_smoke.py`.
- `plugin.cfg` / `plugin.gd` addon entry; `DKWorld.VERSION`.

### Changed
- CI fails if an in-house game's name appears in any file or file name; the kit contains none.
- No default Godot boot-splash image.

## 0.1.0 (2026-10-20)

- Lite: cell grid, materials, damage shapes, scheduler, DKWorld with signals, snapshots and digests,
  instigator attribution; incremental connectivity collapse with falling pieces, rubble and crush damage;
  debris pool, feel (shake, per-chain hitstop, reduced motion); TileMapLayer renderer and chunk collision;
  the "Collapse" demo.
- Headless test runner and CI with a Lite-standalone check.
