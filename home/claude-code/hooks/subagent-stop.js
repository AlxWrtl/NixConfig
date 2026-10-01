#!/usr/bin/env node
let input = "";
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  const fs = require("fs");
  const path = require("path");
  try {
    const data = JSON.parse(input);
    const logDir = path.join(process.env.HOME, ".claude/output");
    fs.mkdirSync(logDir, { recursive: true });
    const entry = {
      ts: new Date().toISOString(),
      agent: data.agent_type || data.agent_name || "unknown",
      duration_ms: data.duration_ms || 0,
      summary: (data.task_description || "").slice(0, 200)
    };
    fs.appendFileSync(path.join(logDir, "agent-log.jsonl"), JSON.stringify(entry) + "\n");
  } catch (e) { process.exit(0); }
  process.exit(0);
});
