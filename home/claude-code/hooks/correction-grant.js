#!/usr/bin/env node
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");

const MAX_ROUNDS = 2;
const BUDGET_MS = 3000;
const MAX_INPUT = 4 * 1024 * 1024;
const TOKEN = /^\s*apex\s*:\s*\+1\s+tour\s*$/i;
const ROUND = /^(.+)\.round([1-9][0-9]*)$/;
const GRANT = /^(.+)\.grant([1-9][0-9]*)$/;
const RUN_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const WRAPPERS = ["<task-notification", "<agent-message", "Another Claude session sent a message", "[SYSTEM NOTIFICATION", "<teammate-message", "<command-name>", "<local-command", "<scheduled-task", "<system-reminder"];

let settled = false;

function firstLine(text) {
  for (const l of text.split(/\r?\n/)) if (l.trim() !== "") return l;
  return "";
}

// process.exit() truncates a pending async pipe write, which would drop
// the context payload itself: write synchronously, retry, never throw.
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

function say(text) {
  if (settled) return;
  settled = true;
  writeAll(1, JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: text
    }
  }));
  process.exit(0);
}

function quiet() {
  if (settled) return;
  settled = true;
  process.exit(0);
}

function isDir(p) {
  try { return fs.statSync(p).isDirectory(); } catch { return false; }
}

let input = "";
let overflow = false;
let ran = false;

function main() {
  let data;
  try { data = JSON.parse(input); } catch { quiet(); return; }
  if (!data || typeof data !== "object" || Array.isArray(data)) { quiet(); return; }
  // Only the user's own prompt grants: a subagent's input never does, and an
  // agent_id of any value is doubt enough.
  if (Object.prototype.hasOwnProperty.call(data, "agent_id") && data.agent_id !== undefined) { quiet(); return; }
  if (typeof data.prompt !== "string") { quiet(); return; }
  // The token is the prompt's first non-empty line, whole: quoted inside a
  // sentence (a deny text read back) or further down it grants nothing.
  if (!TOKEN.test(firstLine(data.prompt))) { quiet(); return; }
  // Task notifications and agent hand-backs reach this event as user turns
  // without agent_id: text the model wrote, wrapped by the harness.
  if (WRAPPERS.some((w) => data.prompt.includes(w))) { quiet(); return; }

  if (typeof data.cwd !== "string" || !path.isAbsolute(data.cwd)) { quiet(); return; }
  const cwd = data.cwd;
  const home = process.env.HOME || os.homedir();
  const dir = path.join(home, ".claude", "apex-correction-budget");
  let names;
  try {
    names = fs.readdirSync(dir);
  } catch (e) {
    if (!e || e.code !== "ENOENT") { quiet(); return; }
    names = [];
  }

  const runs = new Map();
  const runOf = (id) => {
    let r = runs.get(id);
    if (!r) { r = { rounds: [], grants: 0 }; runs.set(id, r); }
    return r;
  };
  for (const n of names) {
    const round = ROUND.exec(n);
    const grant = round ? null : GRANT.exec(n);
    const id = round ? round[1] : grant ? grant[1] : null;
    if (id === null || !RUN_ID.test(id) || id.includes("..")) continue;
    const r = runOf(id);
    if (grant) r.grants++; else r.rounds.push(n);
  }

  // The live run is the project's run with the newest round; it alone may be
  // granted, and only once its budget, grants included, is spent. An older
  // spent run never is. An unreadable round, or a tie, is doubt: no grant.
  let target = null;
  let tie = false;
  for (const [id, r] of runs) {
    if (r.rounds.length === 0) continue;
    if (!isDir(path.join(cwd, ".claude", "output", "apex", id))) continue;
    let last = 0;
    for (const n of r.rounds) {
      let t;
      try { t = fs.statSync(path.join(dir, n)).mtimeMs; } catch { quiet(); return; }
      if (t > last) last = t;
    }
    if (target !== null && last === target.last) tie = true;
    if (target === null || last > target.last) { target = { id, rounds: r.rounds.length, grants: r.grants, last }; tie = false; }
  }
  if (target === null || tie || target.rounds < MAX_ROUNDS + target.grants) {
    say("correction-grant: `apex: +1 tour` read, but this project has no latest correction run whose budget is spent; nothing was granted.");
    return;
  }

  // One grant per prompt, claimed by exclusive create.
  const stamp = JSON.stringify({ ts: new Date().toISOString(), session: safe(data.session_id) }) + "\n";
  let code = "EEXIST";
  for (let n = 1; n <= target.grants + 1; n++) {
    try {
      fs.writeFileSync(path.join(dir, target.id + ".grant" + n), stamp, { flag: "wx" });
    } catch (e) {
      code = safe(e && e.code ? e.code : "error");
      if (code === "EEXIST") continue;
      break;
    }
    say("correction-grant: the user granted run " + target.id + " one more correction round (cap now " + (MAX_ROUNDS + target.grants + 1) + "). Spawn it on model: \"opus\" with APEX-CORRECTION-ROUND: " + target.id + "; never run it inline.");
    return;
  }
  say("correction-grant: could not record the grant for run " + target.id + " (" + code + "); nothing was granted.");
}

// Fail-open: a broken grant hook grants nothing and stops no prompt.
function start() {
  if (ran) return;
  ran = true;
  if (overflow) { quiet(); return; }
  try {
    main();
  } catch {
    quiet();
  }
  quiet();
}

process.on("uncaughtException", () => {
  quiet();
});

const watchdog = setTimeout(() => {
  quiet();
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
