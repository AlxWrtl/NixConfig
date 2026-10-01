#!/usr/bin/env node
"use strict";
// Edit|Write guard for main/master. It FAILS CLOSED (run 57): the old
// version exited 0 on every degraded path (unreadable stdin, no file_path,
// git absent, broken or hung), and exit 0 with no JSON lets the edit
// through. Skeleton ported from home/codex/scripts/protect-main.js; the
// output keeps the Claude form: deny = ONE JSON object written
// synchronously to fd 1, exit 0, nothing on stderr; allow = exit 0, no
// output. Allowing needs positive knowledge about the repository the FILE
// belongs to (run 61): the cwd alone let a feature or non-repo cwd edit a
// file in another repo sitting on master. The file's repo is read from its
// nearest existing directory; it allows when that is no repo, a branch
// that is not protected (detached counts as not), or the vault.
//
// Two time bounds, because a JS timer cannot fire while spawnSync blocks:
// an unref'd watchdog for a stdin that never closes, and a wall-clock
// DEADLINE shared by every git call. Both sit under the host's 5 s hook
// timeout, whose expiry would NOT block the tool.
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const PROTECTED = ["main", "master"];
const BUDGET_MS = 3000;
const GIT_MS = 1500;
const DEADLINE = Date.now() + BUDGET_MS;
const CUT = "Run: git checkout -b <type>/<desc> (e.g. feat/auth-redirect, fix/nav-crash) then retry.";
// The one repo exempt from this guard: the vault is a local-only safety
// net with no PR flow. Exempt by PATH (user decision 2026-09-30); a repo
// without a remote is no longer exempt for that alone.
const VAULT = "@alxVaultPath@";

let settled = false;
let branchSeen = null;

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

function denyUnverifiable(why) {
  deny("BLOCKED: cannot verify the current branch (" + why + "), so main/master cannot be ruled out. " + CUT);
}

function denyOnBranch(why) {
  if (branchSeen === null) { denyUnverifiable(why); return; }
  deny("BLOCKED: on " + safe(branchSeen) + " and " + why + ", so this edit cannot be shown to be safe. " + CUT);
}

// spawnSync, no shell: a path can never be read as shell syntax, and a
// missing binary is ENOENT. LC_ALL=C pins the "not a git repository" text
// that the one benign failure is recognised by.
function git(args, cwd) {
  const left = DEADLINE - Date.now();
  // Budget spent: no spawn, a timeout. A 200 ms floor used to run git past
  // DEADLINE, and a sync spawn keeps the watchdog from firing meanwhile.
  if (left <= 0) return { error: { code: "ETIMEDOUT" }, status: null, signal: null, stdout: "", stderr: "" };
  const opts = {
    encoding: "utf8",
    timeout: Math.min(GIT_MS, left),
    killSignal: "SIGKILL",
    stdio: ["ignore", "pipe", "pipe"],
    maxBuffer: 1024 * 1024,
    windowsHide: true,
    env: Object.assign({}, process.env, { LC_ALL: "C" })
  };
  if (cwd) opts.cwd = cwd;
  return spawnSync("git", args, opts);
}

// null when git ran and answered; a short phrase when it did not.
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

// realpath of a target that may not exist yet (Write creates files):
// resolve the deepest existing ancestor, re-attach the rest. A plain
// realpathSync throws on a new file, and the old fallback compared an
// unresolved symlinked path with a resolved toplevel -> allowed.
// `.native` is realpath(3), which returns the on-disk case: the JS
// realpathSync keeps the case it was given, and APFS is case-insensitive,
// so `MASTER/a.ts` read as outside `master` and was allowed.
function realpathish(p) {
  const abs = path.resolve(p);
  let cur = abs;
  const tail = [];
  for (let i = 0; i < 64; i++) {
    try {
      const real = fs.realpathSync.native(cur);
      if (tail.length === 0) return real;
      return path.join(real, tail.reverse().join(path.sep));
    } catch (e) {
      // Walk up ONLY past an entry that is not there. One that exists but
      // does not resolve (a dangling symlink: realpath says ENOENT, lstat
      // finds the link) cannot be placed, and neither can any other error.
      if (!e || e.code !== "ENOENT") return null;
      let entry = null;
      try { entry = fs.lstatSync(cur); } catch (le) { if (!le || le.code !== "ENOENT") return null; }
      if (entry) return null;
    }
    const parent = path.dirname(cur);
    // The root is its own realpath: re-attach the tail to it.
    if (parent === cur) return path.join(cur, tail.reverse().join(path.sep));
    tail.push(path.basename(cur));
    cur = parent;
  }
  // 64 levels still unresolved: the location cannot be proven. The raw
  // path could read as outside the worktree and allow; null denies.
  return null;
}

// The deepest EXISTING directory on the target's path: a Write creates
// its file, so the file itself may not be there to ask git about.
function nearestDir(p) {
  let cur = p;
  for (let i = 0; i < 64; i++) {
    try {
      if (fs.statSync(cur).isDirectory()) return cur;
    } catch (e) {
      if (!e || (e.code !== "ENOENT" && e.code !== "ENOTDIR")) return null;
    }
    const parent = path.dirname(cur);
    if (parent === cur) return null;
    cur = parent;
  }
  return null;
}

