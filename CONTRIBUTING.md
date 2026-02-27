# Contributing

## Code Quality

A pre-push hook runs `just lint` automatically. This will check for formatting issues and potential compilation problems.

If it fails:

```bash
just lint --fix              # Auto-fix formatting issues

just lint --fix --unsafe     # Also apply unsafe fixes if still failing
```

IMPORTANT: Remember to stage and commit the fixes before pushing.

## Formatting

- **GDScript** uses **tabs** (Godot default). `gdformat` enforces this automatically.
- **TS/HTML** uses **2-space indent**. `biome` enforces this automatically.

Both are handled by `just lint --fix` — you don't need to run them separately.

## Pull Requests

- Assign yourself to your PR.
- Request review from whoever you think is relevant.
- Approvers: leave feedback but **don't merge** — merging is the assignee's responsibility.

## Just Commands

```bash
just dev                     # Spin up dev server to view your changes to the website

just lint                    # Check formatting (TypeScript, Astro, GDScript)
just lint --fix              # Auto-fix formatting  --unsafe if ur feeling risky
just check                   # Type-check (tsc), compile (GDScript), build (Astro)
just test                    # Run Godot unit tests headlessly
```

## Adding Tests

Drop a `*Tests.gd` file into `godot/scenes/tests/`. It will be picked up automatically by the test runner — no registration needed. Your test script should:

```gdscript
extends Node

func _ready():
    my_tests()

func my_tests():
    # Use [PASS] and [FAIL] prefixes for the runner to detect results
    if some_condition:
        print("[PASS] description")
    else:
        print("[FAIL] description")
```
