{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ============================================================================
  # SHARED CONFIGURATION
  # ============================================================================
  # Centralized environment variables and aliases to avoid duplication
  # Used by: shell.nix, development.nix, brew.nix, home/default.nix
  # Options are defined in modules/options.nix

  # ============================================================================
  # ENVIRONMENT VARIABLES
  # ============================================================================

  environment.variables = {
    # === FZF Configuration ===
    FZF_CTRL_R_OPTS = "--no-preview"; # History search: no preview
    FZF_CTRL_T_OPTS = "--preview 'bat -n --color=always --line-range :500 {}'"; # File search: bat preview
    FZF_ALT_C_OPTS = "--preview 'eza --tree --color=always {} | head -200'"; # Directory search: tree preview
    FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git"; # Use fd for file search
    FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border --ansi"; # Default FZF appearance

    # === Tool Appearance & Behavior ===
    BAT_THEME = "TwoDark"; # Dark theme for bat syntax highlighting
    LESS = "-R --use-color"; # Enable colors in less pager
    DOCKER_DEFAULT_PLATFORM = "linux/amd64"; # Default Docker platform

    # === Tool Configuration Directories ===
    EZA_CONFIG_DIR = "$HOME/.config/eza"; # Eza configuration location
    PNPM_HOME = "$HOME/Library/pnpm"; # PNPM installation directory

    # === Homebrew Core Settings ===
    HOMEBREW_NO_ANALYTICS = "1"; # Disable usage analytics
    HOMEBREW_NO_INSECURE_REDIRECT = "1"; # Prevent insecure redirects
    HOMEBREW_PREFIX = "/opt/homebrew"; # Homebrew installation prefix
  };

  # ============================================================================
  # SHELL ALIASES
  # ============================================================================

  environment.shellAliases = {
    # === Git Workflow Shortcuts ===
    g = "git"; # Quick git access
    gs = "git status"; # Check repository status
    ga = "git add"; # Stage changes
    gc = "git commit"; # Commit changes
    gp = "git push"; # Push to remote
    gl = "git pull"; # Pull from remote
    gd = "git diff"; # Show differences
    gco = "git checkout"; # Switch branches/restore files
    gb = "git branch"; # List/manage branches

    # === Enhanced CLI Tools ===
    lt = "eza --tree"; # Tree view with modern formatting
    cat = "bat"; # Cat with syntax highlighting
    find = "fd"; # Faster and more intuitive find
    grep = "rg"; # Faster grep with better defaults
  };
}
