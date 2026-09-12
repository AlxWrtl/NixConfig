#!/usr/bin/env bash
# Probe the apex-verify-external wrapper: does every degraded path still exit
# with the documented code AND leave a BLOCKED envelope on disk?
#
# WHY A STUB AND NEVER THE REAL BINARY. The system under test shells out to the
# OpenAI Codex CLI, and every real invocation spends the user's ChatGPT
# allowance. So the harness builds a `codex` recorder, puts it FIRST on a
# hermetic PATH, and proves before reporting anything that the real binary is
# not reachable from that PATH at all. A test that can accidentally bill the
# user is not a test.
#
# WHY A FIXTURE REPO AND NOT THIS ONE. The --print-brief assertions are about
# the brief's exact shape. Run against this repository, the real diff decides
# the answer, so the assertion would pass or fail for reasons unrelated to the
# wrapper. The fixture repos have a diff whose contents the harness controls.
#
# WHY --out LIVES INSIDE THE FIXTURE. The wrapper confines --out to under the
# reviewed repository's own `.claude/output/`, because `Bash(apex-verify-external
# *)` is auto-approved and an unconstrained --out would be a write-JSON-anywhere
# primitive. Envelopes therefore go to $FIXTURE/.claude/output/apex/, and both
# fixtures carry `.claude/` in .git/info/exclude so those envelopes do not
# become untracked files that contaminate the very diff under review. It must be
# info/exclude and not a .gitignore, because a .gitignore is itself a file in
# the worktree and would show up in the diff.
#
# Standalone, like checks/vault-autocommit-bench.sh: NOT wired into
# `nix flake check`, because it drives a script that is packaged elsewhere.

set -euo pipefail

SUT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/home/claude-code/scripts/apex-verify-external.sh}"

[ -f "$SUT" ] && [ -r "$SUT" ] || {
  echo "probe: script under test not found or not readable: $SUT" >&2
  exit 2
}

# The work dir must exist or the run must STOP. The fuzz harness this copies
# once let a failed `mktemp -d` through: $WORK was empty, every path resolved to
# the filesystem root, and it reported 44 failures that were all its own.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/apex-verify-probe.XXXXXX") || {
  echo "probe: cannot create a work directory under ${TMPDIR:-/tmp}" >&2
  exit 2
}
if [ -z "${WORK:-}" ] || [ ! -d "$WORK" ]; then
  echo "probe: work directory is empty or missing — refusing to run" >&2
  exit 2
fi
trap 'if [ -n "${WORK:-}" ] && [ -d "$WORK" ]; then chmod -R u+w "$WORK" 2>/dev/null || true; rm -rf "$WORK"; fi' EXIT

# --- hermetic PATH ------------------------------------------------------------
#
# Mirrors the package's runtimeInputs (git, jq, coreutils) and nothing else.
# `timeout` lives in coreutils and is absent from the interactive PATH on this
# machine, so it is resolved explicitly rather than assumed.
resolve_dir() { # resolve_dir <tool> [glob...]
  local tool="$1"; shift
  local p
  if p="$(command -v "$tool" 2>/dev/null)"; then
    dirname "$p"; return 0
  fi
  local g
  for g in "$@"; do
    for p in $g; do
      [ -x "$p" ] && { dirname "$p"; return 0; }
    done
  done
  return 1
}

GIT_DIR_BIN="$(resolve_dir git)" || { echo "probe: git not found" >&2; exit 2; }
JQ_DIR_BIN="$(resolve_dir jq)"   || { echo "probe: jq not found" >&2; exit 2; }
CU_DIR_BIN="$(resolve_dir timeout '/nix/store/*coreutils*/bin/timeout' '/opt/homebrew/opt/coreutils/libexec/gnubin/timeout')" || {
  echo "probe: coreutils \`timeout\` not found — the wrapper needs it" >&2
  exit 2
}
BASE_PATH="$CU_DIR_BIN:$GIT_DIR_BIN:$JQ_DIR_BIN:/usr/bin:/bin"

# THE MONEY GUARD. If a real `codex` is reachable from BASE_PATH, a case that
# forgets to install the stub would call it for real. Refuse to run instead.
if PATH="$BASE_PATH" command -v codex >/dev/null 2>&1; then
  echo "probe: a real \`codex\` is reachable from the harness PATH — refusing to run" >&2
  echo "probe: found at $(PATH="$BASE_PATH" command -v codex)" >&2
  exit 2
fi

# --- the stub recorder --------------------------------------------------------

STUB_DIR="$WORK/stub"
NOCODEX_DIR="$WORK/nostub"
mkdir -p "$STUB_DIR" "$NOCODEX_DIR"

cat > "$STUB_DIR/codex" <<'STUB'
#!/usr/bin/env bash
# Stand-in for the Codex CLI. Records argv and the brief, then plays the
# scenario named by $STUB_MODE. Never touches the network.
if [ "${1:-}" = "--version" ]; then
  printf 'codex-cli %s\n' "${STUB_VERSION:-0.153.1}"
  exit 0
fi
printf '%s\n' "$@" > "$STUB_ARGV"
printf 'call\n' >> "$STUB_CALLS"
out=""
prev=""
cd_path=""
for a in "$@"; do
  case "$prev" in
    -o) out="$a" ;;
    --cd) cd_path="$a" ;;
  esac
  prev="$a"
done
cat > "$STUB_STDIN"
if [ -f "$cd_path/tracked.txt" ] && grep -q 'beta-TRACKED-MARKER' "$cd_path/tracked.txt"; then
  : > "${STUB_READ_MARKER:?}"
fi
if [ -e "$cd_path/.claude/output/withheld.md" ]; then
  : > "${STUB_WITHHELD_MARKER:?}"
fi
if [ -e "$cd_path/api-token.txt" ] || [ -e "$cd_path/outside-link.txt" ] \
  || [ -e "$cd_path/secrets/passwords.json" ] || [ -e "$cd_path/.envrc" ] \
  || [ -e "$cd_path/keys/config.json" ]; then
  : > "${STUB_WITHHELD_MARKER:?}"
fi
# Names every protected path still readable from --cd, one per line. A bare
# marker would only say "something leaked"; the scrub filters are a list, and a
# failure has to say WHICH entry of that list stopped working.
if [ -n "${STUB_SURVIVORS:-}" ]; then
  : > "$STUB_SURVIVORS"
  for p in .env .env-private .env-private/config.json; do
    [ -e "$cd_path/$p" ] && printf '%s\n' "$p" >> "$STUB_SURVIVORS"
  done
