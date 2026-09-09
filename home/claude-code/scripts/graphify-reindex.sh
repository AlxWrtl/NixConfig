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

VAULT="$HOME/Vaults/AlxVault/02-Projets"
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

# NUMBA CACHE — the clustering step depended on a directory the sandbox denies.
# graphify pulls graspologic, which pulls hyppo, whose dcorr.py carries
# `@jit(nopython=True, cache=True)`. numba writes that cache NEXT TO the .py
# source, i.e. under ~/.local/share/uv/tools/graphifyy/... — a 755 directory
# owned by the user, yet Claude's Bash sandbox refuses to write there
# (`touch .../hyppo/independence/.sandbox-write-test` -> Operation not
# permitted). With nowhere to write, numba raises
# `RuntimeError: cannot cache function '_center_distmat': no locator available`.
# Measured 2026-08-24: extraction of the two new notes succeeded, clustering
# crashed, graph.json was never rewritten — 1506 nodes in, 1506 out, caught by
# this script's own WARN because it never trusts graphify's exit code. $OUT is
# already in sandbox.allowWrite (settings.nix), so pointing numba there makes
# the failure unrepresentable instead of merely unlikely.
# MPLCONFIGDIR is slowness only, never a failure: without it matplotlib rebuilds
# its font cache on every run.
export NUMBA_CACHE_DIR="$OUT/.numba-cache"
export MPLCONFIGDIR="$OUT/.mpl-cache"
mkdir -p "$NUMBA_CACHE_DIR" "$MPLCONFIGDIR"

# RECURSION MARKER — inherited by the nested `claude` the claude-cli backend
# spawns. The SessionEnd hook tests it and refuses to fire again, so a reindex
# can never trigger the reindex of its own child session. The mkdir lock and the
# freshness gate already bound that loop; this marker cuts it outright.
export GRAPHIFY_REINDEX_ACTIVE=1

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
  # A FULL `label` — not `cluster-only`, and no longer `--missing-only`. Two
  # decisions are stacked in that one line and both were measured.
  #
  # (1) Never `cluster-only` on an incremental run (24/08, still true).
  #     `extract` already runs Leiden, so new nodes land in communities on their
  #     own, just under "Community N" placeholders; only the naming is missing.
  #     `cluster-only` RE-clusters and then renames WITHOUT the LLM, falling
  #     back to naming each community after its hub node. Measured after adding
  #     a single note: "Preliz Business Strategy" became "Session 2026-07-21
  #     (soir) — Wizard ajout véhicule…" — 124 of 140 names destroyed in one
  #     run. That verdict is untouched: cluster-only is right for the INITIAL
  #     build (see the message above), destructive on every incremental one.
  #
  # (2) `--missing-only` was the 24/08 answer to (1), and it is the WRONG answer
  #     to a second, distinct failure: obsolescence by index (25/08).
  #     `.graphify_labels.json` is keyed by community NUMBER, and Leiden
  #     reassigns those numbers at every partition — a saved name therefore
  #     follows the index, not the nodes. Measured: community #5 held 34 nodes
  #     coming ALL from the note written on 25/08 (34 = exactly the 1558 -> 1592
  #     growth) yet carried "Named Invitation Signup Flow", inherited from
  #     whatever cluster occupied index 5 in an earlier partition.
  #     `--missing-only` skips every community that already has a name, so that
  #     false name stays glued on forever. graphify recommends the way out in
  #     its own log: `Run 'graphify label' to refresh names with the LLM.`
  #
  # Affordable: the full rename is measured at 47 s. `--batch-size` groups 100
  # communities per LLM call — this is NOT one call per community.
  # Remapping the saved names onto the new partition by content overlap (zero
  # LLM calls) was evaluated and dropped: `label` RE-clusters on its own
  # (142 -> 145 communities observed), so any mapping computed upstream is
  # invalidated by label's own re-partition.
  #
  # And just as this script never trusts graphify's exit code, it does not trust
  # the RESULT of the rename either: a full `label` whose LLM leg dies could
  # degrade EVERY name into a "Community N" marker, which is strictly worse than
  # stale names. Snapshot before, sanity-check after, roll back on collapse.
  # The rollback covers `.graphify_labels.json` ONLY: the `community_name`
  # markers `label` already wrote into graph.json stay there until the next
  # successful rename — and since the reindex now runs a FULL `label` every
  # pass, that next pass IS the repair. The loud line in the log is the bulk
  # of the value here: without it, a name collapse would pass unnoticed.
  # Every step is neutralised (`|| true`) because of set -euo pipefail: a broken
  # guard must never break the reindex, which owes its callers an exit 0.
  LABELS="$OUT/graphify-out/.graphify_labels.json"
  LABELS_BAK="$OUT/.graphify_labels.json.prelabel"
  rm -f "$LABELS_BAK" || true
  if [ -f "$LABELS" ]; then
    cp "$LABELS" "$LABELS_BAK" || true
  fi

  "$GRAPHIFY" label "$OUT" --backend claude-cli || true

  if [ -f "$LABELS_BAK" ]; then
    marker_pct="$(jq -r '
      [ .[] | select(type == "string") ] as $names
      | if ($names | length) == 0 then 0
        else ([ $names[] | select(test("^Community [0-9]+$")) ] | length)
             * 100 / ($names | length)
        end | floor' "$LABELS" 2>/dev/null || echo 0)"
    case "$marker_pct" in
      '' | *[!0-9]*) marker_pct=0 ;;
    esac
    if [ "$marker_pct" -gt 50 ]; then
      echo "graphify-reindex: !! LABEL COLLAPSE — ${marker_pct}% of community names are bare \"Community N\" markers."
      echo "   The LLM leg of \`graphify label\` failed; restoring the pre-label snapshot of .graphify_labels.json."
      echo "   graph.json keeps the bare markers until the next reindex renames them all — inspect the graphify output just above."
      cp "$LABELS_BAK" "$LABELS" || true
    fi
    rm -f "$LABELS_BAK" || true
  fi
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
