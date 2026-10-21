# Non-regression check for `agent-pane` (home/claude-code/agent-pane.nix),
# the top pane that shows one abduco session and `agent-pane pick <name>`
# that switches it. It only holds while:
#   - pick writes `<name>` + a nonce atomically into a 0700 dir, and a bad
#     name (claude-dispatch's rule) or a wrong arity exits 2 with the file
#     untouched and no temp file left;
#   - a target change sends the attached client SIGTERM (detach, the session
#     stays) BEFORE attaching the new one, a re-pick of the same name
#     reattaches, a client that exits on its own is not restarted until the
#     file changes, a target with no live session (absent, or `+` = ended)
#     attaches nothing and lists the sessions with their state and intent;
#   - on a tty, each attach shrinks it one row before the client starts,
#     restores it, then sends the client SIGWINCH (Claude repaints only on a
#     changed size); headless, no jiggle;
#   - abduco is only ever called as `abduco` (list) or `abduco -a <name>`.
#
# Runtime suite: the BUILT script against a stub abduco that lists a fixed
# set of sessions (`*`, ` `, `+` rows) and, on `-a <name>`, logs the call and
# sleeps until SIGTERM, which it logs as `TERM <name>` (`quits` exits at
# once). The pane runs headless (stdin /dev/null, no tty: `stty` fails
# silently, width falls back to 80; the stub needs no tty) and is driven
# through pick, then stopped with SIGTERM: exit 143, the client detached,
# the terminal-restore sequence last on stdout. The pick and usage cases
# (p01-p13) also run against the real package (pick never calls abduco).
# j01 runs a variant whose `stty` is a stub (size `40 100`, logs `rows <n>`):
# log = `rows 39`, `-a t1`, `rows 40`, `WINCH t1`.
# Canaries: C1 drops pick's name check (p03 `../x` red), C2 drops the
# SIGTERM to the old client on a change (a05 red: no `TERM t1`), C3 drops the
# row restore after the attach (j01 red: no `rows 40`). A canary
# that survives, or dies at another case, fails the check. Anchors and
# `@abduco@` must occur exactly once in the script, and the name rule must
# be claude-dispatch's: an eval-time throw otherwise.
{ pkgs }:

