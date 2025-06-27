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
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, ... }:
  {
    # Build darwin flake using:
    # $ darwin-rebuild switch --flake .#alex-mbp
    darwinConfigurations."alex-mbp" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = { inherit inputs; };
      modules = [
        # Host-specific configuration
        ./hosts/alex-mbp/configuration.nix

        # === CORE SYSTEM MODULES ===
        ./modules/system.nix        # System-wide settings and preferences
        ./modules/packages.nix      # Core system packages and utilities
        ./modules/shell.nix         # Shell configuration and environment
        ./modules/fonts.nix         # Font management and typography
        ./modules/ui.nix            # User interface and desktop settings

        # === SPECIALIZED MODULES ===
        ./modules/development.nix   # Development tools and programming environments
        ./modules/brew.nix          # Homebrew package management (GUI apps)
      ];
    };
  };
}
