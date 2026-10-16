# Non-regression check for the `claude-bg` wrapper
# (home/claude-code/claude-bg.nix), excluded from the sandbox to reach the
# background daemon. It is an allow-list, so it only holds while:
#   - claude gets exactly `respawn <id>`, `logs <id>` or `daemon status`, or for
#     `resume <id>` `stop <id>` then `--bg --resume <uuid>` with only the last
#     --name / --model / --permission-mode of the job's respawnFlags (a name
#     outside [A-Za-z0-9._-] or not led by [A-Za-z0-9] dropped, a mode outside
#     default/acceptEdits/auto/plan dropped, so bypassPermissions never comes
#     back) and the fixed prompt, run in the worktree, else the cwd;
#   - wrong arity, an id that is not 8 lowercase hex (`--all`, a name, a dash-led
#     word, control characters, empty), any other subcommand, and for resume a
#     missing or non-JSON state.json, a job that is not working/blocked, a
#     sessionId that is not a uuid led by the id, no usable directory or a
#     model outside its charset or dash-led exit 2 BEFORE claude is called;
#   - a failed `stop`, or a job still working 15 s after it, exits 1 and is
#     not resumed.
#
# Runtime suite: the BUILT wrapper runs against a stub claude that appends its
# argv (NUL-separated) and records its cwd; on `stop` it exits 1 if the
# fixture is named `stopfail`, else marks the job stopped unless it is named
# `stuck`. Every case runs with HOME=$work/home, where the suite writes the job
# fixtures. The stubbed builds take `true` for sleep, so the 30-poll wait of
# r37 costs no wall time. r01-r03, r23-r27 and r39 accept, r04-r22, r28-r36
# and r38 reject, r37 is the stuck job, r40 the failed stop. The rejects also
# run against the real package (/opt/homebrew/bin/claude): a reject never
# reaches claude, so a regression there exits 126/127 instead of 2 and goes red.
# Canaries: six mutants of the script go through the same suite and must FAIL
# at their case — C1 widens the id regex (r08), C2 drops the status arity rule
# (r05), C3 adds a subcommand (r16), C4 changes the status argv (r03), C5 drops
# the tempo test (r30), C6 lets bypassPermissions through (r25). A canary that
# survives, or dies at another case, fails the check. Anchors, `@claude@`,
# `@jq@`, `@sleep@` and the prompt line must occur exactly once in the script:
# an eval-time throw otherwise.
{ pkgs }:

