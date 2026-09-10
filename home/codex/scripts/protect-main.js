#!/usr/bin/env node
"use strict";
//
// Codex PreToolUse hook — branch protection. SECURITY: it FAILS CLOSED.
//
// Ported from home/claude-code/hooks.nix:hookProtectMain. The LOGIC is the
// same; the output contract is not, and neither is the failure doctrine.
//
// WHAT CHANGED FROM THE CLAUDE VERSION, AND WHY
//
//   The Claude original exits 0 on every degraded path: unreadable stdin, no
//   file_path, git absent, git broken. On that host a hook that exits 0 with
//   no JSON is simply "no opinion", and Claude Code's own permission system
//   still stands behind it. Here it is the only gate, and Codex treats every
//   non-zero exit other than 2 as "did not block" — a hook that crashes
//   therefore GRANTS the edit. So on a protected branch this hook denies
//   unless it can PROVE the target lies outside the worktree.
//
//   Allowing is only ever done from positive knowledge:
//     - git says this is not a work tree      -> nothing to protect
//     - git says the branch is not protected  -> nothing to protect
//     - the resolved target is outside the resolved worktree
//   Everything else denies.
//
// THE WATCHDOG IS LOAD-BEARING
//
//   The hook is registered with `timeout: 5`. A process the host kills exits
//   with a signal-derived code that is not 2, i.e. its death grants
//   permission. So the hook refuses ITSELF before the host can kill it. Two
//   mechanisms, because one is not enough:
//
//     1. An unref'd timer at BUDGET_MS. It covers ASYNC hangs (stdin that
//        never closes) and nothing else.
//     2. A wall-clock deadline shared by every git call. A JS timer cannot
//        fire while a synchronous child_process call is blocked, so the timer
//        alone would sleep through the case that matters — a hanging `git`.
//        Each call gets `timeout: min(GIT_MS, DEADLINE - now)`, so the total
//        synchronous time is bounded by BUDGET_MS no matter how many calls
//        run.
//
// STDOUT HYGIENE
//
//   Codex parses any non-empty stdout as JSON. A Stop hook here once wrote an
//   ANSI escape and Codex reported `hook returned invalid stop hook JSON
//   output`. NOTHING but the single sanctioned object may reach fd 1: no
//   console.log, no progress, no trailing junk. Writes go through fs.writeSync
//   rather than process.stdout.write because process.exit() truncates pending
//   asynchronous pipe writes, which would drop the deny payload itself.
//
// Invoked as: /run/current-system/sw/bin/node <this file>

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const PROTECTED = ["main", "master"];
const BUDGET_MS = 3000; // self-deny deadline; the host kills at 5000
const GIT_MS = 1500; // ceiling for any single git call
const DEADLINE = Date.now() + BUDGET_MS;

// Addressed to the HUMAN, not to the model. Codex mounts .git read-only under
// workspace-write by design — a writable .git/hooks would let an agent plant a
// hook that runs outside the sandbox the next time a human runs git — and there
// is no toggle for it. Measured 2026-09-10: `git checkout -b fix/x` inside a
// Codex session fails with "cannot lock ref … unable to create directory". So
// telling the model to cut the branch asks it for something it cannot do, and
// it loops asking for permission instead.
const CUT =
  "Ask the human to cut a branch (git checkout -b <type>/<desc>, e.g. feat/auth-redirect) and to say when it is done. " +
  "You cannot create it yourself: .git is read-only in this sandbox.";

let settled = false;
let branchSeen = null;

// --- output -----------------------------------------------------------------

// Synchronous, retrying, and it never throws. fd 1 may be a non-blocking pipe.
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

// Branch names cannot legally carry ASCII control characters, but the value is
// interpolated into a message that reaches a terminal, so it is scrubbed
// anyway. Nothing derived from git output is ever echoed verbatim.
function safe(s) {
  return String(s === undefined || s === null ? "" : s).replace(
    /[^\x20-\x7e]/g,
    "?",
  );
}

function deny(reason) {
  if (settled) return;
  settled = true;
  writeAll(2, reason + "\n");
  writeAll(
    1,
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason,
      },
    }),
  );
  process.exit(2);
}

function allow() {
  if (settled) return;
  settled = true;
  process.exit(0);
}

// On a protected branch and unable to prove the edit is harmless. Before the
// branch is known there is nothing to name, so it degrades to the other form.
function denyOnBranch(why) {
  if (branchSeen === null) {
    denyUnverifiable(why);
    return;
  }
  deny(
    "BLOCKED: on " +
      safe(branchSeen) +
      " and " +
      why +
      ", so this edit cannot be shown to be safe. " +
      CUT,
  );
}

// The branch itself could not be established. Refusing beats assuming.
function denyUnverifiable(why) {
  deny(
    "BLOCKED: cannot verify the current branch (" +
      why +
      "), so main/master cannot be ruled out. " +
      CUT,
  );
}

// --- git --------------------------------------------------------------------

// spawnSync, not execSync: same synchronous engine, no shell, so a path or a
// branch name can never be reinterpreted as shell syntax and a missing binary
// surfaces as ENOENT instead of a shell's exit 127.
function git(args) {
  const left = DEADLINE - Date.now();
  return spawnSync("git", args, {
    encoding: "utf8",
    timeout: Math.max(200, Math.min(GIT_MS, left)),
    killSignal: "SIGKILL",
    stdio: ["ignore", "pipe", "pipe"],
    maxBuffer: 1024 * 1024,
    windowsHide: true,
  });
}

