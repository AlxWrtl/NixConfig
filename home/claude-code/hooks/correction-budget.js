#!/usr/bin/env node
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");

const MAX_ROUNDS = 2;
const BUDGET_MS = 3000;
const RUN_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const MARKER = /^[\s>*`-]*APEX-CORRECTION-ROUND:\s*([^\s`]*)[\s`]*$/;
const MENTIONS = /06-resolve\.md|correction round/i;

let settled = false;
let marked = null;

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

function denyNoMarker() {
  deny("BLOCKED: this brief names 06-resolve.md or a correction round but has no APEX-CORRECTION-ROUND line. Add one on its own line: APEX-CORRECTION-ROUND: <run-id> for a correction round, APEX-CORRECTION-ROUND: none for any other brief, then retry.");
}

function denyState(what, file) {
  deny("BLOCKED: budget state " + what + ": " + safe(file) + "; inspect or remove it, or ask the user.");
}

// Past a marker naming a run, a failure must not let the round through.
function failed(why) {
  if (marked !== null) deny("BLOCKED: the correction-budget hook failed (" + safe(why) + ") on a correction round for run " + marked + "; ask the user.");
  allow();
}

let input = "";
let ran = false;

function main() {
  let data;
  try { data = JSON.parse(input); } catch { allow(); return; }
  if (!data || typeof data !== "object" || Array.isArray(data)) { allow(); return; }
  if (data.tool_name !== "Agent" && data.tool_name !== "Task" && data.tool_name !== "SendMessage") { allow(); return; }
  const ti = data.tool_input;
  if (!ti || typeof ti !== "object" || Array.isArray(ti)) { allow(); return; }
  // Agent/Task carry `prompt`, SendMessage `message`; a non-string
  // message (a structured request) is no brief.
  const prompt = [ti.prompt, ti.message].find((v) => typeof v === "string" && v !== "") || "";
  if (prompt === "") { allow(); return; }

  let marker = null;
  for (const line of prompt.split(/\r?\n/)) {
    const m = MARKER.exec(line);
    if (!m) continue;
    if (marker !== null && marker !== m[1]) {
      deny("BLOCKED: this brief carries conflicting APEX-CORRECTION-ROUND lines (" + safe(marker) + ", " + safe(m[1]) + "); keep exactly one, then retry.");
      return;
    }
    marker = m[1];
  }
  if (!marker && MENTIONS.test(prompt)) { denyNoMarker(); return; }
  if (marker === null || marker === "none") { allow(); return; }
  if (!RUN_ID.test(marker) || marker.includes("..")) {
    deny("BLOCKED: APEX-CORRECTION-ROUND names \"" + safe(marker) + "\", which is neither none nor a run-id like 62-correction-budget; fix the line, then retry.");
    return;
  }
  marked = marker;

  const cwd = typeof data.cwd === "string" && data.cwd !== "" ? data.cwd : process.cwd();
  const runDir = path.join(cwd, ".claude", "output", "apex", marker);
  let isDir = false;
  try { isDir = fs.statSync(runDir).isDirectory(); } catch { isDir = false; }
  if (!isDir) {
    deny("BLOCKED: APEX-CORRECTION-ROUND " + marker + ": run dir not found (" + safe(runDir) + "); name the run this round belongs to, then retry.");
    return;
  }

  const home = process.env.HOME || os.homedir();
  const dir = path.join(home, ".claude", "apex-correction-budget");
  const stamp = JSON.stringify({
    ts: new Date().toISOString(),
    tool: safe(data.tool_name),
    session: safe(data.session_id),
    description: safe(ti.description || ti.summary).slice(0, 200)
  }) + "\n";
  try { fs.mkdirSync(dir, { recursive: true }); } catch { denyState("unwritable", dir); return; }

  // Claim a slot by exclusive create: of two racing rounds, one wins.
  for (let n = 1; n <= MAX_ROUNDS; n++) {
    const slot = path.join(dir, marker + ".round" + n);
    try {
      fs.writeFileSync(slot, stamp, { flag: "wx" });
    } catch (e) {
      if (e && e.code === "EEXIST") continue;
      denyState("unwritable", slot);
      return;
    }
    allow();
    return;
  }
  deny("budget de correction épuisé (" + MAX_ROUNDS + "/" + MAX_ROUNDS + ") : livrer avec la liste des résiduels, ou demander à l'utilisateur (run " + marker + ")");
}

function start() {
  if (ran) return;
  ran = true;
  try {
    main();
  } catch (e) {
    failed(e && e.message);
  }
  failed("no decision reached");
}

process.on("uncaughtException", (e) => {
  if (settled) return;
  failed(e && e.message);
});

const watchdog = setTimeout(() => {
  failed("stdin not closed within " + BUDGET_MS + " ms");
}, BUDGET_MS);
if (typeof watchdog.unref === "function") watchdog.unref();

process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => { if (input.length < 4 * 1024 * 1024) input += c; });
process.stdin.on("end", start);
process.stdin.on("error", start);
