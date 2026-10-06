{
  description = "Alexandre's nix-darwin system configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # DESIGN.md library (brand design systems) read by the `design-md` skill
    awesome-design-md = {
      url = "github:VoltAgent/awesome-design-md";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # Automated checks
      checks.${system} = {
        format-check = pkgs.runCommand "check-nix-format" { } ''
          # The flake source holds tracked files only, so this walks every
          # tracked *.nix; a new directory is covered without a new line here.
          cd ${./.}
          find . -type f -name '*.nix' -print0 | sort -z > "$TMPDIR/nixfiles"
          n=$(tr -cd '\0' < "$TMPDIR/nixfiles" | wc -c)
          [ "$n" -gt 0 ] || { echo "format-check: found no .nix file — the walk itself is broken"; exit 1; }
          xargs -0 ${pkgs.nixfmt}/bin/nixfmt --check < "$TMPDIR/nixfiles"
          echo "format-check: $n files"; touch $out
        '';
        system-config = self.darwinConfigurations."alex-mbp".system;
        agent-instructions = import ./checks/agent-instructions.nix { inherit pkgs; };
        apex-consistency = import ./checks/apex-consistency.nix { inherit pkgs; };
        apex-plan-provenance = import ./checks/apex-plan-provenance.nix { inherit pkgs; };
        claude-config = import ./checks/claude-config.nix { inherit pkgs; };
        claude-mods = import ./checks/claude-mods.nix { inherit pkgs; };
        codex-config = import ./checks/codex-config.nix { inherit pkgs; };
        hook-wiring = import ./checks/hook-wiring.nix { inherit pkgs; };
        js-lint = import ./checks/js-lint.nix { inherit pkgs; };
        readme-consistency = import ./checks/readme-consistency.nix { inherit pkgs; };
        trello-cli = import ./checks/trello-cli.nix { inherit pkgs; };
      };

      # System configuration
      darwinConfigurations."alex-mbp" = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
        };

        modules = [
          # Determinate Nix integration (manages daemon, GC, nix.conf)
          inputs.determinate.darwinModules.default

          # Host configuration
          ./hosts/alex-mbp

          # Core system modules
          ./modules/system.nix
          ./modules/packages.nix
          ./modules/services.nix
          ./modules/ui.nix
          ./modules/brew.nix

          # Home Manager
          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "backup";
              users.alx = import ./home;
              extraSpecialArgs = {
                inherit inputs;
              };
            };
          }
        ];
      };

      # Development shell
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.vulnix
          pkgs.nix-tree
          pkgs.nixfmt
          pkgs.nil
        ];

        shellHook = ''
          echo "nix-darwin development environment"
          echo "Commands: vulnix, nix-tree, nixfmt, nil"
        '';
      };
    };
}
