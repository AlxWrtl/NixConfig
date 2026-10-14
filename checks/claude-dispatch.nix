# Non-regression check for the `claude-dispatch` wrapper
# (home/claude-code/claude-dispatch.nix), the only `claude` launch excluded
# from the sandbox. It is an allow-list, so it only holds while:
#   - claude gets exactly `--bg --name <name> "[claude-dispatch] <brief>"`, nothing else;
#   - wrong arity, a bad name, an empty / blank / one-word / dash-led / multi-line /
#     oversize brief exit 2 BEFORE claude is called;
#   - shell metacharacters in the brief reach claude literally.
#
# Runtime suite: the BUILT wrapper runs against a stub claude that records its
# argv (NUL-separated). r01-r04 accept, r05-r23 reject. The rejects also run
# against the real package (/opt/homebrew/bin/claude): a reject never reaches
# claude, so a regression there exits 126/127 instead of 2 and goes red.
# Canaries: three mutants of the script go through the same suite and must
# FAIL at their case — C1 drops the leading-dash rule (r15), C2 widens the
# name regex (r08), C3 adds a permission flag (r01). A canary that survives,
# or dies at another case, fails the check. Anchors and `@claude@` must occur
# exactly once in the script: an eval-time throw otherwise.
{ pkgs }:

