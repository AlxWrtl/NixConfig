# Runtime check for ttw-test-weaken (home/claude-code/ttw-test-weaken.nix): the
# BUILT detector runs against throwaway git repos and must report exactly the
# weakened-test findings each fixture holds, and nothing on the others.
#
# Output contract (one line per finding, then a final count):
#   ttw-test-weaken: assert-removed <path> removed=N added=M
#   ttw-test-weaken: skip-added <path>:<line> <text>
#   ttw-test-weaken: threshold-lowered <path> <key> <old>-><new>
#   ttw-test-weaken: findings=N
# Exit 0 = no finding, 1 = findings, 2 = error. Every non-error run's last
# stdout line is `findings=N`, N = the number of finding lines above it.
#
# Each fixture: a fresh repo on master holding the base files, then branch
# feat/x carrying the change. W1 COMMITS its change on feat/x, every other
# case leaves it in the working tree (W3: untracked): both must be seen.
#
#   W1  src/a.test.ts loses 2 `expect(` lines, gains 0 (committed)
#                                          -> exit 1, assert-removed removed=2 added=0
#   W2  src/a.test.ts gains `it.skip(` at line 7
#                                          -> exit 1, skip-added src/a.test.ts:7
#   W3  UNTRACKED tests/test_new.py holding `@pytest.mark.skip` at line 3
#                                          -> exit 1, skip-added tests/test_new.py:3
#   W4a vitest.config.ts `lines: 80` -> `lines: 60`
#                                          -> exit 1, threshold-lowered lines 80->60
#   W4b package.json `--max-warnings 0` -> `--max-warnings 5`
#                                          -> exit 1, threshold-lowered 0->5
#   W5  one `expect(` line moved inside src/a.test.ts (1 removed, 1 added)
#                                          -> exit 0, no finding, findings=0
#   W6  non-test src/lib.ts loses an `assert(` line
#                                          -> exit 0, no finding, findings=0
#   W7  --base names a ref that does not exist -> exit 2
#   W8  the script copy with `@GIT@` -> a nonexistent path (git missing)
#                                          -> exit 2, `error:` on stderr, no Traceback
#   W9  tests/assertions.test.ts (its path holds `assert`) loses one `expect(`
#                                          -> exit 1, assert-removed removed=1 added=0
#       (the `+++ b/<path>` header is no added line)
#   W10 `my app/package.json` (git ends a path with a space by a TAB)
#       `--max-warnings 0` -> `9`            -> exit 1, threshold-lowered my app/package.json
#   W11 vitest.config.ts `lines: 80` deleted, nothing added
#                                          -> exit 1, threshold-lowered lines 80->none
#   W12 `it.skipIf(` in src/a.test.ts:7 and `self.skipTest(` in an untracked
#       tests/test_skip.py:5              -> exit 1, two skip-added
#   W13 UNTRACKED tests/locked.test.ts made unreadable (chmod 000)
#                                          -> exit 2, error: naming the path, no findings=
#   W7 also asserts an `error:` line on stderr and no Traceback.
#
# Canary C1: a copy of the script with SKIP_RE replaced by a pattern that never
# matches (`x^`) runs W2 and must NOT report skip-added (exit 0, findings=0).
# If it still does, W2's finding comes from something other than the skip rule
# and the W2 assertion proves nothing. Contract: SKIP_RE is one line
# `SKIP_RE = re.compile(...)`.
# Canary C2: a copy with `new < old` turned into `new > old` inside
# `def is_lowered(` runs W4a and must NOT report threshold-lowered (exit 0,
# findings=0). `new > old` inside `is_raised(` (max-warnings) is left alone,
# which is why C2 runs on W4a and not W4b.
# Both canaries fail the build if their sed anchor is gone (the mutant would
# equal the source). Mutants run with python3 after `@GIT@` is substituted.
#
# Offline: git only, HOME and system git config isolated in $TMPDIR.
{ pkgs }:

