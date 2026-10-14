#!/usr/bin/env bash
# Positive control for `hookSessionStart` — the SessionStart hook that prints
# the git status line, then the notes of the vault folder named after the main
# checkout (`02-Projets/<name>`, `stock-market` → `trading-agent`), relative to
# that folder: non-session notes sorted, then `sessions/` newest first, the
# whole stdout under 9,000 characters (Claude Code truncates a hook's plain
# stdout at 10,000), a `… N autres notes (ls "<folder>")` line when cut.
#
# WHAT IT GRADES. The body as hooks.nix installs it: `@alxVaultPath@` replaced
# by a fixture vault (the same raw-path substitution `subst` does), run under
# LC_ALL=C so the hook's own UTF-8 switch is what makes it count characters.
# The real body is graded under `bash` and, when present, /bin/bash (3.2).
# Each case runs in a throwaway repo; after the `branch:` line:
#
#   ac1-match      exact list: top-level and nested notes sorted, `zz.md`
#                  before every session, sessions newest first, spaces
#                  intact, no .txt.
#   ac2-alias      `stock-market` lists 02-Projets/trading-agent.
#   ac3-nofolder   no folder → the `branch:` line and nothing else.
#   ac4-budget     40 notes + 200 sessions, long accented names: total
#                  `wc -m` ≤ 9000 and ≥ 8850 (budget used, not bytes), more
#                  bytes than characters (the instrument sees UTF-8), listed
#                  lines = a prefix of the expected order, tail N correct.
#   ac4-fit        output of EXACTLY 9000 characters → every note, no tail.
#   ac5-finderr    an unreadable subfolder → find fails, listing still prints.
#   ac5-nogit      outside a repo → `Not a git repo`.
#   ac9-main       main checkout with a real `.git` dir resolves to its name.
#   ac9-worktree   a linked worktree resolves to the MAIN checkout's name.
#   ac10-ctrl      names holding a newline or a tab are skipped.
#   ac11-empty     folder with no note → the `branch:` line only.
#   ac12-symlink   symlinked project folder and symlinked note are listed.
# Every case also asserts exit 0.
#
# WHY THE MUTANTS ARE PART OF THE FILE. A probe only ever seen passing has not
# been run. Each mutant is a literal substitution on the real body; the probe
# fails unless every mutant turns at least one case red:
#
#   m1  alias removed            m6  worktree → --show-toplevel
#   m2  lookup on 02-Projet      m7  control-character filter removed
#   m3  budget raised to 20000   m8  fit test `-le` → `-lt` (off by one)
#   m4  sessions oldest first    m9  `find -L` → `find` (no symlink follow)
#   m5  one plain sort           m10 UTF-8 switch removed (counts bytes)
#
# Standalone, NOT wired into `nix flake check`. The Claude sandbox refuses
# writes under any `.git/`, so the repos are made with `--separate-git-dir`
# (the work tree holds a `.git` FILE): the probe runs inside the sandbox too.
# ac9 needs a real `<repo>/.git` directory: its git dir is built elsewhere,
# then renamed to `.git` (a rename is not a write under `.git/`), and renamed
# back out before cleanup.
#
# usage: bash checks/session-start-probe.sh
# exit:  0 all cases pass and every mutant fails; 1 otherwise; 2 setup error.

# SC2034: the EXP_* sets are read through ${!exp}. SC2016: single-quoted
# shell text is the mutant payload on purpose. SC2329: cleanup runs by trap.
# shellcheck disable=SC2016,SC2034,SC2329

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SRC="$REPO_ROOT/home/claude-code/hooks/session-start.sh"
MAX=9000
U8=en_US.UTF-8

