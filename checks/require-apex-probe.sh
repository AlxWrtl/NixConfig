#!/usr/bin/env bash
# Positive control for `hookRequireApex` — the PreToolUse hook that denies a
# file-writing command until APEX has run for the current request.
#
# WHAT IT GRADES. The Bash door of that hook, and above all its INTERPRETER
# rules: inline `python3 -c` / `node -e` / `ruby -e` code that calls a write
# API, an interpreter heredoc that does the same, and a script FILE outside
# the repo whose source writes and names this repo's toplevel. Each rule was
# measured over 20 645 recorded Bash calls before it was written; this file is
# what keeps the written version honest against those measurements.
#
# EVERY RULE IN BOTH POLARITIES. A guard that denies everything scores green on
# every deny case, so each widening has a partner that must PASS:
# `python-c-writes-package-json` denies, `python-c-json-load-read` passes;
# `script-out-of-repo-plain` denies, `script-out-of-repo-no-repo-path` and
# `script-out-of-repo-no-write-api` pass; `cp-helper-not-a-write` passes
# because a script's own function named `cp` is not a file copy.
#
# PASS IS ASSERTED ON EMPTINESS. A pass case asserts that stdout is empty byte
# for byte, never that some word is absent from it: a hook that crashed before
# printing anything would pass an absence test just as well.
#
# THE REAL CONDITIONS, BUILT IN $WORK. The hook reads the cwd's git repo and a
# transcript, so the probe makes both: a throwaway `git init` repo, a
# transcript whose last event is a real user turn (no APEX yet) and one where
# an APEX Skill call follows it. A `git` shim on PATH logs every git call, so
# `no-shape-spawns-no-git` can prove a plain `ls -la` costs no subprocess.
# $HOME is a fixture directory too, so `~/edit.py` is a file this probe owns.
# One fixture lives under /tmp/claude-<uid>, the $TMPDIR a sandboxed Bash call
# gets, while the hook runs with another: `script-tmpdir-split`.
#
# EVERY RUN IS BOUNDED. The hook runs under a 10 s alarm: a regex that
# backtracks for minutes, or an open() that blocks on a FIFO, is a red case
# with its exit status, not a probe that never returns. `pass-fast` cases
# bound the run at 1000 ms.
#
# KNOWN GAPS, asserted as PASS so they cannot be mistaken for coverage:
# `unresolved-var-known-gap` (a script path in a `$VAR` the hook cannot see)
# and `git-commit-heredoc-hash-body` (the interpreter heredoc rule is scoped to
# interpreters; widening the generic heredoc test was measured at +120 false
# positives and rejected).
#
# WHY THE MUTANTS ARE PART OF THE FILE. A test you have only ever seen pass has
# not been run. Each mutant is a literal text substitution on the REAL hook
# body, and must go red on EXACTLY its declared set:
#
#   m1  perl in-place flag class back to [a-zA-Z] (`-0pi` escapes again).
#   m2  the inline-code rule (R_INLINE) neutralised.
#   m3  the interpreter-heredoc rule (R_HEREDOC) neutralised.
#   m4  the out-of-repo script rule neutralised.
#   m5  bare `cp(` put back in WRITE_API.
#   m6  `$TMPDIR` / same-command `NAME=value` expansion removed.
#   m7  the in-repo script exemption removed.
#   m8  the "script names this repo" requirement removed.
#   m9  the 256 KB script size cap removed.
#   m10 the `cd <temp>` exemption removed.
#   m11 the separator classes reverted to `\s*` / `\S*` (they ran past `;`
#       and newlines: `SC=x; python3 "$SC/a.py"` read as ONE command).
#   m12 R_INLINE's flag loop back to `--?[\w=.-]+`, uncapped: exponential.
#   m13 the POS assignment prefix crosses newlines again (`\s+`).
#   m14 R_HEREDOC's word loop crosses newlines again.
#   m15 the /tmp/claude-<uid> $TMPDIR candidates removed.
#   m16 bare `rename(` put back in WRITE_API (`df.rename` fires).
#   m17 `File.open(` mode read anywhere in the call again (`'app.rb'`).
#   m18 `cd " "` (a quoted temp dir, blanked) no longer a temp cd.
#   m19 a `cd` AFTER the interpreter counts again.
#   m20 only the first script of a command looked at.
#   m21 multi-line quoted text no longer blanked before the script scan.
#   m22 the script opened blocking: a FIFO hangs the hook.
#   m23 "names this repo" back to a substring test (`<top>-tools`).
#   m24 `~` expanded inside quotes too.
#   m25 the unresolved-`$` guard removed.
#   m26 the script path no longer realpath'd.
#   m27 the 4096-char cap on an expanded variable removed.
#   m28 the script scan's quote blanking back to pairing ANY two quotes, with
#       no `#` comment pass (an apostrophe in a comment hid a script call).
#   m29 an unset or empty $TMPDIR tried again, and an unresolved `$` stops the
#       candidate loop again instead of moving to the next candidate.
#   m30 `cd <temp> || exit` no longer a temp cd.
#   m31 the Python string prefix (`f' '`) refused by the blanked-temp test.
#   m32 `rmdir` dropped from the fs./Sync write calls.
#   m33 `open (` with a blank before the paren no longer a call.
#
# THE EXACT COMMANDS THAT MAKE THIS PROBE GO RED:
#
#   bash checks/require-apex-probe.sh --mutants        # all of them, graded
#   bash checks/require-apex-probe.sh --mutant m4      # one, raw red output
#   bash checks/require-apex-probe.sh old-hook.js      # e.g. HEAD's version
#
# Standalone, like checks/null-result-gate-probe.sh: NOT wired into
# `nix flake check`, because it shells out to `nix eval` to lift the hook body
# out of hooks.nix, and builds git repos and processes a sandboxed check build
# does not provide.
#
# usage: require-apex-probe.sh [hook.js]
#        require-apex-probe.sh --mutants
#        require-apex-probe.sh --mutant m1..m33