fi
verdict_pass='{"verdict":"PASS","summary":"no defects found","findings":[]}'
case "${STUB_MODE:-pass}" in
  pass)
    printf '%s\n' "$verdict_pass" > "$out"
    exit 0
    ;;
  fail)
    printf '%s\n' '{"verdict":"FAIL","summary":"one defect","findings":[{"file":"a.txt","line":1,"severity":"critical","problem":"p","expected_fix":"f","ac":"AC-1"}]}' > "$out"
    exit 0
    ;;
  # Shaped like the real CLI's output, measured 2026-09-09: codex prefixes its
  # failures `ERROR:` and carries a structured payload. The wrapper classifies on
  # those lines only, because everything else on stderr is the banner and the
  # echoed brief — that is, the diff under review.
  auth)
    printf 'ERROR: {"type":"error","status":401,"error":{"message":"Unauthorized — run `codex login`"}}\n' >&2
    exit 1
    ;;
  # More than 64 KB of stderr whose FIRST line carries the auth signal. The
  # wrapper must still classify it as auth. A `printf ... | grep -q` classifier
  # returns 141 under pipefail once the output outgrows the pipe buffer, turning
  # "matched" into "did not match" on exactly the noisy failures that matter.
  bigauth)
    printf 'ERROR: {"type":"error","status":401,"error":{"message":"Unauthorized"}}\n' >&2
    awk 'BEGIN{for(i=0;i<2000;i++) printf "padding line %d of a very noisy vendor backtrace aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", i}' >&2
    exit 1
    ;;
  # A transport error whose request id merely CONTAINS 401. Not auth.
  reset)
    printf 'error sending request: connection reset (request_id=req_9f401bc2)\n' >&2
    exit 1
    ;;
  # A credential surfacing on the error stream, which must never reach the
  # envelope. Deliberately worded so it classifies as neither auth nor model.
  leak)
    printf 'config error: Authorization: Bearer sk-abcdefghij0123456789 session=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\n' >&2
    exit 1
    ;;
  model)
    printf 'ERROR: 400 model_not_found: unknown model\n' >&2
    exit 1
    ;;
  # Codex echoes the brief on stdout, and the brief carries the diff under
  # review. A classifier that greps stdout therefore lets the reviewed code
  # decide how a failure is classified. Here stdout carries this wrapper's own
  # auth vocabulary while the real failure on stderr is an account-scoped model
  # refusal — the exact shape measured against the live API on 2026-09-09.
  echoed-brief)
    printf 'OpenAI Codex v0.153.4\n--------\nuser\n' >&2
    cat "$STUB_STDIN" >&2
    printf 'ERROR: {"type":"error","status":400,"error":{"message":"The model is not supported when using Codex with a ChatGPT account."}}\n' >&2
    exit 1
    ;;
  # Writes a VALID verdict, but only after sleeping. Without this, "no timeout
  # was enforced" and "the model returned junk" both surface as exit 7 and the
  # timeout assertion cannot tell them apart.
  hang)
    sleep 30
    printf '%s\n' "$verdict_pass" > "$out"
    exit 0
    ;;
  prose)
    printf 'Looks good to me, ship it.\n' > "$out"
    exit 0
    ;;
  *)
    printf 'stub: unknown STUB_MODE=%s\n' "${STUB_MODE:-}" >&2
    exit 99
    ;;
esac
STUB
chmod +x "$STUB_DIR/codex"

# TRIPWIRE: prove the stub is what `codex` resolves to, and that it records.
STUB_ARGV="$WORK/tripwire.argv" STUB_CALLS="$WORK/tripwire.calls" \
STUB_STDIN="$WORK/tripwire.stdin" STUB_MODE=pass \
  PATH="$STUB_DIR:$BASE_PATH" bash -c 'codex --version >/dev/null' || {
  echo "probe: the stub codex is not executable — harness is broken" >&2
  exit 2
}
if [ "$(PATH="$STUB_DIR:$BASE_PATH" command -v codex)" != "$STUB_DIR/codex" ]; then
  echo "probe: \`codex\` does not resolve to the stub — refusing to report" >&2
  exit 2
fi

# --- fixtures -----------------------------------------------------------------

ACS="$WORK/acs.txt"
cat > "$ACS" <<'EOF'
AC-1: the wrapper prints exactly one line on stdout.
AC-2: every degraded path writes a BLOCKED envelope.
EOF
ACS_EMPTY="$WORK/acs-empty.txt"
: > "$ACS_EMPTY"
ACS_MISSING="$WORK/acs-does-not-exist.txt"

# A criteria file that is really a plan. The reviewer must never be handed the
# rationale, and the two files live side by side, so this is an easy slip.
ACS_PLAN="$WORK/acs-plan.md"
cat > "$ACS_PLAN" <<'EOF'
# 1. Premises
The change is correct because the author reasoned carefully about it.

## 2. Tasks
- [ ] do the thing
EOF

git_q() { git -c user.email=probe@local -c user.name=probe -c commit.gpgsign=false "$@"; }

# DIRTY: a tracked modification plus untracked files, including two whose names
# carry a space and a newline. Nothing pins the wrapper's -z / quoting handling
# of those otherwise, and it is correct today.
FIX_DIRTY="$WORK/fix-dirty"
mkdir -p "$FIX_DIRTY"
printf 'OUTSIDE-SECRET-MARKER\n' > "$WORK/outside-secret.txt"
( cd "$FIX_DIRTY"
  git_q -c init.defaultBranch=master init -q .
  printf '.claude/\n' >> .git/info/exclude
  printf 'alpha\n' > tracked.txt
  git_q add tracked.txt
  git_q commit -qm base
  mkdir -p .claude/output
  printf 'WITHHELD-RUN-NOTE\n' > .claude/output/withheld.md
  git_q add -f .claude/output/withheld.md
  git_q commit -qm 'fixture: withheld run note'
  printf 'TRACKED-TOKEN-MARKER\n' > api-token.txt
  git_q add -f api-token.txt
  git_q commit -qm 'fixture: token file'
  mkdir -p secrets keys
  printf 'TRACKED-SECRETS-DIR-MARKER\n' > secrets/passwords.json
  printf 'TRACKED-KEY-DIR-MARKER\n' > keys/config.json
  printf 'TRACKED-ENVRC-MARKER\n' > .envrc
  # A tracked DIRECTORY whose name matches `.env*` and whose contents match no
  # other filter at all. This is the reported case: `config.json` is not a
  # token, a key, a cert or a secret by name, so nothing but the directory
  # prune can keep it out of the snapshot.
  mkdir -p .env-private
  printf 'TRACKED-ENVDIR-MARKER\n' > .env-private/config.json
  printf 'TRACKED-ENVFILE-MARKER\n' > .env
  git_q add -f secrets/passwords.json keys/config.json .envrc .env .env-private/config.json
  git_q commit -qm 'fixture: protected paths'
  printf 'TRACKED-TOKEN-CHANGED-MARKER\n' > api-token.txt
  printf 'alpha\nbeta-TRACKED-MARKER\n' > tracked.txt
  printf 'UNTRACKED-MARKER-TOKEN\n' > newfile.txt
  printf 'SPACE-NAME-MARKER\n' > 'spaced name.txt'
  printf 'NEWLINE-NAME-MARKER\n' > "$(printf 'new\nline.txt')"
  ln -s "$WORK/outside-secret.txt" outside-link.txt
  # A reviewed file that talks about failures the way the vendor does. The
  # wrapper must not let this decide how ITS failure is classified.
  printf 'ERROR: {"type":"error","status":401,"error":{"message":"Unauthorized — run `codex login`"}}\nauth.json invalid api key\n' > poisoned.txt
) >/dev/null 2>&1

