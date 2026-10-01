# trello — Trello REST API v1 wrapper, packaged as a real binary on PATH.
#
# Why a CLI and not curl in the skill: the auto-mode classifier reads
# `cat ~/.config/secrets/trello-*` followed by egress to api.trello.com as an
# exfiltration shape, and refused Trello writes from one call to the next.
# The wrapper reads the key + token itself and sends them only as an
# Authorization header in a curl config on stdin (`curl -q -K -`): never in
# argv, the URL, stdout or stderr. The allowlist then grants `Bash(trello *)`
# instead of a blanket `Bash(curl *)`.
#
# inheritPath = false: the script runs on bash builtins + curl + jq only, so
# the caller's PATH cannot substitute any tool it calls.
#
# writeShellApplication runs shellcheck at build time and prepends
# `set -euo pipefail`, so a regression in the script fails the rebuild.
# mkTrello is exported so checks/trello-cli.nix can build the same script
# against a stub curl (and build its canary mutants).
{ pkgs }:
let
  mkTrello =
    {
      curl ? pkgs.curl,
      text ? builtins.readFile ./scripts/trello.sh,
    }:
    pkgs.writeShellApplication {
      name = "trello";
      runtimeInputs = [
        curl
        pkgs.jq
      ];
      inheritPath = false;
      inherit text;
    };
in
{
  trelloPkg = mkTrello { };
  inherit mkTrello;
}
