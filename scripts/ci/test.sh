#!/usr/bin/env bash
set -euo pipefail

GODOT="${GODOT:-godot4}"
PROJECT_PATH="${PROJECT_PATH:-godot}"

echo "🧪 Running Godot unit tests..."
OUTPUT=$($GODOT --headless --path "$PROJECT_PATH" res://scenes/tests/TestRunner.tscn 2>&1)
echo "$OUTPUT"

if echo "$OUTPUT" | grep -q "ERROR:"; then
    echo "❌ Tests failed: script error detected!"
    exit 1
fi
if echo "$OUTPUT" | grep -q "\[FAIL\]"; then
    echo "❌ Tests failed!"
    exit 1
fi
echo "✅ All tests passed!"