set -euo pipefail

# Timing reads $EPOCHREALTIME, which bash grew in 5.0. macOS's /bin/bash is
# 3.2: there it is unset, and every duration would silently read as 0.
if [ -z "${EPOCHREALTIME:-}" ]; then
  echo "probe: bash >= 5 required (\$EPOCHREALTIME is unset in ${BASH_VERSION:-this shell})" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$REPO_ROOT/checks/$(basename "${BASH_SOURCE[0]}")"

ALL_MUTANTS="m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 m15 m16 m17 m18 m19 m20 m21 m22 m23 m24 m25 m26 m27 m28 m29 m30 m31 m32 m33"

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
WORK=$(mktemp -d "${TMPDIR:-/tmp}/require-apex-probe.XXXXXX") || {
  echo "probe: cannot create a work directory under ${TMPDIR:-/tmp}" >&2
  exit 2
}
if [ -z "${WORK:-}" ] || [ ! -d "$WORK" ]; then
  echo "probe: work directory is empty or missing — refusing to run" >&2
  exit 2
fi
SBX=""
cleanup() {
  local d
  for d in "${WORK:-}" "${SBX:-}"; do
    if [ -n "$d" ] && [ -d "$d" ]; then
      chmod -R u+w "$d" 2> /dev/null || true
      rm -rf "$d"
    fi
  done
}
trap cleanup EXIT

# Never write into, or grade, this repository by accident — and never let the
# fixture repo sit inside another work tree, or `git rev-parse` answers for it.
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
  echo "probe: git not found — the hook's repo test needs it" >&2
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
    "(import \"$HOOKS_NIX\" { graphifyReindexPkg = \"/nix/store/x\"; vaultSnapshotPkg = \"/nix/store/y\"; }).hookRequireApex" \
    > "$dest" 2> "$WORK/extract.err" || {
    echo "probe: extracting hookRequireApex from hooks.nix failed" >&2
    head -c 800 "$WORK/extract.err" >&2
    exit 2
  }
  [ -s "$dest" ] || {
    echo "probe: the extracted hook body is empty — refusing to report" >&2
    exit 2
  }
}

ORIG="$WORK/require-apex.js"
if [ -n "$SUT" ]; then
  SUT="$(abspath "$SUT")"
  [ -f "$SUT" ] && [ -r "$SUT" ] || {
    echo "probe: script under test not found or not readable: $SUT" >&2
    exit 2
  }
else
  extract_hook "$ORIG"
  SUT="$ORIG"
fi

