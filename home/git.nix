{
  config,
  pkgs,
  lib,
  ...
}:

let
  secrets = import ../secrets.nix;
in

{
  programs.git = {
    enable = true;

    signing.format = "ssh";

    ignores = [
      "**/.claude/settings.local.json"
    ];

    settings = {
      user = {
        name = "Alexandre";
        email = secrets.git.email;
        signingKey = secrets.git.signingKey;
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
      core.untrackedcache = true;

      commit.gpgSign = true;
    };
  };
}
