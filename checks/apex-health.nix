# Runtime check for apex-health (home/claude-code/apex-health.nix): the BUILT
# report runs against a fake ~/.claude and a throwaway git repo, clock fixed by
# --now 2026-10-20, cut-off 2026-10-10, 30-day BEFORE window.
#
#   F1  6 BEFORE + 6 AFTER APEX sessions, 1 round each side -> exit 0, VERDICT: ok
#   F2  same sessions, AFTER sessions carry 2 rounds each, 0 before
#                                     -> exit 2, VERDICT: DÉRIVE (rounds / run)
#   F3  6 BEFORE + 2 AFTER sessions   -> exit 0, VERDICT: insuffisant
#   F4  F1 + an APEX session with 3 rounds under a `...-scratchpad-...` project
#       dir -> report identical to F1 except the excluded count (1)
#   F5  repo: `feat: a` touches x.txt, `fix: a` touches x.txt 2 days later
#                                     -> fix-after BEFORE 1/1
#   F6  one session: usage 100/1000/10000/10 (dup line, same message.id) plus a
#       subagent message 10/0/0/2 and one malformed line
#                                     -> 3170.0 weighted, 12.0 output, 1 skipped
#   F7  repo: `feat: b` touches README.md + y.txt, `fix: c` touches only
#       README.md 1 day later, then a docs-only `docs: d`
#                                     -> fix-after BEFORE 0/1 (*.md and
#       flake.lock never count as overlap; a commit with only such files is
#       not scored)
#
# Canary M1: a copy of the script whose drift comparison (the line holding
# `DRIFT_RATIO` in is_drift) returns False runs F2 and must NOT say DÉRIVE. If
# it still does, F2's verdict comes from something other than the comparison
# and the F2 assertion proves nothing, so the check fails. A build-time guard
# fails too if the sed anchor is gone (the mutant would equal the source).
#
# Offline: python3 + git only, HOME and system git config isolated in $TMPDIR.
{ pkgs }:

let
  health = (import ../home/claude-code/apex-health.nix { inherit pkgs; }).apexHealthPkg;
  script = ../home/claude-code/scripts/apex-health.py;
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.python3
    pkgs.git
    pkgs.coreutils
    pkgs.gnused
    pkgs.gnugrep
    pkgs.diffutils
  ];

  fixtures = pkgs.writeText "apex-health-fixtures.py" ''
    import json
    import sys
    from pathlib import Path

    root = Path(sys.argv[1])
    scenario = sys.argv[2]
    ZERO = {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0}


    def assistant(msg_id, ts, content, usage):
        return json.dumps({"type": "assistant", "timestamp": ts, "message": {"id": msg_id, "role": "assistant", "usage": usage, "content": content}})


    def session(proj, sid, ts, usage=None, extra=()):
        d = root / "projects" / proj
        d.mkdir(parents=True, exist_ok=True)
        apex = [{"type": "tool_use", "name": "Skill", "input": {"skill": "apex", "args": "x"}}]
        lines = [json.dumps({"type": "user", "timestamp": ts, "message": {"role": "user", "content": "go"}})]
        lines.append(assistant(sid + "-m1", ts, apex, usage or ZERO))
        lines.extend(extra)
        (d / (sid + ".jsonl")).write_text("\n".join(lines) + "\n")


    def budget(name, sid, ts):
        d = root / "apex-correction-budget"
        d.mkdir(parents=True, exist_ok=True)
        (d / name).write_text(json.dumps({"ts": ts, "tool": "Agent", "session": sid, "description": "r"}) + "\n")


    def base(after_count):
        for i in range(6):
            session("-Users-t-repo", "b%d" % i, "2026-09-%02dT10:00:00.000Z" % (20 + i))
        for i in range(after_count):
            session("-Users-t-repo", "a%d" % i, "2026-10-%02dT10:00:00.000Z" % (11 + i))


    if scenario in ("f1", "f4"):
        base(6)
        budget("rb.round1", "b0", "2026-09-20T11:00:00.000Z")
        budget("ra.round1", "a0", "2026-10-11T11:00:00.000Z")
    if scenario == "f4":
        session("-private-tmp-x-scratchpad-bench", "x0", "2026-10-12T10:00:00.000Z")
        for n in (1, 2, 3):
            budget("rx.round%d" % n, "x0", "2026-10-12T11:00:00.000Z")
    if scenario == "f2":
        base(6)
        for i in range(6):
            for n in (1, 2):
                budget("r%d.round%d" % (i, n), "a%d" % i, "2026-10-%02dT11:00:00.000Z" % (11 + i))
    if scenario == "f3":
        base(2)
    if scenario == "f6":
        usage = {"input_tokens": 100, "cache_creation_input_tokens": 1000, "cache_read_input_tokens": 10000, "output_tokens": 10}
        dup = assistant("t0-m1", "2026-09-20T10:00:01.000Z", [{"type": "text", "text": "same id"}], usage)
        session("-Users-t-repo", "t0", "2026-09-20T10:00:00.000Z", usage, [dup, '{"type":"assistant", broken'])
        sub = root / "projects" / "-Users-t-repo" / "t0" / "subagents"
        sub.mkdir(parents=True)
        sub_usage = {"input_tokens": 10, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 2}
        (sub / "agent-1.jsonl").write_text(assistant("s1", "2026-09-20T10:05:00.000Z", [{"type": "text", "text": "sub"}], sub_usage) + "\n")
  '';
