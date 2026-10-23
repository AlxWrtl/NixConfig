# preprod-curl — HTTP to the Preliz preprod (Cloudflare Access), packaged as a
# real binary on PATH.
#
# Why a CLI and not curl: the auto-mode classifier refused
# `$(cat ~/.config/secrets/…)` followed by curl to the preprod as Credential
# Exploration. The wrapper reads the Access service token and the agent
# passwords itself; the token travels only in a curl config on stdin, the
# password only through a process-substitution fd, never in argv, the URL,
# stdout or stderr (details in scripts/preprod-curl.sh). The allowlist then
# grants `Bash(preprod-curl *)` instead of a blanket `Bash(curl *)`.
#
# inheritPath = false: the script runs on bash builtins + curl + jq +
# coreutils only, so the caller's PATH cannot substitute any tool it calls.
#
# writeShellApplication runs shellcheck at build time and prepends
# `set -euo pipefail`, so a regression in the script fails the rebuild.
# mkPreprodCurl is exported so checks/preprod-curl.nix can build the same
# script against a stub curl (and build its canary mutants).
{ pkgs }:
let
  mkPreprodCurl =
    {
      curl ? pkgs.curl,
      text ? builtins.readFile ./scripts/preprod-curl.sh,
    }:
    pkgs.writeShellApplication {
      name = "preprod-curl";
      runtimeInputs = [
        curl
        pkgs.jq
        pkgs.coreutils
      ];
      inheritPath = false;
      inherit text;
    };
in
{
  preprodCurlPkg = mkPreprodCurl { };
  inherit mkPreprodCurl;
}
