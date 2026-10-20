# Shared demo UI (`demos/common/`): assets, sources and licences

Used by both demos (Lite "Collapse" and Pro "Fire Sale"). Ships with Lite, so it is MIT and has no Pro dependencies.
Everything is original work drawn from code at runtime: no image or font files, no AI art, no third-party assets
(no OFL/CC fonts). Listed in the Obsidian asset register as well.

| File | What | Source | AI? | Author / owner | Licence | SHA-256 (first 16) |
|---|---|---|---|---|---|---|
| `demo_pixel_font.gd` | "Core Block" bitmap pixel font: 62 hand-authored 5x7 glyphs (A-Z, 0-9, punctuation, ·, small x), proportional advance; atlas and 1 px outline silhouettes built at runtime | Written for this repo | No | Joey Vice (original work) | MIT | `113caeea39d83bb3` |
| `demo_ui_art.gd` | Procedural UI atlas: 9-slice plates (Pro amber, Lite teal), stat chips, badges, key caps, speech bubble + tail; 12 hand-authored 11x11 icons (fire, barrel, chain, goon, wreck, burnt, hero, falling, landed, debris, star, dot) | Written for this repo | No | Joey Vice (original work) | MIT | `66e3342e1af20c91` |
| `demo_hud.gd` | Styled HUD: title plate with icon and edition badge, stat chips with value flash, key-cap hint bar | Written for this repo | No | Joey Vice (original work) | MIT | `fa4466e5c34289ac` |
| `demo_callouts.gd` | Floating comic callouts (pop/settle/rise/fade, two-tone fill, pixel outline) and shouted speech lines in the same callout style (2x pixel font, two-tone fill, ink outline + shadow, pop and panic jitter, inked pointer; no plate) | Written for this repo | No | Joey Vice (original work) | MIT | `6412f1ae279bdb95` |
| `demo_ground.gd` | Ground underlay: continues the seamless bedrock tiles from the bottom of the world grid to the screen edge | Written for this repo | No | Joey Vice (original work) | MIT | `15ba3186065d5e55` |
