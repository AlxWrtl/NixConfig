# Non-regression check for the `claude-dispatch` wrapper
# (home/claude-code/claude-dispatch.nix), the only `claude` launch excluded
# from the sandbox. It is an allow-list, so it only holds while:
#   - abduco gets exactly `-n <name> <claude> --worktree <name> --name <name> "[claude-dispatch] <brief>"`,
#     nothing else, and claude is never called directly;
#   - wrong arity, a bad name, an empty / blank / one-word / dash-led / multi-line /
#     oversize brief exit 2 BEFORE abduco is called;
#   - shell metacharacters in the brief reach abduco literally.
#
# Runtime suite: the BUILT wrapper runs against a stub abduco and a stub
# claude that record who was called and its argv (NUL-separated). r01-r04
# accept, r05-r23 reject, r24 calls the wrapper with CLAUDE_CODE_CHILD_SESSION=1
# and requires abduco to see it unset (an inherited marker turns transcript
# saving off in the dispatched session, claude 2.1.305). The rejects also run
# against the real package (store abduco, /opt/homebrew/bin/claude): a reject
# never reaches abduco, so a regression there exits non-2 and goes red.
# Real-abduco probe: the wrapper with the store abduco and an argv-recording
# claude stub, socket in the build dir: abduco must exit 0 and claude get
# `--worktree p --name p "[claude-dispatch] <brief>"` (getopt stops at the
# name). A mutant with `--worktree` before the name dies there with
# `abduco: illegal option -- -` (shown by hand 2026-10-21, not a canary).
# Canaries: seven mutants of the script go through the same suite and must
# FAIL at their case — C1 drops the leading-dash rule (r15), C2 widens the
# name regex (r08), C3 adds a permission flag to claude (r01), C4 drops the
# `[claude-dispatch] ` marker (r01), C5 reverts to `claude --bg` (r01), C6
# adds an abduco flag (r01), C7 drops the CLAUDE_CODE_CHILD_SESSION unset
# (r24). A canary that survives, or dies at another case, fails the check.
# Anchors, `@abduco@` and `@claude@` must occur exactly once
# in the script, `--bg` never: an eval-time throw otherwise.
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

  never =
    what: needle:
    let
      n = count needle source;
    in
    if n == 0 then
      true
    else
      throw "claude-dispatch check: ${what} occurs ${toString n} times in scripts/claude-dispatch.sh, expected never (looked for: ${needle})";

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

  launch = "exec \"$abduco_bin\" -n \"$name\" \"$claude_bin\" --worktree";

  c1Text = mutate "C1" "[[ $prompt != -* ]] || die 'brief must not start with -'\n" "";
  c2Text = mutate "C2" "$name =~ ^[a-z0-9][a-z0-9-]{0,47}$ ]]" "$name =~ ^.+$ ]]";
  c3Text =
    mutate "C3" "\"$claude_bin\" --worktree"
      "\"$claude_bin\" --permission-mode bypassPermissions --worktree";
  c4Text = mutate "C4" "\"[claude-dispatch] $prompt\"" "\"$prompt\"";
  # `: "$abduco_bin";` keeps the variable used: ShellCheck (SC2034) would
  # otherwise fail the mutant's build instead of the suite killing it.
  c5Text = mutate "C5" launch ": \"$abduco_bin\"; exec \"$claude_bin\" --bg --worktree";
  c6Text = mutate "C6" "\"$abduco_bin\" -n" "\"$abduco_bin\" -f -n";
  c7Text = mutate "C7" "unset CLAUDE_CODE_CHILD_SESSION\n" "";

  # Each stub records `<who>` then its argv, NUL-separated, so a wrapper that
  # execs claude directly cannot pass for one that goes through abduco.
  # The abduco stub also records CLAUDE_CODE_CHILD_SESSION as it sees it
  # (`<unset>` when absent) to $STUB_LOG.env.
  stubAbduco = pkgs.writeShellScript "abduco-stub" ''
    printf '%s\0' abduco "$@" >"''${STUB_LOG:?STUB_LOG unset}"
    printf '%s' "''${CLAUDE_CODE_CHILD_SESSION-<unset>}" >"$STUB_LOG.env"
  '';
  stubClaude = pkgs.writeShellScript "claude-stub" ''
    printf '%s\0' claude "$@" >"''${STUB_LOG:?STUB_LOG unset}"
  '';

  withStubs =
    text:
    mkClaudeDispatch (
      {
        abduco = "${stubAbduco}";
        claude = "${stubClaude}";
      }
      // pkgs.lib.optionalAttrs (text != null) { inherit text; }
    );

  # Real-abduco probe: the wrapper with the store abduco and a claude stub
  # that writes its argv (atomically, NUL-separated) to $PROBE_OUT. abduco's
  # getopt must stop at <name>, so claude gets `--worktree <name> …` instead
  # of abduco failing on an illegal option.
  argvClaude = pkgs.writeShellScript "claude-argv" ''
    printf '%s\0' "$@" >"''${PROBE_OUT:?PROBE_OUT unset}.tmp"
    mv "$PROBE_OUT.tmp" "$PROBE_OUT"
  '';
  realAbduco = mkClaudeDispatch { claude = "${argvClaude}"; };

  stubbed = withStubs null;
  c1 = withStubs c1Text;
  c2 = withStubs c2Text;
  c3 = withStubs c3Text;
  c4 = withStubs c4Text;
  c5 = withStubs c5Text;
  c6 = withStubs c6Text;
  c7 = withStubs c7Text;

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
      rm -f "$STUB_LOG" "$STUB_LOG.env"
      "$bin" "$@" >"$work/out" 2>"$work/err" </dev/null
      rc=$?
    }
    # accept <id> <name> <brief>: exit 0, abduco called (not claude) with argv
    # exactly -n <name> <claude> --worktree <name> --name <name> "[claude-dispatch] <brief>".
    accept() {
      run "$@"
      [ "$rc" = 0 ] || fail "exit $rc, expected 0"
      [ -e "$STUB_LOG" ] || fail "abduco not called"
      printf '%s\0' abduco -n "$2" ${stubClaude} --worktree "$2" --name "$2" "[claude-dispatch] $3" >"$work/want"
      cmp -s "$work/want" "$STUB_LOG" || fail "argv differs from abduco -n <name> <claude> --worktree <name> --name <name> [claude-dispatch] <brief>"
      echo "PASS $case"
    }
    # reject <id> <args...>: neither abduco nor claude called, exit 2, a reason on stderr.
    reject() {
      run "$@"
      [ ! -e "$STUB_LOG" ] || fail "abduco or claude called"
      [ "$rc" = 2 ] || fail "exit $rc, expected 2"
      [ -s "$work/err" ] || fail "no reason on stderr"
      echo "PASS $case"
    }
    # child <id> <name> <brief>: the wrapper called with
    # CLAUDE_CODE_CHILD_SESSION=1 (as from a Claude session's Bash) exits 0 and
    # abduco sees the variable unset.
    child() {
      export CLAUDE_CODE_CHILD_SESSION=1
      run "$@"
      unset CLAUDE_CODE_CHILD_SESSION
      [ "$rc" = 0 ] || fail "exit $rc, expected 0"
      [ -e "$STUB_LOG.env" ] || fail "abduco not called"
      seen=$(cat "$STUB_LOG.env")
      [ "$seen" = "<unset>" ] || fail "abduco inherited CLAUDE_CODE_CHILD_SESSION=$seen (transcript saving off in the dispatched session)"
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
      child r24 fix-a "fix the typo"
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
assert once "@abduco@" "@abduco@";
assert once "@claude@" "@claude@";
assert once "the abduco launch line" launch;
assert never "`--bg` (sessions run under abduco, not Claude's daemon)" "--bg";
pkgs.runCommand "claude-dispatch-check" { } ''
  real=${claudeDispatchPkg}/bin/claude-dispatch
  grep -qF /opt/homebrew/bin/claude "$real" || {
    echo "claude-dispatch: /opt/homebrew/bin/claude is not substituted into the real wrapper"
    exit 1
  }
  grep -qF ${pkgs.abduco}/bin/abduco "$real" || {
    echo "claude-dispatch: ${pkgs.abduco}/bin/abduco is not substituted into the real wrapper"
    exit 1
  }
  for p in @abduco@ @claude@; do
    if grep -qF "$p" "$real"; then
      echo "claude-dispatch: $p left unsubstituted in the real wrapper"
      exit 1
    fi
  done

  ${suite} ${stubbed}/bin/claude-dispatch "$TMPDIR/stub" all >stub.log 2>&1 || {
    cat stub.log
    echo "claude-dispatch: suite FAILED against the stubs"
    exit 1
  }
  cat stub.log
  # A reject that regresses must not reach a usable claude: no HOME, no auth,
  # and any abduco socket stays in the build dir.
  HOME="$TMPDIR/nohome" ABDUCO_SOCKET_DIR="$TMPDIR/abduco-sock" \
    ${suite} "$real" "$TMPDIR/real" rejects >real.log 2>&1 || {
    cat real.log
    echo "claude-dispatch: reject suite FAILED against the real wrapper"
    exit 1
  }
  for r in r01 r02 r03 r04 r05 r06 r07 r08 r09 r10 r11 r12 r13 r14 r15 r16 r17 r18 r19 r20 r21 r22 r23 r24; do
    grep -qx "PASS $r" stub.log || { echo "claude-dispatch: case $r did not run against the stubs"; exit 1; }
  done
  for r in r05 r06 r07 r08 r09 r10 r11 r12 r13 r14 r15 r16 r17 r18 r19 r20 r21 r22 r23; do
    grep -qx "PASS $r" real.log || { echo "claude-dispatch: case $r did not run against the real wrapper"; exit 1; }
  done

  # Real-abduco probe (see argvClaude): the session lives in the build
  # sandbox, socket under $TMPDIR, no user session created.
  mkdir -m 700 "$TMPDIR/s"
  export PROBE_OUT="$TMPDIR/probe.argv"
  probe_rc=0
  HOME="$TMPDIR/nohome" ABDUCO_SOCKET_DIR="$TMPDIR/s" \
    ${realAbduco}/bin/claude-dispatch p "probe abduco getopt" </dev/null >probe.log 2>&1 || probe_rc=$?
  if [ "$probe_rc" != 0 ]; then
    cat probe.log
    echo "claude-dispatch: real abduco exited $probe_rc (expected 0: getopt must stop at <name>)"
    exit 1
  fi
  i=0
  while [ ! -e "$PROBE_OUT" ] && [ "$i" -lt 100 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  if [ ! -e "$PROBE_OUT" ]; then
    cat probe.log
    echo "claude-dispatch: real abduco never ran the claude stub (waited 10 s)"
    exit 1
  fi
  printf '%s\0' --worktree p --name p "[claude-dispatch] probe abduco getopt" >probe.want
  if ! cmp -s probe.want "$PROBE_OUT"; then
    echo "claude-dispatch: real abduco passed claude: $(tr '\0' ' ' <"$PROBE_OUT")"
    exit 1
  fi
  echo "claude-dispatch: real abduco probe — claude got --worktree p --name p [claude-dispatch] <brief>"

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
  canary C4 ${c4}/bin/claude-dispatch r01
  canary C5 ${c5}/bin/claude-dispatch r01
  canary C6 ${c6}/bin/claude-dispatch r01
  canary C7 ${c7}/bin/claude-dispatch r24

  echo "claude-dispatch: 24 runtime cases, 7 canaries — OK"
  touch $out
''