let
  inherit (pkgs) lib;
  bg = import ../home/claude-code/claude-bg.nix { inherit pkgs; };
  inherit (bg) mkClaudeBg claudeBgPkg;

  source = builtins.readFile ../home/claude-code/scripts/claude-bg.sh;

  resumePrompt = "Reprends là où tu t'es arrêté : vérifie l'état puis continue la tâche.";
  jqBin = "${pkgs.jq}/bin/jq";

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

  c1Text = mutate "C1" "$2 =~ ^[0123456789abcdef]{8}$ ]]" "$2 =~ ^.+$ ]]";
  c2Text = mutate "C2" "[ \"$#\" -eq 1 ] || die \"$usage\"\n" "";
  c3Text = mutate "C3" "  respawn | logs | resume)" "  respawn | logs | resume | rm)";
  c4Text = mutate "C4" "exec \"$claude_bin\" daemon status" "exec \"$claude_bin\" daemon stop";
  c5Text = mutate "C5" "[ \"$tempo\" = blocked ]" "true";
  c6Text =
    mutate "C6" "default | acceptEdits | auto | plan)"
      "default | acceptEdits | auto | plan | bypassPermissions)";

  stub = pkgs.writeShellScript "claude-stub" ''
    printf '%s\0' "$@" >>"''${STUB_LOG:?STUB_LOG unset}"
    pwd -P >"$STUB_LOG.cwd"
    if [ "''${1-}" = stop ]; then
      f="$HOME/.claude/jobs/$2/state.json"
      n=$(${jqBin} -r .name "$f")
      [ "$n" != stopfail ] || exit 1
      if [ "$n" != stuck ]; then
        ${jqBin} '.state = "stopped"' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
      fi
    fi
  '';

  stubbedWith =
    text:
    mkClaudeBg {
      claude = "${stub}";
      sleep = "${pkgs.coreutils}/bin/true";
      inherit text;
    };
  stubbed = stubbedWith source;
  c1 = stubbedWith c1Text;
  c2 = stubbedWith c2Text;
  c3 = stubbedWith c3Text;
  c4 = stubbedWith c4Text;
  c5 = stubbedWith c5Text;
  c6 = stubbedWith c6Text;

  # suite <claude-bg binary> <work dir> <all|rejects> — prints `PASS rNN` per
  # case; the first failure prints `FAIL rNN: <reason>` and exits 1.
  suite = pkgs.writeShellScript "claude-bg-suite" ''
    set -u
    bin="$1"
    work="$2"
    only="$3"
    mkdir -p "$work"
    export STUB_LOG="$work/argv"
    prompt=${lib.escapeShellArg resumePrompt}
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
      rm -f "$STUB_LOG" "$STUB_LOG.cwd"
      HOME="$work/home" "$bin" "$@" >"$work/out" 2>"$work/err" </dev/null
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
    # accept_resume <case> <job id> <expected cwd> <expected argv...>: exit 0,
    # every claude call's argv concatenated equals the expected words, and
    # the last call ran in the expected directory.
    accept_resume() {
      local want_cwd
      run "$1" resume "$2"
      want_cwd=$(cd "$3" && pwd -P)
      shift 3
      [ "$rc" = 0 ] || fail "exit $rc, expected 0"
      [ -e "$STUB_LOG" ] || fail "claude not called"
      printf '%s\0' "$@" >"$work/want"
      cmp -s "$work/want" "$STUB_LOG" || fail "argv differs: $(tr '\0' ' ' <"$STUB_LOG")"
      [ "$(cat "$STUB_LOG.cwd")" = "$want_cwd" ] || fail "ran in $(cat "$STUB_LOG.cwd"), expected $want_cwd"
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

    # Job fixtures: ~/.claude/jobs/<id>/state.json under HOME=$work/home.
    p="$work/p"
    wt="$p/.claude/worktrees/wt"
    mkdir -p "$wt"
    jobs="$work/home/.claude/jobs"
    job() {
      mkdir -p "$jobs/$1"
      printf '%s\n' "$2" >"$jobs/$1/state.json"
    }
    # stalled <id> <worktreePath json> <respawnFlags json>: working/blocked job.
    stalled() {
      job "$1" "{\"state\":\"working\",\"tempo\":\"blocked\",\"sessionId\":\"$1-0000-4000-8000-000000000000\",\"cwd\":\"$p\",\"worktreePath\":$2,\"respawnFlags\":$3}"
    }
    # edit <id> <jq args...>: rewrite a fixture through jq.
    edit() {
      local f="$jobs/$1/state.json"
      shift
      ${jqBin} "$@" "$f" >"$f.tmp" && mv "$f.tmp" "$f"
    }
    stalled a0000023 "\"$wt\"" '["--name","ghost-return-button","--model","opus[1m]"]'
    stalled a0000024 null '["--plugin-dir","/x/deck","--allowed-tools","mcp__a","--model","haiku","--permission-mode","plan","--model","sonnet","--permission-mode","auto","--settings","{}"]'
    stalled a0000025 null '["--permission-mode","bypassPermissions","--dangerously-skip-permissions","--model","opus"]'
    stalled a0000026 "\"$p/.claude/worktrees/gone\"" '[]'
    stalled a0000027 null '["--name","bouton retour fantôme","--permission-mode","acceptEdits"]'
    stalled a0000029 null '[]'
    edit a0000029 '.state = "done" | .tempo = "idle"'
    stalled a0000030 null '[]'
    edit a0000030 '.tempo = "idle"'
    stalled a0000031 null '[]'
    edit a0000031 '.sessionId = "../x"'
    stalled a0000032 null '[]'
    edit a0000032 '.sessionId = "b0000032-0000-4000-8000-000000000000"'
    stalled a0000033 null '[]'
    edit a0000033 --arg d "$work/nope" '.cwd = $d'
    job a0000034 'not json'
    stalled a0000035 null '[]'
    stalled a0000036 null '["--model","opus;id"]'
    stalled a0000037 null '[]'
    edit a0000037 '.name = "stuck"'
    stalled a0000038 null '["--model","--dangerously-skip-permissions"]'
    stalled a0000039 null '["--name","--dangerously-skip-permissions"]'
    stalled a0000040 null '[]'
    edit a0000040 '.name = "stopfail"'

    if [ "$only" = all ]; then
      accept r01 "respawn 4b04dbe6" respawn 4b04dbe6
      accept r02 "logs 4b04dbe6" logs 4b04dbe6
      accept r03 "daemon status" status
      accept_resume r23 a0000023 "$wt" stop a0000023 --bg --resume a0000023-0000-4000-8000-000000000000 --name ghost-return-button --model 'opus[1m]' "$prompt"
      accept_resume r24 a0000024 "$p" stop a0000024 --bg --resume a0000024-0000-4000-8000-000000000000 --model sonnet --permission-mode auto "$prompt"
      accept_resume r25 a0000025 "$p" stop a0000025 --bg --resume a0000025-0000-4000-8000-000000000000 --model opus "$prompt"
      accept_resume r26 a0000026 "$p" stop a0000026 --bg --resume a0000026-0000-4000-8000-000000000000 "$prompt"
      accept_resume r27 a0000027 "$p" stop a0000027 --bg --resume a0000027-0000-4000-8000-000000000000 --permission-mode acceptEdits "$prompt"
      accept_resume r39 a0000039 "$p" stop a0000039 --bg --resume a0000039-0000-4000-8000-000000000000 "$prompt"
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
    reject r28 resume a0000028
    reject r29 resume a0000029
    reject r30 resume a0000030
    reject r31 resume a0000031
    reject r32 resume a0000032
    reject r33 resume a0000033
    reject r34 resume a0000034
    reject r35 resume a0000035 x
    reject r36 resume a0000036
    reject r38 resume a0000038

    if [ "$only" = all ]; then
      # A job still working after stop: exit 1, stop was the only call.
      run r37 resume a0000037
      [ "$rc" = 1 ] || fail "exit $rc, expected 1"
      printf '%s\0' stop a0000037 >"$work/want"
      cmp -s "$work/want" "$STUB_LOG" || fail "claude got more than stop: $(tr '\0' ' ' <"$STUB_LOG")"
      grep -q 'still working' "$work/err" || fail "no still-working reason on stderr"
      echo "PASS $case"
      # A stop that fails: exit 1, stop was the only call, no --bg.
      run r40 resume a0000040
      [ "$rc" = 1 ] || fail "exit $rc, expected 1"
      printf '%s\0' stop a0000040 >"$work/want"
      cmp -s "$work/want" "$STUB_LOG" || fail "claude got more than stop: $(tr '\0' ' ' <"$STUB_LOG")"
      grep -q 'stop a0000040 failed' "$work/err" || fail "no stop-failed reason on stderr"
      echo "PASS $case"
    fi
    echo ok
  '';
in
assert once "@claude@" "@claude@";
assert once "@jq@" "@jq@";
assert once "@sleep@" "@sleep@";
assert once "the resume prompt line" "resume_prompt=${lib.escapeShellArg resumePrompt}\n";
pkgs.runCommand "claude-bg-check" { } ''
  real=${claudeBgPkg}/bin/claude-bg
  for want in /opt/homebrew/bin/claude ${jqBin} ${pkgs.coreutils}/bin/sleep; do
    grep -qF "$want" "$real" || {
      echo "claude-bg: $want is not substituted into the real wrapper"
      exit 1
    }
  done
  for left in @claude@ @jq@ @sleep@; do
    if grep -qF "$left" "$real"; then
      echo "claude-bg: $left left unsubstituted in the real wrapper"
      exit 1
    fi
  done

  ${suite} ${stubbed}/bin/claude-bg "$TMPDIR/stub" all >stub.log 2>&1 || {
    cat stub.log
    echo "claude-bg: suite FAILED against the stub claude"
    exit 1
  }
  cat stub.log
  # A reject that regresses must not reach a usable claude: the suite runs
  # every case with HOME=$work/home, which holds the fixtures and no auth.
  ${suite} "$real" "$TMPDIR/real" rejects >real.log 2>&1 || {
    cat real.log
    echo "claude-bg: reject suite FAILED against the real wrapper"
    exit 1
  }
  for r in r01 r02 r03 r04 r05 r06 r07 r08 r09 r10 r11 r12 r13 r14 r15 r16 r17 r18 r19 r20 r21 r22 r23 r24 r25 r26 r27 r28 r29 r30 r31 r32 r33 r34 r35 r36 r37 r38 r39 r40; do
    grep -qx "PASS $r" stub.log || { echo "claude-bg: case $r did not run against the stub"; exit 1; }
  done
  for r in r04 r05 r06 r07 r08 r09 r10 r11 r12 r13 r14 r15 r16 r17 r18 r19 r20 r21 r22 r28 r29 r30 r31 r32 r33 r34 r35 r36 r38; do
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
  canary C5 ${c5}/bin/claude-bg r30
  canary C6 ${c6}/bin/claude-bg r25

  echo "claude-bg: 40 runtime cases, 6 canaries — OK"
  touch $out
''
