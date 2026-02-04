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
          ${pkgs.nixfmt-rfc-style}/bin/nixfmt --check ${./.}/flake.nix
          touch $out
        '';
        system-config = self.darwinConfigurations."alex-mbp".system;
      };

      # System configuration
      darwinConfigurations."alex-mbp" = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
        };

        modules = [
          # Host configuration
          ./hosts/alex-mbp

          # Core system modules
          ./modules/system.nix
          ./modules/packages.nix
          ./modules/shell.nix
          ./modules/ui.nix
          ./modules/services.nix
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
          pkgs.nixfmt-rfc-style
          pkgs.nil
        ];

        shellHook = ''
          echo "nix-darwin development environment"
          echo "Commands: vulnix, nix-tree, nixfmt, nil"
        '';
      };
    };
}
