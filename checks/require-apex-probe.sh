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
# bound the run at 1000 ms; the fast-* shapes (64 KB words, newline runs,
# `$(` runs, `/.claude/projects/` repeats, `sed ` runs, codex flag runs, and
# one just under the 256 K command cap, a 13 000-`cd` chain, a 64 KB run of
# `codex exec` calls, a `$B$B…` expansion bomb, a run of `"$(` after a codex
# call) measure under 200 ms against
# that 1000 ms bound; the non-codex ones took 1.7 s to over 30 s before the
# hardening pass.
#
# `$PWD` follows the `cd`s before the script (`script-cd-pwd`): /bin/sh sets
# PWD on every `cd`, so the hook's inherited one is never what the call sees.
#
# THE CODEX EXEMPTION IS A WHITELIST. Every `codex-cd-*` / `codex-subshell-*`
# deny case breaks exactly one of its conditions (top-level cd, resolved,
# existing, under a temp root, not a repo, no `-C`, no danger flag).
# Every fixture of this probe lives under a temp root, so the non-temp
# directory is `/usr`.
#
# KNOWN GAPS, asserted as PASS so they cannot be mistaken for coverage:
# `unresolved-var-known-gap` (a script path in a `$VAR` neither set in the
# command nor in the hook's environment, run with `-u OTHER`: the same blind
# spot as a loop var, `read`, `$1` or `$(...)`)
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
#   m27 the 4096-char caps on a value and on an expansion both removed.
#   m28 the script scan's quote blanking back to pairing ANY two quotes, with
#       no `#` comment pass (an apostrophe in a comment hid a script call).
#   m29 an unset or empty $TMPDIR tried again, and an unresolved `$` stops the
#       candidate loop again instead of moving to the next candidate.
#   m30 `cd <temp> || exit` no longer a temp cd.
#   m31 the Python string prefix (`f' '`) refused by the blanked-temp test.
#   m32 `rmdir` dropped from the fs./Sync write calls.
#   m33 `open (` with a blank before the paren no longer a call.
#   m34 the noTemp word-start lookbehind removed (a 64 KB word is quadratic).
#   m35 the memory-dir class admits `/` again (`/.claude/projects/` nests at 256 K).
#   m36 AT_CMD blanks back to `\s*` (a newline run is quadratic).
#   m37 the `sed -i` gap uncapped again (`sed ` x16 384).
#   m38 the 256 K command cap removed.
#   m39 the environment fallback for a name the command never sets removed.
#   m40 a relative script path read from the cwd again, not after each `cd`.
#   m41 the separate-argument flags (`-W ignore`, `-r esm`) read as plain flags.
#   m42 the quoted-head, bare-tail script path (`"$TMPDIR"/e.py`) not read.
#   m43 the `codex exec` gate (R_CODEX) neutralised.
#   m44 a widening flag or `-c sandbox...` no longer undoes `-s read-only`.
#   m45 quoted prompt text no longer blanked ("use -s read-only" whitelists).
#   m46 `codex exec --help` no longer exempt.
#   m47 the `-C <dir>` repo no longer graded.
#   m48 `$PWD` read from the hook's environment, not from the `cd` fold.
#   m49 the dir the `cd`s lead to no longer graded (only the session cwd).
#   m50 a danger flag no longer voids the temp-dir exemption.
#   m51 a `-c sandbox...` key no longer DANGER (widens read-only only).
#   m52 `-p <profile>` no longer DANGER.
#   m53 option values read from the blanked text again (`-s "read-only"`).
#   m54 a `cd` inside `(...)` / `$(...)` counts as moving the shell again.
#   m55 `cd -` / an unresolved `cd` skipped, not voiding the exemption.
#   m56 the exempt dir no longer has to exist.
#   m57 the exempt dir no longer has to be under a temp root.
#   m58 the exempt dir may be a git repo (every fixture sits under a temp
#       root, so this test alone keeps each in-repo call from the exemption).
#   m59 `-C` no longer voids the exemption.
#   m60 a `cd` word the fold cannot read (`then cd x`) no longer voids it.
#   m61 a backslash-newline cuts the call again.
#   m62 `--yolo` and `--add-dir` no longer DANGER.
#   m63 attached short values (`-sX`, `-CX`) no longer read.
#   m64 `$(...)` inside double quotes blanked again.
#   m65 every `codex` word counts toward the 4-call cap again.
#   m66 calls past the cap no longer graded at the session cwd.
#   m67 the 64-`cd` fold cap removed (`;cd a` x13 000 is quadratic).
#   m68 the 4096-char expansion budget removed (`$B$B…` bomb).
#   m69 a same-command value over 4096 chars falls back to the environment.
#   m70 `-m` taken as a separate-argument flag (SEP_ARG).
#   m71 `-s read-only` never passes.
#   m72 a second `-s <other>` no longer undoes `-s read-only`.
#   m73 the `$(` span inside double quotes back to a first-paren stop, and
#       an unclosed span blanked (`"$(codex exec "fix (this) now")"`).
#   m74 an unclosed `$(` span blanked again instead of left visible.
#   m75 a bare `--` no longer ends the options (`-- -s read-only` whitelists).
#   m76 a `-c` key after a leading blank (`' sandbox_mode=...'`) read as "".
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
#        require-apex-probe.sh --mutant m1..m76

