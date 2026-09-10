#!/usr/bin/env bash
# Probe the three Codex lifecycle hooks: does each one exit with the code its
# doctrine demands, on every degraded path, without ever putting junk on stdout?
#
# WHY THIS HARNESS EXISTS. The bug being fixed is a hook that wrote an ANSI
# escape to stdout, which Codex reported as `hook returned invalid stop hook
# JSON output`. Codex parses ANY non-empty stdout as JSON. So "stdout is empty
# or exactly one JSON object, and carries no 0x1b byte" is asserted for EVERY
# case here, not just the ones about output.
#
# WHY THE HOOKS ARE GRADED BY OPPOSITE RULES. protect-main.js and
# block-main-shell.js are security gates: they must FAIL CLOSED, so their
# degraded cases expect exit 2. quality-gate.js is a workflow nudge: it must
# FAIL OPEN, so its degraded cases expect exit 0. Case `pm-malformed-stdin` and
# case `qg-malformed-stdin` are the same input through the two doctrines, and
# they must disagree. If they ever agree, one of the hooks has drifted.
#
# WHY block-main-shell.js IS HERE AT ALL, MEASURED 2026-09-10. protect-main.js
# is registered on `Edit|Write`. In a throwaway repo on master, Codex changed a
# file with `perl -0pi -e 's/1/2/g' note.txt` — a shell command, so the matcher
# never selected the hook and the file changed on master with the configuration
# looking correct. `bs-perl-inplace-master` below IS that command, byte for
# byte, and it is the case this whole section exists for.
#
# WHY THE HANGING-GIT CASE ASSERTS A CLOCK. Codex registers the hook with
# `timeout: 5`, and the vendor documentation does not say what a hook killed by
# the host does. Assume the worst — that its death is read as "did not block".
# The hook must therefore refuse ITSELF first. `pm-git-hangs` feeds it a `git`
# that sleeps 30 seconds and asserts exit 2 in under 4 seconds. An assertion on
# the exit code alone would pass on a hook with no watchdog at all, 30 seconds
# later, in a world where the host had already killed it.
#
# WHY FIXTURE REPOS AND NEVER THIS ONE. Every answer here depends on the branch
# and the diff. Run against this repository they would depend on whatever is
# checked out at the time.
#
# THE MONEY GUARD. Nothing here invokes `codex`, and the harness proves that by
# refusing to run at all if a real `codex` is reachable from the PATH the cases
# run under. A test that can accidentally bill the user is not a test.
#
# Standalone, like checks/scrapling-shim-fuzz.sh and
# checks/apex-verify-external-probe.sh: NOT wired into `nix flake check`,
# because it drives scripts that nix installs elsewhere.
#
# usage: codex-hooks-probe.sh [protect-main.js] [quality-gate.js] [block-main-shell.js]
#        All three default to the repo copies, and positions 1 and 2 keep the
#        meaning they have always had. Pass a mutated copy in any position to
#        prove the harness can go red.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT_PM="${1:-$REPO_ROOT/home/codex/scripts/protect-main.js}"
SUT_QG="${2:-$REPO_ROOT/home/codex/scripts/quality-gate.js}"
SUT_BS="${3:-$REPO_ROOT/home/codex/scripts/block-main-shell.js}"

# Absolute, always. Every case runs after a `cd` into its fixture, so a script
# passed as a RELATIVE path resolves against the fixture and every case for it
# dies with a module-loader error — measured while proving the suite could go
# red: a mutant handed as `home/codex/scripts/...` took the two untouched hooks
# down with it and buried the one real finding in 28 fake ones.
abspath() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s\n' "$PWD/$1" ;; esac; }
SUT_PM="$(abspath "$SUT_PM")"
SUT_QG="$(abspath "$SUT_QG")"
SUT_BS="$(abspath "$SUT_BS")"

for s in "$SUT_PM" "$SUT_QG" "$SUT_BS"; do
  [ -f "$s" ] && [ -r "$s" ] || {
    echo "probe: script under test not found or not readable: $s" >&2
    exit 2
  }
done

