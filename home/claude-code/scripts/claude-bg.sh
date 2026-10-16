# claude-bg respawn <id> | logs <id> | status — tend background Claude Code
# sessions from the main session. Allow-list: claude only ever gets
# `respawn <id>`, `logs <id>` or `daemon status`, the id being the 8-hex short
# id from ~/.claude/jobs. No flag passthrough, no file read; adds no env
# (inherits the session's own; a VAR= / env prefix on the call is denied by
# hooks/lone-excluded-bash.js). Absolute binary path (substituted at build time).
claude_bin="@claude@"
usage='usage: claude-bg respawn <id> | claude-bg logs <id> | claude-bg status'
die() { printf 'claude-bg: %s\n' "$1" >&2; exit 2; }
[ "$#" -ge 1 ] || die "$usage"
case "$1" in
  status)
    [ "$#" -eq 1 ] || die "$usage"
    exec "$claude_bin" daemon status
    ;;
  respawn | logs)
    [ "$#" -eq 2 ] || die "$usage"
    [[ $2 =~ ^[0123456789abcdef]{8}$ ]] || die 'id must be the 8-hex short id (ls ~/.claude/jobs): ^[0123456789abcdef]{8}$'
    exec "$claude_bin" "$1" "$2"
    ;;
  *) die "$usage" ;;
esac
