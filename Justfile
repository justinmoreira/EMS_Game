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
is_wsl := shell("grep -qi microsoft /proc/version && echo 'true' || echo 'false'")

# ── Executable Paths ──────────────────────────────────────────────────────────
# Find system Godot (non-Nix) for GUI, use Nix for headless
godot_linux_gui := shell("which -a godot 2>/dev/null | grep -v '/nix/store' | head -n1 || echo 'godot'")
godot_linux_headless := "godot4"
# Override in .env or via `GODOT_WIN=... just edit`
godot_win := env("GODOT_WIN", "/mnt/c/Program Files/Godot/Godot_v4.6-stable_win64.exe")

# ── Default ───────────────────────────────────────────────────────────────────
_default:
    @just --list

# ── Recipes ───────────────────────────────────────────────────────────────────

[group('setup')]
[doc('Download and install Godot export templates')]
[private]
_init_godot:
    GODOT_RELEASE_TAG={{godot_release_tag}} GODOT_VERSION={{godot_version}} ./scripts/ci/install-templates.sh

[group('setup')]
[doc('Install client dependencies with bun')]
[private]
_init_client:
    #!/usr/bin/env bash
    echo "📦 Installing client dependencies with bun..."
    cd client
    bun install
    cd ..

[group('setup')]
[doc('Authenticate with GitHub CLI and configure Git')]
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

[group('dev')]
[doc('Open the Godot editor (WSL → Windows exe, Linux → native)')]
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

[group('dev')]
[doc('Open the VSCode workspace')]
code:
    code dev.code-workspace

[group('dev')]
[doc('Start Astro dev server with auto Godot rebuild on changes')]
dev: _init_client
    #!/usr/bin/env bash
    echo "🔄 Watching godot/ for changes (auto rebuild)..."
    (watchexec -w godot -e gd,tscn,gdshader,tres -- just build_game &)
    PORT=$(python3 scripts/find_port.py)
    echo "🌐 Starting dev server on port $PORT..."
    cd {{client_path}} && bun run dev --port $PORT

[group('quality')]
[doc('Fast style/format checks (--fix to auto-fix, --fix --unsafe for unsafe fixes)')]
lint fix="" unsafe="":
    CLIENT_PATH={{client_path}} PROJECT_PATH={{project_path}} ./scripts/ci/lint.sh {{fix}} {{unsafe}}

[group('quality')]
[doc('Compilation and build verification (tsc, GDScript, Astro)')]
check:
    GODOT={{godot_linux_headless}} CLIENT_PATH={{client_path}} PROJECT_PATH={{project_path}} ./scripts/ci/check.sh

[group('quality')]
[doc('Run Godot unit tests headlessly')]
test:
    GODOT={{godot_linux_headless}} PROJECT_PATH={{project_path}} ./scripts/ci/test.sh

[group('build')]
[doc('Export Godot game to web artifacts')]
build_game: _init_godot
    @echo "🔨 Exporting Godot for Web..."
    @mkdir -p {{export_path}}
    {{godot_linux_headless}} --headless --path {{project_path}} --export-release "{{export_preset}}" ../{{export_path}}/index.html
    @echo "✅ Godot export complete"

[group('build')]
[doc('Build Astro site')]
build_client:
    @echo "🔨 Building Astro site..."
    cd {{client_path}} && bun run build
    @echo "✅ Astro build complete"

[group('build')]
[doc('Full pipeline: Godot → Astro')]
build: build_game build_client

[group('deploy')]
[doc('Build and serve in Docker')]
run: build _serve

[group('deploy')]
[doc('Launch web build in Docker (http://localhost:8080)')]
[private]
_serve:
    #!/usr/bin/env bash
    docker rm -f ems-game-server 2>/dev/null
    echo "🌐 Serving at http://localhost:8080"
    docker run -d --name ems-game-server -p 8080:80 \
        -v "$(pwd)/server/public:/usr/share/nginx/html:ro" \
        -v "$(pwd)/server/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
        --rm nginx:alpine

[group('deploy')]
[doc('Stop the Docker serve container')]
stop:
    docker rm -f ems-game-server 2>/dev/null
    @echo "🛑 Server stopped."

[group('utils')]
[doc('Print all git-tracked files in a directory with their contents')]
print-files dir=".":
    @git -C {{dir}} ls-files | xargs -I{} sh -c 'echo "===== {{dir}}/{} ====="; cat "{{dir}}/{}" || true'
