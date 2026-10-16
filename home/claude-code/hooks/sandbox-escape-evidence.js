#!/usr/bin/env node
"use strict";

// A Bash call asking `dangerouslyDisableSandbox: true` leaves the sandbox
// through a permission box. Measured over 14 days, all projects: 2 206 of
// 2 421 such calls (91 %) had no sandbox error before them — the command was
// never tried sandboxed. COMMANDS.md says "retry ONCE after clear sandbox
// evidence"; text alone did not hold. So the flag is denied unless:
//   - the newest Bash result batch (every Bash call of the assistant message
//     that produced the newest Bash result) shows sandbox evidence;
//   - the newest real user prompt asks to leave the sandbox;
//   - one segment of the command is known to fail sandboxed whatever it
//     does (git writes to .git/config, the nix daemon socket, docker…).
//
// A workflow hook, not a barrier: it FAILS OPEN. Unreadable input or
// transcript, no Bash result yet, a throw, the watchdog and an input past
// its cap all allow, silently.

const fs = require("fs");

const BUDGET_MS = 3000;
const MAX_INPUT = 4 * 1024 * 1024;
// Only the transcript's tail is read: the newest batch and prompt sit there.
const MAX_TAIL = 4 * 1024 * 1024;

// Read in the tool_result text only, never in the command or a prompt.
const EVIDENCE = /Operation not permitted|\bEPERM\b|\bEACCES\b|Read-only file system|sandbox_violations|Unable to create .*\.lock|Permission denied|cannot connect to socket|unable to open database file|readonly database|Couldn't load public key|unable to create directory/i;
// The flag's bare name is no ask: "do not use dangerouslyDisableSandbox".
const USER_ASK = /(sans|hors|without|bypass|outside|disable)\W+(?:the\s+|le\s+|du\s+)?sandbox/i;
// Harness envelopes written with the user role: not a request.
const ENVELOPE = /^\s*<(bash-(input|stdout|stderr)|task-notification|command-name|local-command-|system-reminder)/;

// Commands that fail sandboxed by construction: git writes .git/config
// (denyWrite in every repo), nix needs the daemon socket, docker its socket,
// the browser rungs Mach IPC, the probes `git init` fixtures. sandbox-exec
// cannot nest in Claude's Seatbelt (sandbox_apply: Operation not permitted);
// apex-verify-external times out sandboxed with no EPERM text.
// curl --noproxy bypasses the sandbox proxy: the direct connection is
// refused and curl -s prints only 000.
const ALLOW = [
  /^nix\s+(?:flake\s+check|build|eval)\b/,
  /^git(?:\s+-C\s+\S+)?\s+branch\b.*\s(?:-[dDmMu]|--delete|--move|--set-upstream-to)(?=[\s=]|$)/,
  /^git(?:\s+-C\s+\S+)?\s+(?:checkout\s+-[bB]|switch\s+-[cC])\s+\S+\s+\S/,
  /^git(?:\s+-C\s+\S+)?\s+(?:remote|init|clone)\b/,
  /^git(?:\s+-C\s+\S+)?\s+config\s+--local\b/,
  /^docker\b/,
  /^darwin-rebuild\s+build\b/,
  /^scrapling\s+extract\s+(?:fetch|stealthy-fetch)\b/,
  /^(?:bash\s+)?(?:\.\/)?checks\/[\w-]+-(?:probe|bench)\.sh\b/,
  /^sandbox-exec\b/,
  /^curl\b(?=.*\s--noproxy(?:[\s=]|$))/,
  /^apex-verify-external\b/
];

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

// Segments cut on && || ; | and newline outside quotes: a false segment
// adds an allow, so `echo 'x; docker'` must stay one segment. Quotes and
// escapes are scanned as lone-excluded-bash.js's lexer reads them ('…',
// $'…', "…" with backslash, a bare backslash); an unbalanced quote runs to
// the end, which only removes cuts. Segments keep their raw text.
function segments(cmd) {
  const out = [];
  const n = cmd.length;
  let start = 0;
  let i = 0;
  const cut = (len) => {
    out.push(cmd.slice(start, i));
    i += len;
    start = i;
  };
  while (i < n) {
    const ch = cmd[i];
    if (ch === "\\") { i += 2; continue; }
    if (ch === "'") {
      const e = cmd.indexOf("'", i + 1);
      i = e < 0 ? n : e + 1;
      continue;
    }
    if (ch === "$" && cmd[i + 1] === "'") {
      let j = i + 2;
      while (j < n && cmd[j] !== "'") j += cmd[j] === "\\" ? 2 : 1;
      i = j + 1;
      continue;
    }
    if (ch === '"') {
      let j = i + 1;
      while (j < n && cmd[j] !== '"') j += cmd[j] === "\\" ? 2 : 1;
      i = j + 1;
      continue;
    }
    if (cmd.startsWith("&&", i) || cmd.startsWith("||", i)) { cut(2); continue; }
    if (ch === ";" || ch === "|" || ch === "\n") { cut(1); continue; }
    i++;
  }
  out.push(cmd.slice(start));
  return out;
}

