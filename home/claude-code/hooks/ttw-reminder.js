#!/usr/bin/env node
"use strict";
const fs = require("fs");

const BUDGET_MS = 2000;
const MAX_INPUT = 4 * 1024 * 1024;
const LINE = "file change → /ttw (tier table: SKILL.md); question → answer directly.\n";
// Harness envelopes: a subagent hand-back, a peer or cross-session message,
// a task notification. Matched at the very start only, so a human prompt
// quoting one still gets the reminder.
const ENVELOPES = ["<agent-message", "Another Claude session sent a message", "<cross-session-message", "<task-notification"];

let settled = false;

// process.exit() truncates a pending async pipe write: write synchronously,
// retry, never throw.
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

function remind() {
  if (settled) return;
  settled = true;
  writeAll(1, LINE);
  process.exit(0);
}

function quiet() {
  if (settled) return;
  settled = true;
  process.exit(0);
}

let input = "";
let chunks = [];
let size = 0;
let overflow = false;
let ran = false;

function main() {
  let data;
  try { data = JSON.parse(input); } catch { remind(); return; }
  const p = data && typeof data.prompt === "string" ? data.prompt.replace(/^\s+/, "") : "";
  if (ENVELOPES.some((e) => p.startsWith(e))) { quiet(); return; }
  remind();
}

// Fail-open: every doubtful path prints the reminder; never exit 2 (it would block
// the prompt).
function start() {
  if (ran) return;
  ran = true;
  if (overflow) { remind(); return; }
  try {
    input = Buffer.concat(chunks).toString("utf8");
    main();
  } catch {
    remind();
  }
}

process.on("uncaughtException", () => {
  remind();
});

const watchdog = setTimeout(() => {
  remind();
}, BUDGET_MS);
if (typeof watchdog.unref === "function") watchdog.unref();

// No setEncoding: chunks stay Buffers, so MAX_INPUT counts bytes, not
// UTF-16 code units.
process.stdin.on("data", (chunk) => {
  if (overflow) return;
  size += chunk.length;
  if (size > MAX_INPUT) { overflow = true; chunks = []; return; }
  chunks.push(chunk);
});
process.stdin.on("end", start);
process.stdin.on("error", start);
