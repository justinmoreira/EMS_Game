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
    git ls-files -z -- '*.gd' '*.ts' '*.tsx' '*.js' '*.jsx' '*.astro' '*.json' '*.md' '*.yml' '*.yaml' '*.sh' '*.nix' '*.cfg' '*.tscn' | xargs -0 sed -i 's/[[:space:]]*$//'
    echo "✅ All fixes applied!"
else
    exit_code=0
    echo "🔍 Linting TypeScript/Astro (Biome)..."
    (cd "$CLIENT_PATH" && bun run lint) || exit_code=$?
    echo "🔍 Linting GDScript (gdlint)..."
    find "$PROJECT_PATH" -name "*.gd" | xargs gdlint || exit_code=$?
    echo "🔍 Checking GDScript format (gdformat)..."
    find "$PROJECT_PATH" -name "*.gd" | xargs gdformat --diff --check || exit_code=$?
    [ $exit_code -eq 0 ] && echo "✅ All lint checks passed!" || echo "❌ Lint errors found."
    exit $exit_code
fi
