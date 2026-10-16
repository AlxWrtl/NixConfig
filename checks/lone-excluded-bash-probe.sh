#!/usr/bin/env bash
# Positive control for `hookLoneExcludedBash` — the PreToolUse hook that
# denies a sandbox-excluded command (git push/commit/pull/fetch, gh,
# claude-dispatch, claude-bg) composed with anything that keeps the Bash call
# sandboxed.
#
# WHAT IT GRADES, IN BOTH POLARITIES. A hook that denies every `git push`
# scores green on every deny case, so each deny shape has partners that must
# PASS: the lone command, its quoted arguments, fd duplication (2>&1), a
# chain made only of lone excluded commands (user decision 2026-10-11;
# claude-dispatch joined the excluded set 2026-10-15, claude-bg 2026-10-16),
# text
# that merely MENTIONS one (grep, rg, echo, a commit message), and every
# input the hook cannot read (malformed JSON, an unbalanced quote, an input
# past its 4 MiB cap): it fails OPEN.
#
# PASS IS ASSERTED ON EMPTINESS: stdout empty byte for byte, never the
# absence of a word — a hook that crashed before printing would pass that.
#
# EVERY RUN IS BOUNDED: a 10 s alarm per run; the `pass-fast` cases (128 KB
# of `git push ` on one line, a 64 KB newline flood) must finish in 1000 ms.
#
# WHY THE MUTANTS ARE PART OF THE FILE. A test only ever seen passing has not
# been run. Each mutant is a literal substitution on the REAL hook body and
# must go red on EXACTLY its declared set:
#
#   m1  chain: a call passes when ANY segment is a clean target (`some`).
#   m2  redir: a file redirection no longer counts.
#   m3  subst: a command substitution no longer counts.
#   m4  quote: double quotes no longer group a word (over-block).
#   m5  failopen: malformed JSON denies (over-block).
#   m6  dup: fd duplication counted as a file redirection (over-block).
#
# THE EXACT COMMANDS THAT MAKE THIS PROBE GO RED:
#
#   bash checks/lone-excluded-bash-probe.sh --mutants      # all, graded
#   bash checks/lone-excluded-bash-probe.sh --mutant m2    # one, raw output
#   bash checks/lone-excluded-bash-probe.sh old-hook.js    # another body
#
# Standalone: NOT wired into `nix flake check` (the hook-wiring check runs a
# subset of these cases and the same six mutants). The hook is a plain
# `builtins.readFile` in hooks.nix, so the repo file IS the installed body
# and no `nix eval` is needed to grade it.
#
# usage: lone-excluded-bash-probe.sh [hook.js]
#        lone-excluded-bash-probe.sh --mutants
#        lone-excluded-bash-probe.sh --mutant m1..m6

# SC2034: the MN_EXPECT sets are read through ${!v}. SC2016: single-quoted
# shell text is the payload on purpose. SC2018/19: mutant ids are ASCII.
# shellcheck disable=SC2016,SC2018,SC2019,SC2034

set -euo pipefail

if [ -z "${EPOCHREALTIME:-}" ]; then
  echo "probe: bash >= 5 required (\$EPOCHREALTIME is unset in ${BASH_VERSION:-this shell})" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$REPO_ROOT/checks/$(basename "${BASH_SOURCE[0]}")"
HOOK_SRC="$REPO_ROOT/home/claude-code/hooks/lone-excluded-bash.js"

ALL_MUTANTS="m1 m2 m3 m4 m5 m6"

MODE="run"
ONE_MUTANT=""
case "${1:-}" in
  --mutants)
    MODE="mutants"
    shift
    ;;
  --mutant)
    MODE="one-mutant"
    ONE_MUTANT="${2:-}"
    case " $ALL_MUTANTS " in
      *" $ONE_MUTANT "*) ;;
      *)
        echo "probe: --mutant takes one of: $ALL_MUTANTS" >&2
        exit 2
        ;;
    esac
    shift 2 || true
    ;;
esac

SUT="${1:-}"

abspath() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s\n' "$PWD/$1" ;; esac; }