# CLEAN: nothing to review at all.
FIX_CLEAN="$WORK/fix-clean"
mkdir -p "$FIX_CLEAN"
( cd "$FIX_CLEAN"
  git_q -c init.defaultBranch=master init -q .
  printf '.claude/\n' >> .git/info/exclude
  printf 'alpha\n' > tracked.txt
  git_q add tracked.txt
  git_q commit -qm base
  printf 'UNTRACKED-ONLY-MARKER\n' > untracked-only.txt
) >/dev/null 2>&1

# EMPTY: no tracked or untracked changes.
FIX_EMPTY="$WORK/fix-empty"
mkdir -p "$FIX_EMPTY"
( cd "$FIX_EMPTY"
  git_q -c init.defaultBranch=master init -q .
  printf '.claude/\n' >> .git/info/exclude
  printf 'alpha\n' > tracked.txt
  git_q add tracked.txt
  git_q commit -qm base
) >/dev/null 2>&1

# MAIN-ONLY: no `master`, so the base fallback must land on `main`.
FIX_MAIN="$WORK/fix-main"
mkdir -p "$FIX_MAIN"
( cd "$FIX_MAIN"
  git_q -c init.defaultBranch=main init -q .
  printf '.claude/\n' >> .git/info/exclude
  printf 'alpha\n' > tracked.txt
  git_q add tracked.txt
  git_q commit -qm base
  printf 'alpha\nbeta-MAIN-MARKER\n' > tracked.txt
) >/dev/null 2>&1

# NOT A REPO: the wrapper must refuse and must not litter this directory.
NOT_REPO="$WORK/not-a-repo"
mkdir -p "$NOT_REPO"

# --- runner -------------------------------------------------------------------

PASS=0; FAIL=0
CASE_STDOUT=""; CASE_STATUS=0; CASE_OUT=""; CASE_CALLS=0
LAST_ARGV=""

# Informational modes write no envelope and print their own content, by design.
# The "one line on stdout" and "no silent green" rules below are universal
# EXCEPT for these, and the exception is named here rather than left implicit.
INFORMATIONAL=" print-brief help version untracked-included untracked-excluded stale-envelope brief-shape brief-framing odd-names "

fail_case() { # fail_case <label> <detail>
  FAIL=$((FAIL+1))
  printf 'FAIL  %-26s %s\n' "$1" "$2"
}
ok_case() { # ok_case <label> <note>
  PASS=$((PASS+1))
  printf 'ok    %-26s %s\n' "$1" "$2"
}

is_informational() { [[ "$INFORMATIONAL" == *" $1 "* ]]; }

# The envelope always lives under the reviewed repository's own output root,
# because the wrapper rejects anything else with exit 2.
case_out_for() { printf '%s/.claude/output/apex/%s.json\n' "$1" "$2"; }

run_wrapper() { # run_wrapper <label> <mode> <version> <repo> <use-stub 1|0> -- <args...>
  local label="$1" mode="$2" version="$3" repo="$4" usestub="$5"
  shift 6 # drop the literal --
  CASE_OUT="$(case_out_for "$repo" "$label")"
  rm -f "$CASE_OUT"
  local argv="$WORK/argv-$label.txt" calls="$WORK/calls-$label.txt"
  rm -f "$argv" "$calls" "$WORK/survivors-$label.txt"
  : > "$calls"
  LAST_ARGV="$argv"
  local pathspec="$BASE_PATH"
  [ "$usestub" = "1" ] && pathspec="$STUB_DIR:$BASE_PATH"
  [ "$usestub" = "0" ] && pathspec="$NOCODEX_DIR:$BASE_PATH"
  set +e
  CASE_STDOUT="$(
    cd "$repo" &&
    env -u APEX_CODEX_MODEL \
      PATH="$pathspec" \
      TMPDIR="${CASE_TMPDIR:-${TMPDIR:-/tmp}}" \
      STUB_MODE="$mode" STUB_VERSION="$version" \
      STUB_ARGV="$argv" STUB_CALLS="$calls" STUB_STDIN="$WORK/stdin-$label.txt" \
      STUB_READ_MARKER="$WORK/read-$label.marker" \
      STUB_WITHHELD_MARKER="$WORK/withheld-$label.marker" \
      STUB_SURVIVORS="$WORK/survivors-$label.txt" \
      bash -euo pipefail "$SUT" "$@" 2>"$WORK/stderr-$label.txt"
  )"
  CASE_STATUS=$?
  set -e
  CASE_CALLS=$(wc -l < "$calls" | tr -d ' ')
}

# "exactly one line on stdout" is the headline clause of the contract, so it is
# asserted by COUNT and not by a regex: `grep -qE` is happy to match line 1 of a
# two-line stdout, and a mutant that appends a stray line would sail through.
stdout_line_count() { printf '%s\n' "$CASE_STDOUT" | wc -l | tr -d ' '; }