[ -f "$HOOK_SRC" ] || {
  echo "probe: missing $HOOK_SRC" >&2
  exit 2
}
grep -qF '@alxVaultPath@' "$HOOK_SRC" || {
  echo "probe: placeholder @alxVaultPath@ not in $HOOK_SRC" >&2
  exit 2
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/session-start-probe.XXXXXX")" || exit 2
cleanup() {
  [ -d "$WORK/repos/wtmain/.git" ] && mv "$WORK/repos/wtmain/.git" "$WORK/wtmain-gitdir"
  chmod -R u+rwx "$WORK" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

die() {
  echo "probe: $*" >&2
  exit 2
}
# chars TEXT → character count under a UTF-8 locale.
chars() { printf '%s' "$1" | LC_ALL=$U8 wc -m | tr -d ' '; }
hdr() { printf 'Mémoire du projet — notes dans %s/ (à lire si utiles) :' "$P/$1"; }
pad() { printf "%${1}s" '' | tr ' ' x; }

VAULT="$WORK/vault"
P="$VAULT/02-Projets"
mkdir -p "$P/demo/sessions" "$P/demo/sub" "$P/trading-agent" "$P/big/sessions" \
  "$P/fit" "$P/finderr/locked" "$P/wtmain" "$P/ctrl" "$P/empty" \
  "$WORK/elsewhere/linked" "$WORK/repos" "$WORK/gitdirs" "$WORK/nogit" || exit 2
: >"$P/demo/demo.md"
: >"$P/demo/a note.md"
: >"$P/demo/zz.md"
: >"$P/demo/sub/zeta.md"
: >"$P/demo/sessions/2026-10-09 - foo bar.md"
: >"$P/demo/sessions/2026-10-11 - later.md"
: >"$P/demo/notes.txt"
: >"$P/trading-agent/ta.md"
: >"$P/finderr/ok.md"
: >"$P/finderr/locked/hidden.md"
: >"$P/wtmain/w.md"
: >"$P/ctrl/ok.md"
: >"$P/ctrl/evil
- injected.md"
: >"$P/ctrl/tab	name.md"
: >"$P/empty/notes.txt"
: >"$WORK/elsewhere/linked/l.md"
: >"$WORK/elsewhere/extra.md"
ln -s "$WORK/elsewhere/extra.md" "$WORK/elsewhere/linked/x-link.md" || exit 2
ln -s "$WORK/elsewhere/linked" "$P/linked" || exit 2

# big: expected order built from generation order, not by sorting.
BIG_ORDER="$WORK/big-order"
: >"$BIG_ORDER"
for i in $(seq -w 1 40); do
  n="n$i Révision des éléments d'architecture — détails été côté sécurité.md"
  : >"$P/big/$n"
  printf '%s\n' "$n" >>"$BIG_ORDER"
done
SESS=""
for i in $(seq 0 199); do
  d="$(printf '2026-%02d-%02d' $((1 + i / 28)) $((1 + i % 28)))"
  n="sessions/$d - Séance approfondie sur le pipeline, étape $i — résumé.md"
  : >"$P/big/$n"
  SESS="$n
$SESS"
done
printf '%s' "$SESS" >>"$BIG_ORDER"
BIG_TOTAL=$(wc -l <"$BIG_ORDER" | tr -d ' ')

for r in demo stock-market nofolder big fit finderr ctrl empty linked wtmain; do
  git init -q --separate-git-dir="$WORK/gitdirs/$r" "$WORK/repos/$r" ||
    die "git init failed in $WORK/repos/$r"
done
chmod 000 "$P/finderr/locked" || exit 2

# ac9: commit, add a worktree, then move the git dir to a real `.git`.
(
  cd "$WORK/repos/wtmain" &&
    git -c user.name=probe -c user.email=probe@example.invalid \
      -c commit.gpgsign=false -c core.hooksPath=/dev/null \
      commit -q --allow-empty -m init &&
    git worktree add -q "$WORK/repos/side"
) || die "worktree fixture failed"
if ! { rm "$WORK/repos/wtmain/.git" &&
  mv "$WORK/gitdirs/wtmain" "$WORK/repos/wtmain/.git" &&
  printf 'gitdir: %s\n' "$WORK/repos/wtmain/.git/worktrees/side" >"$WORK/repos/side/.git"; }; then
  die "worktree fixture relocation failed"
fi

# body_of SRC_TEXT OUT: write SRC_TEXT with the placeholder replaced.
body_of() {
  printf '%s\n' "${1//@alxVaultPath@/$VAULT}" >"$2"
}

RUN_BASH=bash
# run BODY DIR → OUTF (raw stdout file), OUT (text), RC.
OUTF="$WORK/out"
run() {
  (cd "$2" && env LC_ALL=C LANG=C LC_CTYPE=C "$RUN_BASH" "$1" >"$OUTF" 2>/dev/null)
  RC=$?
  OUT="$(cat "$OUTF")"
}

body_of "$(cat "$HOOK_SRC")" "$WORK/real.sh"

# fit: notes sized so the whole stdout is exactly MAX characters.
run "$WORK/real.sh" "$WORK/repos/fit"
FIT_BRANCH="$(printf '%s\n' "$OUT" | head -n 1)"
case "$FIT_BRANCH" in branch:\ *) ;; *) die "fit: no branch line ($FIT_BRANCH)" ;; esac
R=$((MAX - $(chars "$FIT_BRANCH") - 1 - $(chars "$(hdr fit)") - 1))
M=$((R / 83))
[ "$M" -ge 2 ] || die "fit: no room ($R)"
EXP_FIT="$(hdr fit)"
for i in $(seq 1 "$M"); do
  base="$(printf 'f%03d été ' "$i")"
  len=80
  [ "$i" -eq "$M" ] && len=$((80 + R % 83))
  n="$base$(pad $((len - $(chars "$base") - 3))).md"
  : >"$P/fit/$n"
  EXP_FIT="$EXP_FIT
