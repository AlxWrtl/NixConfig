# Offline check for the weekly TTW stale-step replay (home/ttw-replay/replay.js).
# The replay runs the hook home/claude-code/hooks/ttw-flags.js on every
# Skill(ttw) call of the transcripts under REPLAY_PROJECTS, activation dated
# 1 s before the call, and scores its stale-step line against an oracle.
# Fixtures (checks/ttw-replay/): steps/ = the current step files (read-only
# store dir, as the real home-manager links are), transcripts/ = Claude JSONL:
#   stale-cat.jsonl       `cat` of DIRECT.md showing an OLD text, then Skill(ttw)
#   current-cat-ls.jsonl  `cat` showing the CURRENT text, `ls -la` of it, Skill
#   grep-head-quoted-cd.jsonl  `grep -n Inline DIRECT.md | head -3` showing
#                         current lines, a `for` loop whose `cd steps && cat
#                         COMMANDS.md` is quoted text (no read), Skill
#   grep-quoted-pipe.jsonl  `grep -nE 'Inline|report' DIRECT.md | head`, Skill
#
#   R1  stale-cat, repo hook: exit 0, <date>.json + <date>.md written,
#       all [vp,fp,miss,vn] = [1,0,0,0], 1 transcript, 1 call, no example
#   R2  current-cat-ls, repo hook: all = [0,0,0,1]
#   R3  canary: hook copy whose stale decision is `if (false)` -> R1 gives
#       miss=1 and a miss example on DIRECT.md (the replay can see a miss)
#   R4  canary: hook copy whose stale list is always ["DIRECT.md"] -> R2 gives
#       fp=1 and an fp example on DIRECT.md (the replay can see a false alarm)
#   R5  second run, same REPLAY_DATE: <date>.json/.md unchanged, the run
#       lands in <date>-2.json/.md
#   R6  hook copy without its `try { STEP_RE = stepRe(os.homedir());` line:
#       exit non-zero, REPLAY_OUT left empty
#   R7  every REPLAY_PROJECTS tree byte-identical after its run (content,
#       size, mtime to the ns, mode, no entry added), and the replay's
#       TMPDIR (fake HOME) empty after each run
#   R8  stale-cat with mtime 30 days back + current-cat-ls now: both in all,
#       only the recent one in recent
#   R9  grep-head-quoted-cd, repo hook (names nothing): all = [0,0,0,1] —
#       the grep lines are DIRECT.md lines now (a `head` after a grep is not
#       a file range), COMMANDS.md is never read
#   R10 grep-quoted-pipe (`grep -nE 'Inline|report' DIRECT.md | head`, two
#       non-contiguous current lines), repo hook: all = [0,0,0,1] — the `|`
#       inside the quoted regex is not a pipe stage
# Canary mutants are guarded: the build fails if the sed anchor is gone (the
# mutant would equal the source and the canary would test nothing).
{ pkgs }:

let
  fx = ./ttw-replay;
  hook = ../home/claude-code/hooks/ttw-flags.js;
  replay = ../home/ttw-replay/replay.js;
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.nodejs
    pkgs.coreutils
    pkgs.gnused
    pkgs.gnugrep
    pkgs.findutils
    pkgs.diffutils
    pkgs.jq
  ];
