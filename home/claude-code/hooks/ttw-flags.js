#!/usr/bin/env node
// PreToolUse on Skill: at TTW start, reports the context size and names the
// TTW step files whose copy in context is stale. Nothing else.
//
// Stale steps: a step file under ~/.claude/skills/ttw/steps/ (spelled ~,
// $HOME, ${HOME} or the absolute home) read earlier in this session (a Read,
// or a Bash command naming it, e.g. `cat`, or a bare `NAME.md` after a `cd`
// into that dir, up to the next `cd`) before the last home-manager
// activation (mtime of the current-home gcroot link), whose latest such read
// captured text the file no longer holds, and that no read after the
// activation captured whole. A read after the activation with a partial or
// no capture (`ls`, `sed -n`, a failed Read) is ignored. A Bash capture
// printing a line range (`head -N`, `head -n N`, `sed -n A,Bp`) in the pipe
// stage naming the file or a later stage of that statement (split on newline,
// `;`, `&&`, `||`; quotes not parsed) is current when it holds that slice of
// the file. Such files are listed after the start line so the run re-reads
// them instead of following the old copy. A transcript over 64 MiB is not
// scanned.
//
// It used to classify risk from the BRIEF TEXT and rewrite the flags. Removed
// on 2026-10-07: a 28-line Notification matcher change was forced to
// high-stakes (Codex + Fable) only because the brief said "settings" and
// "hook". Words in a brief are not risk; the diff is. Risk is now decided on
// the diff by `ttw-tier` (SKILL.md tier table). This hook never rewrites the
// call and never decides a permission.
//
// FAIL-OPEN: every error exits 0 (no output, context=unknown, or the start
// line without the stale-step line).
const fs = require("fs");
const os = require("os");

