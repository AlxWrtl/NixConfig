#!/usr/bin/env node
"use strict";

// PreToolUse on Bash: refuse to delete a git worktree (or a tree holding a
// checkout) that a live process still has as its working directory.
//
// WHY. 2026-10-21 20:57, Preliz: a session asked to tidy branches ran
// `git worktree remove --force .claude/worktrees/agent-135738` and
// `git branch -D` while agent-135738 was open in its abduco pane. The
// worktree vanished under the live agent. git itself only checks for
// uncommitted changes, and --force skips even that; nothing asks whether a
// process is still inside.
//
// SHAPES. `git [-C d]... worktree remove [-f|--force]... <wt>` (resolved
// against the -C dir, the session cwd, a leading `cd X &&`, `env -C` or
// `sudo -D`; as git does it, first by a trailing run of path components of
// a listed worktree, then as a path) and `rm -r/-R/-rf/--recursive <p>`.
// In both, `{a,b}` / `{1..3}` braces and a glob in the last component are
// expanded and `$PWD` is the shell's directory; the rm only when a `.git` (file or dir) sits
// between the removed directory and the holder's cwd: deleting a plain
// directory someone sits in is not this hook's business. A target the shell
// would compute ($VAR, $(...), a backtick) cannot be placed and is let
// through: a safety net, not a barrier.
//
// LIVENESS. One lsof call, only once a shape matched: every process's cwd,
// with its parent pid and full command name. A holder has a cwd equal to
// the target or under it, compared case-insensitively (APFS). The hook
// itself, its lsof child and its direct parent when that is a plain shell
// (the host's hook launcher) are not holders. A Claude session removing the
// worktree it runs in IS one, and is denied.
//
// FAIL POLICY, split on the match. Before a shape matched, any error
// (unreadable input, a lexer doubt, a throw, the watchdog) allows: most Bash
// calls are not removals and must not pay for this hook's faults. After a
// matched, resolved, existing target it FAILS CLOSED: lsof missing, hung,
// killed, an unexpected exit status, or an output that does not even list
// this hook's own process all deny. The registered host timeout (5 s) sits
// above the watchdog (3 s), itself above the lsof budget (2 s): a hook the
// host kills fails open.
//
// The lsof path is ONE literal line below: checks/hook-wiring.nix repoints
// it at a fake in the build sandbox (no /usr/sbin, no process info there),
// and checks/worktree-in-use-probe.sh runs the body unmodified against the
// real binary.

const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawnSync } = require("child_process");

const LSOF = "/usr/sbin/lsof";
const BUDGET_MS = 3000;
const LSOF_MS = 2000;
const GIT_MS = 1000;
const DEADLINE = Date.now() + BUDGET_MS;
const MAX_INPUT = 4 * 1024 * 1024;
// Nesting of $(...), backticks, subshells and `sh -c` strings. Past it the
// command is not read at all: an allow (nothing matched yet).
const MAX_DEPTH = 8;
// Entries a last-component glob may list before it is given up on.
const MAX_GLOB = 4096;
// Words a brace expansion may produce before it is given up on.
const MAX_BRACE = 256;
const STOP = "Do not retry or work around; stop and ask the user.";

let settled = false;
// The first resolved target, once a shape matched: from then on every
// failure denies.
let matched = null;

process.on("uncaughtException", (e) => {
  if (settled) return;
  if (matched !== null) denyBlind("the hook crashed: " + safe(e && e.message));
  allow();
});

const watchdog = setTimeout(() => {
  if (matched !== null) denyBlind("the hook hit its own " + BUDGET_MS + " ms deadline");
  allow();
}, BUDGET_MS);
if (typeof watchdog.unref === "function") watchdog.unref();

