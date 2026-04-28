#!/usr/bin/env bash

CLIENT_PATH="${CLIENT_PATH:-client}"
PROJECT_PATH="${PROJECT_PATH:-godot}"

if [ "${1:-}" = "--fix" ]; then
    set -e
    unsafe="${2:-}"
    echo "🔧 Fixing TypeScript/Astro (Biome)..."
    (cd "$CLIENT_PATH" && bun run fix -- $unsafe)
    echo "🔧 Formatting GDScript (gdformat)..."
    find "$PROJECT_PATH" -name "*.gd" | xargs gdformat
    echo "🔧 Removing trailing whitespace..."
    git ls-files -z -- '*.gd' '*.gdshader' '*.tscn' '*.godot' '*.cfg' '*.ts' '*.tsx' '*.js' '*.mjs' '*.jsx' '*.astro' '*.css' '*.json' '*.md' '*.yml' '*.yaml' '*.sh' '*.ps1' '*.py' '*.nix' '*.conf' '*.service' '*.svg' | xargs -0 grep -rlZ '[[:space:]]$' | xargs -0 -r sed -i 's/[[:space:]]*$//'
    echo "✅ All fixes applied!"
else
    biome_log=$(mktemp); gdlint_log=$(mktemp); gdformat_log=$(mktemp)
    trap 'rm -f "$biome_log" "$gdlint_log" "$gdformat_log"; kill 0 2>/dev/null' EXIT

    echo "🔍 Running lint (Biome + gdlint + gdformat) in parallel..."
    (cd "$CLIENT_PATH" && bun run lint) > "$biome_log" 2>&1 & biome_pid=$!
    (find "$PROJECT_PATH" -name "*.gd" -not -path "*/addons/*" -print0 | xargs -0 gdlint) > "$gdlint_log" 2>&1 & gdlint_pid=$!
    (find "$PROJECT_PATH" -name "*.gd" -print0 | xargs -0 gdformat --diff --check) > "$gdformat_log" 2>&1 & gdformat_pid=$!

    declare -A label=([$biome_pid]="Biome (TS/Astro)" [$gdlint_pid]="gdlint" [$gdformat_pid]="gdformat --check")
    declare -A logs=([$biome_pid]="$biome_log" [$gdlint_pid]="$gdlint_log" [$gdformat_pid]="$gdformat_log")

    exit_code=0
    for _ in 1 2 3; do
        wait -n -p done_pid
        rc=$?
        if [ $rc -ne 0 ]; then
            echo "❌ ${label[$done_pid]} failed:"
            cat "${logs[$done_pid]}"
            kill $biome_pid $gdlint_pid $gdformat_pid 2>/dev/null
            exit_code=$rc
            break
        fi
        echo "✅ ${label[$done_pid]}"
    done

    [ $exit_code -eq 0 ] && echo "✅ All lint checks passed!" || echo "❌ Lint errors found."
    exit $exit_code
fi
