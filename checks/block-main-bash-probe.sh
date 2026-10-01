#!/usr/bin/env bash
# Positive control for `hookBlockMainBash` — the PreToolUse hook that keeps
# commits, pushes and ref moves off master/main.
#
# WHAT IT GRADES. Above all the push-destination predicate
# (`pushTargetsProtectedRef`): a push whose DESTINATION names master/main is
# denied from ANY branch, in any repo, with or without a remote. The
# current-branch rule it sits in front of is graded for non-regression (AC6):
# a push from master is still denied, and a commit on a remote-less master is
# DENIED — only the vault is exempt (user decision 2026-09-30, run 61).
#
# EVERY REPO THE COMMAND WRITES TO (run 61, B1/B2). The branch rule reads
# each directory a command may target, not only the first `-C`/`cd`: `-c k=v`
# before `-C`, a second `cd`, `--git-dir=`, `GIT_DIR=`, a computed `cd "$R"`,
# a subshell and `pushd` all deny from a feature cwd, and `git pull` on master
# denies. Their partners (`cd <feature> &&` from master, a single `-C
# <feature>`, a missing `cd` target, the vault) must PASS.
#
# EVERY RULE IN BOTH POLARITIES. A guard that denies every push scores green
# on every P case, so each widening has partners that must PASS: `master-foo`,
# `mainline` and `feat/master` are other branches, `git log master` and
# `git fetch origin master` push nothing, and text that merely MENTIONS a push
# (a quoted commit message, a quoted-delimiter heredoc) is inert.
#
# PASS IS ASSERTED ON EMPTINESS. A pass case asserts that stdout is empty byte
# for byte, never that some word is absent from it: a hook that crashed before
# printing anything would pass an absence test just as well.
#
# THE REAL CONDITIONS, BUILT IN $WORK. The hook reads the target repo's
# branch and remotes, so the probe makes five cwd's: FEAT (feat/probe, with a
# remote), MASTER (master, with a remote), LOCAL (master, no remote), VAULT
# (main, no remote — the path baked into the hook as `alxVaultPath`) and
# NOREPO (outside any work tree). No commit is ever made: the branch is set by
# `git init --initial-branch`, so no signing key or identity is needed.
#
# The vault path is baked at extraction, so the v-cases run only when THIS
# run extracted the hook; against a given hook.js (and so in every mutant
# child) they print `skip` — never silently absent.
#
# EVERY RUN IS BOUNDED. The hook runs under a 10 s alarm; the `pass-fast` case
# (128 KB of `git push ` with no separator) bounds the run at 1000 ms. The
# destination scan must stay LINEAR: the old lazy single-regex scan restarted
# at every `git push` and was quadratic there — mutant m6 puts it back, and
# pass-fast is the case that must catch it (13 KB did not).
#
# KNOWN GAP, asserted as DENY so it cannot be mistaken for coverage:
# `k1-env-commit-msg` — an EXECUTOR word (`env`) keeps the raw string, so a
# commit message that mentions `git push origin master` is denied. Fail-closed,
# accepted.
#
# WHY THE MUTANTS ARE PART OF THE FILE. A test you have only ever seen pass has
# not been run. Each mutant is a literal text substitution on the REAL hook
# body, and must go red on EXACTLY its declared set:
#
#   m1  the push-destination deny neutralised (`if (false)`).
#   m2  the whole-word lookahead after master/main removed.
#   m3  the `refs/heads/` / `heads/` destination prefix removed.
#   m4  quotes and backtick dropped from the word end (`bash -c "git push
#       origin master"` escapes again).
#   m5  `<` `>` dropped from the word end (`git push origin master>/dev/null`
#       escapes again).
#   m6  the linear two-pass scan replaced by the old lazy single regex
#       (same verdicts, quadratic time: only pass-fast may go red).
#   m7  the `\` + newline fold removed (a continued push escapes again).
#
# THE EXACT COMMANDS THAT MAKE THIS PROBE GO RED:
#
#   bash checks/block-main-bash-probe.sh --mutants        # all of them, graded
#   bash checks/block-main-bash-probe.sh --mutant m2      # one, raw red output
#   bash checks/block-main-bash-probe.sh old-hook.js      # e.g. HEAD's version
#
# Standalone, like checks/require-apex-probe.sh: NOT wired into
# `nix flake check`, because it shells out to `nix eval` to lift the hook body
# out of hooks.nix, and builds git repos a sandboxed check build does not
# provide.
#
# usage: block-main-bash-probe.sh [hook.js]
#        block-main-bash-probe.sh --mutants
#        block-main-bash-probe.sh --mutant m1..m7