// Cheap gate: no `rm` or `worktree` word anywhere, nothing to lex.
const PREFILTER = /\brm\b|\bworktree\b/;
const ASSIGN = /^[A-Za-z_][A-Za-z0-9_]*=/;
const KEYWORDS = ["if", "then", "else", "elif", "do", "while", "until", "!", "{", "}", "time"];
const SHELLS = ["sh", "bash", "zsh", "dash", "ksh"];
// Run the word after them (and their options) as the command.
const WRAPPERS = ["env", "command", "builtin", "exec", "nohup", "nice", "timeout", "gtimeout", "sudo", "doas", "stdbuf", "xargs", "caffeinate", "noglob", "rtk"];
// Wrapper options that take their value as the NEXT word (`sudo -u alx`).
const TIMEOUT_ARG_OPTS = ["-s", "--signal", "-k", "--kill-after"];
const WRAPPER_ARG_OPTS = {
  env: ["-u", "--unset", "-C", "--chdir"],
  timeout: TIMEOUT_ARG_OPTS,
  gtimeout: TIMEOUT_ARG_OPTS,
  sudo: ["-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt", "-C", "--close-from", "-D", "--chdir", "-r", "--role", "-t", "--type", "-U", "--other-user", "-T", "--command-timeout", "-R", "--chroot"],
  doas: ["-u", "-C"],
  nice: ["-n", "--adjustment"],
  stdbuf: ["-i", "-o", "-e", "--input", "--output", "--error"],
  xargs: ["-I", "-a", "-d", "-E", "-L", "-n", "-P", "-s", "--arg-file", "--delimiter", "--max-args", "--max-procs", "--max-lines", "--max-chars"],
  caffeinate: ["-t", "-w"]
};
// Wrapper options that run the command in another directory.
const WRAPPER_CHDIR = { env: ["-C", "--chdir"], sudo: ["-D", "--chdir"] };
const COMMAND_LOOKUP = /^-[pvV]*[vV][pvV]*$/;
// git global options that take their value as the NEXT word (-C is read).
const GIT_ARG_OPTS = ["-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--exec-path"];

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

// A matched removal whose liveness could not be read: refused, never guessed.
function denyBlind(why) {
  deny("BLOCKED: this command removes " + safe(matched) + " (git worktree remove / rm -r), and whether a live process still runs in it could not be checked (" + safe(why) + "), so it is refused rather than pull a directory from under a running agent or server. " + STOP);
}

// ---- lexer (adapted from lone-excluded-bash.js) -----------------------
// Thrown where the shell text cannot be read with confidence; before a
// match the caller turns it into an allow.
class Unreadable extends Error {}

function newResult() {
  return { segs: [[]], inner: [] };
}

// Heredoc bodies start at the newline after their operator, in operator
// order, and end on their delimiter line. They are skipped: their text is
// data to the command reading them, not commands of this call.
function bodies(s, i, pending) {
  const n = s.length;
  while (pending.length) {
    const h = pending.shift();
    while (i < n) {
      let e = s.indexOf("\n", i);
      if (e < 0) e = n;
      let line = s.slice(i, e);
      if (h.tabs) line = line.replace(/^\t+/, "");
      i = e < n ? e + 1 : n;
      if (line === h.delim) break;
    }
  }
  return i;
}