let
  pkg = (import ../home/claude-code/ttw-test-weaken.nix { inherit pkgs; }).ttwTestWeakenPkg;
  script = ../home/claude-code/scripts/ttw-test-weaken.py;
  py = "${pkgs.python3}/bin/python3";
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.git
    pkgs.gawk
    pkgs.gnugrep
    pkgs.coreutils
    pkgs.diffutils
    pkgs.gnused
  ];

  testBase = pkgs.writeText "a.test.ts" ''
    import { expect, it } from "vitest";
    it("adds", () => {
      expect(1 + 1).toBe(2);
      expect(2 + 2).toBe(4);
      expect(3 + 3).toBe(6);
    });
  '';

  # W1: two assertions dropped, none added.
  testW1 = pkgs.writeText "a.test.ts" ''
    import { expect, it } from "vitest";
    it("adds", () => {
      expect(3 + 3).toBe(6);
    });
  '';

  # W5: the last assertion moved to the top, same file.
  testW5 = pkgs.writeText "a.test.ts" ''
    import { expect, it } from "vitest";
    it("adds", () => {
      expect(3 + 3).toBe(6);
      expect(1 + 1).toBe(2);
      expect(2 + 2).toBe(4);
    });
  '';

  libBase = pkgs.writeText "lib.ts" ''
    import assert from "node:assert";
    export function f(x: number): number {
      assert(x > 0);
      return x;
    }
  '';

  libW6 = pkgs.writeText "lib.ts" ''
    import assert from "node:assert";
    export function f(x: number): number {
      return x;
    }
  '';

  pyW3 = pkgs.writeText "test_new.py" ''
    import pytest

    @pytest.mark.skip(reason="later")
    def test_new():
        assert True
  '';

  vitestBase = pkgs.writeText "vitest.config.ts" ''
    import { defineConfig } from "vitest/config";
    export default defineConfig({
      test: {
        coverage: {
          thresholds: {
            lines: 80,
            branches: 70,
          },
        },
      },
    });
  '';

  vitestW4 = pkgs.writeText "vitest.config.ts" ''
    import { defineConfig } from "vitest/config";
    export default defineConfig({
      test: {
        coverage: {
          thresholds: {
            lines: 60,
            branches: 70,
          },
        },
      },
    });
  '';

  pkgBase = pkgs.writeText "package.json" ''
    {
      "scripts": {
        "lint": "eslint . --max-warnings 0"
      }
    }
  '';

  pkgW4 = pkgs.writeText "package.json" ''
    {
      "scripts": {
        "lint": "eslint . --max-warnings 5"
      }
    }
  '';

  # W9: one of testBase's three assertions dropped.
  testW9 = pkgs.writeText "assertions.test.ts" ''
    import { expect, it } from "vitest";
    it("adds", () => {
      expect(1 + 1).toBe(2);
      expect(3 + 3).toBe(6);
    });
  '';

  pkgW10 = pkgs.writeText "package.json" ''
    {
      "scripts": {
        "lint": "eslint . --max-warnings 9"
      }
    }
  '';

  # W11: the `lines` threshold deleted outright.
  vitestW11 = pkgs.writeText "vitest.config.ts" ''
    import { defineConfig } from "vitest/config";
    export default defineConfig({
      test: {
        coverage: {
          thresholds: {
            branches: 70,
          },
        },
      },
    });
  '';

  pyW12 = pkgs.writeText "test_skip.py" ''
    import unittest

    class T(unittest.TestCase):
        def test_x(self):
            self.skipTest("later")
  '';