function allowlisted(cmd) {
  return segments(cmd).some((s) => ALLOW.some((re) => re.test(s.trim())));
}

// The last MAX_TAIL bytes, split in lines; a line cut by the window is dropped.
function tailLines(p) {
  const fd = fs.openSync(p, "r");
  try {
    const size = fs.fstatSync(fd).size;
    const len = Math.min(size, MAX_TAIL);
    const buf = Buffer.alloc(len);
    let got = 0;
    while (got < len) {
      const n = fs.readSync(fd, buf, got, len - got, size - len + got);
      if (n <= 0) break;
      got += n;
    }
    const lines = buf.toString("utf8", 0, got).split("\n");
    if (len < size) lines.shift();
    return lines;
  } finally {
    fs.closeSync(fd);
  }
}

function textOf(c) {
  if (typeof c === "string") return c;
  if (!Array.isArray(c)) return "";
  return c.filter((b) => b && b.type === "text").map((b) => String(b.text || "")).join("\n");
}

function parse(line) {
  try { return JSON.parse(line); } catch { return null; }
}

// Bash results in transcript order, each with the assistant message id that
// issued it. The current call's own id never counts.
function bashResults(lines, current) {
  const uses = new Map();
  const results = [];
  for (const line of lines) {
    if (line.indexOf("\"tool_use\"") === -1 && line.indexOf("\"tool_result\"") === -1) continue;
    const msg = parse(line);
    const c = msg && msg.message && msg.message.content;
    if (!Array.isArray(c)) continue;
    for (const b of c) {
      if (!b || typeof b !== "object") continue;
      if (msg.type === "assistant" && b.type === "tool_use") uses.set(b.id, { name: b.name, mid: msg.message.id });
      if (msg.type === "user" && b.type === "tool_result") {
        const u = uses.get(b.tool_use_id);
        if (!u || u.name !== "Bash" || b.tool_use_id === current) continue;
        results.push({ mid: u.mid, text: textOf(b.content) });
      }
    }
  }
  return results;
}

// The newest prompt the user typed. Tool results, isMeta lines (skill
// bodies, injected context) and harness envelopes are skipped; a sidechain
// prompt is a coordinator's brief, not the user, and ends the walk.
function userPrompt(lines) {
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i];
    if (line.indexOf("\"type\":\"user\"") === -1) continue;
    const msg = parse(line);
    if (!msg || msg.type !== "user") continue;
    if (msg.isMeta === true) continue;
    const c = msg.message && msg.message.content;
    if (Array.isArray(c) && c.some((b) => b && b.type === "tool_result")) continue;
    const text = textOf(c);
    if (ENVELOPE.test(text)) continue;
    if (msg.isSidechain === true) return "";
    return text;
  }
  return "";
}

let input = "";
let overflow = false;
let ran = false;

function main() {
  let data;
  try { data = JSON.parse(input); } catch { allow(); return; }
  if (!data || typeof data !== "object" || Array.isArray(data)) { allow(); return; }
  if (data.tool_name !== "Bash") { allow(); return; }
  const ti = data.tool_input;
  if (!ti || typeof ti !== "object" || ti.dangerouslyDisableSandbox !== true) { allow(); return; }
  if (typeof ti.command === "string" && allowlisted(ti.command)) { allow(); return; }
  if (typeof data.transcript_path !== "string") { allow(); return; }
  let lines;
  try { lines = tailLines(data.transcript_path); } catch { allow(); return; }
  const results = bashResults(lines, data.tool_use_id);
  const newest = results[results.length - 1];
  if (newest === undefined) { allow(); return; }
  const texts = results.filter((r) => r.mid === newest.mid).map((r) => r.text);
  if (texts.some((t) => EVIDENCE.test(t))) { allow(); return; }
  if (USER_ASK.test(userPrompt(lines))) { allow(); return; }
  deny("BLOCKED: Run this command sandboxed first, without dangerouslyDisableSandbox. The newest Bash result shows no sandbox evidence (Operation not permitted, EPERM, Read-only file system, sandbox_violations, a refused socket) and the user did not ask to leave the sandbox. If the sandboxed run fails with such an error, the retry with dangerouslyDisableSandbox: true passes. Phase agents do not escalate: report the command to the coordinator.");
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