# ==============================================================================
# MUTANT DRIVER
# ==============================================================================
#
# Each mutant is a LITERAL substitution (no regex in the pattern) on the REAL
# hook body, written into $WORK, proven to have applied (the replacement text
# is found), proven to differ from the original, syntax-checked, then graded by
# re-running this same script against it. Nothing is ever written into the
# repository. The runtime-case count is read back from the child run.

M1_EXPECT="perl-0pi-in-place"
M2_EXPECT="cd-temp-after-inline-write node-e-rmdirsync node-e-writefilesync python-c-open-space python-c-writes-package-json ruby-e-file-write"
M3_EXPECT="heredoc-quoted-hash-body"
M4_EXPECT="comment-apostrophe-then-script multi-script-second-writes script-dollar-brace-var script-newline-var script-npx-tsx script-out-of-repo-plain script-out-of-repo-quoted script-same-command-var script-single-quoted script-tilde-unquoted script-tmpdir-empty script-tmpdir-split script-tmpdir-unset script-tmpdir-var"
M5_EXPECT="cp-helper-not-a-write"
M6_EXPECT="script-dollar-brace-var script-newline-var script-same-command-var script-tmpdir-empty script-tmpdir-split script-tmpdir-unset script-tmpdir-var"
M7_EXPECT="script-in-repo script-in-repo-via-symlink"
M8_EXPECT="script-names-sibling-prefix script-out-of-repo-no-repo-path"
M9_EXPECT="script-over-256k"
M10_EXPECT="cd-quoted-temp-then-inline-write cd-temp-or-exit-then-inline-write cd-temp-then-inline-write"
M11_EXPECT="bounded-64k-separators script-same-command-var"
M12_EXPECT="flags-28-fast"
M13_EXPECT="script-newline-var"
M14_EXPECT="dollar-paren-node-64k-fast heredoc-after-newline-not-interp node-newlines-64k-fast"
M15_EXPECT="script-tmpdir-empty script-tmpdir-split script-tmpdir-unset"
M16_EXPECT="inline-df-rename-read-only"
M17_EXPECT="ruby-file-open-read"
M18_EXPECT="cd-quoted-temp-then-inline-write cd-temp-or-exit-then-inline-write"
M19_EXPECT="cd-temp-after-inline-write"
M20_EXPECT="multi-script-second-writes"
M21_EXPECT="multiline-quoted-commit-msg"
M22_EXPECT="script-fifo-nonblocking"
M23_EXPECT="script-names-sibling-prefix"
M24_EXPECT="script-tilde-quoted-not-expanded"
M25_EXPECT="dollar-guard-dotdot"
M26_EXPECT="script-in-repo-via-symlink"
M27_EXPECT="assign-over-4096-dropped"
M28_EXPECT="comment-apostrophe-then-script"
M29_EXPECT="script-tmpdir-empty script-tmpdir-unset"
M30_EXPECT="cd-temp-or-exit-then-inline-write"
M31_EXPECT="inline-fstring-temp-write"
M32_EXPECT="node-e-rmdirsync"
M33_EXPECT="python-c-open-space"

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
    m1) from='\s-\w*i\b/' to='\s-[a-zA-Z]*i\b/' ;;
    m2) from='const R_INLINE = new RegExp(' to='const R_INLINE = /(?!)/; const R_INLINE_OFF = new RegExp(' ;;
    m3) from='const R_HEREDOC = new RegExp(' to='const R_HEREDOC = /(?!)/; const R_HEREDOC_OFF = new RegExp(' ;;
    m4) from='const R_SCRIPT_RAW = new RegExp(' to='const R_SCRIPT_RAW = /(?!)/g; const R_SCRIPT_OFF = new RegExp(' ;;
    m5) from='|\bcreateWriteStream|' to='|\bcp|\bcreateWriteStream|' ;;
    m6) from='const expand = s => s.replace(' to='const expand = s => s; const expandOff = s => s.replace(' ;;
    m7) from='if (real === top || real.startsWith(top + "/")) continue;' to='if (false) continue;' ;;
    m8) from='WRITE_API.test(src) && NAMES_TOP.test(src)' to='WRITE_API.test(src) && true' ;;
    m9) from='st.size > 262144' to='st.size > 1e12' ;;
    m10) from='&& !CD_TEMP.test(noTemp.slice(0, im.index + 1))' to='&& !false' ;;
    m11)
      # Two substitutions: separator blank `[ \t]*` -> `\s*`, and the
      # path/value class -> `\S*`.
      lit_sub "$ORIG" "$dest.tmp" '[\\n|;&(`][ \\t]*' '[\\n|;&(`]\\s*'
      from='[^\\s;&|(`]*' to='\\S*'
      lit_sub "$dest.tmp" "$dest" "$from" "$to"
      rm -f "$dest.tmp"
      ;;
    m12) from='"(?:" + WS + "-[\\w=.-]+){0,16}?"' to='"(?:" + WS + "--?[\\w=.-]+)*?"' ;;
    m13) from='\\w+=[^\\s;&|(`]*[ \\t]+){0,16}' to='\\w+=[^\\s;&|(`]*\\s+){0,16}' ;;
    m14) from='"(?:[ \\t]+[^\\s<|;&(`]+){0,16}?[ \\t]*<<' to='"(?:\\s+[^\\s<|;&]+)*?\\s*<<' ;;
    m15) from='if (uid !== null) tmpdirs.push(' to='if (false) tmpdirs.push(' ;;
    m16) from='|\bcreateWriteStream|' to='|\brename|\bcreateWriteStream|' ;;
    m17) from='|\bFileUtils\.|' to='|\bFile\.open\([^)]*['"'"'"][wa]|\bFileUtils\.|' ;;
    m18) from='cd[ \t]*(?:"[ \t]*"[ \t]*|'"'"'[ \t]*'"'"'[ \t]*)?(?=' to='cd[ \t]*(?=' ;;
    m19) from='!CD_TEMP.test(noTemp.slice(0, im.index + 1))' to='!CD_TEMP.test(noTemp)' ;;
    m20) from='tries++ < 4' to='tries++ < 1' ;;
    m21) from='const scan = command.replace(' to='const scan = command; const scanOff = command.replace(' ;;
    m22) from='fs.constants.O_RDONLY | fs.constants.O_NONBLOCK' to='fs.constants.O_RDONLY' ;;
    m23) from='+ "(?![\\w.-])")' to='+ "")' ;;
    m24) from='if (m[3] !== undefined && (p === "~"' to='if ((p === "~"' ;;
    m25) from='if (!lit && /[$`]/.test(p)) continue;' to='if (false) continue;' ;;
    m26) from='const real = fs.realpathSync(s);' to='const real = s;' ;;
    m27) from='if (v.length <= 4096) vars[a[1]] = v;' to='if (true) vars[a[1]] = v;' ;;
    m28) from='/(^|[\s=(;&|])('"'"'[^'"'"']*'"'"'|"[^"]*"|#[^\n]*)/g' to='/()('"'"'[^'"'"']*'"'"'|"[^"]*")/g' ;;
    m29)
      # Two substitutions: the empty-candidate filter off, and the `$` guard
      # back to `break`. Either one alone still reaches the fallback.
      lit_sub "$ORIG" "$dest.tmp" 'const tdCands = tmpdirs.filter(Boolean);' 'const tdCands = tmpdirs;'
      from='if (!lit && /[$`]/.test(p)) continue;' to='if (!lit && /[$`]/.test(p)) break;'
      lit_sub "$dest.tmp" "$dest" "$from" "$to"
      rm -f "$dest.tmp"
      ;;
    m30) from='(?=&&|\|\||;|\n|$)' to='(?=&&|;|\n|$)' ;;
    m31) from='[fFrRbBu]{0,2}' to='' ;;
    m32) from='rm|rmdir|' to='rm|' ;;
    m33) from='\bopen\s{0,8}\(' to='\bopen\(' ;;
  esac
  if [ "$which" != "m11" ] && [ "$which" != "m29" ]; then
    grep -qF -- "$from" "$ORIG" || {
      echo "probe: $which did not apply — the text it replaces moved (looked for: $from)" >&2
      return 1
    }
    lit_sub "$ORIG" "$dest" "$from" "$to"
  fi
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

  echo "=== require-apex mutants (built from the live hook, in $WORK) ==="
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