let
  pane = import ../home/claude-code/agent-pane.nix { inherit pkgs; };
  inherit (pane) mkAgentPane agentPanePkg;

  source = builtins.readFile ../home/claude-code/scripts/agent-pane.sh;
  dispatchSource = builtins.readFile ../home/claude-code/scripts/claude-dispatch.sh;

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
      throw "agent-pane check: ${what} occurs ${toString n} times in scripts/agent-pane.sh, expected exactly once (looked for: ${needle}) — update the anchor with the script";

  mutate =
    id: anchor: to:
    let
      text = builtins.replaceStrings [ anchor ] [ to ] source;
    in
    if !(once "canary ${id} anchor" anchor) then
      throw "unreachable"
    else if text == source then
      throw "agent-pane check: canary ${id} equals the source — it would test nothing"
    else
      text;

  nameRule = "^[a-z0-9][a-z0-9-]{0,47}$";

  c1Text = mutate "C1" "  [[ $1 =~ $name_re ]] || die 'name must match ${nameRule}'\n" "";
  c2Text = mutate "C2" "      kill -TERM \"$child\" 2>/dev/null || true\n" "";

  # Jiggle variant: every `stty ` call goes to a stub that answers `size` with
  # `40 100` and logs `rows <n>` into the abduco log, so the order against
  # `-a <name>` shows. C3 drops the restore after the attach.
  stubStty = pkgs.writeShellScript "stty-stub" ''
    case "$1" in
      size) printf '40 100\n' ;;
      rows) printf 'rows %s\n' "$2" >>"''${STUB_LOG:?STUB_LOG unset}" ;;
    esac
    exit 0
  '';
  withSttyStub =
    text:
    let
      out = builtins.replaceStrings [ "stty " ] [ "${stubStty} " ] text;
    in
    if out == text then throw "agent-pane check: no `stty ` call in the script to stub" else out;
  jText = withSttyStub source;
  c3Text = withSttyStub (mutate "C3" "    stty rows \"$tty_rows\" 2>/dev/null || true\n" "");

  # Lists five sessions; `-a <name>` traps TERM and WINCH first, then logs the
  # call, so a signal sent after the log line is always recorded.
  stubAbduco = pkgs.writeShellScript "abduco-stub" ''
    if [ "$#" -eq 0 ]; then
      printf 'Active sessions (on host stub)\n'
      printf '* Wed\t 2026-10-21 10:00:00\t101\tt1\n'
      printf '  Wed\t 2026-10-21 10:00:01\t102\tt2\n'
      printf '  Wed\t 2026-10-21 10:00:02\t103\tquits\n'
      printf '+ Wed\t 2026-10-21 10:00:03\t104\tgone\n'
      printf '  Wed\t 2026-10-21 10:00:04\t105\tbad-json\n'
      exit 0
    fi
    printf '%s\n' "$$" >>"''${STUB_PIDS:?STUB_PIDS unset}"
    if [ "$1" = -a ] && [ "$#" -eq 2 ] && [ "$2" != quits ]; then
      trap 'printf "TERM %s\n" "$2" >>"$STUB_LOG"; exit 0' TERM
      trap 'printf "WINCH %s\n" "$2" >>"$STUB_LOG"' WINCH
      printf '%s\n' "$*" >>"''${STUB_LOG:?STUB_LOG unset}"
      while :; do sleep 0.05; done
    fi
    printf '%s\n' "$*" >>"''${STUB_LOG:?STUB_LOG unset}"
  '';

  withStub =
    text:
    mkAgentPane (
      { abduco = "${stubAbduco}"; } // pkgs.lib.optionalAttrs (text != null) { inherit text; }
    );

  stubbed = withStub null;
  c1 = withStub c1Text;
  c2 = withStub c2Text;
  jiggle = withStub jText;
  c3 = withStub c3Text;

  # suite <agent-pane binary> <work dir> <all|pick|jiggle> — prints `PASS <id>` per
  # case; the first failure prints `FAIL <id>: <reason>` and exits 1.
  suite = pkgs.writeShellScript "agent-pane-suite" ''
    set -u
    bin="$1"
    work="$2"
    only="$3"
    mkdir -p "$work"
    export HOME="$work/home" XDG_STATE_HOME="$work/state"
    export STUB_LOG="$work/abduco.log" STUB_PIDS="$work/abduco.pids"
    tf="$XDG_STATE_HOME/agent-pane/target"
    : >"$STUB_LOG"
    : >"$STUB_PIDS"
    case=""
    rc=0
    pane=""

    stop_all() {
      if [ -n "$pane" ]; then kill "$pane" 2>/dev/null; fi
      while read -r p; do kill "$p" 2>/dev/null; done <"$STUB_PIDS"
    }
    fail() {
      echo "FAIL $case: $*"
      stop_all
      for f in err pane.err abduco.log; do
        echo "--- $f"
        cat "$work/$f" 2>/dev/null
      done
      exit 1
    }
    run() {
      case="$1"
      shift
      "$bin" "$@" >"$work/out" 2>"$work/err" </dev/null
      rc=$?
    }
    only_target() {
      [ "$(ls -A "$XDG_STATE_HOME/agent-pane")" = target ] || fail "state dir holds more than the target: $(ls -A "$XDG_STATE_HOME/agent-pane")"
    }
    # accept <id> <name>: exit 0, line 1 = name, line 2 = a nonce, nothing else.
    accept() {
      run "$1" pick "$2"
      [ "$rc" = 0 ] || fail "exit $rc, expected 0"
      [ "$(sed -n 1p "$tf")" = "$2" ] || fail "line 1 is not $2: $(sed -n 1p "$tf")"
      [ -n "$(sed -n 2p "$tf")" ] || fail "no nonce on line 2"
      [ "$(wc -l <"$tf")" -eq 2 ] || fail "target is not two lines"
      only_target
      echo "PASS $case"
    }
    # reject <id> <args...>: exit 2, a reason on stderr, target unchanged.
    reject() {
      run "$@"
      [ "$rc" = 2 ] || fail "exit $rc, expected 2"
      [ -s "$work/err" ] || fail "no reason on stderr"
      cmp -s "$work/saved" "$tf" || fail "target changed: $(tr '\n' ' ' <"$tf")"
      only_target
      echo "PASS $case"
    }

    accept p01 t1
    [ "$(ls -ld "$XDG_STATE_HOME/agent-pane" | cut -c1-10)" = drwx------ ] || fail "state dir is not 0700"
    cp "$tf" "$work/saved"
    accept p02 t1
    cmp -s "$work/saved" "$tf" && fail "a re-pick of the same name left the file unchanged (no nonce)"
    cp "$tf" "$work/saved"
    reject p03 pick ../x
    reject p04 pick -x
    reject p05 pick A
    reject p06 pick ""
    reject p07 pick "$(printf 'a%048d' 0)"
    reject p08 pick a/b
    reject p09 pick
    reject p10 pick a b
    accept p11 "$(printf 'a%047d' 0)"
    cp "$tf" "$work/saved"
    run h12 --help
    [ "$rc" = 0 ] && grep -q '^usage: agent-pane' "$work/out" && [ ! -s "$work/err" ] || fail "--help: exit $rc or usage not on stdout"
    echo "PASS $case"
    reject p13 --bogus
    [ ! -s "$work/out" ] || fail "unknown argument printed on stdout"
    case "$only" in
      all | jiggle) ;;
      *) echo ok; exit 0 ;;
    esac

    # ---- the pane, headless, against the stub
    sd="$HOME/.claude/session-state"
    mkdir -p "$sd"
    printf '{"state":"working","intent":"fix the readme\\u001b[31m now"}' >"$sd/t1.json"
    printf '{not json' >"$sd/bad-json.json"
    printf '{"state":"waiting","intent":"%s"}' "$(printf 'x%.0s' $(seq 200))" >"$sd/quits.json"
    rm -f "$tf"
    out="$work/pane.out"
    "$bin" </dev/null >"$out" 2>"$work/pane.err" &
    pane=$!

    # wait_for <file> <fixed string> <min count> <reason>
    wait_for() {
      local i=0
      while [ "$(grep -oF -- "$2" "$1" 2>/dev/null | wc -l)" -lt "$3" ]; do
        i=$((i + 1))
        [ "$i" -lt 150 ] || fail "$4 (waited 15 s)"
        kill -0 "$pane" 2>/dev/null || fail "the pane exited: $4"
        sleep 0.1
      done
    }
    n_a() { grep -cx -- "-a $1" "$STUB_LOG"; }
    log_is() {
      printf '%s\n' "$@" | cmp -s - "$STUB_LOG" || fail "abduco log is [$(tr '\n' '|' <"$STUB_LOG")], expected [$(printf '%s|' "$@")]"
    }
    restore=$(printf '\033[?1049l\033[?25h')

    # Jiggle variant (stty stubbed at 40 rows): shrink before the client
    # starts, restore after, then SIGWINCH to the client.
    if [ "$only" = jiggle ]; then
      case=j01
      wait_for "$out" "agent-pane — no agent selected" 1 "no idle header without a target"
      "$bin" pick t1
      wait_for "$STUB_LOG" "WINCH t1" 1 "no SIGWINCH to the t1 client after the attach"
      log_is "rows 39" "-a t1" "rows 40" "WINCH t1"
      echo "PASS $case"
      stop_all
      echo ok
      exit 0
    fi

    case=a01
    wait_for "$out" "agent-pane — no agent selected" 1 "no idle header without a target"
    wait_for "$out" " bad-json " 1 "idle list incomplete (no bad-json row)"
    grep -qE '^\* t1 +working +fix the readme \[31m now$' "$out" || fail "no t1 row with state and blanked intent"
    grep -qE '^  t2 +\? *$' "$out" || fail "no t2 row with state ?"
    grep -qE '^\+ gone +\? *$' "$out" || fail "no + row for gone"
    grep -qE '^  bad-json +\? *$' "$out" || fail "unparsable state file not shown as ?"
    q=$(grep -E '^  quits +waiting +x+$' "$out" | head -n1)
    [ "''${#q}" = 80 ] || fail "quits row is ''${#q} characters, expected 80 (truncated to the width)"
    [ ! -s "$STUB_LOG" ] || fail "abduco -a called without a target"
    echo "PASS $case"

    case=a02
    "$bin" pick ghost
    wait_for "$out" "ghost: no such session" 1 "no idle header for an absent session"
    [ ! -s "$STUB_LOG" ] || fail "abduco -a called for an absent session"
    echo "PASS $case"

    case=a03
    "$bin" pick gone
    wait_for "$out" "gone: no such session" 1 "no idle header for an ended (+) session"
    [ ! -s "$STUB_LOG" ] || fail "abduco -a called for an ended (+) session"
    echo "PASS $case"

    case=a04
    "$bin" pick t1
    wait_for "$STUB_LOG" "-a t1" 1 "pick t1 did not attach t1"
    log_is "-a t1"
    echo "PASS $case"

    case=a05
    "$bin" pick t2
    wait_for "$STUB_LOG" "TERM t1" 1 "TERM t1 not logged after pick t2: the old client was not detached"
    wait_for "$STUB_LOG" "-a t2" 1 "pick t2 did not attach t2"
    log_is "-a t1" "TERM t1" "-a t2"
    [ "$(grep -oF -- "$restore" "$out" | wc -l)" -ge 1 ] || fail "terminal not restored after the detach"
    echo "PASS $case"

    case=a06
    "$bin" pick t2
    wait_for "$STUB_LOG" "TERM t2" 1 "a re-pick of t2 did not detach t2"
    wait_for "$STUB_LOG" "-a t2" 2 "a re-pick of t2 did not reattach"
    log_is "-a t1" "TERM t1" "-a t2" "TERM t2" "-a t2"
    echo "PASS $case"

    case=a07
    "$bin" pick quits
    wait_for "$out" "quits: detached" 1 "no idle header after the client exited on its own"
    sleep 1.5
    [ "$(n_a quits)" = 1 ] || fail "a client that exited on its own was restarted $(n_a quits) times without a pick"
    echo "PASS $case"

    case=a08
    "$bin" pick quits
    wait_for "$STUB_LOG" "-a quits" 2 "a re-pick after an own exit did not reattach"
    echo "PASS $case"

    case=a09
    "$bin" pick t1
    wait_for "$STUB_LOG" "-a t1" 2 "pick t1 after an idle screen did not attach"
    kill -TERM "$pane"
    i=0
    while kill -0 "$pane" 2>/dev/null; do
      i=$((i + 1))
      [ "$i" -lt 100 ] || fail "the pane survived SIGTERM (waited 10 s)"
      sleep 0.1
    done
    wait "$pane"
    prc=$?
    pane=""
    [ "$prc" = 143 ] || fail "pane exited $prc on SIGTERM, expected 143"
    [ "$(grep -cx 'TERM t1' "$STUB_LOG")" = 2 ] || fail "the attached client was not detached when the pane exited"
    [ "$(tail -c ''${#restore} "$out")" = "$restore" ] || fail "terminal not restored on exit"
    echo "PASS $case"

    case=a10
    bad=$(grep -vxE '(-a|TERM) (t1|t2|quits)' "$STUB_LOG")
    [ -z "$bad" ] || fail "abduco called otherwise than -a <name>: $bad"
    echo "PASS $case"
    stop_all
    echo ok
  '';
