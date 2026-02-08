#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/justinmoreira/EMS_Game.git"

echo "==> EMS Game Installer"
echo ""

# ── Determine project directory ───────────────────────────────
# Check if we're already inside EMS_Game or a subdirectory of it
find_project_dir() {
  local current_dir="$PWD"
  while [ "$current_dir" != "/" ]; do
    if [ "$(basename "$current_dir")" = "EMS_Game" ]; then
      echo "$current_dir"
      return 0
    fi
    current_dir="$(dirname "$current_dir")"
  done
  # Not found in parent directories, use EMS_Game in current location
  echo "${PWD}/EMS_Game"
}

DIR=$(find_project_dir)
echo "    Project directory: $DIR"

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

# systemd for
ensure_systemd() {
  # Only necessary for WSL; native Ubuntu usually has it.
  if [ "$PLATFORM" = "wsl" ]; then
    if ! pidof systemd >/dev/null; then
      echo "==> ❌ Systemd is NOT running."
      echo "    The Nix daemon requires systemd to function correctly."

      # Check if we already tried to enable it
      if ! grep -q "systemd=true" /etc/wsl.conf 2>/dev/null; then
         echo "    Attempting to enable systemd in /etc/wsl.conf..."
         # We use tee -a to append safely with sudo
         echo -e "\n[boot]\nsystemd=true" | sudo tee -a /etc/wsl.conf >/dev/null
         echo "    ✓ configuration added."
      else
         echo "    Configuration exists, but WSL hasn't been restarted."
      fi

      echo ""
      echo "❗ ACTION REQUIRED ❗"
      echo "You must restart this WSL instance for systemd to start."
      echo "  1. Exit this shell."
      echo "  2. In PowerShell, run: wsl --terminate ems-wsl"
      echo "  3. Re-open WSL and run this script again."
      echo ""
      exit 1
    fi
    echo "==> ✓ Systemd is running."
  fi
}
ensure_systemd

# ── Helper: install a package if missing ──────────────────────
ensure_pkg() {
  local cmd="$1"
  local pkg="${2:-$cmd}"  # Optional package name (defaults to cmd)
  if command -v "$cmd" &>/dev/null; then return 0; fi

  echo "==> $cmd not found, installing..."
  case "$PLATFORM" in
    arch)
      sudo pacman -S --noconfirm "$pkg"
      ;;
    ubuntu|wsl)
      sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg"
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
ensure_pkg docker docker.io  # docker.io on Ubuntu/Debian, docker on Arch

# ── Setup Docker permissions ──────────────────────────────────
if ! groups "$USER" | grep -q docker; then
  echo "==> Adding $USER to docker group..."
  sudo usermod -aG docker "$USER"
  echo "    ✓ User added to docker group"
fi

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

SHELL_NAME=$(basename "${SHELL:-/bin/bash}")
RC_FILE="~/.${SHELL_NAME}rc"

# ── Hook nix + direnv into the user's shell ───────────────────
add_line() {
  local rc_file="$1"
  local marker="$2"
  local line="$3"

  if [ -f "$rc_file" ] && grep -qF "$marker" "$rc_file"; then
    return 0
  fi

  echo "" >> "$rc_file"
  echo "$line" >> "$rc_file"
  echo "    Added '$marker' to $rc_file"
}

NIX_SOURCE='# nix (added by EMS_Game installer)
if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi'

case "$SHELL_NAME" in
  zsh)
    add_line "$HOME/.zshrc" "nix-daemon.sh" "$NIX_SOURCE"
    add_line "$HOME/.zshrc" "direnv hook" '# direnv (added by EMS_Game installer)
eval "$(direnv hook zsh)"'
    ;;
  bash)
    add_line "$HOME/.bashrc" "nix-daemon.sh" "$NIX_SOURCE"
    add_line "$HOME/.bashrc" "direnv hook" '# direnv (added by EMS_Game installer)
eval "$(direnv hook bash)"'
    ;;
  fish)
    mkdir -p "$HOME/.config/fish/conf.d"
    add_line "$HOME/.config/fish/conf.d/nix.fish" "nix-daemon" '# nix (added by EMS_Game installer)
if test -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
end'
    add_line "$HOME/.config/fish/conf.d/direnv.fish" "direnv hook" '# direnv (added by EMS_Game installer)
direnv hook fish | source'
    ;;
  *)
    echo "WARNING: Could not auto-hook nix/direnv for shell '$SHELL_NAME'."
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
echo "============================================"
echo "  Install complete!"
echo ""
echo "  Manually run 'cd $DIR && exec newgrp docker"
echo "============================================"
echo ""
