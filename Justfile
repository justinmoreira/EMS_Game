set shell := ["bash", "-c"]
set dotenv-load

# ── Configuration ─────────────────────────────────────────────────────────────
godot_version := "4.6.stable"
godot_release_tag := "4.6-stable"
project_path := "godot"
export_path := "server/public"
export_preset := "Web"

# ── Environment Detection ─────────────────────────────────────────────────────
# Returns "true" if running in WSL, "false" otherwise
is_wsl := shell("grep -qi microsoft /proc/version && echo 'true' || echo 'false'")

# ── Executable Paths ──────────────────────────────────────────────────────────
# [Linux Native]: The binary installed via Nix/Pacman
godot_linux := "godot4"

# [Windows Native]: Path to your Windows Executable (WSL Access Path)
# You can override this in a .env file or by running `GODOT_WIN=... just edit`
godot_win := env("GODOT_WIN", "/mnt/c/Program Files/Godot/Godot_v4.6-stable_win64.exe")

# ── Default Command ───────────────────────────────────────────────────────────
default:
    @just --list

# ── Recipes ───────────────────────────────────────────────────────────────────

# [Setup] Download and install Godot Export Templates (Required for Web Export)
_init_godot:
    #!/usr/bin/env bash
    # Note: On WSL, we still want Linux templates because the HEADLESS builder is Linux.
    TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/{{godot_version}}"

    if [ -f "$TEMPLATE_DIR/web_nothreads_release.zip" ]; then
        echo "✅ Templates already installed."
    else
        echo "⬇️ Downloading Godot {{godot_release_tag}} templates..."
        rm -rf "$TEMPLATE_DIR" /tmp/templates.tpz /tmp/templates
        mkdir -p "$TEMPLATE_DIR"
        wget -q --show-progress -O /tmp/templates.tpz https://github.com/godotengine/godot/releases/download/{{godot_release_tag}}/Godot_v{{godot_release_tag}}_export_templates.tpz
        unzip -q /tmp/templates.tpz -d /tmp/
        mv /tmp/templates/* "$TEMPLATE_DIR"
        rm -rf /tmp/templates.tpz /tmp/templates
        echo "✅ Templates installed."
    fi

# [Edit] Open the Godot Editor (GUI)
# Logic: If WSL -> Launch Windows Exe via cmd.exe. If Arch -> Launch Linux Bin.
edit:
    @echo "🚀 Launching Editor..."
    @if [ "{{is_wsl}}" = "true" ]; then \
        echo "   [Environment]: WSL detected via /proc/version"; \
        if [ ! -f "{{godot_win}}" ]; then \
            echo "   ❌ Error: Windows Godot executable not found at: {{godot_win}}"; \
            echo "   👉 Please set GODOT_WIN in your .env file."; \
            exit 1; \
        fi; \
        WIN_PATH=$$(wslpath -w "{{godot_win}}"); \
        PROJECT_PATH=$$(wslpath -w "{{project_path}}"); \
        echo "   [Executable]:  $$WIN_PATH"; \
        cmd.exe /c "$$WIN_PATH" -e --path "$$PROJECT_PATH" & \
    else \
        echo "   [Environment]: Native Linux detected"; \
        {{godot_linux}} -e --path {{project_path}} & \
    fi

# [Build] Compile the game to Web (Headless)
# Logic: Always use the Linux binary from Nix. It works headless perfectly on WSL.
build:
    @echo "🔨 Building for Web (Headless)..."
    @mkdir -p {{export_path}}
    {{godot_linux}} --headless --path {{project_path}} --export-release "{{export_preset}}" ../{{export_path}}/index.html
    @echo "✅ Build complete in {{export_path}}"

# [Serve] Launch web build in a Docker container (http://localhost:8080)
_serve:
    #!/usr/bin/env bash
    docker rm -f ems-game-server 2>/dev/null
    echo "🌐 Serving at http://localhost:8080"
    docker run -d --name ems-game-server -p 8080:80 \
        -v "$(pwd)/{{export_path}}:/usr/share/nginx/html:ro" \
        -v "$(pwd)/server/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
        --rm nginx:alpine

# [Run] Build and Serve
run:
    @just build
    @just _serve

# [Stop] Stop the serve container
stop:
    docker rm -f ems-game-server 2>/dev/null
    @echo "🛑 Server stopped."