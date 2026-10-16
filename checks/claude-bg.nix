# Non-regression check for the `claude-bg` wrapper
# (home/claude-code/claude-bg.nix), excluded from the sandbox to reach the
# background daemon. It is an allow-list, so it only holds while:
#   - claude gets exactly `respawn <id>`, `logs <id>` or `daemon status`, nothing else;
#   - wrong arity, an id that is not 8 lowercase hex (`--all`, a name, a dash-led
#     word, control characters, empty), any other subcommand exit 2 BEFORE
#     claude is called.
#
# Runtime suite: the BUILT wrapper runs against a stub claude that records its
# argv (NUL-separated). r01-r03 accept, r04-r22 reject. The rejects also run
# against the real package (/opt/homebrew/bin/claude): a reject never reaches
# claude, so a regression there exits 126/127 instead of 2 and goes red.
# Canaries: four mutants of the script go through the same suite and must
# FAIL at their case — C1 widens the id regex (r08), C2 drops the status arity
# rule (r05), C3 adds a subcommand (r16), C4 changes the status argv (r03). A
# canary that survives, or dies at another case, fails the check. Anchors and
# `@claude@` must occur exactly once in the script: an eval-time throw otherwise.
{ pkgs }:

let
  bg = import ../home/claude-code/claude-bg.nix { inherit pkgs; };
  inherit (bg) mkClaudeBg claudeBgPkg;

  source = builtins.readFile ../home/claude-code/scripts/claude-bg.sh;

  # Occurrences of a literal needle: length delta, not a regex.
  count =
    needle: hay:
    (builtins.stringLength hay - builtins.stringLength (builtins.replaceStrings [ needle ] [ "" ] hay))
    / builtins.stringLength needle;

  once =
    what: needle:
    let
      n = count needle source;
    in
    if n == 1 then
      true
    else
      throw "claude-bg check: ${what} occurs ${toString n} times in scripts/claude-bg.sh, expected exactly once (looked for: ${needle}) — update the anchor with the script";

  mutate =
    id: anchor: to:
    let
      text = builtins.replaceStrings [ anchor ] [ to ] source;
    in
    if !(once "canary ${id} anchor" anchor) then
      throw "unreachable"
    else if text == source then
      throw "claude-bg check: canary ${id} equals the source — it would test nothing"
    else
      text;

  c1Text = mutate "C1" "$2 =~ ^[0-9a-f]{8}$ ]]" "$2 =~ ^.+$ ]]";
  c2Text = mutate "C2" "[ \"$#\" -eq 1 ] || die \"$usage\"\n" "";
  c3Text = mutate "C3" "  respawn | logs)" "  respawn | logs | rm)";
  c4Text = mutate "C4" "exec \"$claude_bin\" daemon status" "exec \"$claude_bin\" daemon stop";

  stub = pkgs.writeShellScript "claude-stub" ''
    printf '%s\0' "$@" >"''${STUB_LOG:?STUB_LOG unset}"
  '';

  stubbed = mkClaudeBg { claude = "${stub}"; };
  c1 = mkClaudeBg {
    claude = "${stub}";
    text = c1Text;
  };
  c2 = mkClaudeBg {
    claude = "${stub}";
    text = c2Text;
  };
  c3 = mkClaudeBg {
    claude = "${stub}";
    text = c3Text;
  };
  c4 = mkClaudeBg {
    claude = "${stub}";
    text = c4Text;
  };

  # suite <claude-bg binary> <work dir> <all|rejects> — prints `PASS rNN` per
  # case; the first failure prints `FAIL rNN: <reason>` and exits 1.
  suite = pkgs.writeShellScript "claude-bg-suite" ''
    set -u
    bin="$1"
    work="$2"
    only="$3"
    mkdir -p "$work"
    export STUB_LOG="$work/argv"
    case=""
    rc=0

    fail() {
      echo "FAIL $case: $*"
      echo "--- stderr"
      cat "$work/err" 2>/dev/null
      exit 1
    }
    run() {
      case="$1"
      shift
      rm -f "$STUB_LOG"
      "$bin" "$@" >"$work/out" 2>"$work/err" </dev/null
      rc=$?
    }
    # accept <id> "<expected argv, space-separated>" <args...>: exit 0, argv
    # exactly the expected words.
    accept() {
      local id="$1" want="$2"
      shift 2
      run "$id" "$@"
      [ "$rc" = 0 ] || fail "exit $rc, expected 0"
      [ -e "$STUB_LOG" ] || fail "claude not called"
      # shellcheck disable=SC2086
      printf '%s\0' $want >"$work/want"
      cmp -s "$work/want" "$STUB_LOG" || fail "argv differs from $want"
      echo "PASS $case"
    }
    # reject <id> <args...>: claude never called, exit 2, a reason on stderr.
    reject() {
      run "$@"
      [ ! -e "$STUB_LOG" ] || fail "claude called"
      [ "$rc" = 2 ] || fail "exit $rc, expected 2"
      [ -s "$work/err" ] || fail "no reason on stderr"
      echo "PASS $case"
    }

    if [ "$only" = all ]; then
      accept r01 "respawn 4b04dbe6" respawn 4b04dbe6
      accept r02 "logs 4b04dbe6" logs 4b04dbe6
      accept r03 "daemon status" status
    fi

    reject r04
    reject r05 status x
    reject r06 respawn
    reject r07 respawn 4b04dbe6 x
    reject r08 respawn --all
    reject r09 logs -h
    reject r10 respawn 4B04DBE6
    reject r11 respawn 4b04dbe
    reject r12 respawn 4b04dbe6a
    reject r13 logs ghost-return-button
    reject r14 respawn $'4b04dbe6\n'
    reject r15 respawn '4b04dbe6;id'
    reject r16 rm 4b04dbe6
    reject r17 attach 4b04dbe6
    reject r18 daemon status
    reject r19 --all
    reject r20 respawn ""
    reject r21 Status
    reject r22 -- respawn 4b04dbe6
    echo ok
  '';
