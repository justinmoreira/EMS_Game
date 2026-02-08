# EMS_Game

## Setup

### WSL

Setup clean distro:
`irm https://raw.githubusercontent.com/justinmoreira/EMS_Game/main/scripts/wsl/install.ps1 | iex`

Launch:
`wsl -d ems-wsl`

Stop:
`wsl --terminate ems-wsl`

Uninstall distro with:
`irm https://raw.githubusercontent.com/justinmoreira/EMS_Game/main/scripts/wsl/uninstall.ps1 | iex`

### Project

*This command will clone the repo for you*

```bash
curl -fsSL https://raw.githubusercontent.com/justinmoreira/EMS_Game/main/scripts/install.sh | bash
```

This single command will:
- Clone the repo
- Install all dependencies if missing (any Linux or wsl)
- Reload your shell so the nix dev environment loads automatically on `cd`

Then:

```bash
just --chose  # Select action

just edit     # open Godot editor

just build    # build for web
just run      # Run Godot webapp (builds and serves)
```