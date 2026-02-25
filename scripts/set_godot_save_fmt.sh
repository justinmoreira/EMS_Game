#!/usr/bin/env bash
# Configure Godot editor tab size to 4 (uses tabs, Godot default)
# Uses temp file + mv instead of sed -i (sed -i fails silently on WSL/NTFS)

configure_godot_indent() {
  local f="$1"
  if grep -q "text_editor/indent/size = 4" "$f" 2>/dev/null; then
    return # already configured
  elif [ -f "$f" ]; then
    local tmp="$f.tmp"
    awk '
      /text_editor\/indent\/size/ { print "text_editor/indent/size = 4"; next }
      /^\[resource\]$/ { print; if (!injected) { print "text_editor/indent/size = 4"; injected=1 }; next }
      { print }
    ' "$f" > "$tmp" && mv "$tmp" "$f"
  else
    mkdir -p "$(dirname "$f")"
    printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\ntext_editor/indent/size = 4\n' > "$f"
  fi
}

# Patch all Godot editor settings files (editor_settings-4.tres, editor_settings-4.6.tres, etc.)
patch_godot_dir() {
  local dir="$1"
  if [ -d "$dir" ]; then
    for f in "$dir"/editor_settings-*.tres; do
      [ -f "$f" ] && configure_godot_indent "$f"
    done
  fi
}

# Linux (headless Godot)
patch_godot_dir "$HOME/.config/godot"

# Windows editor (WSL only) — patches %APPDATA%\Godot settings
if grep -qi microsoft /proc/version 2>/dev/null; then
  WIN_USER=$(powershell.exe -NoProfile -Command '[Environment]::UserName' 2>/dev/null | tr -d '\r')
  if [ -n "$WIN_USER" ]; then
    patch_godot_dir "/mnt/c/Users/$WIN_USER/AppData/Roaming/Godot"
  fi
fi
