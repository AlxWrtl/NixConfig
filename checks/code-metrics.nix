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
#   S8  `dup --base main` through the BUILT wrapper on two git repos, against a
#       fake venv whose dryer is the pinned input's real cli/discover/model/
#       report plus a stub scanner pairing every same-language file (no
#       tree-sitter here). Repo A: git-ignored .claude/worktrees copies,
#       x.test.ts and node_modules/ never in stdout; the top-level -dash.ts
#       (an option if passed bare), app/-dash.ts and app/one.ts present; the
#       committed then deleted app/gone.ts (still in `ls-files -c`) dropped;
#       4 .ts files paired -> `kept=6 dropped_ui=0 total=6`, exit 1. Repo B
#       (README.md tracked, only ignored sources):
#       stdout exactly `kept=0 dropped_ui=0 total=0`, exit 0
#   S9  the dryer report: the pinned report module writes .metrics/dry.edn
#       in the repo top on every analysis; after `dup` on repo A without
#       .metrics/, neither git status nor the disk shows it; a pre-existing
#       .metrics/dry.edn (rewritten by dryer) and a user file beside it are
#       kept; a pre-existing .metrics/ without dry.edn keeps its files and
#       loses only the new report; a pre-existing EMPTY .metrics/ survives
#       (an rmdir would succeed on it) and loses only the new report
#
# Canary C1: a copy of the filter with UI_SEGMENT -> "/nonexistent/" must FAIL
# S2 on its count line; a guard fails the build if the anchor line is not
# exactly once in the source (the mutant would equal it).
# Canary C2: a copy of the built wrapper with `--exclude-standard` dropped
# from `ls-files -co --exclude-standard -z` must FAIL S8 repo A on the
# ignored-path assertion; same anchor guard, checked after S8.
# Canaries C3/C4: a copy of the dryer-files script without the `./` prefix
# (C3) or without its isfile check (C4), wired into a copy of the built
# wrapper through its DRYER_FILES line, must FAIL S8 repo A on the
# `  -dash.ts:` assertion, with dryer's `Unknown option: -dash.ts` (C3) or the
# filter rejecting dryer's output, exit 2 (C4: app/gone.ts became a substring
# filter) on stderr; same anchor guard, plus DRYER_FILES exactly once.
# Canary C5: a copy of the built wrapper with its `rm -f .metrics/dry.edn`
# line turned into `:` must FAIL S9's first case on the git status assertion; same anchor
# guard.
# Canary C6: a copy of the built wrapper with its `had_dir` guard dropped (the
# rmdir runs whenever .metrics/ exists) must FAIL S9's empty-dir case on the
# dir-removed assertion; same anchor guard.
{
  pkgs,
  crapper,
  mutator,
  dryer,
}:

