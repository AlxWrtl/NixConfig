#!/usr/bin/env bash
# Fuzz the scrapling shim: does --ai-targeted reach the real binary no matter
# how the call is written?
#
# WHY FUZZ AND NOT A CASE LIST. The hook this replaces was tested by
# enumeration — a human listing the shapes they could think of. It passed 26,
# then 30, then 44 hand-written cases and still had seven real defects, because
# the mind that writes the matcher enumerates the same cases it already
# handled. Here the shell composition is GENERATED, so the test explores shapes
# nobody chose.
#
# Method: replace the real binary with a recorder that dumps its argv, then run
# the shim through randomly composed shell invocations and assert the recorded
# argv. Nothing touches the network and the real scrapling is never executed.

set -uo pipefail
SHIM="${1:-}"
if [ -z "$SHIM" ]; then
  echo "usage: scrapling-shim-fuzz.sh <path-to-shim>   (or: nix build the package)" >&2
  exit 2
fi

# Create the sandbox under TMPDIR explicitly, and ABORT if that fails. A bare
# `mktemp -d` is refused inside the Claude Code sandbox; the first version of
# this harness let the failure through, so $WORK was empty and every path
# resolved to /home and /bin. It then reported 44 failures that were all its
# own. An empty work dir must stop the run, never produce results.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/scrapling-fuzz.XXXXXX") || {
  echo "fuzz: cannot create a work directory under ${TMPDIR:-/tmp}" >&2
  exit 2
}
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
  echo "fuzz: work directory is empty or missing — refusing to run" >&2
  exit 2
fi
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
REAL_DIR="$HOME/.local/share/uv/tools/scrapling/bin"
mkdir -p "$REAL_DIR" "$WORK/bin"

# The recorder stands in for the real scrapling: it writes its argv, one per
# line, and exits 0. If the shim ever fails to exec it, the file stays absent.
cat > "$REAL_DIR/scrapling" <<'REC'
#!/usr/bin/env bash
: > "$ARGV_OUT"
for a in "$@"; do printf '%s\n' "$a" >> "$ARGV_OUT"; done
REC
chmod +x "$REAL_DIR/scrapling"

# Install the shim under test, and REFUSE TO RUN if that did not work.
# Without these checks the harness reported "48 passed, 0 failed" and exit 0
# for the argument /nonexistent/path/scrapling: `cp` failed, nothing landed in
# $WORK/bin, and PATH fell through to the shim already installed on the
# machine. It graded the live system while claiming to grade its argument.
[ -f "$SHIM" ] && [ -r "$SHIM" ] || {
  echo "fuzz: shim not found or not readable: $SHIM" >&2
  exit 2
}
cp "$SHIM" "$WORK/bin/scrapling" || {
  echo "fuzz: cannot install the shim under test" >&2
  exit 2
}
chmod +x "$WORK/bin/scrapling"
[ -x "$WORK/bin/scrapling" ] || {
  echo "fuzz: installed shim is not executable" >&2
  exit 2
}
export PATH="$WORK/bin:$PATH"
export ARGV_OUT="$WORK/argv.txt"

# TRIPWIRE: prove the harness can SEE a missing flag before trusting anything
# it says. A pass-through shim must be scored as not-injecting; if it is not,
# the instrument is blind and every number below is decoration.
cat > "$WORK/_tripwire" <<TW
#!/usr/bin/env bash
exec "$REAL_DIR/scrapling" "\$@"
TW
chmod +x "$WORK/_tripwire"
rm -f "$ARGV_OUT"
"$WORK/_tripwire" extract get https://x o.md >/dev/null 2>&1
if [ ! -f "$ARGV_OUT" ]; then
  echo "fuzz: tripwire never reached the recorder — harness is broken" >&2
  exit 2
fi
if grep -qx -- '--ai-targeted' "$ARGV_OUT"; then
  echo "fuzz: tripwire scored a pass-through shim as injecting the flag." >&2
  echo "fuzz: the harness cannot detect a missing flag; refusing to report." >&2
  exit 2
fi

SUBS=(get post put delete fetch stealthy-fetch)
PASS=0; FAIL=0

# Composition templates. %s is the invocation; each must end up executing the
# shim. They are deliberately nasty: the four shapes that defeated the hook are
# in here, plus quoting games.
TEMPLATES=(
  '%s'
  'cd /tmp && %s'
  'true; %s'
  'true | %s'
  'FOO=1 %s'
  '( %s )'
  '{ %s ; }'
  'eval "%s"'
  'S=scrapling; %s'
  'f() { %s ; }; f'
  'true && %s # --ai-targeted'
  'echo "--ai-targeted" > /dev/null; %s'
  'true \
  && %s'
)

