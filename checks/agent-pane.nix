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
#   - stop TERMs the pid the list gives for exactly that name (a prefix or a
#     substring of a listed name is no session: exit 1, nothing killed), a bad
#     name or a wrong arity exits 2, an unlisted name exits 1;
#   - abduco is only ever called as `abduco` (list) or `abduco -a <name>`;
#     stop calls only the list;
#   - the pane holds an flock on pane.lock for its life, and its client
#     never inherits it; `alive` exits 0 only while another process holds
#     that lock (1 for no file, a free lock, a lock that cannot be opened),
#     prints nothing, and exits 2 on an argument. The board opens a pane on
#     exit 1.
#
# Runtime suite: the BUILT script against a stub abduco that lists a fixed
# set of sessions (`*`, ` `, `+` rows) and, on `-a <name>`, logs the call and
# sleeps until SIGTERM, which it logs as `TERM <name>` (`quits` exits at
# once). The pane runs headless (stdin /dev/null, no tty: `stty` fails
# silently, width falls back to 80; the stub needs no tty) and is driven
# through pick, then stopped with SIGTERM: exit 143, the client detached,
# the terminal-restore sequence last on stdout. The pick, usage and alive
# cases (p01-p13, l01-l06) also run against the real package (neither calls
# abduco; l03, a held lock, proves flock is on its PATH). w01-w03 check the
# pane's lock around the pane cases (w03: a SIGKILLed pane, its client alive).
# s01-s05 (stop) run against the stub, whose t1 and t2 rows then carry the
# pids of two sleeps the suite starts (orphaned, so a killed one is reaped
# and `kill -0` sees it gone).
# j01 runs a variant whose `stty` is a stub (size `40 100`, logs `rows <n>`):
# log = `rows 39`, `-a t1`, `rows 40`, `WINCH t1`.
# Canaries: C1 drops pick's name check (p03 `../x` red), C2 drops the
# SIGTERM to the old client on a change (a05 red: no `TERM t1`), C3 drops the
# row restore after the attach (j01 red: no `rows 40`), C4 turns stop's exact
# match into a substring one (s05 red: `t` kills t1), C5 drops alive's
# conflict check (l02 red: a free lock counts as a pane), C6 lets the client
# inherit the lock fd (w03 red: the orphaned client keeps it), C7 drops the
# XDG_CACHE_HOME default (e01 red: abduco sees it unset). A canary
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
  c4Text =
    mutate "C4" "    if [[ $sname == \"$1\" ]]; then\n"
      "    if [[ $sname == *\"$1\"* ]]; then\n";
  c5Text = mutate "C5" "  [ \"$rc\" -eq 75 ] || exit 1\n" "  [ \"$rc\" -ge 0 ] || exit 1\n";
  c7Text = mutate "C7" "export XDG_CACHE_HOME=\"\${XDG_CACHE_HOME:-$HOME/.cache}\"\n" "";
  c6Text =
    mutate "C6" "  \"$abduco_bin\" -a \"$1\" <&0 9>&- &\n"
      "  \"$abduco_bin\" -a \"$1\" <&0 &\n";

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

  # Lists five sessions (t1's and t2's pids from the env when the stop cases
  # set them); `-a <name>` traps TERM and WINCH first, then logs the call, so a
  # signal sent after the log line is always recorded.
  stubAbduco = pkgs.writeShellScript "abduco-stub" ''
    printf '%s\n' "''${XDG_CACHE_HOME-<unset>}" >"''${STUB_LOG:?STUB_LOG unset}.cache"
    if [ "$#" -eq 0 ]; then
      printf 'Active sessions (on host stub)\n'
      printf '* Wed\t 2026-10-21 10:00:00\t%s\tt1\n' "''${STUB_T1_PID:-101}"
      printf '  Wed\t 2026-10-21 10:00:01\t%s\tt2\n' "''${STUB_T2_PID:-102}"
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
  c4 = withStub c4Text;
  c5 = withStub c5Text;
  c6 = withStub c6Text;
  c7 = withStub c7Text;
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

    # ---- alive: 0 only while another process holds the flock on pane.lock,
    # else 1, nothing printed. The holder is a sleep that keeps fd 9 (exec),
    # so killing it frees the lock; it says `ready` once it holds it.
    lf="$XDG_STATE_HOME/agent-pane/pane.lock"
    alive_is() {
      run "$1" alive
      [ "$rc" = "$2" ] || fail "alive: exit $rc, expected $2"
      [ ! -s "$work/out" ] && [ ! -s "$work/err" ] || fail "alive printed something"
      echo "PASS $case"
    }
    alive_is l01 1
    mkdir -p "$XDG_STATE_HOME/agent-pane"
    : >"$lf"
    alive_is l02 1
    "$BASH" -c 'exec 9>>"$1" && ${pkgs.flock}/bin/flock -n 9 && echo ready && exec sleep 300' _ "$lf" \
      </dev/null >"$work/ready" 2>/dev/null &
    holder=$!
    printf '%s\n' "$holder" >>"$STUB_PIDS"
    i=0
    until [ -s "$work/ready" ]; do
      i=$((i + 1))
      [ "$i" -lt 150 ] || { case=l03; fail "the holder never took the lock"; }
      sleep 0.1
    done
    alive_is l03 0
    kill "$holder" 2>/dev/null
    wait "$holder" 2>/dev/null
    alive_is l04 1
    rm -f "$lf"
    mkdir "$lf"
    alive_is l05 1
    run l06 alive x
    [ "$rc" = 2 ] && [ -s "$work/err" ] || fail "alive x: exit $rc, expected 2 with a reason"
    echo "PASS $case"
    rmdir "$lf"
    case "$only" in
      all | jiggle) ;;
      *) echo ok; exit 0 ;;
    esac

    # ---- stop, against the stub: t1 and t2 are listed with the pids of two
    # sleeps started here (orphaned: a killed one is reaped, `kill -0` fails).
    if [ "$only" = all ]; then
      spawn() { sleep 300 </dev/null >/dev/null 2>&1 & echo "$!"; }
      p1=$(spawn)
      p2=$(spawn)
      printf '%s\n' "$p1" "$p2" >>"$STUB_PIDS"
      export STUB_T1_PID="$p1" STUB_T2_PID="$p2"
      alive() { kill -0 "$1" 2>/dev/null; }
      list_only() {
        [ ! -s "$STUB_LOG" ] || fail "stop called abduco otherwise than the bare list: $(tr '\n' ' ' <"$STUB_LOG")"
      }
      # refuse <id> <exit> <args...>: that exit, a reason on stderr, both sleeps alive.
      refuse() {
        local want="$2"
        case="$1"
        shift 2
        run "$case" "$@"
        [ "$rc" = "$want" ] || fail "$*: exit $rc, expected $want"
        [ -s "$work/err" ] || fail "$*: no reason on stderr"
        alive "$p1" && alive "$p2" || fail "$*: a listed process was killed"
        list_only
      }
      refuse s02 2 stop ../x
      refuse s02 2 stop -x
      echo "PASS $case"
      refuse s03 2 stop
      refuse s03 2 stop t1 t2
      echo "PASS $case"
      refuse s04 1 stop nosuch
      grep -qF 'nosuch: no such session' "$work/err" || fail "no 'no such session' reason: $(cat "$work/err")"
      echo "PASS $case"
      # A prefix and a suffix of t1 (and of t2) are no session.
      refuse s05 1 stop t
      refuse s05 1 stop 1
      echo "PASS $case"
      # abduco's socket dir: XDG_CACHE_HOME defaults to ~/.cache, a set one is kept.
      case=e01
      rm -f "$STUB_LOG.cache"
      env -u XDG_CACHE_HOME "$bin" stop nosuch >/dev/null 2>&1
      [ "$(cat "$STUB_LOG.cache" 2>/dev/null)" = "$HOME/.cache" ] || fail "abduco saw XDG_CACHE_HOME=$(cat "$STUB_LOG.cache" 2>/dev/null), expected $HOME/.cache"
      rm -f "$STUB_LOG.cache"
      XDG_CACHE_HOME=/x/cache "$bin" stop nosuch >/dev/null 2>&1
      [ "$(cat "$STUB_LOG.cache" 2>/dev/null)" = /x/cache ] || fail "a set XDG_CACHE_HOME was not kept: $(cat "$STUB_LOG.cache" 2>/dev/null)"
      echo "PASS $case"
      run s01 stop t1
      [ "$rc" = 0 ] || fail "stop t1: exit $rc, expected 0"
      i=0
      while alive "$p1"; do
        i=$((i + 1))
        [ "$i" -lt 50 ] || fail "t1's process survived stop t1 (waited 5 s)"
        sleep 0.1
      done
      alive "$p2" || fail "stop t1 killed t2's process"
      list_only
      echo "PASS $case"
      kill "$p2" 2>/dev/null
      unset STUB_T1_PID STUB_T2_PID
    fi

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

    # wait_lock: `alive` sees the pane's lock (15 s).
    wait_lock() {
      local i=0
      until "$bin" alive 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -lt 150 ] || fail "alive never saw the pane's lock"
        sleep 0.1
      done
    }
    case=w01
    wait_lock
    [ "$(ls -A "$XDG_STATE_HOME/agent-pane")" = pane.lock ] || fail "state dir holds more than pane.lock: $(ls -A "$XDG_STATE_HOME/agent-pane")"
    alive_is w01 0

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

    alive_is w02 1

    case=a10
    bad=$(grep -vxE '(-a|TERM) (t1|t2|quits)' "$STUB_LOG")
    [ -z "$bad" ] || fail "abduco called otherwise than -a <name>: $bad"
    echo "PASS $case"

    # A pane killed by SIGKILL (no cleanup) while attached: its client lives
    # on, and must not have kept the lock.
    case=w03
    rm -f "$tf"
    "$bin" </dev/null >"$work/pane2.out" 2>>"$work/pane.err" &
    pane=$!
    wait_lock
    "$bin" pick t1
    wait_for "$STUB_LOG" "-a t1" 3 "the second pane did not attach t1"
    client=$(tail -n1 "$STUB_PIDS")
    kill -KILL "$pane"
    wait "$pane" 2>/dev/null
    pane=""
    kill -0 "$client" 2>/dev/null || fail "the t1 client died with the pane: the case proves nothing"
    # The pane's own `sleep 0.3` children hold fd 9 until they end.
    i=0
    while "$bin" alive 2>/dev/null; do
      i=$((i + 1))
      [ "$i" -lt 30 ] || break
      sleep 0.1
    done
    alive_is w03 1
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
  for r in p01 p02 p03 p04 p05 p06 p07 p08 p09 p10 p11 h12 p13 l01 l02 l03 l04 l05 l06 s01 s02 s03 s04 s05 e01 a01 w01 a02 a03 a04 a05 a06 a07 a08 a09 w02 a10 w03; do
    grep -qx "PASS $r" stub.log || { echo "agent-pane: case $r did not run against the stub"; exit 1; }
  done
  for r in p01 p02 p03 p04 p05 p06 p07 p08 p09 p10 p11 h12 p13 l01 l02 l03 l04 l05 l06; do
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
  canary C4 ${c4}/bin/agent-pane s05
  canary C5 ${c5}/bin/agent-pane l02
  canary C6 ${c6}/bin/agent-pane w03
  canary C7 ${c7}/bin/agent-pane e01

  echo "agent-pane: runtime cases and canaries C1, C2, C3, C4, C5, C6, C7 — OK"
  touch $out
''
