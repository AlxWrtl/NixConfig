# claude-dispatch <name> "<brief>" — start ONE background Claude Code session.
# Allow-list: the only flags claude ever gets are --bg --name. No file read,
# no flag passthrough; adds no env (inherits the session's own; a VAR= / env
# prefix on the call is denied by hooks/lone-excluded-bash.js). Brief gets the
# `[claude-dispatch] ` marker: the launched session must not dispatch again.
# Absolute binary path (substituted at build time).
claude_bin="@claude@"
die() { printf 'claude-dispatch: %s\n' "$1" >&2; exit 2; }
[ "$#" -eq 2 ] || die 'usage: claude-dispatch <name> "<one-line brief>"'
name=$1
prompt=$2
[[ $name =~ ^[a-z0-9][a-z0-9-]{0,47}$ ]] || die 'name must match ^[a-z0-9][a-z0-9-]{0,47}$'
[ -n "$prompt" ] || die 'empty brief'
[[ $prompt != -* ]] || die 'brief must not start with -'
[[ $prompt =~ [^[:space:]]+[[:space:]]+[^[:space:]] ]] || die 'brief must be several words (one word can be read as a claude subcommand)'
[[ $prompt != *[[:cntrl:]]* ]] || die 'brief must be one line, no control characters'
[ "${#prompt}" -le 8000 ] || die 'brief longer than 8000 characters'
exec "$claude_bin" --bg --name "$name" "[claude-dispatch] $prompt"
