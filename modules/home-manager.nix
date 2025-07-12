{ config, pkgs, lib, inputs, ... }:

{
  # ============================================================================
  # HOME MANAGER INTEGRATION
  # ============================================================================
  # User-level configuration management using Home Manager
  # Manages dotfiles, user services, and personal application configurations

  # ============================================================================
  # HOME MANAGER MODULE IMPORT
  # ============================================================================

  imports = [ inputs.home-manager.darwinModules.home-manager ];

  # ============================================================================
  # HOME MANAGER CONFIGURATION
  # ============================================================================

  home-manager = {
    # === Global Settings ===
    useGlobalPkgs = true;                                 # Use system nixpkgs for consistency
    useUserPackages = true;                               # Install user packages to /etc/profiles
    backupFileExtension = "backup";                       # Backup existing files before managing them

    # ============================================================================
    # USER CONFIGURATION: ALX
    # ============================================================================

    users.alx = { pkgs, ... }: {
      # === Home Manager State Version ===
      home.stateVersion = "24.05";                        # Home Manager version (don't change after initial setup)

      # ============================================================================
      # USER PACKAGES
      # ============================================================================
      # User-specific packages that don't need system-wide installation

      home.packages = with pkgs; [
        # === Personal Productivity Tools ===
        # Add user-level tools here as needed
        # Example: personal scripts, user-specific utilities

        # === Development Utilities ===
        # User-level development tools
        # Example: language-specific formatters, personal dev scripts
      ];

      # ============================================================================
      # USER SERVICES
      # ============================================================================
      # Background services that run for the user

      services = {
        # === Example User Services ===
        # Uncomment and configure as needed:
        
        # gpg-agent = {
        #   enable = true;
        #   enableSshSupport = true;
        # };

        # syncthing.enable = true;
      };

      # ============================================================================
      # USER ENVIRONMENT VARIABLES
      # ============================================================================
      # User-specific environment variables (complement system-wide ones)

      home.sessionVariables = {
        # === Personal Environment Variables ===
        # Add user-specific variables here
        # Example: PERSONAL_WORKSPACE = "$HOME/workspace";
      };

      # ============================================================================
      # PROGRAM CONFIGURATIONS
      # ============================================================================
      # Declarative configuration for user applications

      programs = {
        # === Git Configuration ===
        git = {
          enable = true;
          userName = "Alexandre";                         # Set your actual name
          userEmail = "your-email@example.com";          # Set your actual email
          
          extraConfig = {
            # === Git Behavior ===
            init.defaultBranch = "main";                  # Use 'main' as default branch
            push.autoSetupRemote = true;                  # Auto-setup remote tracking
            pull.rebase = true;                           # Rebase instead of merge on pull
            
            # === Git Security ===
            # url."https://github.com/".insteadOf = "git@github.com:"; # Force HTTPS
          };
        };

        # === Shell Configuration ===
        # Note: Main shell config is in modules/shell.nix
        # This section is for user-specific shell customizations
        
        # === Additional Program Configurations ===
        # Add more program configurations as needed:
        # - VS Code settings
        # - Terminal configurations
        # - Application-specific settings
      };

      # ============================================================================
      # DOTFILE MANAGEMENT
      # ============================================================================
      # Declarative management of configuration files

      # home.file = {
      #   # === Example Dotfile Management ===
      #   ".config/app/config.toml".text = ''
      #     # Application configuration
      #     setting = "value"
      #   '';
      # };

      # ============================================================================
      # XDG CONFIGURATION
      # ============================================================================
      # XDG Base Directory Specification setup

      xdg = {
        enable = true;                                    # Enable XDG directory management
        
        # === XDG User Directories ===
        userDirs = {
          enable = true;                                  # Manage user directories
          createDirectories = true;                       # Automatically create directories
          
          # === Directory Configuration ===
          desktop = "$HOME/Desktop";
          documents = "$HOME/Documents";
          download = "$HOME/Downloads";
          music = "$HOME/Music";
          pictures = "$HOME/Pictures";
          videos = "$HOME/Videos";
          
          # === Development Directories ===
          # publicShare = "$HOME/Public";
          # templates = "$HOME/Templates";
        };
      };
    };
  };

  # ============================================================================
  # HOME MANAGER NOTES
  # ============================================================================
  #
  # This module provides the foundation for user-level configuration management.
  # 
  # Key Benefits:
  # - Declarative dotfile management
  # - User-specific service management
  # - Application configuration as code
  # - Consistent user environment across machines
  # - Backup and restoration of existing configurations
  #
  # Usage Examples:
  # 1. Add user packages to home.packages
  # 2. Configure applications in programs.*
  # 3. Manage dotfiles with home.file
  # 4. Set up user services in services.*
  # 5. Define personal environment variables
  #
  # Integration with nix-darwin:
  # - System-wide packages: modules/packages.nix, modules/development.nix
  # - User-specific packages: this file (home.packages)
  # - System settings: modules/ui.nix, modules/system.nix
  # - User configurations: this file (programs, services, home.file)
  #
}