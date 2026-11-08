#!/usr/bin/env node
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");

const MAX_ROUNDS = 2;
const BUDGET_MS = 3000;
const MAX_INPUT = 4 * 1024 * 1024;
const TOKEN = /^\s*ttw\s*:\s*\+1\s+tour\s*$/i;
const ROUND = /^(.+)\.round([1-9][0-9]*)$/;
const GRANT = /^(.+)\.grant([1-9][0-9]*)$/;
const RUN_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const TTW_OUT = path.join(".claude", "output", "ttw");
const BUDGET_DIR = "ttw-correction-budget";
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

// A run outside the prompt's repo: the run dir its rounds were stamped with
// by correction-budget.js in this session. A stamp that is no readable JSON
// file, two dirs, or a dir that is not an existing absolute
// <repo>/.claude/output/ttw/<run-id> in plain ASCII is doubt: null.
// `rounds` are absolute paths: resolve keeps them as is.
function stampedDir(dir, id, rounds, session) {
  if (typeof session !== "string" || session === "") return null;
  let found = null;
  for (const n of rounds) {
    const f = path.resolve(dir, n);
    let s;
    try {
      if (!fs.statSync(f).isFile()) return null;
      s = JSON.parse(fs.readFileSync(f, "utf8"));
    } catch { return null; }
    if (!s || typeof s !== "object" || Array.isArray(s)) return null;
    if (s.session !== safe(session)) continue;
    if (typeof s.dir !== "string" || (found !== null && s.dir !== found)) return null;
    found = s.dir;
  }
  if (found === null || !path.isAbsolute(found) || found.includes("..") || safe(found) !== found || /[\s`]/.test(found)) return null;
  if (!path.dirname(found).endsWith(path.sep + TTW_OUT) || path.join(path.dirname(found), id) !== found) return null;
  return isDir(found) ? found : null;
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
  // Rounds and grants are read from, and grants written to, the budget dir
  // `dir`, as absolute paths.
  const dir = path.join(home, ".claude", BUDGET_DIR);
  const names = [];
  // A budget dir that is no real directory (a symlink, a file) is doubt:
  // its rounds and grants may be anyone's, so nothing is granted.
  let ents;
  try {
    if (!fs.lstatSync(dir).isDirectory()) { quiet(); return; }
    ents = fs.readdirSync(dir);
  } catch (e) {
    if (!e || e.code !== "ENOENT") { quiet(); return; }
    ents = [];
  }
  for (const n of ents) names.push(path.join(dir, n));

  const runs = new Map();
  const runOf = (id) => {
    let r = runs.get(id);
    if (!r) { r = { rounds: [], grants: 0 }; runs.set(id, r); }
    return r;
  };
  for (const full of names) {
    const n = path.basename(full);
    const round = ROUND.exec(n);
    const grant = round ? null : GRANT.exec(n);
    const id = round ? round[1] : grant ? grant[1] : null;
    if (id === null || !RUN_ID.test(id) || id.includes("..")) continue;
    const r = runOf(id);
    if (grant) r.grants++; else r.rounds.push(full);
  }

  // The live run is the project's run with the newest round; it alone may be
  // granted, and only once its budget, grants included, is spent. An older
  // spent run never is. An unreadable round, or a tie, is doubt: no grant.
  // A run whose dir is not under the cwd counts only through stampedDir.
  let target = null;
  let tie = false;
  for (const [id, r] of runs) {
    if (r.rounds.length === 0) continue;
    let where = null;
    if (!isDir(path.join(cwd, TTW_OUT, id))) {
      where = stampedDir(dir, id, r.rounds, data.session_id);
      if (where === null) continue;
    }
    let last = 0;
    for (const n of r.rounds) {
      let t;
      try { t = fs.statSync(path.resolve(dir, n)).mtimeMs; } catch { quiet(); return; }
      if (t > last) last = t;
    }
    if (target !== null && last === target.last) tie = true;
    if (target === null || last > target.last) { target = { id, rounds: r.rounds.length, grants: r.grants, last, where }; tie = false; }
  }
  if (target === null || tie || target.rounds < MAX_ROUNDS + target.grants) {
    say("correction-grant: `ttw: +1 tour` read, but this project has no latest correction run whose budget is spent; nothing was granted.");
    return;
  }

  // One grant per prompt, claimed by exclusive create.
  const stamp = JSON.stringify({ ts: new Date().toISOString(), session: safe(data.session_id) }) + "\n";
  // `dir` was read above; it may have been removed since.
  try {
    fs.mkdirSync(dir, { recursive: true });
  } catch (e) {
    say("correction-grant: could not record the grant for run " + target.id + " (" + safe(e && e.code ? e.code : "error") + "); nothing was granted.");
    return;
  }
  let code = "EEXIST";
  for (let n = 1; n <= target.grants + 1; n++) {
    try {
      fs.writeFileSync(path.join(dir, target.id + ".grant" + n), stamp, { flag: "wx" });
    } catch (e) {
      code = safe(e && e.code ? e.code : "error");
      if (code === "EEXIST") continue;
      break;
    }
    say("correction-grant: the user granted run " + target.id + " one more correction round (cap now " + (MAX_ROUNDS + target.grants + 1) + "). Spawn it on model: \"opus\" with TTW-CORRECTION-ROUND: " + (target.where === null ? target.id : target.where) + "; never run it inline.");
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