REPO="$WORK/repo"   # the repo the hook guards (cwd of most cases)
EXT="$WORK/ext"     # scripts OUTSIDE that repo
TMPD="$WORK/tmpd"   # the $TMPDIR the hook sees
HOMED="$WORK/home"  # the $HOME the hook sees
NOGIT="$WORK/nogit" # a cwd outside any work tree
BIN="$WORK/bin"     # the git shim
mkdir -p "$REPO/tools" "$EXT" "$TMPD" "$HOMED" "$NOGIT" "$BIN"

"$GIT" -C "$REPO" init -q
TOP="$("$GIT" -C "$REPO" rev-parse --show-toplevel)"
[ -n "$TOP" ] && [ -d "$TOP" ] || {
  echo "probe: the fixture repo has no toplevel — refusing to run" >&2
  exit 2
}
# The work dir must not itself sit in a work tree: NOGIT would then be "in git".
if "$GIT" -C "$NOGIT" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "probe: $NOGIT is inside a git work tree — the outside-git case would lie" >&2
  exit 2
fi

# The sandbox's $TMPDIR, which the hook's own $TMPDIR is not.
UIDN="$(id -u)"
CLTMP="/tmp/claude-$UIDN"
mkdir -p "$CLTMP" && SBX=$(mktemp -d "$CLTMP/require-apex-probe-sbx.XXXXXX") || {
  echo "probe: cannot create a fixture under $CLTMP" >&2
  exit 2
}
SBX_REL="${SBX#"$CLTMP"/}"

