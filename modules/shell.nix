{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

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

}
