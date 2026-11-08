# ttw-health — before/after health report of APEX runs, packaged as a real
# binary on PATH.
#
# Compares APEX runs BEFORE vs AFTER a cut-off date (default 2026-10-10, #235)
# on correction rounds, grants, escalations and fix-after commits, and prints
# token cost for information. Read-only: transcripts, correction-budget files,
# 00-context.md and git log only; zero network, zero model call.
#
# writePython3Bin runs flake8 at build time (only E501 ignored), so a
# regression in the script fails the rebuild. Stdlib only; git comes from PATH.
#
# apex -> ttw, phase 2: bin/apex-health is a symlink to ttw-health in the same
# output (argparse prog is fixed, so both names print the same text). Dropped
# in phase 4.
{ pkgs }:
let
  ttwHealth = pkgs.writers.writePython3Bin "ttw-health" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/ttw-health.py);
in
{
  ttwHealthPkg = pkgs.symlinkJoin {
    name = "ttw-health";
    paths = [ ttwHealth ];
    postBuild = "ln -s ttw-health $out/bin/apex-health";
  };
}
