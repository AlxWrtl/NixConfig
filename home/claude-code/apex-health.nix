# apex-health — before/after health report of APEX runs, packaged as a real
# binary on PATH.
#
# Compares APEX runs BEFORE vs AFTER a cut-off date (default 2026-10-10, #235)
# on correction rounds, grants, escalations and fix-after commits, and prints
# token cost for information. Read-only: transcripts, correction-budget files,
# 00-context.md and git log only; zero network, zero model call.
#
# writePython3Bin runs flake8 at build time (only E501 ignored), so a
# regression in the script fails the rebuild. Stdlib only; git comes from PATH.
{ pkgs }:
{
  apexHealthPkg = pkgs.writers.writePython3Bin "apex-health" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/apex-health.py);
}
