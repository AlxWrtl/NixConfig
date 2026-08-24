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
# set GRAPHIFY_CLAUDE_CLI_PARALLEL — parallel subprocesses conflict over
# Claude Code session state, it is not merely a rate-limit guard.
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

# LEAK FIX — the root cause, not a workaround.
# `--out` does not cover every writer: on 2026-08-24 a run with --out still
# created <VAULT>/graphify-out/cache/ INSIDE the scanned vault. graphify/paths.py
# is the single source of truth for that directory and reads GRAPHIFY_OUT once at
# import time; it accepts an ABSOLUTE path and is the upstream-documented
# mechanism for shared-output setups (#686, #1423 centralised it so every reader
# honours it). Exporting it absolute makes a vault-relative cache path
# unrepresentable. The check after the extraction stays as a belt-and-braces
# guard in case a future writer regresses.
export GRAPHIFY_OUT="$HOME/GraphVault/graphify-out"

# NO model pinned on purpose. claude-cli defaults to Opus, and the whole 164-note
# corpus was extracted with Opus for uniformity. Pinning haiku/sonnet here would
# extract each NEW note with a different model than the corpus it joins,
# recreating the two-speed graph the rebuild was done to eliminate. At one or two
# notes per session the cost is negligible. This is a decision, not an omission.

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
  # `label --missing-only`, NOT `cluster-only` — the distinction matters and was
  # learned the hard way. `extract` already runs Leiden, so new nodes land in
  # communities on their own, just under "Community N" placeholders; only the
  # naming is missing. `cluster-only` RE-clusters and renames everything, so the
  # community set shifts, the saved labels no longer match, and graphify falls
  # back to naming each community after its hub node. Measured after adding a
  # single note: "Preliz Business Strategy" and "Security Audit Findings" became
  # "Session 2026-07-21 (soir) — Wizard ajout véhicule…" — 124 of 140 names lost
  # in one run. cluster-only IS right for the initial build (see the message
  # above); it is destructive on every incremental one. --missing-only keeps
  # existing labels and names only the new placeholders, so the cost is a few
  # calls instead of 140.
  "$GRAPHIFY" label "$OUT" --missing-only --backend claude-cli || true
} >>"$LOG" 2>&1

# Belt-and-braces: GRAPHIFY_OUT above should make this impossible, so anything
# found here is a NEW upstream regression and must be loud, never swallowed.
# Strictly bounded to that one path — no recursive delete anywhere else.
LEAK="$VAULT/graphify-out"
if [ -d "$LEAK" ]; then
  if [ -n "$(find "$LEAK" -name '*.md' -print -quit 2>/dev/null)" ]; then
    echo "graphify-reindex: !! $LEAK contains .md files — NOT removing it."
    echo "   This is a different, worse regression than the cache leak: inspect by hand."
  else
    rm -rf "$LEAK"
    echo "graphify-reindex: !! graphify wrote $LEAK despite GRAPHIFY_OUT — removed (cache only)."
    echo "   The GRAPHIFY_OUT override no longer covers every writer: report upstream."
  fi
fi

after_nodes="$(jq -r '(.nodes // []) | length' "$GRAPH" 2>/dev/null || echo 0)"
after_mtime="$(stat -c %Y "$GRAPH" 2>/dev/null || echo 0)"

if [ "$after_nodes" -gt 0 ] && [ "$after_mtime" -gt "$before_mtime" ]; then
  echo "graphify-reindex: OK — $after_nodes nodes (was $before_nodes), graph refreshed"
else
  echo "graphify-reindex: WARN — graph NOT refreshed (nodes: $before_nodes -> $after_nodes); see $LOG"
fi
exit 0
