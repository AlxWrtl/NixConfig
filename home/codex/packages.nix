# The two shell wrappers ~/.codex needs, in a plain `{ pkgs }:` file.
#
# WHY THEY LIVE HERE AND NOT IN home/codex.nix. That file is a home-manager
# module — it takes config/lib/pkgs and only the module system can call it, so
# a check could not import it and therefore could not RUN these wrappers.
# Nothing tested them, which is precisely how the PATH bug below reached a
# rebuild. checks/codex-config.nix now imports THIS file and executes both
# wrappers with the ambient PATH emptied.
{ pkgs }:

let
  # writeShellApplication prepends `set -euo pipefail` and runs shellcheck at
  # build time — both scripts are written for it and add neither themselves.
  #
  # EVERY external command a script calls must be listed here. runtimeInputs is
  # what the wrapper PREPENDS to PATH, and home-manager activation runs with a
  # restricted PATH, so anything missing is simply not found there while it
  # still works when you run the script by hand. Measured 2026-09-10, first
  # rebuild: `awk` and `grep` were absent, the hash pipeline failed, and the
  # verifier reported "no sha256 tool found" — with sha256sum present. The
  # staleness detector, the one the design calls not optional, was dead in the
  # only environment that matters, and it took a live run to see it.
  #
  # yq supplies tomlq; coreutils supplies mktemp/cp/mv/mkdir/sha256sum;
  # diffutils supplies cmp, which coreutils does NOT; gawk and gnugrep supply
  # the two the first version forgot.
  codexRuntimeInputs = [
    pkgs.yq
    pkgs.coreutils
    pkgs.diffutils
    pkgs.gawk
    pkgs.gnugrep
  ];
in
{
  inherit codexRuntimeInputs;

  configMergePkg = pkgs.writeShellApplication {
    name = "codex-config-merge";
    runtimeInputs = codexRuntimeInputs;
    text = builtins.readFile ./scripts/config-merge.sh;
  };

  verifyTrustPkg = pkgs.writeShellApplication {
    name = "codex-verify-hook-trust";
    runtimeInputs = codexRuntimeInputs;
    text = builtins.readFile ./scripts/verify-hook-trust.sh;
  };
}
