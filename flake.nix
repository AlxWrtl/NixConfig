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
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable"; # Primary package repository

    # === nix-darwin Framework ===
    nix-darwin = {
      url = "github:LnL7/nix-darwin"; # macOS system configuration framework
      inputs.nixpkgs.follows = "nixpkgs"; # Use our nixpkgs version
    };

    # === Home Manager (Future Integration) ===
    home-manager = {
      url = "github:nix-community/home-manager/master"; # User environment management
      inputs.nixpkgs.follows = "nixpkgs"; # Use our nixpkgs version
    };
  };

  # ============================================================================
  # FLAKE OUTPUTS & SYSTEM CONFIGURATIONS
  # ============================================================================

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
      # ============================================================================
      # AUTOMATED TESTS & CHECKS
      # ============================================================================

      checks.${system} = {
        # Format check: Ensure all Nix files follow nixfmt-rfc-style
        format-check = pkgs.runCommand "check-nix-format" { } ''
          set -e
          echo "Checking Nix file formatting..."
          ${pkgs.nixfmt-rfc-style}/bin/nixfmt --check ${./.}/flake.nix || {
            echo "ERROR: Nix files not formatted. Run: nixfmt **/*.nix"
            exit 1
          }
          touch $out
        '';

        # System configuration reference (implicitly validates evaluation)
        system-config = self.darwinConfigurations."alex-mbp".system;
      };

      # === DARWIN SYSTEM CONFIGURATIONS ===
      # Build and switch to configuration using:
      # $ darwin-rebuild switch --flake .#alex-mbp

      darwinConfigurations = {
        # === Alexandre's MacBook Pro Configuration ===
        "alex-mbp" = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin"; # Apple Silicon architecture
          specialArgs = { inherit inputs; }; # Pass inputs to all modules

          modules =
            let
              # Core system configuration
              coreModules = [
                ./hosts/alex-mbp # Host module (networking, users, platform)
                ./modules/options.nix # Module option definitions
                ./modules/nix.nix # Nix package manager configuration
                ./modules/environment.nix # Environment variables & user management
              ];

              # Shell and CLI environment
              shellModules = [
                ./modules/shell.nix # Zsh + Starship + Direnv + Aliases (consolidated)
                ./modules/packages.nix # System utilities & CLI tools
              ];

              # System integration
              systemModules = [
                ./modules/fonts.nix # Programming fonts & typography
                ./modules/ui.nix # macOS UI/UX & system defaults
              ];

              # Automation services
              serviceModules = [
                ./modules/launchd/flake-update.nix # Automatic flake updates
                ./modules/launchd/homebrew-update.nix # Automatic Homebrew updates
                ./modules/launchd/system-optimization.nix # Power & network optimization
              ];

              # Development and security
              devSecModules = [
                ./modules/brew.nix # Homebrew for GUI applications
                ./modules/security.nix # Security hardening & vulnerability scanning
                ./modules/secrets.nix # SOPS secrets management with age encryption
              ];

              # Home Manager integration
              homeModules = [
                home-manager.darwinModules.home-manager
                {
                  home-manager.useGlobalPkgs = true;
                  home-manager.useUserPackages = true;
                  home-manager.backupFileExtension = "backup";
                  home-manager.users.alx = import ./home;
                  home-manager.extraSpecialArgs = { inherit inputs; };
                }
              ];
            in
            coreModules ++ shellModules ++ systemModules ++ serviceModules ++ devSecModules ++ homeModules;
        };
      };

      # ============================================================================
      # ADDITIONAL FLAKE OUTPUTS
      # ============================================================================

      # === Development Shells ===
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          vulnix # Security scanning
          nix-tree # Dependency visualization
          nixfmt-rfc-style # Code formatting
          nil # Language server
        ];

        shellHook = ''
          echo "nix-darwin development environment"
          echo "Available commands:"
          echo "  vulnix --system /var/run/current-system  # Security scan"
          echo "  nix-tree                                 # Visualize dependencies"
          echo "  nixfmt **/*.nix                          # Format Nix files"
        '';
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
