# nix-options — nix-darwin + home-manager option docs, packaged as a real
# binary on PATH. Replaces the static Nix-Darwin-Doc.md: it evaluates the
# option declarations pinned by flake.lock, so the docs never drift from the
# modules actually in use, and links "declared in" to GitHub at the lock rev.
#
# NO `pkgs.nix` in runtimeInputs on purpose: writeShellApplication appends the
# caller PATH, so `nix` resolves to the system Determinate nix (same daemon,
# settings and lazy trees as darwin-rebuild), not a second nixpkgs nix.
#
# Inside the Claude sandbox the daemon socket is denied; the script retries on
# a read-only local store with a private XDG_CACHE_HOME. It must stay sandboxed:
# allowlisted as `Bash(nix-options *)`, never in excludedCommands.
#
# writeShellApplication runs shellcheck at build time and prepends
# `set -euo pipefail`, so a regression in the script fails the rebuild.
{ pkgs }:
{
  nixOptionsPkg = pkgs.writeShellApplication {
    name = "nix-options";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
    ];
    text = builtins.readFile ./scripts/nix-options.sh;
  };
}
