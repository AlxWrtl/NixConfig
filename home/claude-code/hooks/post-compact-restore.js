#!/usr/bin/env node
const fs = require("fs");
const path = require("path");
let input = "";
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  const stateFile = path.join(process.env.HOME, ".claude/compact-state.json");
  try {
    const state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
    // Skip if state is stale (>1 hour)
    const age = Date.now() - new Date(state.ts).getTime();
    if (age > 3600000) { process.exit(0); return; }
    const parts = [];
    if (state.branch) parts.push("Branch: " + state.branch);
    if (state.modifiedFiles && state.modifiedFiles.length > 0)
      parts.push("Modified files: " + state.modifiedFiles.join(", "));
    if (state.stagedFiles && state.stagedFiles.length > 0)
      parts.push("Staged files: " + state.stagedFiles.join(", "));
    if (state.activePlans && state.activePlans.length > 0)
      parts.push("Active plans in .claude/output/: " + state.activePlans.join(", "));
    if (state.circuitBreaker && state.circuitBreaker.totalTrips > 0)
      parts.push("Circuit breaker trips: " + state.circuitBreaker.totalTrips);
    if (parts.length > 0) {
      const ctx = "POST-COMPACT STATE RESTORE:\n" + parts.join("\n");
      // MEASURED 2026-09-22, and this shape does NOT make the hook work.
      // The official reference lists PostCompact, verbatim, under
      // "None | No decision control. Used for side effects like logging or
      // cleanup", and the document carries no `PostCompact decision
      // control` section at all — both replay in one command each, with no
      // count to rot. So this event
      // honours no additionalContext: whatever is written here reaches
      // nobody. The nested form is kept only so the shape is right the day
      // the event gains one. What actually restores context after a
      // compaction is the SessionStart hook with matcher "compact"
      // (compact-context.sh) — that one is on a channel that exists.
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: { hookEventName: "PostCompact", additionalContext: ctx }
      }));
    }
  } catch {}
  process.exit(0);
});
