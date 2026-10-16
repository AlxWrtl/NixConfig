# claude-bg respawn <id> | logs <id> | resume <id> | status — tend background
# Claude Code sessions from the main session. Allow-list: claude only ever gets
# `respawn <id>`, `logs <id>`, `daemon status`, or for resume `stop <id>` then
# `--bg --resume <uuid> [--name n] [--model m] [--permission-mode p] <fixed
# prompt>`, the id being the 8-hex short id from ~/.claude/jobs. No flag
# passthrough. One file read: resume reads ~/.claude/jobs/<id>/state.json with
# jq (stalled = state working + tempo blocked; sessionId, worktreePath or cwd,
# and the last --name/--model/--permission-mode of respawnFlags, each
# re-checked: a bad model refuses, a bad name or mode is dropped, so
# bypassPermissions never comes back). Adds no env (inherits the session's
# own; a VAR= / env prefix on the call is denied by hooks/lone-excluded-bash.js).
# Absolute claude, jq and sleep paths (substituted at build time).
# Exit 2 = refused input, claude never called; exit 1 = stop failed or the job
# was still working 15 s after it, not resumed.
claude_bin="@claude@"
jq_bin="@jq@"
sleep_bin="@sleep@"
resume_prompt='Reprends là où tu t'\''es arrêté : vérifie l'\''état puis continue la tâche.'
usage='usage: claude-bg respawn <id> | claude-bg logs <id> | claude-bg resume <id> | claude-bg status'
die() { printf 'claude-bg: %s\n' "$1" >&2; exit 2; }
note() { printf 'claude-bg: %s\n' "$1" >&2; }
# shellcheck disable=SC2016 # jq variables, not shell ones
jq_defs='def flag($k): (.respawnFlags | arrays) as $a | [range(0; ($a | length) - 1) as $i | select($a[$i] == $k) | $a[$i + 1] | strings] | last // "";'
uuid_re='^[0123456789abcdef]{8}-[0123456789abcdef]{4}-[0123456789abcdef]{4}-[0123456789abcdef]{4}-[0123456789abcdef]{12}$'
model_re='^[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789][][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]{0,63}$'
name_re='^[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]{0,63}$'

resume() {
  local id="$1" f state tempo needs questions sid wt cwd dir model name mode shown i
  local -a flags=()
  f="$HOME/.claude/jobs/$id/state.json"
  [ -f "$f" ] || die "no job $id (no ~/.claude/jobs/$id/state.json)"
  field() { "$jq_bin" -r "$jq_defs $1 | strings // \"\"" "$f"; }
  state=$(field .state) || die "job $id: state.json is not readable JSON"
  tempo=$(field .tempo) || die "job $id: state.json is not readable JSON"
  needs=$(field .needs) || die "job $id: state.json is not readable JSON"
  questions=$(field '(.block | objects | .questions | arrays | length | tostring)') || die "job $id: state.json is not readable JSON"
  sid=$(field .sessionId) || die "job $id: state.json is not readable JSON"
  wt=$(field .worktreePath) || die "job $id: state.json is not readable JSON"
  cwd=$(field .cwd) || die "job $id: state.json is not readable JSON"
  model=$(field 'flag("--model")') || die "job $id: state.json is not readable JSON"
  name=$(field 'flag("--name")') || die "job $id: state.json is not readable JSON"
  mode=$(field 'flag("--permission-mode")') || die "job $id: state.json is not readable JSON"

  if ! { [ "$state" = working ] && [ "$tempo" = blocked ]; }; then
    printf -v shown '%q/%q' "$state" "$tempo"
    die "job $id is $shown, not stalled (working/blocked)"
  fi
  # A pending question (AskUserQuestion) also reads working/blocked: it waits on the user.
  if [ -n "$needs" ] || [ "${questions:-0}" != 0 ]; then
    die "job $id is waiting for an answer, not stalled"
  fi
  if ! [[ $sid =~ $uuid_re ]] || [[ $sid != "$id"-* ]]; then
    die "job $id: sessionId is not a uuid starting with $id"
  fi
  if [[ $wt == /* ]] && [ -d "$wt" ]; then
    dir=$wt
  elif [[ $cwd == /* ]] && [ -d "$cwd" ]; then
    dir=$cwd
  else
    die "job $id: neither worktreePath nor cwd is an existing absolute directory"
  fi

  if [ -n "$name" ]; then
    if [[ $name =~ $name_re ]]; then
      flags+=(--name "$name")
    else
      note "job $id: name dropped (not ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}\$)"
    fi
  fi
  if [ -n "$model" ]; then
    [[ $model =~ $model_re ]] || die "job $id: model is not ^[A-Za-z0-9][][A-Za-z0-9._-]{0,63}\$, refused"
    flags+=(--model "$model")
  fi
  if [ -n "$mode" ]; then
    case "$mode" in
      default | acceptEdits | auto | plan) flags+=(--permission-mode "$mode") ;;
      *) note "job $id: permission mode dropped (not default, acceptEdits, auto or plan)" ;;
    esac
  fi

  "$claude_bin" stop "$id" || { note "claude stop $id failed — not resumed"; exit 1; }
  i=0
  while [ -f "$f" ]; do
    # A torn write mid-update reads as unreadable: keep waiting.
    state=$("$jq_bin" -r '.state | strings // ""' "$f" 2>/dev/null) || state=unreadable
    if [ "$state" != working ] && [ "$state" != unreadable ]; then
      break
    fi
    i=$((i + 1))
    if [ "$i" -gt 30 ]; then
      note "job $id still working 15 s after stop — not resumed"
      exit 1
    fi
    "$sleep_bin" 0.5
  done
  cd -- "$dir" || { note "cannot enter $dir — not resumed"; exit 1; }
  exec "$claude_bin" --bg --resume "$sid" "${flags[@]}" "$resume_prompt"
}

[ "$#" -ge 1 ] || die "$usage"
case "$1" in
  status)
    [ "$#" -eq 1 ] || die "$usage"
    exec "$claude_bin" daemon status
    ;;
  respawn | logs | resume)
    [ "$#" -eq 2 ] || die "$usage"
    [[ $2 =~ ^[0123456789abcdef]{8}$ ]] || die 'id must be the 8-hex short id (ls ~/.claude/jobs): ^[0123456789abcdef]{8}$'
    if [ "$1" = resume ]; then
      resume "$2"
      exit 1
    fi
    exec "$claude_bin" "$1" "$2"
    ;;
  *) die "$usage" ;;
esac
