# scrapling shim — guarantees --ai-targeted on every `extract` subcommand.
#
# This replaces guessing with knowing. The PreToolUse hook it supersedes read
# the raw command line as TEXT, before the shell had touched it, so it had to
# predict what the shell would do with quotes, `$(...)`, `eval` and variable
# indirection. Seven defects came out of that, four unclosable by construction:
# no regex can know what `eval` will run.
#
# A shim is executed BY the shell, after parsing, so it receives the final
# argument vector and predicts nothing. The four shapes that defeated the hook
# all end up running this file.
#
# It is NOT put on PATH through home.packages: the nix profile dirs sit at
# positions 3-4 in PATH, behind ~/.local/bin at position 2, where uv installs
# its own `scrapling`. Activation symlinks ~/.local/bin/scrapling to this
# package instead, which is why the store path must stay stable and the
# activation entry must re-link on every run (uv recreates its symlink on every
# reinstall).
#
# writeShellApplication prepends `set -euo pipefail` and runs shellcheck at
# build time, so a regression in the script fails the rebuild rather than
# reaching PATH.
{ pkgs }:
{
  scraplingShimPkg = pkgs.writeShellApplication {
    name = "scrapling";
    text = builtins.readFile ./scripts/scrapling-shim.sh;
  };
}
