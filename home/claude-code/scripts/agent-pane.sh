# agent-pane — the top pane of the agent screen: shows ONE abduco session,
# the one last picked; `agent-pane pick <name>` switches it.
# The selection is a file, `${XDG_STATE_HOME:-$HOME/.local/state}/agent-pane/target`
# (dir 0700): line 1 = the name, line 2 = a nonce, so picking the shown name
# again changes the file and reattaches. pick writes it atomically (temp file
# in the same dir, then mv) and checks only the name, not that the session
# exists: the pane handles a missing one.
# The pane runs `abduco -a <name>` as a background child (explicit `<&0`: an
# async command in a non-interactive shell otherwise gets /dev/null) and polls
# the file; on a change it sends the client SIGTERM, which detaches it and
# leaves the session running (abduco(1) SIGNALS). The client dies without
# restoring the terminal, so the pane does (`stty sane`, leave the alternate
# screen, show the cursor). A client that exits on its own (Ctrl+\ detach,
# session ended) is not restarted until the file changes: no reattach loop.
# Each attach shrinks the tty one row, then restores it and sends the client
# SIGWINCH: Node emits 'resize' only on a changed size, so a reattach at the
# same size never repaints Claude over the cleared screen.
# Session list = `abduco` with no argument: `<mark> <day>\t <date> <time>\t<pid>\t<name>`
# (its strftime `%a%t %F %T` holds a TAB), so name = last field, pid = the one before;
# mark `*` = a client attached, `+` = command ended (not attachable).
# `agent-pane stop <name>` ends the session of exactly that name: TERM to the
# pid the list gives, the abduco server (measured: the session leaves the
# list, its socket goes, the command gets SIGHUP). abduco is called bare.
# State and intent come from ~/.claude/session-state/<name>.json
# (hooks/session-state.js), control characters blanked before printing.
# The pane holds an exclusive flock on `$state_dir/pane.lock` (fd 9) for its
# whole life; the kernel drops it when the pane dies, even by SIGKILL (once
# its `sleep 0.3` children end), and the attached client gets the fd closed
# so it never keeps it. `agent-pane alive`
# (the board, before opening a pane): exit 0 when that lock is held, 1 when it
# is free or cannot be tried; prints nothing. No pid file: a pid can be reused.
# `--slot <id>` as the first argument gives one board tab its own pane: its
# target and lock live in `$state_dir/slots/<id>/` (dirs 0700; slots/ and not
# <id>/ directly, so a slot named `target` cannot collide with the global
# file). <id> follows the name rule; a bad or missing one exits 2 before
# anything is created. stop takes it and ignores it (sessions are global).
# Without it, target and lock are the global files above.
# `--here` (the `ap` alias, and the command of the splits the board opens) is
# `--slot <id>` with the id of the Ghostty terminal it runs in, lowercased
# (Ghostty prints uppercase UUIDs): the board names a pane by the terminal
# the user clicks, with no registry. The id is the focused terminal of the
# front window's selected tab (the shell `ap` was typed in, or the split
# Ghostty just opened, has the focus). osascript failing or an id off the
# name rule: the global pane, said on stderr and in the idle header (the
# pane clears the screen, stderr alone would not be seen).
# abduco and osascript are called by absolute path (substituted at build
# time); PATH is the package's own (coreutils, jq, flock).
abduco_bin="@abduco@"
osascript_bin="@osascript@"
# Set by a --here that fell back to the global pane; shown under the idle header.
here_note=""
name_re='^[a-z0-9][a-z0-9-]{0,47}$'
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/agent-pane"
# slot, pane_dir, target_file and lock_file are set once the arguments are
# parsed (end of file).
slot=""
session_dir="$HOME/.claude/session-state"
# abduco's socket dir follows XDG_CACHE_HOME (sessions live in ~/.cache/abduco).
# A pane Ghostty opens for the board (`login … bash --noprofile`) has no
# XDG_CACHE_HOME and would look elsewhere: no session listed (measured
# 2026-10-21). Default it as the user's shells set it.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

usage() {
  printf '%s\n' \
    'usage: agent-pane [--slot <id>]              show the picked abduco session (run it in the top pane)' \
    '       agent-pane [--slot <id>] pick <name>  pick the session the pane shows' \
    '       agent-pane [--slot <id>] stop <name>  end the session (TERM to its abduco server)' \
    '       agent-pane [--slot <id>] alive        exit 0 if a pane runs, 1 if none' \
    '--slot <id>: the pane of one board tab (its own target and lock); stop ignores it.' \
    '--here: --slot <id of this Ghostty terminal>; Ghostty unreachable: the global pane.' \
    'In the pane: Ctrl+\ detaches, Ctrl+C on the session list quits.'
}
die() { printf 'agent-pane: %s\n' "$1" >&2; exit 2; }
# The request was valid, its target is not there (or would not die).
die1() { printf 'agent-pane: %s\n' "$1" >&2; exit 1; }