in
assert once "@abduco@" "@abduco@";
assert once "the name rule" "name_re='${nameRule}'";
assert
  pkgs.lib.hasInfix "$name =~ ${nameRule} ]]" dispatchSource
  || throw "agent-pane check: claude-dispatch's name rule is no longer ${nameRule} — keep both scripts on one rule";
pkgs.runCommand "agent-pane-check" { } ''
  real=${agentPanePkg}/bin/agent-pane
  grep -qF ${pkgs.abduco}/bin/abduco "$real" || {
    echo "agent-pane: ${pkgs.abduco}/bin/abduco is not substituted into the real script"
    exit 1
  }
  if grep -qF @abduco@ "$real"; then
    echo "agent-pane: @abduco@ left unsubstituted in the real script"
    exit 1
  fi

  ${suite} ${stubbed}/bin/agent-pane "$TMPDIR/stub" all >stub.log 2>&1 || {
    cat stub.log
    echo "agent-pane: suite FAILED against the stub"
    exit 1
  }
  cat stub.log
  ${suite} "$real" "$TMPDIR/real" pick >real.log 2>&1 || {
    cat real.log
    echo "agent-pane: pick suite FAILED against the real package"
    exit 1
  }
  for r in p01 p02 p03 p04 p05 p06 p07 p08 p09 p10 p11 h12 p13 a01 a02 a03 a04 a05 a06 a07 a08 a09 a10; do
    grep -qx "PASS $r" stub.log || { echo "agent-pane: case $r did not run against the stub"; exit 1; }
  done
  for r in p01 p02 p03 p04 p05 p06 p07 p08 p09 p10 p11 h12 p13; do
    grep -qx "PASS $r" real.log || { echo "agent-pane: case $r did not run against the real package"; exit 1; }
  done
  ${suite} ${jiggle}/bin/agent-pane "$TMPDIR/jiggle" jiggle >jiggle.log 2>&1 || {
    cat jiggle.log
    echo "agent-pane: jiggle suite FAILED against the stubbed stty"
    exit 1
  }
  cat jiggle.log
  grep -qx "PASS j01" jiggle.log || { echo "agent-pane: case j01 did not run against the stubbed stty"; exit 1; }

  # canary <id> <binary> <expected first failing case> [suite mode, default all]
  canary() {
    if ${suite} "$2" "$TMPDIR/$1" "''${4:-all}" >"$1.log" 2>&1; then
      cat "$1.log"
      echo "agent-pane: canary $1 SURVIVED — the suite cannot see its fault"
      exit 1
    fi
    first=$(grep -m1 '^FAIL ' "$1.log")
    case "$first" in
      "FAIL $3: "*) ;;
      *)
        cat "$1.log"
        echo "agent-pane: canary $1 died at the wrong case (expected $3, got: $first)"
        exit 1
        ;;
    esac
    echo "agent-pane: canary $1 killed — $first"
  }
  canary C1 ${c1}/bin/agent-pane p03
  canary C2 ${c2}/bin/agent-pane a05
  canary C3 ${c3}/bin/agent-pane j01 jiggle

  echo "agent-pane: runtime cases and canaries C1, C2, C3 — OK"
  touch $out
''
