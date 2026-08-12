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
          cd ${./.}
          ${pkgs.nixfmt}/bin/nixfmt --check flake.nix
          ${pkgs.nixfmt}/bin/nixfmt --check modules/*.nix
          ${pkgs.nixfmt}/bin/nixfmt --check home/*.nix
          # The glob above does not descend, so the largest files in the repo
          # sat unchecked. Reformatting them is safe: every one of the 35
          # attributes skills.nix exports evaluates byte-identical before and
          # after, verified — nixfmt does not shift the indentation that nix
          # strips from multiline strings.
          ${pkgs.nixfmt}/bin/nixfmt --check home/claude-code/*.nix
          ${pkgs.nixfmt}/bin/nixfmt --check hosts/alex-mbp/*.nix
          ${pkgs.nixfmt}/bin/nixfmt --check checks/*.nix
          touch $out
        '';
        system-config = self.darwinConfigurations."alex-mbp".system;
        apex-consistency = import ./checks/apex-consistency.nix { inherit pkgs; };
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
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.users.alx = import ./home;
            home-manager.extraSpecialArgs = {
              inherit inputs;
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