// Quote-aware scan of s from i into r: words grouped into segments (cut on
// && || ; | |& & and newline). `closer` ")" stops on the unquoted `)` that
// ends a $(...) / (...) body and returns past it.
// Word: { val, glob, brace, dyn, pwd } — `val` is the dequoted text,
// `glob[k]` marks an UNQUOTED * or ? at val[k], `brace[k]` an unquoted { , },
// `dyn` means the shell computes part of it ($VAR, $(...), a backtick, an
// unquoted [), so it cannot be placed. $HOME / ${HOME} and a leading ~ are
// expanded: they are where a worktree path is most often spelled from. A
// leading $PWD / ${PWD} / ~+ sets `pwd` and is left out of `val`: segment()
// prefixes the directory the shell is in at that point.
function lex(s, i, closer, depth, r) {
  if (depth > MAX_DEPTH) throw new Unreadable("nesting too deep");
  const n = s.length;
  const pending = [];
  let word = null;
  let operand = false;
  const seg = () => r.segs[r.segs.length - 1];
  const open = () => {
    if (word === null) word = { val: "", glob: [], brace: [], dyn: false, pwd: false };
    return word;
  };
  const lit = (t) => {
    const w = open();
    w.val += t;
    for (let k = 0; k < t.length; k++) { w.glob.push(false); w.brace.push(false); }
  };
  const bare = (c) => {
    const w = open();
    w.val += c;
    w.glob.push(c === "*" || c === "?");
    w.brace.push(c === "{" || c === "," || c === "}");
    if (c === "[") w.dyn = true;
  };
  const sub = (inner) => {
    r.inner.push(inner);
    open().dyn = true;
  };
  const endWord = () => {
    if (word === null) return;
    if (operand) { operand = false; word = null; return; }
    seg().push(word);
    word = null;
  };
  const endSeg = () => {
    endWord();
    operand = false;
    if (seg().length) r.segs.push([]);
  };
  // `$` at s[j]: the index past what it consumed.
  const dollar = (j) => {
    const home = /^\$(?:HOME(?![A-Za-z0-9_])|\{HOME\})/.exec(s.slice(j, j + 7));
    if (home !== null) { lit(os.homedir()); return j + home[0].length; }
    const pwd = /^\$(?:PWD(?![A-Za-z0-9_])|\{PWD\})/.exec(s.slice(j, j + 6));
    if (pwd !== null) {
      // Only a leading one is placed; inside a word it is computed text.
      if (word === null || (word.val === "" && !word.pwd)) open().pwd = true;
      else open().dyn = true;
      return j + pwd[0].length;
    }
    if (s[j + 1] === "(") {
      const inner = newResult();
      const e = lex(s, j + 2, ")", depth + 1, inner);
      sub(inner);
      return e;
    }
    open().dyn = true;
    lit("$");
    return j + 1;
  };
  while (i < n) {
    const ch = s[i];
    if (ch === ")") {
      if (closer !== ")") throw new Unreadable("unbalanced )");
      endSeg();
      return i + 1;
    }
    if (ch === " " || ch === "\t") { endWord(); i++; continue; }
    if (ch === "\n") {
      endSeg();
      i++;
      if (pending.length) i = bodies(s, i, pending);
      continue;
    }
    if (ch === "#" && word === null) {
      const e = s.indexOf("\n", i);
      i = e < 0 ? n : e;
      continue;
    }
    if (ch === "\\") {
      if (s[i + 1] === "\n") { i += 2; continue; }
      lit(s.slice(i + 1, i + 2));
      i += 2;
      continue;
    }
    if (ch === "'") {
      const e = s.indexOf("'", i + 1);
      if (e < 0) throw new Unreadable("unbalanced '");
      lit(s.slice(i + 1, e));
      i = e + 1;
      continue;
    }
    if (ch === "$" && s[i + 1] === "'") {
      let j = i + 2;
      while (j < n && s[j] !== "'") j += s[j] === "\\" ? 2 : 1;
      if (j >= n) throw new Unreadable("unbalanced $'");
      const body = s.slice(i + 2, j);
      lit(body);
      // Escapes are not decoded here: such a word cannot be placed.
      if (body.indexOf("\\") >= 0) open().dyn = true;
      i = j + 1;
      continue;
    }
    if (ch === '"') {
      let j = i + 1;
      open();
      for (;;) {
        if (j >= n) throw new Unreadable("unbalanced \"");
        const c = s[j];
        if (c === '"') { j++; break; }
        if (c === "\\") { lit(s.slice(j + 1, j + 2)); j += 2; continue; }
        if (c === "$") { j = dollar(j); continue; }
        if (c === "`") { j = backtick(s, j, depth, sub); continue; }
        lit(c);
        j++;
      }
      i = j;
      continue;
    }
    if (ch === "`") { i = backtick(s, i, depth, sub); continue; }
    if (ch === "$") { i = dollar(i); continue; }
    if ((ch === "<" || ch === ">") && s[i + 1] === "(") {
      const inner = newResult();
      i = lex(s, i + 2, ")", depth + 1, inner);
      sub(inner);
      continue;
    }
    if (ch === "(") {
      endWord();
      const inner = newResult();
      i = lex(s, i + 1, ")", depth + 1, inner);
      r.inner.push(inner);
      continue;
    }
    if (ch === "<" && s[i + 1] === "<" && s[i + 2] !== "<") {
      endWord();
      let k = i + 2;
      const tabs = s[k] === "-";
      if (tabs) k++;
      while (s[k] === " " || s[k] === "\t") k++;
      const m = /^[^\s;&|<>()]+/.exec(s.slice(k, k + 4096));
      if (m === null) throw new Unreadable("heredoc without a delimiter");
      const delim = m[0].replace(/['"\\]/g, "");
      if (delim === "") throw new Unreadable("empty heredoc delimiter");
      pending.push({ delim: delim, tabs: tabs });
      i = k + m[0].length;
      continue;
    }
    if (ch === "<" || ch === ">" || (ch === "&" && s[i + 1] === ">")) {
      // An all-digit word glued to the operator is its fd number (2>x).
      if (word !== null && /^[0-9]+$/.test(word.val)) word = null;
      endWord();
      const two = s.slice(i, i + 2);
      let op = ch;
      if (s.startsWith("<<<", i)) op = "<<<";
      else if (s.startsWith("&>>", i)) op = "&>>";
      else if (["&>", ">>", ">&", "<&", ">|", "<>"].includes(two)) op = two;
      // The next word is the redirection's operand, not an argument.
      operand = true;
      i += op.length;
      continue;
    }
    if (ch === ";") { endSeg(); i += s[i + 1] === ";" ? 2 : 1; continue; }
    if (ch === "|") { endSeg(); i += s[i + 1] === "|" || s[i + 1] === "&" ? 2 : 1; continue; }
    if (ch === "&") { endSeg(); i += s[i + 1] === "&" ? 2 : 1; continue; }
    if (ch === "~" && word === null && s[i + 1] === "+" && /^(?:[/\s;&|<>()]|$)/.test(s.slice(i + 2, i + 3))) {
      open().pwd = true;
      i += 2;
      continue;
    }
    if (ch === "~" && word === null && /^(?:[/\s;&|<>()]|$)/.test(s.slice(i + 1, i + 2))) {
      lit(os.homedir());
      i++;
      continue;
    }
    bare(ch);
    i++;
  }
  if (closer === ")") throw new Unreadable("unbalanced (");
  endSeg();
  return n;
}

// A backtick body, read to its unescaped twin, then lexed as a command.
function backtick(s, i, depth, sub) {
  let j = i + 1;
  while (j < s.length && s[j] !== "`") j += s[j] === "\\" ? 2 : 1;
  if (j >= s.length) throw new Unreadable("unbalanced `");
  const inner = newResult();
  lex(s.slice(i + 1, j).replace(/\\([`$\\])/g, "$1"), 0, null, depth + 1, inner);
  sub(inner);
  return j + 1;
}

// ---- targets -----------------------------------------------------------
const base = (v) => v.slice(v.lastIndexOf("/") + 1);
const hasGlob = (w) => w.glob.some(Boolean);

// The words bash and zsh make of w's unquoted braces, before globbing:
// a{b,c}d is abd acd, {1..3} is 1 2 3, groups nest. A group with neither a
// comma nor a range stays literal in both shells; it is read both ways here
// (literal, and with the braces dropped), so `{held}` still meets held.
function braces(w) {
  const res = [];
  const cut = (x, a, z) => ({ val: x.val.slice(a, z), glob: x.glob.slice(a, z), brace: x.brace.slice(a, z), dyn: x.dyn, pwd: x.pwd });
  const join = (x, parts) => ({
    val: parts.map((q) => q.val).join(""),
    glob: [].concat(...parts.map((q) => q.glob)),
    brace: [].concat(...parts.map((q) => q.brace)),
    dyn: x.dyn,
    pwd: x.pwd
  });
  const walk = (x) => {
    if (res.length >= MAX_BRACE) return;
    for (let i = 0; i < x.val.length; i++) {
      if (!x.brace[i] || x.val[i] !== "{") continue;
      let depth = 0;
      let end = -1;
      const commas = [];
      for (let j = i + 1; j < x.val.length && end < 0; j++) {
        if (!x.brace[j]) continue;
        const c = x.val[j];
        if (c === "{") depth++;
        else if (c === "}" && depth > 0) depth--;
        else if (c === "}") end = j;
        else if (c === "," && depth === 0) commas.push(j);
      }
      // An unmatched { is a plain character: try the next one.
      if (end < 0) continue;
      const pre = cut(x, 0, i);
      const post = cut(x, end + 1, x.val.length);
      const alts = [];
      if (commas.length > 0) {
        let a = i + 1;
        for (const c of commas.concat([end])) { alts.push(cut(x, a, c)); a = c + 1; }
      } else {
        const seq = /^(-?[0-9]{1,6})\.\.(-?[0-9]{1,6})$/.exec(x.val.slice(i + 1, end));
        if (seq !== null) {
          const z = Number(seq[2]);
          const step = Number(seq[1]) <= z ? 1 : -1;
          for (let v = Number(seq[1]); alts.length < MAX_BRACE; v += step) {
            const t = String(v);
            alts.push({ val: t, glob: Array(t.length).fill(false), brace: Array(t.length).fill(false), dyn: false, pwd: false });
            if (v === z) break;
          }
        } else {
          walk(Object.assign({}, x, { brace: x.brace.map((b, k) => b && k !== i && k !== end) }));
          alts.push(cut(x, i + 1, end));
        }
      }
      for (const a of alts) walk(join(x, [pre, a, post]));
      return;
    }
    res.push(x);
  };
  walk(w);
  return res;
}

// A word led by $PWD / ~+, prefixed with the directory the shell is in;
// left unplaceable when that is not known.
function atPwd(w, cur) {
  if (cur === null) return w;
  const n = cur.length;
  return {
    val: cur + w.val,
    glob: Array(n).fill(false).concat(w.glob),
    brace: Array(n).fill(false).concat(w.brace),
    dyn: w.dyn,
    pwd: false
  };
}

// The physical directory behind p, or null when there is none: lsof
// reports getcwd's path, so a symlinked spelling must be resolved first.
function realDir(p) {
  try {
    const real = fs.realpathSync.native(p);
    return fs.statSync(real).isDirectory() ? real : null;
  } catch {
    return null;
  }
}

// An absolute path for a word, relative to dir; null when it cannot be
// placed (computed, or relative to an unknown directory).
function place(w, dir) {
  if (w.dyn || w.pwd || w.val === "") return null;
  if (path.isAbsolute(w.val)) return path.resolve(w.val);
  if (dir === null) return null;
  return path.resolve(dir, w.val);
}

function git(args, cwd) {
  const left = DEADLINE - Date.now();
  if (left <= 0) return null;
  const r = spawnSync("git", args, {
    cwd: cwd,
    encoding: "utf8",
    timeout: Math.min(GIT_MS, left),
    killSignal: "SIGKILL",
    stdio: ["ignore", "pipe", "ignore"],
    maxBuffer: 1024 * 1024,
    windowsHide: true,
    env: Object.assign({}, process.env, { LC_ALL: "C" })
  });
  if (r.error || r.signal || r.status !== 0) return null;
  return String(r.stdout || "");
}

// `git worktree remove <wt>`: git looks the word up FIRST as a trailing run
// of path components of a listed worktree (`held` for .../wts/held), then
// as a path. Both are taken: a plain directory sharing the name does not
// stop the lookup. One listing per directory.
const listings = new Map();
function resolveWt(w, dir, out) {
  const abs = place(w, dir);
  if (abs === null) return;
  const real = realDir(abs);
  if (real !== null) out.push({ path: real, kind: "remove" });
  if (path.isAbsolute(w.val) || realDir(dir) === null) return;
  if (!listings.has(dir)) listings.set(dir, git(["worktree", "list", "--porcelain"], dir));
  const list = listings.get(dir);
  if (list === null) return;
  const want = "/" + w.val.replace(/\/+$/, "");
  for (const line of list.split("\n")) {
    if (!line.startsWith("worktree ")) continue;
    const p = line.slice("worktree ".length);
    if (p.endsWith(want)) {
      const r = realDir(p);
      if (r !== null) out.push({ path: r, kind: "remove" });
    }
  }
}

function gitSeg(words, k, cur, out) {
  let dir = cur;
  let j = k + 1;
  while (j < words.length) {
    const v = words[j].val;
    if (v === "-C") {
      const a = words[j + 1];
      if (a === undefined) return;
      dir = place(a, dir);
      if (dir === null) return;
      j += 2;
      continue;
    }
    if (GIT_ARG_OPTS.includes(v)) { j += 2; continue; }
    if (v.startsWith("-")) { j++; continue; }
    break;
  }
  if (words[j] === undefined || words[j].val !== "worktree") return;
  if (words[j + 1] === undefined || words[j + 1].val !== "remove") return;
  let opts = true;
  for (j += 2; j < words.length; j++) {
    const w = words[j];
    if (opts && w.val === "--") { opts = false; continue; }
    if (opts && w.val.startsWith("-")) continue;
    for (const b of braces(w)) {
      // The shell globs in its own directory; git reads each match from -C.
      if (hasGlob(b)) { for (const g of globWords(b, cur)) resolveWt(g, dir, out); continue; }
      resolveWt(b, dir, out);
    }
    return;
  }
}

// The words a last-component glob in w becomes, matched in dir as the shell
// does it, spelled as w is (relative stays relative). A glob anywhere else
// cannot be placed: none.
function globWords(w, dir) {
  const slash = w.val.lastIndexOf("/");
  if (w.glob.indexOf(true) < slash) return [];
  const head = slash < 0 ? "" : w.val.slice(0, slash + 1);
  const parent = place({ val: head === "" ? "." : head, glob: [], dyn: w.dyn }, dir);
  if (parent === null) return [];
  let re = "^";
  for (let k = slash + 1; k < w.val.length; k++) {
    const c = w.val[k];
    if (w.glob[k]) re += c === "*" ? "[^/]*" : "[^/]";
    else re += c.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
  }
  const pat = new RegExp(re + "$");
  // The shell's * and ? never match a leading dot.
  const dot = w.val[slash + 1] === "." && !w.glob[slash + 1];
  let names;
  try { names = fs.readdirSync(parent); } catch { return []; }
  if (names.length > MAX_GLOB) return [];
  return names.filter((x) => (dot || x[0] !== ".") && pat.test(x)).map((x) => ({ val: head + x, glob: [], dyn: false }));
}

// The directories a word names once its last-component glob is expanded.
function expand(w, dir) {
  if (!hasGlob(w)) {
    const abs = place(w, dir);
    return abs === null ? [] : [abs];
  }
  return globWords(w, dir).map((g) => place(g, dir)).filter((x) => x !== null);
}

function rmSeg(words, k, cur, out) {
  let rec = false;
  let opts = true;
  const pos = [];
  for (let j = k + 1; j < words.length; j++) {
    const w = words[j];
    const v = w.val;
    if (opts && v === "--") { opts = false; continue; }
    if (opts && v.startsWith("--")) { if (v === "--recursive") rec = true; continue; }
    if (opts && /^-./.test(v)) { if (/[rR]/.test(v.slice(1))) rec = true; continue; }
    pos.push(w);
  }
  if (!rec) return;
  for (const b of [].concat(...pos.map(braces))) {
    for (const abs of expand(b, cur)) {
      // rm removes a symlink itself, not the directory it points at,
      // unless a trailing slash makes the shell follow it.
      try {
        if (fs.lstatSync(abs).isSymbolicLink() && !b.val.endsWith("/")) continue;
      } catch {
        continue;
      }
      const real = realDir(abs);
      if (real !== null) out.push({ path: real, kind: "rm" });
    }
  }
}

// One segment: its removal targets pushed to out. Returns the directory
// the next segment runs in (a `cd` moves it; null once it cannot be told,
// a `popd` included: the directory stack is not modelled). `env -C` and
// `sudo -D` move only the command they run (`here`).
function segment(raw, cur, depth, out) {
  const words = raw.map((w) => (w.pwd ? atPwd(w, cur) : w));
  let here = cur;
  let k = 0;
  while (k < words.length) {
    const v = words[k].val;
    if (ASSIGN.test(v) || KEYWORDS.includes(v)) { k++; continue; }
    const w = base(v);
    if (WRAPPERS.includes(w)) {
      const opts = WRAPPER_ARG_OPTS[w] || [];
      const chdir = WRAPPER_CHDIR[w] || [];
      k++;
      while (k < words.length) {
        const o = words[k].val;
        if (w === "command" && COMMAND_LOOKUP.test(o)) return cur;
        if (chdir.includes(o)) { here = words[k + 1] === undefined ? null : place(words[k + 1], here); k += 2; continue; }
        if (chdir.includes("--chdir") && o.startsWith("--chdir=")) {
          here = place({ val: o.slice("--chdir=".length), glob: [], dyn: words[k].dyn }, here);
          k++;
          continue;
        }
        if (opts.includes(o)) { k += 2; continue; }
        if (/^-/.test(o) || /^[0-9.]+[smhd]?$/.test(o) || ASSIGN.test(o)) { k++; continue; }
        break;
      }
      continue;
    }
    break;
  }
  if (k >= words.length) return cur;
  const head = words[k];
  if (head.dyn) return cur;
  const cmd = base(head.val);
  if (cmd === "popd") return null;
  if (cmd === "cd" || cmd === "pushd") {
    let j = k + 1;
    while (j < words.length && /^-[LPe@]+$|^--$/.test(words[j].val)) j++;
    const a = words[j];
    // pushd alone or with +N / -N rotates the stack.
    if (cmd === "pushd" && (a === undefined || /^[+-][0-9]+$/.test(a.val))) return null;
    if (a === undefined) return os.homedir();
    if (a.val === "-" || hasGlob(a)) return null;
    return place(a, cur);
  }
  if (cmd === "git") { gitSeg(words, k, here, out); return cur; }
  if (cmd === "rm") { rmSeg(words, k, here, out); return cur; }
  let code = null;
  if (cmd === "eval") code = words.slice(k + 1).map((w) => w.val).join(" ");
  if (SHELLS.includes(cmd)) {
    let c = words.findIndex((w, x) => x > k && /^-[A-Za-z]*c[A-Za-z]*$/.test(w.val));
    if (c > 0 && words[c + 1] !== undefined && words[c + 1].val === "--") c++;
    if (c > 0 && c + 1 < words.length) code = words[c + 1].val;
  }
  if (code !== null) {
    const inner = newResult();
    lex(code, 0, null, depth + 1, inner);
    collect(inner, here, depth + 1, out);
  }
  return cur;
}

// Segments in order, a `cd` carried to the ones after it; subshells and
// substitutions from the call's own directory.
function collect(r, cwd, depth, out) {
  let cur = cwd;
  for (const words of r.segs) cur = segment(words, cur, depth, out);
  for (const inner of r.inner) collect(inner, cwd, depth + 1, out);
}

// ---- liveness ------------------------------------------------------------
// p equal to root or under it. Case-insensitive: APFS is, and a spelling
// differing in case names the same directory.
function under(p, root) {
  const c = String(p).toLowerCase();
  const r = String(root).toLowerCase().replace(/\/+$/, "");
  return c === r || c.startsWith(r + "/");
}

// A .git that cannot be checked counts as present: the shape matched.
function hasGit(d) {
  try {
    fs.lstatSync(path.join(d, ".git"));
    return true;
  } catch (e) {
    return !(e && (e.code === "ENOENT" || e.code === "ENOTDIR"));
  }
}

// A checkout between root (the removed directory) and cwd (the holder's):
// `rm -r` of a plain directory someone sits in is not a worktree removal.
function isCheckoutBetween(root, cwd) {
  let d = cwd;
  for (let k = 0; k < 256 && under(d, root); k++) {
    if (hasGit(d)) return true;
    const up = path.dirname(d);
    if (up === d) break;
    d = up;
  }
  return false;
}

const holds = (x, cwd) => under(cwd, x.path) && (x.kind !== "rm" || isCheckoutBetween(x.path, cwd));

// Every process's cwd: { procs } or { broken, why }. Record order in -F
// output is p, R, c, then the file set (f, n); read by field, not position.
function listProcs() {
  const left = DEADLINE - Date.now();
  if (left <= 0) return { broken: true, why: "no time left to run lsof" };
  const r = spawnSync(LSOF, ["-n", "-P", "-w", "+c", "0", "-R", "-d", "cwd", "-FpcRn"], {
    encoding: "utf8",
    timeout: Math.min(LSOF_MS, left),
    killSignal: "SIGKILL",
    stdio: ["ignore", "pipe", "ignore"],
    maxBuffer: 16 * 1024 * 1024,
    windowsHide: true,
    env: Object.assign({}, process.env, { LC_ALL: "C" })
  });
  if (r.error) {
    const code = r.error.code;
    if (code === "ENOENT") return { broken: true, why: "lsof is missing at " + LSOF };
    if (code === "ETIMEDOUT") return { broken: true, why: "lsof did not answer within " + Math.min(LSOF_MS, left) + " ms" };
    if (code === "ENOBUFS") return { broken: true, why: "lsof output overflowed its buffer" };
    return { broken: true, why: "lsof could not be executed (" + safe(code) + ")" };
  }
  if (r.signal) return { broken: true, why: "lsof was killed by " + safe(r.signal) };
  // 1 is lsof's "something it was asked for was not found": still a listing.
  if (r.status !== 0 && r.status !== 1) return { broken: true, why: "lsof exited " + r.status };
  const procs = [];
  let p = null;
  for (const line of String(r.stdout || "").split("\n")) {
    const t = line[0];
    const v = line.slice(1);
    if (t === "p") { p = { pid: Number(v), ppid: 0, cmd: "", cwd: null }; procs.push(p); continue; }
    if (p === null) continue;
    if (t === "R") p.ppid = Number(v);
    else if (t === "c") p.cmd = v;
    else if (t === "n" && p.cwd === null) p.cwd = v;
  }
  // A listing without this very process saw too little to clear anyone.
  if (!procs.some((x) => x.pid === process.pid)) return { broken: true, why: "lsof did not list this hook's own process" };
  return { broken: false, procs: procs, child: r.pid };
}

function decide(cmd, cwd) {
  if (!PREFILTER.test(cmd)) return;
  const r = newResult();
  lex(cmd, 0, null, 0, r);
  const targets = [];
  collect(r, cwd, 0, targets);
  if (targets.length === 0) return;
  matched = targets[0].path;
  const ls = listProcs();
  if (ls.broken) denyBlind(ls.why);
  const child = ls.child;
  const isSelf = (p) => p.pid === process.pid || p.pid === child || p.ppid === process.pid || (p.pid === process.ppid && SHELLS.includes(base(p.cmd).replace(/^-/, "")));
  const byPid = new Map(ls.procs.map((p) => [p.pid, p]));
  const held = [];
  for (const p of ls.procs) {
    if (p.cwd === null || isSelf(p)) continue;
    const t = targets.find((x) => holds(x, p.cwd));
    if (t !== undefined) held.push({ p: p, t: t });
  }
  if (held.length === 0) return;
  const show = held.slice(0, 5).map((h) => {
    const parent = byPid.get(h.p.ppid);
    return "pid " + h.p.pid + " " + safe(h.p.cmd) + " (parent " + h.p.ppid + (parent ? " " + safe(parent.cmd) : "") + ") in " + safe(h.p.cwd);
  });
  const more = held.length > 5 ? " and " + (held.length - 5) + " more" : "";
  const how = held[0].t.kind === "rm" ? "rm -r" : "git worktree remove";
  deny("BLOCKED: `" + how + "` would delete " + safe(held[0].t.path) + ", the working directory of a live process: " + show.join("; ") + more + ". Removing it pulls the tree from under that process (a Claude agent in its worktree, a dev server). It may only go once they have exited. " + STOP);
}

let input = "";
let overflow = false;
let ran = false;

function main() {
  let data;
  try { data = JSON.parse(input); } catch { allow(); return; }
  if (!data || typeof data !== "object" || Array.isArray(data)) { allow(); return; }
  if (data.tool_name !== undefined && data.tool_name !== "Bash") { allow(); return; }
  const ti = data.tool_input;
  const cmd = ti && typeof ti === "object" && !Array.isArray(ti) ? ti.command : undefined;
  if (typeof cmd !== "string") { allow(); return; }
  const cwd = typeof data.cwd === "string" && path.isAbsolute(data.cwd) ? data.cwd : process.cwd();
  decide(cmd, cwd);
  allow();
}

function start() {
  if (ran) return;
  ran = true;
  // Never parse a truncated prefix: input not fully read is allowed.
  if (overflow) { allow(); return; }
  try {
    main();
  } catch (e) {
    if (matched !== null) denyBlind("the hook failed: " + safe(e && e.message));
    allow();
  }
  if (matched !== null) denyBlind("the hook reached no decision");
  allow();
}

process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => {
  if (overflow) return;
  if (input.length + c.length > MAX_INPUT) { overflow = true; input = ""; return; }
  input += c;
});
process.stdin.on("end", start);
process.stdin.on("error", start);