# An empty $WORK must STOP the run: every path would resolve to the root.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lone-excluded-bash-probe.XXXXXX") || {
  echo "probe: cannot create a work directory under ${TMPDIR:-/tmp}" >&2
  exit 2
}
if [ -z "${WORK:-}" ] || [ ! -d "$WORK" ]; then
  echo "probe: work directory is empty or missing — refusing to run" >&2
  exit 2
fi
cleanup() {
  if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT
mkdir -p "$WORK/out"

NODE="$(command -v node 2> /dev/null || true)"
[ -n "$NODE" ] || NODE=/run/current-system/sw/bin/node
[ -x "$NODE" ] || {
  echo "probe: no usable node interpreter (tried \$PATH and /run/current-system/sw/bin/node)" >&2
  exit 2
}
JQ="$(command -v jq 2> /dev/null || true)"
[ -n "$JQ" ] || {
  echo "probe: jq not found — the payload builders and stdout assertions need it" >&2
  exit 2
}
PERL="$(command -v perl 2> /dev/null || true)"
[ -n "$PERL" ] || {
  echo "probe: perl not found — the run alarm and the mutant builder need it" >&2
  exit 2
}

ORIG="$WORK/lone-excluded-bash.js"
[ -s "$HOOK_SRC" ] || {
  echo "probe: cannot read $HOOK_SRC" >&2
  exit 2
}
cp "$HOOK_SRC" "$ORIG"
if [ -n "$SUT" ]; then
  SUT="$(abspath "$SUT")"
  [ -f "$SUT" ] && [ -r "$SUT" ] || {
    echo "probe: script under test not found or not readable: $SUT" >&2
    exit 2
  }
else
  SUT="$ORIG"
fi

# ==============================================================================
# MUTANT DRIVER
# ==============================================================================

M1_EXPECT="d01-cd-chain d04-add-commit d05-pipe-head d12-newline d19-push-then-ls d23-semicolon d24-pipe-into-gh d33-dispatch-cd d36-dispatch-pipe d41-bg-cd d44-bg-pipe"
M2_EXPECT="d06-redir-file d20-devnull d35-dispatch-redir d43-bg-redir"
M3_EXPECT="d07-subst-in-msg d08-echo-subst d21-backtick-msg d31-heredoc-body d34-dispatch-subst d42-bg-subst"
M4_EXPECT="a09-quoted-msg a33-dispatch-quoted-sep d15-quoted-verb d17-bash-c"
M5_EXPECT="a12-malformed"
M6_EXPECT="a06-fd-dup a17-push-dup-dash"

mutant_expect() {
  local v
  v="$(printf '%s' "$1" | tr 'a-z' 'A-Z')_EXPECT"
  printf '%s\n' "${!v}"
}

lit_sub() {
  FROM="$3" TO="$4" "$PERL" -pe 's/\Q$ENV{FROM}\E/$ENV{TO}/g' "$1" > "$2"
}

build_mutant() { # build_mutant <mN> <destination>
  local which="$1" dest="$2" from="" to="" n
  case "$which" in
    m1) from='if (!segs.every(isCleanTarget)) return CAUSE.shape;' to='if (!segs.some(isCleanTarget)) return CAUSE.shape;' ;;
    m2) from='if (!dup) r.fileRedir = true;' to='if (false) r.fileRedir = true;' ;;
    m3) from='if (r.subst) return CAUSE.subst;' to='if (false) return CAUSE.subst;' ;;
    m4) from="if (ch === '\"') {" to='if (false) {' ;;
    m5) from='try { data = JSON.parse(input); } catch { allow(); return; }' to='try { data = JSON.parse(input); } catch { deny("BLOCKED: malformed input"); return; }' ;;
    m6) from='const dup = (op === ">&" || op === "<&") && /^(?:[0-9]+-?|-)$/.test(w.val);' to='const dup = false;' ;;
  esac
  n="$(grep -cF -- "$from" "$ORIG" || true)"
  [ "$n" = "1" ] || {
    echo "probe: $which did not apply — expected its text exactly once, found $n (looked for: $from)" >&2
    return 1
  }
  lit_sub "$ORIG" "$dest" "$from" "$to"
  grep -qF -- "$to" "$dest" || {
    echo "probe: $which did not apply — replacement not found (looked for: $to)" >&2
    return 1
  }
  if cmp -s "$ORIG" "$dest"; then
    echo "probe: $which is byte-identical to the original — a no-op mutant proves nothing" >&2
    return 1
  fi
  "$NODE" --check "$dest" 2> "$WORK/$which.syntax" || {
    echo "probe: $which is not valid JavaScript:" >&2
    head -c 400 "$WORK/$which.syntax" >&2
    return 1
  }
}

