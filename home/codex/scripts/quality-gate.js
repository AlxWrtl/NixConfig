#!/usr/bin/env node
"use strict";
//
// Codex Stop hook — quality gate. WORKFLOW: it FAILS OPEN.
//
// Ported from home/claude-code/hooks.nix:hookQualityGate. It is the doctrinal
// mirror of protect-main.js in this same directory: that one is a security
// gate and refuses when it cannot decide, this one is a workflow nudge and
// gets out of the way when it cannot decide. A quality reminder that can
// wedge a session is worse than no quality reminder.
//
// Every failure — unreadable stdin, no repo, no diff, an unreadable file, a
// broken git — exits 0 with empty stdout.
//
// TWO CHANGES FROM THE CLAUDE VERSION
//
//   1. It chdir's to the `cwd` field on stdin before calling git. The Claude
//      version trusts the process working directory, which is whatever the
//      host happened to launch the hook in.
//   2. It honours `stop_hook_active`. Blocking a Stop restarts the model; if
//      the model stops again with the violations still present, blocking a
//      second time is a loop, so the second pass steps aside.
//
// STDOUT HYGIENE. Codex parses any non-empty stdout as JSON, and an ANSI
// escape written by another hook is the live bug this module exists to fix.
// Only the single sanctioned object may ever reach fd 1, written synchronously
// so process.exit() cannot truncate it.
//
// Invoked as: /run/current-system/sw/bin/node <this file>

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const GIT_MS = 3000;
const MAX_REPORTED = 10;

// Blocking anti-patterns only. TODO/HACK/FIXME are legitimate work markers and
// must not block a Stop. Deliberately NOT global: a /g regex carries lastIndex
// across .test() calls, which made the original skip every other match.
const PATTERNS = [
  { re: /console\.log\(/, msg: "console.log in production code" },
  { re: /:\s*any\b/, msg: "TypeScript 'any' type" },
  { re: /\balert\s*\(/, msg: "alert() call" },
  { re: /\bconfirm\s*\(/, msg: "confirm() call" },
];

function writeAll(fd, text) {
  let buf;
  try {
    buf = Buffer.from(String(text), "utf8");
  } catch {
    return;
  }
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

function git(args) {
  return spawnSync("git", args, {
    encoding: "utf8",
    timeout: GIT_MS,
    killSignal: "SIGKILL",
    stdio: ["ignore", "pipe", "pipe"],
    maxBuffer: 8 * 1024 * 1024,
    windowsHide: true,
  });
}

function ok(r) {
  return r && !r.error && !r.signal && r.status === 0;
}

let input = "";
let ran = false;

function main() {
  const data = JSON.parse(input); // malformed -> throw -> exit 0
  if (!data || typeof data !== "object") return;

  // Loop guard. Codex re-runs the Stop hook after a block; a second block on
  // the same turn would spin the session.
  if (data.stop_hook_active) return;

  // Improvement 1: the repository is the one the session says it is in.
  if (typeof data.cwd === "string" && data.cwd !== "") {
    process.chdir(data.cwd); // failure -> throw -> exit 0
  }

  const diff = git(["diff", "--name-only", "HEAD"]);
  if (!ok(diff)) return; // no repo, no HEAD, broken git: not our business
  const names = String(diff.stdout || "")
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean);
  if (names.length === 0) return;

  // git prints names relative to the worktree root, which is not necessarily
  // the directory we were told to work in.
  const top = git(["rev-parse", "--show-toplevel"]);
  if (!ok(top)) return;
  const root = String(top.stdout || "").trim();
  if (!root) return;

  const files = names
    .filter((f) => /\.(ts|tsx|js|jsx)$/.test(f))
    // CLI scripts legitimately use console.log — progress output and
    // machine-readable results that harnesses parse. ESLint already ignores
    // scripts/**; the gate stays consistent with it.
    .filter((f) => !/(^|\/)scripts\//.test(f))
    // Generated declaration files carry vendor console.log and `any`.
    .filter((f) => !/\.d\.ts$/.test(f));
  if (files.length === 0) return;

  const issues = [];
  for (const file of files) {
    let lines;
    try {
      lines = fs.readFileSync(path.join(root, file), "utf8").split("\n");
    } catch {
      continue; // deleted, binary, unreadable — skip the file, not the run
    }
    for (let i = 0; i < lines.length; i++) {
      for (const p of PATTERNS) {
        if (p.re.test(lines[i]))
          issues.push(file + ":" + (i + 1) + " — " + p.msg);
      }
    }
    if (issues.length >= MAX_REPORTED * 4) break;
  }
  if (issues.length === 0) return;

  const reason =
    "QUALITY GATE — " +
    issues.length +
    " issue(s) in changed files:\n" +
    issues.slice(0, MAX_REPORTED).join("\n");

  // Both documented channels: the reason on stderr, and the one sanctioned
  // JSON object on stdout. Exit 2 is what makes Codex block.
  writeAll(2, reason + "\n");
  writeAll(1, JSON.stringify({ decision: "block", reason: reason }));
  process.exit(2);
}

function start() {
  if (ran) return;
  ran = true;
  try {
    main();
  } catch {
    /* fail open, by design */
  }
  process.exit(0);
}

// A workflow hook that hangs is a workflow hook that blocks the session, so it
// gives up on its own rather than waiting for the host to kill it.
const watchdog = setTimeout(() => {
  process.exit(0);
}, 4000);
if (typeof watchdog.unref === "function") watchdog.unref();

process.on("uncaughtException", () => {
  process.exit(0);
});

process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => {
  if (input.length < 4 * 1024 * 1024) input += c;
});
process.stdin.on("end", start);
process.stdin.on("error", start);
