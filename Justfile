set shell := ["bash", "-c"]
set dotenv-load

# ── Configuration ─────────────────────────────────────────────────────────────
godot_version := "4.6.stable"
godot_release_tag := "4.6-stable"
project_path := "godot"
client_path := "client"
export_path := "client/public/godot"
export_preset := "Web"

# ── Environment Detection ─────────────────────────────────────────────────────
# Returns "true" if running in WSL, "false" otherwise
is_wsl := shell("grep -qi microsoft /proc/version && echo 'true' || echo 'false'")

# ── Executable Paths ──────────────────────────────────────────────────────────
# [Linux Native]: Find system Godot (non-Nix) for GUI, use Nix for headless
godot_linux_gui := shell("which -a godot 2>/dev/null | grep -v '/nix/store' | head -n1 || echo 'godot'")
godot_linux_headless := "godot4"

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
# Logic: If WSL -> Launch Windows Exe via PowerShell. If Arch -> Launch Linux Bin.
edit:
    @echo "🚀 Launching Editor..."
    @if [ "{{is_wsl}}" = "true" ]; then \
        echo "   [Environment]: WSL detected via /proc/version"; \
        if [ ! -f "{{godot_win}}" ]; then \
            echo "   ❌ Error: Windows Godot executable not found at: {{godot_win}}"; \
            echo "   👉 Please set GODOT_WIN in your .env file."; \
            exit 1; \
        fi; \
        echo "   [Executable]:  {{godot_win}}"; \
        powershell.exe -Command "Start-Process '$(wslpath -w "{{godot_win}}")' -ArgumentList '-e','--path','$(wslpath -w "{{project_path}}")'"; \
    else \
        echo "   [Environment]: Native Linux detected"; \
        {{godot_linux_gui}} -e --path {{project_path}} &>/dev/null & \
    fi

_init_client:
    #!/usr/bin/env bash
    echo "📦 Installing client dependencies with bun..."
    cd client
    bun install
    cd ..

# [Build] Export Godot game to web artifacts
build_game:
    @echo "🔨 Exporting Godot for Web..."
    @mkdir -p {{export_path}}
    {{godot_linux_headless}} --headless --path {{project_path}} --export-release "{{export_preset}}" ../{{export_path}}/index.html
    @echo "✅ Godot export complete"

# [Build] Build Astro site (outputs to server/public/)
_build_client:
    @echo "🔨 Building Astro site..."
    cd {{client_path}} && bun run build
    @echo "✅ Astro build complete"

# [Build] Full pipeline: Godot → Astro → server/public/
build:
    @just build_game
    @just _build_client

# [Dev] Start Astro dev server (run build_game first if needed)
dev:
    cd {{client_path}} && bun run dev

# [Serve] Launch web build in a Docker container (http://localhost:8080)
_serve:
    #!/usr/bin/env bash
    docker rm -f ems-game-server 2>/dev/null
    echo "🌐 Serving at http://localhost:8080"
    docker run -d --name ems-game-server -p 8080:80 \
        -v "$(pwd)/server/public:/usr/share/nginx/html:ro" \
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

# [Auth] Authenticate with GitHub CLI and configure Git
github-auth:
    #!/usr/bin/env bash
    echo "🔐 Checking GitHub authentication..."
    
    # Check if already authenticated
    if gh auth status &>/dev/null; then
        echo "✅ Already authenticated with GitHub"
        gh auth status
        echo ""
        read -p "Do you want to logout and re-authenticate? [y/N]: " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            gh auth logout
            gh auth login
        fi
    else
        echo "🔑 Not authenticated. Starting login..."
        gh auth login
    fi
    
    echo ""
    echo "🔧 Checking Git configuration..."
    
    # Check git user.name
    if ! git config --global user.name &>/dev/null; then
        echo "⚠️  Git user.name not set"
        read -p "Enter your name for Git commits: " git_name
        git config --global user.name "$git_name"
        echo "✅ Set user.name to: $git_name"
    else
        echo "✅ user.name: $(git config --global user.name)"
    fi
    
    # Check git user.email
    if ! git config --global user.email &>/dev/null; then
        echo "⚠️  Git user.email not set"
        read -p "Enter your email for Git commits: " git_email
        git config --global user.email "$git_email"
        echo "✅ Set user.email to: $git_email"
    else
        echo "✅ user.email: $(git config --global user.email)"
    fi
    
    echo ""
    echo "🎉 Authentication setup complete!"

code:
    code dev.code-workspace