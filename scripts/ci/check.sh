#!/usr/bin/env bash

GODOT="${GODOT:-godot4}"
CLIENT_PATH="${CLIENT_PATH:-client}"
PROJECT_PATH="${PROJECT_PATH:-godot}"

exit_code=0

echo "🔍 Type-checking TypeScript (tsc)..."
(cd "$CLIENT_PATH" && bunx tsc --noEmit) || exit_code=$?

echo "🔍 Checking GDScript (Godot compiler)..."
$GODOT --headless --path "$PROJECT_PATH" --import 2>/dev/null
gd_errors=0
while IFS= read -r gd_file; do
    rel="res://${gd_file#$PROJECT_PATH/}"
    out=$($GODOT --headless --path "$PROJECT_PATH" --script "$rel" --check-only 2>&1 || true)
    if echo "$out" | grep -q "SCRIPT ERROR: Parse Error:"; then
        echo "$out" | grep -A1 "SCRIPT ERROR: Parse Error:" | grep -v "^--$"
        gd_errors=1
    fi
done < <(find "$PROJECT_PATH" -name "*.gd")
[ $gd_errors -eq 0 ] || { echo "❌ GDScript compile errors found."; exit_code=1; }

echo "🔍 Building Astro site..."
(cd "$CLIENT_PATH" && bun run build) || exit_code=$?

[ $exit_code -eq 0 ] && echo "✅ All checks passed!" || echo "❌ Check errors found."
exit $exit_code