# --- work directory -----------------------------------------------------------
#
# An empty $WORK must STOP the run. The fuzz harness this copies once let a
# failed `mktemp -d` through: every path resolved to the filesystem root and it
# reported 44 failures that were all its own.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/codex-hooks-probe.XXXXXX") || {
  echo "probe: cannot create a work directory under ${TMPDIR:-/tmp}" >&2
  exit 2
}
if [ -z "${WORK:-}" ] || [ ! -d "$WORK" ]; then
  echo "probe: work directory is empty or missing — refusing to run" >&2
  exit 2
fi
trap 'if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then chmod -R u+w "$WORK" 2>/dev/null || true; rm -rf "$WORK"; fi' EXIT

# Never grade this repository by accident.
case "$WORK/" in
  "$REPO_ROOT"/*)
    echo "probe: the work directory is inside this repository — refusing to run" >&2
    exit 2
    ;;
esac

# --- hermetic PATH ------------------------------------------------------------
resolve_dir() { # resolve_dir <tool> [glob...]
  local tool="$1"
  shift
  local p g
  if p="$(command -v "$tool" 2>/dev/null)"; then
    dirname "$p"
    return 0
  fi
  for g in "$@"; do
    for p in $g; do
      [ -x "$p" ] && {
        dirname "$p"
        return 0
      }
    done
  done
  return 1
}

GIT_BIN_DIR="$(resolve_dir git)" || {
  echo "probe: git not found" >&2
  exit 2
}
JQ_BIN_DIR="$(resolve_dir jq)" || {
  echo "probe: jq not found — the stdout assertions need it" >&2
  exit 2
}
NODE="$(command -v node 2>/dev/null || true)"
[ -n "$NODE" ] || NODE=/run/current-system/sw/bin/node
[ -x "$NODE" ] || {
  echo "probe: no usable node interpreter (tried \$PATH and /run/current-system/sw/bin/node)" >&2
  exit 2
}
NODE_BIN_DIR="$(dirname "$NODE")"
BASE_PATH="$NODE_BIN_DIR:$GIT_BIN_DIR:$JQ_BIN_DIR:/usr/bin:/bin"

# THE MONEY GUARD. No case invokes codex; this proves none can.
if PATH="$BASE_PATH" command -v codex >/dev/null 2>&1; then
  echo "probe: a real \`codex\` is reachable from the harness PATH — refusing to run" >&2
  echo "probe: found at $(PATH="$BASE_PATH" command -v codex)" >&2
  exit 2
fi

# Hermetic git: the user's global and system config must not decide anything.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export HOME="$WORK/home"
mkdir -p "$HOME" "$WORK/out"

git_q() {
  PATH="$BASE_PATH" git -c user.email=probe@local -c user.name=probe \
    -c commit.gpgsign=false -c advice.detachedHead=false "$@"
}

# --- stub PATHs ---------------------------------------------------------------

NOGIT_DIR="$WORK/path-without-git"
SLOWGIT_DIR="$WORK/path-with-slow-git"
mkdir -p "$NOGIT_DIR" "$SLOWGIT_DIR"

# A `git` that never answers. Not a `git` that fails — a failure is easy to
# detect, a hang is the one the host resolves by killing the hook.
cat > "$SLOWGIT_DIR/git" << 'STUB'
#!/bin/sh
sleep 30
STUB
chmod +x "$SLOWGIT_DIR/git"

# TRIPWIRES: prove the two stub PATHs really are what they claim, before any
# case leans on them.
if [ "$(PATH="$SLOWGIT_DIR:$BASE_PATH" command -v git)" != "$SLOWGIT_DIR/git" ]; then
  echo "probe: \`git\` does not resolve to the sleeping stub — refusing to report" >&2
  exit 2
fi
if PATH="$NOGIT_DIR" command -v git > /dev/null 2>&1; then
  echo "probe: \`git\` is still reachable on the git-less PATH — refusing to report" >&2
  exit 2
fi

# --- fixtures -----------------------------------------------------------------

new_repo() { # new_repo <dir> <branch>
  mkdir -p "$1/src"
  (
    cd "$1"
    git_q -c init.defaultBranch="$2" init -q .
    printf 'export const a = 1;\n' > src/app.ts
    git_q add -A
    git_q commit -qm base
  ) > /dev/null 2>&1
}

FIX_MAIN="$WORK/repo-main"
new_repo "$FIX_MAIN" main

FIX_FEAT="$WORK/repo-feature"
new_repo "$FIX_FEAT" main
(cd "$FIX_FEAT" && git_q checkout -q -b feat/probe) > /dev/null 2>&1

# `master`, not just `main`. Measured 2026-09-10: with only a `main` fixture,
# dropping "master" from the hook's protected list left this suite fully green —
# 18 of 18 — and master is the default branch of the repository this hook was
# written to protect. Two names are guarded, so both need a case.
FIX_MASTER="$WORK/repo-master"
new_repo "$FIX_MASTER" master

# A `master` repo WITH a remote. block-main-shell.js ports the Claude side's
# vault carve-out — a repo with NO remote cannot receive a PR, so a command
# that only moves a git ref is allowed there — and NARROWS it to ref moves
# only. Two fixtures are therefore needed to grade it: this one, where
# `git commit` must be refused, and $FIX_MASTER (remote-less), where the same
# command must pass while `perl -0pi` and `git checkout --` must not.
FIX_REMOTE="$WORK/repo-master-remote"
new_repo "$FIX_REMOTE" master
(cd "$FIX_REMOTE" && git_q remote add origin https://example.invalid/probe.git) > /dev/null 2>&1

# PRECONDITION for the carve-out pair: one fixture has a remote, the other does
# not. Both cases pass by accident if this ever stops being true.
if [ -n "$( (cd "$FIX_MASTER" && PATH="$BASE_PATH" git remote) 2> /dev/null)" ]; then
  echo "probe: \$FIX_MASTER has a remote — the no-remote carve-out cases would be meaningless" >&2
  exit 2
fi
if [ -z "$( (cd "$FIX_REMOTE" && PATH="$BASE_PATH" git remote) 2> /dev/null)" ]; then
  echo "probe: \$FIX_REMOTE has no remote — the carve-out would swallow its cases" >&2
  exit 2
fi

FIX_CLEAN="$WORK/repo-qg-clean"
new_repo "$FIX_CLEAN" main

FIX_DIRTY="$WORK/repo-qg-dirty"
new_repo "$FIX_DIRTY" main
printf 'export const a = 1;\nconsole.log(a);\n' > "$FIX_DIRTY/src/app.ts"

FIX_SCRIPTS="$WORK/repo-qg-scripts"
new_repo "$FIX_SCRIPTS" main
(
  cd "$FIX_SCRIPTS"
  mkdir -p scripts
  printf 'export const b = 2;\n' > scripts/tool.ts
  git_q add -A
  git_q commit -qm scripts
) > /dev/null 2>&1
printf 'export const b = 2;\nconsole.log(b);\n' > "$FIX_SCRIPTS/scripts/tool.ts"

FIX_DTS="$WORK/repo-qg-dts"
new_repo "$FIX_DTS" main
(
  cd "$FIX_DTS"
  printf 'export declare const c: number;\n' > src/gen.d.ts
  git_q add -A
  git_q commit -qm dts
) > /dev/null 2>&1
printf 'export declare const c: number;\nconsole.log(c);\n' > "$FIX_DTS/src/gen.d.ts"

# Not a repository, and the process working directory for the chdir case.
NOT_REPO="$WORK/not-a-repo"
ELSEWHERE="$WORK/elsewhere"
OUTSIDE="$WORK/outside"
mkdir -p "$NOT_REPO" "$ELSEWHERE" "$OUTSIDE"
printf 'plain\n' > "$OUTSIDE/plain.txt"
# A path that LOOKS outside the worktree and resolves inside it. A prefix test
# on the unresolved string says "elsewhere" and lets the edit through.
ln -s "$FIX_MAIN/src/app.ts" "$OUTSIDE/link.ts"

# PRECONDITION: the neutral directories must really not be inside any git
# repository, or four cases would be graded by this machine's layout.
for d in "$NOT_REPO" "$ELSEWHERE" "$OUTSIDE"; do
  if (cd "$d" && PATH="$BASE_PATH" git rev-parse --is-inside-work-tree) > /dev/null 2>&1; then
    echo "probe: $d is inside a git repository — refusing to report" >&2
    exit 2
  fi
done

# --- payloads -----------------------------------------------------------------

pay() { # pay <name> <content>
  printf '%s' "$2" > "$WORK/pay-$1.json"
  printf '%s\n' "$WORK/pay-$1.json"
}

P_INSIDE=$(pay inside "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"cwd\":\"$FIX_MAIN\",\"tool_input\":{\"file_path\":\"$FIX_MAIN/src/app.ts\"}}")
P_FEAT=$(pay feat "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"cwd\":\"$FIX_FEAT\",\"tool_input\":{\"file_path\":\"$FIX_FEAT/src/app.ts\"}}")
P_MASTER=$(pay master "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"cwd\":\"$FIX_MASTER\",\"tool_input\":{\"file_path\":\"$FIX_MASTER/src/app.ts\"}}")
P_OUTSIDE=$(pay outside "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"cwd\":\"$FIX_MAIN\",\"tool_input\":{\"file_path\":\"$OUTSIDE/plain.txt\"}}")
P_SYMLINK=$(pay symlink "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Edit\",\"cwd\":\"$FIX_MAIN\",\"tool_input\":{\"file_path\":\"$OUTSIDE/link.ts\"}}")
P_NOTREPO=$(pay notrepo "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"cwd\":\"$NOT_REPO\",\"tool_input\":{\"file_path\":\"$NOT_REPO/x.ts\"}}")
P_NOPATH=$(pay nopath '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"content":"x"}}')
P_BROKEN=$(pay broken '{"hook_event_name":"PreToolUse","tool_input":{')

# --- shell payloads -----------------------------------------------------------
#
# `tool_name` is written as "shell" here, but NOTHING in this file depends on
# it: the real name is not established (the binary carries `shell`,
# `local_shell` and `bash`), the matcher in hooks.nix names all three, and the
# hook itself keys on the command field, never on the tool name. A probe that
# asserted a tool name would be asserting a guess.
sh_payload() { # sh_payload <name> <cwd> <json-command-value>
  pay "$1" "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"shell\",\"cwd\":\"$2\",\"tool_input\":{\"command\":$3}}"
}

# THE CASE THIS HOOK EXISTS FOR: the exact command that changed a file on
# master while protect-main.js watched Edit|Write and never ran.
S_PERL=$(sh_payload sh-perl "$FIX_MASTER" "\"perl -0pi -e 's/1/2/g' note.txt\"")
S_PERL_FEAT=$(sh_payload sh-perl-feat "$FIX_FEAT" "\"perl -0pi -e 's/1/2/g' note.txt\"")
S_PERL_NOREPO=$(sh_payload sh-perl-norepo "$NOT_REPO" "\"perl -0pi -e 's/1/2/g' note.txt\"")
# The argv form: a `local_shell`-shaped tool is likelier to pass a list than a
# string, and a hook that only understands strings would read "no command" and,
# fail-closed or not, would be blind to what it is being asked to allow.
S_PERL_ARGV=$(sh_payload sh-perl-argv "$FIX_MASTER" "[\"bash\",\"-lc\",\"perl -0pi -e 's/1/2/g' note.txt\"]")
S_REDIRECT=$(sh_payload sh-redirect "$FIX_MASTER" "\"echo broken > src/app.ts\"")
S_SED=$(sh_payload sh-sed "$FIX_MASTER" "\"sed -i '' 's/1/2/' src/app.ts\"")
S_TEE=$(sh_payload sh-tee "$FIX_MASTER" "\"echo x | tee src/app.ts\"")
S_RM=$(sh_payload sh-rm "$FIX_MASTER" "\"rm -f src/app.ts\"")
S_CHECKOUT=$(sh_payload sh-checkout "$FIX_MASTER" "\"git checkout -- .\"")
S_COMMIT_REMOTE=$(sh_payload sh-commit-remote "$FIX_REMOTE" "\"git commit -am wip\"")
S_COMMIT_LOCAL=$(sh_payload sh-commit-local "$FIX_MASTER" "\"git commit -am wip\"")
# Read-only, on master, must stay allowed — a branch nothing may run on is a
# branch its owner turns the guard off for. The second one also pins the
# /dev/null carve-out: `> /dev/null 2>&1` is a redirection and must not count.
S_STATUS=$(sh_payload sh-status "$FIX_MASTER" "\"git status --short\"")
S_LS=$(sh_payload sh-ls "$FIX_MASTER" "\"ls -la > /dev/null 2>&1\"")
S_NOCMD=$(pay sh-nocmd "{\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"shell\",\"cwd\":\"$FIX_MASTER\",\"tool_input\":{\"description\":\"list files\"}}")

qg_payload() { # qg_payload <name> <cwd> <stop_hook_active>
  pay "$1" "{\"hook_event_name\":\"Stop\",\"cwd\":\"$2\",\"stop_hook_active\":$3,\"session_id\":\"probe\",\"transcript_path\":\"/dev/null\",\"model\":\"stub\",\"permission_mode\":\"default\",\"turn_id\":\"t1\",\"last_assistant_message\":\"done\"}"
}
Q_CLEAN=$(qg_payload qg-clean "$FIX_CLEAN" false)
Q_DIRTY=$(qg_payload qg-dirty "$FIX_DIRTY" false)
Q_LOOP=$(qg_payload qg-loop "$FIX_DIRTY" true)
Q_SCRIPTS=$(qg_payload qg-scripts "$FIX_SCRIPTS" false)
Q_DTS=$(qg_payload qg-dts "$FIX_DTS" false)

# --- runner -------------------------------------------------------------------

PASS=0
FAIL=0
CASE_STATUS=0
CASE_MS=0
OUT_F=""
ERR_F=""

fail_case() {
  FAIL=$((FAIL + 1))
  printf 'FAIL  %-22s %s\n' "$1" "$2"
}
ok_case() {
  PASS=$((PASS + 1))
  printf 'ok    %-22s %s\n' "$1" "$2"
}

# Millisecond clock. $EPOCHREALTIME is bash 5; older shells fall back to whole
# seconds, which is still enough to separate 1.6 s from 30 s.
now_ms() {
  local t="${EPOCHREALTIME:-}"
  t="${t/,/.}"
  case "$t" in
    *.*) printf '%s%s\n' "${t%%.*}" "$(printf '%-3.3s' "${t#*.}" | tr ' ' '0')" ;;
    *) printf '%s000\n' "$(date +%s)" ;;
  esac
}

# Codex reads ANY non-empty stdout as JSON. Prints a reason, or nothing.
stdout_problem() { # stdout_problem <file>
  local f="$1" esc
  # Count the 0x1b bytes by deleting everything that is not one. Byte-exact and
  # binary-safe; a grep on a file with high bytes would report "Binary file
  # matches" and decide nothing.
  esc=$(LC_ALL=C tr -dc '\033' < "$f" | wc -c | tr -d ' ')
  if [ "$esc" != "0" ]; then
    printf 'stdout carries %s ESC (0x1b) byte(s)' "$esc"
    return 0
  fi
  if [ -s "$f" ]; then
    if ! PATH="$BASE_PATH" jq -e -s 'length == 1 and (.[0] | type) == "object"' "$f" > /dev/null 2>&1; then
      printf 'stdout is not exactly one JSON object: %s' "$(head -c 160 "$f")"
      return 0
    fi
  fi
  return 0
}

run_case() { # run_case <label> <script> <cwd> <pathspec> <payload>
  OUT_F="$WORK/out/$1.stdout"
  ERR_F="$WORK/out/$1.stderr"
  : > "$OUT_F"
  : > "$ERR_F"
  local t0 t1
  t0=$(now_ms)
  set +e
  (cd "$3" && PATH="$4" exec "$NODE" "$2") < "$5" > "$OUT_F" 2> "$ERR_F"
  CASE_STATUS=$?
  set -e
  t1=$(now_ms)
  CASE_MS=$((t1 - t0))
}

echo "=== codex hooks probe (offline; no codex binary is reachable) ==="
echo "    protect-main:     $SUT_PM"
echo "    quality-gate:     $SUT_QG"
echo "    block-main-shell: $SUT_BS"
echo

# label | script | cwd | pathkey | payload | want-exit | jq-filter | stderr-regex | max-seconds
while IFS='|' read -r label script wd pathkey payload want filt stderr_re maxsec; do
  case "$label" in '' | '#'*) continue ;; esac

  case "$script" in
    pm) sut="$SUT_PM" ;;
    qg) sut="$SUT_QG" ;;
    bs) sut="$SUT_BS" ;;
    *)
      fail_case "$label" "unknown script column: $script"
      continue
      ;;
  esac
  case "$pathkey" in
    base) ps="$BASE_PATH" ;;
    nogit) ps="$NOGIT_DIR" ;;
    slowgit) ps="$SLOWGIT_DIR:$BASE_PATH" ;;
    *)
      fail_case "$label" "unknown path column: $pathkey"
      continue
      ;;
  esac

  run_case "$label" "$sut" "$wd" "$ps" "$payload"

  why=""
  if [ "$CASE_STATUS" != "$want" ]; then
    why="exit: expected $want, got $CASE_STATUS (stderr: $(head -c 160 "$ERR_F"))"
  fi
  # Universal, every case: AC7.
  if [ -z "$why" ]; then
    p="$(stdout_problem "$OUT_F")"
    if [ -n "$p" ]; then why="$p"; fi
  fi
  # Success means silence. Anything on stdout at exit 0 is a hook with an
  # opinion it failed to declare.
  if [ -z "$why" ] && [ "$want" = "0" ] && [ -s "$OUT_F" ]; then
    why="stdout: expected empty at exit 0, got $(head -c 160 "$OUT_F")"
  fi
  # A block with nothing on stderr is a block the user cannot act on.
  if [ -z "$why" ] && [ "$want" != "0" ] && [ ! -s "$ERR_F" ]; then
    why="stderr: a block must carry a reason, stderr was empty"
  fi
  if [ -z "$why" ] && [ -n "$filt" ] && [ "$filt" != "-" ]; then
    if ! PATH="$BASE_PATH" jq -e "$filt" "$OUT_F" > /dev/null 2>&1; then
      why="stdout json: [$filt] is false; got $(head -c 200 "$OUT_F")"
    fi
  fi
  if [ -z "$why" ] && [ -n "$stderr_re" ] && [ "$stderr_re" != "-" ]; then
    if ! grep -qE -- "$stderr_re" "$ERR_F"; then
      why="stderr: expected /$stderr_re/, got $(head -c 200 "$ERR_F")"
    fi
  fi
  if [ -z "$why" ] && [ -n "$maxsec" ] && [ "$maxsec" != "-" ]; then
    if [ "$CASE_MS" -ge $((maxsec * 1000)) ]; then
      why="elapsed ${CASE_MS}ms — the watchdog did not fire before ${maxsec}s"
    fi
  fi

  if [ -n "$why" ]; then
    fail_case "$label" "${why} [${CASE_MS}ms]"
  else
    ok_case "$label" "exit $CASE_STATUS, ${CASE_MS}ms"
  fi
done << TABLE
# --- protect-main.js: SECURITY, fails CLOSED ---------------------------------
pm-main-inside|pm|$FIX_MAIN|base|$P_INSIDE|2|.hookSpecificOutput.permissionDecision == "deny"|BLOCKED: on main|
pm-master-inside|pm|$FIX_MASTER|base|$P_MASTER|2|.hookSpecificOutput.permissionDecision == "deny"|BLOCKED: on master|
pm-feature-branch|pm|$FIX_FEAT|base|$P_FEAT|0|-|-|
pm-outside-worktree|pm|$FIX_MAIN|base|$P_OUTSIDE|0|-|-|
pm-not-a-repo|pm|$NOT_REPO|base|$P_NOTREPO|0|-|-|
pm-malformed-stdin|pm|$FIX_MAIN|base|$P_BROKEN|2|.hookSpecificOutput.permissionDecision == "deny"|-|
pm-missing-path|pm|$FIX_MAIN|base|$P_NOPATH|2|.hookSpecificOutput.permissionDecision == "deny"|-|
pm-no-git-on-path|pm|$FIX_MAIN|nogit|$P_INSIDE|2|.hookSpecificOutput.permissionDecision == "deny"|-|
pm-symlink-into-tree|pm|$FIX_MAIN|base|$P_SYMLINK|2|.hookSpecificOutput.permissionDecision == "deny"|-|
pm-git-hangs|pm|$FIX_MAIN|slowgit|$P_INSIDE|2|.hookSpecificOutput.permissionDecision == "deny"|-|4
# --- block-main-shell.js: SECURITY, fails CLOSED ------------------------------
# The named case first: the command that got through, byte for byte.
bs-perl-inplace-master|bs|$FIX_MASTER|base|$S_PERL|2|.hookSpecificOutput.permissionDecision == "deny"|BLOCKED: on master|
bs-perl-argv-array|bs|$FIX_MASTER|base|$S_PERL_ARGV|2|.hookSpecificOutput.permissionDecision == "deny"|BLOCKED: on master|
bs-redirect-master|bs|$FIX_MASTER|base|$S_REDIRECT|2|.hookSpecificOutput.permissionDecision == "deny"|fs-redirect|
bs-sed-inplace-master|bs|$FIX_MASTER|base|$S_SED|2|.hookSpecificOutput.permissionDecision == "deny"|fs-inplace-edit|
bs-tee-master|bs|$FIX_MASTER|base|$S_TEE|2|.hookSpecificOutput.permissionDecision == "deny"|fs-writer-command|
bs-rm-master|bs|$FIX_MASTER|base|$S_RM|2|.hookSpecificOutput.permissionDecision == "deny"|fs-writer-command|
bs-checkout-paths-master|bs|$FIX_MASTER|base|$S_CHECKOUT|2|.hookSpecificOutput.permissionDecision == "deny"|worktree-checkout-paths|
bs-commit-with-remote|bs|$FIX_REMOTE|base|$S_COMMIT_REMOTE|2|.hookSpecificOutput.permissionDecision == "deny"|BLOCKED: on master|
bs-commit-no-remote|bs|$FIX_MASTER|base|$S_COMMIT_LOCAL|0|-|-|
bs-readonly-git-status|bs|$FIX_MASTER|base|$S_STATUS|0|-|-|
bs-readonly-ls-devnull|bs|$FIX_MASTER|base|$S_LS|0|-|-|
bs-feature-branch|bs|$FIX_FEAT|base|$S_PERL_FEAT|0|-|-|
bs-not-a-repo|bs|$NOT_REPO|base|$S_PERL_NOREPO|0|-|-|
bs-malformed-stdin|bs|$FIX_MASTER|base|$P_BROKEN|2|.hookSpecificOutput.permissionDecision == "deny"|-|
bs-missing-command|bs|$FIX_MASTER|base|$S_NOCMD|2|.hookSpecificOutput.permissionDecision == "deny"|-|
bs-no-git-on-path|bs|$FIX_MASTER|nogit|$S_PERL|2|.hookSpecificOutput.permissionDecision == "deny"|-|
bs-git-hangs|bs|$FIX_MASTER|slowgit|$S_PERL|2|.hookSpecificOutput.permissionDecision == "deny"|-|4
# --- quality-gate.js: WORKFLOW, fails OPEN -----------------------------------
qg-clean-repo|qg|$FIX_CLEAN|base|$Q_CLEAN|0|-|-|
qg-debug-print|qg|$FIX_DIRTY|base|$Q_DIRTY|2|.decision == "block"|src/app\.ts:2|
qg-loop-guard|qg|$FIX_DIRTY|base|$Q_LOOP|0|-|-|
qg-cwd-from-stdin|qg|$ELSEWHERE|base|$Q_DIRTY|2|.decision == "block"|src/app\.ts:2|
qg-scripts-excluded|qg|$FIX_SCRIPTS|base|$Q_SCRIPTS|0|-|-|
qg-dts-excluded|qg|$FIX_DTS|base|$Q_DTS|0|-|-|
qg-malformed-stdin|qg|$FIX_DIRTY|base|$P_BROKEN|0|-|-|
TABLE

# --- the doctrinal mirror -----------------------------------------------------
#
# The same malformed input must be refused by the security hook and waved
# through by the workflow hook. Asserted here as one statement so a drift that
# makes both agree cannot hide behind two independently green cases.
if [ -s "$WORK/out/pm-malformed-stdin.stdout" ] && [ ! -s "$WORK/out/qg-malformed-stdin.stdout" ]; then
  ok_case doctrine-mirror "same bad input: security denies, workflow yields"
else
  fail_case doctrine-mirror "the two hooks did not disagree on malformed stdin"
fi

# --- final guard --------------------------------------------------------------
if PATH="$BASE_PATH" command -v codex > /dev/null 2>&1; then
  fail_case real-binary "a real codex became reachable during the run"
else
  ok_case real-binary "never on the harness PATH"
fi

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
