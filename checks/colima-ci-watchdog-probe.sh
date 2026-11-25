#!/usr/bin/env bash
# Behavioural probe for the colima-ci-watchdog launchd agent (home/colima.nix),
# the one that restarts the `ci` VM when it stays down.
#
# WHY IT EXISTS. checks/colima-ci.nix (item 10) reads the agent's inline
# script at evaluation time and can only match text: it proves the script
# polls `colima status ci` and calls the right kickstart, never WHEN. A
# grace that is too short (killing a VM still starting), a stamp re-armed at
# every tick (grace never elapses), a stale stamp kept across a sleep (a
# kickstart the moment the Mac wakes) or a failed kickstart swallowed would
# all pass the flake green. This probe RUNS the script, as launchd does
# (`<ProgramArguments[0]> -c <ProgramArguments[2]>`), on the agent's own
# PATH, with `/bin/launchctl` replaced by a recording stub and a stub
# `colima` first on PATH, under a fake HOME.
#
# STATE CONTRACT. "$HOME/.cache/colima-ci-watchdog": its CONTENT is the
# epoch of the first down tick, its MTIME the last down tick (touched every
# down tick in the grace). A stamp whose mtime is more than 180 s old is
# stale (the Mac slept): rewritten to now, no kickstart. After 300 s down
# the job is kickstarted once and the stamp re-armed to now.
#
# CASES (colima status rc / stamp content age / stamp mtime age):
#   (a) 0 / 1000 s / now      state removed, no kickstart
#   (b) 1 / none              state written ~now, no kickstart
#   (c) 1 / 200 s / now       no kickstart, content unchanged
#   (d) 1 / 305 s / now       exactly one `kickstart -k gui/<uid>/<colima-ci
#                             label>`, a `YYYY-MM-DD HH:MM:SS` stderr line with
#                             `status rc=1` and `restarting`, content re-armed
#   (e) as (d), kickstart rc 1  one attempt, failure on stderr, script rc != 0
#   (f) 1 / 3600 s / 3600 s   stale: no kickstart, content re-armed, rc 0
#   (g) 1 / 305 s / 30 s      exactly one kickstart
#   (h) 1 / 200 s / 60 s      no kickstart, content unchanged, mtime ~now
#   (i) 1 / leading-zero 100 s / now   no kickstart, rc 0 (no octal error)
#   (j) 124 / 305 s / 30 s    one kickstart, stderr names `status rc=124`
# Mtimes are set with GNU touch/stat from the agent's PATH (checked GNU
# first: macOS /usr/bin/touch has no `-d @EPOCH`).
#
# Standalone, NOT wired into `nix flake check`. Run it from the repo root,
# OUTSIDE the Claude sandbox (nix needs the daemon).
#
# usage: bash checks/colima-ci-watchdog-probe.sh
set -u

agents='.#darwinConfigurations.alex-mbp.config.home-manager.users.alx.launchd.agents'
label='org.nix-community.home.colima-ci'
fails=0
pass() { printf 'PASS %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1"
  fails=$((fails + 1))
}
die() {
  printf 'FAIL %s\n' "$1"
  exit 1
}

[ -f flake.nix ] || die "run from the nix-darwin repo root (flake.nix not found)"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/colima-ci-watchdog-probe.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$tmp"' EXIT
# nix's stderr (e.g. "warning: Git tree … has uncommitted changes") goes to a
# file: only stdout is the value, stderr is quoted on failure.
err="$tmp/nix.err"

has=$(nix eval --json "$agents" --apply 'a: builtins.hasAttr "colima-ci-watchdog" a' 2>"$err") ||
  die "nix eval of launchd.agents failed: $(cat "$err")"
[ "$has" = true ] || die "launchd agent colima-ci-watchdog is missing (home/colima.nix) (eval said: $has)"

pa="$agents.colima-ci-watchdog.config.ProgramArguments"
shape=$(nix eval --json "$pa" --apply 'a: builtins.length a == 3 && builtins.elemAt a 1 == "-c"' 2>"$err") ||
  die "cannot read ProgramArguments of colima-ci-watchdog: $(cat "$err")"
[ "$shape" = true ] || die "ProgramArguments must be [ <bash> \"-c\" <script> ] (inline script)"

# [0] = the bash launchd runs, [2] = the inline script text (plain eval, no build).
bash=$(nix eval --raw "$pa" --apply 'a: builtins.elemAt a 0' 2>"$err") ||
  die "cannot read ProgramArguments[0]: $(cat "$err")"
