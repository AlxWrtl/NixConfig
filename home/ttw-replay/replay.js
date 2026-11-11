#!/usr/bin/env node
// Weekly replay of the TTW stale-step hook (~/.claude/hooks/ttw-flags.js)
// against the real transcripts. Read-only on the transcripts.
//
// For every Skill(ttw) call of every `*/*.jsonl` under REPLAY_PROJECTS
// (sidechain entries skipped), the transcript cut before the call is written
// into a fake HOME (a mktemp dir holding a copy of REPLAY_STEPS and a
// current-home gcroot link dated 1 s before the call), and the hook is run on
// it with HOME = that fake HOME. Only the hook line building its path regexes
// keeps REPLAY_REALHOME, the home spelled in the transcripts. The step files
// the hook names are scored per (call, file) against an oracle that walks the
// file's reads before the call in order: a whole read sets stale from an exact
// comparison, a capture holding the whole current file clears it, a partial
// read marks it unless its lines are the current slice of its printed range,
// a contiguous block of the file now, or (grep) lines of the file now. No read
// showing text: nocontent (fp when the hook names it).
//
// Env: REPLAY_PROJECTS, REPLAY_STEPS, REPLAY_HOOK, REPLAY_REALHOME, REPLAY_OUT,
// REPLAY_DATE (YYYY-MM-DD), REPLAY_RECENT_DAYS. Writes REPLAY_OUT/<date>.json
// and .md, or <date>-2.* and on when taken, never overwriting. Any error: one
// stderr line, exit 1, nothing written; the fake HOME is always removed.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const HOME = os.homedir();
const env = process.env;
const PROJECTS = env.REPLAY_PROJECTS || path.join(HOME, ".claude/projects");
const STEPS = env.REPLAY_STEPS || path.join(HOME, ".claude/skills/ttw/steps");
const HOOK = env.REPLAY_HOOK || path.join(HOME, ".claude/hooks/ttw-flags.js");
const REALHOME = env.REPLAY_REALHOME || HOME;
const OUT = env.REPLAY_OUT || path.join(HOME, ".local/share/ttw-replay");
const HOOK_LINE = "try { STEP_RE = stepRe(os.homedir());";
const HOOK_TIMEOUT_MS = 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_EXAMPLES = 20;

function today() {
  const d = new Date();
  const p = n => String(n).padStart(2, "0");
  return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
}

function settings() {
  const date = env.REPLAY_DATE || today();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("REPLAY_DATE is not YYYY-MM-DD: " + date);
  const days = Number(env.REPLAY_RECENT_DAYS === undefined ? "7" : env.REPLAY_RECENT_DAYS);
  if (!Number.isFinite(days) || days < 0) throw new Error("REPLAY_RECENT_DAYS is not a non-negative number");
  return { date, days };
}

// ---- the hook, with its regex line keeping the real home ----
function patchedHook(src) {
  const lines = src.split("\n");
  const k = lines.findIndex(l => l.startsWith(HOOK_LINE));
  if (k < 0) throw new Error("hook line '" + HOOK_LINE + "' not found in " + HOOK);
  lines[k] = lines[k].split("os.homedir()").join(JSON.stringify(REALHOME));
  return lines.join("\n");
}

