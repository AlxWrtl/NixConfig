# Offline check for the daily veille collector (home/veille/), no network.
#
#   V1  `python3 -I -m unittest` on a copy of home/veille/ exits 0 and runs
#       the whole suite (no skip, at least MIN_TESTS tests): fetch.py imports
#       without side effect and its parsers hold on the fixtures (HN JSON
#       dedup by objectID + sort by points + 3-point threshold, Reddit Atom
#       sub/title/link + date filter, arXiv Atom paging `fini` on a full recent
#       page vs a page crossing `since`, GitHub releases date filter), and
#       fetch exposes nothing of X
#   V2  fetch.py contains neither `api.x.com` nor `X_BEARER_TOKEN`
#   V3  filter-prompt.md still lists the entry types and no longer lists the
#       `social` type (X source removed)
#
# Canary C1: a copy of fetch.py with the HN threshold `< 3` -> `< 0` must FAIL
# the suite on test_hn_threshold_3_points; if it passes, the threshold is
# untested. A guard fails the build if the sed anchor is gone (the mutant
# would equal the source).
# Canaries C2/C3: V2 and V3 detectors must fire on copies with the forbidden
# text appended.
#
# daily.sh, offline: run with `bash -euo pipefail` (writeShellApplication's
# options) against stub claude/fetch (fixtures/stub-*), VEILLE_DIR = a scratch
# vault whose inbox.md has no final newline.
#   D1  run 1 (fixtures/tri-run1.md): "(rien)", a 5-field line, `![`, `[[`,
#       an unknown type, another day and a non-http URL are not appended; a
#       line with backticks is, once, backticks stripped; the valid line is, once; its duplicate (spaces around the
#       URL) and a URL already in inbox.md are counted as duplicates; claude
#       got --safe-mode, the raw file on stdin and not in argv
#   D2  the inbox line without final newline stays whole, the new line follows
#   D3  run 2 the same day: bruts/<day>.md and tris/<day>.json unchanged,
#       run 2 lands in <day>-2.md / <day>-2.json
#   D4  a run whose claude fails (rc 3) exits non-zero, logs rc + subtype and
#       leaves VEILLE_DIR byte-identical
#   D5  VEILLE_DIR unset: exit 0, bruts/ tris/ inbox.md written under
#       ~/.local/share/veille-ttw, nothing under ~/Vaults
# Canary C4: daily.sh with the field-count test turned into `if false` must
# fail D1 on the 5-field line (anchor guard as C1).
{ pkgs }:

let
  src = ../home/veille;
  minTests = 19;
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.python3
    pkgs.coreutils
    pkgs.gnused
    pkgs.gnugrep
    pkgs.diffutils
    pkgs.bash
    pkgs.jq
  ];
