#!/usr/bin/env node
// PostToolUse on Bash: once a `gh pr merge` has merged, writes pr.md in the
// APEX run(s) whose 00-context.md names the PR's head branch. The board puts a
// run in Terminé as soon as pr.md exists, and three runs stayed stuck on the
// coordinator forgetting that write (2026-10-21).
//
// Acts only on a lone `gh pr merge [selector] [flags]` (the shape the sandbox
// exclusion lets out anyway) that did not fail, and only once `gh pr view`
// says MERGED: `--auto` leaves the PR OPEN, and nothing is written.
// Selector: the first non-flag word after `merge`, the values of the flags
// that take one skipped; none, and gh resolves the CURRENT branch, which
// `--delete-branch` has already left: nothing found, nothing written.
// Match: a `Branch: <head>` line, the name followed by a blank or the end.
// When no run has one, a run WITHOUT any `Branch:` line whose dir is the
// head's last segment (Direct cuts `{type}/{task-id}` and writes no
// `Branch:` line: #609/#610 stayed stuck, 2026-10-21), or that names the head
// as a whole token in its first 12 lines. Every match is written, never over
// an existing pr.md (O_EXCL), never in a run that has commit.txt.
//
// FAIL-OPEN, workflow hook: exit 0 on every path, nothing on stdout ever; one
// stderr line when gh or a write fails. git and gh run through execFileSync,
// no shell, each under its own timeout: 2 + 2 + 10 s stays under the 15 s
// the host gives this hook.
"use strict";
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const READ_MS = 2000;
const GIT_MS = 2000;
const GH_MS = 10000;
const MAX_INPUT = 4 * 1024 * 1024;
const MAX_CONTEXT = 256 * 1024;
const HEADER_LINES = 12;
// `gh pr merge` flags whose value is the next word: never the selector.
const VALUE_FLAGS = new Set(["-b", "--body", "-F", "--body-file", "-t", "--subject", "-R", "--repo", "--match-head-commit", "-A", "--author-email"]);
const TOKEN = /[\w./-]/;

function quit() { process.exit(0); }

function note(msg) {
  // Synchronous: process.exit() can drop an async pipe write.
  try { fs.writeSync(2, "apex-pr-record: " + String(msg).split("\n")[0].slice(0, 200) + "\n"); } catch {}
}

// The words of a lone simple command, or null when it chains, pipes,
// redirects, substitutes or leaves a quote open: not a lone `gh pr merge`.
function words(cmd) {
  const out = [];
  let cur = null;
  let i = 0;
  while (i < cmd.length) {
    const c = cmd[i];
    if (c === "'") {
      const j = cmd.indexOf("'", i + 1);
      if (j < 0) return null;
      cur = (cur || "") + cmd.slice(i + 1, j);
      i = j + 1;
    } else if (c === "\"") {
      cur = cur || "";
      for (i++; ; i++) {
        if (i >= cmd.length) return null;
        const q = cmd[i];
        if (q === "\"") { i++; break; }
        if (q === "$" || q === "`") return null;
        if (q === "\\" && i + 1 < cmd.length && "\"\\$`".includes(cmd[i + 1])) { cur += cmd[++i]; continue; }
        cur += q;
      }
    } else if (c === "\\") {
      if (i + 1 >= cmd.length) return null;
      cur = (cur || "") + cmd[i + 1];
      i += 2;
    } else if (c === " " || c === "\t") {
      if (cur !== null) { out.push(cur); cur = null; }
      i++;
    } else if (c === "#" && cur === null) {
      break;
    } else if (";&|<>()`$\n\r".includes(c)) {
      return null;
    } else {
      cur = (cur || "") + c;
      i++;
    }
  }
  if (cur !== null) out.push(cur);
  return out;
}

// The PR selector and the `-R` repo among the words after `merge`.
function selectorOf(args) {
  let sel = null;
  let repo = null;
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--") { if (sel === null && i + 1 < args.length) sel = args[i + 1]; break; }
    if (VALUE_FLAGS.has(a)) {
      if ((a === "-R" || a === "--repo") && i + 1 < args.length) repo = args[i + 1];
      i++;
      continue;
    }
    if (a.startsWith("--repo=")) { repo = a.slice(7); continue; }
    if (a.startsWith("-R") && a.length > 2) { repo = a.slice(2); continue; }
    if (a.startsWith("-")) continue;
    if (sel === null) sel = a;
  }
  return { sel, repo };
}

function toolFailed(r) {
  return !!r && typeof r === "object" && (r.interrupted === true || r.is_error === true);
}

// `Branch: <head>` with the name followed by a blank or the end of the line.
function branchLine(l, head) {
  if (!l.startsWith("Branch:")) return false;
  const rest = l.slice(7).replace(/^\s+/, "");
  return rest.startsWith(head) && /^(\s|$)/.test(rest.slice(head.length));
}

// A trailing period ends the sentence, not the branch name.
function endsToken(s) {
  return s === "" || !TOKEN.test(s[0]) || (s[0] === "." && (s.length === 1 || !TOKEN.test(s[1])));
}