// ---- step names, as the hook spells them ----
function homeAlt(home) {
  const alts = ["~", "\\$HOME", "\\$\\{HOME\\}"];
  const h = home.replace(/\/+$/, "");
  if (h !== "") alts.push(h.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&"));
  return "(?:" + alts.join("|") + ")";
}
const HOME_ALT = homeAlt(REALHOME);
function stepRe() {
  return new RegExp("(?<=^|[\\s'\"=(<;|&])" + HOME_ALT
    + "\\/\\.claude\\/skills\\/ttw\\/steps\\/([A-Za-z0-9][A-Za-z0-9._-]*\\.md)(?![A-Za-z0-9._-])", "g");
}
// Same cd rule as the hook: `cd` at a word start (after whitespace, ;&|( or
// the line start), its target one word equal to the home steps dir, optionally
// quoted, optional `/`; bare names resolved up to the next `cd`.
const CD_RE = /(?<![^\s;&|(])cd(?:[ \t]+([^\s;&|)]+))?(?![^\s;&|)])/g;
const CD_DIR_RE = new RegExp("^(['\"]?)" + HOME_ALT + "\\/\\.claude\\/skills\\/ttw\\/steps\\/?\\1$");
const BARE_RE = /(?<=^|[\s'"=(<;|&])([A-Za-z0-9][A-Za-z0-9._-]*\.md)(?![A-Za-z0-9._-])/g;
const PATH_RE = new RegExp(HOME_ALT + "\\/\\S+", "g");
const STATEMENT_SEPS = ["\n", "&&", "||", ";"];
const PIPE_SEPS = ["|"];

// `s` cut at each separator outside single or double quotes (backslash
// escapes honoured outside single quotes). A newline closes any open quote, so
// an apostrophe in a heredoc body cannot swallow the following lines.
function splitTop(s, seps) {
  const out = [];
  let cur = "";
  let q = null;
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === "\n") q = null;
    if (q !== null) {
      cur += ch;
      if (ch === q) q = null;
      else if (ch === "\\" && q === '"' && i + 1 < s.length && s[i + 1] !== "\n") cur += s[++i];
      continue;
    }
    if (ch === "'" || ch === '"') { q = ch; cur += ch; continue; }
    if (ch === "\\" && i + 1 < s.length && s[i + 1] !== "\n") { cur += ch + s[++i]; continue; }
    const sep = seps.find(t => s.startsWith(t, i));
    if (sep !== undefined) { out.push(cur); cur = ""; i += sep.length - 1; continue; }
    cur += ch;
  }
  out.push(cur);
  return out;
}

function names(text) {
  const re = stepRe();
  const s = new Set();
  let m;
  while ((m = re.exec(text)) !== null) s.add(m[1]);
  return [...s];
}
function namesStep(text, name) {
  return names(text).includes(name);
}

// ---- how a Bash command shows one step file ----
const NO_CONTENT = new Set(["ls", "wc", "readlink/stat", "grep no-text"]);
const FULL = new Set(["Read", "cat"]);
const LATE_FILTERS = ["head", "tail", "grep", "rg", "egrep", "sed", "wc"];
const GREPS = ["grep", "rg", "egrep"];