in
pkgs.runCommand "ttw-replay-check" { } ''
  export PATH=${runtimePath}
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  steps=${fx}/steps
  date=2026-11-09

  fail() {
    echo "ttw-replay: $1"
    for f in "$TMPDIR"/*.out "$TMPDIR"/*.err; do [ -s "$f" ] && { echo "--- $f"; cat "$f"; }; done
    exit 1
  }

  # $1 run name, $2 REPLAY_PROJECTS, $3 REPLAY_HOOK, $4 REPLAY_OUT; sets rc.
  # The replay gets its own empty TMPDIR so R7 can see a leftover fake HOME.
  replay() {
    mkdir -p "$TMPDIR/tmp-$1"
    rc=0
    env TMPDIR="$TMPDIR/tmp-$1" REPLAY_PROJECTS="$2" REPLAY_STEPS="$steps" REPLAY_HOOK="$3" \
      REPLAY_REALHOME="$HOME" REPLAY_OUT="$4" REPLAY_DATE="$date" REPLAY_RECENT_DAYS=7 \
      node ${replay} > "$TMPDIR/$1.out" 2> "$TMPDIR/$1.err" || rc=$?
  }
  # $1 projects dir, $2 project, $3 session uuid, $4 fixture transcript
  mkproj() {
    mkdir -p "$1/$2"
    cp "${fx}/transcripts/$4" "$1/$2/$3.jsonl"
    chmod u+w "$1/$2/$3.jsonl"
    touch "$1/$2/$3.jsonl"
  }
  snap() { (cd "$1" && find . -exec stat -c '%n %s %.9Y %a' {} + | sort && find . -type f -exec sha256sum {} + | sort); }
  counts() { jq -c '[.all.vp, .all.fp, .all.miss, .all.vn]' "$1"; }
  # $1 case, $2 run name, $3 projects dir, $4 tree before the run
  untouched() {
    [ "$(snap "$3")" = "$4" ] || fail "R7 $1 run modified REPLAY_PROJECTS"
    [ -z "$(ls -A "$TMPDIR/tmp-$2")" ] || fail "R7 $1 run left in its TMPDIR: $(ls -A "$TMPDIR/tmp-$2" | tr '\n' ' ')"
  }

  [ "$(cat $steps/DIRECT.md)" = "$(jq -r 'select((.message.content[0]?.tool_use_id) == "toolu_r2cat") | .toolUseResult.stdout' ${fx}/transcripts/current-cat-ls.jsonl)" ] \
    || fail "fixture current-cat-ls: its cat stdout is not steps/DIRECT.md"
  [ "$(cat $steps/DIRECT.md)" != "$(jq -r 'select((.message.content[0]?.tool_use_id) == "toolu_r1cat") | .toolUseResult.stdout' ${fx}/transcripts/stale-cat.jsonl)" ] \
    || fail "fixture stale-cat: its cat stdout equals steps/DIRECT.md"

  p1="$TMPDIR/p1"
  mkproj "$p1" -Users-test-proj 11111111-1111-4111-8111-111111111111 stale-cat.jsonl
  t1=$(snap "$p1")
  replay r1 "$p1" ${hook} "$TMPDIR/out1"
  [ "$rc" = 0 ] || fail "R1 exit $rc, want 0"
  j1="$TMPDIR/out1/$date.json"
  [ -f "$j1" ] || fail "R1 no $date.json in REPLAY_OUT"
  [ -s "$TMPDIR/out1/$date.md" ] || fail "R1 no $date.md in REPLAY_OUT"
  jq -e . "$j1" > /dev/null || fail "R1 $date.json is not JSON"
  [ "$(counts "$j1")" = "[1,0,0,0]" ] || fail "R1 all [vp,fp,miss,vn] = $(counts "$j1"), want [1,0,0,0]"
  jq -e --arg d "$date" '.date == $d and has("hook") and .transcripts == 1 and .calls == 1 and (.all.nocontent | type) == "number" and .examples == []' "$j1" > /dev/null \
    || fail "R1 date/hook/transcripts/calls/nocontent/examples wrong: $(jq -c 'del(.all, .recent)' "$j1")"
  untouched R1 r1 "$p1" "$t1"
  echo "ttw-replay: R1 stale cat -> vp=1 OK"
  echo "ttw-replay: R7 R1 run left REPLAY_PROJECTS and its TMPDIR untouched OK"

  p2="$TMPDIR/p2"
  mkproj "$p2" -Users-test-proj 22222222-2222-4222-8222-222222222222 current-cat-ls.jsonl
  t2=$(snap "$p2")
  replay r2 "$p2" ${hook} "$TMPDIR/out2"
  [ "$rc" = 0 ] || fail "R2 exit $rc, want 0"
  j2="$TMPDIR/out2/$date.json"
  [ -f "$j2" ] || fail "R2 no $date.json in REPLAY_OUT"
  [ "$(counts "$j2")" = "[0,0,0,1]" ] || fail "R2 all [vp,fp,miss,vn] = $(counts "$j2"), want [0,0,0,1]"
  untouched R2 r2 "$p2" "$t2"
  echo "ttw-replay: R2 current cat + ls -> vn=1 OK"

  anchor3='    if (stale) out.push(name);'
  sed 's/^    if (stale) out\.push(name);$/    if (false) out.push(name);/' ${hook} > "$TMPDIR/hook-c3.js"
  if [ "$(grep -cxF "$anchor3" ${hook})" != 1 ] || grep -qxF "$anchor3" "$TMPDIR/hook-c3.js" || cmp -s ${hook} "$TMPDIR/hook-c3.js"; then
    fail "canary anchor '$anchor3' gone from ttw-flags.js — the R3 mutant equals the source"
  fi
  replay r3 "$p1" "$TMPDIR/hook-c3.js" "$TMPDIR/out3"
  [ "$rc" = 0 ] || fail "R3 canary killed by the wrong reason — exit $rc"
  j3="$TMPDIR/out3/$date.json"
  [ -f "$j3" ] || fail "R3 canary killed by the wrong reason — no $date.json"
  [ "$(counts "$j3")" = "[0,0,1,0]" ] || fail "R3 canary SURVIVED — a hook that never marks gives [vp,fp,miss,vn] = $(counts "$j3"), want [0,0,1,0]"
  jq -e '[.examples[] | select(.kind == "miss" and .file == "DIRECT.md")] | length == 1' "$j3" > /dev/null \
    || fail "R3 no miss example on DIRECT.md: $(jq -c .examples "$j3")"
  echo "ttw-replay: R3 canary killed — miss=1"

  anchor4='    try { stale = staleSteps(data.transcript_path, os.homedir()); } catch (e) { stale = []; }'
  sed 's/stale = staleSteps(data\.transcript_path, os\.homedir());/stale = ["DIRECT.md"];/' ${hook} > "$TMPDIR/hook-c4.js"
  if [ "$(grep -cxF "$anchor4" ${hook})" != 1 ] || grep -qxF "$anchor4" "$TMPDIR/hook-c4.js" || [ "$(grep -cF 'stale = ["DIRECT.md"];' "$TMPDIR/hook-c4.js")" != 1 ]; then
    fail "canary anchor '$anchor4' gone from ttw-flags.js — the R4 mutant equals the source"
  fi
  replay r4 "$p2" "$TMPDIR/hook-c4.js" "$TMPDIR/out4"
  [ "$rc" = 0 ] || fail "R4 canary killed by the wrong reason — exit $rc"
  j4="$TMPDIR/out4/$date.json"
  [ -f "$j4" ] || fail "R4 canary killed by the wrong reason — no $date.json"
  [ "$(counts "$j4")" = "[0,1,0,0]" ] || fail "R4 canary SURVIVED — a hook that always names DIRECT.md gives [vp,fp,miss,vn] = $(counts "$j4"), want [0,1,0,0]"
  jq -e '[.examples[] | select(.kind == "fp" and .file == "DIRECT.md")] | length == 1' "$j4" > /dev/null \
    || fail "R4 no fp example on DIRECT.md: $(jq -c .examples "$j4")"
  echo "ttw-replay: R4 canary killed — fp=1"

  cp "$j1" "$TMPDIR/r5.json.keep"
  cp "$TMPDIR/out1/$date.md" "$TMPDIR/r5.md.keep"
  replay r5 "$p1" ${hook} "$TMPDIR/out1"
  [ "$rc" = 0 ] || fail "R5 second run exit $rc, want 0"
  cmp -s "$TMPDIR/r5.json.keep" "$j1" || fail "R5 $date.json overwritten by the second run"
  cmp -s "$TMPDIR/r5.md.keep" "$TMPDIR/out1/$date.md" || fail "R5 $date.md overwritten by the second run"
  [ -f "$TMPDIR/out1/$date-2.json" ] && [ -s "$TMPDIR/out1/$date-2.md" ] || fail "R5 second run did not write $date-2.json + $date-2.md: $(ls "$TMPDIR/out1" | tr '\n' ' ')"
  [ "$(counts "$TMPDIR/out1/$date-2.json")" = "[1,0,0,0]" ] || fail "R5 $date-2.json all = $(counts "$TMPDIR/out1/$date-2.json"), want [1,0,0,0]"
  untouched R5 r5 "$p1" "$t1"
  echo "ttw-replay: R5 second run same day -> $(ls "$TMPDIR/out1" | tr '\n' ' ')OK"

  anchor6='^try { STEP_RE = stepRe(os\.homedir());'
  sed "/$anchor6/d" ${hook} > "$TMPDIR/hook-c6.js"
  if [ "$(grep -c "$anchor6" ${hook})" != 1 ] || grep -qF 'STEP_RE = stepRe(os.homedir())' "$TMPDIR/hook-c6.js" \
    || [ "$(($(wc -l < ${hook}) - $(wc -l < "$TMPDIR/hook-c6.js")))" != 1 ]; then
    fail "anchor '$anchor6' gone from ttw-flags.js — the R6 hook equals the source"
  fi
  mkdir -p "$TMPDIR/out6"
  replay r6 "$p1" "$TMPDIR/hook-c6.js" "$TMPDIR/out6"
  [ "$rc" != 0 ] || fail "R6 exit 0 on a hook without its regex line — a hook refactor would give a silent wrong report"
  [ -z "$(ls -A "$TMPDIR/out6")" ] || fail "R6 failed run wrote in REPLAY_OUT: $(ls -A "$TMPDIR/out6" | tr '\n' ' ')"
  untouched R6 r6 "$p1" "$t1"
  echo "ttw-replay: R6 hook without its regex line -> exit $rc, nothing written OK"

  p8="$TMPDIR/p8"
  mkproj "$p8" -Users-test-old 11111111-1111-4111-8111-111111111111 stale-cat.jsonl
  mkproj "$p8" -Users-test-new 22222222-2222-4222-8222-222222222222 current-cat-ls.jsonl
  touch -d '30 days ago' "$p8/-Users-test-old/11111111-1111-4111-8111-111111111111.jsonl"
  t8=$(snap "$p8")
  replay r8 "$p8" ${hook} "$TMPDIR/out8"
  [ "$rc" = 0 ] || fail "R8 exit $rc, want 0"
  j8="$TMPDIR/out8/$date.json"
  [ -f "$j8" ] || fail "R8 no $date.json in REPLAY_OUT"
  jq -e '.transcripts == 2 and .calls == 2 and .all.vp == 1 and .all.vn == 1' "$j8" > /dev/null \
    || fail "R8 all wrong (want 2 transcripts, 2 calls, vp=1, vn=1): $(jq -c '{transcripts, calls, all}' "$j8")"
  jq -e '.recent.transcripts == 1 and .recent.calls == 1 and .recent.vp == 0 and .recent.vn == 1' "$j8" > /dev/null \
    || fail "R8 recent wrong (want 1 transcript, 1 call, vp=0, vn=1): $(jq -c .recent "$j8")"
  untouched R8 r8 "$p8" "$t8"
  echo "ttw-replay: R8 30-day-old transcript in all, not in recent OK"

  t9fx=${fx}/transcripts/grep-head-quoted-cd.jsonl
  g9=$(grep -n Inline $steps/DIRECT.md | head -3)
  [ -n "$g9" ] && [ "$g9" = "$(jq -r 'select((.message.content[0]?.tool_use_id) == "toolu_r9grep") | .toolUseResult.stdout' $t9fx)" ] \
    || fail "fixture grep-head-quoted-cd: its grep stdout is not 'grep -n Inline steps/DIRECT.md | head -3'"
  [ -f $steps/COMMANDS.md ] && [ "$(jq -r 'select((.message.content[0]?.tool_use_id) == "toolu_r9for") | .toolUseResult.stdout' $t9fx)" = 0 ] \
    || fail "fixture grep-head-quoted-cd: steps/COMMANDS.md missing or the for-loop stdout is not 0"
  p9="$TMPDIR/p9"
  mkproj "$p9" -Users-test-proj 99999999-9999-4999-8999-999999999999 grep-head-quoted-cd.jsonl
  t9=$(snap "$p9")
  replay r9 "$p9" ${hook} "$TMPDIR/out9"
  [ "$rc" = 0 ] || fail "R9 exit $rc, want 0"
  j9="$TMPDIR/out9/$date.json"
  [ -f "$j9" ] || fail "R9 no $date.json in REPLAY_OUT"
  [ "$(counts "$j9")" = "[0,0,0,1]" ] || fail "R9 all [vp,fp,miss,vn] = $(counts "$j9"), want [0,0,0,1] — grep|head lines current, quoted cd/cat not a read: $(jq -c .examples "$j9")"
  untouched R9 r9 "$p9" "$t9"
  echo "ttw-replay: R9 grep|head current + quoted cd/cat -> vn=1 OK"

  t10fx=${fx}/transcripts/grep-quoted-pipe.jsonl
  g10=$(grep -nE 'Inline|report' $steps/DIRECT.md | head)
  [ "$(printf '%s\n' "$g10" | grep -c .)" -ge 2 ] && [ "$g10" = "$(jq -r 'select((.message.content[0]?.tool_use_id) == "toolu_r10grep") | .toolUseResult.stdout' $t10fx)" ] \
    || fail "fixture grep-quoted-pipe: its grep stdout is not 'grep -nE Inline|report steps/DIRECT.md | head' with >= 2 lines"
  b10=$(printf '%s\n' "$g10" | sed 's/^[0-9]*://')
  case "$(cat $steps/DIRECT.md)" in *"$b10"*) fail "fixture grep-quoted-pipe: the grep lines are one contiguous block of DIRECT.md — R10 would pass on a block match" ;; esac
  p10="$TMPDIR/p10"
  mkproj "$p10" -Users-test-proj aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa grep-quoted-pipe.jsonl
  t10=$(snap "$p10")
  replay r10 "$p10" ${hook} "$TMPDIR/out10"
  [ "$rc" = 0 ] || fail "R10 exit $rc, want 0"
  j10="$TMPDIR/out10/$date.json"
  [ -f "$j10" ] || fail "R10 no $date.json in REPLAY_OUT"
  [ "$(counts "$j10")" = "[0,0,0,1]" ] || fail "R10 all [vp,fp,miss,vn] = $(counts "$j10"), want [0,0,0,1] — a | inside the quoted grep regex is not a pipe stage: $(jq -c .examples "$j10")"
  untouched R10 r10 "$p10" "$t10"
  echo "ttw-replay: R10 grep -nE 'a|b' | head, non-contiguous current lines -> vn=1 OK"

  echo "ttw-replay: 10 cases, 2 canaries — OK"
  touch $out
''
