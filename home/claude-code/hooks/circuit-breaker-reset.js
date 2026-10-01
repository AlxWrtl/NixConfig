#!/usr/bin/env node
const fs = require("fs");
const path = require("path");
let input = "";
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  const stateFile = path.join(process.env.HOME, ".claude/circuit-breaker-state.json");
  try {
    const state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
    if (state.consecutiveFailures > 0) {
      state.consecutiveFailures = 0;
      fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
    }
  } catch {}
  process.exit(0);
});
