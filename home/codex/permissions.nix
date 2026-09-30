# The Codex permissions profile, as a pure function of the vault path so
# checks/codex-config.nix can import the very same value and compare it with
# the CANONICAL copy hard-coded in scripts/config-merge.sh (C12). Rationale
# for the vault grant lives next to `alxVaultPath` in home/codex.nix.
{ alxVaultPath }:

{
  permissionsProfile = "git-workspace";
  # One TOML section, inline tables only. A `[permissions.git-workspace.*]`
  # sub-table would be a SECOND section header, and codex-config-merge replaces
  # exactly one section by name — the sub-table would survive the strip and
  # accumulate. Keeping it inline keeps the managed block singular.
  permissionsBlock = ''
    [permissions.git-workspace]
    extends = ":workspace"
    workspace_roots = { "${alxVaultPath}" = true }
    filesystem = { ":workspace_roots" = { ".git" = "write", ".git/hooks" = "read" } }
  '';
}