case "$bash" in */bin/bash) ;; *) die "ProgramArguments[0] is not a bash: $bash" ;; esac
if [ ! -x "$bash" ]; then
  nix-store --realise "${bash%/bin/bash}" >/dev/null 2>"$err" ||
    die "bash $bash is not in the store and cannot be realised: $(cat "$err")"
fi
script="$tmp/watchdog.orig"
nix eval --raw "$pa" --apply 'a: builtins.elemAt a 2' >"$script" 2>"$err" ||
  die "cannot read ProgramArguments[2] (script text): $(cat "$err")"
[ -s "$script" ] || die "ProgramArguments[2] (script text) is empty"

agentPath=$(nix eval --raw "$agents.colima-ci-watchdog.config.EnvironmentVariables.PATH" 2>"$err") ||
  die "colima-ci-watchdog has no EnvironmentVariables.PATH: $(cat "$err")"
[ -n "$agentPath" ] || die "colima-ci-watchdog EnvironmentVariables.PATH is empty"

# GNU touch/stat from the agent's PATH (the same ones the script sees).
gtouch=$(PATH="$agentPath" command -v touch) || die "no touch on the agent PATH"
gstat=$(PATH="$agentPath" command -v stat) || die "no stat on the agent PATH"
"$gtouch" --version 2>/dev/null | head -1 | grep -q GNU || die "$gtouch is not GNU touch"
"$gstat" --version 2>/dev/null | head -1 | grep -q GNU || die "$gstat is not GNU stat"

stubs="$tmp/stubs"
mkdir -p "$stubs"
cat >"$stubs/colima" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$tmp/colima.calls"
exit "\$(cat "$tmp/colima.rc")"
EOF
cat >"$stubs/launchctl" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$tmp/launchctl.calls"
exit "\$(cat "$tmp/launchctl.rc")"
EOF
chmod +x "$stubs/colima" "$stubs/launchctl"

grep -q '/bin/launchctl' "$script" || die "watchdog script never calls /bin/launchctl"
sed "s#/bin/launchctl#$stubs/launchctl#g" "$script" >"$tmp/watchdog"

uid=$(id -u)
expected="kickstart -k gui/$uid/$label"

# run <case> <colima rc> <launchctl rc> <content age s | none> <mtime age s | -> [content prefix]
run() {
  local name=$1 crc=$2 lrc=$3 cage=$4 mage=$5 prefix=${6:-} t0
  home="$tmp/$name/home"
  state="$home/.cache/colima-ci-watchdog"
  mkdir -p "$home/.cache"
  : >"$tmp/colima.calls"
  : >"$tmp/launchctl.calls"
  printf '%s' "$crc" >"$tmp/colima.rc"
  printf '%s' "$lrc" >"$tmp/launchctl.rc"
  t0=$(date +%s)
  seeded=
  if [ "$cage" != none ]; then
    seeded="$prefix$((t0 - cage))"
    printf '%s\n' "$seeded" >"$state"
    if [ "$mage" != - ]; then
      "$gtouch" -d "@$((t0 - mage))" "$state" || die "($name) cannot set the stamp mtime"
      [ "$("$gstat" -c %Y "$state")" = $((t0 - mage)) ] || die "($name) stamp mtime not set"
    fi
  fi
  env -i HOME="$home" PATH="$stubs:$agentPath" \
    COLIMA_HOME="$home/.colima" XDG_CACHE_HOME="$home/.cache" \
    "$bash" -c "$(cat "$tmp/watchdog")" >"$tmp/$name/stdout" 2>"$tmp/$name/stderr"
  rc=$?
  now=$(date +%s)
  kicks=$(grep -c . "$tmp/launchctl.calls")
  content= mtime=
  if [ -f "$state" ]; then
    content=$(tr -d '[:space:]' <"$state")
    mtime=$("$gstat" -c %Y "$state")
  fi
}

calls() { tr '\n' ';' <"$tmp/launchctl.calls"; }
polled() { grep -qx 'status ci' "$tmp/colima.calls"; }
recent() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge $((now - 5)) ] && [ "$1" -le "$now" ]; }
one_kick() { [ "$kicks" = 1 ] && [ "$(cat "$tmp/launchctl.calls")" = "$expected" ]; }
# A `YYYY-MM-DD HH:MM:SS ` line of <case>'s stderr matching ERE $2 and $3.
logline() {
  grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} ' "$tmp/$1/stderr" |
    grep -E -- "$2" | grep -Eq -- "$3"
}
nopoll() { fail "($1) colima stub never got \`status ci\` (calls: $(tr '\n' ';' <"$tmp/colima.calls"))"; }

run a 0 0 1000 -
if ! polled; then
  nopoll a
elif [ -e "$state" ]; then
  fail "(a) status 0: state file still present"