in
pkgs.runCommand "apex-health-check" { } ''
  export PATH=${runtimePath}
  export HOME="$TMPDIR" GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$TMPDIR"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  FLAGS="--since 2026-10-10 --days 30 --now 2026-10-20T00:00:00Z"

  # Canary M1: the drift comparison returns False.
  anchor='^    return after > before \* DRIFT_RATIO '
  sed "s/$anchor.*/    return False/" ${script} > "$TMPDIR/mutant.py"
  if [ "$(grep -c "$anchor" ${script})" != 1 ] || grep -q "$anchor" "$TMPDIR/mutant.py" || cmp -s ${script} "$TMPDIR/mutant.py"; then
    echo "apex-health: canary anchor '$anchor' gone from the script — the mutant equals the source"
    exit 1
  fi

  for s in f1 f2 f3 f4 f6; do
    python3 -I ${fixtures} "$TMPDIR/$s" "$s"
  done
  mkdir "$TMPDIR/nogit"
  cd "$TMPDIR/nogit"

  # run NAME ARGS...: runs the built tool, stores output in $out_NAME file and exit in $rc.
  run() {
    name="$1"; shift
    rc=0
    ${health}/bin/apex-health $FLAGS "$@" > "$TMPDIR/$name.out" 2>&1 || rc=$?
  }
  fail() {
    echo "apex-health: $1 FAILED — $2"
    cat "$TMPDIR/$1.out"
    exit 1
  }
  has() { grep -qE -- "$2" "$TMPDIR/$1.out" || fail "$1" "missing /$2/"; }

  run f1 --claude-dir "$TMPDIR/f1"
  [ "$rc" = 0 ] || fail f1 "exit $rc, want 0"
  has f1 '^VERDICT: ok$'
  has f1 '^rounds / run +\| +6 \| +0\.17 \| +6 \| +0\.17 \|'
  has f1 '^Sessions exclues \(bancs, dépôts jetables\) : 0$'
  echo "apex-health: F1 no drift OK"

  run f2 --claude-dir "$TMPDIR/f2"
  [ "$rc" = 2 ] || fail f2 "exit $rc, want 2"
  has f2 '^VERDICT: DÉRIVE \(rounds / run\)$'
  has f2 '^rounds / run +\| +6 \| +0\.00 \| +6 \| +2\.00 \|'
  echo "apex-health: F2 drift OK"

  run f3 --claude-dir "$TMPDIR/f3"
  [ "$rc" = 0 ] || fail f3 "exit $rc, want 0"
  has f3 '^VERDICT: insuffisant$'
  has f3 '^rounds / run : insuffisant$'
  echo "apex-health: F3 insufficient OK"

  run f4 --claude-dir "$TMPDIR/f4"
  [ "$rc" = 0 ] || fail f4 "exit $rc, want 0"
  has f4 '^Sessions exclues \(bancs, dépôts jetables\) : 1$'
  grep -v '^Sessions exclues' "$TMPDIR/f1.out" > "$TMPDIR/f1.cmp"
  grep -v '^Sessions exclues' "$TMPDIR/f4.out" > "$TMPDIR/f4.cmp"
  diff "$TMPDIR/f1.cmp" "$TMPDIR/f4.cmp" || fail f4 "report differs from F1 beyond the excluded count"
  echo "apex-health: F4 exclusion OK"

  # commit MSG DATE FILE...: appends MSG to each FILE in repo $R and commits at DATE.
  commit() {
    msg="$1"; when="$2"; shift 2
    for f in "$@"; do
      printf '%s\n' "$msg" >> "$R/$f"
      git -C "$R" add "$f"
    done
    GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" git -C "$R" commit -qm "$msg"
  }

  R="$TMPDIR/repo"
  mkdir "$R"
  git -C "$R" init -q -b master --template=
  commit "chore: init" 2026-09-01T10:00:00Z y.txt
  commit "feat: a" 2026-09-20T10:00:00Z x.txt
  commit "fix: a" 2026-09-22T10:00:00Z x.txt
  run f5 --claude-dir "$TMPDIR/f1" --repo "$R"
  [ "$rc" = 0 ] || fail f5 "exit $rc, want 0"
  has f5 '^fix-after : avant 1/1 suivis, après 0/0 suivis'
  has f5 '^taux fix-after +\| +1 \| +1\.00 \|'
  echo "apex-health: F5 fix-after OK"

  # F7: a fix sharing only README.md is not a follow-up; a docs-only commit is not scored.
  R="$TMPDIR/repo7"
  mkdir "$R"
  git -C "$R" init -q -b master --template=
  commit "feat: b" 2026-09-20T10:00:00Z README.md y.txt
  commit "fix: c" 2026-09-21T10:00:00Z README.md
  commit "docs: d" 2026-09-23T10:00:00Z README.md
  commit "fix: e" 2026-09-24T10:00:00Z README.md
  run f7 --claude-dir "$TMPDIR/f1" --repo "$R"
  [ "$rc" = 0 ] || fail f7 "exit $rc, want 0"
  has f7 '^fix-after : avant 0/1 suivis, après 0/0 suivis'
  echo "apex-health: F7 docs-only overlap OK"

  run f6 --claude-dir "$TMPDIR/f6"
  [ "$rc" = 0 ] || fail f6 "exit $rc, want 0"
  has f6 '^tokens pondérés / run +\| +1 \| +3170\.0 \|'
  has f6 '^tokens de sortie / run +\| +1 \| +12\.0 \|'
  has f6 '^Lignes illisibles ignorées : 1$'
  echo "apex-health: F6 tokens OK"

  # M1 on F2: must not drift.
  m1rc=0
  python3 -I "$TMPDIR/mutant.py" $FLAGS --claude-dir "$TMPDIR/f2" > "$TMPDIR/m1.out" 2>&1 || m1rc=$?
  if [ "$m1rc" = 1 ] || ! grep -q '^VERDICT: ' "$TMPDIR/m1.out"; then
    echo "apex-health: canary M1 crashed instead of reporting (exit $m1rc)"
    cat "$TMPDIR/m1.out"
    exit 1
  fi
  if grep -q 'DÉRIVE' "$TMPDIR/m1.out"; then
    echo "apex-health: canary M1 SURVIVED — drift comparison neutralised and F2 still says DÉRIVE; the F2 assertion does not prove the comparison"
    exit 1
  fi
  echo "apex-health: canary M1 killed — F2 without the comparison: $(grep '^VERDICT' "$TMPDIR/m1.out")"

  echo "apex-health: 7 fixtures, 1 canary — OK"
  touch $out
''
