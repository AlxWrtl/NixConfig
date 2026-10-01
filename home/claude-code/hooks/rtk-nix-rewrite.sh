#!/usr/bin/env bash
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

[ "$TOOL_NAME" = "Bash" ] || exit 0
command -v rtk >/dev/null 2>&1 || exit 0

# Simple commands only (compound/for/pipe lines won't match) — never double-wrap
if echo "$COMMAND" | grep -qE '^(nix-instantiate|nixfmt) '; then
  echo "$INPUT" | jq '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input | .command = "rtk " + .command)}}'
fi
exit 0
