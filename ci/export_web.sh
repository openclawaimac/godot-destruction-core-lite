#!/usr/bin/env bash
# Exports both demos for the web (single-threaded build: no COOP/COEP headers
# needed) into OUT/lite and OUT/pro, plus a small index page linking both.
#   GODOT=/path/to/godot ci/export_web.sh [OUT]   (default .build/web)
# Serve with any static server, e.g. `python3 -m http.server -d OUT 8000`.
# Needs the Godot web export templates for the engine version.
set -euo pipefail
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/.build/web}"
cd "$ROOT"
mkdir -p "$OUT/lite"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web Lite" "$OUT/lite/index.html"
for f in lite/index.html lite/index.pck lite/index.wasm; do
	[ -s "$OUT/$f" ] || { echo "export_web: missing $OUT/$f" >&2; exit 1; }
done
if strings "$OUT/lite/index.pck" | grep -q "addons/godot_destruction_core/pro/"; then
	echo "export_web: the Lite build contains Pro files" >&2
	exit 1
fi
cat > "$OUT/index.html" <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Godot Destruction Core: web demos</title>
<style>body{background:#120d18;color:#e9e3d2;font:16px/1.5 monospace;margin:3em}a{color:#5ad1ff}</style></head>
<body><h1>Godot Destruction Core 0.2.1: web demos</h1>
<ul><li><a href="lite/index.html">Lite: "Collapse"</a> (LMB/RMB charges, M, R, SPACE)</li>
</ul>
<p>Autoplay runs until the first input.</p></body></html>
HTML
echo "export_web: $OUT"
