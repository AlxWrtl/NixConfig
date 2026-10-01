#!/usr/bin/env node
const fs = require("fs");
const path = require("path");
let input = "";
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  try {
    const data = JSON.parse(input);
    const logDir = path.join(process.env.HOME, ".claude/audit");
    fs.mkdirSync(logDir, { recursive: true });
    const entry = {
      ts: new Date().toISOString(),
      tool: data.tool_name || "unknown",
      target: "",
      session: data.session_id || ""
    };
    const ti = data.tool_input || {};
    if (ti.file_path) entry.target = ti.file_path;
    else if (ti.command) entry.target = ti.command.slice(0, 200);
    else if (ti.prompt) entry.target = "agent: " + (ti.prompt || "").slice(0, 100);
    fs.appendFileSync(
      path.join(logDir, "audit.jsonl"),
      JSON.stringify(entry) + "\n"
    );
  } catch {}
  process.exit(0);
});
