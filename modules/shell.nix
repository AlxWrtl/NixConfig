{
  config,
  pkgs,
  lib,
  ...
}:

{
  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  environment.variables = {
    # FZF Configuration
    FZF_CTRL_R_OPTS = "--no-preview";
    FZF_CTRL_T_OPTS = "--preview 'bat -n --color=always --line-range :500 {}'";
    FZF_ALT_C_OPTS = "--preview 'eza --tree --color=always {} | head -200'";
    FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git";
    FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border --ansi";

    # Tool Appearance
    BAT_THEME = "TwoDark";
    LESS = "-R --use-color";
    DOCKER_DEFAULT_PLATFORM = "linux/amd64";

    # Tool Directories
    EZA_CONFIG_DIR = "$HOME/.config/eza";
    PNPM_HOME = "$HOME/Library/pnpm";

    # Homebrew
    HOMEBREW_NO_ANALYTICS = "1";
    HOMEBREW_NO_INSECURE_REDIRECT = "1";
    HOMEBREW_PREFIX = "/opt/homebrew";
  };

  environment.shellAliases = {
    lt = "eza --tree";
    cat = "bat";
    find = "fd";
    grep = "rg";
  };
}
