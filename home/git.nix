{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ============================================================================
  # GIT CONFIGURATION
  # ============================================================================

  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Alexandre";
        email = "indexes-benzine0p@icloud.com";
      };

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
}
