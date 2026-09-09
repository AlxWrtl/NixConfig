# vault-snapshot — encrypted off-machine backup of AlxVault, packaged as a real
# binary on PATH (same rationale as graphify-reindex: one stable command for the
# SessionEnd hook to fire, a narrow `Bash(vault-snapshot)` permission grant
# instead of a blanket git/age/gh one, and shellcheck at build time via
# writeShellApplication).
#
# Since 2026-09-09 the vault lives outside the iCloud file provider, so iCloud
# is no longer a backup of it — and there is no Time Machine destination
# configured on this machine. This command IS the vault's only off-machine
# copy, which is why it verifies its own upload by downloading it back before
# rotating anything away.
#
# `age` is a system package (modules/packages.nix) and `gh` ships with the
# user profile; both are pinned here anyway so the script never depends on
# ambient PATH ordering.
{ pkgs }:
{
  vaultSnapshotPkg = pkgs.writeShellApplication {
    name = "vault-snapshot";
    runtimeInputs = [
      pkgs.git
      pkgs.age
      pkgs.gh
      pkgs.jq
      # GNU coreutils pinned on PATH: the script uses sha256sum and
      # `date -u`, and BSD coreutils differ on both.
      pkgs.coreutils
    ];
    text = builtins.readFile ./scripts/vault-snapshot.sh;
  };
}
