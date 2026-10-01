#!/usr/bin/env node
const fs = require("fs");
const path = require("path");
let input = "";
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  const stateFile = path.join(process.env.HOME, ".claude/circuit-breaker-state.json");
  let state = { consecutiveFailures: 0, totalTrips: 0, lastTool: "", lastError: "" };
  try { state = JSON.parse(fs.readFileSync(stateFile, "utf8")); } catch {}
  try {
    const data = JSON.parse(input);
    state.consecutiveFailures++;
    state.lastTool = data.tool_name || "unknown";
    state.lastError = (data.error || "").slice(0, 200);
    let ctx = "";
    if (state.consecutiveFailures >= 5) {
      state.totalTrips++;
      state.consecutiveFailures = 0;
      ctx = "CIRCUIT BREAKER TRIPPED (" + state.totalTrips + " total). STOP retrying the same approach. Step back, re-read the code, and try a structurally different solution.";
    } else if (state.consecutiveFailures >= 3) {
      ctx = "WARNING: " + state.consecutiveFailures + " consecutive tool failures on " + state.lastTool + ". Consider a different approach before continuing.";
    }
    fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
    if (ctx) {
      // Only the nested form carrying hookEventName is documented.
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: { hookEventName: "PostToolUseFailure", additionalContext: ctx }
      }));
    }
  } catch {}
  process.exit(0);
});