# assert_case <label> <expected-exit> <stdout-regex> <jq-filter-or-> <expected-calls-or-*>
assert_case() {
  local label="$1" want="$2" rex="$3" filt="$4" wantcalls="$5"
  local why=""
  [ "$CASE_STATUS" = "$want" ] || why="exit: expected $want, got $CASE_STATUS"
  if [ -z "$why" ] && ! is_informational "$label"; then
    if [ -z "$CASE_STDOUT" ]; then
      why="stdout: expected exactly one line, got nothing"
    elif [ "$(stdout_line_count)" != "1" ]; then
      why="stdout: expected exactly 1 line, got $(stdout_line_count): $CASE_STDOUT"
    fi
  fi
  if [ -z "$why" ] && [ -n "$rex" ]; then
    printf '%s\n' "$CASE_STDOUT" | grep -qE "$rex" || why="stdout: expected /$rex/, got: $CASE_STDOUT"
  fi
  if [ -z "$why" ] && [ "$filt" != "-" ]; then
    if [ ! -s "$CASE_OUT" ]; then
      why="envelope: expected a file at $CASE_OUT, none written"
    elif ! jq -e "$filt" "$CASE_OUT" >/dev/null 2>&1; then
      why="envelope: jq filter [$filt] false; got $(jq -c '{verdict,reason,base,models_tried}' "$CASE_OUT" 2>/dev/null)"
    fi
  fi
  if [ -z "$why" ] && [ "$wantcalls" != "*" ]; then
    [ "$CASE_CALLS" = "$wantcalls" ] || why="codex calls: expected $wantcalls, got $CASE_CALLS"
  fi
  # NO SILENT GREEN: exit 0 is only ever legitimate alongside a PASS envelope,
  # except in the informational modes named above.
  if [ -z "$why" ] && [ "$CASE_STATUS" = "0" ] && ! is_informational "$label"; then
    if ! jq -e '.verdict == "PASS"' "$CASE_OUT" >/dev/null 2>&1; then
      why="silent green: exit 0 without \"verdict\":\"PASS\" on disk"
    fi
  fi
  if [ -n "$why" ]; then fail_case "$label" "$why"; else ok_case "$label" "exit $CASE_STATUS"; fi
}

echo "=== apex-verify-external probe (stub codex; the real binary is unreachable) ==="

DIRTY_OUT="$FIX_DIRTY/.claude/output/apex"

# --- verdict paths ------------------------------------------------------------
run_wrapper pass pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_DIRTY" pass)"
assert_case pass 0 '^EXTERNAL-VERIFY PASS ' '.verdict == "PASS" and (.findings | length) == 0' 1
PASS_ARGV="$LAST_ARGV"

run_wrapper fail fail 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_DIRTY" fail)"
assert_case fail 1 '^EXTERNAL-VERIFY FAIL ' '.verdict == "FAIL" and (.findings | length) == 1' 1

# --- usage --------------------------------------------------------------------
run_wrapper usage pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --out "$(case_out_for "$FIX_DIRTY" usage)" --bogus-flag
usage_why=""
[ "$CASE_STATUS" = 2 ] || usage_why="exit: expected 2, got $CASE_STATUS"
[ -z "$usage_why" ] && [ "$(stdout_line_count)" != "1" ] && usage_why="stdout: expected exactly 1 line, got $(stdout_line_count)"
[ -z "$usage_why" ] && [ -e "$CASE_OUT" ] && usage_why="an envelope was written on the usage path"
if [ -n "$usage_why" ]; then fail_case usage "$usage_why"; else ok_case usage "exit 2, one line, no envelope"; fi

# --- --out is confined to the reviewed repo's output tree ---------------------
#
# `Bash(apex-verify-external *)` is auto-approved, so an --out that escapes is
# the difference between a verification tool and a write-JSON-anywhere
# primitive. Both an absolute escape and a `..` traversal must be refused, and
# refused BEFORE anything is written anywhere.
ESCAPE_TARGET="$WORK/pretend-home/x.json"
mkdir -p "$WORK/pretend-home"
rm -f "$ESCAPE_TARGET"
escape_why=""
run_wrapper out-escape pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$ESCAPE_TARGET"
[ "$CASE_STATUS" = 2 ] || escape_why="absolute escape: expected exit 2, got $CASE_STATUS"
[ -z "$escape_why" ] && [ -e "$ESCAPE_TARGET" ] && escape_why="absolute escape wrote an envelope at $ESCAPE_TARGET"
[ -z "$escape_why" ] && [ "$CASE_CALLS" != "0" ] && escape_why="absolute escape still called codex $CASE_CALLS time(s)"
if [ -z "$escape_why" ]; then
  run_wrapper out-escape pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master \
    --out "$FIX_DIRTY/.claude/output/apex/../../../traversal.json"
  [ "$CASE_STATUS" = 2 ] || escape_why="traversal: expected exit 2, got $CASE_STATUS"
  [ -z "$escape_why" ] && [ -e "$FIX_DIRTY/traversal.json" ] && escape_why="traversal wrote an envelope at $FIX_DIRTY/traversal.json"
  [ -z "$escape_why" ] && [ "$CASE_CALLS" != "0" ] && escape_why="traversal still called codex $CASE_CALLS time(s)"
fi
if [ -n "$escape_why" ]; then fail_case out-escape "$escape_why"; else ok_case out-escape "confined to <repo>/.claude/output, nothing written"; fi

# --- binary -------------------------------------------------------------------
run_wrapper binary-absent pass 0.153.1 "$FIX_DIRTY" 0 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_DIRTY" binary-absent)"
assert_case binary-absent 3 '^EXTERNAL-VERIFY BLOCKED ' '.verdict == "BLOCKED" and .reason == "binary"' 0

run_wrapper binary-old pass 0.142.5 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_DIRTY" binary-old)"
assert_case binary-old 3 'reason=binary' '.verdict == "BLOCKED" and .reason == "binary"' 0

# --- model chain --------------------------------------------------------------
# The chain must STOP on an auth-shaped failure: models_tried length 1.
run_wrapper auth auth 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_DIRTY" auth)"
assert_case auth 4 'reason=auth' '.verdict == "BLOCKED" and .reason == "auth" and (.models_tried | length) == 1' 1

# THE REGRESSION TEST FOR THE WORST DEFECT IN THE REVIEW. The auth signal is on
# line 1 of more than 64 KB of stderr. A classifier built on `printf | grep -q`
# exits 141 under pipefail here and silently downgrades this to reason=model.
run_wrapper auth-large bigauth 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_DIRTY" auth-large)"
assert_case auth-large 4 'reason=auth' '.verdict == "BLOCKED" and .reason == "auth" and (.models_tried | length) == 1' 1

# The mirror image: a bare 401 inside a request id, with no HTTP context on the
# line, must NOT be read as auth. Telling a user to log in again over a
# connection reset sends them to fix the one thing that is not broken.
run_wrapper auth-false-positive reset 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_DIRTY" auth-false-positive)"
assert_case auth-false-positive 5 'reason=model' '.verdict == "BLOCKED" and .reason == "model"' 1

# The diff under review must not be able to decide how a failure is classified.
# Measured against the live API on 2026-09-09: this repo's own diff contains the
# wrapper's auth vocabulary, Codex echoed the brief on stdout, and an
# account-scoped model refusal was reported as reason=auth — which stops the
# chain, so the fallback model was never dialled. Three rungs, because a model
# refusal must advance to the end of the chain.
run_wrapper echoed-brief echoed-brief 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_DIRTY" echoed-brief)"
assert_case echoed-brief 5 'reason=model' '.verdict == "BLOCKED" and .reason == "model" and (.models_tried | length) == 3' 3

