# Codex CLI — ~/.codex under repo control.
#
# What is declarative here: hooks.json and the two hook scripts, as store
# symlinks. What is NOT: config.toml, which is merged in place by an
# activation script because Codex writes its own per-hook trust table into it
# (and rewrites `model` itself when the user runs /model). There is
# deliberately NO home.file entry for it — the merge renames a temp file over
# the target, which would turn a home-manager symlink into a regular file.
{
  pkgs,
  lib,
  ...
}:

let
  codexDir = ".codex";

  # The one key this repo forces (D3). It decides what the agent may break; a
  # silent drift to full access is precisely what a declarative configuration
  # exists to prevent. `model` and `model_reasoning_effort` stay session
  # choices, exactly as the Claude side refuses to force `.model`.
  sandboxMode = "workspace-write";

  hooks = import ./codex/hooks.nix { inherit pkgs; };

  # writeShellApplication prepends `set -euo pipefail` and runs shellcheck at
  # build time — both scripts are written for it and add neither themselves.
  # yq supplies tomlq; coreutils supplies cmp/mktemp/cp/mv/sha256sum.
  configMergePkg = pkgs.writeShellApplication {
    name = "codex-config-merge";
    runtimeInputs = [
      pkgs.yq
      pkgs.coreutils
    ];
    text = builtins.readFile ./codex/scripts/config-merge.sh;
  };

  verifyTrustPkg = pkgs.writeShellApplication {
    name = "codex-verify-hook-trust";
    runtimeInputs = [
      pkgs.yq
      pkgs.coreutils
    ];
    text = builtins.readFile ./codex/scripts/verify-hook-trust.sh;
  };

  activationScripts = import ./codex/activation.nix {
    inherit
      lib
      configMergePkg
      verifyTrustPkg
      sandboxMode
      ;
    # Same expression that generates the JSON emits these keys, so they cannot
    # drift from the file they describe. "$HOME" is expanded by the activation
    # shell, not by nix.
    trustKeys = hooks.trustKeysFor "$HOME/${codexDir}/hooks.json";
  };

  # Store symlinks, from the same list that built the command strings.
  hookScriptFiles = builtins.listToAttrs (
    map (f: {
      name = f.target;
      value = {
        inherit (f) source;
        executable = true;
      };
    }) hooks.scriptFiles
  );
in
{
  home.file = hookScriptFiles // {
    "${codexDir}/hooks.json".text = hooks.hooksJson + "\n";
  };

  # On PATH so the human can record the reviewed baseline by hand after
  # trusting the hooks in a Codex session: `codex-verify-hook-trust -a`.
  home.packages = [
    configMergePkg
    verifyTrustPkg
  ];

  home.activation = activationScripts // {
    # The commands in hooks.json hard-code the absolute system node. If node
    # ever leaves the system profile, every Codex turn prints `hook exited
    # with code 127` and branch protection is OFF while still looking
    # configured — that is the exact live failure this module repairs, so it
    # gets a loud guard rather than a silent one.
    codexNodeCheck = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      (
        if [ ! -x "${hooks.nodeBin}" ]; then
          echo "⚠ codex hooks: ${hooks.nodeBin} is missing or not executable."
          echo "  Every Codex hook will fail with 'hook exited with code 127',"
          echo "  so branch protection is OFF while hooks.json still declares it."
          echo "  FIX: keep pkgs.nodejs_22 in modules/packages.nix, then rebuild."
        fi
      ) || true
    '';
  };
}