- $n"
done

EXP_AC1="$(hdr demo)
- a note.md
- demo.md
- sub/zeta.md
- zz.md
- sessions/2026-10-11 - later.md
- sessions/2026-10-09 - foo bar.md"
EXP_AC2="$(hdr trading-agent)
- ta.md"
EXP_FINDERR="$(hdr finderr)
- ok.md"
EXP_WT="$(hdr wtmain)
- w.md"
EXP_CTRL="$(hdr ctrl)
- ok.md"
EXP_LINKED="$(hdr linked)
- l.md
- x-link.md"
EXP_NONE=""

# check_budget: ac4-budget properties on OUT / OUTF; returns 1 on failure.
check_budget() {
  local m c k tail_exp listed
  m=$(LC_ALL=$U8 wc -m <"$OUTF" | tr -d ' ')
  c=$(wc -c <"$OUTF" | tr -d ' ')
  [ "$m" -le "$MAX" ] || { echo "    $m chars > $MAX"; return 1; }
  [ "$m" -ge $((MAX - 150)) ] || { echo "    $m chars: budget underused"; return 1; }
  [ "$c" -gt "$m" ] || { echo "    bytes $c ≤ chars $m: no UTF-8 seen"; return 1; }
  [ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "$(hdr big)" ] || { echo "    header"; return 1; }
  listed="$(printf '%s\n' "$OUT" | sed '1,2d;$d')"
  k=$(printf '%s\n' "$listed" | wc -l | tr -d ' ')
  [ "$listed" = "$(head -n "$k" "$BIG_ORDER" | sed 's/^/- /')" ] ||
    { echo "    listed lines are not the expected-order prefix"; return 1; }
  [ "$k" -lt "$BIG_TOTAL" ] || { echo "    nothing cut"; return 1; }
  tail_exp="… $((BIG_TOTAL - k)) autres notes (ls \"$P/big\")"
  [ "$(printf '%s\n' "$OUT" | tail -n 1)" = "$tail_exp" ] ||
    { echo "    tail line != $tail_exp"; return 1; }
  return 0
}