# A model-shaped failure must ADVANCE through the whole chain. The last rung
# passes no -m at all, so the chain is three rungs and ends at cli-default.
run_wrapper model model 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_DIRTY" model)"
assert_case model 5 'reason=model' '.verdict == "BLOCKED" and .reason == "model" and (.models_tried | length) == 3 and (.models_tried | last) == "cli-default"' 3

# --- timeout, unparseable -----------------------------------------------------
# The hang stub writes a VALID verdict after its sleep, so a wrapper that failed
# to enforce the timeout would exit 0 rather than landing on 7 by accident.
run_wrapper timeout hang 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --timeout 2 --out "$(case_out_for "$FIX_DIRTY" timeout)"
assert_case timeout 6 'reason=timeout' '.verdict == "BLOCKED" and .reason == "timeout" and .model == "none"' 1

run_wrapper unparseable prose 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_DIRTY" unparseable)"
assert_case unparseable 7 'reason=unparseable' '.verdict == "BLOCKED" and .reason == "unparseable"' 1

# --- input bounds -------------------------------------------------------------
# Oversize must be caught BEFORE the subprocess: zero calls, no allowance spent.
run_wrapper oversize pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --max-diff-bytes 5 --out "$(case_out_for "$FIX_DIRTY" oversize)"
assert_case oversize 8 'reason=input' '.verdict == "BLOCKED" and .reason == "input"' 0

run_wrapper empty-diff pass 0.153.1 "$FIX_EMPTY" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_EMPTY" empty-diff)"
assert_case empty-diff 8 'reason=input' '.verdict == "BLOCKED" and .reason == "input"' 0

run_wrapper acs-missing pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS_MISSING" --base master --out "$(case_out_for "$FIX_DIRTY" acs-missing)"
assert_case acs-missing 8 'reason=input' '.verdict == "BLOCKED" and .reason == "input"' 0

run_wrapper acs-empty pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS_EMPTY" --base master --out "$(case_out_for "$FIX_DIRTY" acs-empty)"
assert_case acs-empty 8 'reason=input' '.verdict == "BLOCKED" and .reason == "input"' 0

# Handing --acs the planning document quietly undoes the whole design: the
# reviewer would be told why the author believes the change is right.
run_wrapper acs-plan pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS_PLAN" --base master --out "$(case_out_for "$FIX_DIRTY" acs-plan)"
assert_case acs-plan 8 'reason=input' '.verdict == "BLOCKED" and .reason == "input"' 0

# --- base fallback ------------------------------------------------------------
# `master` was once hard-coded. A repository whose only sin is being called main
# must still be reviewable without --base.
run_wrapper base-fallback pass 0.153.1 "$FIX_MAIN" 1 -- --acs "$ACS" --out "$(case_out_for "$FIX_MAIN" base-fallback)"
assert_case base-fallback 0 '^EXTERNAL-VERIFY PASS ' '.verdict == "PASS" and .base == "main"' 1

# --- failures with nowhere to write -------------------------------------------
# No work directory: the wrapper has not resolved an --out yet, so it must print
# its line with out=- and write nothing at all.
MKTEMP_OUT="$(case_out_for "$FIX_DIRTY" mktemp-fail)"
rm -f "$MKTEMP_OUT"
CASE_TMPDIR="$WORK/no-such-tmpdir-$$"
run_wrapper mktemp-fail pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$MKTEMP_OUT"
unset CASE_TMPDIR
mktemp_why=""
[ "$CASE_STATUS" = 8 ] || mktemp_why="exit: expected 8, got $CASE_STATUS"
[ -z "$mktemp_why" ] && [ "$(stdout_line_count)" != "1" ] && mktemp_why="stdout: expected exactly 1 line, got $(stdout_line_count)"
if [ -z "$mktemp_why" ]; then
  printf '%s\n' "$CASE_STDOUT" | grep -qE '^EXTERNAL-VERIFY BLOCKED .* out=-$' \
    || mktemp_why="stdout: expected a BLOCKED line ending out=-, got: $CASE_STDOUT"
fi
[ -z "$mktemp_why" ] && [ -e "$MKTEMP_OUT" ] && mktemp_why="an envelope was written despite having no work directory"
if [ -n "$mktemp_why" ]; then fail_case mktemp-fail "$mktemp_why"; else ok_case mktemp-fail "exit 8, out=-, nothing written"; fi

# Outside a git repo there is no sanctioned output root, and the wrapper must
# not invent one in whatever directory the caller happened to be standing in.
rm -rf "${NOT_REPO:?}/.claude"
run_wrapper not-a-repo pass 0.153.1 "$NOT_REPO" 1 -- --acs "$ACS" --base master
norepo_why=""
[ "$CASE_STATUS" = 8 ] || norepo_why="exit: expected 8, got $CASE_STATUS"
[ -z "$norepo_why" ] && [ "$(stdout_line_count)" != "1" ] && norepo_why="stdout: expected exactly 1 line, got $(stdout_line_count)"
if [ -z "$norepo_why" ]; then
  printf '%s\n' "$CASE_STDOUT" | grep -qE '^EXTERNAL-VERIFY BLOCKED .* out=-$' \
    || norepo_why="stdout: expected a BLOCKED line ending out=-, got: $CASE_STDOUT"
fi
[ -z "$norepo_why" ] && [ -e "$NOT_REPO/.claude" ] && norepo_why="./.claude/ was created outside a git repository"
[ -z "$norepo_why" ] && [ "$CASE_CALLS" != "0" ] && norepo_why="codex was called outside a git repository"
if [ -n "$norepo_why" ]; then fail_case not-a-repo "$norepo_why"; else ok_case not-a-repo "exit 8, out=-, no ./.claude created"; fi

# --- the envelope is the verdict: no artefact, no green -----------------------
# The model answers PASS, but --out points inside a regular FILE, so both
# `mkdir -p` and the redirect fail. Before this case existed the wrapper printed
# a warning and still exited 0: a green whose artefact does not exist. The
# blocker must live inside the sanctioned output root, or the run is rejected
# for the path rather than for the write.
mkdir -p "$DIRTY_OUT"
rm -rf "$DIRTY_OUT/blocker"
: > "$DIRTY_OUT/blocker"
run_wrapper envelope pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$DIRTY_OUT/blocker/verdict.json"
envelope_why=""
[ "$CASE_STATUS" = "9" ] || envelope_why="exit: expected 9, got $CASE_STATUS"
[ -z "$envelope_why" ] && [ "$(stdout_line_count)" != "1" ] && envelope_why="stdout: expected exactly 1 line, got $(stdout_line_count)"
if [ -z "$envelope_why" ]; then
  printf '%s\n' "$CASE_STDOUT" | grep -qE '^EXTERNAL-VERIFY BLOCKED ' \
    || envelope_why="stdout: expected BLOCKED, got: $CASE_STDOUT"
