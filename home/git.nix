{
  config,
  pkgs,
  lib,
  ...
}:

{
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

      transfer.fsckObjects = true;
      fetch.fsckObjects = true;
      receive.fsckObjects = true;

      feature.manyFiles = true;
      index.version = 4;
    };
  };
}