function namesToken(line, head) {
  for (let i = line.indexOf(head); i >= 0; i = line.indexOf(head, i + 1)) {
    if (i > 0 && TOKEN.test(line[i - 1])) continue;
    const after = line.slice(i + head.length, i + head.length + 2);
    if (endsToken(after)) return true;
  }
  return false;
}

function present(p) {
  try { fs.lstatSync(p); return true; } catch { return false; }
}

// Every run dir (not a symlink) with a readable 00-context.md, by id.
function runsUnder(top) {
  const base = path.join(top, ".claude", "output", "apex");
  let ents;
  try { ents = fs.readdirSync(base, { withFileTypes: true }); } catch { return []; }
  const runs = [];
  for (const e of ents.filter(x => x.isDirectory()).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))) {
    const dir = path.join(base, e.name);
    const ctx = path.join(dir, "00-context.md");
    try {
      const st = fs.lstatSync(ctx);
      if (!st.isFile() || st.size > MAX_CONTEXT) continue;
      runs.push({ dir, lines: fs.readFileSync(ctx, "utf8").split(/\r?\n/) });
    } catch {}
  }
  return runs;
}

function main(input) {
  let data;
  try { data = JSON.parse(input); } catch { return; }
  if (!data || typeof data !== "object" || Array.isArray(data)) return;
  if (data.hook_event_name !== "PostToolUse" || data.tool_name !== "Bash") return;
  if (toolFailed(data.tool_response)) return;
  const ti = data.tool_input && typeof data.tool_input === "object" ? data.tool_input : {};
  const cmd = typeof ti.command === "string" ? ti.command.replace(/^[ \t\n]+|[ \t\n]+$/g, "") : "";
  if (!cmd.startsWith("gh")) return;
  const w = words(cmd);
  if (!w || w[0] !== "gh" || w[1] !== "pr" || w[2] !== "merge") return;
  const { sel, repo } = selectorOf(w.slice(3));

  const cwd = typeof data.cwd === "string" && path.isAbsolute(data.cwd) ? data.cwd : process.cwd();
  let top;
  try {
    top = execFileSync("git", ["-c", "core.fsmonitor=false", "rev-parse", "--show-toplevel"], { cwd, encoding: "utf8", timeout: GIT_MS, killSignal: "SIGKILL", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch { return; }
  if (!top) return;
  // Runs first: a repo without APEX runs never waits on the network.
  const runs = runsUnder(top);
  if (runs.length === 0) return;

  const ghArgs = ["pr", "view"];
  if (sel !== null) ghArgs.push(sel);
  if (repo) ghArgs.push("-R", repo);
  ghArgs.push("--json", "number,url,state,headRefName,mergeCommit");
  let pr;
  try {
    pr = JSON.parse(execFileSync("gh", ghArgs, { cwd, encoding: "utf8", timeout: GH_MS, killSignal: "SIGKILL", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 1024 * 1024 }));
  } catch (e) {
    note("gh pr view failed: " + String((e && e.stderr) || (e && e.message) || e).trim());
    return;
  }
  if (!pr || pr.state !== "MERGED") return;
  const head = typeof pr.headRefName === "string" ? pr.headRefName : "";
  if (!/^[^\s\0]+$/.test(head) || !Number.isInteger(pr.number) || pr.number <= 0) return;
  if (typeof pr.url !== "string" || !/^https?:\/\/\S+$/.test(pr.url)) return;
  const oid = pr.mergeCommit && typeof pr.mergeCommit.oid === "string" ? pr.mergeCommit.oid : "";
  const sha = /^[0-9a-f]{8,}$/.test(oid) ? oid.slice(0, 8) : "unknown";

  let hits = runs.filter(r => r.lines.some(l => branchLine(l, head)));
  const unbranched = runs.filter(r => !r.lines.some(l => l.startsWith("Branch:")));
  const leaf = head.slice(head.lastIndexOf("/") + 1);
  if (hits.length === 0) hits = unbranched.filter(r => path.basename(r.dir) === leaf || r.lines.slice(0, HEADER_LINES).some(l => namesToken(l, head)));

  const body = "#" + pr.number + " " + pr.url + " — merged (" + sha + ") — recorded by apex-pr-record\n";
  for (const r of hits) {
    if (present(path.join(r.dir, "commit.txt"))) continue;
    try {
      fs.writeFileSync(path.join(r.dir, "pr.md"), body, { flag: "wx" });
    } catch (e) {
      if (!e || e.code !== "EEXIST") note(path.basename(r.dir) + "/pr.md: " + String((e && e.code) || e));
    }
  }
}

let input = "";
let overflow = false;
process.stdin.setEncoding("utf8");
const reading = setTimeout(quit, READ_MS);
process.stdin.on("data", c => {
  if (overflow) return;
  input += c;
  if (input.length > MAX_INPUT) { overflow = true; quit(); }
});
process.stdin.on("error", quit);
process.stdin.on("end", () => {
  clearTimeout(reading);
  try { main(input); } catch (e) {
    note(String((e && e.code) || (e && e.message) || e));
  }
  quit();
});