if [ "$MODE" != "run" ]; then
  MUT_FAIL=0
  echo "=== lone-excluded-bash mutants (built from the repo hook, in $WORK) ==="
  echo
  set +e
  BASE_OUT="$("$BASH" "$SELF" "$ORIG" 2>&1)"
  BASE_RC=$?
  set -e
  RUNTIME_CASES="$(printf '%s\n' "$BASE_OUT" | awk '/^runtime-cases: /{print $2; exit}')"
  if [ "$BASE_RC" -eq 0 ]; then
    echo "baseline: green — $(printf '%s\n' "$BASE_OUT" | grep -E '^=== [0-9]+ passed')"
  else
    echo "baseline: NOT GREEN (rc=$BASE_RC), red on: $(printf '%s\n' "$BASE_OUT" | awk '/^FAIL /{print $2}' | tr '\n' ' ')"
    echo "baseline: refusing to grade mutants against a suite that already fails" >&2
    exit 2
  fi
  case "${RUNTIME_CASES:-}" in
    '' | *[!0-9]*)
      echo "probe: could not read the runtime-case count back from the child run" >&2
      exit 2
      ;;
  esac
  echo "baseline: $RUNTIME_CASES runtime cases, derived from the case table"
  echo

  for m in $ALL_MUTANTS; do
    [ "$MODE" = "one-mutant" ] && [ "$m" != "$ONE_MUTANT" ] && continue
    MF="$WORK/$m.js"
    if ! build_mutant "$m" "$MF"; then
      echo "MUTANT $m: COULD NOT BE BUILT"
      MUT_FAIL=$((MUT_FAIL + 1))
      continue
    fi
    set +e
    MOUT="$("$BASH" "$SELF" "$MF" 2>&1)"
    set -e
    RED="$(printf '%s\n' "$MOUT" | awk '/^FAIL /{print $2}' | sort | tr '\n' ' ')"
    RED="${RED% }"
    N_RED="$(printf '%s\n' "$MOUT" | awk '/^FAIL /{print $2}' | wc -l | tr -d ' ')"
    WANT="$(mutant_expect "$m")"
    # shellcheck disable=SC2086 # word-splitting the declared set is the point
    WANT="$(printf '%s\n' $WANT | sort | tr '\n' ' ')"
    WANT="${WANT% }"
    if [ "$MODE" = "one-mutant" ]; then
      printf '%s\n' "$MOUT"
      echo
    fi
    echo "MUTANT $m"
    echo "  red   ($N_RED): $RED"
    echo "  want  : $WANT"
    if [ -z "$WANT" ]; then
      echo "  verdict: MISMATCH — a mutant with no declared red set proves nothing"
      MUT_FAIL=$((MUT_FAIL + 1))
    elif [ "$RED" = "$WANT" ]; then
      echo "  verdict: TARGETED — the probe goes red on exactly the declared set"
    else
      echo "  verdict: MISMATCH"
      MUT_FAIL=$((MUT_FAIL + 1))
    fi
    echo
  done
  if [ "$MUT_FAIL" -eq 0 ]; then
    echo "=== mutants: all declared red sets matched ==="
  else
    echo "=== mutants: $MUT_FAIL mutant(s) did not match their declared red set ==="
  fi
  [ "$MUT_FAIL" -eq 0 ]
  exit $?
fi

# ==============================================================================
# PAYLOADS
# ==============================================================================