let
  dispatch = import ../home/claude-code/claude-dispatch.nix { inherit pkgs; };
  inherit (dispatch) mkClaudeDispatch claudeDispatchPkg;

  source = builtins.readFile ../home/claude-code/scripts/claude-dispatch.sh;

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
      throw "claude-dispatch check: ${what} occurs ${toString n} times in scripts/claude-dispatch.sh, expected exactly once (looked for: ${needle}) — update the anchor with the script";

  mutate =
    id: anchor: to:
    let
      text = builtins.replaceStrings [ anchor ] [ to ] source;
    in
    if !(once "canary ${id} anchor" anchor) then
      throw "unreachable"
    else if text == source then
      throw "claude-dispatch check: canary ${id} equals the source — it would test nothing"
    else
      text;

  c1Text = mutate "C1" "[[ $prompt != -* ]] || die 'brief must not start with -'\n" "";
  c2Text = mutate "C2" "$name =~ ^[a-z0-9][a-z0-9-]{0,47}$ ]]" "$name =~ ^.+$ ]]";
  c3Text =
    mutate "C3" "\"$claude_bin\" --bg --name"
      "\"$claude_bin\" --bg --permission-mode bypassPermissions --name";

  stub = pkgs.writeShellScript "claude-stub" ''
    printf '%s\0' "$@" >"''${STUB_LOG:?STUB_LOG unset}"
  '';

  stubbed = mkClaudeDispatch { claude = "${stub}"; };
  c1 = mkClaudeDispatch {
    claude = "${stub}";
    text = c1Text;
  };
  c2 = mkClaudeDispatch {
    claude = "${stub}";
    text = c2Text;
  };
  c3 = mkClaudeDispatch {
    claude = "${stub}";
    text = c3Text;
  };

  # suite <claude-dispatch binary> <work dir> <all|rejects> — prints
  # `PASS rNN` per case; the first failure prints `FAIL rNN: <reason>` and
  # exits 1.
  suite = pkgs.writeShellScript "claude-dispatch-suite" ''
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
    # accept <id> <name> <brief>: exit 0, argv exactly --bg --name <name> "[claude-dispatch] <brief>".
    accept() {
      run "$@"
      [ "$rc" = 0 ] || fail "exit $rc, expected 0"
      [ -e "$STUB_LOG" ] || fail "claude not called"
      printf '%s\0' --bg --name "$2" "[claude-dispatch] $3" >"$work/want"
      cmp -s "$work/want" "$STUB_LOG" || fail "argv differs from --bg --name <name> [claude-dispatch] <brief>"
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
      accept r01 fix-readme "corrige la faute dans README.md"
      accept r02 "$(printf 'a%047d' 0)" "fix the typo"
      long="a $(printf '%07998d' 0)"
      [ "''${#long}" = 8000 ] || { echo "FAIL r03: fixture is ''${#long} characters, expected 8000"; exit 1; }
      accept r03 fix-a "$long"
      accept r04 fix-a "x; touch $work/pwned \$(id)"
      [ ! -e "$work/pwned" ] || fail "the brief was evaluated by a shell"
    fi

    reject r05
    reject r06 fix-a
    reject r07 fix-a "fix the typo" extra
    reject r08 Fix "fix the typo"
    reject r09 -x "fix the typo"
    reject r10 a/b "fix the typo"
    reject r11 "$(printf 'a%048d' 0)" "fix the typo"
    reject r12 "" "fix the typo"
    reject r13 'a;b' "fix the typo"
    reject r14 fix-a ""
    reject r15 fix-a "-p hi"
    reject r16 fix-a "--dangerously-skip-permissions x"
    reject r17 fix-a purge
    reject r18 fix-a $'fix the\ntypo'
    reject r19 fix-a $'fix the\rtypo'
    reject r20 fix-a $'fix the \e[31m typo'
    reject r21 fix-a "a $(printf '%07999d' 0)"
    reject r22 fix-a ' '
    reject r23 fix-a '  x'
    echo ok
  '';
in
assert once "@claude@" "@claude@";
pkgs.runCommand "claude-dispatch-check" { } ''
  real=${claudeDispatchPkg}/bin/claude-dispatch
  grep -qF /opt/homebrew/bin/claude "$real" || {
    echo "claude-dispatch: /opt/homebrew/bin/claude is not substituted into the real wrapper"
    exit 1
  }
  if grep -qF @claude@ "$real"; then
    echo "claude-dispatch: @claude@ left unsubstituted in the real wrapper"
    exit 1
  fi

  ${suite} ${stubbed}/bin/claude-dispatch "$TMPDIR/stub" all >stub.log 2>&1 || {
    cat stub.log
    echo "claude-dispatch: suite FAILED against the stub claude"
    exit 1
  }
  cat stub.log
  # A reject that regresses must not reach a usable claude: no HOME, no auth.
  HOME="$TMPDIR/nohome" ${suite} "$real" "$TMPDIR/real" rejects >real.log 2>&1 || {
    cat real.log
    echo "claude-dispatch: reject suite FAILED against the real wrapper"
    exit 1
  }
  for r in r01 r02 r03 r04 r05 r06 r07 r08 r09 r10 r11 r12 r13 r14 r15 r16 r17 r18 r19 r20 r21 r22 r23; do
    grep -qx "PASS $r" stub.log || { echo "claude-dispatch: case $r did not run against the stub"; exit 1; }
  done
  for r in r05 r06 r07 r08 r09 r10 r11 r12 r13 r14 r15 r16 r17 r18 r19 r20 r21 r22 r23; do
    grep -qx "PASS $r" real.log || { echo "claude-dispatch: case $r did not run against the real wrapper"; exit 1; }
  done

  canary() {
    if ${suite} "$2" "$TMPDIR/$1" all >"$1.log" 2>&1; then
      cat "$1.log"
      echo "claude-dispatch: canary $1 SURVIVED — the suite cannot see its fault"
      exit 1
    fi
    first=$(grep -m1 '^FAIL ' "$1.log")
    case "$first" in
      "FAIL $3: "*) ;;
      *)
        cat "$1.log"
        echo "claude-dispatch: canary $1 died at the wrong case (expected $3, got: $first)"
        exit 1
        ;;
    esac
    echo "claude-dispatch: canary $1 killed — $first"
  }
  canary C1 ${c1}/bin/claude-dispatch r15
  canary C2 ${c2}/bin/claude-dispatch r08
  canary C3 ${c3}/bin/claude-dispatch r01

  echo "claude-dispatch: 23 runtime cases, 3 canaries — OK"
  touch $out
''