fi
if [ -z "$envelope_why" ]; then
  printf '%s\n' "$CASE_STDOUT" | grep -q 'reason=envelope' \
    || envelope_why="stdout: expected reason=envelope, got: $CASE_STDOUT"
fi
if [ -z "$envelope_why" ] && [ -e "$DIRTY_OUT/blocker/verdict.json" ]; then
  envelope_why="an envelope exists at a path that cannot hold one"
fi
if [ -n "$envelope_why" ]; then
  fail_case envelope "$envelope_why"
else
  ok_case envelope "exit 9, no artefact, no green"
fi
rm -f "$DIRTY_OUT/blocker"

# --- a stale envelope is a lie waiting to be read -----------------------------
# --print-brief exits 0 and writes nothing, so a caller checking $? and then
# reading --out must not be handed the PREVIOUS run's PASS.
STALE_OUT="$(case_out_for "$FIX_DIRTY" stale-envelope)"
mkdir -p "$(dirname "$STALE_OUT")"
printf '%s\n' '{"verdict":"PASS"}' > "$STALE_OUT"
run_wrapper stale-envelope pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --print-brief --out "$STALE_OUT"
stale_why=""
[ "$CASE_STATUS" = 0 ] || stale_why="exit: expected 0, got $CASE_STATUS"
[ -z "$stale_why" ] && [ -e "$STALE_OUT" ] && stale_why="the previous run's envelope survived a --print-brief run"
if [ -n "$stale_why" ]; then fail_case stale-envelope "$stale_why"; else ok_case stale-envelope "prior verdict cleared before any work"; fi

# --- secrets never reach the envelope -----------------------------------------
# A vendor error stream is the likeliest place in this tool for a credential to
# surface, and the summary is read straight back into an agent's context.
run_wrapper secrets leak 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_DIRTY" secrets)"
secrets_why=""
[ "$CASE_STATUS" = 5 ] || secrets_why="exit: expected 5, got $CASE_STATUS"
if [ -z "$secrets_why" ] && [ ! -s "$CASE_OUT" ]; then
  secrets_why="no envelope written, so the scrubbing assertion would be vacuous"
fi
if [ -z "$secrets_why" ]; then
  for secret in 'sk-abcdefghij0123456789' 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'; do
    if grep -qF "$secret" "$CASE_OUT"; then
      secrets_why="the envelope contains the secret $secret"
    fi
  done
fi
if [ -z "$secrets_why" ]; then
  grep -qF 'redacted' "$CASE_OUT" || secrets_why="nothing was redacted, so the leak never reached the summary and the case proves nothing"
fi
if [ -n "$secrets_why" ]; then fail_case secrets "$secrets_why"; else ok_case secrets "credentials scrubbed before the envelope"; fi

# --- the scrub prunes protected DIRECTORIES, not only protected files ---------
#
# `.env*` sat on the file filter alone, so a tracked `.env-private/` reached the
# snapshot whole: the directory prune did not know the name, and nothing inside
# it — `config.json` — matched any other filter either. The reviewer could read
# every byte of it. The stub reports back which protected paths it can still
# see from --cd, so a regression names the survivor instead of only denying it.
run_wrapper snapshot-env pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_DIRTY" snapshot-env)"
SURVIVORS="$WORK/survivors-snapshot-env.txt"
envdir_why=""
# `ls-files --error-unmatch` et non `-f` : la présence dans l'arbre de travail ne
# dit pas que git les SUIT. Un `.env*` non suivi est filtré par un autre chemin
# de code — la copie des non-suivis — donc le cas ne prouverait rien sur
# l'élagage des répertoires, qui est ce qu'il existe pour tester.
git -C "$FIX_DIRTY" ls-files --error-unmatch .env .env-private/config.json >/dev/null 2>&1 \
  || envdir_why="the fixture does not TRACK .env and .env-private/config.json, so the case proves nothing about directory pruning"
[ -z "$envdir_why" ] && [ "$CASE_CALLS" != "1" ] && envdir_why="codex calls: expected 1, got $CASE_CALLS — the snapshot was never inspected"
[ -z "$envdir_why" ] && [ ! -f "$SURVIVORS" ] && envdir_why="the stub recorded no survivor list, so the assertion would be vacuous"
if [ -z "$envdir_why" ] && [ -s "$SURVIVORS" ]; then
  envdir_why="protected paths survived into the snapshot: $(tr '\n' ' ' < "$SURVIVORS")"
fi
if [ -n "$envdir_why" ]; then fail_case snapshot-env "$envdir_why"; else ok_case snapshot-env ".env and .env-private/ both pruned from the snapshot"; fi

# --- argv: the subprocess is a verifier, not an actor -------------------------
#
# Presence-only assertions are not enough. `-s danger-full-access` appended
# AFTER `-s read-only` contains the string `-s read-only` and would pass, while
# the LAST -s is what the CLI honours. So: exactly one -s, and its value is
# read-only. And `--cd` defines the reconstructed source perimeter, so its value
# is asserted, not just its presence.
argv_why=""
if [ ! -s "$PASS_ARGV" ]; then
  argv_why="no argv recorded — the stub never ran"
else
  mapfile -t ARGV_ARR < "$PASS_ARGV"
  argv_line="$(tr '\n' ' ' < "$PASS_ARGV")"

  s_count=0; s_value=""; cd_seen=0; cd_value=""; skip_seen=0
  for ((i = 0; i < ${#ARGV_ARR[@]}; i++)); do
    case "${ARGV_ARR[i]}" in
      -s)   s_count=$((s_count + 1)); s_value="${ARGV_ARR[i+1]:-}" ;;
      --cd) cd_seen=1; cd_value="${ARGV_ARR[i+1]:-}" ;;
      --skip-git-repo-check) skip_seen=1 ;;
    esac
  done

  [ "$s_count" = 1 ] || argv_why="expected exactly one -s, found $s_count; argv: $argv_line"
  [ -z "$argv_why" ] && [ "$s_value" != "read-only" ] && argv_why="the -s value is '$s_value', not read-only; argv: $argv_line"

  if [ -z "$argv_why" ]; then
    for want in '--ignore-user-config ' '--output-schema ' '--ephemeral '; do
      case "$argv_line" in *"$want"*) : ;; *) argv_why="missing $want; argv: $argv_line" ;; esac
    done
  fi

  # Every documented way to hand this subprocess more authority than a reviewer
  # needs. Any of them appearing is a defect regardless of what else is present.
  if [ -z "$argv_why" ]; then
    for forbidden in 'danger-full-access' '--full-auto' '--yolo' '-a never' \
                     '--dangerously-bypass-approvals-and-sandbox' \
                     '--dangerously-bypass-hook-trust' 'dangerously-bypass'; do
      case " $argv_line" in *"$forbidden"*) argv_why="argv contains $forbidden: $argv_line" ;; esac
    done
  fi

