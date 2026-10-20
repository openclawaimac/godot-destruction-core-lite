#!/usr/bin/env bash
# Strict test runner: full suite, then (Pro) a Lite-standalone copy with the Pro folder deleted.
# Fails on any test failure, script/parse error or leaked object. Usage: bash tools/run_tests.sh [/path/to/godot]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-godot}}" exec bash ci/run_tests.sh
