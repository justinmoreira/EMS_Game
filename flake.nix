{
  description = "EMS Game Dev Environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            godot_4        # The Engine (Headless & GUI)
            just           # The Command Runner
            wget           # For downloading templates
            unzip          # For extracting templates
            docker         # For serving web builds
            fzf            # For just --choose
            gh             # GitHub CLI
            bun            # For Astro web shell (build tool)
            entr           # For watching file changes (optional)
            python313      # For dev tooling scripts - eventual API
            gdtoolkit_4    # GDScript linter & formatter
          ];

          shellHook = ''
            if [ ! -d client/node_modules/@biomejs ]; then
              cd client && bun install && cd ..
            fi

            # Configure Godot editor to use tab size 4
            bash scripts/set_godot_save_fmt.sh

            if ! systemctl is-active --quiet docker 2>/dev/null; then
              echo "Starting Docker daemon..."
              sudo systemctl start docker
            fi


            # Start Godot LSP server in background if not already running (enables format-on-save in VSCode)
            if ! pgrep -f "godot4.*--editor" > /dev/null 2>&1; then
              echo "🎮 Starting Godot LSP server (headless)..."
              godot4 --headless --editor --path "$(pwd)/scripts/bin/godot" &>/dev/null &
              disown
            fi

            # Setup git hooks
            git config core.hooksPath .github/hooks
            chmod +x .github/hooks/pre-push 2>/dev/null || true

            cp ./client/biome.json ./biome.json

            # Symlink Biome binary to a stable path for VSCode Server LSP (biome.lsp.bin)
            # node_modules path changes with version bumps; this stays stable
            BIOME_BIN=$(find "$HOME/.bun/install/cache/@biomejs/cli-linux-x64@"*/biome -type f 2>/dev/null | sort -V | tail -1)
            if [ -n "$BIOME_BIN" ]; then
              mkdir -p "$HOME/.local/bin"
              ln -sfn "$BIOME_BIN" "$HOME/.local/bin/biome"
            fi

            # Silence direnv noise (env diff, loading messages) on future runs
            DIRENV_TOML="$HOME/.config/direnv/direnv.toml"
            if [ ! -f "$DIRENV_TOML" ] || ! grep -q "hide_env_diff" "$DIRENV_TOML"; then
              mkdir -p "$(dirname "$DIRENV_TOML")"
              cat > "$DIRENV_TOML" << 'TOML'
[global]
hide_env_diff = true
warn_timeout = "0s"
TOML
            fi

            RC_FILE="$HOME/.$(basename "''${SHELL:-/bin/bash}")rc"
            if ! grep -q 'DIRENV_LOG_FORMAT' "$RC_FILE" 2>/dev/null; then
              printf '\n# Silence direnv status messages (added by EMS_Game)\nexport DIRENV_LOG_FORMAT=\n' >> "$RC_FILE"
              export DIRENV_LOG_FORMAT=
            fi
          '';
        };
      }
    );
}