const TAIL = 256 * 1024;
const SCAN_MAX = 64 * 1024 * 1024;
let STEP_RE, CD_DIR_RE;
try { STEP_RE = stepRe(os.homedir()); CD_DIR_RE = cdDirRe(os.homedir()); } catch (e) { STEP_RE = stepRe(""); CD_DIR_RE = cdDirRe(""); }
const RESULT_ID_RE = /"tool_use_id":\s*"([^"]+)"/g;
const HEAD_RE = /(?<![\w.-])head\s+-(?:n\s*)?(\d+)(?!\w)/g;
const SED_RE = /(?<![\w.-])sed\s+-n\s+(['"]?)(\d+),(\d+)p\1(?!\w)/g;
const CD_RE = /(?<![^\s;&|(])cd(?:[ \t]+([^\s;&|)]+))?(?![^\s;&|)])/g;
const BARE_RE = /(?<=^|[\s'"=(<;|&])([A-Za-z0-9][A-Za-z0-9._-]*\.md)(?![A-Za-z0-9._-])/g;
const STATEMENT_RE = /\n|;|&&|\|\|/;

// The home spelled ~, $HOME, ${HOME} or literally, as a regex alternation.
function homeAlt(home) {
  const alts = ["~", "\\$HOME", "\\$\\{HOME\\}"];
  const h = typeof home === "string" ? home.replace(/\/+$/, "") : "";
  if (h !== "") alts.push(h.replace(/[.*+?^${}()|[\]\\\/]/g, "\\$&"));
  return "(?:" + alts.join("|") + ")";
}

// A step name under the home steps dir only: the home at a word start, and
// the name ending at `.md`.
function stepRe(home) {
  return new RegExp("(?<=^|[\\s'\"=(<;|&])" + homeAlt(home)
    + "\\/\\.claude\\/skills\\/ttw\\/steps\\/([A-Za-z0-9][A-Za-z0-9._-]*\\.md)(?![A-Za-z0-9._-])", "g");
}

// A `cd` target that is the home steps dir, optionally quoted, optional `/`.
function cdDirRe(home) {
  return new RegExp("^(['\"]?)" + homeAlt(home) + "\\/\\.claude\\/skills\\/ttw\\/steps\\/?\\1$");
}

// The Bash text with each bare `NAME.md` after a `cd` into the home steps
// dir, up to the next `cd`, spelled ~/.claude/skills/ttw/steps/NAME.md.
function resolveCd(cmd) {
  if (typeof cmd !== "string") return cmd;
  const fix = (seg, on) => on ? seg.replace(BARE_RE, "~/.claude/skills/ttw/steps/$1") : seg;
  let out = "";
  let from = 0;
  let on = false;
  let m;
  CD_RE.lastIndex = 0;
  while ((m = CD_RE.exec(cmd)) !== null) {
    out += fix(cmd.slice(from, m.index), on) + m[0];
    from = m.index + m[0].length;
    on = m[1] !== undefined && CD_DIR_RE.test(m[1]);
  }
  return out + fix(cmd.slice(from), on);
}

function namesStep(text, name) {
  STEP_RE.lastIndex = 0;
  let m;
  while ((m = STEP_RE.exec(text)) !== null) if (m[1] === name) return true;
  return false;
}

// True when a pipeline reading step `name` prints a line range (1-based,
// inclusive) of `now` whose non-blank slice is in `cap`: the range is taken
// from the stage naming the file and the later stages of that statement.
function rangeHit(cmd, name, now, cap) {
  if (typeof cmd !== "string" || typeof cap !== "string") return false;
  const ranges = [];
  for (const st of cmd.split(STATEMENT_RE)) {
    const stages = st.split("|");
    const i = stages.findIndex(s => namesStep(s, name));
    if (i < 0) continue;
    const tail = stages.slice(i).join("|");
    let m;
    HEAD_RE.lastIndex = 0;
    while ((m = HEAD_RE.exec(tail)) !== null) ranges.push([1, Number(m[1])]);
    SED_RE.lastIndex = 0;
    while ((m = SED_RE.exec(tail)) !== null) ranges.push([Number(m[2]), Number(m[3])]);
  }
  const lines = now.split("\n");
  for (const [a, b] of ranges) {
    if (!(a >= 1 && b >= a)) continue;
    const slice = lines.slice(a - 1, b).join("\n").trimEnd();
    if (slice.trim() === "") continue;
    if (cap.includes(slice)) return true;
  }
  return false;
}

function contextTokens(path) {
  if (typeof path !== "string" || path === "") return null;
  let fd;
  try {
    fd = fs.openSync(path, "r");
    const size = fs.fstatSync(fd).size;
    const len = Math.min(size, TAIL);
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, size - len);
    const lines = buf.toString("utf8").split("\n");
    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i];
      if (!line.includes('"usage"')) continue;
      let entry;
      try { entry = JSON.parse(line); } catch (e) { continue; }
      const msg = entry && entry.message;
      const u = msg && msg.usage;
      if (!u || (entry.type !== "assistant" && msg.role !== "assistant")) continue;
      const n = (u.input_tokens || 0) + (u.cache_read_input_tokens || 0)
        + (u.cache_creation_input_tokens || 0);
      return Number.isFinite(n) ? n : null;
    }
    return null;
  } catch (e) {
    return null;
  } finally {
    if (fd !== undefined) { try { fs.closeSync(fd); } catch (e) { /* fail open */ } }
  }
}

// Last home-manager activation (ms), or +Infinity when unknown.
function activationMs(home) {
  try {
    const t = fs.lstatSync(home + "/.local/state/home-manager/gcroots/current-home").mtimeMs;
    return Number.isFinite(t) ? t : Infinity;
  } catch (e) {
    return Infinity;
  }
}

function contentArray(entry) {
  const msg = entry && entry.message;
  return msg && Array.isArray(msg.content) ? msg.content : [];
}

