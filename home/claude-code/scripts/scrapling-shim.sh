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
# `--version` and anything else pass through untouched.
#
# `--` is the end-of-options marker and Click treats it as transparent, so it
# may sit before `extract`, before the subcommand, or both. Locate each word by
# stepping over one rather than hard-coding an index — hard-coding produced two
# bypasses, the second found only after the first was fixed:
#   scrapling extract -- get URL out    `--` read as the subcommand
#   scrapling -- extract get URL out    `extract` assumed to be argv[1]
# Both fetched the page unsanitized: measured live at 196 bytes against the 180
# a flagged run produces.
cmd_pos=1
[ "${1:-}" = "--" ] && cmd_pos=2
sub_pos=$((cmd_pos + 1))
[ "${!sub_pos-}" = "--" ] && sub_pos=$((sub_pos + 1))
next_pos=$((sub_pos + 1))

cmd="${!cmd_pos-}"
sub="${!sub_pos-}"
next="${!next_pos-}"

inject=0
if [ "$cmd" = "extract" ]; then
  case "$sub" in
    get | post | put | delete | fetch | stealthy-fetch) inject=1 ;;
    *) ;;
  esac
fi

# ONE reason not to inject, and it is checked at ONE position: the token
# immediately after the subcommand being `--help`.
#
# The first version scanned the WHOLE argv for `--help` or an existing
# `--ai-targeted`, and that was the same defect the replaced hook had — a token
# Click consumes as an option VALUE is not an option. `-s --help`,
# `--proxy --help`, `-H --help` and `-s --ai-targeted` all suppressed injection
# while the fetch went ahead unsanitized. Position, not presence.
#
# No check for an existing `--ai-targeted` either: the flag is idempotent
# (measured — `--ai-targeted --ai-targeted` exits 0 with identical output), so
# injecting unconditionally is both simpler and impossible to trick.
if [ "$inject" = 1 ] && [ "$next" = "--help" ]; then
  inject=0
fi

if [ "$inject" = 1 ]; then
  # Right after the subcommand, so Click binds it to the subcommand rather than
  # to the `extract` group or to whatever option happens to precede it.
  set -- "${@:1:sub_pos}" --ai-targeted "${@:sub_pos+1}"
fi

exec "$REAL" "$@"
