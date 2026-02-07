# Configuration
godot_version := "4.3.stable"
# Windows users can override this env var to point to their .exe if they want
godot_bin := env_var_or_default("GODOT_BIN", "godot4")
project_path := "godot"
export_path := "server/public"
export_preset := "Web"

# Default command
default:
    @just --list

# [Setup] Download and install Godot Export Templates (Required for Web Export)
setup:
    #!/usr/bin/env bash
    # Note: On WSL2, this installs to the Linux home directory, which is what the headless builder needs.
    # TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/{{godot_version}}"
    
    # if [ ! -d "$TEMPLATE_DIR" ]; then
    #     echo "Templates not found. Downloading Godot {{godot_version}} templates..."
    #     mkdir -p "$TEMPLATE_DIR"
    #     wget -q --show-progress -O /tmp/templates.tpz https://github.com/godotengine/godot/releases/download/{{godot_version}}/Godot_v{{godot_version}}_export_templates.tpz
    #     unzip -q /tmp/templates.tpz -d /tmp/
    #     mv /tmp/templates/* "$TEMPLATE_DIR"
    #     rm -rf /tmp/templates.tpz /tmp/templates
    #     echo "✅ Templates installed."
    # else
    #     echo "✅ Templates already installed."
    # fi

# [Edit] Open the Godot Editor (GUI)
edit:
    {{godot_bin}} -e --path {{project_path}} &

# [Build] Compile the game to Web (Headless)
build:
    @echo "Building for Web..."
    mkdir -p {{export_path}}
    # The --headless flag is key here; it allows this to run in WSL2 without a window manager
    {{godot_bin}} --headless --path {{project_path}} --export-release "{{export_preset}}" ../{{export_path}}/index.html
    @echo "✅ Build complete in {{export_path}}"