GIT_LOG="$WORK/git.log"
cat > "$BIN/git" << SHIM
#!/bin/sh
printf '%s\n' "\$*" >> "$GIT_LOG"
exec "$GIT" "\$@"
SHIM
chmod +x "$BIN/git"

T_NOAPEX="$WORK/transcript-noapex.jsonl"
T_APEX="$WORK/transcript-apex.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"please edit the thing"}}' > "$T_NOAPEX"
{
  cat "$T_NOAPEX"
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"apex"}}]}}'
} > "$T_APEX"

# Out-of-repo scripts. Each is the smallest source that separates one rule.
printf "import json\nopen('%s/package.json', 'w').write('{}')\n" "$TOP" > "$EXT/edit.py"
cp "$EXT/edit.py" "$TMPD/edit.py"
cp "$EXT/edit.py" "$HOMED/edit.py"
cp "$EXT/edit.py" "$SBX/edit.py"
printf "import { writeFileSync } from 'fs';\nwriteFileSync('%s/src/a.ts', '');\n" "$TOP" > "$EXT/edit.ts"
printf "open('/elsewhere/out.txt', 'w').write('x')\n" > "$EXT/noname.py"
printf "print(open('%s/package.json').read())\n" "$TOP" > "$EXT/nowrite.py"
printf "def cp(a, b):\n    print(a, b)\ncp('%s/a', '%s/b')\n" "$TOP" "$TOP" > "$EXT/cphelper.py"
printf "open('%s-tools/out.txt', 'w').write('x')\n" "$TOP" > "$EXT/sibling.py"
{
  cat "$EXT/edit.py"
  head -c 300000 /dev/zero | tr '\0' '#'
  printf '\n'
} > "$EXT/big.py"
cp "$EXT/edit.py" "$REPO/tools/edit.py"
mkfifo "$EXT/fifo.py"
ln -s "$REPO" "$WORK/repolink"

# 64 KB on ONE line, dense with separators: under the regex classes as first
# measured, every `;` restarted a scan to the end of the line.
LONG="$(head -c 13107 /dev/zero | tr '\0' 'x' | sed 's/x/node;/g')"
# The adversarial shapes the backtracking review timed.
FLAGS28="python3$(printf ' --a%.0s' $(seq 28))"
NODE_NL="$(head -c 13107 /dev/zero | tr '\0' 'x' | sed 's/x/node\\n/g')"
NODE_NL="$(printf '%b' "$NODE_NL")"
DOLLAR_NODE="$(head -c 9362 /dev/zero | tr '\0' 'x' | sed 's/x/$(node /g')"
ASSIGN_NL="$(printf 'a=b\\n%.0s' $(seq 16384))"
ASSIGN_NL="$(printf '%b' "$ASSIGN_NL")python3 \"\$a/edit.py\""
# A value that doubles 28 times: 2^28 chars unless the 4096 cap drops it.
DOUBLING="A=xy$(printf '; A=$A$A%.0s' $(seq 28)); python3 \"\$A/edit.py\""
LONG_VAL="A=$EXT$(printf '/.%.0s' $(seq 2500)); python3 \"\$A/edit.py\""

