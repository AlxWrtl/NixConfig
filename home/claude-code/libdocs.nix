# libdocs — Context7 REST API wrapper, packaged as a real binary on PATH.
#
# Deliberately NOT an MCP server: MCP costs a permanent process plus tool-schema
# weight in every session. This is a CLI, invoked only when a docs lookup is
# actually needed, and it narrows the permission surface — the allowlist grants
# `Bash(libdocs *)` instead of a blanket `Bash(curl *)`.
#
# writeShellApplication runs shellcheck at build time and prepends
# `set -euo pipefail`, so a regression in the script fails the rebuild.
{ pkgs }:
{
  libdocsPkg = pkgs.writeShellApplication {
    name = "libdocs";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    text = builtins.readFile ./scripts/libdocs.sh;
  };
}