// null when git ran and answered; a short human phrase when it did not.
function gitBroken(r) {
  if (!r) return "git did not run";
  if (r.error) {
    if (r.error.code === "ENOENT") return "git is not on PATH";
    if (r.error.code === "ETIMEDOUT") return "git did not answer in time";
    return "git could not be executed";
  }
  if (r.signal) return "git was killed";
  return null;
}

// --- paths ------------------------------------------------------------------

// realpath that tolerates a target which does not exist yet — Write creates
// new files, and a plain realpathSync throws on those. Resolves the deepest
// existing ancestor and re-attaches the rest, so a symlinked parent directory
// still gives away a target that really lands inside the worktree.
function realpathish(p) {
  const abs = path.resolve(p);
  let cur = abs;
  const tail = [];
  for (let i = 0; i < 64; i++) {
    try {
      const real = fs.realpathSync(cur);
      if (tail.length === 0) return real;
      return path.join(real, tail.reverse().join(path.sep));
    } catch {
      /* keep walking up */
    }
    const parent = path.dirname(cur);
    if (parent === cur) return abs;
    tail.push(path.basename(cur));
    cur = parent;
  }
  return abs;
}

function firstPath(obj) {
  if (!obj || typeof obj !== "object") return null;
  const keys = ["file_path", "path", "filePath", "notebook_path"];
  for (const k of keys) {
    const v = obj[k];
    if (typeof v === "string" && v.trim() !== "") return v;
  }
  return null;
}

// --- main -------------------------------------------------------------------

let input = "";
let ran = false;

function main() {
  // 1. Is there a worktree at all, and can git answer?
  const probe = git(["rev-parse", "--is-inside-work-tree"]);
  const probeBroken = gitBroken(probe);
  if (probeBroken) denyUnverifiable(probeBroken);
  if (probe.status !== 0) {
    // The ONE benign failure: there is no repository here, so there is no
    // branch to protect. Every other git failure is treated as unverifiable.
    if (/not a git repository/i.test(String(probe.stderr || ""))) allow();
    denyUnverifiable("git rev-parse failed");
  }
  // "false" means a bare repo or the inside of a .git directory: no worktree,
  // nothing a file path can be inside of.
  if (String(probe.stdout || "").trim() !== "true") allow();

  // 2. Which branch?
  const br = git(["branch", "--show-current"]);
  const brBroken = gitBroken(br);
  if (brBroken) denyUnverifiable(brBroken);
  if (br.status !== 0) denyUnverifiable("git branch --show-current failed");
  const branch = String(br.stdout || "").trim();
  branchSeen = branch;
  // Detached HEAD prints nothing and is not a protected branch.
  if (PROTECTED.indexOf(branch) === -1) allow();

  // 3. From here, every path leads to a deny except a proven escape.
  let data;
  try {
    data = JSON.parse(input);
  } catch {
    denyOnBranch("the hook input was not valid JSON");
    return;
  }
  if (!data || typeof data !== "object") {
    denyOnBranch("the hook input was not an object");
    return;
  }

  // The exact field name is the vendor's, not ours: read the plausible
  // aliases rather than betting on one (plan R4).
  const raw = firstPath(data.tool_input) || firstPath(data);
  if (!raw) {
    denyOnBranch("the hook input carries no file path field");
    return;
  }

  const top = git(["rev-parse", "--show-toplevel"]);
  const topBroken = gitBroken(top);
  if (topBroken) {
    denyOnBranch(topBroken);
    return;
  }
  if (top.status !== 0) {
    denyOnBranch("the worktree root could not be located");
    return;
  }
  const realTop = realpathish(String(top.stdout || "").trim());
  const realTarget = realpathish(raw);

  // The only allow left: the target is PROVABLY somewhere else.
  if (realTarget !== realTop && !realTarget.startsWith(realTop + path.sep)) {
    allow();
  }

  deny("BLOCKED: on " + safe(branch) + ". " + CUT);
}

function start() {
  if (ran) return;
  ran = true;
  try {
    main();
  } catch (e) {
    // An uncaught throw must never become permission. If the branch was
    // already established as unprotected, main() has exited long before here.
    denyOnBranch("the hook itself failed (" + safe(e && e.message) + ")");
  }
  // Unreachable: main() always exits. Belt and braces.
  denyOnBranch("the hook reached no decision");
}

process.on("uncaughtException", (e) => {
  if (settled) return;
  deny(
    "BLOCKED: the branch-protection hook crashed (" +
      safe(e && e.message) +
      "), so the branch could not be checked. " +
      CUT,
  );
});

// Covers the async hang only — see the header. A sync git hang is bounded by
// DEADLINE instead, because no timer can fire while spawnSync blocks.
const watchdog = setTimeout(() => {
  deny(
    "BLOCKED: the branch-protection hook hit its own " +
      BUDGET_MS +
      " ms deadline before it could read its input. " +
      CUT,
  );
}, BUDGET_MS);
if (typeof watchdog.unref === "function") watchdog.unref();

process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => {
  if (input.length < 4 * 1024 * 1024) input += c;
});
process.stdin.on("end", start);
process.stdin.on("error", start);