# ==============================================================================
# RUNNER
# ==============================================================================

PASS=0
FAIL=0
NCASES=0

fail_case() {
  FAIL=$((FAIL + 1))
  printf 'FAIL  %-34s %s\n' "$1" "$2"
}
ok_case() {
  PASS=$((PASS + 1))
  printf 'ok    %-34s %s\n' "$1" "$2"
}

now_ms() { printf '%s\n' "${EPOCHREALTIME/[.,]/}" | cut -c1-13; }

# check <label> <deny|pass|pass-nogit|pass-fast> <cwd> <transcript> <command>
#   deny       exactly one JSON object with permissionDecision "deny"
#   pass       stdout empty, byte for byte
#   pass-nogit pass, AND the git shim recorded no call at all
#   pass-fast  pass, AND the run finished within 1000 ms
check() {
  local label="$1" kind="$2" cwd="$3" tr="$4" cmd="$5" pay out err rc
  NCASES=$((NCASES + 1))
  pay="$WORK/out/$label.json"
  out="$WORK/out/$label.stdout"
  err="$WORK/out/$label.stderr"
  "$JQ" -n --arg c "$cmd" --arg t "$tr" \
    '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},transcript_path:$t,permission_mode:"bypassPermissions"}' \
    > "$pay"
  run_raw "$cwd" "$pay" "$out" "$err"
  rc=$RUN_RC
  grade "$label" "$kind" "$rc" "$out" "$err"
}

RUN_RC=0
RUN_MS=0
# The hook's $TMPDIR: `set` (the fixture dir), `unset`, or `empty` (TMPDIR=).
TMPDIR_MODE=set
run_raw() { # run_raw <cwd> <payload> <stdout> <stderr>
  : > "$GIT_LOG"
  local t0 t1 tenv
  case "$TMPDIR_MODE" in
    unset) tenv=(-u TMPDIR) ;;
    empty) tenv=(TMPDIR=) ;;
    *) tenv=(TMPDIR="$TMPD") ;;
  esac
  t0="$(now_ms)"
  set +e
  # The alarm outlives the exec: SIGALRM at 10 s ends node with status 142.
  (cd "$1" && env "${tenv[@]}" HOME="$HOMED" PATH="$BIN:$PATH" \
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
      pass | pass-nogit | pass-fast)
        if [ -s "$out" ]; then
          why="stdout: expected empty, got $(head -c 200 "$out")"
        elif [ "$kind" = "pass-nogit" ] && [ -s "$GIT_LOG" ]; then
          why="git was spawned: $(tr '\n' ';' < "$GIT_LOG" | head -c 200)"
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

echo "=== require-apex probe ==="
echo "    hook under test: $SUT"
echo

HD_HASH="$(printf "python3 - <<'PY'\n# rewrite the manifest\nopen('package.json', 'w').write('{}')\nPY")"
GIT_HD="$(printf "git commit -F - <<'EOF'\n# not an interpreter\nEOF")"
NL_HD="$(printf "python3 --version\ngit commit -F - <<'EOF'\n# fix open('a', 'w') handling\nEOF")"
NL_VAR="$(printf 'SC=%s\npython3 "$SC/edit.py"' "$EXT")"
ML_MSG="$(printf "git commit -m 'subject\npython3 %s/edit.py was run by hand'" "$EXT")"
CMT_APOS="$(printf "# don't touch\npython3 %s/edit.py 'x'" "$EXT")"