// { kind: "norepo" } | { kind: "branch", branch } | { kind: "broken", why }
// Same shape as block-main-bash's branchOf. A directory INSIDE a .git
// (rev-parse says "false") still reads its branch: writing a ref file
// there moves that branch as surely as a commit.
function branchOf(dir) {
  const probe = git(["rev-parse", "--is-inside-work-tree"], dir);
  const broken = gitBroken(probe);
  if (broken) return { kind: "broken", why: broken };
  if (probe.status !== 0) {
    if (/not a git repository/i.test(String(probe.stderr || ""))) return { kind: "norepo" };
    return { kind: "broken", why: "git rev-parse failed" };
  }
  const br = git(["branch", "--show-current"], dir);
  const brBroken = gitBroken(br);
  if (brBroken) return { kind: "broken", why: brBroken };
  if (br.status !== 0) return { kind: "broken", why: "git branch --show-current failed" };
  return { kind: "branch", branch: String(br.stdout || "").trim() };
}

// True only when git names a toplevel for `dir` and it is the vault, both
// sides realpath'd. Any failure is false: no proof, no exemption.
function isVaultTop(dir) {
  try {
    const top = git(["rev-parse", "--show-toplevel"], dir);
    if (gitBroken(top) !== null || top.status !== 0) return false;
    const t = String(top.stdout || "").replace(/\n$/, "");
    if (t === "") return false;
    return fs.realpathSync.native(t) === fs.realpathSync.native(VAULT);
  } catch {
    return false;
  }
}

let input = "";
let ran = false;

function main() {
  // The cwd no longer allows on its own: it only records a protected
  // branch, for the messages and for the in-worktree test below.
  const probe = git(["rev-parse", "--is-inside-work-tree"]);
  const probeBroken = gitBroken(probe);
  if (probeBroken) denyUnverifiable(probeBroken);
  if (probe.status !== 0) {
    if (!/not a git repository/i.test(String(probe.stderr || ""))) denyUnverifiable("git rev-parse failed");
  } else if (String(probe.stdout || "").trim() === "true") {
    const br = git(["branch", "--show-current"]);
    const brBroken = gitBroken(br);
    if (brBroken) denyUnverifiable(brBroken);
    if (br.status !== 0) denyUnverifiable("git branch --show-current failed");
    const branch = String(br.stdout || "").trim();
    if (PROTECTED.indexOf(branch) !== -1) branchSeen = branch;
  }

  let data;
  try { data = JSON.parse(input); } catch { denyOnBranch("the hook input was not valid JSON"); return; }
  if (!data || typeof data !== "object" || Array.isArray(data)) { denyOnBranch("the hook input was not an object"); return; }
  const ti = data.tool_input;
  // NotebookEdit carries its target in notebook_path, not file_path.
  const given = ti && typeof ti === "object" && !Array.isArray(ti) ? ti.file_path || ti.notebook_path : undefined;
  const raw = typeof given === "string" && given.trim() !== "" ? given : null;
  if (!raw) { denyOnBranch("the hook input carries no tool_input.file_path or notebook_path"); return; }
  // A `..` walks through whatever the segment before it names, which may
  // be a symlink the resolution below never sees the same way the tool
  // does: it is refused rather than reasoned about.
  if (raw.split("/").indexOf("..") !== -1) { denyOnBranch("the target path has a \"..\" segment"); return; }
  const realTarget = realpathish(raw);
  if (realTarget === null) { denyOnBranch("the target path could not be resolved"); return; }

  if (branchSeen !== null) {
    const top = git(["rev-parse", "--show-toplevel"]);
    const topBroken = gitBroken(top);
    if (topBroken) { denyOnBranch(topBroken); return; }
    if (top.status !== 0) { denyOnBranch("the worktree root could not be located"); return; }
    // Only git's own trailing newline is cut: `.trim()` also ate spaces a
    // directory name may legitimately end with.
    const realTop = realpathish(String(top.stdout || "").replace(/\n$/, ""));
    if (realTop === null) { denyOnBranch("the target path could not be resolved"); return; }
    if (realTarget === realTop || realTarget.startsWith(realTop + path.sep)) {
      if (isVaultTop(realTop)) allow();
      deny("BLOCKED: on " + safe(branchSeen) + ". " + CUT);
    }
  }

  // The repo the FILE belongs to, whatever the cwd is.
  const home = nearestDir(realTarget);
  if (home === null) { denyOnBranch("no existing directory holds the target path"); return; }
  const f = branchOf(home);
  if (f.kind === "broken") denyUnverifiable(f.why + " in the repository the file belongs to");
  if (f.kind === "branch" && PROTECTED.indexOf(f.branch) !== -1 && !isVaultTop(home)) {
    deny("BLOCKED: on " + safe(f.branch) + ". " + CUT);
  }
  allow();
}

function start() {
  if (ran) return;
  ran = true;
  try {
    main();
  } catch (e) {
    denyOnBranch("the hook itself failed (" + safe(e && e.message) + ")");
  }
  denyOnBranch("the hook reached no decision");
}

process.on("uncaughtException", (e) => {
  if (settled) return;
  deny("BLOCKED: the branch-protection hook crashed (" + safe(e && e.message) + "), so the branch could not be checked. " + CUT);
});

const watchdog = setTimeout(() => {
  deny("BLOCKED: the branch-protection hook hit its own " + BUDGET_MS + " ms deadline before it could read its input. " + CUT);
}, BUDGET_MS);
if (typeof watchdog.unref === "function") watchdog.unref();

process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => { if (input.length < 4 * 1024 * 1024) input += c; });
process.stdin.on("end", start);
process.stdin.on("error", start);