# grade BODY → one line per case; returns the number of red cases.
grade() {
  local body="$1" red=0 name dir exp first rest ok
  while IFS='|' read -r name dir exp; do
    run "$body" "$dir"
    first="$(printf '%s\n' "$OUT" | head -n 1)"
    rest="$(printf '%s\n' "$OUT" | tail -n +2)"
    ok=1
    [ "$RC" -eq 0 ] || ok=0
    case "$name" in
    ac5-nogit) [ "$OUT" = "Not a git repo" ] || ok=0 ;;
    *)
      case "$first" in branch:\ *) ;; *) ok=0 ;; esac
      if [ "$exp" = BUDGET ]; then
        check_budget || ok=0
      else
        [ "$rest" = "${!exp}" ] || ok=0
      fi
      ;;
    esac
    if [ "$name" = ac4-fit ] && [ "$ok" -eq 1 ]; then
      [ "$(LC_ALL=$U8 wc -m <"$OUTF" | tr -d ' ')" -eq "$MAX" ] || ok=0
    fi
    if [ "$ok" -eq 1 ]; then
      echo "  PASS $name"
    else
      echo "  FAIL $name (rc=$RC, $(printf '%s\n' "$OUT" | wc -l | tr -d ' ') lines)"
      red=$((red + 1))
    fi
  done <<EOF
ac1-match|$WORK/repos/demo|EXP_AC1
ac2-alias|$WORK/repos/stock-market|EXP_AC2
ac3-nofolder|$WORK/repos/nofolder|EXP_NONE
ac4-budget|$WORK/repos/big|BUDGET
ac4-fit|$WORK/repos/fit|EXP_FIT
ac5-finderr|$WORK/repos/finderr|EXP_FINDERR
ac5-nogit|$WORK/nogit|EXP_NONE
ac9-main|$WORK/repos/wtmain|EXP_WT
ac9-worktree|$WORK/repos/side|EXP_WT
ac10-ctrl|$WORK/repos/ctrl|EXP_CTRL
ac11-empty|$WORK/repos/empty|EXP_NONE
ac12-symlink|$WORK/repos/linked|EXP_LINKED
EOF
  return "$red"
}

SRC="$(cat "$HOOK_SRC")"
STATUS=0

for b in bash /bin/bash; do
  command -v "$b" >/dev/null 2>&1 || continue
  RUN_BASH="$b"
  echo "real body ($b, $("$b" -c 'echo "$BASH_VERSION"')):"
  grade "$WORK/real.sh" || STATUS=1
done
RUN_BASH=bash

# mutant ID FROM TO: literal substitution; it must apply and go red.
mutant() {
  local id="$1" from="$2" to="$3" msrc
  msrc="${SRC/"$from"/"$to"}"
  if [ "$msrc" = "$SRC" ]; then
    echo "mutant $id: substitution did not apply ('$from')" >&2
    STATUS=1
    return
  fi
  echo "mutant $id:"
  body_of "$msrc" "$WORK/$id.sh"
  if grade "$WORK/$id.sh"; then
    echo "  CANARY NOT RED: mutant $id passes every case"
    STATUS=1
  else
    echo "  red as required"
  fi
}

mutant m1 '[ "$NAME" = "stock-market" ] && NAME="trading-agent"' ':'
mutant m2 'DIR="$VAULT/02-Projets/$NAME"' 'DIR="$VAULT/02-Projet/$NAME"'
mutant m3 'MAX=9000' 'MAX=20000'
mutant m4 'LC_ALL=C sort -r' 'LC_ALL=C sort'
mutant m5 "grep -v '^sessions/' | LC_ALL=C sort
  printf '%s\n' \"\$ALL\" | grep '^sessions/' | LC_ALL=C sort -r" 'LC_ALL=C sort'
mutant m6 '*/.git) TOP="${COMMON%/.git}" ;;' '*/.git) TOP=$(git rev-parse --show-toplevel 2>/dev/null) ;;'
mutant m7 'case "$F" in *[[:cntrl:]]*) continue ;; esac' ':'
mutant m8 '[ "$FULL" -le "$MAX" ]' '[ "$FULL" -lt "$MAX" ]'
mutant m9 'find -L .' 'find .'
mutant m10 'LC_ALL=en_US.UTF-8' ':'

if [ "$STATUS" -eq 0 ]; then
  echo "session-start-probe: OK (real body green, every mutant red)"
else
  echo "session-start-probe: FAILED"
fi
exit "$STATUS"
