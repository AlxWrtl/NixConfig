#!/usr/bin/env bash
# Real-lsof control for worktree-in-use.js, the PreToolUse guard that denies
# `git worktree remove` / `rm -r` of a worktree some live process has as cwd.
#
# WHY IT EXISTS. checks/hook-wiring.nix runs the hook in the nix build
# sandbox, which has no /usr/sbin and no process info: there the hook's one
# `const LSOF = "/usr/sbin/lsof";` line is repointed at a fake. Nothing in
# the flake ever runs the REAL lsof, so a wrong flag, a field the real -F
# output does not carry, or a parse of the real record order would pass the
# flake green. This probe runs the body UNMODIFIED, against /usr/sbin/lsof.
#
# CASES, on a throwaway repo with one linked worktree $WT:
#   held-deny    a real `sleep` with cwd $WT; `git worktree remove --force
#                $WT` → exit 0, deny, reason names `pid <sleep pid>` and
#                `sleep`; wall time < 1 s.
#   free-allow   the sleep killed and reaped; the same command → exit 0, no
#                deny, stderr empty; wall time < 1 s.
# Before any case the instrument is checked: real lsof must see the sleep's
# cwd as $WT, or the probe stops (exit 2) instead of grading the hook.
#
# Standalone, NOT wired into `nix flake check`. Run it OUTSIDE the Claude
# sandbox: it runs `git init` / `git worktree add` (writes under `.git/`).
#
# usage: bash checks/worktree-in-use-probe.sh [hook.js]
#        (default: home/claude-code/hooks/worktree-in-use.js)
# exit:  0 every case passes; 1 a case failed; 2 setup error.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SRC="${1:-$REPO_ROOT/home/claude-code/hooks/worktree-in-use.js}"
LSOF=/usr/sbin/lsof
LIT='const LSOF = "/usr/sbin/lsof";'
BUDGET_US=1000000

die() {
  echo "probe: $*" >&2
  exit 2
}

[ -f "$HOOK_SRC" ] || die "missing $HOOK_SRC"
[ "$(grep -cF -- "$LIT" "$HOOK_SRC")" = 1 ] || die "$LIT is not in exactly one line of $HOOK_SRC: the probe would not grade the real lsof"
[ -x "$LSOF" ] || die "$LSOF is not executable"
NODE="$(command -v node)" || die "node not on PATH"
GIT="$(command -v git)" || die "git not on PATH"
JQ="$(command -v jq)" || die "jq not on PATH"
[ -n "${EPOCHREALTIME:-}" ] || die "bash ${BASH_VERSION} has no EPOCHREALTIME (bash >= 5 needed to time the hook)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/worktree-in-use-probe.XXXXXX")" || exit 2
WORK="$(cd "$WORK" && pwd -P)"
SP=""
cleanup() {
  if [ -n "$SP" ]; then kill "$SP" 2>/dev/null; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

g() { GIT_CONFIG_NOSYSTEM=1 HOME="$WORK" "$GIT" -c commit.gpgsign=false -c user.name=p -c user.email=p@p "$@"; }
R="$WORK/repo"
WT="$WORK/wts/held"
mkdir -p "$WORK/wts" || exit 2
g init -q -b master "$R" || die "git init failed (inside the Claude sandbox? run it outside)"
g -C "$R" commit -q --allow-empty -m probe || die "commit failed"
g -C "$R" worktree add -q -b wt-held "$WT" || die "worktree add failed"

(cd "$WT" && exec sleep 300) </dev/null >/dev/null 2>&1 &
SP=$!
seen=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  seen="$("$LSOF" -n -P -w -a -p "$SP" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
  [ "$seen" = "$WT" ] && break
  sleep 0.1
done
[ "$seen" = "$WT" ] || die "instrument: real lsof sees sleep $SP with cwd '$seen', expected '$WT'"

pass=0
failn=0
ok() {
  pass=$((pass + 1))
  echo "ok   $1"
}
ko() {
  failn=$((failn + 1))
  echo "FAIL $1: $2"
}

CMD="git worktree remove --force $WT"
# shellcheck disable=SC2016 # $c and $w are jq variables.
INPUT="$("$JQ" -cn --arg c "$CMD" --arg w "$R" '{hook_event_name:"PreToolUse",session_id:"probe",cwd:$w,tool_name:"Bash",tool_input:{command:$c,description:"probe"}}')"

# Leaves rc, out, err, us (wall time in microseconds).
run_hook() {
  local t0 t1
  t0=${EPOCHREALTIME/./}
  out="$(cd "$R" && printf '%s' "$INPUT" | "$NODE" "$HOOK_SRC" 2>"$WORK/err")"
  rc=$?
  t1=${EPOCHREALTIME/./}
  err="$(cat "$WORK/err")"
  us=$((t1 - t0))
}
decision() { printf '%s' "$out" | "$JQ" -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo unparseable; }
reason() { printf '%s' "$out" | "$JQ" -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }
timed() {
  echo "     $1: hook wall time $((us / 1000)) ms"
  if [ "$us" -lt "$BUDGET_US" ]; then ok "$1-under-1s"; else ko "$1-under-1s" "$((us / 1000)) ms"; fi
}

# held-deny
run_hook
v="$(decision)"
r="$(reason)"
if [ "$rc" -ne 0 ]; then
  ko held-deny "exit $rc, expected 0 (stderr: $err)"
elif [ "$v" != deny ]; then
  ko held-deny "decision '$v', expected deny (stdout: $out; stderr: $err)"
else
  case "$r" in
    *"pid $SP"[!0-9]* | *"pid $SP")
      case "$r" in
        *sleep*) ok held-deny ;;
        *) ko held-deny "reason does not name 'sleep': $r" ;;
      esac
      ;;
    *) ko held-deny "reason does not name 'pid $SP': $r" ;;
  esac
fi
timed held-deny

# free-allow
kill "$SP" 2>/dev/null
wait "$SP" 2>/dev/null
SP=""
run_hook
v="$(decision)"
if [ "$rc" -ne 0 ]; then
  ko free-allow "exit $rc, expected 0 (stderr: $err)"
elif [ "$v" = deny ]; then
  ko free-allow "denied with the holder gone: $(reason)"
elif [ -n "$err" ]; then
  ko free-allow "stderr not empty: $err"
else
  ok free-allow
fi
timed free-allow

echo "=== $pass passed, $failn failed ==="
[ "$failn" -eq 0 ]
