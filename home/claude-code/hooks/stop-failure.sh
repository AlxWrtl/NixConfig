#!/usr/bin/env bash
# Alert on rate limits or API failures
INPUT=$(cat)
if echo "$INPUT" | grep -qi "rate.limit\|429\|overloaded"; then
  osascript -e 'display notification "Rate limit hit — pause recommended" with title "Claude Code" sound name "Basso"' 2>/dev/null || true
fi
