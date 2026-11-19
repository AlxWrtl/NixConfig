# Runtime check for the code-metrics filter
# (home/claude-code/scripts/code-metrics-filter.py), offline: no dryer,
# crapper or mutator run here, only the stdlib filter between them and TTW.
#
#   S1  `dup` on a 9-block dryer report: kept blocks printed VERBATIM in input
#       order, blocks and the final count line separated by one blank line,
#       stdout == expected byte for byte, exit 1. Pins: score 1.00 and 0.82
#       kept, a same-file pair kept, changed side left or right, exact path
#       match (`app/lib/a.tsx` is not the changed `app/lib/a.ts`), the ui
#       SEGMENT (`components/uikit/` kept, a root-level `components/ui/` path
#       dropped: the segment is matched on "/" + path), dropped_ui counts only
#       the touched pairs (an untouched ui x ui pair is in neither count)
#   S2  ui x changed pair dropped -> `dropped_ui=1`; a changed path that is
#       itself under components/ui/ is dropped too
#   S3  nothing touched (or an empty changed list) -> `kept=0`, exit 0
#   S4  `No duplicate candidates found.` -> `kept=0 dropped_ui=0 total=0`, exit 0
#   S5  truncated block, empty stdin, missing --changed file, unknown
#       subcommand -> exit 2, stdout empty, reason on stderr
#   S6  `sources`: existing files with a source extension, minus tests and
#       components/ui/, order of the changed list preserved
#   S7  `lines` on a `git diff -U0` produced here by pkgs.git (the git the
#       wrapper runs): count omitted = 1 line, `+c,0` = no line, hunks merged,
#       deleted / mode-only files omitted, `\ No newline` skipped, an added
#       line reading `++ b/fake.md` (`+++ b/fake.md` in the diff) is content,
#       not a file header: the next notes.md hunk stays on notes.md
#
# Canary C1: a copy of the filter with UI_SEGMENT -> "/nonexistent/" must FAIL
# S2 on its count line; a guard fails the build if the anchor line is not
# exactly once in the source (the mutant would equal it).
{ pkgs }:

