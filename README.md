# EMS_Game

## Setup

```bash
curl -fsSL https://raw.githubusercontent.com/justinmoreira/EMS_Game/main/install.sh | bash
```

This single command will:
- Install **git**, **curl**, **Nix**, and **direnv** if missing (supports WSL, Arch, Ubuntu)
- Clone the repo
- Hook direnv into your shell so `nix develop` loads automatically on `cd`

Once installed, open a new terminal and:

```bash
cd EMS_Game
just edit     # open Godot editor
just build    # build for web
```
