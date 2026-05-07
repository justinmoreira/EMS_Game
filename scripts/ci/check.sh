#!/usr/bin/env bash

GODOT="${GODOT:-godot4}"
CLIENT_PATH="${CLIENT_PATH:-client}"
PROJECT_PATH="${PROJECT_PATH:-godot}"

exit_code=0

echo "🔍 Type-checking TypeScript (tsc)..."
(cd "$CLIENT_PATH" && bunx tsc --noEmit) || exit_code=$?

echo "🔍 Checking GDScript (Godot editor mode)..."

out=$($GODOT --headless --editor --quit-after 5 --path "$PROJECT_PATH" 2>&1 || true)
if echo "$out" | grep -qE "SCRIPT ERROR:|ERROR:.*autoload|WARNING:.*\.gd"; then
    echo "❌ Errors/warnings:"
    echo "$out" | grep -E "SCRIPT ERROR:|ERROR:.*autoload|WARNING:.*\.gd"
    exit_code=1
fi

echo "🔍 Building Astro site..."
(cd "$CLIENT_PATH" && bun run build) || exit_code=$?

[ $exit_code -eq 0 ] && echo "✅ All checks passed!" || echo "❌ Check errors found."
exit $exit_code
