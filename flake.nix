{
  # ============================================================================
  # NIX-DARWIN SYSTEM FLAKE
  # ============================================================================
  # Alexandre's modern modular nix-darwin system configuration
  # Provides reproducible macOS system configuration using Nix flakes

  description = "Alexandre's modern modular nix-darwin system flake";

  # ============================================================================
  # FLAKE INPUTS & DEPENDENCIES
  # ============================================================================

  inputs = {
    # === Core Nix Ecosystem ===
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";  # Primary package repository

    # === nix-darwin Framework ===
    nix-darwin = {
      url = "github:LnL7/nix-darwin";                      # macOS system configuration framework
      inputs.nixpkgs.follows = "nixpkgs";                  # Use our nixpkgs version
    };

    # === Home Manager (Future Integration) ===
    home-manager = {
      url = "github:nix-community/home-manager/master";    # User environment management
      inputs.nixpkgs.follows = "nixpkgs";                  # Use our nixpkgs version
    };
  };

  # ============================================================================
  # FLAKE OUTPUTS & SYSTEM CONFIGURATIONS
  # ============================================================================

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, ... }:
  {
    # === DARWIN SYSTEM CONFIGURATIONS ===
    # Build and switch to configuration using:
    # $ darwin-rebuild switch --flake .#alex-mbp
    
    darwinConfigurations = {
      # === Alexandre's MacBook Pro Configuration ===
      "alex-mbp" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";                          # Apple Silicon architecture
        specialArgs = { inherit inputs; };                  # Pass inputs to all modules
        
        modules = [
          # === HOST-SPECIFIC CONFIGURATION ===
          ./hosts/alex-mbp                                  # Host module (networking, users, platform)

          # === CORE SYSTEM MODULES ===
          ./modules/system.nix                              # Core Nix settings, TouchID, security
          ./modules/packages.nix                            # System utilities & CLI tools
          ./modules/shell.nix                               # Zsh, aliases, environment setup
          ./modules/starship.nix                            # Starship prompt configuration
          ./modules/fonts.nix                               # Programming fonts & typography
          ./modules/ui.nix                                  # macOS UI/UX & system defaults

          # === SPECIALIZED MODULES ===
          ./modules/development.nix                         # Development environments & tools
          ./modules/brew.nix                                # Homebrew for GUI applications
          ./modules/claude-code.nix                         # Claude Code CLI integration
        ];
      };
    };

    # ============================================================================
    # ADDITIONAL FLAKE OUTPUTS (Future Extensions)
    # ============================================================================
    
    # === Development Shells (Future) ===
    # devShells.aarch64-darwin = {
    #   default = nixpkgs.legacyPackages.aarch64-darwin.mkShell {
    #     buildInputs = [ /* development tools */ ];
    #   };
    # };

    # === Custom Packages (Future) ===
    # packages.aarch64-darwin = {
    #   custom-package = /* custom package definition */;
    # };

    # === Deployment Configurations (Future) ===
    # deploy.nodes = {
    #   alex-mbp = {
    #     hostname = "alex-mbp.local";
    #     profiles.system = {
    #       path = self.darwinConfigurations."alex-mbp".system;
    #     };
    #   };
    # };
  };

  # ============================================================================
  # FLAKE CONFIGURATION NOTES
  # ============================================================================
  #
  # Architecture Overview:
  # ├── flake.nix                    # This file - system orchestration
  # ├── hosts/                       # Host-specific configurations
  # │   └── alex-mbp/               # MacBook Pro configuration
  # │       ├── default.nix         # Host module entry point
  # │       └── configuration.nix   # Core host settings
  # └── modules/                     # Shared system modules
  #     ├── system.nix              # Core Nix & security settings
  #     ├── packages.nix            # CLI tools & utilities
  #     ├── development.nix         # Development environments
  #     ├── shell.nix               # Shell configuration
  #     ├── ui.nix                  # macOS interface settings
  #     ├── fonts.nix               # Font management
  #     ├── brew.nix                # Homebrew GUI apps
  #     ├── starship.nix            # Prompt configuration
  #     └── claude-code.nix         # Claude Code integration
  #
  # Benefits of this structure:
  # - Clear separation between host-specific and shared configuration
  # - Easy to add new hosts by copying host directory
  # - Modular approach allows selective feature enabling/disabling
  # - Follows nix-darwin and NixOS conventions
  # - Supports future home-manager integration
  #
  # Common Commands:
  # - Build: nix build .#darwinConfigurations.alex-mbp.system
  # - Switch: darwin-rebuild switch --flake .#alex-mbp
  # - Update: nix flake update
  # - Show diff: nix store diff-closures /var/run/current-system ./result
  #
}