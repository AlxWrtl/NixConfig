#!/usr/bin/env bash
# SessionStart, and PostToolUse on EnterWorktree: when the event's cwd sits in
# a linked git worktree, copy in from the main checkout the root-level .env,
# .env.* and .dev.vars files the worktree lacks. A file is copied only if it is
# a regular file (a symlink is never followed), absent from the worktree (a
# file or a symlink there, dangling included, is never replaced or written
# through), ignored by the main checkout (so never one it tracks) and ignored
# by the worktree (so never one git there would commit). The copy keeps the
# mode; it lands on a temp file in the worktree, then a hard link that fails
# if the name appeared meanwhile (-n: a symlink to a directory planted there
# is not followed). Root only: nested files are left to the repo's own
# .worktreeinclude. Every git call passes -c core.fsmonitor=false: check-ignore
# reads the index, which would start the repo's own fsmonitor command, and
# this hook runs outside the sandbox.
# Fail-open, silent: exit 0 on every path, nothing on stderr, stdout only when
# something was copied. jq and git are absolute store paths, as the hook PATH
# is not guaranteed. bash 3.2-safe: no set -e/-u, no arrays.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
JQ="@jq@"
GIT="@git@"
tmp=""
trap '[ -z "$tmp" ] || rm -f "$tmp"' EXIT

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | "$JQ" -r '.hook_event_name // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | "$JQ" -r '.cwd // empty' 2>/dev/null)
case "$EVENT" in
SessionStart | PostToolUse) ;;
*) exit 0 ;;
esac
case "$CWD" in
/*) ;;
*) exit 0 ;;
esac
[ -d "$CWD" ] || exit 0

GD=$("$GIT" -c core.fsmonitor=false -C "$CWD" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
CD=$("$GIT" -c core.fsmonitor=false -C "$CWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
WT=$("$GIT" -c core.fsmonitor=false -C "$CWD" rev-parse --path-format=absolute --show-toplevel 2>/dev/null) || exit 0
[ -n "$GD" ] && [ -n "$CD" ] && [ -n "$WT" ] || exit 0
# A linked worktree has its own git dir; the main checkout's is the common one.
[ "$GD" != "$CD" ] || exit 0
case "$CD" in
*/.git) MAIN="${CD%/.git}" ;;
*) exit 0 ;;
esac
[ "$MAIN" != "$WT" ] && [ -d "$MAIN" ] && [ -d "$WT" ] || exit 0

LIST=""
shopt -s nullglob
for src in "$MAIN"/.env "$MAIN"/.env.* "$MAIN"/.dev.vars; do
  name="${src##*/}"
  case "$name" in *[[:cntrl:]]*) continue ;; esac
  if [ -L "$src" ] || [ ! -f "$src" ]; then continue; fi
  dst="$WT/$name"
  if [ -e "$dst" ] || [ -L "$dst" ]; then continue; fi
  "$GIT" -c core.fsmonitor=false -C "$MAIN" check-ignore -q -- "$name" 2>/dev/null || continue
  "$GIT" -c core.fsmonitor=false -C "$WT" check-ignore -q -- "$name" 2>/dev/null || continue
  tmp=$(mktemp "$WT/.worktree-env-sync.XXXXXX" 2>/dev/null) || continue
  if cp -p "$src" "$tmp" 2>/dev/null && ln -n "$tmp" "$dst" 2>/dev/null; then LIST="$LIST, $name"; fi
  rm -f "$tmp"
  tmp=""
done

[ -n "$LIST" ] || exit 0
MSG="worktree-env-sync: copied ${LIST#, } from the main checkout"
case "$EVENT" in
SessionStart) "$JQ" -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}' 2>/dev/null ;;
PostToolUse) "$JQ" -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}' 2>/dev/null ;;
esac
exit 0
