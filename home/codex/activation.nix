# Home Manager activation scripts for ~/.codex
#
# Every body below runs inside a ( … ) || true subshell, for the reason
# documented at home/claude-code/activation.nix:256-260: home-manager
# concatenates ALL activation entries into ONE `set -eu` shell, so a bare
# `exit` — or any non-zero command — terminates the entire activation and
# silently skips every later DAG entry. Both scripts called here already exit
# 0 unconditionally by contract; the subshell is the belt to that braces.
{
  lib,
  configMergePkg,
  verifyTrustPkg,
  sandboxMode,
  approvalPolicy,
  trustKeys,
}:

let
  # Literal "$HOME/…" strings, quoted for the activation shell to expand.
  trustArgs = builtins.concatStringsSep " " (map (k: ''"${k}"'') trustKeys);

  # The USER skills root Codex documents (learn.chatgpt.com/docs/build-skills):
  # "$HOME/.agents/skills". Expanded by the activation shell, not by nix.
  skillsRoot = "$HOME/.agents/skills";

  # Dated once, on purpose. This is a one-time takeover of a tree that was
  # never under repo control, not a rolling backup: a second date would mean
  # the guards below failed.
  skillsFossil = "$HOME/.agents/skills.fossil-2026-09-10";
in
{
  # A leftover hooks.json.backup makes checkLinkTargets abort the whole
  # activation with "would be clobbered by backing up" — same story as
  # claudeCodePreLink. hooks.json goes under nix here for the first time, so
  # home-manager moves the pre-existing hand-written one aside on the first
  # rebuild; purge it before the link check rather than accumulate.
  # NOTE: by name and by name only. Nothing in this file deletes by glob in
  # ~/.codex — the verifier merely *reports* stray siblings.
  codexPreLink = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    (
      rm -f "$HOME/.codex/hooks.json.backup"
    ) || true
  '';

  # THE ONE THIS ENTRY EXISTS FOR, and it is NOT "the rebuild would abort".
  #
  # ~/.agents/skills/ held twelve skill directories dated 17 May, under no
  # file in this repo. Left in place, home-manager does NOT refuse them: with
  # backupFileExtension set (flake.nix), check-link-targets.sh has no branch
  # for a directory — a real directory falls into the `! -L && BACKUP_EXT`
  # arm, which only WARNS, and files.nix then runs a type-agnostic
  #   mv "$targetPath" "$targetPath.backup"
  # So each fossil would land at ~/.agents/skills/<name>.backup — INSIDE the
  # very root Codex scans. Those names do not start with a dot, so the
  # scanner walks them, and a skill is named by the `name:` of its
  # frontmatter, not by its directory (measured: a directory `zzmismatchdir`
  # holding `name: zzmismatchname` is listed as zzmismatchname). Every fossil
  # would therefore reload under its ORIGINAL name, collide with the fresh
  # one, and — Codex does not deduplicate — the stale entry is the one whose
  # description gets quoted. That is strictly worse than doing nothing, and
  # it is the exact failure this whole module exists to remove.
  #
  # Moving the root aside first means nothing is ever in the way, so no
  # .backup is ever created. Hence entryBefore checkLinkTargets: it has to
  # happen before home-manager decides to back anything up.
  #
  # NEVER deletes. `mv` only, by name, never a glob — same rule as
  # codexPreLink above.
  codexSkillsFossilBackup = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    (
      set -euo pipefail

      # Three guards, one failure mode each:
      #   1. the backup already exists  -> second rebuild, nothing to do
      #   2. no skills root at all      -> fresh machine, nothing to move
      #   3. apex is already a symlink  -> the tree is the LIVE one this
      #      module installs. Without this guard, deleting the backup would
      #      make the next rebuild move the live tree under the fossil name.
      #      `apex` is present in both inventories, so the test always decides.
      if [ ! -e "${skillsFossil}" ] && [ -d "${skillsRoot}" ] && [ ! -L "${skillsRoot}/apex" ]; then
        echo "codex skills: taking over ${skillsRoot} (unmanaged since 17 May)."
        echo "  moved to ${skillsFossil} — nothing deleted, restore by moving it back."
        mv "${skillsRoot}" "${skillsFossil}"
      fi
    ) || true
  '';

  codexDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    (
      set -euo pipefail
      mkdir -p "$HOME/.codex"
      mkdir -p "$HOME/.codex/hooks"
    ) || true
  '';

  # config.toml is MERGED, never generated and never linked: Codex stores the
  # per-hook trust table inside that same file, and wiping it un-trusts every
  # hook in silence. The script forces exactly one key, warns on any change,
  # writes its own .backup and restores it if validation fails.
  codexConfigMerge = lib.hm.dag.entryAfter [ "codexDirs" ] ''
    (
      ${configMergePkg}/bin/codex-config-merge "sandbox_mode=${sandboxMode}" "approval_policy=${approvalPolicy}"
    ) || true
  '';

  # After the merge (it reads config.toml's trust table) AND after
  # linkGeneration (it hashes the freshly linked hooks.json). It prints and
  # always exits 0; it can only report that a hook is un-approved or stale,
  # never that one is trusted at runtime. On the first rebuild it is EXPECTED
  # to warn on both hooks — a silent pass there would be the failure.
  # `-a` is never passed from here: recording the reviewed baseline is a human
  # act, done by hand after trusting the hooks in a Codex session.
  # Reports, never repairs — same contract as codexVerifyHookTrust below.
  #
  # Two things can put stale skills back into the scanned root after this
  # module owns it, and both are silent: a hand-made directory colliding with
  # a managed name (home-manager backs it up to <name>.backup, IN the root),
  # or a leftover from an aborted activation. Either way Codex walks it and
  # loads whatever `name:` its frontmatter declares — see the long note on
  # codexSkillsFossilBackup. Nothing here deletes: a warning is what a
  # declarative config may honestly do about a file it does not own.
  codexSkillsStrayCheck = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    (
      set -euo pipefail
      if [ -d "${skillsRoot}" ]; then
        for entry in "${skillsRoot}"/*; do
          [ -e "$entry" ] || continue
          case "$entry" in
            *.backup)
              echo "⚠ codex skills: $entry sits inside the scanned root."
              echo "  Codex walks it and reads its frontmatter name, so a stale"
              echo "  skill is loaded under a live name. Move it out of"
              echo "  ${skillsRoot} to stop that."
              ;;
            *)
              if [ ! -L "$entry" ]; then
                echo "⚠ codex skills: $entry is not managed by this repo."
                echo "  It will be loaded by Codex alongside the generated ones,"
                echo "  and wins the description slot on a name collision."
              fi
              ;;
          esac
        done
      fi
    ) || true
  '';

  codexVerifyHookTrust =
    lib.hm.dag.entryAfter
      [
        "codexConfigMerge"
        "linkGeneration"
      ]
      ''
        (
          ${verifyTrustPkg}/bin/codex-verify-hook-trust ${trustArgs}
        ) || true
      '';
}
