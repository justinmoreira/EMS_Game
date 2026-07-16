#!/usr/bin/env bash

GODOT="${GODOT:-godot4}"
CLIENT_PATH="${CLIENT_PATH:-client}"
PROJECT_PATH="${PROJECT_PATH:-godot}"

tsc_log=$(mktemp); gd_log=$(mktemp); astro_log=$(mktemp)
trap 'rm -f "$tsc_log" "$gd_log" "$astro_log"' EXIT

echo "🔍 Running check (tsc + GDScript + Astro build) in parallel..."

(cd "$CLIENT_PATH" && bunx tsc --noEmit) > "$tsc_log" 2>&1 & tsc_pid=$!

(
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
    exit $gd_errors
) > "$gd_log" 2>&1 & gd_pid=$!

(cd "$CLIENT_PATH" && bun run build) > "$astro_log" 2>&1 & astro_pid=$!

declare -A label=([$tsc_pid]="tsc" [$gd_pid]="GDScript" [$astro_pid]="Astro build")
declare -A logs=([$tsc_pid]="$tsc_log" [$gd_pid]="$gd_log" [$astro_pid]="$astro_log")

exit_code=0
for _ in 1 2 3; do
    wait -n -p done_pid
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "❌ ${label[$done_pid]} failed:"
        cat "${logs[$done_pid]}"
        kill $tsc_pid $gd_pid $astro_pid 2>/dev/null
        exit_code=$rc
        break
    fi
    echo "✅ ${label[$done_pid]}"
done

[ $exit_code -eq 0 ] && echo "✅ All checks passed!" || echo "❌ Check errors found."
exit $exit_code