PUSH128K="$(head -c 14564 /dev/zero | tr '\0' 'x' | sed 's/x/git push /g')"
[ "${#PUSH128K}" -ge 131072 ] || {
  echo "probe: the 128 KB payload is ${#PUSH128K} bytes, expected >= 131072" >&2
  exit 2
}
HD_COMMIT="$(printf "git commit -F - <<'EOF'\nfix: x\nEOF")"
NL_PUSH="$(printf 'cd /x\ngit push')"
CONT_PUSH="$(printf 'git push \\\n  origin feat/x')"
HD_BODY_SUBST="$(printf '%s\n%s\n%s' 'cat <<EOF' '$(gh auth token)' 'EOF')"
HD_QBODY_SUBST="$(printf '%s\n%s\n%s' "cat <<'EOF'" '$(gh auth token)' 'EOF')"

# ==============================================================================
# RUNNER
# ==============================================================================

PASS=0
FAIL=0
NCASES=0

fail_case() {
  FAIL=$((FAIL + 1))
  printf 'FAIL  %-28s %s\n' "$1" "$2"
}
ok_case() {
  PASS=$((PASS + 1))
  printf 'ok    %-28s %s\n' "$1" "$2"
}

now_ms() { printf '%s\n' "${EPOCHREALTIME/[.,]/}" | cut -c1-13; }

RUN_RC=0
RUN_MS=0
run_raw() { # run_raw <payload> <stdout> <stderr>
  local t0 t1
  t0="$(now_ms)"
  set +e
  (cd "$WORK" && "$PERL" -e 'alarm 10; exec @ARGV or die "exec: $!"' "$NODE" "$SUT" < "$1" > "$2" 2> "$3")
  RUN_RC=$?
  set -e
  t1="$(now_ms)"
  RUN_MS=$((t1 - t0))
}

# grade <label> <deny|pass|pass-fast> <stdout> <stderr> [reason-substring]
grade() {
  local label="$1" kind="$2" out="$3" err="$4" want="${5:-}" why="" reason
  if [ "$RUN_RC" != "0" ]; then
    why="exit: expected 0, got $RUN_RC after ${RUN_MS} ms (stderr: $(head -c 200 "$err"))"
  elif [ -s "$err" ]; then
    why="stderr: expected empty, got $(head -c 200 "$err")"
  fi
  if [ -z "$why" ]; then
    case "$kind" in
      deny)
        if [ ! -s "$out" ]; then
          why="stdout: expected a deny, got nothing"
        elif ! "$JQ" -e -s 'length == 1 and (.[0].hookSpecificOutput.permissionDecision == "deny") and (.[0].hookSpecificOutput.hookEventName == "PreToolUse")' "$out" > /dev/null 2>&1; then
          why="stdout is not one PreToolUse deny object: $(head -c 200 "$out")"
        else
          reason="$("$JQ" -r '.hookSpecificOutput.permissionDecisionReason' "$out")"
          case "$reason" in
            *"Run it ALONE"*"-F <file>"*"--body-file <file>"*) ;;
            *) why="reason lacks the run-alone / -F / --body-file fix: $reason" ;;
          esac
          case "$reason" in
            *dangerouslyDisableSandbox*) why="reason names dangerouslyDisableSandbox" ;;
            *"cwd persists"* | *"cd in a separate call"*) why="reason claims the cwd persists across calls: $reason" ;;
            *"project root"*) ;;
            *) why="reason lacks the project-root fix: $reason" ;;
          esac
          if [ -z "$why" ] && [ -n "$want" ]; then
            case "$reason" in
              *"$want"*) ;;
              *) why="denied, but the reason lacks '$want': $reason" ;;
            esac
          fi
        fi
        ;;
      pass | pass-fast)
        if [ -s "$out" ]; then
          why="stdout: expected empty, got $(head -c 200 "$out")"
        elif [ "$kind" = "pass-fast" ] && [ "$RUN_MS" -gt 1000 ]; then
          why="took ${RUN_MS} ms, bound is 1000 ms"
        fi
        ;;
      *) why="unknown kind: $kind" ;;
    esac
  fi
  if [ -n "$why" ]; then
    fail_case "$label" "$why"
  else
    ok_case "$label" "exit 0, $kind (${RUN_MS} ms)"
  fi
}

