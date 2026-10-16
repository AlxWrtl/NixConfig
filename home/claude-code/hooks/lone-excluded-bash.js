#!/usr/bin/env node
"use strict";

// The sandbox-excluded commands (settings.nix excludedCommands: git
// push/commit/pull/fetch, gh, claude-dispatch, claude-bg) leave the sandbox only when
// the Bash call is made of them alone. `cd x && git push`, `git -C x push`, a
// pipe, `$(...)`, a heredoc or a file redirection keep the WHOLE call
// sandboxed, where the keychain and ~/.ssh are denied: the network or signing
// step fails (x509, no SSH key; EPERM on ~/.claude/jobs for claude-dispatch,
// a dead daemon socket for claude-bg)
// and the retry turns into a permission prompt. Refusing that
// shape up front, with the fix in the reason, costs one retry instead.
//
// A workflow hook, not a barrier: it FAILS OPEN. Unreadable input, a throw,
// the watchdog, an input past its cap and a command the lexer cannot read
// all allow, silently.

const fs = require("fs");

const BUDGET_MS = 3000;
const MAX_INPUT = 4 * 1024 * 1024;
// Nesting of $(...), backticks, subshells and `bash -c` strings. Past it the
// command is not read at all: an allow.
const MAX_DEPTH = 8;
const VERBS = ["push", "commit", "pull", "fetch"];
// Run the word after them (and their options) as the command. Their
// unsandboxing is undocumented, so a target behind one is never clean.
const WRAPPERS = ["env", "command", "builtin", "exec", "nohup", "nice", "timeout", "gtimeout", "sudo", "doas", "time", "stdbuf", "xargs", "caffeinate", "noglob", "rtk"];
// Wrapper options that take their value as the NEXT word (`sudo -u alx`):
// skipping only the option would read its value as the command.
const TIMEOUT_ARG_OPTS = ["-s", "--signal", "-k", "--kill-after"];
const WRAPPER_ARG_OPTS = {
  env: ["-u", "--unset", "-C", "--chdir"],
  timeout: TIMEOUT_ARG_OPTS,
  gtimeout: TIMEOUT_ARG_OPTS,
  sudo: ["-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt", "-C", "--close-from", "-D", "--chdir", "-r", "--role", "-t", "--type", "-U", "--other-user", "-T", "--command-timeout", "-R", "--chroot"],
  doas: ["-u", "-C"],
  nice: ["-n", "--adjustment"],
  time: ["-f", "--format", "-o", "--output"],
  stdbuf: ["-i", "-o", "-e", "--input", "--output", "--error"],
  xargs: ["-I", "-a", "-d", "-E", "-L", "-n", "-P", "-s", "--arg-file", "--delimiter", "--max-args", "--max-procs", "--max-lines", "--max-chars"],
  caffeinate: ["-t", "-w"]
};
// `command -v gh` / `command -V git` look the name up, they do not run it.
const COMMAND_LOOKUP = /^-[pvV]*[vV][pvV]*$/;
const KEYWORDS = ["if", "then", "else", "elif", "do", "while", "until", "!", "{", "}"];
const SHELLS = ["sh", "bash", "zsh", "dash", "ksh"];
// git global options that take their value as the NEXT word.
const GIT_ARG_OPTS = ["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"];
// Cheap gate: no `git`, `gh`, `claude-dispatch` or `claude-bg` word anywhere,
// nothing to lex.
const PREFILTER = /\bg(?:it|h)\b|\bclaude-(?:dispatch|bg)\b/;
const ASSIGN = /^[A-Za-z_][A-Za-z0-9_]*=/;

const CAUSE = {
  subst: "with a command substitution ($(...), backticks, <(...)) in the call",
  heredoc: "with a heredoc or here-string",
  redir: "with a file redirection (only fd duplication like 2>&1 is kept)",
  group: "inside a subshell or a { } group",
  background: "sent to the background with &",
  shape: "next to another command or behind a prefix (cd &&, a pipe, ;, git -C / -c, VAR=, a wrapper, an absolute path, a quoted verb)"
};

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