# SC2034: the MN_EXPECT sets are read through ${!v}. SC2016: perl and jq
# programs are single-quoted on purpose. SC2018/19: mutant ids are ASCII.
# shellcheck disable=SC2016,SC2018,SC2019,SC2034

set -euo pipefail

# Timing reads $EPOCHREALTIME, which bash grew in 5.0. macOS's /bin/bash is
# 3.2: there it is unset, and every duration would silently read as 0.
if [ -z "${EPOCHREALTIME:-}" ]; then
  echo "probe: bash >= 5 required (\$EPOCHREALTIME is unset in ${BASH_VERSION:-this shell})" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$REPO_ROOT/checks/$(basename "${BASH_SOURCE[0]}")"

ALL_MUTANTS="m1 m2 m3 m4 m5 m6 m7"

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

# --- work directory -----------------------------------------------------------
#
# An empty $WORK must STOP the run: every path would resolve to the filesystem
# root and the failures reported would all be the harness's own.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/block-main-bash-probe.XXXXXX") || {
  echo "probe: cannot create a work directory under ${TMPDIR:-/tmp}" >&2
  exit 2
}
if [ -z "${WORK:-}" ] || [ ! -d "$WORK" ]; then
  echo "probe: work directory is empty or missing — refusing to run" >&2
  exit 2