set -euo pipefail

# Timing reads $EPOCHREALTIME, which bash grew in 5.0. macOS's /bin/bash is
# 3.2: there it is unset, and every duration would silently read as 0.
if [ -z "${EPOCHREALTIME:-}" ]; then
  echo "probe: bash >= 5 required (\$EPOCHREALTIME is unset in ${BASH_VERSION:-this shell})" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$REPO_ROOT/checks/$(basename "${BASH_SOURCE[0]}")"

ALL_MUTANTS="m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 m15 m16 m17 m18 m19 m20 m21 m22 m23 m24 m25 m26 m27 m28 m29 m30 m31 m32 m33 m34 m35 m36 m37 m38 m39 m40 m41 m42 m43 m44 m45 m46 m47 m48 m49 m50 m51 m52 m53 m54 m55 m56 m57 m58 m59 m60 m61 m62 m63 m64 m65 m66 m67 m68 m69 m70 m71 m72 m73 m74 m75 m76"

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
M2_EXPECT="cd-temp-after-inline-write node-e-rmdirsync node-e-writefilesync node-r-then-e-write python-W-ignore-c-write python-c-open-space python-c-writes-package-json ruby-e-file-write"
M3_EXPECT="heredoc-quoted-hash-body"
M4_EXPECT="comment-apostrophe-then-script multi-script-second-writes script-W-ignore script-cd-chain script-cd-relative script-dollar-brace-var script-newline-var script-npx-tsx script-out-of-repo-plain script-out-of-repo-quoted script-env-home script-cd-pwd script-quoted-var-bare-tail script-same-command-var script-single-quoted script-tilde-unquoted script-tmpdir-empty script-tmpdir-split script-tmpdir-unset script-tmpdir-var"
M5_EXPECT="cp-helper-not-a-write"
M6_EXPECT="script-dollar-brace-var script-env-home script-newline-var script-cd-pwd script-quoted-var-bare-tail script-same-command-var script-tmpdir-empty script-tmpdir-split script-tmpdir-unset script-tmpdir-var"
M7_EXPECT="cd-subdir-in-repo script-in-repo script-in-repo-via-symlink"
M8_EXPECT="cd-relative-noname script-names-sibling-prefix script-out-of-repo-no-repo-path"
M9_EXPECT="script-over-256k"
M10_EXPECT="cd-quoted-temp-then-inline-write cd-temp-or-exit-then-inline-write cd-temp-then-inline-write"
M11_EXPECT="assign-over-4096-env-unresolved bounded-64k-separators fast-64k-dollar-paren fast-64k-newlines script-same-command-var fast-64k-dq-subst"
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
M27_EXPECT="assign-over-4096-dropped assign-over-4096-env-unresolved fast-expand-bomb"
M28_EXPECT="comment-apostrophe-then-script"
M29_EXPECT="script-tmpdir-empty script-tmpdir-unset"
M30_EXPECT="cd-temp-or-exit-then-inline-write"
M31_EXPECT="inline-fstring-temp-write"
M32_EXPECT="node-e-rmdirsync"
M33_EXPECT="python-c-open-space"
M34_EXPECT="fast-64k-claude-projects fast-64k-dollar-paren fast-64k-word fast-cap-claude-projects fast-expand-bomb"
M35_EXPECT="fast-cap-claude-projects"
M36_EXPECT="fast-64k-newlines"
M37_EXPECT="fast-64k-sed"
M38_EXPECT="huge-command-denied"
M39_EXPECT="script-env-home"
M40_EXPECT="script-cd-chain script-cd-relative"
M41_EXPECT="node-r-then-e-write python-W-ignore-c-write script-W-ignore"
M42_EXPECT="script-quoted-var-bare-tail"
M43_EXPECT="codex-C-repo-from-nogit codex-cd-repo-subdir codex-cd-temp-C-repo codex-cd-temp-danger codex-cd-temp-config-danger codex-cd-temp-profile-danger codex-after-separator codex-e-alias codex-exec-default codex-read-only-in-prompt codex-resume-default codex-ro-bypass codex-ro-config-sandbox codex-ro-profile codex-workspace-write codex-C-nonrepo-from-repo codex-cd-temp-C-nonrepo codex-subshell-cd codex-dollar-cd codex-cd-missing-dir codex-cd-dash codex-cd-nontemp codex-cd-temp-gitrepo codex-unread-cd codex-add-dir codex-yolo-temp codex-quoted-danger-temp codex-C-quoted-pwd-then-c codex-C-quoted-repo-from-nogit codex-attached-C codex-backslash-newline codex-ro-then-bsnl-danger codex-ro-then-ww codex-subst-in-dquotes codex-five-calls codex-five-exec-calls codex-subst-nested codex-subst-parens-in-prompt codex-subst-unclosed codex-double-dash-ro codex-c-key-leading-blank"
M44_EXPECT="codex-ro-bypass codex-ro-config-sandbox codex-ro-profile codex-ro-then-bsnl-danger"
M45_EXPECT="codex-read-only-in-prompt"
M46_EXPECT="codex-exec-help"
M47_EXPECT="codex-C-repo-from-nogit codex-C-quoted-repo-from-nogit codex-attached-C"
M48_EXPECT="script-cd-pwd"
M49_EXPECT="codex-cd-repo-subdir"
M50_EXPECT="codex-cd-temp-danger codex-cd-temp-config-danger codex-cd-temp-profile-danger codex-add-dir codex-yolo-temp codex-quoted-danger-temp codex-c-key-leading-blank"
M51_EXPECT="codex-cd-temp-config-danger codex-c-key-leading-blank"
M52_EXPECT="codex-cd-temp-profile-danger"
M53_EXPECT="codex-ro-quoted codex-C-quoted-repo-from-nogit"
M54_EXPECT="codex-subshell-cd codex-dollar-cd"
M55_EXPECT="codex-cd-dash"
M56_EXPECT="codex-cd-missing-dir"
M57_EXPECT="codex-cd-nontemp"
M58_EXPECT="codex-after-separator codex-backslash-newline codex-cd-repo-subdir codex-cd-temp-gitrepo codex-e-alias codex-exec-default codex-five-calls codex-read-only-in-prompt codex-resume-default codex-ro-then-ww codex-subst-in-dquotes codex-workspace-write codex-subst-nested codex-subst-parens-in-prompt codex-subst-unclosed codex-double-dash-ro"
M59_EXPECT="codex-attached-C codex-C-quoted-repo-from-nogit codex-C-repo-from-nogit codex-cd-temp-C-nonrepo codex-cd-temp-C-repo"
M60_EXPECT="codex-unread-cd"
M61_EXPECT="codex-backslash-newline codex-ro-then-bsnl-danger codex-ro-bsnl"
M62_EXPECT="codex-add-dir codex-yolo-temp"
M63_EXPECT="codex-attached-C codex-ro-attached"
M64_EXPECT="codex-subst-in-dquotes codex-subst-nested codex-subst-parens-in-prompt codex-subst-unclosed"
M65_EXPECT="codex-five-calls-temp"
M66_EXPECT="codex-five-exec-calls"
M67_EXPECT="fast-64k-cd-chain"
M68_EXPECT="fast-expand-bomb"
M69_EXPECT="assign-over-4096-env-unresolved"
M70_EXPECT="python-m-script-arg"
M71_EXPECT="codex-ro-short codex-ro-eq-effort codex-ro-quoted codex-ro-attached codex-ro-bsnl fast-64k-codex-config"
M72_EXPECT="codex-ro-then-ww"
M73_EXPECT="codex-subst-nested codex-subst-parens-in-prompt codex-subst-unclosed"
M74_EXPECT="codex-subst-unclosed"
M75_EXPECT="codex-double-dash-ro"
M76_EXPECT="codex-c-key-leading-blank"

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
    m6) from='const expand = s => {' to='const expand = s => s; const expandOff = s => {' ;;
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
    m12) from='"(?:" + WS + "(?:" + SEP_ARG + "|-[\\w=.-]+)){0,16}?"' to='"(?:" + WS + "(?:" + SEP_ARG + "|--?[\\w=.-]+))*?"' ;;
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
    m27)
      # Two substitutions: the value cap off, and the expansion budget off —
      # the budget alone also stops a long value from resolving.
      lit_sub "$ORIG" "$dest.tmp" 'if (v.length <= 4096) vars[a[1]] = v;' 'if (true) vars[a[1]] = v;'
      from='if (len > 4096) { over = true; return ""; }' to='if (false) { over = true; return ""; }'
      lit_sub "$dest.tmp" "$dest" "$from" "$to"
      rm -f "$dest.tmp"
      ;;
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
    m34) from='(?<![^\s'"'"'"|;&)])[^\s'"'"'"|;&)]*(\$\{?TMPDIR' to='[^\s'"'"'"|;&)]*(\$\{?TMPDIR' ;;
    m35) from='\/\.claude\/projects\/[^\s'"'"'"|;&)\/]*\/memory\/' to='\/\.claude\/projects\/[^\s'"'"'"|;&)]*\/memory\/' ;;
    m36) from='"(^|[\\n|;&][ \\t]*|\\$\\([ \\t]*|&&[ \\t]*|\\|\\|[ \\t]*)"' to='"(^|[\\n|;&]\\s*|\\$\\(\\s*|&&\\s*|\\|\\|\\s*)"' ;;
    m37) from='[^|;&]{0,1024}\s-\w*i\b/' to='[^|;&]*\s-\w*i\b/' ;;
    m38) from='command.length > 262144' to='command.length > 1e12' ;;
    m39) from='if (n !== "TMPDIR" && process.env[n]' to='if (false && process.env[n]' ;;
    m40) from='path.resolve(dir, p)' to='path.resolve(process.cwd(), p)' ;;
    m41) from='const SEP_ARG = "(?:-[rWXI]|' to='const SEP_ARG = "(?!)"; const SEP_ARG_OFF = "(?:-[rWXI]|' ;;
    m42) from='+ "|\"([^\"\\n]*)\"(' to='+ "|(?!)\"([^\"\\n]*)\"(' ;;
    m43) from='const R_CODEX = new RegExp(' to='const R_CODEX = /(?!)/g; const R_CODEX_OFF = new RegExp(' ;;
    m44) from='if (ro && !other && !wide) continue;' to='if (ro && !other) continue;' ;;
    m45) from='} else if (ws && ch === "\"" && !noDq) {' to='} else if (false) {' ;;
    m46) from='(?:-h|--help|-V|--version)' to='(?!)(?:-h|--help|-V|--version)' ;;
    m47) from='if (cdir !== null) graded.add(' to='if (false) graded.add(' ;;
    m48) from='else if (n === "PWD") v = expand.pwd;' to='else if (false) v = expand.pwd;' ;;
    m49) from='graded.add(w.dir);' to='graded.add(process.cwd());' ;;
    m50) from='const exempt = !danger && ' to='const exempt = ' ;;
    m51) from='{ wide = true; danger = true; }' to='{ wide = true; }' ;;
    m52) from='} else if (f === "p") danger = true;' to='} else if (false) danger = true;' ;;
    m53) from='.exec(command.slice(q, q + 4098))' to='.exec(cq.slice(q, q + 4098))' ;;
    m54) from='if (depth !== 0) ok = false;' to='if (false) ok = false;' ;;
    m55) from='else if (arg === "-" || /[`$]/.test(arg)) ok = false;' to='else if (arg === "-" || /[`$]/.test(arg)) {}' ;;
    m56) from='&& isDir(w.dir) &&' to='&& true &&' ;;
    m57) from='&& underTemp(w.dir) &&' to='&& true &&' ;;
    m58) from=' && !repoAt(w.dir);' to=' && true;' ;;
    m59) from='&& !hasC && w.ok' to='&& w.ok' ;;
    m60) from='if (c !== null || n !== any) ok = false;' to='if (c !== null) ok = false;' ;;
    m61) from='const bs = command.replace(/\\\n/g, "  ");' to='const bs = command;' ;;
    m62) from='(?:--yolo|--add-dir|' to='(?:' ;;
    m63) from='(?:-([scCp])|--(' to='(?:-([scCp])(?=[ \t=]|$)|--(' ;;
    m64) from='if (d === "$" && bs[k + 1] === "(") {' to='if (false) {' ;;
    m65) from='if (++seen > 64) {' to='if (++seen > 64 || ++calls > 4) {' ;;
    m66) from='if (capped) graded.add(process.cwd());' to='if (false) graded.add(process.cwd());' ;;
    m67) from='while (n++ < 64 && (c = CD_ARG.exec(head)) !== null) {' to='while ((c = CD_ARG.exec(head)) !== null) {' ;;
    m68) from='if (len > 4096) { over = true; return ""; }' to='if (false) { over = true; return ""; }' ;;
    m69) from='else vars[a[1]] = null;' to='else delete vars[a[1]];' ;;
    m70) from='const SEP_ARG = "(?:-[rWXI]|' to='const SEP_ARG = "(?:-[rWXIm]|' ;;
    m71) from='if (ro && !other && !wide) continue;' to='if (false) continue;' ;;
    m72) from='if (ro && !other && !wide) continue;' to='if (ro && !wide) continue;' ;;
    m73)
      # Two substitutions: the depth walk back to a first-paren stop, and
      # an unclosed span blanked again (the pre-walk scanner).
      lit_sub "$ORIG" "$dest.tmp" 'const j = substEnd(k);' 'let j = k + 2; while (j < bs.length && j < k + 4098 && bs[j] !== "(" && bs[j] !== ")") j++; if (bs[j] !== ")") j = -1;'
      from='if (j === -1) break;' to='if (j === -1) { out += " "; k++; continue; }'
      lit_sub "$dest.tmp" "$dest" "$from" "$to"
      rm -f "$dest.tmp"
      ;;
    m74) from='if (j === -1) break;' to='if (j === -1) { out += " "; k++; continue; }' ;;
    m75) from='if (dd !== -1) seg = seg.slice(0, dd);' to='if (false) seg = seg.slice(0, dd);' ;;
    m76) from='/^['"'"'"]?[ \t]*([\w.-]*)/' to='/^['"'"'"]?([\w.-]*)/' ;;
  esac
  if [ "$which" != "m11" ] && [ "$which" != "m27" ] && [ "$which" != "m29" ] && [ "$which" != "m73" ]; then
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
# A git repo under a temp root: the codex exemption must still refuse it.
mkdir -p "$TMPD/grepo" && "$GIT" -C "$TMPD/grepo" init -q
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
LONG_HOME="HOME=$EXT$(printf '/.%.0s' $(seq 2500)); python3 \"\$HOME/edit.py\""
# The shell door's 64 KB shapes, each once seconds long or killed by the
# alarm. `$(…)` strips trailing newlines, so the `x` fences of the newline run
# are printed INSIDE it: fenced outside, the run collapses to `xx`.
W64="$(head -c 65536 /dev/zero | tr '\0' 'x')"
NL64="$(printf x; head -c 65534 /dev/zero | tr '\0' '\n'; printf x)"
DP64="$(head -c 32768 /dev/zero | tr '\0' 'x' | sed 's/x/$(/g')"
CP64="$(printf '/.claude/projects/%.0s' $(seq 3641))"
# The same word just under the cap: the memory-dir class admitting `/` is
# quadratic on it, 0.4 s at 64 KB (under the bound) but 6 s here.
CPCAP="$(printf '/.claude/projects/%.0s' $(seq 14563))"
SED64="$(head -c 16384 /dev/zero | tr '\0' 'x' | sed 's/x/sed /g')"
# Over the 256 K cap, made of one-letter words: fast on every hook version,
# so only the cap can turn it into a deny (a 300 K single word would hit the
# old hook's alarm and redden the pass cases too).
HUGE_CMD="$(head -c 150000 /dev/zero | tr '\0' 'x' | sed 's/x/a /g')"
# The codex gate reads every command holding `codex`: a 78 KB run of the
# word, and one read-only call carrying 9 000 `-c` keys to read.
CODEX64="$(head -c 13000 /dev/zero | tr '\0' 'x' | sed 's/x/codex /g')"
CODEXCFG64="codex exec -s read-only$(head -c 9000 /dev/zero | tr '\0' 'x' | sed 's/x/ -c a=b/g') x"
# 13 000 `cd`s: the fold resolved a path 13 000 deep once per `cd` (6 s).
CDCHAIN="$(head -c 13000 /dev/zero | tr '\0' 'x' | sed 's/x/;cd a/g') && python3 \"\$TMPDIR/x.py\""
CODEXEXEC64="$(head -c 5041 /dev/zero | tr '\0' 'x' | sed 's/x/codex exec x;/g')"
# The `$(` depth walk inside double quotes: `"$(` x20 000, the slowest of three
# shapes timed (with `"$(` + `$(` x32 000 and `"$(` + 4098 `(`), all under 70 ms.
DQSUBST64="codex exec x; $(head -c 20000 /dev/zero | tr '\0' 'x' | sed 's/x/"$(/g')"
# One 4096-char value named ~15 000 times: megabytes unless the budget stops it.
B4K="$(head -c 4096 /dev/zero | tr '\0' 'a')"
EXPBOMB="B=$B4K; cd \"$(head -c 15000 /dev/zero | tr '\0' 'x' | sed 's/x/$B/g')\" && python3 \"\$TMPDIR/x.py\"; python3 \"\$TMPDIR/y.py\"; python3 \"\$TMPDIR/z.py\"; python3 \"\$TMPDIR/w.py\""
NL=$'\n'

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
    unset) tenv=(-u OTHER -u TMPDIR) ;;
    empty) tenv=(-u OTHER TMPDIR=) ;;
    *) tenv=(-u OTHER TMPDIR="$TMPD") ;;
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
# A name the command never sets, read from the environment the Bash call
# inherits; a `cd` moves where a relative script path is read from.
check script-env-home deny "$REPO" "$T_NOAPEX" 'python3 "$HOME/edit.py"'
check script-cd-relative deny "$REPO" "$T_NOAPEX" "cd $EXT && python3 edit.py"
check script-cd-chain deny "$REPO" "$T_NOAPEX" "cd $WORK && cd ext && python3 edit.py"
# A flag with a separate argument, and a quoted head with a bare tail.
check python-W-ignore-c-write deny "$REPO" "$T_NOAPEX" "python3 -W ignore -c \"open('package.json', 'w').write('{}')\""
check script-W-ignore deny "$REPO" "$T_NOAPEX" "python3 -W ignore $EXT/edit.py"
check node-r-then-e-write deny "$REPO" "$T_NOAPEX" "node -r esm -e \"require('fs').writeFileSync('a', '')\""
check script-quoted-var-bare-tail deny "$REPO" "$T_NOAPEX" 'python3 "$TMPDIR"/edit.py'
# `$PWD` is where the `cd`s leave the shell: read from the environment (or the
# cwd), `$PWD/edit.py` would name the repo, where there is no edit.py.
check script-cd-pwd deny "$REPO" "$T_NOAPEX" "cd $EXT && python3 \"\$PWD/edit.py\""
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
check cd-relative-noname pass "$REPO" "$T_NOAPEX" "cd $EXT && python3 noname.py"
check cd-subdir-in-repo pass "$REPO" "$T_NOAPEX" 'cd tools && python3 edit.py'
# `-m` ends the flag run: the path after it is the module's argument.
check python-m-script-arg pass "$REPO" "$T_NOAPEX" "python3 -m pytest $EXT/edit.py"
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
# The same, set on a name the environment also has: the shell sees the long
# value, so the hook must not fall back to its own $HOME (where edit.py is).
check assign-over-4096-env-unresolved pass "$REPO" "$T_NOAPEX" "$LONG_HOME"
# --- MUST PASS: the gate's own exits -----------------------------------------
check apex-already-ran pass "$REPO" "$T_APEX" "python3 -c \"open('package.json', 'w').write('{}')\""
check apex-already-ran-script pass "$REPO" "$T_APEX" "python3 $EXT/edit.py"
check outside-git-inline pass "$NOGIT" "$T_NOAPEX" "python3 -c \"open('package.json', 'w').write('{}')\""
check outside-git-script pass "$NOGIT" "$T_NOAPEX" "python3 $EXT/edit.py"
# --- codex exec: denied unless an explicit, unwidened `-s read-only` --------
check codex-exec-default deny "$REPO" "$T_NOAPEX" 'codex exec "fix it"'
check codex-e-alias deny "$REPO" "$T_NOAPEX" 'codex e -m m "x"'
check codex-after-separator deny "$REPO" "$T_NOAPEX" 'cd . && timeout 60 codex exec --json "x"'
check codex-workspace-write deny "$REPO" "$T_NOAPEX" 'codex exec -s workspace-write "x"'
check codex-read-only-in-prompt deny "$REPO" "$T_NOAPEX" 'codex exec "use -s read-only here"'
check codex-ro-config-sandbox deny "$REPO" "$T_NOAPEX" 'codex exec -s read-only -c sandbox_mode=danger-full-access "x"'
check codex-ro-profile deny "$REPO" "$T_NOAPEX" 'codex exec --sandbox read-only -p fast "x"'
check codex-ro-bypass deny "$REPO" "$T_NOAPEX" 'codex exec -s read-only --dangerously-bypass-approvals-and-sandbox "x"'
check codex-resume-default deny "$REPO" "$T_NOAPEX" 'codex exec resume --last "go"'
check codex-C-repo-from-nogit deny "$NOGIT" "$T_NOAPEX" "codex exec -C $REPO \"x\""
check codex-ro-short pass "$REPO" "$T_NOAPEX" 'codex exec -s read-only "x"'
check codex-ro-eq-effort pass "$REPO" "$T_NOAPEX" 'codex exec --sandbox=read-only -c model_reasoning_effort=low "x"'
check codex-exec-help pass "$REPO" "$T_NOAPEX" 'codex exec --help'
check codex-grep-mention pass "$REPO" "$T_NOAPEX" 'grep -n "codex exec" README.md'
check codex-apex pass "$REPO" "$T_APEX" 'codex exec "fix it"'
check codex-nogit pass "$NOGIT" "$T_NOAPEX" 'codex exec "fix it"'
# Graded where codex runs: the `cd`s before it, then `-C`.
check codex-cd-temp-pass pass "$REPO" "$T_NOAPEX" "cd $TMPD && codex exec \"x\""
check codex-cd-temp-timeout-pass pass "$REPO" "$T_NOAPEX" "cd $TMPD && timeout 240 codex exec --skip-git-repo-check -m m -c model_reasoning_effort=low 'x'"
check codex-cd-temp-danger deny "$REPO" "$T_NOAPEX" "cd $TMPD && codex exec -s danger-full-access \"x\""
check codex-cd-temp-C-repo deny "$REPO" "$T_NOAPEX" "cd $TMPD && codex exec -C $REPO \"x\""
check codex-cd-temp-config-danger deny "$REPO" "$T_NOAPEX" "cd $TMPD && codex exec -c sandbox_mode=danger-full-access \"x\""
check codex-cd-temp-profile-danger deny "$REPO" "$T_NOAPEX" "cd $TMPD && codex exec -p yolo \"x\""
check codex-cd-repo-subdir deny "$NOGIT" "$T_NOAPEX" "cd $REPO/tools && codex exec \"x\""
# The exemption is a whitelist: each case below breaks one condition.
check codex-C-nonrepo-from-repo deny "$REPO" "$T_NOAPEX" "codex exec -C $NOGIT \"x\""
check codex-cd-temp-C-nonrepo deny "$REPO" "$T_NOAPEX" "cd $TMPD && codex exec -C $NOGIT \"x\""
check codex-subshell-cd deny "$REPO" "$T_NOAPEX" "(cd $TMPD && ls); codex exec \"x\""
check codex-dollar-cd deny "$REPO" "$T_NOAPEX" "x=\$(cd $TMPD && pwd) && codex exec \"x\""
check codex-cd-missing-dir deny "$REPO" "$T_NOAPEX" "cd $TMPD/missing && codex exec \"x\""
check codex-cd-dash deny "$REPO" "$T_NOAPEX" "cd $TMPD && cd - && codex exec \"x\""
check codex-cd-nontemp deny "$REPO" "$T_NOAPEX" 'cd /usr && codex exec "x"'
check codex-cd-temp-gitrepo deny "$REPO" "$T_NOAPEX" "cd $TMPD/grepo && codex exec \"x\""
check codex-unread-cd deny "$REPO" "$T_NOAPEX" "cd $TMPD && if true; then cd $REPO; fi; codex exec \"x\""
check codex-add-dir deny "$REPO" "$T_NOAPEX" "cd $TMPD && codex exec --add-dir $REPO \"x\""
check codex-yolo-temp deny "$REPO" "$T_NOAPEX" "cd $TMPD && codex exec --yolo \"x\""
check codex-quoted-danger-temp deny "$REPO" "$T_NOAPEX" "cd $TMPD && codex exec -s \"danger-full-access\" \"x\""
# Option values read from the raw command: quoted, attached, after `\`+newline.
check codex-C-quoted-pwd-then-c deny "$REPO" "$T_NOAPEX" 'codex exec --sandbox workspace-write -C "$(pwd)" -c x=1 "fix"'
check codex-C-quoted-repo-from-nogit deny "$NOGIT" "$T_NOAPEX" "codex exec -C \"$REPO\" \"x\""
check codex-attached-C deny "$NOGIT" "$T_NOAPEX" "codex exec -C$REPO \"x\""
check codex-backslash-newline deny "$REPO" "$T_NOAPEX" "codex \\${NL}exec \"x\""
check codex-ro-then-bsnl-danger deny "$REPO" "$T_NOAPEX" "codex exec -s read-only \\${NL}--dangerously-bypass-approvals-and-sandbox \"x\""
check codex-ro-then-ww deny "$REPO" "$T_NOAPEX" 'codex exec -s read-only -s workspace-write "x"'
check codex-subst-in-dquotes deny "$REPO" "$T_NOAPEX" 'out="$(codex exec "fix")"'
# The span's end is found by paren depth, past nested quotes and `$(`.
check codex-subst-nested deny "$REPO" "$T_NOAPEX" 'out="$(codex exec "$(cat p.txt)")"'
check codex-subst-parens-in-prompt deny "$REPO" "$T_NOAPEX" 'out="$(codex exec "fix (this) now")"'
# Unclosed: the string is left visible (fail closed), not blanked.
check codex-subst-unclosed deny "$REPO" "$T_NOAPEX" 'out="$(codex exec "x"'
check codex-parens-mention-pass pass "$REPO" "$T_NOAPEX" 'git commit -m "mention codex exec (docs)"'
# A bare `--` ends the options: `-s read-only` after it is prompt text.
check codex-double-dash-ro deny "$REPO" "$T_NOAPEX" 'codex exec -- -s read-only fix'
check codex-c-key-leading-blank deny "$REPO" "$T_NOAPEX" "cd $TMPD && codex exec -c ' sandbox_mode=danger-full-access' \"x\""
# Only exec calls count toward the cap of 4; past it, graded at the cwd.
check codex-five-calls deny "$REPO" "$T_NOAPEX" 'codex --version; codex --version; codex --version; codex --version; codex exec "x"'
check codex-five-exec-calls deny "$REPO" "$T_NOAPEX" "cd $TMPD && codex exec -s read-only a; codex exec -s read-only b; codex exec -s read-only c; codex exec -s read-only d; codex exec \"x\""
check codex-five-calls-temp pass "$REPO" "$T_NOAPEX" "codex --version; codex --version; codex --version; codex --version; cd $TMPD && codex exec \"x\""
check codex-ro-quoted pass "$REPO" "$T_NOAPEX" 'codex exec -s "read-only" "x"'
check codex-ro-attached pass "$REPO" "$T_NOAPEX" 'codex exec -sread-only "x"'
check codex-ro-bsnl pass "$REPO" "$T_NOAPEX" "codex exec \\${NL}-s read-only \"x\""
# --- MUST PASS FAST: adversarial shapes --------------------------------------
check bounded-64k-separators pass-fast "$REPO" "$T_NOAPEX" "$LONG"
check flags-28-fast pass-fast "$REPO" "$T_NOAPEX" "$FLAGS28"
check node-newlines-64k-fast pass-fast "$REPO" "$T_NOAPEX" "$NODE_NL"
check dollar-paren-node-64k-fast pass-fast "$REPO" "$T_NOAPEX" "$DOLLAR_NODE"
check assign-newlines-16k-fast pass-fast "$REPO" "$T_NOAPEX" "$ASSIGN_NL"
check assign-doubling-fast pass-fast "$REPO" "$T_NOAPEX" "$DOUBLING"
check fast-64k-word pass-fast "$REPO" "$T_NOAPEX" "$W64"
check fast-64k-newlines pass-fast "$REPO" "$T_NOAPEX" "$NL64"
check fast-64k-dollar-paren pass-fast "$REPO" "$T_NOAPEX" "$DP64"
check fast-64k-claude-projects pass-fast "$REPO" "$T_NOAPEX" "$CP64"
check fast-64k-sed pass-fast "$REPO" "$T_NOAPEX" "$SED64"
check fast-cap-claude-projects pass-fast "$REPO" "$T_NOAPEX" "$CPCAP"
check fast-64k-codex pass-fast "$REPO" "$T_NOAPEX" "$CODEX64"
check fast-64k-codex-config pass-fast "$REPO" "$T_NOAPEX" "$CODEXCFG64"
check fast-64k-cd-chain pass-fast "$REPO" "$T_NOAPEX" "$CDCHAIN"
check fast-64k-codex-exec-calls pass-fast "$NOGIT" "$T_NOAPEX" "$CODEXEXEC64"
check fast-expand-bomb pass-fast "$REPO" "$T_NOAPEX" "$EXPBOMB"
check fast-64k-dq-subst pass-fast "$NOGIT" "$T_NOAPEX" "$DQSUBST64"
# --- OVER 256 K: denied unread, unless APEX ran or the cwd is not a repo -----
check huge-command-denied deny "$REPO" "$T_NOAPEX" "$HUGE_CMD"
check huge-command-apex pass "$REPO" "$T_APEX" "$HUGE_CMD"
check huge-command-nogit pass "$NOGIT" "$T_NOAPEX" "$HUGE_CMD"

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