// Thrown where the shell text cannot be read with confidence; the caller
// turns it into an allow.
class Unreadable extends Error {}

function newResult() {
  return { segs: [[]], inner: [], subst: false, heredoc: false, fileRedir: false, group: false, background: false };
}

// Heredoc bodies start at the newline after their operator, in operator
// order. A body without its delimiter runs to the end of the input, as the
// shell reads it. An UNQUOTED delimiter expands $(...) and backticks in
// its body; a quoted one (<<'EOF', <<"EOF", <<\EOF) keeps it literal.
function bodies(s, i, pending, depth, r) {
  const n = s.length;
  while (pending.length) {
    const h = pending.shift();
    const start = i;
    let end = n;
    while (i < n) {
      let e = s.indexOf("\n", i);
      if (e < 0) e = n;
      let line = s.slice(i, e);
      if (h.tabs) line = line.replace(/^\t+/, "");
      const at = i;
      i = e < n ? e + 1 : n;
      if (line === h.delim) { end = at; break; }
    }
    if (!h.quoted) bodySubst(s.slice(start, end), depth, r);
  }
  return i;
}

// The substitutions of an unquoted heredoc body; quotes there are literal.
// A body the lexer cannot read adds nothing: the heredoc flag still stands.
function bodySubst(b, depth, r) {
  const sub = (inner) => {
    r.subst = true;
    r.inner.push(inner);
  };
  try {
    let j = 0;
    while (j < b.length) {
      const c = b[j];
      if (c === "\\") { j += 2; continue; }
      if (c === "$" && b[j + 1] === "(") {
        const inner = newResult();
        j = lex(b, j + 2, ")", depth + 1, inner);
        sub(inner);
        continue;
      }
      if (c === "`") { j = backtick(b, j, depth, sub); continue; }
      j++;
    }
  } catch (e) {
    if (!(e instanceof Unreadable)) throw e;
  }
}