make_dir() { [ -d "$1" ] || mkdir -m 700 "$1" || [ -d "$1" ]; }
# The base dir, then with a slot slots/ and slots/<id>/, each 0700 when made.
make_state_dir() {
  mkdir -p "${state_dir%/*}"
  make_dir "$state_dir" || return 1
  [ -z "$slot" ] || { make_dir "$state_dir/slots" && make_dir "$pane_dir"; }
}

pick() {
  [ "$#" -eq 1 ] || { usage >&2; exit 2; }
  [[ $1 =~ $name_re ]] || die 'name must match ^[a-z0-9][a-z0-9-]{0,47}$'
  make_state_dir
  local tmp
  tmp=$(mktemp "$pane_dir/.target.XXXXXX")
  if ! printf '%s\n%s\n' "$1" "$EPOCHREALTIME-$$" >"$tmp" || ! mv -f "$tmp" "$target_file"; then
    rm -f "$tmp"
    die "cannot write $target_file"
  fi
}

# The list parsed as list_sessions does; only a name equal to $1 counts (a
# prefix or a substring is another session). pid 0 would signal the group.
stop() {
  [ "$#" -eq 1 ] || { usage >&2; exit 2; }
  [[ $1 =~ $name_re ]] || die "name must match $name_re"
  local listing line pid="" sname
  local -a f
  listing=$("$abduco_bin" 2>/dev/null </dev/null) || true
  while IFS= read -r line; do
    IFS=$'\t' read -r -a f <<<"$line"
    if [ "${#f[@]}" -lt 3 ]; then continue; fi
    sname=${f[${#f[@]} - 1]}
    if [[ $sname == "$1" ]]; then
      pid=${f[${#f[@]} - 2]}
      break
    fi
  done <<<"$listing"
  [ -n "$pid" ] || die1 "$1: no such session"
  [[ $pid =~ ^[1-9][0-9]*$ ]] || die1 "$1: listed pid is not a pid: ${pid//[[:cntrl:]]/?}"
  kill -TERM "$pid" 2>/dev/null || die1 "$1: cannot signal pid $pid"
}

# Held = a pane runs. flock exits 75 (-E) only on a conflict; a free lock is
# taken and dropped with this process, any other failure counts as no pane.
alive() {
  [ "$#" -eq 0 ] || { usage >&2; exit 2; }
  [ -f "$lock_file" ] || exit 1
  exec 9<"$lock_file" 2>/dev/null || exit 1
  local rc=0
  flock -n -E 75 9 2>/dev/null || rc=$?
  [ "$rc" -eq 75 ] || exit 1
}

# A pane that cannot take it still runs: the board then opens another one.
take_lock() {
  make_state_dir && exec 9>>"$lock_file" && flock -n 9
}

# Sets tgt_raw (the whole file, compared to detect a change) and tgt_name
# (line 1 when it is a valid name, else empty).
read_target() {
  local a="" b=""
  if [ -f "$target_file" ]; then
    { IFS= read -r a || true; IFS= read -r b || true; } <"$target_file" 2>/dev/null || true
  fi
  tgt_raw="$a"$'\n'"$b"
  tgt_name=""
  if [[ $a =~ $name_re ]]; then tgt_name=$a; fi
}

# Sets rows (one `<mark>\t<name>` per session, list order) and live (the
# names that can be attached, mark other than `+`, space-delimited).
list_sessions() {
  local listing line head pid sname
  local -a f
  rows=()
  live=" "
  listing=$("$abduco_bin" 2>/dev/null </dev/null) || true
  while IFS= read -r line; do
    IFS=$'\t' read -r -a f <<<"$line"
    if [ "${#f[@]}" -lt 3 ]; then continue; fi
    head=${f[0]}
    pid=${f[${#f[@]} - 2]}
    sname=${f[${#f[@]} - 1]}
    if [ -z "${sname:-}" ] || [ -z "${pid:-}" ]; then continue; fi
    rows+=("${head:0:1}"$'\t'"$sname")
    if [ "${head:0:1}" != + ]; then live+="$sname "; fi
  done <<<"$listing"
}

# Sets st and intent for session $1 from its session-state file ("?" if none).
session_info() {
  local f a="" b=""
  st="?"
  intent=""
  [[ $1 =~ $name_re ]] || return 0
  f="$session_dir/$1.json"
  [ -f "$f" ] || return 0
  { IFS= read -r a || true; IFS= read -r b || true; } < <(jq -r \
    '(.state // "?" | tostring | gsub("[[:cntrl:]]"; " ")), (.intent // "" | tostring | gsub("[[:cntrl:]]"; " "))' \
    "$f" 2>/dev/null) || true
  if [ -n "$a" ]; then st=$a; fi
  intent=$b
}

restore_tty() {
  stty sane 2>/dev/null || true
  printf '\e[?1049l\e[?25h'
}

draw_idle() {
  local cols=80 size out line row mark sname
  size=$(stty size 2>/dev/null) || size=""
  if [[ ${size##* } =~ ^[1-9][0-9]*$ ]]; then cols=${size##* }; fi
  out=$'\e[H\e[2J'"${1:0:cols}"$'\n'
  if [ -n "$here_note" ]; then out+="${here_note:0:cols}"$'\n'; fi
  out+=$'\n'
  if [ "${#rows[@]}" -eq 0 ]; then out+=$'(no abduco session)\n'; fi
  for row in "${rows[@]}"; do
    mark=${row%%$'\t'*}
    sname=${row#*$'\t'}
    session_info "$sname"
    printf -v line '%s %-24s %-10s %s' "$mark" "${sname//[[:cntrl:]]/?}" "$st" "$intent"
    out+="${line:0:cols}"$'\n'
  done
  printf '%s' "$out"
}

# Idle until the target file changes or ~2 s pass (the caller redraws).
wait_change() {
  for _ in 1 2 3 4 5 6 7; do
    sleep 0.3
    read_target
    if [[ $tgt_raw != "$shown" ]]; then return 0; fi
  done
}

# Attach to $1 until the target changes (return 0) or the client exits on
# its own (return 1).
attach() {
  local size
  printf '\e[H\e[2J'
  # tty_rows = the rows to restore (global: cleanup restores them if the pane
  # dies mid-jiggle); empty when headless or the shrink failed.
  size=$(stty size 2>/dev/null) || size=""
  if [[ ${size%% *} =~ ^[1-9][0-9]*$ ]] && [ "${size%% *}" -gt 1 ] &&
    stty rows "$((${size%% *} - 1))" 2>/dev/null; then
    tty_rows=${size%% *}
  fi
  "$abduco_bin" -a "$1" <&0 9>&- &
  child=$!
  if [ -n "$tty_rows" ]; then
    sleep 0.3
    stty rows "$tty_rows" 2>/dev/null || true
    tty_rows=""
    kill -WINCH "$child" 2>/dev/null || true
  fi
  while kill -0 "$child" 2>/dev/null; do
    sleep 0.3
    read_target
    if [[ $tgt_raw != "$shown" ]]; then
      kill -TERM "$child" 2>/dev/null || true
      wait "$child" 2>/dev/null || true
      child=""
      restore_tty
      return 0
    fi
  done
  wait "$child" 2>/dev/null || true
  child=""
  restore_tty
  return 1
}

# EXIT trap: undo an unfinished jiggle, detach the client if one runs
# (default signal = TERM), restore the terminal. The lock goes with the
# process.
cleanup() {
  set +e
  if [ -n "$tty_rows" ]; then
    stty rows "$tty_rows" 2>/dev/null
    tty_rows=""
  fi
  if [ -n "$child" ]; then
    kill "$child" 2>/dev/null
    wait "$child" 2>/dev/null
  fi
  restore_tty
}

pane() {
  local header left=""
  child=""
  tty_rows=""
  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  take_lock 2>/dev/null || true
  while :; do
    read_target
    shown=$tgt_raw
    list_sessions
    if [ -z "$tgt_name" ]; then
      header='agent-pane — no agent selected'
    elif [[ $shown == "$left" ]]; then
      header="$tgt_name: detached (pick it again to reattach)"
    elif [[ $live == *" $tgt_name "* ]]; then
      if attach "$tgt_name"; then left=""; else left=$shown; fi
      continue
    else
      header="$tgt_name: no such session"
    fi
    draw_idle "$header"
    wait_change
  done
}

# The slot is checked before any command runs, so a bad one creates nothing.
if [ "$#" -gt 0 ] && [ "$1" = --here ]; then
  shift
  here_id=$("$osascript_bin" -e 'tell application "Ghostty" to get id of focused terminal of selected tab of front window' </dev/null 2>/dev/null) || here_id=""
  here_id=${here_id,,}
  if [[ $here_id =~ $name_re ]]; then
    slot=$here_id
  else
    here_note='agent-pane — Ghostty injoignable (--here) : pane global'
    if [ -z "$here_id" ]; then
      printf 'agent-pane: --here: osascript gave no terminal id: the global pane\n' >&2
    else
      printf 'agent-pane: --here: the terminal id is off %s: the global pane\n' "$name_re" >&2
    fi
  fi
elif [ "$#" -gt 0 ] && [ "$1" = --slot ]; then
  [ "$#" -ge 2 ] || die '--slot needs an id'
  [[ $2 =~ $name_re ]] || die "slot must match $name_re"
  slot=$2
  shift 2
fi
pane_dir=$state_dir
if [ -n "$slot" ]; then pane_dir="$state_dir/slots/$slot"; fi
target_file="$pane_dir/target"
lock_file="$pane_dir/pane.lock"

if [ "$#" -eq 0 ]; then
  pane
fi
case "$1" in
  --help | -h)
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    usage
    ;;
  pick)
    shift
    pick "$@"
    ;;
  stop)
    shift
    stop "$@"
    ;;
  alive)
    shift
    alive "$@"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
