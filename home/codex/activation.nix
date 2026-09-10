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
