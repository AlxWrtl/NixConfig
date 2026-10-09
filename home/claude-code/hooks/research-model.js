#!/usr/bin/env node
"use strict";
const fs = require("fs");

const BUDGET_MS = 3000;
const RESEARCH = ["Explore", "codebase-navigator"];

let settled = false;

// process.exit() truncates a pending async pipe write, which would drop
// the deny payload itself: write synchronously, retry, never throw.
function writeAll(fd, text) {
  let buf;
  try { buf = Buffer.from(String(text), "utf8"); } catch { return; }
  let off = 0;
  let spins = 0;
  while (off < buf.length && spins < 100000) {
    spins++;
    try {
      off += fs.writeSync(fd, buf, off, buf.length - off);
    } catch (e) {
      if (e && (e.code === "EAGAIN" || e.code === "EINTR")) continue;
      return;
    }
  }
}

function safe(s) {
  return String(s === undefined || s === null ? "" : s).replace(/[^\x20-\x7e]/g, "?");
}

function deny(reason) {
  if (settled) return;
  settled = true;
  writeAll(1, JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason
    }
  }));
  process.exit(0);
}

function allow() {
  if (settled) return;
  settled = true;
  process.exit(0);
}

const MAX_INPUT = 4 * 1024 * 1024;

let input = "";
let overflow = false;
let ran = false;

function main() {
  let data;
  try { data = JSON.parse(input); } catch { allow(); return; }
  if (!data || typeof data !== "object" || Array.isArray(data)) { allow(); return; }
  if (data.tool_name !== "Agent" && data.tool_name !== "Task") { allow(); return; }
  const ti = data.tool_input;
  if (!ti || typeof ti !== "object" || Array.isArray(ti)) { allow(); return; }
  const type = ti.subagent_type;
  if (!RESEARCH.includes(type)) { allow(); return; }
  if (ti.model === "haiku") { allow(); return; }
  const absent = ti.model === undefined || ti.model === null || ti.model === "";
  const asked = absent ? "absent" : "\"" + safe(ti.model) + "\"";
  deny("BLOCKED: research agents run on haiku. This " + type + " spawn has model " + asked + "; re-spawn it with model: \"haiku\" (read-only search). Analyze synthesis is a separate spawn: subagent_type: Plan, model: \"opus\".");
}

// Fail-open: a cost guard, not a barrier; a broken hook must not stop work.
function start() {
  if (ran) return;
  ran = true;
  // Never parse a truncated prefix: input not fully read is allowed silently.
  if (overflow) { allow(); return; }
  try {
    main();
  } catch {
    allow();
  }
  allow();
}

process.on("uncaughtException", () => {
  allow();
});

const watchdog = setTimeout(() => {
  allow();
}, BUDGET_MS);
if (typeof watchdog.unref === "function") watchdog.unref();

process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => {
  if (overflow) return;
  if (input.length + c.length > MAX_INPUT) { overflow = true; input = ""; return; }
  input += c;
});
process.stdin.on("end", start);
process.stdin.on("error", start);