elif [ "$kicks" != 0 ]; then
  fail "(a) status 0: launchctl called: $(calls)"
else pass "(a) status 0 -> state removed, no kickstart"; fi

run b 1 0 none -
if ! polled; then
  nopoll b
elif ! recent "$content"; then
  fail "(b) status 1, no state: content missing or not ~now (${content:-absent})"
elif [ "$kicks" != 0 ]; then
  fail "(b) status 1, no state: launchctl called: $(calls)"
else pass "(b) status 1, no state -> state written, no kickstart"; fi

run c 1 0 200 -
if ! polled; then
  nopoll c
elif [ "$kicks" != 0 ]; then
  fail "(c) status 1, 200 s down: launchctl called: $(calls)"
elif [ "$content" != "$seeded" ]; then
  fail "(c) status 1, 200 s down: content rewritten ($seeded -> ${content:-absent}): the grace would never elapse"
else pass "(c) status 1, 200 s down -> no kickstart, content kept"; fi

run d 1 0 305 -
if ! polled; then
  nopoll d
elif ! one_kick; then
  fail "(d) expected exactly one \`$expected\`, got: $(calls)"
elif ! logline d 'status rc=1([^0-9]|$)' 'restarting'; then
  fail "(d) no 'YYYY-MM-DD HH:MM:SS … status rc=1 … restarting' line on stderr: $(head -c 300 "$tmp/d/stderr")"
elif ! recent "$content"; then
  fail "(d) content not re-armed to now (${content:-absent})"
else pass "(d) status 1, 305 s down -> one kickstart -k, logged, re-armed"; fi

run e 1 1 305 -
if ! polled; then
  nopoll e
elif ! one_kick; then
  fail "(e) expected one \`$expected\` attempt, got: $(calls)"
elif ! grep -Eiq 'fail|error' "$tmp/e/stderr"; then
  fail "(e) kickstart rc 1: no failure on stderr: $(head -c 300 "$tmp/e/stderr")"
elif [ "$rc" = 0 ]; then
  fail "(e) kickstart rc 1 swallowed: script exited 0"
else pass "(e) kickstart failing -> failure logged, script rc $rc"; fi

run f 1 0 3600 3600
if ! polled; then
  nopoll f
elif [ "$kicks" != 0 ]; then
  fail "(f) stale stamp (mtime 3600 s old): launchctl called: $(calls)"
elif ! recent "$content"; then
  fail "(f) stale stamp: content not re-armed to now ($seeded -> ${content:-absent})"
elif [ "$rc" != 0 ]; then
  fail "(f) stale stamp: script rc $rc, expected 0"
else pass "(f) stale stamp -> re-armed, no kickstart, rc 0"; fi

run g 1 0 305 30
if ! polled; then
  nopoll g
elif ! one_kick; then
  fail "(g) 305 s down, mtime 30 s: expected exactly one \`$expected\`, got: $(calls)"
else pass "(g) 305 s down, last tick 30 s ago -> one kickstart"; fi

run h 1 0 200 60
if ! polled; then
  nopoll h
elif [ "$kicks" != 0 ]; then
  fail "(h) 200 s down, mtime 60 s: launchctl called: $(calls)"
elif [ "$content" != "$seeded" ]; then
  fail "(h) 200 s down: content rewritten ($seeded -> ${content:-absent})"
elif ! recent "$mtime"; then
  fail "(h) 200 s down: mtime not refreshed to now (${mtime:-absent}, now $now)"
else pass "(h) in grace -> no kickstart, content kept, mtime refreshed"; fi

run i 1 0 100 - 0
if ! polled; then
  nopoll i
elif [ "$kicks" != 0 ]; then
  fail "(i) leading-zero stamp ($seeded): launchctl called: $(calls)"
elif [ "$rc" != 0 ]; then
  fail "(i) leading-zero stamp ($seeded): script rc $rc: $(head -c 300 "$tmp/i/stderr")"
else pass "(i) leading-zero stamp -> no kickstart, rc 0"; fi

run j 124 0 305 30
if ! polled; then
  nopoll j
elif ! one_kick; then
  fail "(j) status rc 124, 305 s down: expected exactly one \`$expected\`, got: $(calls)"
elif ! grep -q 'status rc=124' "$tmp/j/stderr"; then
  fail "(j) stderr does not name status rc=124: $(head -c 300 "$tmp/j/stderr")"
else pass "(j) status timeout (124) -> one kickstart, rc logged"; fi

if [ "$fails" -ne 0 ]; then
  printf '%d case(s) failed\n' "$fails"
  exit 1
fi
printf 'all cases passed\n'
