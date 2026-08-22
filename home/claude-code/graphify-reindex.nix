# graphify-reindex — incremental AlxVault knowledge-graph refresh, packaged as
# a real binary on PATH (same rationale as libdocs: one stable command for the
# APEX steps to fire in the background, a narrow `Bash(graphify-reindex)`
# permission grant instead of a blanket graphify/jq/find one, and shellcheck
# at build time via writeShellApplication).
#
# The graphify binary itself is NOT a nix input: it is a uv tool installed by
# the claudeCodeGraphify activation script into ~/.local/bin — the script
# references it by absolute path and degrades to a no-op when it is missing.
{ pkgs }:
{
  graphifyReindexPkg = pkgs.writeShellApplication {
    name = "graphify-reindex";
    runtimeInputs = [
      pkgs.jq
      # GNU coreutils/findutils pinned on PATH: the script uses GNU flags
      # (stat -c %Y / %s) that BSD stat does not understand.
      pkgs.coreutils
      pkgs.findutils
    ];
    text = builtins.readFile ./scripts/graphify-reindex.sh;
  };
}