let
  filter = ../home/claude-code/scripts/code-metrics-filter.py;
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.python3
    pkgs.git
    pkgs.coreutils
    pkgs.gnused
    pkgs.gnugrep
    pkgs.diffutils
  ];

  fixture = pkgs.writeText "code-metrics-dup-fixture.txt" ''
    DUPLICATE score=1.00
      app/lib/format.ts:3-14
      app/server/format-date.ts:8-19

    DUPLICATE score=0.91
      app/lib/util.ts:10-20
      app/lib/util.ts:40-50

    DUPLICATE score=0.88
      app/components/ui/button.tsx:5-30
      app/lib/form.ts:12-37

    DUPLICATE score=0.86
      app/components/uikit/x.ts:1-12
      app/lib/form.ts:50-61

    DUPLICATE score=0.84
      app/lib/a.tsx:2-15
      app/server/b.ts:4-17

    DUPLICATE score=0.82
      app/routes/home.tsx:20-41
      app/routes/about.tsx:18-39

    DUPLICATE score=0.80
      app/server/x.ts:1-9
      app/server/y.ts:3-11

    DUPLICATE score=0.79
      app/components/ui/card.tsx:4-16
      app/components/ui/dialog.tsx:7-19

    DUPLICATE score=0.78
      app/lib/format.ts:30-39
      components/ui/badge.tsx:1-10
  '';

  truncated = pkgs.writeText "code-metrics-dup-truncated.txt" ''
    DUPLICATE score=1.00
      app/lib/format.ts:3-14
      app/server/format-date.ts:8-19

    DUPLICATE score=0.91
      app/lib/util.ts:10-20
  '';

  noCandidates = pkgs.writeText "code-metrics-dup-none.txt" ''
    No duplicate candidates found.
  '';

  changedS1 = pkgs.writeText "code-metrics-changed-s1.txt" ''
    app/lib/format.ts
    app/routes/about.tsx
    app/lib/util.ts
    app/lib/form.ts
    app/lib/a.ts
  '';

  changedS2 = pkgs.writeText "code-metrics-changed-s2.txt" ''
    app/lib/form.ts
  '';

  changedS2b = pkgs.writeText "code-metrics-changed-s2b.txt" ''
    app/components/ui/card.tsx
  '';

  changedS3 = pkgs.writeText "code-metrics-changed-s3.txt" ''
    app/lib/a.ts
    docs/readme.md
  '';

  emptyChanged = pkgs.writeText "code-metrics-changed-empty.txt" "";

  expectedS1 = pkgs.writeText "code-metrics-expected-s1.txt" ''
    DUPLICATE score=1.00
      app/lib/format.ts:3-14
      app/server/format-date.ts:8-19

    DUPLICATE score=0.91
      app/lib/util.ts:10-20
      app/lib/util.ts:40-50

    DUPLICATE score=0.86
      app/components/uikit/x.ts:1-12
      app/lib/form.ts:50-61

    DUPLICATE score=0.82
      app/routes/home.tsx:20-41
      app/routes/about.tsx:18-39

    code-metrics dup: kept=4 dropped_ui=2 total=9
  '';

  expectedS2 = pkgs.writeText "code-metrics-expected-s2.txt" ''
    DUPLICATE score=0.86
      app/components/uikit/x.ts:1-12
      app/lib/form.ts:50-61

    code-metrics dup: kept=1 dropped_ui=1 total=9
  '';

  expectedS2b = pkgs.writeText "code-metrics-expected-s2b.txt" ''
    code-metrics dup: kept=0 dropped_ui=1 total=9
  '';

  expectedS3 = pkgs.writeText "code-metrics-expected-s3.txt" ''
    code-metrics dup: kept=0 dropped_ui=0 total=9
  '';

  expectedS4 = pkgs.writeText "code-metrics-expected-s4.txt" ''
    code-metrics dup: kept=0 dropped_ui=0 total=0
  '';

  # S6: every path is created as a file except app/lib/deleted.ts (absent)
  # and app/dir.ts (a directory).
  changedSrc = pkgs.writeText "code-metrics-changed-src.txt" ''
    server/main.go
    app/lib/deleted.ts
    docs/guide.md
    app/lib/format.ts
    app/lib/format.test.ts
    app/lib/form.spec.tsx
    tests/helpers.py
    app/test/setup.ts
    app/__tests__/x.js
    spec/z.go
    app/tests/y.py
    app/components/ui/button.tsx
    components/ui/badge.tsx
    app/components/uikit/x.ts
    app/dir.ts
    app/testing/util.ts
    app/contest.ts
    src/lib.rs
    scripts/tool.py
    a.mjs
    b.cjs
    c.jsx
    app/Main.java
    app/core.clj
    app/view.tsx
    README
    app/lib/format.ts.orig
  '';

  expectedSrc = pkgs.writeText "code-metrics-expected-src.txt" ''
    server/main.go
    app/lib/format.ts
    app/components/uikit/x.ts
    app/testing/util.ts
    app/contest.ts
    src/lib.rs
    scripts/tool.py
    a.mjs
    b.cjs
    c.jsx
    app/Main.java
    app/core.clj
    app/view.tsx
  '';
