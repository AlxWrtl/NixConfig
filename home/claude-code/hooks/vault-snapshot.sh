#!/usr/bin/env bash
SNAP="@vaultSnapshotPkg@/bin/vault-snapshot"
LOG="$HOME/GraphVault/vault-snapshot.log"
mkdir -p "$HOME/GraphVault" 2>/dev/null

# Nested `claude -p` sessions spawned by graphify-reindex end too: same
# recursion guard as hookGraphifyReindex, before the busy check.
if [ -n "${GRAPHIFY_REINDEX_ACTIVE:-}" ]; then
  printf '%s event=SessionEnd skip=recursion\n' "$(date '+%Y-%m-%dT%H:%M:%S')" >>"$LOG"
  exit 0
fi

# One snapshot at a time: parallel sessions ending together would race on
# the release rotation and could delete a generation that was still the
# newest proven one.
if command -v pgrep >/dev/null 2>&1; then
  if pgrep -f "bin/vault-snapshot" >/dev/null 2>&1; then
    printf '%s event=SessionEnd skip=busy\n' "$(date '+%Y-%m-%dT%H:%M:%S')" >>"$LOG"
    exit 0
  fi
fi

( nohup "$SNAP" >>"$LOG" 2>&1 </dev/null & )

INPUT=$(cat)
: "$INPUT"
exit 0
