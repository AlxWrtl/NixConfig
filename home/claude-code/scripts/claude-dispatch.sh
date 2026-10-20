# claude-dispatch <name> "<brief>" — start ONE Claude Code session in a
# detached abduco session named <name> (attach: `abduco -a <name>`), hosted by
# a local abduco server, not by Claude's background daemon: daemon-hosted
# sessions lose the microphone (anthropics/claude-code#86217).
# Allow-list: abduco gets only `-n <name>`, the only flags claude ever gets are
# --worktree --name. No file read, no flag passthrough; adds no env (inherits
# the session's own; a VAR= / env prefix on the call is denied by
# hooks/lone-excluded-bash.js), minus the child-session marker
# CLAUDE_CODE_CHILD_SESSION: claude 2.1.305 does not save the transcript of a
# session that inherits it. Brief gets the `[claude-dispatch] ` marker:
# the launched session must not dispatch again.
# abduco's getopt is libSystem's (BSD): it stops at the first operand <name>,
# so claude's `--worktree` after it is never read as an abduco option
# (probed 2026-10-20: `abduco -v` prints the version, `abduco -n x cmd -v` goes
# on to create the session). A GNU-getopt build would permute: not this one.
# Absolute binary paths (substituted at build time).
abduco_bin="@abduco@"
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
unset CLAUDE_CODE_CHILD_SESSION
exec "$abduco_bin" -n "$name" "$claude_bin" --worktree "$name" --name "$name" "[claude-dispatch] $prompt"
