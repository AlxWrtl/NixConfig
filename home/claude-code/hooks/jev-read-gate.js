#!/usr/bin/env node
"use strict";

// PreToolUse on Read: the FIRST whole Read of a text file over 30 KB, per
// session and per agent, is denied with the way to locate first.
//
// WHY. Reading a whole page, log or source file to answer one targeted
// question spends its whole size in context. `jev-locate FILE "question"`
// asks TypeSafe Jev which ~2.5 KB block answers it and prints that block
// with its `lines A-B` span; a Read with offset/limit then costs a few KB.
// A rule in CLAUDE.md saying so was read and skipped: this is the nudge at
// the moment it applies. It stays a nudge: the same Read re-issued passes,
// so a file that has to be read whole (an edit across it, a synthesis,
// JEV FULL, a jev-locate error) costs one round trip, never a dead end.
//
// SHAPES. tool_input.file_path, absolute (the host expands ~ and relative
// paths before hooks). Allowed untouched: offset, limit or pages present,
// allow_large true, an image/PDF/notebook extension, a path that does not
// stat as a regular file, a file of 30 KB or less. Otherwise the key is
// (session_id, agent_id): each subagent gets its own nudge. A marker per
// file under $HOME/.claude/jev-read-gate/<key>/ is created exclusively
// ("wx"): created means first attempt, deny; EEXIST means second, allow.
// Every call refreshes its key dir's mtime; a key dir this call created
// prunes its siblings idle (by that mtime) for 7 days. A base or key dir
// that is a symlink or not a directory allows, with nothing written.
//
// FAIL POLICY: open everywhere. A workflow nudge, not a guard: unreadable
// or oversized input, a throw, the watchdog (3 s, under the host's 5 s) and
// a state dir that cannot be written all allow, in silence. No deny is ever
// sent without its marker on disk, so a second attempt always passes.
// Nothing is written to stderr on any path.
//
// Anchored lines (checks/hook-wiring.nix mutants) hold one statement each.

const fs = require("fs");
const path = require("path");
const os = require("os");
const crypto = require("crypto");

const BUDGET_MS = 3000;
const MAX_INPUT = 4 * 1024 * 1024;
const THRESHOLD = 30 * 1024;
const SKIP_EXT = /\.(png|jpe?g|gif|webp|bmp|tiff?|heic|ico|pdf|ipynb)$/i;
const PRUNE_AGE_MS = 7 * 24 * 60 * 60 * 1000;
const PRUNE_MAX = 512;

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

function present(v) {
  return v !== undefined && v !== null;
}

// https://nodejs.org/docs/latest-v24.x/api/crypto.html#cryptocreatehashalgorithm-options
function digest(s) {
  return crypto.createHash("sha256").update(s, "utf8").digest("hex").slice(0, 32);
}

// Key dirs idle for PRUNE_AGE_MS go; a symlink or a non-dir is left alone.
function prune(base, own) {
  try {
    const cutoff = Date.now() - PRUNE_AGE_MS;
    for (const name of fs.readdirSync(base).slice(0, PRUNE_MAX)) {
      const p = path.join(base, name);
      if (p === own) continue;
      const st = fs.lstatSync(p);
      if (!st.isDirectory() || st.isSymbolicLink()) continue;
      if (st.mtimeMs < cutoff) fs.rmSync(p, { recursive: true, force: true });
    }
  } catch {}
}

// lstat: a symlink is never a directory here, whatever it points to.
function realDir(p) {
  try { return fs.lstatSync(p).isDirectory(); } catch { return false; }
}

let input = "";
let overflow = false;
let ran = false;

function main() {
  let data;
  try { data = JSON.parse(input); } catch { allow(); return; }
  if (!data || typeof data !== "object" || Array.isArray(data)) { allow(); return; }
  if (data.tool_name !== undefined && data.tool_name !== "Read") { allow(); return; }
  const ti = data.tool_input;
  if (!ti || typeof ti !== "object" || Array.isArray(ti)) { allow(); return; }
  const fp = ti.file_path;
  if (typeof fp !== "string" || fp === "" || !path.isAbsolute(fp)) { allow(); return; }
  if (present(ti.offset) || present(ti.limit) || present(ti.pages)) { allow(); return; }
  if (ti.allow_large === true) { allow(); return; }
  if (SKIP_EXT.test(fp)) { allow(); return; }

  let size;
  try {
    const st = fs.statSync(fp);
    if (!st.isFile()) { allow(); return; }
    size = st.size;
  } catch { allow(); return; }
  if (size <= THRESHOLD) { allow(); return; }

  const sid = String(data.session_id || "");
  const aid = typeof data.agent_id === "string" ? data.agent_id : "";
  const home = process.env.HOME || os.homedir();
  const base = path.join(home, ".claude", "jev-read-gate");
  const dir = path.join(base, digest(sid + "\0" + aid));
  const marker = path.join(dir, digest(fp));
  const p = safe(fp);
  const kb = Math.round(size / 1024);
  const reason = "jev-read-gate: " + p + " is " + kb + " KB. Locate first: jev-locate \"" + p + "\" \"<question>\" (Bash, allowed_domains [\"api.typesafe.ai\"]), then Read it with offset/limit from the \"lines A-B\" it prints. JEV FULL, an error, or a real need for the whole file (an edit across it, a synthesis): re-issue this exact Read; it passes the second time.";

  // The base is created alone and checked before the key dir: a recursive
  // mkdir through a symlinked base would land the key dir in its target.
  try {
    fs.mkdirSync(base, { recursive: true, mode: 0o700 });
  } catch { allow(); return; }
  if (!realDir(base)) { allow(); return; }
  let created = true;
  try {
    fs.mkdirSync(dir, { mode: 0o700 });
  } catch (e) {
    if (!e || e.code !== "EEXIST") { allow(); return; }
    created = false;
  }
  if (!realDir(dir)) { allow(); return; }
  // Every call keeps its key dir's mtime fresh: a second Read writes no
  // marker, and prune() goes by this mtime, so an active key is never idle.
  const now = new Date();
  try {
    fs.utimesSync(dir, now, now);
  } catch { allow(); return; }
  try {
    fs.writeFileSync(marker, "", { flag: "wx", mode: 0o600 });
  } catch (e) {
    if (e && e.code === "EEXIST") { allow(); return; }
    allow();
    return;
  }
  if (created) prune(base, dir);
  deny(reason);
}

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
