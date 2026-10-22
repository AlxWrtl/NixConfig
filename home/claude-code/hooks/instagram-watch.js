#!/usr/bin/env node
"use strict";
const fs = require("fs");

const BUDGET_MS = 3000;
const MAX_INPUT = 4 * 1024 * 1024;
const WRAPPERS = ["<task-notification", "<agent-message", "Another Claude session sent a message", "[SYSTEM NOTIFICATION", "<teammate-message", "<command-name>", "<local-command", "<scheduled-task", "<system-reminder"];
const MAX_URLS = 3;
// A post, reel or IGTV link, optionally under a username; never a profile page.
const IG_URL = /(?:^|[^A-Za-z0-9.@-])((?:https?:\/\/)?(?:(?:www|m)\.)?instagram\.com\/(?:[A-Za-z0-9._]{1,30}\/)?(?:p|reels?|tv)\/[A-Za-z0-9_-]+)/gi;

let settled = false;

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

let input = "";
let overflow = false;
let ran = false;

function main() {
  let data;
  try { data = JSON.parse(input); } catch { quiet(); return; }
  if (!data || typeof data !== "object" || Array.isArray(data)) { quiet(); return; }
  // Only the user's own prompt asks: a subagent's input never does, and an
  // agent_id of any value is doubt enough.
  if (Object.prototype.hasOwnProperty.call(data, "agent_id") && data.agent_id !== undefined) { quiet(); return; }
  if (typeof data.prompt !== "string") { quiet(); return; }
  // Task notifications and agent hand-backs reach this event as user turns
  // without agent_id: text the model wrote, wrapped by the harness.
  if (WRAPPERS.some((w) => data.prompt.includes(w))) { quiet(); return; }
  // The match ends with the shortcode, so a query string (igsh, utm_*) is dropped.
  const urls = [];
  for (const m of data.prompt.matchAll(IG_URL)) {
    const u = (/^https?:\/\//i.test(m[1]) ? m[1] : "https://" + m[1]) + "/";
    if (!urls.includes(u)) urls.push(u);
    if (urls.length === MAX_URLS) break;
  }
  if (urls.length === 0) { quiet(); return; }
  say("instagram-watch: the prompt contains Instagram video link(s): " + urls.join(" ") + ". This user wants the `watch` skill run on every Instagram link they paste, before any answer, unless the prompt says not to: one run per link with `--engine local`, their question (if any) passed as `--question`. The answer then rests on the frames and transcript it returns.");
}

// Fail-open: a broken hook asks for nothing and stops no prompt (exit 2
// would block it).
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
