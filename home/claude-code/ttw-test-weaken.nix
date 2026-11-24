# ttw-test-weaken — the TTW weakened-test scan, packaged as a real binary on
# PATH (step-04 validate and Direct run it on the branch diff).
#
# Flags removed assertions, added skips/focus and lowered coverage or
# max-warnings thresholds between merge-base(--base, HEAD) and the working
# tree, untracked files included. Advisory: its findings are triaged, never a
# gate on their own (agent-roast is a static heuristic of this kind and its
# author reports 25-66 % false positives on unknown repos). Offline and read-only: git only, pinned here
# through `@GIT@`. writePython3Bin runs flake8 at build time; the behaviour is
# pinned by checks/ttw-test-weaken.nix.
{ pkgs }:
{
  ttwTestWeakenPkg =
    pkgs.writers.writePython3Bin "ttw-test-weaken"
      {
        flakeIgnore = [ "E501" ];
      }
      (
        builtins.replaceStrings [ "@GIT@" ] [ "${pkgs.git}/bin/git" ] (
          builtins.readFile ./scripts/ttw-test-weaken.py
        )
      );
}