function stageCmd(stage) {
  const w = stage.trim().split(/\s+/).filter(x => !/^[A-Z_][A-Z0-9_]*=/.test(x));
  while (w.length && ["rtk", "command", "sudo", "env", "time", "do", "then"].includes(w[0])) w.shift();
  return w.length ? path.basename(w[0]) : "";
}
function mapCmd(c, stage) {
  switch (c) {
    case "cat": case "bat": return "cat";
    case "head": return "head";
    case "tail": return "tail";
    case "sed":
      if (/-n\s+['"]?\d+,\d+p/.test(stage)) return "sed -n A,Bp";
      if (/\/[^/]*\//.test(stage.replace(PATH_RE, ""))) return "sed regex";
      return "other";
    case "grep": case "rg": case "egrep":
      return /\s-[A-Za-z]*[clLq]/.test(stage) ? "grep no-text" : "grep";
    case "ls": return "ls";
    case "wc": return "wc";
    case "readlink": case "realpath": case "stat": case "test": case "[": case "file": return "readlink/stat";
    default: return "other";
  }
}
// The form of one statement for `name`, or null when it does not name it.
function classifyOne(statement, name) {
  const stages = splitTop(statement, PIPE_SEPS);
  for (let i = 0; i < stages.length; i++) {
    if (!namesStep(stages[i], name)) continue;
    let c = stageCmd(stages[i]);
    let stage = stages[i];
    if (c === "for" || c === "while") return "other";
    // A later filter stage decides what reaches stdout.
    for (let k = stages.length - 1; k > i; k--) {
      const f = stageCmd(stages[k]);
      if (LATE_FILTERS.includes(f)) { c = f; stage = stages[k]; break; }
    }
    // Lines that went through a grep are grep lines, whatever filter follows
    // (`grep -n X F | head -3`), unless that filter shows no text (`| wc`).
    if (!NO_CONTENT.has(mapCmd(c, stage))) {
      for (let k = stages.length - 1; k >= i; k--) {
        if (GREPS.includes(stageCmd(stages[k]))) return mapCmd("grep", stages[k]);
      }
    }
    return mapCmd(c, stage);
  }
  return null;
}
// A file shown by any statement takes that statement's form.
function classifyBash(cmd, name) {
  const forms = splitTop(cmd, STATEMENT_SEPS).map(st => classifyOne(st, name)).filter(f => f !== null);
  return forms.find(f => !NO_CONTENT.has(f)) || forms[0] || "other";
}
// Line ranges printed for `name` (head -N, sed -n A,Bp, from its stage on).
function rangesFor(cmd, name) {
  const out = [];
  for (const st of splitTop(cmd, STATEMENT_SEPS)) {
    const stages = splitTop(st, PIPE_SEPS);
    const i = stages.findIndex(s => namesStep(s, name));
    if (i < 0) continue;
    const tail = stages.slice(i).join("|");
    const H = /(?<![\w.-])head\s+-(?:n\s*)?(\d+)(?!\w)/g;
    const D = /(?<![\w.-])sed\s+-n\s+(['"]?)(\d+),(\d+)p\1(?!\w)/g;
    let m;
    while ((m = H.exec(tail)) !== null) out.push([1, Number(m[1])]);
    while ((m = D.exec(tail)) !== null) out.push([Number(m[2]), Number(m[3])]);
  }
  return out;
}
// The Bash text with each bare `NAME.md` after a `cd` into the home steps dir,
// up to the next `cd`, spelled ~/.claude/skills/ttw/steps/NAME.md.
function resolveCd(cmd) {
  const fix = (seg, on) => (on ? seg.replace(BARE_RE, "~/.claude/skills/ttw/steps/$1") : seg);
  const re = new RegExp(CD_RE.source, "g");
  let out = "";
  let from = 0;
  let on = false;
  let m;
  while ((m = re.exec(cmd)) !== null) {
    out += fix(cmd.slice(from, m.index), on) + m[0];
    from = m.index + m[0].length;
    on = m[1] !== undefined && CD_DIR_RE.test(m[1]);
  }
  return out + fix(cmd.slice(from), on);
}

// ---- one transcript: step reads (with their capture) and Skill(ttw) calls ----
function parse(file) {
  const lines = fs.readFileSync(file, "utf8").split("\n");
  const reads = [];
  const byId = new Map();
  const skills = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!line || !(line.includes("ttw") || line.includes("tool_use_id"))) continue;
    let e;
    try { e = JSON.parse(line); } catch (x) { continue; }
    if (!e || typeof e !== "object" || e.isSidechain === true) continue;
    const content = e.message && Array.isArray(e.message.content) ? e.message.content : null;
    if (e.type === "assistant" && content) {
      const ts = Date.parse(e.timestamp);
      for (const c of content) {
        if (!c || c.type !== "tool_use") continue;
        const inp = c.input || {};
        if (c.name === "Skill" && inp.skill === "ttw") { skills.push({ ts, line: i }); continue; }
        let t = null;
        if (c.name === "Read") t = inp.file_path;
        else if (c.name === "Bash") t = inp.command;
        if (typeof t !== "string") continue;
        const text = c.name === "Bash" ? resolveCd(t) : t;
        const ns = names(text);
        if (ns.length === 0) continue;
        const group = [];
        for (const n of ns) {
          let form;
          if (c.name === "Read") form = (inp.offset != null || inp.limit != null) ? "Read partial" : "Read";
          else form = classifyBash(text, n);
          const r = { name: n, kind: c.name, form, cmd: text, cap: null, err: false, line: i };
          reads.push(r);
          group.push(r);
        }
        byId.set(c.id, group);
      }
    } else if (e.type === "user") {
      for (const c of content || []) {
        if (!c || c.type !== "tool_result" || !byId.has(c.tool_use_id)) continue;
        const g = byId.get(c.tool_use_id);
        const tur = e.toolUseResult;
        let cap = null;
        if (typeof tur === "string") cap = tur;
        else if (tur && typeof tur === "object") {
          if (g[0].kind === "Read" && tur.file && typeof tur.file.content === "string") cap = tur.file.content;
          else if (g[0].kind === "Bash" && typeof tur.stdout === "string") cap = tur.stdout;
        }
        for (const r of g) { r.cap = cap; r.err = c.is_error === true; }
      }
    }
  }
  for (const r of reads) if (r.err) r.form = "error";
  return { lines, reads, skills };
}

// ---- oracle: is a stale copy of `name` the one in force? ----
function fullStale(r, now) {
  if (typeof r.cap !== "string") return false;
  if (r.kind === "Read") return r.cap.trimEnd() !== now.trimEnd();
  return !r.cap.includes(now.trimEnd());
}
function stripLine(l) {
  return l.replace(/^\/\S+?\.md[:-]/, "").replace(/^\s*\d+[\t:-]/, "");
}
function partialCurrent(r, now) {
  if (typeof r.cap !== "string") return null;
  const raw = r.cap.split("\n").filter(l => l.trim() !== "" && !/^(Exit code|Error:)/.test(l));
  if (raw.length === 0) return null;
  const set = new Set(now.split("\n"));
  if (r.form === "grep") return raw.every(l => set.has(l) || set.has(stripLine(l)));
  // The exact current slice of a printed range is shown: current.
  const nl = now.split("\n");
  if (r.kind === "Bash") {
    for (const [a, b] of rangesFor(r.cmd, r.name)) {
      const slice = nl.slice(a - 1, b).join("\n").trimEnd();
      if (slice.trim() !== "" && r.cap.includes(slice)) return true;
    }
  }
  const block = ls => now.includes(ls.join("\n")) || now.replace(/\n\n+/g, "\n").includes(ls.join("\n"));
  return block(raw) || block(raw.map(stripLine));
}
// true stale, false current, null no read showed text.
function truth(name, reads, steps) {
  const now = steps.get(name);
  let stale = false;
  let seen = false;
  for (const r of reads) {
    if (r.name !== name || NO_CONTENT.has(r.form) || r.cap === null) continue;
    seen = true;
    if (FULL.has(r.form) || r.form === "error") { stale = fullStale(r, now); continue; }
    // Whatever its shape, a capture holding the whole current file is a whole current copy.
    if (r.cap.includes(now.trimEnd())) { stale = false; continue; }
    if (partialCurrent(r, now) === false) stale = true;
  }
  return seen ? stale : null;
}

// ---- inputs ----
function readSteps() {
  const steps = new Map();
  for (const f of fs.readdirSync(STEPS).sort()) {
    const p = path.join(STEPS, f);
    if (fs.statSync(p).isFile()) steps.set(f, fs.readFileSync(p, "utf8"));
  }
  if (steps.size === 0) throw new Error("no step file in " + STEPS);
  return steps;
}
function listTranscripts() {
  const files = [];
  for (const d of fs.readdirSync(PROJECTS, { withFileTypes: true })) {
    if (!d.isDirectory()) continue;
    const dir = path.join(PROJECTS, d.name);
    for (const f of fs.readdirSync(dir, { withFileTypes: true })) {
      if (f.isFile() && f.name.endsWith(".jsonl")) files.push(path.join(dir, f.name));
    }
  }
  return files.sort();
}

// ---- fake HOME and one hook run ----
function makeFakeHome(tmp, steps, hookSrc) {
  const stepsDir = path.join(tmp, ".claude/skills/ttw/steps");
  const gc = path.join(tmp, ".local/state/home-manager/gcroots");
  fs.mkdirSync(stepsDir, { recursive: true });
  fs.mkdirSync(gc, { recursive: true });
  for (const [n, t] of steps) fs.writeFileSync(path.join(stepsDir, n), t);
  const link = path.join(gc, "current-home");
  fs.symlinkSync("/nonexistent-generation", link);
  const hook = path.join(tmp, "ttw-flags.js");
  fs.writeFileSync(hook, hookSrc);
  return { home: tmp, link, hook, cut: path.join(tmp, "cut.jsonl") };
}
const NAMED_RE = /TTW steps changed since read: (.*?)\. Re-read/;
function runHook(fake, actMs) {
  const s = actMs / 1000;
  fs.lutimesSync(fake.link, s, s);
  const out = cp.execFileSync(process.execPath, [fake.hook], {
    input: JSON.stringify({ tool_input: { skill: "ttw" }, transcript_path: fake.cut }),
    env: { ...env, HOME: fake.home },
    encoding: "utf8",
    timeout: HOOK_TIMEOUT_MS,
  });
  let parsed;
  try { parsed = JSON.parse(out); } catch (e) { throw new Error("hook printed non-JSON: " + JSON.stringify(out.slice(0, 120)), { cause: e }); }
  const ctx = parsed && parsed.hookSpecificOutput && parsed.hookSpecificOutput.additionalContext;
  if (typeof ctx !== "string") throw new Error("hook output has no additionalContext: " + out.slice(0, 120));
  const m = ctx.match(NAMED_RE);
  return m ? m[1].split(", ") : [];
}

// ---- report ----
function zero() { return { vp: 0, fp: 0, miss: 0, vn: 0, nocontent: 0 }; }
function writeReport(report) {
  fs.mkdirSync(OUT, { recursive: true });
  for (let n = 1; ; n++) {
    const base = path.join(OUT, n === 1 ? report.date : report.date + "-" + n);
    if (fs.existsSync(base + ".json") || fs.existsSync(base + ".md")) continue;
    fs.writeFileSync(base + ".json", JSON.stringify(report, null, 1) + "\n", { flag: "wx" });
    fs.writeFileSync(base + ".md", markdown(report), { flag: "wx" });
    return base;
  }
}
function markdown(r) {
  const row = (label, c) => "| " + label + " | " + [c.transcripts, c.calls, c.vp, c.fp, c.miss, c.vn, c.nocontent].join(" | ") + " |";
  const L = [
    "# TTW stale-step replay " + r.date,
    "",
    "Hook: `" + r.hook + "`",
    "",
    "| scope | transcripts | calls | vp | fp | miss | vn | nocontent |",
    "|---|---|---|---|---|---|---|---|",
    row("all", { transcripts: r.transcripts, calls: r.calls, ...r.all }),
    row("recent", r.recent),
    "",
    "## Examples (fp, miss)",
    "",
  ];
  if (r.examples.length === 0) L.push("None.");
  for (const x of r.examples) L.push("- " + x.kind + " `" + x.file + "` in `" + x.transcript + "`: " + x.forms.join(" > "));
  return L.join("\n") + "\n";
}

function main() {
  const { date, days } = settings();
  const hookSrc = patchedHook(fs.readFileSync(HOOK, "utf8"));
  const steps = readSteps();
  const files = listTranscripts();
  const nowMs = Date.now();
  const all = zero();
  const recent = { transcripts: 0, calls: 0, ...zero() };
  const examples = [];
  let calls = 0;
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "ttw-replay-"));
  try {
    const fake = makeFakeHome(tmp, steps, hookSrc);
    for (const file of files) {
      const isRecent = nowMs - fs.statSync(file).mtimeMs <= days * DAY_MS;
      if (isRecent) recent.transcripts++;
      const P = parse(file);
      const rel = path.relative(PROJECTS, file);
      for (const s of P.skills) {
        if (!Number.isFinite(s.ts)) continue;
        calls++;
        if (isRecent) recent.calls++;
        fs.writeFileSync(fake.cut, P.lines.slice(0, s.line).join("\n") + "\n");
        const named = runHook(fake, s.ts - 1000);
        const before = P.reads.filter(r => r.line < s.line);
        for (const n of new Set(before.map(r => r.name))) {
          if (!steps.has(n)) continue;
          const t = truth(n, before, steps);
          const hit = named.includes(n);
          const kind = t === null ? (hit ? "fp" : "nocontent")
            : t ? (hit ? "vp" : "miss") : (hit ? "fp" : "vn");
          all[kind]++;
          if (isRecent) recent[kind]++;
          if ((kind === "fp" || kind === "miss") && examples.length < MAX_EXAMPLES) {
            examples.push({ kind, transcript: rel, file: n, forms: before.filter(r => r.name === n).map(r => r.form) });
          }
        }
      }
    }
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  const report = { date, hook: fs.realpathSync(HOOK), transcripts: files.length, calls, all, recent, examples };
  const base = writeReport(report);
  process.stdout.write("ttw-replay: " + base + ".json — " + calls + " calls, vp " + all.vp + ", fp " + all.fp
    + ", miss " + all.miss + ", vn " + all.vn + ", nocontent " + all.nocontent + "\n");
}

try {
  main();
} catch (e) {
  process.stderr.write("ttw-replay: " + (e && e.message ? e.message.split("\n")[0] : String(e)) + "\n");
  process.exitCode = 1;
}
