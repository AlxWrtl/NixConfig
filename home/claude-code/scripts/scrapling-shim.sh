# scrapling — shim that guarantees --ai-targeted on every extract subcommand.
#
# WHY A SHIM AND NOT A HOOK. The PreToolUse hook this replaces read the raw
# command line as TEXT, before the shell had interpreted it, so it had to guess
# what the shell would do with quotes, `$(...)`, `eval` and variable
# indirection. Seven defects came out of that guessing, four of them
# unclosable by construction. A shim runs AFTER the shell has parsed
# everything: it receives the final argument list and has nothing left to
# guess. `$(scrapling extract get U o)`, `eval "scrapling ..."`,
# `S=scrapling; $S extract get`, `scrapling extract "get"` — all four end up
# executing this file, so all four are covered.
#
# Limit, stated plainly: calling the real binary by its full path skips this
# shim. That is not something anyone writes by accident, and the hook covers it.
#
# writeShellApplication prepends `set -euo pipefail` and runs shellcheck at
# build time, so a regression here fails the rebuild.

REAL="$HOME/.local/share/uv/tools/scrapling/bin/scrapling"

if [ ! -x "$REAL" ]; then
  echo "scrapling: real binary not found at $REAL" >&2
  echo "scrapling: run a rebuild, or: uv tool install \"scrapling[shell]==0.4.15\"" >&2
  exit 127
fi

# Only `extract <subcommand>` accepts --ai-targeted. `install`, `shell`,
# `--version` and anything else are passed through untouched.
inject=0
if [ "${1:-}" = "extract" ]; then
  case "${2:-}" in
    get | post | put | delete | fetch | stealthy-fetch) inject=1 ;;
    *) ;;
  esac
fi

# Two reasons not to inject, both checked against the PARSED arguments rather
# than a text match, so neither can be forged by quoting:
#   --help    prints usage and fetches nothing
#   the flag  is already there (harmless to repeat, but keep the argv clean)
if [ "$inject" = 1 ]; then
  for arg in "$@"; do
    case "$arg" in
      --help | --ai-targeted)
        inject=0
        break
        ;;
      *) ;;
    esac
  done
fi

if [ "$inject" = 1 ]; then
  # Insert right after the subcommand, where it belongs to the subcommand and
  # not to the `extract` group.
  set -- "$1" "$2" --ai-targeted "${@:3}"
fi

exec "$REAL" "$@"
