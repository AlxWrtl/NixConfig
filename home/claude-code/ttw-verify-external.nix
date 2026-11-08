# ttw-verify-external — the TTW `-e` pass, packaged as a real binary on PATH.
#
# Runs the Codex CLI as a second, cross-vendor, READ-ONLY verifier over the same
# bounded brief the Fable diff pass gets, and returns a bounded JSON verdict.
# It adds to that pass, never replaces it.
#
# A CLI rather than an MCP server, for the same reason as libdocs: a subprocess
# invoked only when `-e` is on (typed, or the High-stakes default) costs nothing
# the rest of the time, and the
# allowlist can grant `Bash(ttw-verify-external *)` instead of a broader rule.
#
# writeShellApplication prepends `set -euo pipefail` and runs shellcheck at
# build time, so a regression in the script fails the rebuild. runtimeInputs is
# PREPENDED to $PATH rather than replacing it, which is why the brew-installed
# `codex` in /opt/homebrew/bin stays reachable from inside the wrapper.
#
# apex -> ttw, phase 2: bin/apex-verify-external is a symlink to
# ttw-verify-external in the same output; the script never reads $0, so both
# names print the same text. Dropped in phase 4.
{ pkgs }:
let
  ttwVerifyExternal = pkgs.writeShellApplication {
    name = "ttw-verify-external";
    # grep and sed do the failure classification and the secret scrubbing, so
    # they are pinned for the same reason coreutils is: a BSD/GNU difference in
    # `grep -E` or `sed -E` would change a verdict, not just a message.
    runtimeInputs = [
      pkgs.git
      pkgs.jq
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = builtins.readFile ./scripts/ttw-verify-external.sh;
  };
in
{
  ttwVerifyExternalPkg = pkgs.symlinkJoin {
    name = "ttw-verify-external";
    paths = [ ttwVerifyExternal ];
    postBuild = "ln -s ttw-verify-external $out/bin/apex-verify-external";
  };
}
