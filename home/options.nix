{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ============================================================================
  # HOME MANAGER OPTIONAL FEATURES
  # ============================================================================
  # Enable/disable optional features for home-manager configuration

  options.home-features = with lib; {
    # === Development Tools ===
    devTools = mkOption {
      type = types.bool;
      default = true;
      description = "Enable development utilities (gh-dash, gitleaks, pre-commit)";
    };

    # === Productivity Tools ===
    productivity = mkOption {
      type = types.bool;
      default = true;
      description = "Enable productivity tools (tree, watch, tldr)";
    };

    # === Claude Code Integration ===
    claudeCode = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Claude Code integration and configuration";
    };
  };

  config = {
    # User packages conditionally included
    home.packages =
      with pkgs;
      lib.lists.optionals config.home-features.devTools [
        gh-dash
        gitleaks
        pre-commit
      ]
      ++ lib.lists.optionals config.home-features.productivity [
        tree
        watch
        tldr
      ];
  };
}