let
  filter = ../home/claude-code/scripts/code-metrics-filter.py;
  dryerFiles = ../home/claude-code/scripts/code-metrics-dryer-files.py;
  wrapper = "${
    (import ../home/claude-code/code-metrics.nix {
      inherit
        pkgs
        crapper
        mutator
        dryer
        ;
    }).codeMetricsPkg
  }/bin/code-metrics";

  # Stands in for dryer.scan (tree-sitter): one 5-line entry per source file,
  # every same-language pair scores 1.0, in the order of the files dryer's
  # own cli selected.
  stubScan = pkgs.writeText "dryer-scan-stub.py" ''
    """Stub dryer.scan for checks/code-metrics.nix."""

    from __future__ import annotations

    from pathlib import Path

    from dryer.discover import language_of
    from dryer.model import Duplicate, Entry, Span


    def display_path(path: Path, root: Path) -> str:
        resolved = Path(path).resolve()
        try:
            return resolved.relative_to(Path(root).resolve()).as_posix()
        except ValueError:
            return resolved.as_posix()


    def scan_files(files, root, min_lines, min_nodes):
        entries = []
        for path in files:
            language = language_of(path)
            if language is None:
                continue
            entries.append(Entry(language, display_path(path, root), 1, 5, 20, frozenset()))
        return entries, []


    def find_duplicates(entries, threshold):
        found = []
        for index, left in enumerate(entries):
            for right in entries[index + 1:]:
                if left.language != right.language:
                    continue
                found.append(
                    Duplicate(1.0, left.language, Span(left.file, 1, 5), Span(right.file, 1, 5), 20, 20)
                )
        return found
  '';
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

  mkdir -p "$TMPDIR/stub/dryer" "$TMPDIR/xdg/code-metrics/venv/bin"
  for f in __init__ __main__ cli discover model report; do
    cp ${dryer}/src/dryer/$f.py "$TMPDIR/stub/dryer/$f.py"
  done
  cp ${stubScan} "$TMPDIR/stub/dryer/scan.py"
  printf '#!%s\nexec %s "$@"\n' ${pkgs.runtimeShell} ${pkgs.python3}/bin/python3 > "$TMPDIR/xdg/code-metrics/venv/bin/python"
  chmod +x "$TMPDIR/xdg/code-metrics/venv/bin/python"
  printf '%s\n' ${crapper} ${mutator} ${dryer} > "$TMPDIR/xdg/code-metrics/.ready"

  mkdir -p "$TMPDIR/repoA/app" "$TMPDIR/repoA/node_modules/m" "$TMPDIR/repoA/.claude/worktrees/old/app"
  cd "$TMPDIR/repoA"
  g init -q --template= --separate-git-dir "$TMPDIR/repoA.git" .
  printf '.claude/\n' > .gitignore
  printf 'export const b = 1;\n' > app/base.ts
  printf 'export const g = 1;\n' > app/gone.ts
  g add .gitignore app/base.ts app/gone.ts
  g commit -qm base
  rm app/gone.ts
  for f in app/one.ts -dash.ts app/-dash.ts app/x.test.ts node_modules/m/i.ts .claude/worktrees/old/app/one.ts .claude/worktrees/old/app/two.ts; do
    printf 'export const v = 1;\n' > "$f"
  done
  printf '# a\n' > README.md
  g check-ignore -q .claude/worktrees/old/app/one.ts || fail "S8 fixture: repo A does not ignore .claude/"
  [ "$(g ls-files | tr '\n' ' ')" = ".gitignore app/base.ts app/gone.ts " ] || fail "S8 fixture: repo A tracks the wrong files"
  [ ! -e app/gone.ts ] && [ -f ./-dash.ts ] || fail "S8 fixture: repo A app/gone.ts not deleted or -dash.ts missing"
  mkdir -p "$TMPDIR/repoB/.claude/worktrees/old"
  cd "$TMPDIR/repoB"
  g init -q --template= --separate-git-dir "$TMPDIR/repoB.git" .
  mkdir -p "$TMPDIR/repoB.git/info"
  printf '.claude/\n' > "$TMPDIR/repoB.git/info/exclude"
  printf '# b\n' > README.md
  g add README.md
  g commit -qm base
  printf 'export const a = 1;\n' > .claude/worktrees/old/a.ts
  printf 'export const b = 1;\n' > .claude/worktrees/old/b.ts
  [ "$(g ls-files -co --exclude-standard)" = README.md ] || fail "S8 fixture: repo B lists more than README.md"
  cd "$TMPDIR"

  # runcm WRAPPER REPO TAG -> $rc, $TMPDIR/TAG.out, $TMPDIR/TAG.err; the
  # report dryer writes is removed so every run sees the same tree.
  runcm() {
    rc=0
    (cd "$2" && XDG_CACHE_HOME="$TMPDIR/xdg" PYTHONPATH="$TMPDIR/stub" ${pkgs.bash}/bin/bash "$1" dup --base main) > "$TMPDIR/$3.out" 2> "$TMPDIR/$3.err" || rc=$?
    rm -rf "$2/.metrics"
  }

  # s8a WRAPPER TAG: repo A; on failure returns 1 with the reason in $why.
  # stdout is checked before the exit code, so a run that dies (exit 2,
  # empty stdout) is reported by the first file it lost.
  s8a() {
    runcm "$1" "$TMPDIR/repoA" "$2"
    o="$TMPDIR/$2.out"
    if grep -qF '.claude/worktrees' "$o"; then why="$2 ignored path .claude/worktrees in stdout"; return 1; fi
    for p in x.test.ts node_modules gone.ts; do
      if grep -qF "$p" "$o"; then why="$2 $p in stdout"; return 1; fi
    done
    for p in '  -dash.ts:' 'app/-dash.ts:' 'app/one.ts:'; do
      grep -qF -- "$p" "$o" || { why="$2 '$p' missing from stdout"; return 1; }
    done
    [ "$rc" = 1 ] || { why="$2 exit $rc, want 1"; return 1; }
    got=$(tail -n 1 "$o")
    [ "$got" = 'code-metrics dup: kept=6 dropped_ui=0 total=6' ] || { why="$2 count line: got '$got', want 'code-metrics dup: kept=6 dropped_ui=0 total=6'"; return 1; }
  }

  # dfmutant TAG ANCHOR SED: copy of the dryer-files script with SED applied
  # (ANCHOR exactly once in the source, gone from the mutant), wired into a
  # copy of the built wrapper -> $TMPDIR/cm-TAG.
  dfmutant() {
    sed "$3" ${dryerFiles} > "$TMPDIR/df-$1.py"
    if [ "$(grep -cF -- "$2" ${dryerFiles})" != 1 ] || grep -qF -- "$2" "$TMPDIR/df-$1.py" || cmp -s ${dryerFiles} "$TMPDIR/df-$1.py"; then
      fail "canary anchor '$2' not exactly once in the dryer-files script — the mutant equals the source"
    fi
    sed "s|^DRYER_FILES=.*|DRYER_FILES=\"$TMPDIR/df-$1.py\"|" ${wrapper} > "$TMPDIR/cm-$1"
    if [ "$(grep -c '^DRYER_FILES=' ${wrapper})" != 1 ] || ! grep -qxF "DRYER_FILES=\"$TMPDIR/df-$1.py\"" "$TMPDIR/cm-$1"; then
      fail "canary $1: DRYER_FILES not exactly once in the wrapper — the mutant is not wired"
    fi
  }

  s8a ${wrapper} s8-a || fail "S8 repo A: $why"
  runcm ${wrapper} "$TMPDIR/repoB" s8-b
  [ "$rc" = 0 ] || fail "S8 repo B: exit $rc, want 0"
  printf 'code-metrics dup: kept=0 dropped_ui=0 total=0\n' > "$TMPDIR/s8-b.want"
  cmp -s "$TMPDIR/s8-b.want" "$TMPDIR/s8-b.out" || fail "S8 repo B: stdout is not exactly the empty count line"
  echo "code-metrics: S8 wrapper dup on git-listed files OK"

  # s9 WRAPPER TAG: dup on repo A with no .metrics/ before; the pinned
  # report module writes .metrics/dry.edn (its `Wrote` line on stderr), the
  # wrapper must leave neither it nor the dir. Cleans up before asserting.
  s9() {
    rc=0
    (cd "$TMPDIR/repoA" && XDG_CACHE_HOME="$TMPDIR/xdg" PYTHONPATH="$TMPDIR/stub" ${pkgs.bash}/bin/bash "$1" dup --base main) > "$TMPDIR/$2.out" 2> "$TMPDIR/$2.err" || rc=$?
    st=$(cd "$TMPDIR/repoA" && g status --porcelain --untracked-files=all)
    left=0
    [ ! -e "$TMPDIR/repoA/.metrics" ] || left=1
    rm -rf "$TMPDIR/repoA/.metrics"
    grep -qF '/.metrics/dry.edn' "$TMPDIR/$2.err" || { why="$2 dryer wrote no .metrics/dry.edn (no Wrote line)"; return 1; }
    case $st in *.metrics*) why="$2 .metrics left in git status"; return 1 ;; esac
    [ "$left" = 0 ] || { why="$2 .metrics left on disk"; return 1; }
    [ "$rc" = 1 ] || { why="$2 exit $rc, want 1"; return 1; }
  }

  [ ! -e "$TMPDIR/repoA/.metrics" ] || fail "S9 fixture: repo A already has .metrics/"
  s9 ${wrapper} s9 || fail "S9 no .metrics before: $why"
  # Pre-existing report (dryer rewrites it) and a file of the user's: kept.
  mkdir -p "$TMPDIR/repoA/.metrics"
  printf 'mine\n' > "$TMPDIR/repoA/.metrics/keep.txt"
  printf 'old report\n' > "$TMPDIR/repoA/.metrics/dry.edn"
  rc=0
  (cd "$TMPDIR/repoA" && XDG_CACHE_HOME="$TMPDIR/xdg" PYTHONPATH="$TMPDIR/stub" ${pkgs.bash}/bin/bash ${wrapper} dup --base main) > "$TMPDIR/s9-kept.out" 2> "$TMPDIR/s9-kept.err" || rc=$?
  [ "$rc" = 1 ] || fail "S9 pre-existing report: exit $rc, want 1"
  [ -s "$TMPDIR/repoA/.metrics/dry.edn" ] || fail "S9 pre-existing .metrics/dry.edn removed"
  [ "$(cat "$TMPDIR/repoA/.metrics/keep.txt")" = mine ] || fail "S9 pre-existing .metrics/keep.txt lost"
  rm "$TMPDIR/repoA/.metrics/dry.edn"
  rc=0
  (cd "$TMPDIR/repoA" && XDG_CACHE_HOME="$TMPDIR/xdg" PYTHONPATH="$TMPDIR/stub" ${pkgs.bash}/bin/bash ${wrapper} dup --base main) > "$TMPDIR/s9-dir.out" 2> "$TMPDIR/s9-dir.err" || rc=$?
  [ "$rc" = 1 ] || fail "S9 pre-existing dir: exit $rc, want 1"
  [ ! -e "$TMPDIR/repoA/.metrics/dry.edn" ] || fail "S9 pre-existing dir: the new .metrics/dry.edn was left"
  [ "$(cat "$TMPDIR/repoA/.metrics/keep.txt")" = mine ] || fail "S9 pre-existing dir: .metrics/ or keep.txt removed"
  rm -rf "$TMPDIR/repoA/.metrics"

  # s9e WRAPPER TAG: dup on repo A whose .metrics/ exists EMPTY: the new
  # dry.edn goes, the dir stays (an rmdir would succeed on it, so only the
  # had_dir guard keeps it). Cleans up before asserting.
  s9e() {
    rm -rf "$TMPDIR/repoA/.metrics"
    mkdir "$TMPDIR/repoA/.metrics"
    rc=0
    (cd "$TMPDIR/repoA" && XDG_CACHE_HOME="$TMPDIR/xdg" PYTHONPATH="$TMPDIR/stub" ${pkgs.bash}/bin/bash "$1" dup --base main) > "$TMPDIR/$2.out" 2> "$TMPDIR/$2.err" || rc=$?
    dir=0
    [ -d "$TMPDIR/repoA/.metrics" ] || dir=1
    report=0
    [ ! -e "$TMPDIR/repoA/.metrics/dry.edn" ] || report=1
    rm -rf "$TMPDIR/repoA/.metrics"
    grep -qF '/.metrics/dry.edn' "$TMPDIR/$2.err" || { why="$2 dryer wrote no .metrics/dry.edn (no Wrote line)"; return 1; }
    [ "$dir" = 0 ] || { why="$2 pre-existing empty .metrics/ removed"; return 1; }
    [ "$report" = 0 ] || { why="$2 the new .metrics/dry.edn was left"; return 1; }
    [ "$rc" = 1 ] || { why="$2 exit $rc, want 1"; return 1; }
  }
  s9e ${wrapper} s9-empty || fail "S9 pre-existing empty dir: $why"
  echo "code-metrics: S9 dryer report cleaned only when this run created it OK"

  why=""
  if s2 "$TMPDIR/mutant.py" c1; then
    fail "canary C1 SURVIVED — UI_SEGMENT /nonexistent/ still passes S2"
  fi
  case $why in
    "c1 count line:"*) ;;
    *) fail "canary C1 killed by the wrong assertion: $why" ;;
  esac
  echo "code-metrics: canary C1 killed — $why"

  anchor2='ls-files -co --exclude-standard -z'
  sed "s|$anchor2|ls-files -co -z|" ${wrapper} > "$TMPDIR/cm-mutant"
  if [ "$(grep -cF -- "$anchor2" ${wrapper})" != 1 ] || grep -qF -- "$anchor2" "$TMPDIR/cm-mutant" || cmp -s ${wrapper} "$TMPDIR/cm-mutant"; then
    fail "canary anchor '$anchor2' not exactly once in the wrapper — the mutant equals the source"
  fi
  why=""
  if s8a "$TMPDIR/cm-mutant" c2; then
    fail "canary C2 SURVIVED — ls-files without --exclude-standard still passes S8"
  fi
  case $why in
    "c2 ignored path"*) ;;
    *) fail "canary C2 killed by the wrong assertion: $why" ;;
  esac
  echo "code-metrics: canary C2 killed — $why"

  dfmutant c3 '"./" + ' 's|"\./" + ||'
  why=""
  if s8a "$TMPDIR/cm-c3" c3; then
    fail "canary C3 SURVIVED — dryer-files without the ./ prefix still passes S8"
  fi
  case $why in
    "c3 '  -dash.ts:' missing"*) grep -qF 'Unknown option: -dash.ts' "$TMPDIR/c3.err" || fail "canary C3 killed without dryer's option error: $why" ;;
    *) fail "canary C3 killed by the wrong assertion: $why" ;;
  esac
  echo "code-metrics: canary C3 killed — $why"

  dfmutant c4 'if not os.path.isfile(path):' 's|if not os\.path\.isfile(path):|if False:|'
  why=""
  if s8a "$TMPDIR/cm-c4" c4; then
    fail "canary C4 SURVIVED — dryer-files without the isfile check still passes S8"
  fi
  case $why in
    "c4 '  -dash.ts:' missing"*) [ "$rc" = 2 ] && grep -qF 'code-metrics-filter dup:' "$TMPDIR/c4.err" || fail "canary C4 killed without the filter rejecting dryer's output (exit $rc): $why" ;;
    *) fail "canary C4 killed by the wrong assertion: $why" ;;
  esac
  echo "code-metrics: canary C4 killed — $why"

  anchor5='^ *rm -f \.metrics/dry\.edn$'
  sed "s|$anchor5|    :|" ${wrapper} > "$TMPDIR/cm-c5"
  if [ "$(grep -c "$anchor5" ${wrapper})" != 1 ] || grep -q "$anchor5" "$TMPDIR/cm-c5" || cmp -s ${wrapper} "$TMPDIR/cm-c5"; then
    fail "canary anchor '$anchor5' not exactly once in the wrapper — the mutant equals the source"
  fi
  why=""
  if s9 "$TMPDIR/cm-c5" c5; then
    fail "canary C5 SURVIVED — the wrapper without its dry.edn cleanup still passes S9"
  fi
  case $why in
    "c5 .metrics left in git status") ;;
    *) fail "canary C5 killed by the wrong assertion: $why" ;;
  esac
  echo "code-metrics: canary C5 killed — $why"

  anchor6='^ *if \[ "\$had_dir" = 0 \] && \[ -d \.metrics \]; then$'
  sed "s|$anchor6|  if [ -d .metrics ]; then|" ${wrapper} > "$TMPDIR/cm-c6"
  if [ "$(grep -c "$anchor6" ${wrapper})" != 1 ] || grep -q "$anchor6" "$TMPDIR/cm-c6" || cmp -s ${wrapper} "$TMPDIR/cm-c6"; then
    fail "canary anchor '$anchor6' not exactly once in the wrapper — the mutant equals the source"
  fi
  why=""
  if s9e "$TMPDIR/cm-c6" c6; then
    fail "canary C6 SURVIVED — the wrapper without its had_dir guard still keeps an empty pre-existing .metrics/"
  fi
  case $why in
    "c6 pre-existing empty .metrics/ removed") ;;
    *) fail "canary C6 killed by the wrong assertion: $why" ;;
  esac
  echo "code-metrics: canary C6 killed — $why"

  echo "code-metrics: 9 scenarios, 6 canaries — OK"
  touch $out
''
