# EMS_Game

## Setup

```bash
curl -fsSL https://raw.githubusercontent.com/justinmoreira/EMS_Game/main/scripts/install.sh | bash
```

This single command will:
- Install **git**, **curl**, **Nix**, and **direnv** if missing (supports WSL, Arch, Ubuntu)
- Clone the repo
- Reload your shell so the nix dev environment loads automatically on `cd`

Then:

```bash
cd EMS_Game
just edit     # open Godot editor
just build    # build for web
```
