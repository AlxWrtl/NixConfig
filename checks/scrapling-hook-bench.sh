#!/usr/bin/env bash
# Bench for the scrapling PreToolUse hook, AFTER the shim took over.
#
# The hook's job shrank to one thing: refuse the real binary when it is reached
# by its full path, which is the only way to skip the shim on PATH. Everything
# else — quoting, `$(...)`, `eval`, variable indirection, compound lines — is
# the shim's problem now, and the shim solves it by running after the shell
# instead of guessing before it. See checks/scrapling-shim-fuzz.sh, which is
# where the actual guarantee is tested.
#
# The previous version of this file held 51 hand-written cases against a
# text-matching hook. It went green while the hook still had seven real
# defects, because enumeration only ever covers the shapes its author already
# thought of. Kept short on purpose: a small contract deserves a small bench.
#
# With no argument, the hook is extracted straight out of hooks.nix so this
# tests what Nix will write, and works before any rebuild.

if [ $# -ge 1 ]; then
  HOOK="$1"
else
  HOOK="${TMPDIR:-/tmp}/scrapling-hook-under-test.sh"
  "$(dirname "${BASH_SOURCE[0]}")/scrapling-hook-extract.sh" "$HOOK" >/dev/null
fi
PASS=0
FAIL=0
REAL='/Users/alx/.local/share/uv/tools/scrapling/bin/scrapling'

run() { # run <expect: deny|allow> <label> <command> [tool]
  local expect="$1" label="$2" cmd="$3" tool="${4:-Bash}" out decision
  out=$(printf '%s' "$(jq -nc --arg t "$tool" --arg c "$cmd" \
    '{tool_name:$t,tool_input:{command:$c}}')" | bash "$HOOK" 2>&1)
  if echo "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    decision=deny
  else
    decision=allow
  fi
  if [ "$decision" = "$expect" ]; then
    PASS=$((PASS + 1))
    printf 'ok    %-52s -> %s\n' "$label" "$decision"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %-52s -> %s (expected %s)\n' "$label" "$decision" "$expect"
  fi
}

echo "=== hook under test: $HOOK ==="
[ -f "$HOOK" ] || {
  echo "MISSING: $HOOK"
  exit 1
}
echo

echo "--- must DENY: the real binary reached directly, skipping the shim ---"
run deny "absolute path, no flag" "$REAL extract get https://x o.md"
run deny "absolute path, WITH flag" "$REAL extract get https://x o.md --ai-targeted"
run deny "absolute path, compound" "cd /tmp && $REAL extract fetch https://x o.md"
run deny "absolute path, other subcmd" "$REAL extract stealthy-fetch https://x o.md"
# The flag on the command line is irrelevant here: the objection is to routing
# around the shim at all, not to this one invocation's arguments.

echo
echo "--- must ALLOW: the shim handles these, denying them would be a false positive ---"
run allow "plain call, no flag" 'scrapling extract get https://x o.md'
run allow "plain call, compound" 'cd /tmp && scrapling extract get https://x o.md'
run allow "plain call with flag" 'scrapling extract get https://x o.md --ai-targeted'
run allow "quoted subcommand" 'scrapling extract "get" https://x o.md'
run allow "command substitution" 'echo $(scrapling extract get https://x o.md)'
run allow "eval" 'eval "scrapling extract get https://x o.md"'
run allow "variable indirection" 'S=scrapling; $S extract get https://x o.md'
run allow "install / shell / version" 'scrapling install && scrapling shell'
run allow "prose mentioning it" 'echo "scrapling extract get is documented"'
run allow "unrelated command" 'ls -la /tmp'

echo
echo "--- must DENY: other ways to the same binary, all found by review ---"
# The first version matched one spelling of the path, so every one of these
# walked past it. They all name the tool directory, or reach it through uv.
run deny "relative after cd" 'cd ~/.local/share/uv/tools/scrapling/bin && ./scrapling extract get https://x o.md'
run deny "PATH prefix" 'PATH=/Users/alx/.local/share/uv/tools/scrapling/bin scrapling extract get https://x o.md'
run deny "dir in a variable" 'D=/Users/alx/.local/share/uv/tools/scrapling/bin; $D/scrapling extract get https://x o.md'
run deny "redundant slashes" '/Users/alx/.local/share/uv/tools/scrapling/bin/./scrapling extract get https://x o.md'
run deny "uvx" 'uvx scrapling extract get https://x o.md'
run deny "uv tool run" 'uv tool run scrapling extract get https://x o.md'
run deny "the venv python" '/Users/alx/.local/share/uv/tools/scrapling/bin/python -c "from scrapling.cli import main; main()"'

echo
echo "--- accepted FALSE POSITIVES: denied although nothing would run ---"
# The read-only exemption that used to allow these matched cat/ls/head ANYWHERE
# on the line, so `cat /dev/null; $REAL extract get U o` was exempted too — it
# let running through, which is the opposite of its purpose. Scoping it needs
# per-segment shell parsing, the guessing this design exists to avoid. Denying
# `cat` on one nix-managed path is the cheaper mistake; use the Read tool.
run deny "cat the real binary" "cat $REAL"
run deny "ls the tool dir" "ls -l $REAL"

echo
echo "--- must ALLOW: wrong tool, and malformed payloads must not deny-all ---"
run allow "Read tool" "$REAL extract get https://x o.md" Read
run allow "empty command" ''
run allow "null command" 'null'

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
