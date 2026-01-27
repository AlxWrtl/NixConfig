{
  config,
  pkgs,
  lib,
  ...
}:

{
  # direnv: per-directory environment loader
  # Automatically loads/unloads .envrc files when entering/leaving directories

  # ============================================================================
  # DIRENV CONFIGURATION
  # ============================================================================

  # === Enable direnv with shell integration ===
  programs.direnv = {
    enable = true; # Install direnv and enable automatic shell integration

    # Silent mode: suppress "direnv: loading" messages for cleaner shell output
    silent = false;

    # Nix integration: automatically evaluate and cache .envrc files containing Nix expressions
    nix-direnv.enable = true;
  };

  # ============================================================================
  # ENVIRONMENT VARIABLES
  # ============================================================================

  environment.variables = {
    # Configure direnv logging behavior
    DIRENV_LOG_FORMAT = ""; # Empty = minimal output, set to "direnv: %s" for verbose
  };
}
