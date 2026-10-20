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
# Session list = `abduco` with no argument: `<mark> <day>\t <date> <time>\t<pid>\t<name>`
# (its strftime `%a%t %F %T` holds a TAB), so name = last field, pid = the one before;
# mark `*` = a client attached, `+` = command ended (not attachable).
# State and intent come from ~/.claude/session-state/<name>.json
# (hooks/session-state.js), control characters blanked before printing.
# abduco is called by absolute path (substituted at build time); PATH is the
# package's own (coreutils, jq).
abduco_bin="@abduco@"
name_re='^[a-z0-9][a-z0-9-]{0,47}$'
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/agent-pane"
target_file="$state_dir/target"
session_dir="$HOME/.claude/session-state"

usage() {
  printf '%s\n' \
    'usage: agent-pane              show the picked abduco session (run it in the top pane)' \
    '       agent-pane pick <name>  pick the session the pane shows' \
    'In the pane: Ctrl+\ detaches, Ctrl+C on the session list quits.'
}
die() { printf 'agent-pane: %s\n' "$1" >&2; exit 2; }

pick() {
  [ "$#" -eq 1 ] || { usage >&2; exit 2; }
  [[ $1 =~ $name_re ]] || die 'name must match ^[a-z0-9][a-z0-9-]{0,47}$'
  mkdir -p "${state_dir%/*}"
  [ -d "$state_dir" ] || mkdir -m 700 "$state_dir" || [ -d "$state_dir" ]
  local tmp
  tmp=$(mktemp "$state_dir/.target.XXXXXX")
  if ! printf '%s\n%s\n' "$1" "$EPOCHREALTIME-$$" >"$tmp" || ! mv -f "$tmp" "$target_file"; then
    rm -f "$tmp"
    die "cannot write $target_file"
  fi
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
  out=$'\e[H\e[2J'"${1:0:cols}"$'\n\n'
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
  printf '\e[H\e[2J'
  "$abduco_bin" -a "$1" <&0 &
  child=$!
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

# EXIT trap: detach the client if one runs (default signal = TERM), restore
# the terminal.
cleanup() {
  set +e
  if [ -n "$child" ]; then
    kill "$child" 2>/dev/null
    wait "$child" 2>/dev/null
  fi
  restore_tty
}

pane() {
  local header left=""
  child=""
  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
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
  *)
    usage >&2
    exit 2
    ;;
esac