// Step reads in transcript order: { name, ts, id, kind, cmd, cap }.
function stepReads(path) {
  const reads = [];
  const byId = new Map();
  if (fs.statSync(path).size > SCAN_MAX) return reads;
  const lines = fs.readFileSync(path, "utf8").split("\n");
  for (const line of lines) {
    let wanted = line.includes("skills/ttw/steps");
    if (!wanted && byId.size > 0 && line.includes('"tool_use_id"')) {
      RESULT_ID_RE.lastIndex = 0;
      let m;
      while ((m = RESULT_ID_RE.exec(line)) !== null) {
        if (byId.has(m[1])) { wanted = true; break; }
      }
    }
    if (!wanted) continue;
    let entry;
    try { entry = JSON.parse(line); } catch (e) { continue; }
    if (!entry || typeof entry !== "object") continue;
    if (entry.type === "assistant") {
      const ts = Date.parse(entry.timestamp);
      if (!Number.isFinite(ts)) continue;
      for (const c of contentArray(entry)) {
        if (!c || c.type !== "tool_use" || typeof c.id !== "string") continue;
        const inp = c.input || {};
        let text;
        if (c.name === "Read") text = inp.file_path;
        else if (c.name === "Bash") text = resolveCd(inp.command);
        if (typeof text !== "string") continue;
        const names = new Set();
        STEP_RE.lastIndex = 0;
        let m;
        while ((m = STEP_RE.exec(text)) !== null) names.add(m[1]);
        if (names.size === 0) continue;
        const group = [];
        for (const name of names) {
          const r = { name, ts, id: c.id, kind: c.name, cmd: c.name === "Bash" ? text : null, cap: null };
          reads.push(r);
          group.push(r);
        }
        byId.set(c.id, group);
      }
    } else if (entry.type === "user") {
      for (const c of contentArray(entry)) {
        if (!c || c.type !== "tool_result" || !byId.has(c.tool_use_id)) continue;
        const group = byId.get(c.tool_use_id);
        const tur = entry.toolUseResult;
        let cap = null;
        if (typeof tur === "string") {
          cap = tur;
        } else if (tur && typeof tur === "object") {
          if (group[0].kind === "Read" && tur.file && typeof tur.file.content === "string") {
            cap = tur.file.content;
          } else if (group[0].kind === "Bash" && typeof tur.stdout === "string") {
            cap = tur.stdout;
          }
        }
        for (const r of group) r.cap = cap;
      }
    }
  }
  return reads;
}

function staleSteps(path, home) {
  if (typeof path !== "string" || path === "") return [];
  const steps = home + "/.claude/skills/ttw/steps/";
  const act = activationMs(home);
  // Per name: the last pre-activation read, the latest non-null capture up
  // to it, and the non-null captures of post-activation reads (refresh
  // candidates, never judged).
  const per = new Map();
  for (const r of stepReads(path)) {
    if (!per.has(r.name)) per.set(r.name, { pre: null, capRead: null, post: [] });
    const s = per.get(r.name);
    if (r.ts >= act) { if (r.cap !== null) s.post.push(r.cap); continue; }
    s.pre = r;
    if (r.cap !== null) s.capRead = r;
  }
  const out = [];
  for (const name of Array.from(per.keys()).sort()) {
    const r = per.get(name);
    if (r.pre === null) continue;
    let now;
    try { now = fs.readFileSync(steps + name, "utf8"); } catch (e) { continue; }
    if (r.post.some(c => c.includes(now.trimEnd()))) continue;
    if (r.capRead === null) {
      if (Number.isFinite(act)) out.push(name);
      continue;
    }
    const cap = r.capRead.cap;
    if (r.capRead.kind === "Bash" && rangeHit(r.capRead.cmd, name, now, cap)) continue;
    const stale = r.capRead.kind === "Read" ? !now.includes(cap) : !cap.includes(now.trimEnd());
    if (stale) out.push(name);
  }
  return out;
}

let input = "";
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  try {
    const data = JSON.parse(input);
    const ti = data.tool_input || {};
    if (ti.skill !== "ttw") process.exit(0);
    const n = contextTokens(data.transcript_path);
    const tp = typeof data.transcript_path === "string" ? data.transcript_path : "unknown";
    let ctx = "TTW start: context=" + (n === null ? "unknown" : n)
      + " tokens; transcript=" + tp
      + ". Tier is decided on the diff (SKILL.md); ttw-tier re-checks it.";
    let stale = [];
    try { stale = staleSteps(data.transcript_path, os.homedir()); } catch (e) { stale = []; }
    if (stale.length > 0) {
      ctx += " TTW steps changed since read: " + stale.join(", ")
        + ". Re-read them from ~/.claude/skills/ttw/steps/ before following them;"
        + " the copy in context is stale.";
    }
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: ctx
      }
    }));
  } catch (e) { /* fail open */ }
  process.exit(0);
});