in
pkgs.runCommand "ttw-test-weaken-check" { } ''
  export PATH=${runtimePath}
  export HOME="$TMPDIR" GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

  fail() { echo "ttw-test-weaken: $*"; exit 1; }

  sed 's|@GIT@|${pkgs.git}/bin/git|g' ${script} > "$TMPDIR/src.py"

  # Canary C1: SKIP_RE replaced by a pattern that never matches.
  [ "$(grep -c '^SKIP_RE = re\.compile(' "$TMPDIR/src.py")" = 1 ] \
    || fail "canary anchor '^SKIP_RE = re.compile(' not found exactly once in the script — C1's mutant would equal the source"
  sed 's/^SKIP_RE = .*/SKIP_RE = re.compile(r"x^")/' "$TMPDIR/src.py" > "$TMPDIR/c1.py"
  grep -qxF 'SKIP_RE = re.compile(r"x^")' "$TMPDIR/c1.py" \
    || fail "canary C1 sed left no neutralised SKIP_RE line"

  # Canary C2: the lowered-threshold comparison inverted inside is_lowered().
  grep -q '^[[:space:]]*def is_lowered(' "$TMPDIR/src.py" \
    || fail "canary anchor 'def is_lowered(' gone from the script — C2's mutant would equal the source"
  rc=0
  awk '
    /^[ \t]*def / { inf = ($0 ~ /^[ \t]*def is_lowered\(/) }
    inf && index($0, "new < old") { gsub(/new < old/, "new > old"); n++ }
    { print }
    END { if (n < 1) exit 3 }
  ' "$TMPDIR/src.py" > "$TMPDIR/c2.py" || rc=$?
  [ "$rc" = 0 ] || fail "canary anchor 'new < old' absent from the body of is_lowered() — C2's mutant would equal the source"
  if cmp -s "$TMPDIR/src.py" "$TMPDIR/c2.py"; then
    fail "canary C2 mutant equals the source"
  fi

  # fixture NAME: a fresh repo on master with every base file, then feat/x.
  fixture() {
    R="$TMPDIR/$1"
    mkdir -p "$R/src" "$R/tests"
    cd "$R"
    git init -q -b master --template=
    cp ${testBase} src/a.test.ts
    cp ${libBase} src/lib.ts
    cp ${vitestBase} vitest.config.ts
    cp ${pkgBase} package.json
    chmod u+w src/a.test.ts src/lib.ts vitest.config.ts package.json
    git add -A
    git commit -qm init
    git checkout -qb feat/x
  }

  # put SRC DST: overwrite a fixture file with a variant.
  put() { cp "$1" "$2"; chmod u+w "$2"; }

  # run LABEL WANT_RC CMD...: runs CMD (it carries --base) in the current repo into
  # $TMPDIR/LABEL.out; checks the exit code and, unless WANT_RC is 2, that the
  # last line is findings=N with N = the finding lines printed.
  run() {
    label="$1"; want="$2"; shift 2
    of="$TMPDIR/$label.out"
    rc=0
    "$@" > "$of" 2> "$TMPDIR/$label.err" || rc=$?
    if [ "$rc" != "$want" ]; then
      echo "ttw-test-weaken: $label FAILED — exited $rc, want $want. stdout:"
      cat "$of"
      echo "stderr:"
      cat "$TMPDIR/$label.err"
      exit 1
    fi
    [ "$want" = 2 ] && return 0
    n="$(grep -cE '^ttw-test-weaken: (assert-removed|skip-added|threshold-lowered) ' "$of" || true)"
    last="$(tail -n 1 "$of")"
    [ "$last" = "ttw-test-weaken: findings=$n" ] \
      || fail "$label FAILED — last line '$last', want 'ttw-test-weaken: findings=$n'"
    if [ "$want" = 0 ] && [ "$n" != 0 ]; then fail "$label FAILED — exit 0 with $n finding line(s)"; fi
    if [ "$want" = 1 ] && [ "$n" = 0 ]; then fail "$label FAILED — exit 1 with no finding line"; fi
  }

  # count LABEL RULE WANT: exactly WANT lines of RULE in LABEL's output.
  count() {
    got="$(grep -c "^ttw-test-weaken: $2 " "$TMPDIR/$1.out" || true)"
    [ "$got" = "$3" ] || { echo "ttw-test-weaken: $1 FAILED — $got '$2' line(s), want $3:"; cat "$TMPDIR/$1.out"; exit 1; }
  }

  # has LABEL TEXT: some line of LABEL's output starts with TEXT.
  has() {
    awk -v t="$2" 'index($0, t) == 1 { f = 1 } END { exit !f }' "$TMPDIR/$1.out" \
      || { echo "ttw-test-weaken: $1 FAILED — no line starting '$2':"; cat "$TMPDIR/$1.out"; exit 1; }
  }

  # total LABEL N: exactly N finding lines of any rule.
  total() {
    got="$(grep -cE '^ttw-test-weaken: (assert-removed|skip-added|threshold-lowered) ' "$TMPDIR/$1.out" || true)"
    [ "$got" = "$2" ] || { echo "ttw-test-weaken: $1 FAILED — $got finding line(s), want $2:"; cat "$TMPDIR/$1.out"; exit 1; }
  }

  bin=${pkg}/bin/ttw-test-weaken

  # W1: two assertions removed, committed on feat/x.
  fixture w1
  put ${testW1} src/a.test.ts
  git commit -qam weaken
  run w1 1 "$bin" --base master
  has w1 'ttw-test-weaken: assert-removed src/a.test.ts removed=2 added=0'
  count w1 assert-removed 1
  total w1 1
  echo "ttw-test-weaken: W1 assert-removed OK"

  # W2: it.skip( appended as line 7.
  fixture w2
  printf '%s\n' 'it.skip("pending", () => {});' >> src/a.test.ts
  run w2 1 "$bin" --base master
  has w2 'ttw-test-weaken: skip-added src/a.test.ts:7 '
  grep -F 'skip-added src/a.test.ts:7 ' "$TMPDIR/w2.out" | grep -qF 'it.skip(' \
    || fail "W2 FAILED — the skip-added line does not carry the added text"
  count w2 skip-added 1
  total w2 1
  echo "ttw-test-weaken: W2 skip-added OK"

  # W3: an untracked new test file holding a pytest skip.
  fixture w3
  put ${pyW3} tests/test_new.py
  run w3 1 "$bin" --base master
  has w3 'ttw-test-weaken: skip-added tests/test_new.py:3 '
  count w3 skip-added 1
  total w3 1
  echo "ttw-test-weaken: W3 untracked skip-added OK"

  # W4a: coverage threshold lowered.
  fixture w4a
  put ${vitestW4} vitest.config.ts
  run w4a 1 "$bin" --base master
  has w4a 'ttw-test-weaken: threshold-lowered vitest.config.ts lines 80->60'
  count w4a threshold-lowered 1
  total w4a 1
  echo "ttw-test-weaken: W4a lines threshold-lowered OK"

  # W4b: --max-warnings raised (a lowered gate).
  fixture w4b
  put ${pkgW4} package.json
  run w4b 1 "$bin" --base master
  has w4b 'ttw-test-weaken: threshold-lowered package.json '
  grep -E '^ttw-test-weaken: threshold-lowered package\.json ' "$TMPDIR/w4b.out" | grep -qF ' 0->5' \
    || fail "W4b FAILED — the threshold-lowered line does not say 0->5"
  count w4b threshold-lowered 1
  total w4b 1
  echo "ttw-test-weaken: W4b max-warnings threshold-lowered OK"

  # W5: one assertion moved inside the same test file.
  fixture w5
  put ${testW5} src/a.test.ts
  run w5 0 "$bin" --base master
  total w5 0
  [ "$(tail -n 1 "$TMPDIR/w5.out")" = 'ttw-test-weaken: findings=0' ] || fail "W5 FAILED — last line is not findings=0"
  echo "ttw-test-weaken: W5 moved assertion is no finding OK"

  # W6: a non-test file loses an assert( line.
  fixture w6
  put ${libW6} src/lib.ts
  run w6 0 "$bin" --base master
  total w6 0
  echo "ttw-test-weaken: W6 non-test assert removal is no finding OK"

  # W7: unknown base ref.
  fixture w7
  put ${testW1} src/a.test.ts
  run w7 2 "$bin" --base no-such-ref
  grep -qF 'ttw-test-weaken: error:' "$TMPDIR/w7.err" || { cat "$TMPDIR/w7.err"; fail "W7 no error: line on stderr"; }
  if grep -qF 'Traceback' "$TMPDIR/w7.err"; then cat "$TMPDIR/w7.err"; fail "W7 traceback on stderr"; fi
  echo "ttw-test-weaken: W7 unknown --base exits 2 OK"

  # W8: git binary missing -> exit 2 with an error: line, no traceback.
  sed "s|@GIT@|$TMPDIR/no-such-git|g" ${script} > "$TMPDIR/w8.py"
  grep -qF "GIT = \"$TMPDIR/no-such-git\"" "$TMPDIR/w8.py" \
    || fail "W8 sed left no GIT line pointing at the missing binary"
  [ ! -e "$TMPDIR/no-such-git" ] || fail "W8 fixture: $TMPDIR/no-such-git exists"
  fixture w8
  run w8 2 ${py} -I "$TMPDIR/w8.py" --base master
  grep -qF 'ttw-test-weaken: error:' "$TMPDIR/w8.err" || { cat "$TMPDIR/w8.err"; fail "W8 no error: line on stderr"; }
  if grep -qF 'Traceback' "$TMPDIR/w8.err"; then cat "$TMPDIR/w8.err"; fail "W8 traceback on stderr"; fi
  echo "ttw-test-weaken: W8 missing git exits 2 with error: OK"

  # base_add SRC DST: commit DST (a copy of SRC) on master, feat/x reset onto it.
  base_add() {
    git checkout -q master
    mkdir -p "$(dirname "$2")"
    put "$1" "$2"
    git add -A
    git commit -qm "base $2"
    git checkout -qB feat/x
  }

  # W9: a test path holding `assert` loses one expect(.
  fixture w9
  base_add ${testBase} tests/assertions.test.ts
  put ${testW9} tests/assertions.test.ts
  run w9 1 "$bin" --base master
  has w9 'ttw-test-weaken: assert-removed tests/assertions.test.ts removed=1 added=0'
  count w9 assert-removed 1
  total w9 1
  echo "ttw-test-weaken: W9 header line is no added assertion OK"

  # W10: max-warnings raised in a path with a space.
  fixture w10
  base_add ${pkgBase} "my app/package.json"
  put ${pkgW10} "my app/package.json"
  run w10 1 "$bin" --base master
  has w10 'ttw-test-weaken: threshold-lowered my app/package.json max-warnings 0->9'
  count w10 threshold-lowered 1
  total w10 1
  echo "ttw-test-weaken: W10 path with a space threshold-lowered OK"

  # W11: a threshold line deleted, nothing added in its place.
  fixture w11
  put ${vitestW11} vitest.config.ts
  run w11 1 "$bin" --base master
  has w11 'ttw-test-weaken: threshold-lowered vitest.config.ts lines 80->none'
  count w11 threshold-lowered 1
  total w11 1
  echo "ttw-test-weaken: W11 deleted threshold OK"

  # W12: it.skipIf( appended as line 7, self.skipTest( in an untracked file.
  fixture w12
  printf '%s\n' 'it.skipIf(process.env.CI)("ci only", () => {});' >> src/a.test.ts
  put ${pyW12} tests/test_skip.py
  run w12 1 "$bin" --base master
  has w12 'ttw-test-weaken: skip-added src/a.test.ts:7 '
  has w12 'ttw-test-weaken: skip-added tests/test_skip.py:5 '
  count w12 skip-added 2
  total w12 2
  echo "ttw-test-weaken: W12 skipIf and skipTest skip-added OK"

  # W13: an unreadable untracked test file is an error, not a silent skip.
  fixture w13
  put ${testBase} tests/locked.test.ts
  chmod 000 tests/locked.test.ts
  run w13 2 "$bin" --base master
  chmod 644 tests/locked.test.ts
  grep -qF 'error:' "$TMPDIR/w13.err" || { cat "$TMPDIR/w13.err"; fail "W13 no error: line on stderr"; }
  grep -qF 'tests/locked.test.ts' "$TMPDIR/w13.err" || { cat "$TMPDIR/w13.err"; fail "W13 stderr does not name the path"; }
  if grep -qF 'findings=' "$TMPDIR/w13.out"; then cat "$TMPDIR/w13.out"; fail "W13 findings= on stdout"; fi
  echo "ttw-test-weaken: W13 unreadable untracked file exits 2 OK"

  # C1 on W2: skip rule neutralised, no skip-added.
  fixture c1
  printf '%s\n' 'it.skip("pending", () => {});' >> src/a.test.ts
  run c1 0 ${py} -I "$TMPDIR/c1.py" --base master
  count c1 skip-added 0
  echo "ttw-test-weaken: canary C1 killed — W2 without SKIP_RE reports no skip-added"

  # C2 on W4a: threshold comparison inverted, no threshold-lowered.
  fixture c2
  put ${vitestW4} vitest.config.ts
  run c2 0 ${py} -I "$TMPDIR/c2.py" --base master
  count c2 threshold-lowered 0
  echo "ttw-test-weaken: canary C2 killed — W4a with is_lowered inverted reports no threshold-lowered"

  echo "ttw-test-weaken: 14 fixtures, 2 canaries — OK"
  touch $out
''
