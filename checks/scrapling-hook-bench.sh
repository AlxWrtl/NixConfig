#!/usr/bin/env bash
# Behavioural test bench for the scrapling --ai-targeted PreToolUse hook.
# Read-only: feeds JSON fixtures on stdin, asserts deny/allow. Writes nothing.
#
# Contract under test:
#   1. tool_name != Bash                     -> silent (allow)
#   2. no "scrapling extract" in command     -> silent (allow)
#   3. "--ai-targeted" already present       -> silent (allow)
#   4. otherwise                             -> deny
# The bypass cases (compound lines) are the ones that matter: an anchored
# prefix regex would let them through silently, which is the measured flaw
# of the rtk hook this must NOT reproduce.

# With no argument, extract the hook straight out of hooks.nix so the bench
# tests what NIX WILL WRITE, not a copy that may have drifted, and so it works
# before any rebuild has installed the hook.
if [ $# -ge 1 ]; then
  HOOK="$1"
else
  HOOK="${TMPDIR:-/tmp}/scrapling-hook-under-test.sh"
  "$(dirname "${BASH_SOURCE[0]}")/scrapling-hook-extract.sh" "$HOOK" >/dev/null
fi
PASS=0
FAIL=0

run() { # run <expect: deny|allow> <label> <command>
  local expect="$1" label="$2" cmd="$3" tool="${4:-Bash}"
  local out decision
  out=$(printf '%s' "$(jq -nc --arg t "$tool" --arg c "$cmd" \
        '{tool_name:$t,tool_input:{command:$c}}')" | bash "$HOOK" 2>&1)
  if echo "$out" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    decision=deny
  else
    decision=allow
  fi
  if [ "$decision" = "$expect" ]; then
    PASS=$((PASS+1)); printf 'ok    %-58s -> %s\n' "$label" "$decision"
  else
    FAIL=$((FAIL+1)); printf 'FAIL  %-58s -> %s (expected %s)\n' "$label" "$decision" "$expect"
    [ -n "$out" ] && printf '        payload: %s\n' "$out"
  fi
}

echo "=== hook under test: $HOOK ==="
[ -f "$HOOK" ] || { echo "MISSING: $HOOK"; exit 1; }
echo

echo "--- must DENY (missing --ai-targeted) ---"
run deny "plain get"            'scrapling extract get "https://x.com" out.md'
run deny "fetch"                'scrapling extract fetch "https://x.com" out.md'
run deny "stealthy-fetch"       'scrapling extract stealthy-fetch "https://x.com" o.md'
run deny "post"                 'scrapling extract post "https://x.com" o.md -d "a=1"'
run deny "BYPASS cd &&"         'cd /tmp && scrapling extract get "https://x.com" o.md'
run deny "BYPASS semicolon"     'echo hi; scrapling extract get "https://x.com" o.md'
run deny "BYPASS env prefix"    'FOO=1 scrapling extract get "https://x.com" o.md'
run deny "BYPASS pipe"          'true | scrapling extract get "https://x.com" o.md'
run deny "BYPASS abs path"      '/Users/alx/.local/bin/scrapling extract get "https://x" o.md'
run deny "BYPASS subshell"      '(scrapling extract get "https://x.com" o.md)'
run deny "BYPASS newline"       'echo hi
scrapling extract get "https://x.com" o.md'
run deny "with css selector"    'scrapling extract get "https://x.com" o.md -s article'

echo
echo "--- must DENY: flag present but NOT on the extract call (C1 regression) ---"
# The flag check must be scoped to the shell segment holding the extract call.
# A whole-line search lets a mention anywhere disarm a real, unflagged call.
run deny "flag only in unrelated echo" \
  'echo "use --ai-targeted always" && scrapling extract get "https://x.com" o.md'
run deny "flag only on 2nd of 2 calls" \
  'scrapling extract get A a.md && scrapling extract get B b.md --ai-targeted'
run deny "flag in a comment"          \
  'scrapling extract get "https://x.com" o.md # --ai-targeted'
run deny "flag only after a pipe"     \
  'scrapling extract get A a.md | grep -- --ai-targeted'

echo
echo "--- must DENY: shapes found by independent review, all reproduced ---"
# Every one of these ALLOWED an unflagged extract before the quote-blanking /
# line-joining / separator fixes. Each was replayed against the live hook.
run deny "single & separator"        'scrapling extract get https://x o.md & echo --ai-targeted'
run deny "flag literal in a URL"     'scrapling extract get "https://x/?q=--ai-targeted" o.md'
run deny "flag in a header value"    'scrapling extract get https://x o.md -H "X: --ai-targeted"'
run deny "quoted # fools stripper"   'echo " #" && scrapling extract get https://x o.md'
run deny "backslash continuation"    'scrapling \
extract get https://x o.md'
run deny "flag glued to a word"      'scrapling extract get https://x o.md --ai-targeted-later'

echo
echo "--- must ALLOW: false denials fixed by quote-blanking ---"
run allow "quoted # after real flag" 'scrapling extract get "https://x/a #b" o.md --ai-targeted'
run allow "prose in a commit msg"    'git commit -m "fix: scrapling extract get denies"'
# --help prints usage and fetches nothing; denying it was a pure false positive.
# It must sit DIRECTLY after the subcommand: anywhere else, Click swallows it as
# an option VALUE and a real extract runs. `-h` is NOT a scrapling option at all
# (`scrapling extract get -h` -> "Error: No such option '-h'"), so exempting it
# was pure attack surface — it excused nothing legitimate.
run allow "--help after subcommand"  'scrapling extract fetch --help'

echo
echo "--- must DENY: --help swallowed as an option value (a real extract runs) ---"
run deny "--help as -s value"        'scrapling extract get https://x o.md -s --help'
run deny "--help as -H value"        'scrapling extract get https://x o.md -H --help'
run deny "--help as --proxy value"   'scrapling extract get https://x o.md --proxy --help'
run deny "-h as -s value"            'scrapling extract get https://x o.md -s -h'
run deny "-h as a redirect target"   'scrapling extract get https://x o.md > -h'

echo
echo "--- must DENY: quote pairing the shell would not do (C1 regression, round 2) ---"
# Two sequential gsubs (double-quotes, then single) pair a `"` inside '...' with
# a later `"`, swallowing the real call between them. One alternation fixes it.
run deny "double quote inside single" \
  $'echo \x27a\x22\x27 ; scrapling extract get https://x o.md ; echo \x27\x22\x27'

echo
echo "--- KNOWN GAPS: unclosable by text matching, asserted so they stay visible ---"
# These need real shell semantics to catch. The hook is a guardrail against
# accidental omission, NOT a boundary against deliberate evasion. If one of
# these ever flips to deny, the matcher grew teeth it was not designed to have
# and probably started denying legitimate commands too — investigate, do not
# celebrate.
run allow "command substitution"     'echo $(scrapling extract get https://x o.md) --ai-targeted'
run allow "quoted subcommand"        'scrapling extract "get" https://x o.md'
run allow "variable indirection"     'S=scrapling; $S extract get https://x o.md'
run allow "eval + detached comment"  'eval "scrapling extract get https://x o.md" "#" --ai-targeted'
# Both need a real tokenizer, not a regex: a backslash-escaped quote makes the
# flag look present while it is really part of the output filename, and a quote
# opened on one line and closed on another hides the call from any per-line scan.
run allow "escaped quote forges flag" \
  $'scrapling extract get https://x \x22o\\\x22 --ai-targeted .md\x22'

echo
echo "--- accepted FALSE POSITIVE: denied though nothing would run ---"
# awk scans line by line, so a quoted string spanning newlines is not seen as
# quoted and its contents read as a command. Here the call is inside an echo and
# no extract ever runs, yet it is denied. Kept as-is deliberately: this is the
# fail-closed direction. Denying a harmless echo costs a turn; allowing a real
# call costs the protection. Asserted so the behaviour stays known, not silent.
run deny "call quoted across lines"  'echo "start
scrapling extract get https://x o.md
end"'

echo
echo "--- must ALLOW (flag present) ---"
run allow "flag at end"         'scrapling extract get "https://x.com" o.md --ai-targeted'
run allow "flag in middle"      'scrapling extract get --ai-targeted "https://x.com" o.md'
run allow "flag + selector"     'scrapling extract get "https://x" o.md --ai-targeted -s article'
run allow "compound with flag"  'cd /tmp && scrapling extract get "https://x" o.md --ai-targeted'

echo
echo "--- must ALLOW (not an extract command) ---"
run allow "scrapling install"   'scrapling install'
run allow "scrapling shell"     'scrapling shell'
run allow "scrapling --version" 'scrapling --version'
run allow "unrelated command"   'ls -la /tmp'
# Detection keys on `scrapling extract <subcommand>`, so prose that merely mentions
# the two words is not denied — otherwise editing the skill's own docs would be blocked.
run allow "prose mentioning it" 'echo "scrapling extract is documented in the skill"'
run allow "grep for the string" 'grep -r "scrapling extract" home/'

echo
echo "--- must ALLOW (wrong tool) ---"
run allow "Read tool"           'scrapling extract get "https://x.com" o.md' Read
run allow "Edit tool"           'scrapling extract get "https://x.com" o.md' Edit

echo
echo "--- robustness: must not crash or deny-all ---"
run allow "empty command"       ''
run allow "no command key"      'null'

echo
echo "=== $PASS passed, $FAIL failed ==="

echo
echo "--- regex linearity: 200-token adversarial line must return fast ---"
LONG=$(python3 -c 'print("a " * 2000 + "scrapling extract get u o.md")' 2>/dev/null \
       || printf 'scrapling extract get u o.md')
START=$(date +%s)
printf '%s' "$(jq -nc --arg c "$LONG" '{tool_name:"Bash",tool_input:{command:$c}}')" \
  | bash "$HOOK" >/dev/null 2>&1
END=$(date +%s)
echo "elapsed: $((END-START))s (must be 0-1s; a backtracking hook would hang every Bash call)"

[ "$FAIL" -eq 0 ]