# THE READ PERIMETER. Codex must receive code to inspect, but not the repository
# metadata and run notes. The wrapper supplies a temporary reconstructed snapshot
# and keeps the real repository path out of argv.
  if [ -z "$argv_why" ]; then
    [ "$cd_seen" = 1 ] || argv_why="no --cd in argv: $argv_line"
  fi
  if [ -z "$argv_why" ]; then
    for repo_form in "$FIX_DIRTY" "$(cd "$FIX_DIRTY" && pwd -P)"; do
      [ "$cd_value" = "$repo_form" ] && argv_why="--cd points at the repository ($cd_value): the reviewer can read everything the brief withholds"
    done
  fi
  if [ -z "$argv_why" ]; then
    case "$cd_value" in
      */repo) : ;;
      *) argv_why="--cd is not the reconstructed source snapshot: $cd_value" ;;
    esac
  fi
  if [ -z "$argv_why" ]; then
    [ "$skip_seen" = 1 ] || argv_why="no --skip-git-repo-check, so the CLI cannot start outside a repo: $argv_line"
  fi
  if [ -z "$argv_why" ] && [ ! -e "$WORK/read-pass.marker" ]; then
    argv_why="stub could not read tracked marker from reconstructed snapshot"
  fi
  if [ -z "$argv_why" ] && [ -e "$WORK/withheld-pass.marker" ]; then
    argv_why="snapshot exposed withheld .claude/output metadata"
  fi
fi
if [ -n "$argv_why" ]; then fail_case argv "$argv_why"; else ok_case argv "one -s read-only, reconstructed snapshot, no bypass"; fi

# --- informational modes ------------------------------------------------------
# Both are named in the contract as printing their own content and no status
# line, and neither was exercised before.
for info in help version; do
  info_out="$(case_out_for "$FIX_DIRTY" "$info")"
  rm -f "$info_out"
  run_wrapper "$info" pass 0.153.1 "$FIX_DIRTY" 1 -- "--$info"
  info_why=""
  [ "$CASE_STATUS" = 0 ] || info_why="exit: expected 0, got $CASE_STATUS"
  [ -z "$info_why" ] && [ -z "$CASE_STDOUT" ] && info_why="printed nothing"
  if [ -z "$info_why" ]; then
    printf '%s\n' "$CASE_STDOUT" | grep -q '^EXTERNAL-VERIFY ' && info_why="printed a status line, which --$info must not"
  fi
  [ -z "$info_why" ] && [ "$CASE_CALLS" != "0" ] && info_why="called codex $CASE_CALLS time(s)"
  [ -z "$info_why" ] && [ -e "$info_out" ] && info_why="wrote an envelope"
  if [ -n "$info_why" ]; then fail_case "$info" "$info_why"; else ok_case "$info" "exit 0, own content, no envelope"; fi
done

# --- the brief carries criteria and diff, and nothing else --------------------
run_wrapper print-brief pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --print-brief --out "$(case_out_for "$FIX_DIRTY" print-brief)"
BRIEF_TEXT="$WORK/brief-captured.txt"
printf '%s\n' "$CASE_STDOUT" > "$BRIEF_TEXT"
brief_why=""
[ "$CASE_STATUS" = 0 ] || brief_why="exit: expected 0, got $CASE_STATUS"
[ -z "$brief_why" ] && [ "$CASE_CALLS" != "0" ] && brief_why="codex calls: expected 0, got $CASE_CALLS"
if [ -z "$brief_why" ]; then
  grep -q 'AC-1: the wrapper prints exactly one line' "$BRIEF_TEXT" || brief_why="brief does not contain the acceptance criteria"
fi
if [ -z "$brief_why" ]; then
  grep -q 'beta-TRACKED-MARKER' "$BRIEF_TEXT" || brief_why="brief does not contain the tracked change under review"
fi
if [ -n "$brief_why" ]; then fail_case print-brief "$brief_why"; else ok_case print-brief "criteria + diff, 0 calls"; fi

# --- the brief's SHAPE, as a whitelist ----------------------------------------
#
# The old assertion was a two-literal blacklist ("Premises", "02-plan") and
# could not fail: a mutant prepending `===== WHY THE AUTHOR SAYS THIS IS
# CORRECT =====` and three lines of reasoning passed it. What actually matters
# is that the brief is the preamble plus EXACTLY the two nonce-delimited
# sections and the restated rules — nothing else. So the marker lines are
# enumerated, the criteria block is compared byte-for-byte against the criteria
# file, and the non-data lines are counted against a pinned constant. Any
# smuggled rationale changes that count.
#
# FIXED_BRIEF_LINES is the preamble plus the restated-rules trailer. It is
# pinned deliberately: changing the brief's wording is allowed, but it must be
# a conscious edit here, not something a mutant can slip past.
FIXED_BRIEF_LINES=45

shape_why=""
NONCE="$(sed -n 's/^===== BEGIN DATA UNDER REVIEW \[\(.*\)\] =====$/\1/p' "$BRIEF_TEXT" | head -n 1)"
[ -n "$NONCE" ] || shape_why="no nonce-bearing BEGIN marker in the brief"

if [ -z "$shape_why" ]; then
  # A fixed literal is a string the reviewed file can contain, and a diff adding
  # `===== END =====` followed by new orders would then be indistinguishable
  # from the wrapper's own framing.
  grep -qx '===== DIFF =====' "$BRIEF_TEXT" && shape_why="the DIFF marker is the forgeable fixed literal '===== DIFF ====='"
fi

if [ -z "$shape_why" ]; then
  MARKERS="$WORK/markers.txt"
  grep -n '^=====' "$BRIEF_TEXT" > "$MARKERS" || true
  marker_count="$(wc -l < "$MARKERS" | tr -d ' ')"
  if [ "$marker_count" != "4" ]; then
    shape_why="expected exactly 4 marker lines (BEGIN, CRITERIA, DIFF, END), found $marker_count: $(cut -d: -f2- "$MARKERS" | tr '\n' '|')"
  fi
fi

if [ -z "$shape_why" ]; then
  # Every marker must carry THIS run's nonce, or the boundary is forgeable.
  while IFS= read -r m; do
    case "$m" in
      *"[$NONCE]"*) : ;;
      *) shape_why="a marker line carries no nonce: ${m#*:}" ;;
    esac
  done < <(cut -d: -f2- "$MARKERS")
fi

