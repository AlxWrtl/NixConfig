# Runtime check for jev-locate (home/claude-code/jev-locate.nix), offline.
#
#   S1  the BUILT binary's `--self-test` exits 0: split (block sizes, line
#       boundaries, concatenation equals input), window numbering, decision
#       (inclusive thresholds, prev block, block 1 alone, FULL on low present
#       or low confidence), the 1-based `lines A-B` span of the shown blocks
#       (counted on \n, as Read numbers lines), response parsing and window
#       selection
#   S2  no key file (HOME isolated) -> exit 1, stderr names the key file,
#       stdout empty: the caller falls back to a full read
#   S3  empty input file -> exit 1 before the key is read
#
# Canary C1: a copy of the script with CONF_MIN 0.8 -> 0.0 must FAIL its
# self-test; if it passes, the confidence threshold is untested. A guard fails
# the build if the sed anchor is gone (the mutant would equal the source).
# Canary C2: a copy with the line span's `+ 1` dropped (every span off by one)
# must FAIL its self-test on a `line_span:` assertion; same guard.
#
# No network: S2/S3 stop before any request, the self-test injects a fake ask.
{ pkgs }:

let
  jev = (import ../home/claude-code/jev-locate.nix { inherit pkgs; }).jevLocatePkg;
  script = ../home/claude-code/scripts/jev-locate.py;
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.python3
    pkgs.coreutils
    pkgs.gnused
    pkgs.gnugrep
    pkgs.diffutils
  ];
in
pkgs.runCommand "jev-locate-check" { } ''
  export PATH=${runtimePath}
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"

  fail() {
    echo "jev-locate: $1"
    for f in "$TMPDIR"/*.out "$TMPDIR"/*.err; do [ -f "$f" ] && { echo "--- $f"; cat "$f"; }; done
    exit 1
  }

  anchor='^CONF_MIN = 0\.8$'
  sed "s/$anchor/CONF_MIN = 0.0/" ${script} > "$TMPDIR/mutant.py"
  if [ "$(grep -c "$anchor" ${script})" != 1 ] || grep -q "$anchor" "$TMPDIR/mutant.py" || cmp -s ${script} "$TMPDIR/mutant.py"; then
    fail "canary anchor '$anchor' gone from the script — the mutant equals the source"
  fi

  anchor2='^    start = sum(.*) + 1$'
  sed "/$anchor2/s/ + 1\$//" ${script} > "$TMPDIR/mutant2.py"
  if [ "$(grep -c "$anchor2" ${script})" != 1 ] || grep -q "$anchor2" "$TMPDIR/mutant2.py" || cmp -s ${script} "$TMPDIR/mutant2.py"; then
    fail "canary anchor '$anchor2' gone from the script — the mutant equals the source"
  fi

  rc=0
  ${jev}/bin/jev-locate --self-test > "$TMPDIR/s1.out" 2> "$TMPDIR/s1.err" || rc=$?
  [ "$rc" = 0 ] || fail "S1 self-test exit $rc, want 0"
  grep -q '^jev-locate self-test: OK$' "$TMPDIR/s1.out" || fail "S1 self-test did not print OK"
  echo "jev-locate: S1 self-test OK"

  printf 'some page\n' > "$TMPDIR/page.md"
  rc=0
  ${jev}/bin/jev-locate "$TMPDIR/page.md" "what?" > "$TMPDIR/s2.out" 2> "$TMPDIR/s2.err" || rc=$?
  [ "$rc" = 1 ] || fail "S2 missing key: exit $rc, want 1"
  grep -q 'typesafe-api-key' "$TMPDIR/s2.err" || fail "S2 missing key: stderr does not name the key file"
  [ ! -s "$TMPDIR/s2.out" ] || fail "S2 missing key: stdout not empty"
  echo "jev-locate: S2 missing key OK"

  : > "$TMPDIR/empty.md"
  rc=0
  ${jev}/bin/jev-locate "$TMPDIR/empty.md" "what?" > "$TMPDIR/s3.out" 2> "$TMPDIR/s3.err" || rc=$?
  [ "$rc" = 1 ] || fail "S3 empty file: exit $rc, want 1"
  grep -q 'is empty' "$TMPDIR/s3.err" || fail "S3 empty file: stderr does not say empty"
  if grep -q 'typesafe-api-key' "$TMPDIR/s3.err"; then
    fail "S3 empty file: key read before the input was checked"
  fi
  echo "jev-locate: S3 empty file OK"

  rc=0
  python3 -I "$TMPDIR/mutant.py" --self-test > "$TMPDIR/c1.out" 2> "$TMPDIR/c1.err" || rc=$?
  [ "$rc" != 0 ] || fail "canary C1 SURVIVED — CONF_MIN 0.0 still passes the self-test"
  grep -q '^FAIL decide: low confidence must be FULL$' "$TMPDIR/c1.err" || fail "canary C1 killed by the wrong assertion"
  echo "jev-locate: canary C1 killed — $(head -n 1 "$TMPDIR/c1.err")"

  rc=0
  python3 -I "$TMPDIR/mutant2.py" --self-test > "$TMPDIR/c2.out" 2> "$TMPDIR/c2.err" || rc=$?
  [ "$rc" != 0 ] || fail "canary C2 SURVIVED — a line span off by one still passes the self-test"
  grep -q '^FAIL line_span: ' "$TMPDIR/c2.err" || fail "canary C2 killed by the wrong assertion"
  echo "jev-locate: canary C2 killed — $(grep -m 1 '^FAIL line_span: ' "$TMPDIR/c2.err")"

  echo "jev-locate: 3 cases, 2 canaries — OK"
  touch $out
''
