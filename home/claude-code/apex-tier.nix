# apex-tier — the APEX tier classifier, packaged as a real binary on PATH.
#
# Decides direct / standard / high from the DIFF (size, paths, and the
# indentation ancestry of each changed line), replacing the old brief-text
# regexes of apex-flags.js. Read-only: git diff/show/ls-files only.
#
# writeShellApplication prepends `set -euo pipefail` and runs shellcheck at
# build time, so a regression in the script fails the rebuild. gawk and gnugrep
# are pinned: a BSD/GNU difference in `match()`/RLENGTH or `\b` would change a
# tier, not just a message.
{ pkgs }:
{
  apexTierPkg = pkgs.writeShellApplication {
    name = "apex-tier";
    runtimeInputs = [
      pkgs.git
      pkgs.gawk
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = builtins.readFile ./scripts/apex-tier.sh;
  };
}