fi
cleanup() {
  if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then
    chmod -R u+w "$WORK" 2> /dev/null || true
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

# Never write into, or grade, this repository by accident — and never let the
# fixture repos sit inside another work tree, or `git rev-parse` answers for it.
case "$WORK/" in
  "$REPO_ROOT"/*)
    echo "probe: the work directory is inside this repository — refusing to run" >&2
    exit 2
    ;;
esac

mkdir -p "$WORK/out"

# --- interpreters -------------------------------------------------------------

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
GIT="$(command -v git 2> /dev/null || true)"
[ -n "$GIT" ] || {
  echo "probe: git not found — the fixture repos need it" >&2
  exit 2
}
# perl carries the run alarm (`alarm` survives the exec into node) and the
# literal text substitutions that build the mutants.
PERL="$(command -v perl 2> /dev/null || true)"
[ -n "$PERL" ] || {
  echo "probe: perl not found — the run alarm and the mutant builder need it" >&2
  exit 2
}

# --- the script under test ----------------------------------------------------

HOOKS_NIX="$REPO_ROOT/home/claude-code/hooks.nix"
[ -r "$HOOKS_NIX" ] || {
  echo "probe: cannot read $HOOKS_NIX" >&2
  exit 2
}

extract_hook() { # extract_hook <destination>
  local dest="$1" nix
  nix="$(command -v nix 2> /dev/null || true)"
  [ -n "$nix" ] || {
    echo "probe: \`nix\` not found and no hook path was given — nothing to grade" >&2
    exit 2
  }
  "$nix" eval --raw --impure --expr \
    "(import \"$HOOKS_NIX\" { graphifyReindexPkg = \"/nix/store/x\"; vaultSnapshotPkg = \"/nix/store/y\"; alxVaultPath = \"$WORK/vault\"; }).hookBlockMainBash" \
    > "$dest" 2> "$WORK/extract.err" || {
    echo "probe: extracting hookBlockMainBash from hooks.nix failed" >&2
    head -c 800 "$WORK/extract.err" >&2
    exit 2
  }
  [ -s "$dest" ] || {
    echo "probe: the extracted hook body is empty — refusing to report" >&2
    exit 2
  }
}

ORIG="$WORK/block-main-bash.js"
# 1 only when this run baked "$WORK/vault" into the hook it grades.
VAULT_BAKED=0
if [ -n "$SUT" ]; then
  SUT="$(abspath "$SUT")"
  [ -f "$SUT" ] && [ -r "$SUT" ] || {
    echo "probe: script under test not found or not readable: $SUT" >&2
    exit 2
  }
else
  extract_hook "$ORIG"
  SUT="$ORIG"
  VAULT_BAKED=1
fi

# ==============================================================================
# MUTANT DRIVER
# ==============================================================================
#
# Each mutant is a LITERAL substitution (no regex in the pattern) on the REAL
# hook body, written into $WORK, proven to have applied, proven to differ from
# the original, syntax-checked, then graded by re-running this same script
# against it. Nothing is ever written into the repository.

M1_EXPECT="k1-env-commit-msg p01-origin-master p01-no-repo p02-origin-main p03-head-colon-master p04-refs-heads-master p05-force-plus-head-main p06-set-upstream-master p07-delete-master p08-heads-main p09-quoted-master p10-git-C-push p11-chained-push p12-two-refspecs p13-bash-c-push p14-redirect-glued p15-head-colon-redirect p16-line-continuation"
M2_EXPECT="n03-master-foo n10-mainline"
M3_EXPECT="p04-refs-heads-master p08-heads-main"
M4_EXPECT="k1-env-commit-msg p13-bash-c-push"
M5_EXPECT="p14-redirect-glued p15-head-colon-redirect"
M6_EXPECT="push-128k-fast"
M7_EXPECT="p16-line-continuation"

mutant_expect() { # mutant_expect <mN>
  local v
  v="$(printf '%s' "$1" | tr 'a-z' 'A-Z')_EXPECT"
  printf '%s\n' "${!v}"
}

# lit_sub <src> <dest> <from> <to> — every occurrence of <from>, literally.
lit_sub() {
  FROM="$3" TO="$4" "$PERL" -pe 's/\Q$ENV{FROM}\E/$ENV{TO}/g' "$1" > "$2"
}

build_mutant() { # build_mutant <mN> <destination>
  local which="$1" dest="$2" from="" to=""
  case "$which" in
    m1) from='if (pushTargetsProtectedRef(cmd))' to='if (false)' ;;
    m2) from='(?:refs\/heads\/|heads\/)?(?:master|main)(?=[\s;&|()<>"'"'"'`]|$)/;' to='(?:refs\/heads\/|heads\/)?(?:master|main)/;' ;;
    m3) from='(?:refs\/heads\/|heads\/)?(?:master|main)(?=' to='(?:master|main)(?=' ;;
    m4) from='(?:master|main)(?=[\s;&|()<>"'"'"'`]|$)/;' to='(?:master|main)(?=[\s;&|()<>]|$)/;' ;;
    m5) from='(?:master|main)(?=[\s;&|()<>"'"'"'`]|$)/;' to='(?:master|main)(?=[\s;&|()"'"'"'`]|$)/;' ;;
    m6) from='const scan = (v) => [...v.matchAll(PUSH_SEG)].some((m) => DST_WORD.test(m[1]));' to='const scan = (v) => new RegExp(src(GIT) + "push" + src(EOW) + "[^;&|\\n()]*?\\s" + src(PROTECTED_DST)).test(v);' ;;
    m7) from='const v = c.replace(/\\\n/g, " ");' to='const v = c;' ;;
  esac
  local n
  n="$(grep -cF -- "$from" "$ORIG" || true)"
  [ "$n" = "1" ] || {
    echo "probe: $which did not apply — expected its text exactly once, found $n (looked for: $from)" >&2
    return 1
  }
  lit_sub "$ORIG" "$dest" "$from" "$to"
  if ! grep -qF -- "$to" "$dest"; then
    echo "probe: $which did not apply — replacement not found (looked for: $to)" >&2
    return 1
  fi
  if cmp -s "$ORIG" "$dest"; then
    echo "probe: $which is byte-identical to the original — a no-op mutant proves nothing" >&2
    return 1
  fi
  "$NODE" --check "$dest" 2> "$WORK/$which.syntax" || {
    echo "probe: $which is not valid JavaScript:" >&2
    head -c 400 "$WORK/$which.syntax" >&2
    return 1
  }
  return 0
}

if [ "$MODE" != "run" ]; then
  [ -f "$ORIG" ] || extract_hook "$ORIG"
  MUT_FAIL=0

  echo "=== block-main-bash mutants (built from the live hook, in $WORK) ==="
  echo

  # Baseline first: grading a mutant against a suite that is not green to
  # begin with would attribute the harness's own failures to the mutation.
  set +e
  BASE_OUT="$("$SELF" "$ORIG" 2>&1)"
  BASE_RC=$?
  set -e
  BASE_RED="$(printf '%s\n' "$BASE_OUT" | awk '/^FAIL /{print $2}' | sort | tr '\n' ' ')"
  RUNTIME_CASES="$(printf '%s\n' "$BASE_OUT" | awk '/^runtime-cases: /{print $2; exit}')"
  if [ "$BASE_RC" -eq 0 ]; then
    echo "baseline: green — $(printf '%s\n' "$BASE_OUT" | grep -E '^=== [0-9]+ passed')"
  else
    echo "baseline: NOT GREEN (rc=$BASE_RC), red on: $BASE_RED"
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
    MOUT="$("$SELF" "$MF" 2>&1)"
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
    if [ "$N_RED" -ge "$RUNTIME_CASES" ]; then
      echo "  NOTE: this mutant reddens every runtime case — that is a COUPLED"
      echo "        harness reporting on itself, not a broken hook."
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
# FIXTURES
# ==============================================================================

FEAT="$WORK/feat"     # feat/probe, with a remote
MASTER="$WORK/master" # master, with a remote
LOCAL="$WORK/local"   # master, no remote
NOREPO="$WORK/norepo" # outside any work tree
HOMED="$WORK/home"    # the $HOME the hook sees
VAULT="$WORK/vault"   # main, no remote: the path passed as alxVaultPath
mkdir -p "$FEAT" "$MASTER" "$LOCAL" "$NOREPO" "$HOMED" "$VAULT"

# The work dir must not itself sit in a work tree: NOREPO would then be "in git".
if "$GIT" -C "$NOREPO" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "probe: $NOREPO is inside a git work tree — the no-repo case would lie" >&2
  exit 2
fi

"$GIT" -C "$FEAT" init -q --initial-branch=feat/probe
"$GIT" -C "$FEAT" remote add origin https://example.invalid/p.git
"$GIT" -C "$MASTER" init -q --initial-branch=master
"$GIT" -C "$MASTER" remote add origin https://example.invalid/p.git
"$GIT" -C "$LOCAL" init -q --initial-branch=master
"$GIT" -C "$VAULT" init -q --initial-branch=main

fixture_ok() { # fixture_ok <dir> <branch> <remotes>
  local b r
  b="$("$GIT" -C "$1" branch --show-current)"
  r="$("$GIT" -C "$1" remote)"
  [ "$b" = "$2" ] && [ "$r" = "$3" ] || {
    echo "probe: fixture $1 is on '$b' with remotes '$r', expected '$2' / '$3'" >&2
    exit 2
  }
}
fixture_ok "$FEAT" feat/probe origin
fixture_ok "$MASTER" master origin
fixture_ok "$LOCAL" master ""
fixture_ok "$VAULT" main ""

# 128 KB on one line, no separator: 14564 x `git push ` (9 bytes). Quadratic
# for a scan that restarts at every `git push`, linear for one that does not.
PUSH128K="$(head -c 14564 /dev/zero | tr '\0' 'x' | sed 's/x/git push /g')"
[ "${#PUSH128K}" -ge 131072 ] || {
  echo "probe: the pass-fast payload is ${#PUSH128K} bytes, expected >= 131072" >&2
  exit 2
}
# A `\` + newline is a line continuation: still one push command.
PUSH_CONT="$(printf 'git push origin \\\nmaster')"
# The commit body is a quoted-delimiter heredoc: inert text.
HD_PUSH="$(printf "git commit -F - <<'EOF'\ngit push origin master\nEOF")"

# ==============================================================================
# RUNNER
# ==============================================================================

PASS=0
FAIL=0
NCASES=0

fail_case() {
  FAIL=$((FAIL + 1))
  printf 'FAIL  %-30s %s\n' "$1" "$2"
}
ok_case() {
  PASS=$((PASS + 1))
  printf 'ok    %-30s %s\n' "$1" "$2"
}

now_ms() { printf '%s\n' "${EPOCHREALTIME/[.,]/}" | cut -c1-13; }

RUN_RC=0
RUN_MS=0
run_raw() { # run_raw <cwd> <payload> <stdout> <stderr>
  local t0 t1
  t0="$(now_ms)"
  set +e
  # The alarm outlives the exec: SIGALRM at 10 s ends node with status 142.
  (cd "$1" && env HOME="$HOMED" \
    "$PERL" -e 'alarm 10; exec @ARGV or die "exec: $!"' "$NODE" "$SUT" < "$2" > "$3" 2> "$4")
  RUN_RC=$?
  set -e
  t1="$(now_ms)"
  RUN_MS=$((t1 - t0))
}

grade() { # grade <label> <kind> <rc> <stdout> <stderr>
  local label="$1" kind="$2" rc="$3" out="$4" err="$5" why=""
  # FORM, every case: the host must never see a non-zero exit, and stderr
  # stays silent — this is a fail-open hook.
  if [ "$rc" != "0" ]; then
    why="exit: expected 0, got $rc after ${RUN_MS} ms (stderr: $(head -c 200 "$err"))"
  elif [ -s "$err" ]; then
    why="stderr: expected empty, got $(head -c 200 "$err")"
  fi
  if [ -z "$why" ]; then
    case "$kind" in
      deny)
        if [ ! -s "$out" ]; then
          why="stdout: expected a deny, got nothing"
        elif ! "$JQ" -e -s 'length == 1 and (.[0].hookSpecificOutput.permissionDecision == "deny") and ((.[0].hookSpecificOutput.permissionDecisionReason | length) > 0)' "$out" > /dev/null 2>&1; then
          why="stdout is not one deny object: $(head -c 200 "$out")"
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

# check <label> <deny|pass|pass-fast> <cwd> <command>
#   deny       exactly one JSON object with permissionDecision "deny"
#   pass       stdout empty, byte for byte
#   pass-fast  pass, AND the run finished within 1000 ms
check() {
  local label="$1" kind="$2" cwd="$3" cmd="$4" pay out err
  NCASES=$((NCASES + 1))
  pay="$WORK/out/$label.json"
  out="$WORK/out/$label.stdout"
  err="$WORK/out/$label.stderr"
  "$JQ" -n --arg c "$cmd" '{tool_input:{command:$c}}' > "$pay"
  run_raw "$cwd" "$pay" "$out" "$err"
  grade "$label" "$kind" "$RUN_RC" "$out" "$err"
}

echo "=== block-main-bash probe ==="
echo "    hook under test: $SUT"
echo

# --- MUST DENY: a push whose destination is master/main, from feat/probe -----
check p01-origin-master deny "$FEAT" 'git push origin master'
check p02-origin-main deny "$FEAT" 'git push origin main'
check p03-head-colon-master deny "$FEAT" 'git push origin HEAD:master'
check p04-refs-heads-master deny "$FEAT" 'git push origin feat/probe:refs/heads/master'
check p05-force-plus-head-main deny "$FEAT" 'git push --force origin +HEAD:main'
check p06-set-upstream-master deny "$FEAT" 'git push -u origin master'
check p07-delete-master deny "$FEAT" 'git push origin :master'
check p08-heads-main deny "$FEAT" 'git push origin heads/main'
check p09-quoted-master deny "$FEAT" "git push origin 'master'"
check p10-git-C-push deny "$FEAT" "git -C $FEAT push origin master"
check p11-chained-push deny "$FEAT" 'git add -A && git push origin master'
check p12-two-refspecs deny "$FEAT" 'git push origin feat/probe master'
# Behind an executor the raw string is scanned: the word ends on a quote.
check p13-bash-c-push deny "$FEAT" 'bash -c "git push origin master"'
# A redirection glued to the word ends it: the push still goes to master.
check p14-redirect-glued deny "$FEAT" 'git push origin master>/dev/null'
check p15-head-colon-redirect deny "$FEAT" 'git push origin HEAD:master>/dev/null 2>&1'
check p16-line-continuation deny "$FEAT" "$PUSH_CONT"
# Unconditional: no remote, no repo — the destination alone decides.
check p01-local-no-remote deny "$LOCAL" 'git push origin master'
check p01-no-repo deny "$NOREPO" 'git push origin master'
# --- MUST PASS: other branches, reads, and text that only mentions a push ----
check n01-own-branch pass "$FEAT" 'git push origin feat/probe'
check n02-head-upstream pass "$FEAT" 'git push -u origin HEAD'
check n03-master-foo pass "$FEAT" 'git push origin master-foo'
check n04-feat-master pass "$FEAT" 'git push origin feat/master'
check n05-fix-x pass "$FEAT" 'git push origin fix/x'
check n06-log-master pass "$FEAT" 'git log master'
check n07-commit-msg-mentions pass "$FEAT" 'git commit -m "doc: never run git push origin master"'
check n08-fetch-master pass "$FEAT" 'git fetch origin master'
check n08-pull-master pass "$FEAT" 'git pull origin master'
check n09-chain-then-log-master pass "$FEAT" 'git push origin feat/x && git log master'
check n10-mainline pass "$FEAT" 'git push origin mainline'
check n11-heredoc-body pass "$FEAT" "$HD_PUSH"
# --- KNOWN GAP, asserted DENY: an EXECUTOR word keeps the raw string ---------
check k1-env-commit-msg deny "$FEAT" 'env X=1 git commit -m "git push origin master"'
# --- AC6, no regression of the current-branch rule ---------------------------
check ac6-master-push-own-branch deny "$MASTER" 'git push origin feat/x'
check ac6-local-commit-no-remote deny "$LOCAL" 'git commit -m x'
# --- B1, MUST DENY: every repo the command writes to is read (run 61) --------
check b1-c-then-C deny "$FEAT" "git -c k=v -C $MASTER commit -m x"
check b1-C-log-then-commit deny "$MASTER" "git -C $FEAT log; git commit -m x"
check b1-second-cd deny "$FEAT" "cd $FEAT && true; cd $MASTER && git commit -m x"
check b1-gitdir-flag deny "$FEAT" "git --git-dir=$MASTER/.git commit -m x"
check b1-gitdir-env deny "$FEAT" "GIT_DIR=$MASTER/.git git commit -m x"
check b1-var-cd deny "$FEAT" "R=$MASTER; cd \"\$R\" && git commit -m x"
check b1-pushd deny "$FEAT" "pushd $MASTER && git commit -m x"
check b1-subshell deny "$FEAT" "(cd $MASTER && git commit -m x)"
# --- B2, MUST DENY: a pull merges into the current branch --------------------
check b2-pull-bare deny "$MASTER" 'git pull'
check b2-pull-master deny "$MASTER" 'git pull origin feat/x'
# --- B1 partners, MUST PASS: the command provably lands on a feature branch --
check b1p-leading-cd pass "$MASTER" "cd $FEAT && git add -A && git commit -m x"
check b1p-single-C pass "$MASTER" "git -C $FEAT commit -m x"
check b1p-cd-missing-feat pass "$FEAT" 'cd /nonexistent57 && git commit -m x'
check b1p-status-master pass "$MASTER" 'git status'
# --- VAULT, MUST PASS: the one exempt repo, by the realpath of its toplevel --
if [ "$VAULT_BAKED" = "1" ]; then
  check v01-vault-commit pass "$VAULT" 'git commit -m x'
  check v02-vault-from-feat pass "$FEAT" "cd $VAULT && git commit -m x"
else
  printf 'skip  %-30s %s\n' v01-vault-commit "vault path baked at extraction — hook given as $SUT"
  printf 'skip  %-30s %s\n' v02-vault-from-feat "vault path baked at extraction — hook given as $SUT"
fi
# --- MUST PASS FAST: adversarial shape ---------------------------------------
check push-128k-fast pass-fast "$FEAT" "$PUSH128K"

# Derived, never declared: the mutant driver reads this back.
echo "runtime-cases: $NCASES"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
