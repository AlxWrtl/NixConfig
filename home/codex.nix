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

  # The Obsidian vault, granted as a second workspace root so Codex can write
  # its own session note instead of handing it to a human — the asymmetry that
  # left three commits (8f5e724, 0d70c93, fe9b527) with no note at all.
  #
  # A ROOT, not a `filesystem` entry, and that is the whole design: the rules
  # under `:workspace_roots` apply to EVERY effective root, so the vault
  # inherits the `.git/hooks` = read line already written below instead of
  # needing a second, unproven precedence rule beside it. One list, one place.
  # The vault is itself a git repository (vault-snapshot auto-commits it), so
  # the distinction is not academic: a hook planted in ITS `.git/hooks` would
  # run outside this sandbox at the next auto-commit.
  #
  # Measured before the line was written, two arms on the same targets, a
  # control arm each time, a throwaway vault under $HOME because $TMPDIR is
  # writable by default and would have made the positive arm vacuous:
  #
  #                                    without grant   with grant
  #   workspace control                ÉCRIT           ÉCRIT
  #   vault/note.md                    refused         ÉCRIT     <- what it buys
  #   vault/.git/probe                 refused         ÉCRIT     <- the trade
  #   vault/.git/hooks/pre-commit      refused         refused   <- holds
  #   anywhere else under $HOME        refused         refused   <- unchanged
  #
  # The trade named plainly: `.git` = write reaches the vault's git objects
  # too, because the rule is per-root-set and not per-root. `.git/hooks` — the
  # half that EXECUTES — stays out of reach, which is the half that matters.
  alxVaultPath = "/Users/alx/Vaults/AlxVault";

  permissionsProfile = "git-workspace";
  # One TOML section, inline tables only. A `[permissions.git-workspace.*]`
  # sub-table would be a SECOND section header, and codex-config-merge replaces
  # exactly one section by name — the sub-table would survive the strip and
  # accumulate. Keeping it inline keeps the managed block singular.
  permissionsBlock = ''
    [permissions.git-workspace]
    extends = ":workspace"
    workspace_roots = { "${alxVaultPath}" = true }
    filesystem = { ":workspace_roots" = { ".git" = "write", ".git/hooks" = "read" } }
  '';

  # No human confirmation before an action. What is left between the model and
  # the filesystem is the permissions profile above and two branch hooks —
  # nothing else. A deliberate trade for a working loop, made 2026-09-10 after
  # the guard was measured refusing a write on master: the refusal did not
  # depend on the confirmation, so removing the confirmation does not remove
  # the guard. Textual inspection of a shell command has limits the hook's own
  # header states; this makes them the only limits that remain.
  approvalPolicy = "never";

  hooks = import ./codex/hooks.nix { inherit pkgs; };

  # Reads home/claude-code/skills-manifest.nix — the SAME list the Claude side
  # installs from — and writes a translated copy to ~/.agents/skills. One
  # source of text, two outputs. The previous copy of this tree was kept by
  # hand and drifted for four months in silence: its apex still advertised
  # flags removed in May, and its obsidian skill still pointed at a vault path
  # that had moved.
  skills = import ./codex/skills.nix { inherit pkgs lib; };

  inherit (import ./codex/agents-md.nix) agentsMd;

  # Defined in a plain `{ pkgs }:` file so checks/codex-config.nix can import
  # the very same derivations and run them with an empty PATH — see the
  # measurement recorded there. A home-manager module cannot be imported by a
  # check, and that is why these two wrappers went untested until the PATH bug
  # shipped.
  inherit (import ./codex/packages.nix { inherit pkgs; }) configMergePkg verifyTrustPkg;

  activationScripts = import ./codex/activation.nix {
    inherit
      lib
      configMergePkg
      verifyTrustPkg
      permissionsProfile
      permissionsBlock
      approvalPolicy
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
  home.file =
    hookScriptFiles
    // skills.files
    // {
      "${codexDir}/hooks.json".text = hooks.hooksJson + "\n";

      # force: this file already exists as a real, hand-edited file. Without it
      # home-manager refuses to link and leaves an AGENTS.md.backup behind, and
      # the stale instructions keep being loaded.
      "${codexDir}/AGENTS.md" = {
        text = agentsMd;
        force = true;
      };
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
