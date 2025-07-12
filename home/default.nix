{ config, pkgs, lib, ... }:

{
  # ============================================================================
  # HOME MANAGER USER CONFIGURATION
  # ============================================================================
  # Modern user-level configuration managed by home-manager
  # This separates user settings from system settings for better modularity

  # === Basic Configuration ===
  home.username = "alx";
  home.homeDirectory = "/Users/alx";
  home.stateVersion = "24.11";

  # === Allow Home Manager to manage itself ===
  programs.home-manager.enable = true;

  # ============================================================================
  # USER SHELL CONFIGURATION
  # ============================================================================

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    # Enhanced history configuration
    history = {
      size = 50000;
      save = 50000;
      share = true;
      ignoreDups = true;
      ignoreSpace = true;
    };

    # User-specific aliases (supplement system aliases)
    shellAliases = {
      # === Security tools ===
      vulnscan = "vulnix --system /var/run/current-system";
      secrets = "sops";
      encrypt = "age";
      
      # === Home Manager shortcuts ===
      hm = "home-manager";
      hms = "home-manager switch";
      hmb = "home-manager build";
    };

    # User-specific environment variables
    sessionVariables = {
      # Development environment
      HOMEBREW_NO_ANALYTICS = "1";
      HOMEBREW_NO_INSECURE_REDIRECT = "1";
      
      # Security
      GNUPGHOME = "$XDG_CONFIG_HOME/gnupg";
      AGE_DIR = "$XDG_CONFIG_HOME/age";
    };
  };

  # ============================================================================
  # USER GIT CONFIGURATION
  # ============================================================================

  programs.git = {
    enable = true;
    userName = "Alexandre";
    userEmail = "indexes-benzine0p@icloud.com";
    
    extraConfig = {
      init.defaultBranch = "main";
      push.default = "simple";
      pull.rebase = true;
      rerere.enabled = true;
      
      # Security settings
      transfer.fsckObjects = true;
      fetch.fsckObjects = true;
      receive.fsckObjects = true;
      
      # Modern Git features
      feature.manyFiles = true;
      index.version = 4;
    };
  };

  # ============================================================================
  # USER DEVELOPMENT ENVIRONMENT
  # ============================================================================

  # User-specific packages (development tools, utilities)
  home.packages = with pkgs; [
    # Development utilities that should be user-scoped
    gh-dash                # GitHub dashboard
    gitleaks               # Git secrets scanner
    pre-commit             # Git pre-commit hooks
    
    # Personal productivity tools
    tree                   # Directory tree viewer
    watch                  # Execute programs periodically
    tldr                   # Simplified man pages
  ];

  # ============================================================================
  # USER SERVICES & AUTOMATION
  # ============================================================================

  # Personal security scanning service
  launchd.agents.personal-security-scan = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.vulnix}/bin/vulnix"
        "--system"
        "/var/run/current-system"
        "--json"
        "/Users/alx/.cache/vulnix-scan.json"
      ];
      StartCalendarInterval = [
        { Weekday = 1; Hour = 10; Minute = 0; }  # Monday 10 AM
      ];
      StandardOutPath = "/Users/alx/.cache/vulnix-scan.log";
      StandardErrorPath = "/Users/alx/.cache/vulnix-scan-error.log";
    };
  };

  # ============================================================================
  # XDG DIRECTORIES
  # ============================================================================

  xdg = {
    enable = true;
    # Note: userDirs is Linux-only, macOS uses standard directories
  };

  # ============================================================================
  # USER FONTS
  # ============================================================================
  
  fonts.fontconfig.enable = true;

}