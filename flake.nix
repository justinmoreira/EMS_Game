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
            bun                          # For Astro web shell (build tool)
            entr                         # For watching file changes (optional)
            gdtoolkit_4                  # GDScript linter/formatter (gdlint, gdformat)
          ];

          shellHook = ''
            # Setup web compilation template
            just _init_godot

            # Install client dependencies if needed
            if [ ! -d "client/node_modules" ]; then
              echo "📦 Installing client dependencies..."
              just _init_client
            fi

            # Configure Godot editor to use 2-space indent (matches rest of project)
            GODOT_SETTINGS="$HOME/.config/godot/editor_settings-4.tres"
            if [ ! -f "$GODOT_SETTINGS" ]; then
              mkdir -p "$(dirname "$GODOT_SETTINGS")"
              printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\ntext_editor/indent/type = 1\ntext_editor/indent/size = 2\n' > "$GODOT_SETTINGS"
            else
              sed -i 's|text_editor/indent/type = .*|text_editor/indent/type = 1|' "$GODOT_SETTINGS"
              sed -i 's|text_editor/indent/size = .*|text_editor/indent/size = 2|' "$GODOT_SETTINGS"
              grep -q "text_editor/indent/type" "$GODOT_SETTINGS" || sed -i '/\[resource\]/a text_editor/indent/type = 1' "$GODOT_SETTINGS"
              grep -q "text_editor/indent/size" "$GODOT_SETTINGS" || sed -i '/\[resource\]/a text_editor/indent/size = 2' "$GODOT_SETTINGS"
            fi

            if ! systemctl is-active --quiet docker 2>/dev/null; then
              echo "Starting Docker daemon..."
              sudo systemctl start docker
            fi


            # Start Godot LSP server in background if not already running (enables format-on-save in VSCode)
            if ! pgrep -f "godot4.*--editor" > /dev/null 2>&1; then
              echo "🎮 Starting Godot LSP server (headless)..."
              godot4 --headless --editor --path "$(pwd)/godot" &>/dev/null &
              disown
            fi

            # Setup git hooks
            git config core.hooksPath .githooks
            chmod +x .githooks/pre-push 2>/dev/null || true

            cp ./client/biome.json ./biome.json

            echo "🎮 EMS Game Dev Environment Loaded"
          '';
        };
      }
    );
}
