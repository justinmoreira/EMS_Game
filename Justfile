# Configuration
godot_version := "4.6.stable"          # local template dir name (dot)
godot_release_tag := "4.6-stable"      # GitHub release tag (dash)
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
    TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/{{godot_version}}"

    if [ -f "$TEMPLATE_DIR/web_nothreads_release.zip" ]; then
        echo "Templates already installed."
    else
        echo "Templates not found. Downloading Godot {{godot_release_tag}} templates (~1.2 GB)..."
        rm -rf "$TEMPLATE_DIR" /tmp/templates.tpz /tmp/templates
        mkdir -p "$TEMPLATE_DIR"
        wget -q --show-progress -O /tmp/templates.tpz https://github.com/godotengine/godot/releases/download/{{godot_release_tag}}/Godot_v{{godot_release_tag}}_export_templates.tpz
        unzip -q /tmp/templates.tpz -d /tmp/
        mv /tmp/templates/* "$TEMPLATE_DIR"
        rm -rf /tmp/templates.tpz /tmp/templates
        echo "Templates installed."
    fi

# [Edit] Open the Godot Editor (GUI)
edit:
    {{godot_bin}} -e --path {{project_path}} &

# [Build] Compile the game to Web (Headless)
build: setup
    @echo "Building for Web..."
    mkdir -p {{export_path}}
    # The --headless flag is key here; it allows this to run in WSL2 without a window manager
    {{godot_bin}} --headless --path {{project_path}} --export-release "{{export_preset}}" ../{{export_path}}/index.html
    @echo "Build complete in {{export_path}}"

# [Serve] Launch web build in a Docker container (http://localhost:8080)
serve:
    #!/usr/bin/env bash
    docker rm -f ems-game-server 2>/dev/null
    echo "Serving at http://localhost:8080"
    docker run -d --name ems-game-server -p 8080:80 \
        -v "$(pwd)/{{export_path}}:/usr/share/nginx/html:ro" \
        -v "$(pwd)/server/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
        --rm nginx:alpine

# [Stop] Stop the serve container
stop:
    docker rm -f ems-game-server 2>/dev/null
    @echo "Server stopped."
