#!/usr/bin/env node
// UserPromptSubmit, Stop, Notification, SessionStart and SessionEnd: the state
// of a dispatched session, for the readers of PR 4 (apex-board's Agents tab,
// the deck). Since #299 a dispatched session runs under abduco with Claude's
// daemon off, so ~/.claude/jobs is no longer written; this file replaces it.
//
// Acts only inside an abduco session: abduco puts ABDUCO_SESSION=<name> in the
// session's environment and hooks inherit it. Any other session, or a name
// outside claude-dispatch's rule, is a no-op.
//
// Writes ~/.claude/session-state/<name>.json (dir 0700, file 0600) through a
// temp file in the same dir and a rename, so a reader never sees half a file:
//   { name, state, event, updatedAt, cwd, sessionId, transcriptPath, intent, notice }
// state: SessionStart idle (compact keeps the state it had), UserPromptSubmit
// working, Stop waiting, Notification needs-you, SessionEnd done.
// intent: the session's first prompt, one line, <= 500 chars, kept until the
// session id changes. notice: the last Notification message, one line,
// <= 300 chars, cleared by the next prompt.
//
// Never follows a symlink: a state dir or state file that is one is left
// alone and nothing is written.
// FAIL-OPEN, workflow hook: exit 0 on every path, nothing on stdout ever
// (UserPromptSubmit and SessionStart stdout would land in the model's
// context), no temp file left; one stderr line on an unexpected error only.
"use strict";
const fs = require("fs");
const path = require("path");

const BUDGET_MS = 3000;
const MAX_INPUT = 4 * 1024 * 1024;
const MAX_STATE = 64 * 1024;
const NAME_RE = /^[a-z0-9][a-z0-9-]{0,47}$/;
const STATES = {
  SessionStart: "idle",
  UserPromptSubmit: "working",
  Stop: "waiting",
  Notification: "needs-you",
  SessionEnd: "done",
};
const C = fs.constants;

function quit() { process.exit(0); }

function str(v) { return typeof v === "string" ? v : ""; }

// One line, no control characters, at most `max` code points. `\s` covers
// the Unicode line and paragraph separators.
function oneLine(v, max) {
  const bare = Array.from(str(v), ch => {
    const c = ch.charCodeAt(0);
    return c < 0x20 || c === 0x7f ? " " : ch;
  }).join("");
  const s = bare.replace(/\s+/g, " ").trim();
  const cps = Array.from(s);
  return cps.length > max ? cps.slice(0, max).join("") : s;
}

// The state file as it stands, or null when absent or unreadable as JSON.
// Throws "symlink" when it is not a regular file: the caller refuses.
function readPrevious(file) {
  let fd;
  try {
    fd = fs.openSync(file, C.O_RDONLY | C.O_NOFOLLOW);
  } catch (e) {
    if (e && e.code === "ENOENT") return null;
    if (e && e.code === "ELOOP") throw new Error("symlink", { cause: e });
    throw e;
  }
  try {
    const st = fs.fstatSync(fd);
    if (!st.isFile()) throw new Error("symlink");
    if (st.size > MAX_STATE) return null;
    const buf = Buffer.alloc(st.size);
    let off = 0;
    while (off < st.size) {
      const n = fs.readSync(fd, buf, off, st.size - off, off);
      if (n === 0) break;
      off += n;
    }
    const prev = JSON.parse(buf.toString("utf8", 0, off));
    return prev && typeof prev === "object" && !Array.isArray(prev) ? prev : null;
  } catch (e) {
    if (e && e.message === "symlink") throw e;
    return null;
  } finally {
    fs.closeSync(fd);
  }
}

function main(input) {
  const name = String(process.env.ABDUCO_SESSION || "");
  if (!NAME_RE.test(name)) return;

  let data;
  try { data = JSON.parse(input); } catch { return; }
  if (!data || typeof data !== "object" || Array.isArray(data)) return;
  const event = str(data.hook_event_name);
  if (!Object.prototype.hasOwnProperty.call(STATES, event)) return;

  const home = process.env.HOME;
  if (!home || !path.isAbsolute(home)) return;
  const dir = path.join(home, ".claude", "session-state");
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const dst = fs.lstatSync(dir);
  if (!dst.isDirectory() || dst.uid !== process.getuid()) return;

  const file = path.join(dir, name + ".json");
  let prev;
  try { prev = readPrevious(file); } catch (e) {
    if (e && e.message === "symlink") return;
    throw e;
  }
  const sessionId = str(data.session_id);
  if (prev && str(prev.sessionId) !== sessionId) prev = null;

  let state = STATES[event];
  if (event === "SessionStart" && data.source === "compact" && prev && str(prev.state)) state = str(prev.state);

  let intent = prev ? str(prev.intent) : "";
  if (event === "UserPromptSubmit" && intent === "") intent = oneLine(data.prompt, 500);
  let notice = prev ? str(prev.notice) : "";
  if (event === "UserPromptSubmit") notice = "";
  if (event === "Notification") notice = oneLine(data.message, 300);

  const body = JSON.stringify({
    name,
    state,
    event,
    updatedAt: new Date().toISOString(),
    cwd: str(data.cwd),
    sessionId,
    transcriptPath: str(data.transcript_path),
    intent,
    notice,
  }) + "\n";

  const tmp = path.join(dir, "." + name + ".json." + process.pid + "." + Date.now() + ".tmp");
  let fd = null;
  try {
    fd = fs.openSync(tmp, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o600);
    fs.writeFileSync(fd, body);
    fs.closeSync(fd);
    fd = null;
    fs.renameSync(tmp, file);
  } catch (e) {
    if (fd !== null) { try { fs.closeSync(fd); } catch {} }
    try { fs.unlinkSync(tmp); } catch {}
    throw e;
  }
}

let input = "";
let overflow = false;
process.stdin.setEncoding("utf8");
setTimeout(quit, BUDGET_MS);
process.stdin.on("data", c => {
  if (overflow) return;
  input += c;
  if (input.length > MAX_INPUT) { overflow = true; quit(); }
});
process.stdin.on("error", quit);
process.stdin.on("end", () => {
  try { main(input); } catch (e) {
    // Synchronous: process.exit() can drop an async pipe write.
    try { fs.writeSync(2, "session-state: " + String(e && e.code || e && e.message || e).slice(0, 200) + "\n"); } catch {}
  }
  quit();
});
