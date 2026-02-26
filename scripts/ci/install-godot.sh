#!/usr/bin/env bash
set -euo pipefail

GODOT_RELEASE_TAG="${GODOT_RELEASE_TAG:-4.6-stable}"

echo "⬇️ Installing Godot ${GODOT_RELEASE_TAG}..."
wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE_TAG}/Godot_v${GODOT_RELEASE_TAG}_linux.x86_64.zip"
unzip -q "Godot_v${GODOT_RELEASE_TAG}_linux.x86_64.zip"
sudo mv "Godot_v${GODOT_RELEASE_TAG}_linux.x86_64" /usr/local/bin/godot4
sudo chmod +x /usr/local/bin/godot4
echo "✅ Godot installed."
