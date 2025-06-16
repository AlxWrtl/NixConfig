{
  description = "Alexandre's modern modular nix-darwin system flake";

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
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, nix-homebrew, home-manager, ... }:
  {
    # Build darwin flake using:
    # $ darwin-rebuild switch --flake .#alex-mbp
    darwinConfigurations."alex-mbp" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = { inherit inputs; };
      modules = [
        # Host-specific configuration
        ./hosts/alex-mbp/configuration.nix

        # Shared modules
        ./modules/system.nix
        ./modules/packages.nix
        ./modules/shell.nix
        ./modules/fonts.nix
        ./modules/ui.nix
        ./modules/brew.nix

        # nix-homebrew integration
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = true;
            enableRosetta = true;
            user = "alexandrewertel";
            autoMigrate = true;
          };
        }
      ];
    };

    # Expose the packages set for convenience
    darwinPackages = self.darwinConfigurations."alex-mbp".pkgs;
  };
}