# --- MUST DENY: the shell door (control) -------------------------------------
check ctl-redirect deny "$REPO" "$T_NOAPEX" 'echo x > src/a.ts'
check perl-0pi-in-place deny "$REPO" "$T_NOAPEX" "perl -0pi -e 's/a\\nb/c/s' src/x.ts"
# --- MUST DENY: interpreter inline code and heredoc --------------------------
check heredoc-quoted-hash-body deny "$REPO" "$T_NOAPEX" "$HD_HASH"
check python-c-writes-package-json deny "$REPO" "$T_NOAPEX" "python3 -c \"import json; open('package.json', 'w').write(json.dumps({}))\""
check node-e-writefilesync deny "$REPO" "$T_NOAPEX" "node -e \"require('fs').writeFileSync('package.json', '{}')\""
check ruby-e-file-write deny "$REPO" "$T_NOAPEX" "ruby -e \"File.write('a.rb', 'x')\""
check cd-temp-after-inline-write deny "$REPO" "$T_NOAPEX" "python3 -c \"open('x', 'w').write('1')\" && cd $TMPD"
# --- MUST DENY: an out-of-repo script that writes and names this repo --------
check script-out-of-repo-plain deny "$REPO" "$T_NOAPEX" "python3 $EXT/edit.py"
check script-out-of-repo-quoted deny "$REPO" "$T_NOAPEX" "python3 \"$EXT/edit.py\" --dry-run=no"
check script-single-quoted deny "$REPO" "$T_NOAPEX" "python3 '$EXT/edit.py'"
check script-npx-tsx deny "$REPO" "$T_NOAPEX" "npx tsx $EXT/edit.ts"
check script-tmpdir-var deny "$REPO" "$T_NOAPEX" 'python3 "$TMPDIR/edit.py"'
check script-tmpdir-split deny "$REPO" "$T_NOAPEX" "python3 \"\$TMPDIR/$SBX_REL/edit.py\""
check script-same-command-var deny "$REPO" "$T_NOAPEX" "SC=$EXT; python3 \"\$SC/edit.py\""
check script-newline-var deny "$REPO" "$T_NOAPEX" "$NL_VAR"
check script-dollar-brace-var deny "$REPO" "$T_NOAPEX" "SC=\"$EXT\" && python3 \${SC}/edit.py"
check script-tilde-unquoted deny "$REPO" "$T_NOAPEX" 'python3 ~/edit.py'
check multi-script-second-writes deny "$REPO" "$T_NOAPEX" "python3 $EXT/noname.py; python3 $EXT/edit.py"
# The comment's apostrophe must not pair with the quote after the script.
check comment-apostrophe-then-script deny "$REPO" "$T_NOAPEX" "$CMT_APOS"
# The hook itself without a $TMPDIR: the sandbox candidates still resolve.
TMPDIR_MODE=unset
check script-tmpdir-unset deny "$REPO" "$T_NOAPEX" "python3 \"\$TMPDIR/$SBX_REL/edit.py\""
TMPDIR_MODE=empty
check script-tmpdir-empty deny "$REPO" "$T_NOAPEX" "python3 \"\$TMPDIR/$SBX_REL/edit.py\""
TMPDIR_MODE=set
check python-c-open-space deny "$REPO" "$T_NOAPEX" "python3 -c \"open ('a', 'w').write('1')\""
check node-e-rmdirsync deny "$REPO" "$T_NOAPEX" "node -e \"require('fs').rmdirSync('build')\""
# --- MUST PASS: read-only and module calls -----------------------------------
check python-m-json-tool pass "$REPO" "$T_NOAPEX" 'python3 -m json.tool package.json'
check node-version pass "$REPO" "$T_NOAPEX" 'node --version'
check python-c-json-load-read pass "$REPO" "$T_NOAPEX" "python3 -c \"import json; print(json.load(open('package.json')))\""
check inline-df-rename-read-only pass "$REPO" "$T_NOAPEX" "python3 -c \"import pandas as pd; print(pd.read_csv('a.csv').rename(columns={'a': 'b'}))\""
check ruby-file-open-read pass "$REPO" "$T_NOAPEX" "ruby -e \"puts File.open('app.rb').read\""
check cd-temp-then-inline-write pass "$REPO" "$T_NOAPEX" "cd $TMPD && python3 -c \"open('x', 'w').write('1')\""
check cd-quoted-temp-then-inline-write pass "$REPO" "$T_NOAPEX" "cd \"\$TMPDIR\" && python3 -c \"open('x', 'w').write('1')\""
check cd-temp-or-exit-then-inline-write pass "$REPO" "$T_NOAPEX" "cd \"\$TMPDIR\" || exit 1; python3 -c \"open('x','w')\""
check inline-fstring-temp-write pass "$REPO" "$T_NOAPEX" "python3 -c \"open(f'\$TMPDIR/x','w').write('1')\""
check git-commit-heredoc-hash-body pass "$REPO" "$T_NOAPEX" "$GIT_HD"
check heredoc-after-newline-not-interp pass "$REPO" "$T_NOAPEX" "$NL_HD"
check multiline-quoted-commit-msg pass "$REPO" "$T_NOAPEX" "$ML_MSG"
check no-shape-spawns-no-git pass-nogit "$REPO" "$T_NOAPEX" 'ls -la'
# --- MUST PASS: scripts the rule must leave alone ----------------------------
check script-in-repo pass "$REPO" "$T_NOAPEX" 'python3 tools/edit.py'
check script-in-repo-via-symlink pass "$REPO" "$T_NOAPEX" "python3 $WORK/repolink/tools/edit.py"
check script-out-of-repo-no-repo-path pass "$REPO" "$T_NOAPEX" "python3 $EXT/noname.py"
check script-out-of-repo-no-write-api pass "$REPO" "$T_NOAPEX" "python3 $EXT/nowrite.py"
check script-names-sibling-prefix pass "$REPO" "$T_NOAPEX" "python3 $EXT/sibling.py"
check cp-helper-not-a-write pass "$REPO" "$T_NOAPEX" "python3 $EXT/cphelper.py"
check script-over-256k pass "$REPO" "$T_NOAPEX" "python3 $EXT/big.py"
check script-missing pass "$REPO" "$T_NOAPEX" "python3 $EXT/missing.py"
check script-fifo-nonblocking pass-fast "$REPO" "$T_NOAPEX" "python3 $EXT/fifo.py"
check script-tilde-quoted-not-expanded pass "$REPO" "$T_NOAPEX" 'python3 "~/edit.py"'
check unresolved-var-known-gap pass "$REPO" "$T_NOAPEX" 'python3 "$OTHER/edit.py"'
# Resolved lexically, `$OTHER/../../ext` IS the ext dir: only the `$` guard
# stops an unexpanded name from being read as a directory.
check dollar-guard-dotdot pass "$REPO" "$T_NOAPEX" 'python3 "$OTHER/../../ext/edit.py"'
# Over 4096 chars a value is dropped, so `$A` stays unresolved — though this
# one, `/.` x2500 after the ext dir, would normalise to a real script.
check assign-over-4096-dropped pass "$REPO" "$T_NOAPEX" "$LONG_VAL"
# --- MUST PASS: the gate's own exits -----------------------------------------
check apex-already-ran pass "$REPO" "$T_APEX" "python3 -c \"open('package.json', 'w').write('{}')\""
check apex-already-ran-script pass "$REPO" "$T_APEX" "python3 $EXT/edit.py"
check outside-git-inline pass "$NOGIT" "$T_NOAPEX" "python3 -c \"open('package.json', 'w').write('{}')\""
check outside-git-script pass "$NOGIT" "$T_NOAPEX" "python3 $EXT/edit.py"
# --- MUST PASS FAST: adversarial shapes --------------------------------------
check bounded-64k-separators pass-fast "$REPO" "$T_NOAPEX" "$LONG"
check flags-28-fast pass-fast "$REPO" "$T_NOAPEX" "$FLAGS28"
check node-newlines-64k-fast pass-fast "$REPO" "$T_NOAPEX" "$NODE_NL"
check dollar-paren-node-64k-fast pass-fast "$REPO" "$T_NOAPEX" "$DOLLAR_NODE"
check assign-newlines-16k-fast pass-fast "$REPO" "$T_NOAPEX" "$ASSIGN_NL"
check assign-doubling-fast pass-fast "$REPO" "$T_NOAPEX" "$DOUBLING"

# Malformed JSON: no payload builder, the raw bytes are the case.
NCASES=$((NCASES + 1))
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"python3 -c ' > "$WORK/out/malformed-json.json"
run_raw "$REPO" "$WORK/out/malformed-json.json" "$WORK/out/malformed-json.stdout" "$WORK/out/malformed-json.stderr"
grade malformed-json pass "$RUN_RC" "$WORK/out/malformed-json.stdout" "$WORK/out/malformed-json.stderr"

# Derived, never declared: the mutant driver reads this back.
echo "runtime-cases: $NCASES"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
