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
          ];

          shellHook = ''
            # Setup web compilation template
            just _init_godot

            cd client && bun install && cd ..

            if ! systemctl is-active --quiet docker 2>/dev/null; then
              echo "Starting Docker daemon..."
              sudo systemctl start docker
            fi
            echo "🎮 EMS Game Dev Environment Loaded"
          '';
        };
      }
    );
}
