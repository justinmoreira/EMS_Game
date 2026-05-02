#!/usr/bin/env bash

GODOT="${GODOT:-godot4}"
CLIENT_PATH="${CLIENT_PATH:-client}"
PROJECT_PATH="${PROJECT_PATH:-godot}"

ts_check() {
    (cd "$CLIENT_PATH" && bunx tsc --noEmit)
}

gd_check() {
    "$GODOT" --headless --path "$PROJECT_PATH" --import 2>/dev/null
    local errors=0
    local out rel
    while IFS= read -r gd_file; do
        rel="res://${gd_file#"$PROJECT_PATH"/}"
        out=$("$GODOT" --headless --path "$PROJECT_PATH" --script "$rel" --check-only 2>&1 || true)
        if echo "$out" | grep -q "SCRIPT ERROR: Parse Error:"; then
            echo "$out" | grep -A1 "SCRIPT ERROR: Parse Error:" | grep -v "^--$"
            errors=1
        fi
    done < <(find "$PROJECT_PATH" -name "*.gd")
    return $errors
}

build_check() {
    (cd "$CLIENT_PATH" && bun run build)
}

# Run a labeled job, prefixing every output line with its label so the
# interleaved output of parallel jobs is readable.
labeled() {
    local label=$1; shift
    echo "🔍 [$label] starting..."
    if "$@" 2>&1 | sed -u "s/^/[$label] /"; then
        echo "✅ [$label] passed"
        return 0
    fi
    return "${PIPESTATUS[0]}"
}

# Launch all three checks in parallel
labeled "tsc"        ts_check    & ts_pid=$!
labeled "gdscript"   gd_check    & gd_pid=$!
labeled "astro"      build_check & build_pid=$!

# Wait for each to finish; on the first failure, kill the rest and exit.
total=3
done=0
while [ $done -lt $total ]; do
    if wait -n; then
        done=$((done + 1))
    else
        rc=$?
        kill "$ts_pid" "$gd_pid" "$build_pid" 2>/dev/null
        wait 2>/dev/null
        echo "❌ Check failed (exit $rc). Remaining jobs killed."
        exit "$rc"
    fi
done

echo "✅ All checks passed!"
exit 0
