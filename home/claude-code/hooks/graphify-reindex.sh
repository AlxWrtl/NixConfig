#!/usr/bin/env bash
if [ -n "${GRAPHIFY_REINDEX_ACTIVE:-}" ]; then
  SKIP=recursion
else
  SKIP=
fi

HOOKLOG="$HOME/GraphVault/reindex-hook.log"
mkdir -p "$HOME/GraphVault" 2>/dev/null
if ! ( : >>"$HOOKLOG" ) 2>/dev/null; then
  HOOKLOG=/dev/null
fi

REINDEX="@graphifyReindexPkg@/bin/graphify-reindex"
TS=$(date '+%Y-%m-%dT%H:%M:%S')

if [ -f "$HOOKLOG" ]; then
  SIZE=$(wc -c <"$HOOKLOG" 2>/dev/null | tr -d ' ')
  if [ "${SIZE:-0}" -gt 65536 ] 2>/dev/null; then
    ROTTMP="$HOOKLOG.$$"
    if cp "$HOOKLOG" "$ROTTMP" 2>/dev/null; then
      : >"$HOOKLOG"
      tail -c 32768 "$ROTTMP" >>"$HOOKLOG" 2>/dev/null
    fi
    rm -f "$ROTTMP" 2>/dev/null
  fi
fi

if [ -n "$SKIP" ]; then
  printf '%s event=SessionEnd skip=recursion cwd=%s\n' "$TS" "$PWD" >>"$HOOKLOG"
  exit 0
fi

if command -v pgrep >/dev/null 2>&1; then
  if pgrep -f 'graphify extract' >/dev/null 2>&1; then
    printf '%s event=SessionEnd skip=busy cwd=%s\n' "$TS" "$PWD" >>"$HOOKLOG"
    exit 0
  fi
fi

( nohup "$REINDEX" >>"$HOOKLOG" 2>&1 </dev/null & )

INPUT=$(cat)
REASON=$(printf '%s' "$INPUT" | sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
SESSION=$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
printf '%s event=SessionEnd fire reason=%s session=%s cwd=%s\n' \
  "$TS" "$REASON" "$SESSION" "$PWD" >>"$HOOKLOG"

exit 0
