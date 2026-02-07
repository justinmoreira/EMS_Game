#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/justinmoreira/EMS_Game.git"
DIR="EMS_Game"

echo "==> EMS Game Installer"
echo ""

# ── Detect platform ───────────────────────────────────────────
detect_platform() {
  if grep -qi microsoft /proc/version 2>/dev/null; then
    echo "wsl"
  elif [ -f /etc/arch-release ]; then
    echo "arch"
  elif grep -qi ubuntu /etc/os-release 2>/dev/null; then
    echo "ubuntu"
  else
    echo "unknown"
  fi
}

PLATFORM=$(detect_platform)
echo "    Platform: $PLATFORM"

# ── Helper: install a package if missing ──────────────────────
ensure_pkg() {
  local cmd="$1"
  if command -v "$cmd" &>/dev/null; then return 0; fi

  echo "==> $cmd not found, installing..."
  case "$PLATFORM" in
    arch)
      sudo pacman -S --noconfirm "$cmd"
      ;;
    ubuntu|wsl)
      sudo apt-get update -qq && sudo apt-get install -y -qq "$cmd"
      ;;
    *)
      echo "ERROR: $cmd is not installed and platform not recognized."
      echo "       Install $cmd manually, then re-run this script."
      exit 1
      ;;
  esac
}

# ── Core dependencies ─────────────────────────────────────────
ensure_pkg git
ensure_pkg curl

# ── Install Nix if missing ────────────────────────────────────
if ! command -v nix &>/dev/null; then
  echo "==> Nix not found, installing via Determinate Systems installer..."
  curl --proto '=https' --tlsv1.2 -sSf -L \
    https://install.determinate.systems/nix | sh -s -- install --no-confirm

  # Source nix in the current shell
  if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  elif [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
  fi

  if ! command -v nix &>/dev/null; then
    echo ""
    echo "WARNING: Nix was installed but isn't in your current PATH."
    echo "         Open a new terminal and re-run this script."
    exit 1
  fi
fi

# ── Install direnv if missing ─────────────────────────────────
if ! command -v direnv &>/dev/null; then
  echo "==> direnv not found, installing..."
  case "$PLATFORM" in
    arch)
      sudo pacman -S --noconfirm direnv
      ;;
    ubuntu|wsl)
      sudo apt-get update -qq && sudo apt-get install -y -qq direnv
      ;;
    *)
      echo "ERROR: direnv is not installed and platform not recognized."
      echo "       Install direnv manually, then re-run this script."
      exit 1
      ;;
  esac
fi

# ── Hook direnv into the user's shell ─────────────────────────
hook_direnv() {
  local rc_file="$1"
  local hook_line="$2"

  if [ -f "$rc_file" ] && grep -qF "direnv" "$rc_file"; then
    return 0
  fi

  if [ -f "$rc_file" ] || [ "$rc_file" = "$HOME/.bashrc" ]; then
    echo "" >> "$rc_file"
    echo "# direnv (added by EMS_Game installer)" >> "$rc_file"
    echo "$hook_line" >> "$rc_file"
    echo "    Added direnv hook to $rc_file"
  fi
}

SHELL_NAME=$(basename "${SHELL:-/bin/bash}")
case "$SHELL_NAME" in
  zsh)
    hook_direnv "$HOME/.zshrc" 'eval "$(direnv hook zsh)"'
    ;;
  bash)
    hook_direnv "$HOME/.bashrc" 'eval "$(direnv hook bash)"'
    ;;
  fish)
    mkdir -p "$HOME/.config/fish/conf.d"
    hook_direnv "$HOME/.config/fish/conf.d/direnv.fish" 'direnv hook fish | source'
    ;;
  *)
    echo "WARNING: Could not auto-hook direnv for shell '$SHELL_NAME'."
    echo "         See https://direnv.net/docs/hook.html"
    ;;
esac

# ── Clone ──────────────────────────────────────────────────────
if [ -d "$DIR" ]; then
  echo "==> Directory '$DIR' already exists, pulling latest..."
  git -C "$DIR" pull --ff-only
else
  echo "==> Cloning repo..."
  git clone "$REPO" "$DIR"
fi

# ── Allow direnv for this project ─────────────────────────────
cd "$DIR"
direnv allow .

# ── Done ───────────────────────────────────────────────────────
echo ""
echo "==> Done! Open a new terminal, then:"
echo ""
echo "    cd $DIR"
echo "    just edit     # open Godot editor"
echo "    just build    # build for web"
echo ""
echo "    The nix dev environment loads automatically via direnv."
echo ""