// Quote-aware scan of s from i into r: words grouped into segments (cut on
// && || ; | |& & and newline), plus the shape flags. `closer` ")" stops on
// the unquoted `)` that ends a $(...) / (...) body and returns past it.
// Word: { val, plain } — `plain` means no quote, escape, `$` or
// substitution went into it, so `git "push"` and `g\it` are not plain.
function lex(s, i, closer, depth, r) {
  if (depth > MAX_DEPTH) throw new Unreadable("nesting too deep");
  const n = s.length;
  const pending = [];
  let word = null;
  let operand = null;
  const seg = () => r.segs[r.segs.length - 1];
  const add = (text, plain) => {
    if (word === null) word = { val: "", plain: true };
    word.val += text;
    if (!plain) word.plain = false;
  };
  const sub = (inner) => {
    r.subst = true;
    r.inner.push(inner);
    add("\u0000", false);
  };
  const redirect = (op, w) => {
    if (op === "<<<") return;
    const dup = (op === ">&" || op === "<&") && /^(?:[0-9]+-?|-)$/.test(w.val);
    if (!dup) r.fileRedir = true;
  };
  const endWord = () => {
    if (word === null) return;
    if (operand !== null) { redirect(operand, word); operand = null; word = null; return; }
    if (word.plain && (word.val === "{" || word.val === "}") && seg().length === 0) r.group = true;
    seg().push(word);
    word = null;
  };
  const endSeg = () => {
    endWord();
    if (operand !== null) { r.fileRedir = true; operand = null; }
    if (seg().length) r.segs.push([]);
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
      if (pending.length) i = bodies(s, i, pending, depth, r);
      continue;
    }
    if (ch === "#" && word === null) {
      const e = s.indexOf("\n", i);
      i = e < 0 ? n : e;
      continue;
    }
    if (ch === "\\") {
      if (s[i + 1] === "\n") { i += 2; continue; }
      add(s.slice(i + 1, i + 2), false);
      i += 2;
      continue;
    }
    if (ch === "'") {
      const e = s.indexOf("'", i + 1);
      if (e < 0) throw new Unreadable("unbalanced '");
      add(s.slice(i + 1, e), false);
      i = e + 1;
      continue;
    }
    if (ch === "$" && s[i + 1] === "'") {
      let j = i + 2;
      while (j < n && s[j] !== "'") j += s[j] === "\\" ? 2 : 1;
      if (j >= n) throw new Unreadable("unbalanced $'");
      add(s.slice(i + 2, j), false);
      i = j + 1;
      continue;
    }
    if (ch === '"') {
      let j = i + 1;
      let text = "";
      for (;;) {
        if (j >= n) throw new Unreadable("unbalanced \"");
        const c = s[j];
        if (c === '"') { j++; break; }
        if (c === "\\") { text += s.slice(j + 1, j + 2); j += 2; continue; }
        if (c === "$" && s[j + 1] === "(") {
          add(text, false); text = "";
          const inner = newResult();
          j = lex(s, j + 2, ")", depth + 1, inner);
          sub(inner);
          continue;
        }
        if (c === "`") {
          add(text, false); text = "";
          j = backtick(s, j, depth, sub);
          continue;
        }
        text += c;
        j++;
      }
      add(text, false);
      i = j;
      continue;
    }
    if (ch === "`") { i = backtick(s, i, depth, sub); continue; }
    if ((ch === "$" || ch === "<" || ch === ">") && s[i + 1] === "(") {
      const inner = newResult();
      i = lex(s, i + 2, ")", depth + 1, inner);
      sub(inner);
      continue;
    }
    if (ch === "(") {
      endWord();
      r.group = true;
      const inner = newResult();
      i = lex(s, i + 1, ")", depth + 1, inner);
      r.inner.push(inner);
      continue;
    }
    if (ch === "<" && s[i + 1] === "<" && s[i + 2] !== "<") {
      endWord();
      r.heredoc = true;
      let k = i + 2;
      const tabs = s[k] === "-";
      if (tabs) k++;
      while (s[k] === " " || s[k] === "\t") k++;
      const m = /^[^\s;&|<>()]+/.exec(s.slice(k, k + 4096));
      if (m === null) throw new Unreadable("heredoc without a delimiter");
      const delim = m[0].replace(/['"\\]/g, "");
      if (delim === "") throw new Unreadable("empty heredoc delimiter");
      pending.push({ delim: delim, tabs: tabs, quoted: delim !== m[0] });
      i = k + m[0].length;
      continue;
    }
    if (ch === "<" || ch === ">" || (ch === "&" && s[i + 1] === ">")) {
      // An all-digit word glued to the operator is its fd number (2>x).
      if (word !== null && word.plain && /^[0-9]+$/.test(word.val)) word = null;
      endWord();
      const two = s.slice(i, i + 2);
      let op = ch;
      if (s.startsWith("<<<", i)) { op = "<<<"; r.heredoc = true; }
      else if (s.startsWith("&>>", i)) op = "&>>";
      else if (["&>", ">>", ">&", "<&", ">|", "<>"].includes(two)) op = two;
      operand = op;
      i += op.length;
      continue;
    }
    if (ch === ";") { endSeg(); i += s[i + 1] === ";" ? 2 : 1; continue; }
    if (ch === "|") { endSeg(); i += s[i + 1] === "|" || s[i + 1] === "&" ? 2 : 1; continue; }
    if (ch === "&") {
      if (s[i + 1] === "&") { endSeg(); i += 2; continue; }
      r.background = true;
      endSeg();
      i++;
      continue;
    }
    add(ch, ch !== "$");
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

const base = (v) => v.slice(v.lastIndexOf("/") + 1);

// The excluded commands a segment runs, through prefixes, wrappers,
// keywords and `sh -c` / eval strings. Detection reads the dequoted value:
// `git "push"` IS a push, it is just not a clean one.
function segTargets(words, depth) {
  let k = 0;
  while (k < words.length) {
    const v = words[k].val;
    if (ASSIGN.test(v) || KEYWORDS.includes(v)) { k++; continue; }
    const w = base(v);
    if (WRAPPERS.includes(w)) {
      const opts = WRAPPER_ARG_OPTS[w] || [];
      k++;
      while (k < words.length) {
        const o = words[k].val;
        if (w === "command" && COMMAND_LOOKUP.test(o)) return [];
        if (opts.includes(o)) { k += 2; continue; }
        if (/^-/.test(o) || /^[0-9.]+[smhd]?$/.test(o) || ASSIGN.test(o)) { k++; continue; }
        break;
      }
      continue;
    }
    break;
  }
  if (k >= words.length) return [];
  const cmd = base(words[k].val);
  if (cmd === "gh") return ["gh"];
  if (cmd === "claude-dispatch" || cmd === "claude-bg") return [cmd];
  if (cmd === "git") {
    let j = k + 1;
    while (j < words.length) {
      const v = words[j].val;
      if (GIT_ARG_OPTS.includes(v)) { j += 2; continue; }
      if (v.startsWith("-")) { j++; continue; }
      return VERBS.includes(v) ? ["git " + v] : [];
    }
    return [];
  }
  let code = null;
  if (cmd === "eval") code = words.slice(k + 1).map((w) => w.val).join(" ");
  if (SHELLS.includes(cmd)) {
    const c = words.findIndex((w, x) => x > k && /^-[A-Za-z]*c[A-Za-z]*$/.test(w.val));
    if (c > 0 && c + 1 < words.length) code = words[c + 1].val;
  }
  if (code === null) return [];
  const inner = newResult();
  lex(code, 0, null, depth + 1, inner);
  return targetsOf(inner, depth + 1);
}

function targetsOf(r, depth) {
  const out = [];
  for (const words of r.segs) out.push(...segTargets(words, depth));
  for (const inner of r.inner) out.push(...targetsOf(inner, depth + 1));
  return out;
}

// Clean = what an excludedCommands entry matches: `git` then the verb, or
// `gh` / `claude-dispatch` / `claude-bg`, literal words at the head of the
// segment.
function isCleanTarget(words) {
  const w0 = words[0];
  const w1 = words[1];
  if (w0 === undefined || !w0.plain) return false;
  if (w0.val === "gh" || w0.val === "claude-dispatch" || w0.val === "claude-bg") return true;
  return w0.val === "git" && w1 !== undefined && w1.plain && VERBS.includes(w1.val);
}

// The first reason the call stays sandboxed, or null when it leaves it.
// A chain made ONLY of clean targets leaves it (user decision 2026-10-11).
function causeOf(r, segs) {
  if (r.subst) return CAUSE.subst;
  if (r.heredoc) return CAUSE.heredoc;
  if (r.fileRedir) return CAUSE.redir;
  if (r.group) return CAUSE.group;
  if (r.background) return CAUSE.background;
  if (!segs.every(isCleanTarget)) return CAUSE.shape;
  return null;
}

function decide(cmd) {
  if (!PREFILTER.test(cmd)) return null;
  const r = newResult();
  lex(cmd, 0, null, 0, r);
  const found = targetsOf(r, 0);
  if (found.length === 0) return null;
  const cause = causeOf(r, r.segs.filter((w) => w.length > 0));
  return cause === null ? null : { target: found[0], cause: cause };
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
  let v;
  try { v = decide(cmd); } catch { allow(); return; }
  if (v === null) { allow(); return; }
  deny("BLOCKED: `" + safe(v.target) + "` leaves the sandbox only when the Bash call is that command alone; here it runs " + v.cause + ", so the whole call stays sandboxed and its network or signing step fails. Run it ALONE in its own Bash call, from the project root: the cwd resets after each call, so neither cd nor git -C can help, and a repo outside the project root has no unsandboxed form (let the sandboxed call fail, then answer the permission prompt). Pass a message by file (git commit -F <file>, gh ... --body-file <file>), filter gh output with --jq instead of a pipe. Give claude-dispatch its brief inline as one quoted line, never through $(...) or a file. Give claude-bg its id as a plain word. Lone git push/commit/pull/fetch, gh, claude-dispatch and claude-bg commands may still be joined with &&.");
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
