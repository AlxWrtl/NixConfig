# ttw-ci-gate — CI parity for TTW validation, packaged as a real binary on PATH.
#
# Why: TTW validation never looked at a repo's CI, so a change could pass
# every local gate and fail a GitHub Actions step. The tool reads
# `.github/workflows/*.y{a,}ml`, classifies each `run:` step (local / setup /
# ci-only (reason)) on the STEP's own text and env, never the job env (a
# job-level secret does not make a DB-free typecheck ci-only), and `--run`
# executes the local ones as `bash -eo pipefail -c`, deduplicated by run
# text. The TTW steps run it at baseline and gate; ci-only lines are listed,
# never counted green.
#
# writePython3Bin runs flake8 at build time (only E501 ignored), so a
# regression in the script fails the rebuild; checks/ttw-ci-gate.nix runs the
# built binary against workflow fixtures plus six canary mutants. PyYAML is
# the only non-stdlib dependency; no network, no git of its own.
{ pkgs }:
{
  ttwCiGatePkg = pkgs.writers.writePython3Bin "ttw-ci-gate" {
    libraries = [ pkgs.python3Packages.pyyaml ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/ttw-ci-gate.py);
}