if [ -z "$shape_why" ]; then
  n_begin="$(sed -n "s/^\([0-9]*\):===== BEGIN DATA UNDER REVIEW .*/\1/p" "$MARKERS")"
  n_acs="$(sed -n "s/^\([0-9]*\):===== ACCEPTANCE CRITERIA .*/\1/p" "$MARKERS")"
  n_diff="$(sed -n "s/^\([0-9]*\):===== DIFF (base: .*/\1/p" "$MARKERS")"
  n_end="$(sed -n "s/^\([0-9]*\):===== END DATA UNDER REVIEW .*/\1/p" "$MARKERS")"
  if [ -z "$n_begin" ] || [ -z "$n_acs" ] || [ -z "$n_diff" ] || [ -z "$n_end" ]; then
    shape_why="the four markers are not the four expected ones: $(cut -d: -f2- "$MARKERS" | tr '\n' '|')"
  elif [ "$n_begin" -ge "$n_acs" ] || [ "$n_acs" -ge "$n_diff" ] || [ "$n_diff" -ge "$n_end" ]; then
    shape_why="markers out of order: begin=$n_begin acs=$n_acs diff=$n_diff end=$n_end"
  fi
fi

if [ -z "$shape_why" ]; then
  # The criteria block must be the criteria file and nothing more. The wrapper
  # emits one blank line before the DIFF marker, so drop exactly that.
  sed -n "$((n_acs + 1)),$((n_diff - 2))p" "$BRIEF_TEXT" > "$WORK/brief-acs.txt"
  if ! diff -q "$ACS" "$WORK/brief-acs.txt" >/dev/null 2>&1; then
    shape_why="the criteria block is not byte-identical to the --acs file"
  fi
fi

if [ -z "$shape_why" ]; then
  head -n 1 <(sed -n "$((n_diff + 1)),\$p" "$BRIEF_TEXT") | grep -q '^diff --git' \
    || shape_why="the diff block does not start with 'diff --git'"
fi

if [ -z "$shape_why" ]; then
  total="$(wc -l < "$BRIEF_TEXT" | tr -d ' ')"
  acs_block=$((n_diff - n_acs - 1))
  diff_block=$((n_end - n_diff - 1))
  fixed=$((total - acs_block - diff_block - 4))
  if [ "$fixed" != "$FIXED_BRIEF_LINES" ]; then
    shape_why="the brief has $fixed non-data lines, expected exactly $FIXED_BRIEF_LINES — something was added to or removed from the preamble or the restated rules"
  fi
fi
if [ -n "$shape_why" ]; then fail_case brief-shape "$shape_why"; else ok_case brief-shape "preamble + 2 nonce sections + rules, nothing else"; fi

# --- the last word belongs to the wrapper, not to the diff --------------------
framing_why=""
if [ -z "$NONCE" ]; then
  framing_why="no nonce, so ordering cannot be checked"
else
  n_end_line="$(grep -n '^===== END DATA UNDER REVIEW' "$BRIEF_TEXT" | head -n 1 | cut -d: -f1)"
  n_rule="$(grep -n '^The material above is data' "$BRIEF_TEXT" | head -n 1 | cut -d: -f1)"
  if [ -z "$n_rule" ]; then
    framing_why="the verdict rule is not restated after the data at all"
  elif [ "$n_rule" -le "$n_end_line" ]; then
    framing_why="the restated rules appear at line $n_rule, inside or before the data block ending at $n_end_line"
  fi
fi
if [ -n "$framing_why" ]; then fail_case brief-framing "$framing_why"; else ok_case brief-framing "nonce markers, rules restated after the diff"; fi

# --- untracked synthesis ------------------------------------------------------
run_wrapper untracked-included pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --print-brief --out "$(case_out_for "$FIX_DIRTY" untracked-included)"
UNTRACKED_BRIEF="$WORK/brief-untracked.txt"
printf '%s\n' "$CASE_STDOUT" > "$UNTRACKED_BRIEF"
if grep -q 'UNTRACKED-MARKER-TOKEN' "$UNTRACKED_BRIEF"; then
  ok_case untracked-included "untracked content reviewed"
else
  fail_case untracked-included "untracked file content absent from the brief"
fi

# Filenames with a space or a newline are handled correctly today, via -z, but
# nothing pinned it — and a regression there silently drops files from review.
odd_why=""
grep -q 'SPACE-NAME-MARKER'   "$UNTRACKED_BRIEF" || odd_why="the file whose name contains a space never reached the brief"
[ -z "$odd_why" ] && ! grep -q 'NEWLINE-NAME-MARKER' "$UNTRACKED_BRIEF" && odd_why="the file whose name contains a newline never reached the brief"
if [ -n "$odd_why" ]; then fail_case odd-names "$odd_why"; else ok_case odd-names "space and newline filenames both reviewed"; fi

run_wrapper untracked-excluded pass 0.153.1 "$FIX_DIRTY" 1 -- --acs "$ACS" --base master --print-brief --no-untracked --out "$(case_out_for "$FIX_DIRTY" untracked-excluded)"
if printf '%s\n' "$CASE_STDOUT" | grep -q 'UNTRACKED-MARKER-TOKEN'; then
  fail_case untracked-excluded "--no-untracked still included the untracked file"
else
  ok_case untracked-excluded "--no-untracked excludes it"
fi

# A repository with only included untracked changes must still reach Codex: the
# tracked patch is empty, but the synthesized untracked diff is reviewable.
run_wrapper untracked-only pass 0.153.1 "$FIX_CLEAN" 1 -- --acs "$ACS" --base master --out "$(case_out_for "$FIX_CLEAN" untracked-only)"
if [ "$CASE_STATUS" = 0 ] && jq -e '.verdict == "PASS"' "$CASE_OUT" >/dev/null 2>&1; then
  ok_case untracked-only "empty tracked patch accepted; untracked source reviewed"
else
  fail_case untracked-only "only-untracked review did not reach a PASS verdict"
fi

# --- the envelopes never contaminated the diff --------------------------------
# If .git/info/exclude stopped hiding .claude/, every envelope written above
# would become an untracked file and be fed back into the next review.
# `grep` sur le FICHIER, pas sur son nom. La forme précédente pipait la VARIABLE
# — un chemin sous $WORK — dans grep, donc le motif `.claude/output/apex` ne
# pouvait jamais matcher et la branche verte gagnait toujours. Assertion verte
# par construction, AC6 non prouvée.
if grep -q '\.claude/output/apex' "$UNTRACKED_BRIEF"; then
  fail_case envelope-isolation "the harness's own envelopes appear in the reviewed diff"
else
  ok_case envelope-isolation "envelopes excluded from the reviewed diff"
fi

# --- final guard: the real binary was never reachable, let alone run ----------
if PATH="$BASE_PATH" command -v codex >/dev/null 2>&1; then
  fail_case real-binary "a real codex became reachable during the run"
else
  ok_case real-binary "never on the harness PATH"
fi

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
