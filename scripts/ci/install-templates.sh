#!/usr/bin/env bash
set -euo pipefail

GODOT_RELEASE_TAG="${GODOT_RELEASE_TAG:-4.6-stable}"
GODOT_VERSION="${GODOT_VERSION:-4.6.stable}"

TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}"

if [ -f "$TEMPLATE_DIR/web_nothreads_release.zip" ]; then
    echo "✅ Templates already installed."
else
    echo "⬇️ Downloading Godot ${GODOT_RELEASE_TAG} templates..."
    rm -rf "$TEMPLATE_DIR" /tmp/templates.tpz /tmp/templates
    mkdir -p "$TEMPLATE_DIR"
    wget -q --show-progress -O /tmp/templates.tpz \
        "https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE_TAG}/Godot_v${GODOT_RELEASE_TAG}_export_templates.tpz"
    unzip -q /tmp/templates.tpz -d /tmp/
    mv /tmp/templates/* "$TEMPLATE_DIR"
    rm -rf /tmp/templates.tpz /tmp/templates
    echo "✅ Templates installed."
fi
