{
  # ============================================================================
  # NIX-DARWIN SYSTEM FLAKE
  # ============================================================================

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
          ./modules/security.nix                            # Security hardening & vulnerability scanning

          # === HOME MANAGER INTEGRATION ===
          home-manager.darwinModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.users.alx = import ./home;
            home-manager.extraSpecialArgs = { inherit inputs; };
          }
        ];
      };
    };

    # ============================================================================
    # ADDITIONAL FLAKE OUTPUTS
    # ============================================================================

    # === Development Shells ===
    devShells.aarch64-darwin.default = nixpkgs.legacyPackages.aarch64-darwin.mkShell {
      buildInputs = with nixpkgs.legacyPackages.aarch64-darwin; [
        vulnix                    # Security scanning
        nix-tree                  # Dependency visualization
        nixfmt-rfc-style         # Code formatting
        nil                       # Language server
      ];
      
      shellHook = ''
        echo "🔧 nix-darwin development environment"
        echo "Available commands:"
        echo "  vulnix --system /var/run/current-system  # Security scan"
        echo "  nix-tree                                 # Visualize dependencies"
        echo "  nixfmt **/*.nix                          # Format Nix files"
      '';
    };

    # === Configuration Validation Checks ===
    checks.aarch64-darwin = {
      # Format check
      format-check = nixpkgs.legacyPackages.aarch64-darwin.runCommand "format-check" {
        buildInputs = [ nixpkgs.legacyPackages.aarch64-darwin.nixfmt-rfc-style ];
      } ''
        echo "Checking Nix file formatting..."
        cd ${./.}
        find . -name "*.nix" -exec nixfmt --check {} \;
        touch $out
      '';
      
      # Build system configuration
      build-config = self.darwinConfigurations."alex-mbp".system;
    };

    # === Templates ===
    # Note: Templates removed to avoid broken references
    # To add templates: create templates/basic/ directory with flake.nix
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