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
            watchexec      # For watching file changes (HMR)
            python313      # For dev tooling scripts - eventual API
            gdtoolkit_4    # GDScript linter & formatter
          ];

          shellHook = ''
            if [ ! -d client/node_modules/@biomejs ]; then
              cd client && bun install && cd ..
            fi

            # Configure Godot editor to use tab size 4
            bash scripts/set_godot_save_fmt.sh

            # Configure Godot editor to use tab size 4
            bash scripts/set_godot_save_fmt.sh

            if ! systemctl is-active --quiet docker 2>/dev/null; then
              echo "Starting Docker daemon..."
              sudo systemctl start docker
            fi


            # Godot LSP systemd service (GDScript autocomplete + format-on-save in VSCode)
            UNIT_DIR="$HOME/.config/systemd/user"
            UNIT_FILE="$UNIT_DIR/godot-lsp.service"
            if [ ! -f "$UNIT_FILE" ] || ! grep -q "$(pwd)" "$UNIT_FILE"; then
              mkdir -p "$UNIT_DIR"
              sed -e "s|EMS_GAME_DIR|$(pwd)|g" -e "s|NIX_BIN_DIR|$(dirname "$(which nix)")|g" scripts/godot-lsp.service > "$UNIT_FILE"
              systemctl --user daemon-reload
              systemctl --user enable godot-lsp.service
            fi
            systemctl --user start godot-lsp.service 2>/dev/null || true

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

            # Symlink gdformat to a stable path so the EddieDover gdscript-formatter-linter
            # extension finds the same binary that `just lint` uses
            GDFORMAT_BIN=$(command -v gdformat 2>/dev/null)
            if [ -n "$GDFORMAT_BIN" ]; then
              mkdir -p "$HOME/.local/bin"
              ln -sfn "$GDFORMAT_BIN" "$HOME/.local/bin/gdformat"
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