# check <label> <kind> <command> [reason-substring]
check() {
  local label="$1" kind="$2" cmd="$3" want="${4:-}" pay
  NCASES=$((NCASES + 1))
  pay="$WORK/out/$label.json"
  "$JQ" -n --arg c "$cmd" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}' > "$pay"
  run_raw "$pay" "$WORK/out/$label.stdout" "$WORK/out/$label.stderr"
  grade "$label" "$kind" "$WORK/out/$label.stdout" "$WORK/out/$label.stderr" "$want"
}

# check_raw <label> <kind> <payload-file>
check_raw() {
  NCASES=$((NCASES + 1))
  run_raw "$3" "$WORK/out/$1.stdout" "$WORK/out/$1.stderr"
  grade "$1" "$2" "$WORK/out/$1.stdout" "$WORK/out/$1.stderr"
}

echo "=== lone-excluded-bash probe ==="
echo "    hook under test: $SUT"
echo

# --- MUST DENY (AC6 + plan testing strategy) ---------------------------------
check d01-cd-chain deny 'cd /x && git push' 'next to another command'
check d02-git-C deny 'git -C /x push' 'next to another command'
check d03-git-c deny 'git -c a=b push' 'next to another command'
check d04-add-commit deny 'git add . && git commit -m x' 'next to another command'
check d05-pipe-head deny 'gh pr list | head' 'next to another command'
check d06-redir-file deny 'gh api x > out.json' 'file redirection'
check d07-subst-in-msg deny 'git commit -m "$(cat m)"' 'command substitution'
check d08-echo-subst deny 'echo $(gh auth token)' 'command substitution'
check d09-heredoc deny "$HD_COMMIT" 'heredoc'
check d10-env-prefix deny 'GIT_X=1 git push' 'next to another command'
check d11-timeout deny 'timeout 30 gh pr list' 'next to another command'
check d12-newline deny "$NL_PUSH" 'next to another command'
check d13-command-gh deny 'command gh pr list' 'next to another command'
check d14-abs-path deny '/usr/bin/git push' 'next to another command'
check d15-quoted-verb deny 'git "push"' 'next to another command'
check d16-subshell deny '(git push)' 'subshell'
check d17-bash-c deny 'bash -c "git push"' 'next to another command'
check d18-background deny 'git push &' 'background'
check d19-push-then-ls deny 'git push && ls' 'next to another command'
check d20-devnull deny 'gh pr view 1 2>/dev/null' 'file redirection'
check d21-backtick-msg deny 'git commit -m "`cat m`"' 'command substitution'
check d22-herestring deny 'git push <<< x' 'heredoc'
check d23-semicolon deny 'git status; git push' 'next to another command'
check d24-pipe-into-gh deny 'cat b.md | gh pr create --body-file -' 'next to another command'
check d25-group deny '{ git push; }' 'group'
check d26-timeout-signal deny 'timeout -s KILL 30 gh pr list' 'next to another command'
check d27-sudo-user deny 'sudo -u alx git push' 'next to another command'
check d28-env-unset deny 'env -u V git push' 'next to another command'
check d29-env-chdir deny 'env -C /x git push' 'next to another command'
check d30-rtk deny 'rtk git push' 'next to another command'
check d31-heredoc-body deny "$HD_BODY_SUBST" 'command substitution'
check d32-abs-path-cause deny '/usr/bin/git push' 'an absolute path'
check d33-dispatch-cd deny 'cd /x && claude-dispatch fix-a "fix the typo"' 'next to another command'
check d34-dispatch-subst deny 'claude-dispatch fix-a "$(cat brief.md)"' 'command substitution'
check d35-dispatch-redir deny 'claude-dispatch fix-a "fix the typo" > log.txt' 'file redirection'
check d36-dispatch-pipe deny 'claude-dispatch fix-a "fix the typo" | tee log' 'next to another command'
check d37-dispatch-herestring deny 'claude-dispatch fix-a "fix it now" <<< x' 'heredoc'
check d38-dispatch-abs deny '/etc/profiles/per-user/alx/bin/claude-dispatch fix-a "fix the typo"' 'an absolute path'
check d39-dispatch-env-assign deny 'CLAUDE_CONFIG_DIR=/x claude-dispatch fix-a "fix the typo"' 'next to another command'
check d40-dispatch-env-cmd deny 'env CLAUDE_CONFIG_DIR=/x claude-dispatch fix-a "fix the typo"' 'next to another command'
check d41-bg-cd deny 'cd /x && claude-bg logs 4b04dbe6' 'next to another command'
check d42-bg-subst deny 'claude-bg logs "$(cat id)"' 'command substitution'
check d43-bg-redir deny 'claude-bg logs 4b04dbe6 > log.txt' 'file redirection'
check d44-bg-pipe deny 'claude-bg logs 4b04dbe6 | tail' 'next to another command'
check d45-bg-env-assign deny 'CLAUDE_CONFIG_DIR=/x claude-bg logs 4b04dbe6' 'next to another command'
# --- MUST PASS (AC7, AC8) ------------------------------------------------------
check a01-push pass 'git push'
check a02-push-u pass 'git push -u origin feat/x'
check a03-commit-F pass 'git commit -F msg.txt'
check a04-gh-body-file pass 'gh pr create --body-file b.md'
check a05-gh-json pass 'gh pr view 12 --json state'
check a06-fd-dup pass 'git fetch 2>&1'
check a07-grep pass 'grep -rn "git push" .'
check a08-rg pass "rg 'gh pr' file"
check a09-quoted-msg pass 'git commit -m "fix gh thing; git push"'
check a10-status-diff pass 'git status && git diff'
check a11-chain-targets pass 'git commit -F m.txt && git push'
check a13-push-and-pr pass 'git push && gh pr create --body-file b.md'
check a14-blanks pass '  git fetch  '
check a15-echo-mention pass 'echo "use gh pr view"'
check a16-which-gh pass 'which gh'
check a17-push-dup-dash pass 'git push origin feat/x 2>&1'
check a18-brew-gh pass 'brew upgrade gh'
check a19-log-grep pass 'git log --grep="git push"'
check a20-ls-status pass 'ls && git status'
check a21-unbalanced pass 'git push "oops'
check a22-gh-jq pass "gh pr view 3 --json state --jq '.state'"
check a23-continuation pass "$CONT_PUSH"
check a24-no-git pass 'ls -la'
check a27-quoted-heredoc-body pass "$HD_QBODY_SUBST"
check a28-command-v pass 'command -v gh'
check a29-command-V pass 'command -V git'
check a30-dispatch pass 'claude-dispatch fix-a "fix the typo in README.md"'
check a31-dispatch-chain pass 'claude-dispatch fix-a "fix the typo" && claude-dispatch add-b "add the helper"'
check a32-dispatch-mention pass 'grep -rn "claude-dispatch" README.md'
check a33-dispatch-quoted-sep pass 'claude-dispatch fix-a "fix x; then run the tests"'
check a34-bg-status pass 'claude-bg status'
check a35-bg-chain pass 'claude-bg respawn 4b04dbe6 && claude-bg logs 4b04dbe6'
# --- MUST PASS: inputs the hook cannot read (fail open) ----------------------
printf '%s' '{"hook_event_name":"PreToolUse","tool_input":{' > "$WORK/out/malformed.json"
check_raw a12-malformed pass "$WORK/out/malformed.json"
printf '%s' '{}' > "$WORK/out/empty.json"
check_raw a25-empty-object pass "$WORK/out/empty.json"
{
  "$JQ" -cn '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"cd /x && git push"}}'
  head -c 4400000 /dev/zero | tr '\0' ' '
  printf '}garbage'
} > "$WORK/out/oversize.json"
check_raw a26-oversize pass "$WORK/out/oversize.json"
# --- MUST PASS FAST: adversarial shapes --------------------------------------
check f01-push-128k pass-fast "$PUSH128K"
"$JQ" -cn '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:("git push" + ("\n" * 65536))}}' > "$WORK/out/nlflood.json"
NCASES=$((NCASES + 1))
run_raw "$WORK/out/nlflood.json" "$WORK/out/f02.stdout" "$WORK/out/f02.stderr"
grade f02-nl-flood pass-fast "$WORK/out/f02.stdout" "$WORK/out/f02.stderr"

echo "runtime-cases: $NCASES"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
