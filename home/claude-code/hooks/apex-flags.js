#!/usr/bin/env node
// PreToolUse on Skill: reports the context size at APEX start, nothing else.
//
// It used to classify risk from the BRIEF TEXT and rewrite the flags. Removed
// on 2026-10-07: a 28-line Notification matcher change was forced to
// high-stakes (Codex + Fable) only because the brief said "settings" and
// "hook". Words in a brief are not risk; the diff is. Risk is now decided on
// the diff by `apex-tier` (SKILL.md tier table). This hook never rewrites the
// call and never decides a permission.
//
// FAIL-OPEN: every error exits 0 (no output, or context=unknown).
const fs = require("fs");

const TAIL = 256 * 1024;

function contextTokens(path) {
  if (typeof path !== "string" || path === "") return null;
  let fd;
  try {
    fd = fs.openSync(path, "r");
    const size = fs.fstatSync(fd).size;
    const len = Math.min(size, TAIL);
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, size - len);
    const lines = buf.toString("utf8").split("\n");
    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i];
      if (!line.includes('"usage"')) continue;
      let entry;
      try { entry = JSON.parse(line); } catch (e) { continue; }
      const msg = entry && entry.message;
      const u = msg && msg.usage;
      if (!u || (entry.type !== "assistant" && msg.role !== "assistant")) continue;
      const n = (u.input_tokens || 0) + (u.cache_read_input_tokens || 0)
        + (u.cache_creation_input_tokens || 0);
      return Number.isFinite(n) ? n : null;
    }
    return null;
  } catch (e) {
    return null;
  } finally {
    if (fd !== undefined) { try { fs.closeSync(fd); } catch (e) { /* fail open */ } }
  }
}

let input = "";
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  try {
    const data = JSON.parse(input);
    const ti = data.tool_input || {};
    if (ti.skill !== "apex") process.exit(0);
    const n = contextTokens(data.transcript_path);
    const tp = typeof data.transcript_path === "string" ? data.transcript_path : "unknown";
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: "APEX start: context=" + (n === null ? "unknown" : n)
          + " tokens; transcript=" + tp
          + ". Tier is decided on the diff (SKILL.md); apex-tier re-checks it."
      }
    }));
  } catch (e) { /* fail open */ }
  process.exit(0);
});
