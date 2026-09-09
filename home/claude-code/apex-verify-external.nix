# apex-verify-external — the APEX `-e` pass, packaged as a real binary on PATH.
#
# Runs the Codex CLI as a second, cross-vendor, READ-ONLY verifier over the same
# bounded brief the Fable diff pass gets, and returns a bounded JSON verdict.
# It adds to that pass, never replaces it.
#
# A CLI rather than an MCP server, for the same reason as libdocs: a subprocess
# invoked only when `-e` is typed costs nothing the rest of the time, and the
# allowlist can grant `Bash(apex-verify-external *)` instead of a broader rule.
#
# writeShellApplication prepends `set -euo pipefail` and runs shellcheck at
# build time, so a regression in the script fails the rebuild. runtimeInputs is
# PREPENDED to $PATH rather than replacing it, which is why the brew-installed
# `codex` in /opt/homebrew/bin stays reachable from inside the wrapper.
{ pkgs }:
{
  apexVerifyExternalPkg = pkgs.writeShellApplication {
    name = "apex-verify-external";
    # grep and sed do the failure classification and the secret scrubbing, so
    # they are pinned for the same reason coreutils is: a BSD/GNU difference in
    # `grep -E` or `sed -E` would change a verdict, not just a message.
    runtimeInputs = [
      pkgs.git
      pkgs.jq
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = builtins.readFile ./scripts/apex-verify-external.sh;
  };
}
