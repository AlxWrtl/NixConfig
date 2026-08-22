# graphify-reindex — incremental refresh of the AlxVault knowledge graph.
# (writeShellApplication prepends set -euo pipefail and shellchecks at build.)
#
# Fired in the BACKGROUND by APEX step-09b (after the session note is written)
# and by step-01b (catch-up when the graph is stale). Contract with callers:
#   - ALWAYS exits 0: a failed reindex degrades to a stale graph; it never
#     blocks or fails a session. The next run catches up.
#   - Single-instance: atomic mkdir lock; a lock older than 120 min is a
#     crashed run and gets reclaimed.
#   - NEVER trusts graphify's exit code — `graphify extract` returns 0 even
#     when the whole extraction failed. Verifies node count + graph mtime.
#   - NEVER writes into the vault: reads 02-Projets, writes only to $OUT.
#     The explicit --out is mandatory — without it graphify drops
#     graphify-out/ INSIDE the scanned vault directory.
#   - Refuses the INITIAL full build (164 serial claude-cli calls, hours):
#     that one is launched manually. This script is incremental-only — the
#     semantic cache is keyed on content hashes, unchanged notes cost nothing.

VAULT="$HOME/Documents/AlxVault/02-Projets"
OUT="$HOME/GraphVault"
GRAPH="$OUT/graphify-out/graph.json"
LOCK="$OUT/.reindex.lock"
LOG="$OUT/reindex.log"
GRAPHIFY="$HOME/.local/bin/graphify"

# The claude-cli backend shells out to `claude` (homebrew). Make it reachable
# even from a minimal PATH (sandboxed Bash, hooks). Serial on purpose: do NOT
# set GRAPHIFY_CLAUDE_CLI_PARALLEL.
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

if [ ! -d "$VAULT" ]; then
  echo "graphify-reindex: vault dir missing ($VAULT) — skip"
  exit 0
fi
if [ ! -x "$GRAPHIFY" ]; then
  echo "graphify-reindex: graphify not installed — skip"
  exit 0
fi

if [ ! -f "$GRAPH" ]; then
  echo "graphify-reindex: no graph.json yet — the initial full build is manual; run:"
  echo "  graphify extract \"$VAULT\" --backend claude-cli --out \"$OUT\" && graphify cluster-only \"$OUT\" --backend claude-cli"
  exit 0
fi

# Freshness gate: no note newer than the graph -> no-op.
if [ -z "$(find "$VAULT" -name '*.md' -newer "$GRAPH" -print -quit 2>/dev/null)" ]; then
  echo "graphify-reindex: graph already fresh — nothing to do"
  exit 0
fi

# Single-instance lock (atomic mkdir).
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then
    rmdir "$LOCK" 2>/dev/null || true
    if ! mkdir "$LOCK" 2>/dev/null; then
      echo "graphify-reindex: lock contention — skip"
      exit 0
    fi
  else
    echo "graphify-reindex: another reindex is running — skip"
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# Cheap log rotation: keep the tail if the log grows past ~1 MB.
if [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 1000000 ]; then
  { tail -c 100000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; } || true
fi

before_nodes="$(jq -r '(.nodes // []) | length' "$GRAPH" 2>/dev/null || echo 0)"
before_mtime="$(stat -c %Y "$GRAPH" 2>/dev/null || echo 0)"

{
  echo "=== graphify-reindex $(date '+%Y-%m-%dT%H:%M:%S') ==="
  # Incremental semantic extraction of new/changed notes only.
  "$GRAPHIFY" extract "$VAULT" --backend claude-cli --out "$OUT" || true
  # Mandatory after extract: (re)name communities, else placeholders remain.
  "$GRAPHIFY" cluster-only "$OUT" --backend claude-cli || true
} >>"$LOG" 2>&1

after_nodes="$(jq -r '(.nodes // []) | length' "$GRAPH" 2>/dev/null || echo 0)"
after_mtime="$(stat -c %Y "$GRAPH" 2>/dev/null || echo 0)"

if [ "$after_nodes" -gt 0 ] && [ "$after_mtime" -gt "$before_mtime" ]; then
  echo "graphify-reindex: OK — $after_nodes nodes (was $before_nodes), graph refreshed"
else
  echo "graphify-reindex: WARN — graph NOT refreshed (nodes: $before_nodes -> $after_nodes); see $LOG"
fi
exit 0
