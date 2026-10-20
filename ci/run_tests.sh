#!/usr/bin/env bash
# CI: runs the full suite, then proves Lite stands alone by copying the repo
# into .build/lite-only, deleting the Pro addon folder (and the Pro tests, as a
# Lite-only distribution would, plus the Pro demos) and running the default runner there.
# Fails on any test failure, script/parse error, or leaked objects at exit.
set -euo pipefail
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Runs Godot, echoes the output and fails if it contains engine errors that
# would not show up as test failures (a runtime error inside a test does not
# abort it, and leaks point to reference cycles).
run_checked() {
	local log
	log="$(mktemp)"
	set +e
	"$GODOT" "$@" 2>&1 | tee "$log"
	local code=${PIPESTATUS[0]}
	set -e
	if [ "$code" -ne 0 ]; then
		echo "CI: godot exited with $code" >&2
		rm -f "$log"
		exit "$code"
	fi
	if grep -qE "SCRIPT ERROR|Parse Error|^ERROR:|leaked at exit|resources still in use" "$log"; then
		echo "CI: engine errors or leaks in output (see above)" >&2
		rm -f "$log"
		exit 1
	fi
	rm -f "$log"
}

# Kits never ship another game's content: fail on the in-house game's name in
# any file or file name (the pattern is split so this script does not match itself).
FORBIDDEN="toon""force"
if grep -rIil --exclude-dir=.git --exclude-dir=.godot --exclude-dir=.build "$FORBIDDEN" . ; then
	echo "CI: forbidden name found in the files above" >&2
	exit 1
fi
if find . -path ./.git -prune -o -path ./.godot -prune -o -path ./.build -prune -o -iname "*$FORBIDDEN*" -print | grep -q . ; then
	find . -path ./.git -prune -o -path ./.godot -prune -o -path ./.build -prune -o -iname "*$FORBIDDEN*" -print
	echo "CI: forbidden name in a file name" >&2
	exit 1
fi
echo "CI: no foreign game names"

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
echo "--- Full suite (Lite + Pro) ---"
run_checked --headless --path . -s res://tests/run_tests.gd

LITE="$ROOT/.build/lite-only"
rm -rf "$LITE"
mkdir -p "$LITE"
# Everything except VCS, editor cache and build output.
tar -C "$ROOT" --exclude=./.git --exclude=./.godot --exclude=./.build -cf - . | tar -C "$LITE" -xf -
rm -rf "$LITE/addons/godot_destruction_core/pro" "$LITE/tests/pro" "$LITE"/demos/pro_*
if [ -d "$LITE/addons/godot_destruction_core/pro" ]; then
	echo "CI: Pro folder still present in the Lite copy" >&2
	exit 1
fi
# The import of a Lite-only checkout must be clean (no missing Pro classes).
IMPORT_LOG="$(mktemp)"
"$GODOT" --headless --path "$LITE" --import >"$IMPORT_LOG" 2>&1 || true
if grep -qE "SCRIPT ERROR|Parse Error|Could not find type|Identifier .* not declared" "$IMPORT_LOG"; then
	cat "$IMPORT_LOG"
	echo "CI: Lite-only import has errors" >&2
	exit 1
fi
rm -f "$IMPORT_LOG"
echo "--- Lite standalone (Pro folder deleted, default runner) ---"
run_checked --headless --path "$LITE" -s res://tests/run_tests.gd
echo "CI: all green"