run_case() {  # run_case <shell-line> <label>
  rm -f "$ARGV_OUT"
  bash -c "$1" >/dev/null 2>&1
  if [ ! -f "$ARGV_OUT" ]; then
    FAIL=$((FAIL+1)); printf 'FAIL  %-30s real binary never ran\n      %s\n' "$2" "$1"; return
  fi
  # POSITION, not presence. `-s --ai-targeted` puts the literal string in argv
  # as the css-selector VALUE while ai_targeted stays False — presence alone
  # scored that as a pass. Whatever shell wrapper was used, the real binary's
  # argv is always `extract <sub> --ai-targeted …`, so the flag belongs at
  # index 3 — or 4 when `--` sits between `extract` and the subcommand.
  local want=3
  [ "$(sed -n 2p "$ARGV_OUT")" = "--" ] && want=4
  if [ "$(sed -n "${want}p" "$ARGV_OUT")" = "--ai-targeted" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    printf 'FAIL  %-30s flag not at argv[%s]\n      cmd:  %s\n      argv: %s\n' \
      "$2" "$want" "$1" "$(tr '\n' ' ' < "$ARGV_OUT")"
  fi
}

echo "=== fuzz: flag must reach the real binary in every composition ==="
for tpl in "${TEMPLATES[@]}"; do
  for i in 1 2 3; do
    sub=${SUBS[$((RANDOM % ${#SUBS[@]}))]}
    # Randomised, hostile argument shapes.
    case $((RANDOM % 6)) in
      0) args="https://x.example/a o.md" ;;
      1) args="\"https://x.example/?q=--ai-targeted\" o.md" ;;
      2) args="https://x.example o.md -s article" ;;
      3) args="https://x.example o.md -H \"X: --ai-targeted\"" ;;
      4) args="'https://x.example/a#frag' o.md" ;;
      5) args="https://x.example \"o md.md\"" ;;
    esac
    inv="scrapling extract $sub $args"
    if [ "$tpl" = 'S=scrapling; %s' ]; then inv="\$S extract $sub $args"; fi
    # shellcheck disable=SC2059
    line=$(printf "$tpl" "$inv")
    run_case "$line" "$(echo "$tpl" | head -1 | cut -c1-28)"
  done
done

echo
echo "=== the four shapes that defeated the text-matching hook ==="
run_case 'echo $(scrapling extract get https://x o.md)' "command substitution"
run_case 'eval "scrapling extract get https://x o.md"' "eval"
run_case 'S=scrapling; $S extract get https://x o.md'  "variable indirection"
run_case 'scrapling extract "get" https://x o.md'      "quoted subcommand"

echo
echo "=== argv shapes, where the shim broke ==="
# None of these were covered by the templates above, and all three reached the
# real binary unflagged. `--` hid the subcommand; the other two exploited that
# suppression scanned the WHOLE argv, so a token consumed by Click as an option
# VALUE was mistaken for the user asking for help or already passing the flag.
run_case 'scrapling extract -- get https://x o.md'            "-- before subcommand"
run_case 'scrapling extract get https://x o.md -s --help'     "--help as -s value"
run_case 'scrapling extract get https://x o.md --proxy --help' "--help as --proxy value"
run_case 'scrapling extract get https://x o.md -H --help'     "--help as -H value"
run_case 'scrapling extract get https://x o.md -s --ai-targeted' "flag as -s value"
run_case 'scrapling extract get https://x -- --help'          "--help as positional"

echo
echo "=== the flag must land right after the subcommand, not merely somewhere ==="
# Presence is not placement: Click binds a value to the option before it, so a
# flag inserted in the wrong slot can be swallowed as somebody's argument.
rm -f "$ARGV_OUT"
bash -c 'scrapling extract get https://x o.md -s article' >/dev/null 2>&1
if [ -f "$ARGV_OUT" ] && [ "$(sed -n 3p "$ARGV_OUT")" = "--ai-targeted" ]; then
  PASS=$((PASS+1)); printf 'ok    %-30s argv[3] == --ai-targeted\n' "flag position"
else
  FAIL=$((FAIL+1))
  printf 'FAIL  %-30s argv: %s\n' "flag position" "$(tr '\n' ' ' < "$ARGV_OUT" 2>/dev/null)"
fi

echo
echo "=== must NOT inject: --help, and non-extract subcommands ==="
neg() { # neg <line> <label> <token-that-must-be-absent>
  rm -f "$ARGV_OUT"; bash -c "$1" >/dev/null 2>&1
  if [ -f "$ARGV_OUT" ] && grep -qx -- "$3" "$ARGV_OUT"; then
    FAIL=$((FAIL+1)); printf 'FAIL  %-30s injected when it must not\n' "$2"
  else
    PASS=$((PASS+1)); printf 'ok    %-30s\n' "$2"
  fi
}
neg 'scrapling extract get --help'    "extract get --help"    '--ai-targeted'
neg 'scrapling install'               "install"               '--ai-targeted'
neg 'scrapling shell'                 "shell"                 '--ai-targeted'
neg 'scrapling --version'             "--version"             '--ai-targeted'

echo
echo "=== an explicit flag is injected over, on purpose ==="
# The shim does NOT look for an existing --ai-targeted before injecting. That
# search is what let `-s --ai-targeted` disarm it: a token Click consumes as an
# option value is not an option. Injecting unconditionally cannot be tricked,
# and the duplicate is free — measured on 0.4.15, `--ai-targeted --ai-targeted`
# exits 0 with byte-identical output. What matters is the flag at argv[3].
rm -f "$ARGV_OUT"
bash -c 'scrapling extract get https://x o.md --ai-targeted' >/dev/null 2>&1
if [ "$(sed -n 3p "$ARGV_OUT" 2>/dev/null)" = "--ai-targeted" ]; then
  PASS=$((PASS+1)); printf 'ok    %-30s injected at argv[3] regardless\n' "explicit flag"
else
  FAIL=$((FAIL+1)); printf 'FAIL  %-30s argv: %s\n' "explicit flag" \
    "$(tr '\n' ' ' < "$ARGV_OUT" 2>/dev/null)"
fi

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