in
pkgs.runCommand "code-metrics-check" { } ''
  export PATH=${runtimePath}
  export HOME="$TMPDIR/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  mkdir -p "$HOME"
  why=""

  fail() {
    echo "code-metrics: $1"
    for f in "$TMPDIR"/*.out "$TMPDIR"/*.err "$TMPDIR"/*.diff; do [ -f "$f" ] && { echo "--- $f"; cat "$f"; }; done
    exit 1
  }

  # rundup SCRIPT CHANGED INPUT TAG -> $rc, $TMPDIR/TAG.out, $TMPDIR/TAG.err
  rundup() {
    rc=0
    python3 -I "$1" dup --changed "$2" < "$3" > "$TMPDIR/$4.out" 2> "$TMPDIR/$4.err" || rc=$?
  }

  # expect_dup TAG WANT_RC EXPECTED_FILE: exit code, then the count line, then
  # stdout byte for byte; on failure returns 1 with the reason in $why.
  expect_dup() {
    [ "$rc" = "$2" ] || { why="$1 exit $rc, want $2"; return 1; }
    got=$(tail -n 1 "$TMPDIR/$1.out")
    want=$(tail -n 1 "$3")
    [ "$got" = "$want" ] || { why="$1 count line: got '$got', want '$want'"; return 1; }
    cmp -s "$3" "$TMPDIR/$1.out" || { why="$1 stdout differs from the expected text"; return 1; }
  }

  s2() {
    rundup "$1" ${changedS2} ${fixture} "$2"
    expect_dup "$2" 1 ${expectedS2} || return 1
    if grep -q 'components/ui/button.tsx' "$TMPDIR/$2.out"; then why="$2 ui pair printed"; return 1; fi
    rundup "$1" ${changedS2b} ${fixture} "$2-b"
    expect_dup "$2-b" 0 ${expectedS2b} || return 1
  }

  anchor='^UI_SEGMENT = "/components/ui/"$'
  sed "s|$anchor|UI_SEGMENT = \"/nonexistent/\"|" ${filter} > "$TMPDIR/mutant.py"
  if [ "$(grep -c "$anchor" ${filter})" != 1 ] || grep -q "$anchor" "$TMPDIR/mutant.py" || cmp -s ${filter} "$TMPDIR/mutant.py"; then
    fail "canary anchor '$anchor' not exactly once in the filter — the mutant equals the source"
  fi

  rundup ${filter} ${changedS1} ${fixture} s1
  expect_dup s1 1 ${expectedS1} || fail "S1 $why"
  echo "code-metrics: S1 dup report OK"

  s2 ${filter} s2 || fail "S2 $why"
  echo "code-metrics: S2 ui pair dropped OK"

  rundup ${filter} ${changedS3} ${fixture} s3
  expect_dup s3 0 ${expectedS3} || fail "S3 $why"
  rundup ${filter} ${emptyChanged} ${fixture} s3-empty
  expect_dup s3-empty 0 ${expectedS3} || fail "S3 $why"
  echo "code-metrics: S3 nothing touched OK"

  rundup ${filter} ${changedS1} ${noCandidates} s4
  expect_dup s4 0 ${expectedS4} || fail "S4 $why"
  echo "code-metrics: S4 no candidates OK"

  : > "$TMPDIR/empty.txt"
  for c in truncated empty nochanged usage; do
    rc=0
    case $c in
      truncated) python3 -I ${filter} dup --changed ${changedS1} < ${truncated} ;;
      empty) python3 -I ${filter} dup --changed ${changedS1} < "$TMPDIR/empty.txt" ;;
      nochanged) python3 -I ${filter} dup --changed "$TMPDIR/absent.txt" < ${fixture} ;;
      usage) python3 -I ${filter} frobnicate < ${fixture} ;;
    esac > "$TMPDIR/s5-$c.out" 2> "$TMPDIR/s5-$c.err" || rc=$?
    [ "$rc" = 2 ] || fail "S5 $c: exit $rc, want 2"
    [ ! -s "$TMPDIR/s5-$c.out" ] || fail "S5 $c: stdout not empty"
    [ -s "$TMPDIR/s5-$c.err" ] || fail "S5 $c: no reason on stderr"
  done
  echo "code-metrics: S5 malformed input / usage -> exit 2 OK"

  mkdir -p "$TMPDIR/src/app/dir.ts"
  while IFS= read -r f; do
    case $f in app/lib/deleted.ts | app/dir.ts) continue ;; esac
    mkdir -p "$TMPDIR/src/$(dirname "$f")"
    printf 'x\n' > "$TMPDIR/src/$f"
  done < ${changedSrc}
  [ ! -e "$TMPDIR/src/app/lib/deleted.ts" ] && [ -d "$TMPDIR/src/app/dir.ts" ] || fail "S6 fixture tree wrong"
  rc=0
  (cd "$TMPDIR/src" && python3 -I ${filter} sources --changed ${changedSrc}) > "$TMPDIR/s6.out" 2> "$TMPDIR/s6.err" || rc=$?
  [ "$rc" = 0 ] || fail "S6 sources: exit $rc, want 0"
  cmp -s ${expectedSrc} "$TMPDIR/s6.out" || fail "S6 sources: stdout differs from the expected list"
  rc=0
  (cd "$TMPDIR/src" && python3 -I ${filter} sources --changed ${emptyChanged}) > "$TMPDIR/s6-empty.out" 2> "$TMPDIR/s6-empty.err" || rc=$?
  [ "$rc" = 0 ] && [ ! -s "$TMPDIR/s6-empty.out" ] || fail "S6 sources on an empty list: exit $rc or stdout not empty"
  echo "code-metrics: S6 sources OK"

  g() { git -c core.fsmonitor=false -c commit.gpgsign=false -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }
  mkdir -p "$TMPDIR/repo/app/lib"
  cd "$TMPDIR/repo"
  g init -q --template= --separate-git-dir "$TMPDIR/repo.git" .
  for i in 1 2 3 4 5 6 7 8 9 10; do echo "export const l$i = $i;"; done > app/lib/format.ts
  printf 'a\nb\nc\n' > app/lib/old.ts
  for i in 1 2 3 4 5 6 7 8; do echo "const t$i = 0;"; done > app/lib/trim.ts
  printf '# notes\n\nend\n' > notes.md
  printf '#!/bin/sh\necho hi\n' > run.sh
  printf 'const x = 1;\nconst y = 2;\nconst z = 3;' > app/lib/nonl.ts
  g add -A
  g commit -qm base
  for i in 1 2 33 4 6 7 extraA extraB 8 9 10; do
    case $i in
      33) echo "export const l3 = 33;" ;;
      extra*) echo "export const $i = 1;" ;;
      *) echo "export const l$i = $i;" ;;
    esac
  done > app/lib/format.ts
  rm app/lib/old.ts
  printf 'export const n1 = 1;\nexport const n2 = 2;\nexport const n3 = 3;\n' > app/lib/new.ts
  for i in 1 4 5 6 7 8; do echo "const t$i = 0;"; done > app/lib/trim.ts
  printf '# notes\n++ b/fake.md\n\nfin\n' > notes.md
  chmod +x run.sh
  printf 'const x = 1;\nconst y = 2;\nconst z = 4;' > app/lib/nonl.ts
  g add -A
  g diff -U0 HEAD > "$TMPDIR/s7.diff"
  cd "$TMPDIR"
  for trap in '^@@ -3 +3 @@' '^@@ -5 +4,0 @@' '^@@ -7,0 +7,2 @@' '^@@ -0,0 +1,3 @@' '^+++ /dev/null$' '^\\ No newline at end of file$' '^+++ b/fake\.md$' '^@@ -3 +4 @@' '^old mode 100644$' '^@@ -2,2 +1,0 @@'; do
    grep -q "$trap" "$TMPDIR/s7.diff" || fail "S7 fixture lost its trap '$trap' — git output changed"
  done
  printf 'app/lib/format.ts\t3,7,8\napp/lib/new.ts\t1,2,3\napp/lib/nonl.ts\t3\nnotes.md\t2,4\n' > "$TMPDIR/s7.expected"
  rc=0
  python3 -I ${filter} lines < "$TMPDIR/s7.diff" > "$TMPDIR/s7.out" 2> "$TMPDIR/s7.err" || rc=$?
  [ "$rc" = 0 ] || fail "S7 lines: exit $rc, want 0"
  cmp -s "$TMPDIR/s7.expected" "$TMPDIR/s7.out" || fail "S7 lines: stdout differs from the expected map"
  rc=0
  python3 -I ${filter} lines < "$TMPDIR/empty.txt" > "$TMPDIR/s7-empty.out" 2> "$TMPDIR/s7-empty.err" || rc=$?
  [ "$rc" = 0 ] && [ ! -s "$TMPDIR/s7-empty.out" ] || fail "S7 lines on an empty diff: exit $rc or stdout not empty"
  echo "code-metrics: S7 lines OK"

  why=""
  if s2 "$TMPDIR/mutant.py" c1; then
    fail "canary C1 SURVIVED — UI_SEGMENT /nonexistent/ still passes S2"
  fi
  case $why in
    "c1 count line:"*) ;;
    *) fail "canary C1 killed by the wrong assertion: $why" ;;
  esac
  echo "code-metrics: canary C1 killed — $why"

  echo "code-metrics: 7 scenarios, 1 canary — OK"
  touch $out
''