in
assert once "@claude@" "@claude@";
pkgs.runCommand "claude-bg-check" { } ''
  real=${claudeBgPkg}/bin/claude-bg
  grep -qF /opt/homebrew/bin/claude "$real" || {
    echo "claude-bg: /opt/homebrew/bin/claude is not substituted into the real wrapper"
    exit 1
  }
  if grep -qF @claude@ "$real"; then
    echo "claude-bg: @claude@ left unsubstituted in the real wrapper"
    exit 1
  fi

  ${suite} ${stubbed}/bin/claude-bg "$TMPDIR/stub" all >stub.log 2>&1 || {
    cat stub.log
    echo "claude-bg: suite FAILED against the stub claude"
    exit 1
  }
  cat stub.log
  # A reject that regresses must not reach a usable claude: no HOME, no auth.
  HOME="$TMPDIR/nohome" ${suite} "$real" "$TMPDIR/real" rejects >real.log 2>&1 || {
    cat real.log
    echo "claude-bg: reject suite FAILED against the real wrapper"
    exit 1
  }
  for r in r01 r02 r03 r04 r05 r06 r07 r08 r09 r10 r11 r12 r13 r14 r15 r16 r17 r18 r19 r20 r21 r22; do
    grep -qx "PASS $r" stub.log || { echo "claude-bg: case $r did not run against the stub"; exit 1; }
  done
  for r in r04 r05 r06 r07 r08 r09 r10 r11 r12 r13 r14 r15 r16 r17 r18 r19 r20 r21 r22; do
    grep -qx "PASS $r" real.log || { echo "claude-bg: case $r did not run against the real wrapper"; exit 1; }
  done

  canary() {
    if ${suite} "$2" "$TMPDIR/$1" all >"$1.log" 2>&1; then
      cat "$1.log"
      echo "claude-bg: canary $1 SURVIVED — the suite cannot see its fault"
      exit 1
    fi
    first=$(grep -m1 '^FAIL ' "$1.log")
    case "$first" in
      "FAIL $3: "*) ;;
      *)
        cat "$1.log"
        echo "claude-bg: canary $1 died at the wrong case (expected $3, got: $first)"
        exit 1
        ;;
    esac
    echo "claude-bg: canary $1 killed — $first"
  }
  canary C1 ${c1}/bin/claude-bg r08
  canary C2 ${c2}/bin/claude-bg r05
  canary C3 ${c3}/bin/claude-bg r16
  canary C4 ${c4}/bin/claude-bg r03

  echo "claude-bg: 22 runtime cases, 4 canaries — OK"
  touch $out
''
