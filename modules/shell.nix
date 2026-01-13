{ config, pkgs, lib, inputs, ... }:

{
  # Shell environment configuration

  # ============================================================================
  # ZSH CONFIGURATION
  # ============================================================================

  programs.zsh = {
    enable = true;
  };

  # ============================================================================
  # SHELL ENVIRONMENT VARIABLES
  # ============================================================================

  # Set Zsh as the default system shell
  environment.shells = [ pkgs.zsh ];

  # Tool-specific environment variables
  environment.variables = {
    # ---- FZF Configuration ----
    FZF_CTRL_R_OPTS = "--no-preview";                                           # History search: no preview
    FZF_CTRL_T_OPTS = "--preview 'bat -n --color=always --line-range :500 {}'"; # File search: bat preview
    FZF_ALT_C_OPTS = "--preview 'eza --tree --color=always {} | head -200'";     # Directory search: tree preview
    FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git";       # Use fd for file search
    FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border --ansi";         # Default FZF appearance

    # ---- Tool Appearance & Behavior ----
    BAT_THEME = "TwoDark";                         # Dark theme for bat syntax highlighting
    LESS = "-R --use-color";                       # Enable colors in less pager
    DOCKER_DEFAULT_PLATFORM = "linux/amd64";      # Default Docker platform

    # ---- Tool Configuration Directories ----
    EZA_CONFIG_DIR = "$HOME/.config/eza";         # Eza configuration location
    PNPM_HOME = "$HOME/Library/pnpm";             # PNPM installation directory
    FNM_DIR = "$HOME/.fnm";                       # Fast Node Manager directory
  };

  # Note: EDITOR, VISUAL, PAGER are configured in system.nix to avoid duplication
}