in
pkgs.runCommand "veille-check" { } ''
  export PATH=${runtimePath}
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"

  fail() {
    echo "veille: $1"
    for f in "$TMPDIR"/*.out "$TMPDIR"/*.err; do [ -f "$f" ] && { echo "--- $f"; cat "$f"; }; done
    exit 1
  }

  run_tests() { # $1 = directory holding fetch.py + test_fetch.py + fixtures/
    (cd "$1" && python3 -I -B -m unittest discover -s "$1" -t "$1" -p 'test_*.py' -v)
  }
  has_x() { grep -nE 'api\.x\.com|X_BEARER_TOKEN' "$1"; }
  has_social() { grep -niw 'social' "$1"; }

  cp -r ${src} "$TMPDIR/veille"
  chmod -R u+w "$TMPDIR/veille"
  dir="$TMPDIR/veille"

  rc=0
  run_tests "$dir" > "$TMPDIR/v1.out" 2> "$TMPDIR/v1.err" || rc=$?
  [ "$rc" = 0 ] || fail "V1 unittest exit $rc, want 0"
  grep -qx 'OK' "$TMPDIR/v1.err" || fail "V1 unittest did not end on a bare OK (skips or failures)"
  ran=$(sed -n 's/^Ran \([0-9]*\) tests\{0,1\} in .*/\1/p' "$TMPDIR/v1.err")
  [ -n "$ran" ] && [ "$ran" -ge ${toString minTests} ] || fail "V1 ran '$ran' tests, want >= ${toString minTests}"
  echo "veille: V1 unittest OK ($ran tests)"

  [ -f "$dir/fetch.py" ] || fail "V2 fetch.py missing"
  if has_x "$dir/fetch.py" > "$TMPDIR/v2.out"; then
    fail "V2 fetch.py still references the X API"
  fi
  echo "veille: V2 no X in fetch.py OK"

  [ -f "$dir/filter-prompt.md" ] || fail "V3 filter-prompt.md missing"
  grep -q '`officiel`' "$dir/filter-prompt.md" || fail "V3 filter-prompt.md lists no entry type"
  if has_social "$dir/filter-prompt.md" > "$TMPDIR/v3.out"; then
    fail "V3 filter-prompt.md still lists the social type"
  fi
  echo "veille: V3 no social type in filter-prompt.md OK"

  anchor='if (h\.get("points") or 0) < 3:$'
  cp -r "$dir" "$TMPDIR/mutant"
  sed "/$anchor/s/< 3:\$/< 0:/" "$dir/fetch.py" > "$TMPDIR/mutant/fetch.py"
  if [ "$(grep -c "$anchor" "$dir/fetch.py")" != 1 ] || grep -q "$anchor" "$TMPDIR/mutant/fetch.py" || cmp -s "$dir/fetch.py" "$TMPDIR/mutant/fetch.py"; then
    fail "canary anchor '$anchor' gone from fetch.py — the mutant equals the source"
  fi
  rc=0
  run_tests "$TMPDIR/mutant" > "$TMPDIR/c1.out" 2> "$TMPDIR/c1.err" || rc=$?
  [ "$rc" != 0 ] || fail "canary C1 SURVIVED — an HN threshold of 0 points still passes the suite"
  grep -q '^FAIL: test_hn_threshold_3_points ' "$TMPDIR/c1.err" || fail "canary C1 killed by the wrong assertion"
  echo "veille: canary C1 killed — $(grep -m 1 '^FAIL: test_hn_threshold_3_points ' "$TMPDIR/c1.err")"

  { cat "$dir/fetch.py"; echo 'TOKEN = "X_BEARER_TOKEN"'; } > "$TMPDIR/c2.py"
  has_x "$TMPDIR/c2.py" > /dev/null || fail "canary C2 SURVIVED — V2 misses X_BEARER_TOKEN"
  { cat "$dir/filter-prompt.md"; echo '- `social` : post X'; } > "$TMPDIR/c3.md"
  has_social "$TMPDIR/c3.md" > /dev/null || fail "canary C3 SURVIVED — V3 misses the social type"
  echo "veille: canaries C2/C3 killed"

  printf '#!%s\nexec bash %s "$@"\n' "$(command -v bash)" "$dir/fixtures/stub-claude.sh" > "$TMPDIR/claude"
  chmod +x "$TMPDIR/claude"
  printf '# Inbox\n- [2026-01-01] Old — ancien — blog — https://old.example/a' > "$TMPDIR/seed.md"
  daily() { # $1 script, $2 VEILLE_DIR, $3 run name, $4 stub tri text, $5 STUB_FAIL; sets rc
    mkdir -p "$TMPDIR/log-$3"
    rc=0
    env STUB_LOG="$TMPDIR/log-$3" STUB_TAG="$3" STUB_RESULT="$4" STUB_FAIL="$5" \
      VEILLE_DIR="$2" VEILLE_CLAUDE="$TMPDIR/claude" \
      VEILLE_FETCH="$dir/fixtures/stub-fetch.py" VEILLE_PROMPT="$dir/filter-prompt.md" \
      bash -euo pipefail "$1" 48 > "$TMPDIR/$3.out" 2> "$TMPDIR/$3.err" || rc=$?
  }
  check_d1() { # $1 VEILLE_DIR after run 1 (tri-run1.md), $2 run name
    [ "$(grep -cxF -- "- [$day] Tick — résumé — blog — https://tick.example/" "$1/inbox.md")" = 1 ] || { echo "D1 backtick line not appended once, backticks stripped"; return 1; }
    for n in five.example img.example wiki.example social.example stale.example ftp.example '(rien)'; do
      if grep -qF "$n" "$1/inbox.md"; then
        echo "D1 rejected line appended: $n"
        return 1
      fi
    done
    [ "$(grep -cF 'https://good.example/a' "$1/inbox.md")" = 1 ] || { echo "D1 valid line missing or appended twice"; return 1; }
    [ "$(grep -cF 'https://old.example/a' "$1/inbox.md")" = 1 ] || { echo "D1 URL already in inbox.md appended again"; return 1; }
    grep -qxF 'inbox: 2 ajoutée(s), 2 doublon(s), 6 rejetée(s)' "$TMPDIR/$2.out" || { echo "D1 counters wrong"; return 1; }
  }

  v="$TMPDIR/vault"
  mkdir -p "$v"
  cp "$TMPDIR/seed.md" "$v/inbox.md"
  daily "$dir/daily.sh" "$v" run1 "$dir/fixtures/tri-run1.md" ""
  [ "$rc" = 0 ] || fail "D1 run 1 exit $rc, want 0"
  day=$(cat "$TMPDIR/log-run1/day")
  [ -f "$v/bruts/$day.md" ] && [ -f "$v/tris/$day.json" ] || fail "D1 run 1 wrote no bruts/$day.md + tris/$day.json"
  msg=$(check_d1 "$v" run1) || fail "$msg"
  grep -qxF -- '--safe-mode' "$TMPDIR/log-run1/args" || fail "D1 claude called without --safe-mode"
  cmp -s "$TMPDIR/log-run1/stdin" "$v/bruts/$day.md" || fail "D1 claude stdin is not the raw file"
  if grep -qF 'Candidats stub' "$TMPDIR/log-run1/args"; then fail "D1 raw file passed in argv"; fi
  echo "veille: D1 line filter + dedup OK — $(cat "$TMPDIR/run1.out" | sed -n 1p)"

  { cat "$TMPDIR/seed.md"; printf '\n- [%s] Tick — résumé — blog — https://tick.example/\n- [%s] Good — résumé valide — officiel — https://good.example/a\n' "$day" "$day"; } > "$TMPDIR/inbox1.want"
  diff "$TMPDIR/inbox1.want" "$v/inbox.md" > "$TMPDIR/d2.out" || fail "D2 inbox.md after run 1 is not seed + newline + the valid lines"
  echo "veille: D2 inbox without final newline OK"

  cp "$v/bruts/$day.md" "$TMPDIR/brut1.keep"
  cp "$v/tris/$day.json" "$TMPDIR/tri1.keep"
  daily "$dir/daily.sh" "$v" run2 "$dir/fixtures/tri-run2.md" ""
  [ "$rc" = 0 ] || fail "D3 run 2 exit $rc, want 0"
  cmp -s "$TMPDIR/brut1.keep" "$v/bruts/$day.md" || fail "D3 bruts/$day.md overwritten by run 2"
  cmp -s "$TMPDIR/tri1.keep" "$v/tris/$day.json" || fail "D3 tris/$day.json overwritten by run 2"
  grep -qF 'Candidats stub run2,' "$v/bruts/$day-2.md" || fail "D3 run 2 raw file not in bruts/$day-2.md"
  grep -qF 'second.example' "$v/tris/$day-2.json" || fail "D3 run 2 tri not in tris/$day-2.json"
  grep -qxF 'inbox: 1 ajoutée(s), 1 doublon(s), 0 rejetée(s)' "$TMPDIR/run2.out" || fail "D3 run 2 counters wrong"
  echo "veille: D3 second run same day OK — $(ls "$v/bruts" | tr '\n' ' ')"

  cp -a "$v" "$TMPDIR/vault.before"
  daily "$dir/daily.sh" "$v" run3 "$dir/fixtures/tri-run2.md" 1
  [ "$rc" != 0 ] || fail "D4 run with a failing claude exit 0"
  diff -r "$TMPDIR/vault.before" "$v" > "$TMPDIR/d4.out" || fail "D4 failed run modified VEILLE_DIR"
  grep -qF 'claude rc=3 subtype=error_during_execution' "$TMPDIR/run3.err" || fail "D4 claude failure not logged with rc + subtype"
  echo "veille: D4 failed run leaves the vault untouched — $(cat "$TMPDIR/run3.err")"

  mkdir -p "$TMPDIR/home5" "$TMPDIR/log-run5"
  rc=0
  env -u VEILLE_DIR HOME="$TMPDIR/home5" STUB_LOG="$TMPDIR/log-run5" STUB_TAG=run5 STUB_RESULT="$dir/fixtures/tri-run2.md" \
    VEILLE_CLAUDE="$TMPDIR/claude" VEILLE_FETCH="$dir/fixtures/stub-fetch.py" VEILLE_PROMPT="$dir/filter-prompt.md" \
    bash -euo pipefail "$dir/daily.sh" 48 > "$TMPDIR/run5.out" 2> "$TMPDIR/run5.err" || rc=$?
  [ "$rc" = 0 ] || fail "D5 default run exit $rc"
  d5="$TMPDIR/home5/.local/share/veille-ttw"
  [ -f "$d5/inbox.md" ] && [ -d "$d5/bruts" ] && [ -d "$d5/tris" ] || fail "D5 default run did not write under ~/.local/share/veille-ttw"
  [ ! -e "$TMPDIR/home5/Vaults" ] || fail "D5 default run wrote under ~/Vaults"
  echo "veille: D5 default dir ~/.local/share/veille-ttw, nothing in the vault OK"

  anchor4='if [ "$tirets" != 3 ]; then'
  sed 's/if \[ "\$tirets" != 3 \]; then/if false; then/' "$dir/daily.sh" > "$TMPDIR/daily-c4.sh"
  if [ "$(grep -cF "$anchor4" "$dir/daily.sh")" != 1 ] || grep -qF "$anchor4" "$TMPDIR/daily-c4.sh" || cmp -s "$dir/daily.sh" "$TMPDIR/daily-c4.sh"; then
    fail "canary anchor '$anchor4' gone from daily.sh — the mutant equals the source"
  fi
  vm="$TMPDIR/vault-c4"
  mkdir -p "$vm"
  cp "$TMPDIR/seed.md" "$vm/inbox.md"
  daily "$TMPDIR/daily-c4.sh" "$vm" c4 "$dir/fixtures/tri-run1.md" ""
  [ "$rc" = 0 ] || fail "canary C4 killed by the wrong reason — mutant run exit $rc"
  rc=0
  msg=$(check_d1 "$vm" c4) || rc=$?
  [ "$rc" != 0 ] || fail "canary C4 SURVIVED — D1 passes without the field-count test"
  [ "$msg" = "D1 rejected line appended: five.example" ] || fail "canary C4 killed by the wrong reason: $msg"
  echo "veille: canary C4 killed — $msg"

  echo "veille: 8 cases, 4 canaries — OK"
  touch $out
''
