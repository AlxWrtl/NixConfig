#!/usr/bin/env node
"use strict";
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");

const MAX_ROUNDS = 2;
// Rounds in all, grants aside, that progress alone can reach: the bound on
// a review that keeps finding something new.
const CEILING = 5;
// The criteria the review still fails, one line per brief; self-declared,
// so a guardrail on progress, never proof of it.
const FAILING = /^[\s>*`-]*TTW-FAILING:(.*)$/;
const FAIL_ID = /^[A-Za-z0-9][A-Za-z0-9._:/#-]{0,79}$/;
const BUDGET_MS = 3000;
const RUN_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const TTW_OUT = path.join(".claude", "output", "ttw");
const BUDGET_DIR = "ttw-correction-budget";
const ROUND = /^(.+)\.round([1-9][0-9]*)$/;
const MARKER = /^[\s>*`-]*TTW-CORRECTION-ROUND:\s*([^\s`]*)[\s`]*$/;
// Any separator: a brief carrying only a pre-rename marker line (unread by
// MARKER) still names a correction round, so it is denied, never uncounted.
const MENTIONS = /06-resolve\.md|correction[\s_-]*round/i;
const GRANT = /^(.+)\.grant([1-9][0-9]*)$/;
// Same line as correction-grant.js: a scheduled prompt comes back as a user
// turn, so the model may not schedule the user's grant.
const TOKEN = /^\s*ttw\s*:\s*\+1\s+tour\s*$/i;
const SCHEDULERS = ["CronCreate", "ScheduleWakeup"];

let settled = false;
let marked = null;

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

function denyNoMarker() {
  deny("BLOCKED: this brief names 06-resolve.md or a correction round but has no TTW-CORRECTION-ROUND line. Add one on its own line: TTW-CORRECTION-ROUND: <run-id> for a correction round, TTW-CORRECTION-ROUND: none for any other brief, then retry.");
}

function denyState(what, file) {
  deny("BLOCKED: budget state " + what + ": " + safe(file) + "; inspect or remove it, or ask the user.");
}

// Past a marker naming a run, a failure must not let the round through.
function failed(why) {
  if (marked !== null) deny("BLOCKED: the correction-budget hook failed (" + safe(why) + ") on a correction round for run " + marked + "; ask the user.");
  allow();
}

// Every file of the budget dir `dir`, as { bd, f }. A missing dir holds
// nothing; a dir that is no real directory (a symlink, a file) or any other
// read error throws (fails closed).
function budgetFiles(dir) {
  let st;
  try {
    st = fs.lstatSync(dir);
  } catch (e) {
    if (e && e.code === "ENOENT") return [];
    throw e;
  }
  if (!st.isDirectory()) throw new Error("budget dir is not a real directory: " + dir);
  return fs.readdirSync(dir).map((f) => ({ bd: dir, f }));
}

// Rounds the user granted this run past MAX_ROUNDS: one <run>.grant<n> file
// each, written by correction-grant.js from the user's own prompt.
function grantsOf(dir, run) {
  let n = 0;
  for (const { f } of budgetFiles(dir)) {
    const m = GRANT.exec(f);
    if (m && m[1] === run) n++;
  }
  return n;
}

// Rounds this run spent in the budget dir: their total is what the
// cap bounds, their indices are the slots a new stamp may not reuse.
// `rounds` holds what each stamp recorded, in round order.
function roundsOf(dir, run) {
  const taken = new Set();
  const rounds = [];
  let total = 0;
  for (const { bd, f } of budgetFiles(dir)) {
    const m = ROUND.exec(f);
    if (m && m[1] === run) { total++; taken.add(Number(m[2])); }
    if (m && m[1] === run) rounds.push(roundOf(Number(m[2]), stampOf(path.join(bd, f))));
  }
  rounds.sort((a, b) => a.n - b.n);
  return { total, taken, rounds };
}

// A TTW-FAILING line's ids, deduped and sorted, or null when it names none
// or one is malformed: an unreadable set is no evidence of progress.
function idsOf(text) {
  const ids = String(text).split(",").map((s) => s.replace(/`/g, "").trim()).filter((s) => s !== "");
  if (ids.length === 0 || ids.length > 64 || !ids.every((id) => FAIL_ID.test(id))) return null;
  return [...new Set(ids)].sort();
}

// A round's stamp as a plain object; anything unreadable is {}, never a
// throw: an old or damaged stamp reads as a budget round with no brief and
// no set, which only ever allows fewer rounds.
function stampOf(file) {
  try {
    const st = fs.lstatSync(file);
    if (!st.isFile() || st.size > 64 * 1024) return {};
    const v = JSON.parse(fs.readFileSync(file, "utf8"));
    return v && typeof v === "object" && !Array.isArray(v) ? v : {};
  } catch {
    return {};
  }
}

function roundOf(n, s) {
  const brief = typeof s.brief_sha256 === "string" && /^[0-9a-f]{64}$/.test(s.brief_sha256) ? s.brief_sha256 : null;
  const failing = Array.isArray(s.failing) && s.failing.every((id) => typeof id === "string") ? idsOf(s.failing.join(",")) : null;
  return { n, brief, failing, progress: s.via === "progress" };
}

// Why a round past the cap may not go out on its own, or null when its
// TTW-FAILING set shows progress: non-empty, equal to no earlier round's
// set, and without at least one id the previous round still failed.
function stopOf(cur, rounds) {
  const ids = cur || [];
  if (ids.length === 0) return "evidence";
  const sets = rounds.map((r) => r.failing);
  const key = ids.join(",");
  const seen = sets.findIndex((s) => s !== null && s.join(",") === key);
  if (seen !== -1) return seen === sets.length - 1 ? "repeat" : "oscillation:" + rounds[seen].n;
  const prev = sets.length > 0 ? sets[sets.length - 1] : null;
  if (!(prev || []).some((id) => !ids.includes(id))) return prev === null ? "noprev" : "nodrop";
  return null;
}

// Whether TTW ran since the session's last user turn, read from transcript
// `t` by require-ttw.js's own walk, kept verbatim (D10): true, false, or
// null for no verdict (no path, not a regular file, a read error). Never
// throws: null leaves the round counted as before.
function ttwGate(t) {
  try {
    if (typeof t !== "string" || t === "") return null;
    if (!fs.statSync(t).isFile()) return null;
    const lines = fs.readFileSync(t, "utf8").split("\n");
    // BEGIN shared openAt (require-ttw.js, D10)
    const TTW = "\"name\":\"Skill\",\"input\":{\"skill\":\"ttw\"";

    // Walk backwards from line `from`: whichever comes first decides. An
    // TTW call before any user turn means TTW ran for THIS task -> pass.
    // A user turn first means this is a new request with no TTW yet -> deny.
    const openAt = from => {
    for (let i = from; i >= 0; i--) {
      const line = lines[i];
      if (!line) continue;

      if (line.indexOf(TTW) !== -1) return true;

      // A prompt typed while the model works is often recorded only as an
      // attachment, never as a user line: a queued_command marked human
      // (humanTurn, or origin.kind on the older shape). Task notifications
      // and subagent hand-backs share the attachment type and stay out.
      if (line.indexOf("\"queued_command\"") !== -1) {
        let q;
        try { q = JSON.parse(line); } catch { q = null; }
        // isMeta sits on the attachment in the real lines, never on top.
        const a = q && q.type === "attachment" && q.isMeta !== true ? q.attachment : null;
        if (a && a.type === "queued_command" && a.isMeta !== true && a.commandMode === "prompt"
          && (a.humanTurn === true || (a.origin && a.origin.kind === "human"))) return false;
      }

      // Cheap reject before the JSON.parse cost.
      if (line.indexOf("\"type\":\"user\"") === -1) continue;

      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      if (msg.type !== "user") continue;

      // Harness-injected content, written with the user role but never
      // typed by anyone. This one is load-bearing: invoking a Skill writes
      // the skill's own body back as an isMeta user line, AFTER the Skill
      // marker. Without this skip the backwards walk hits that line first
      // and denies forever — ttw plants a fresh one on every retry.
      // Replayed over 4 real transcripts: 161/161 historical edits denied.
      if (msg.isMeta === true) continue;

      // The compaction summary, written as a user line with its own flag
      // and no isMeta: /compact, or the window running out mid-task, is not
      // a new request. The walk goes on above it, where the lines from
      // before the compaction still decide; in a file that starts at the
      // compaction, nothing does: the walk reaches the top and denies.
      if (msg.isCompactSummary === true) continue;

      const c = msg.message && msg.message.content;

      // Tool results are recorded as user messages. They are not turns.
      if (Array.isArray(c) && c.some(b => b && b.type === "tool_result")) continue;

      // Harness envelopes that carry no isMeta flag: `! command` lines,
      // background-task completions, and slash-command markers. All are
      // user-role lines, none is a new request.
      const text = typeof c === "string"
        ? c
        : (Array.isArray(c) ? c.filter(b => b && b.type === "text").map(b => b.text || "").join("") : "");
      if (/^\s*<(bash-(input|stdout|stderr)|task-notification|command-name|local-command-)/.test(text)) continue;

      return false; // a real user turn, reached before any TTW call
    }
    return false;
    };
    // END shared openAt
    return openAt(lines.length - 1);
  } catch { return null; }
}

let input = "";
let ran = false;

function main() {
  let data;
  try { data = JSON.parse(input); } catch { allow(); return; }
  if (!data || typeof data !== "object" || Array.isArray(data)) { allow(); return; }
  if (SCHEDULERS.includes(data.tool_name)) {
    const sp = data.tool_input && typeof data.tool_input === "object" ? data.tool_input.prompt : undefined;
    if (typeof sp === "string" && sp.split(/\r?\n/).some((l) => TOKEN.test(l))) {
      deny("BLOCKED: a scheduled prompt may not carry the correction-grant token; only the user types it.");
      return;
    }
    allow();
    return;
  }
  if (data.tool_name !== "Agent" && data.tool_name !== "Task" && data.tool_name !== "SendMessage") { allow(); return; }
  const ti = data.tool_input;
  if (!ti || typeof ti !== "object" || Array.isArray(ti)) { allow(); return; }
  // Agent/Task carry `prompt`, SendMessage `message`; a non-string
  // message (a structured request) is no brief.
  const prompt = [ti.prompt, ti.message].find((v) => typeof v === "string" && v !== "") || "";
  if (prompt === "") { allow(); return; }

  let marker = null;
  let failing = null;
  let fails = 0;
  for (const line of prompt.split(/\r?\n/)) {
    const f = FAILING.exec(line);
    if (f) { fails++; failing = f[1]; }
    const m = MARKER.exec(line);
    if (!m) continue;
    if (marker !== null && marker !== m[1]) {
      deny("BLOCKED: this brief carries conflicting TTW-CORRECTION-ROUND lines (" + safe(marker) + ", " + safe(m[1]) + "); keep exactly one, then retry.");
      return;
    }
    marker = m[1];
  }
  if (!marker && MENTIONS.test(prompt)) { denyNoMarker(); return; }
  if (marker === null || marker === "none") { allow(); return; }
  // A run outside the session's repo is named by its absolute run dir,
  // <repo>/.claude/output/ttw/<run-id>; its budget is keyed by the
  // run-id.
  const named = marker;
  let runDir = null;
  if (path.isAbsolute(marker) && path.dirname(marker).endsWith(path.sep + TTW_OUT) && path.join(path.dirname(marker), path.basename(marker)) === marker) {
    runDir = marker;
    marker = path.basename(marker);
  }
  if (!RUN_ID.test(marker) || named.includes("..")) {
    deny("BLOCKED: TTW-CORRECTION-ROUND names \"" + safe(named) + "\", which is neither none, a run-id like 62-correction-budget, nor an absolute <repo>/.claude/output/ttw/<run-id> path; fix the line, then retry.");
    return;
  }
  marked = marker;

  const cwd = typeof data.cwd === "string" && data.cwd !== "" ? data.cwd : process.cwd();
  // A run-id resolves under the repo's .claude/output/ttw only.
  if (runDir === null) runDir = path.join(cwd, TTW_OUT, marker);
  let isDir;
  try { isDir = fs.statSync(runDir).isDirectory(); } catch { isDir = false; }
  if (!isDir) {
    deny("BLOCKED: TTW-CORRECTION-ROUND " + safe(named) + ": run dir not found (" + safe(runDir) + "); name the run this round belongs to, then retry.");
    return;
  }

  // A correction round runs on opus, checked before any slot is claimed:
  // a denied brief spends nothing. SendMessage carries no model.
  if (data.tool_name !== "SendMessage" && ti.model !== "opus") { const asked = ti.model === undefined || ti.model === null || ti.model === "" ? "absent" : "\"" + safe(ti.model) + "\""; deny("BLOCKED: correction rounds run on opus. This correction brief for run " + marker + " has model " + asked + "; re-spawn it with model: \"opus\". No round was counted."); return; }

  // A user turn after the last Skill ttw call re-arms require-ttw, which
  // then denies every write of the round: refused here, before the free
  // retry and any slot, so nothing is spent. A subagent's call carries the
  // parent's transcript: not gated. No verdict (null): counted as before.
  if (data.agent_id === undefined && ttwGate(data.transcript_path) === false) {
    deny("BLOCKED: TTW has not run since the user's last message, so require-ttw would deny every write of this correction round for run " + safe(marker) + ". Invoke the ttw skill first (Skill ttw), then resend this brief. No round was counted.");
    return;
  }

  const home = process.env.HOME || os.homedir();
  const dir = path.join(home, ".claude", BUDGET_DIR);
  // The brief's identity: the same text re-wrapped or re-indented hashes
  // the same, so a plain resend is told apart from a new round.
  const brief = crypto.createHash("sha256").update(prompt.trim().replace(/\s+/g, " "), "utf8").digest("hex");
  // More than one TTW-FAILING line is no set: no evidence either way.
  const cur = fails === 1 ? idsOf(failing) : null;
  const stampFor = (via) => JSON.stringify({
    ts: new Date().toISOString(),
    tool: safe(data.tool_name),
    session: safe(data.session_id),
    description: safe(ti.description || ti.summary).slice(0, 200),
    // correction-grant.js grants a run outside the prompt's repo by it.
    dir: runDir,
    brief_sha256: brief,
    failing: cur,
    via
  }) + "\n";
  try { fs.mkdirSync(dir, { recursive: true }); } catch { denyState("unwritable", dir); return; }

  // A round goes out while the run's total is under the cap.
  // Claim a slot by exclusive create at a free index: of two
  // racing rounds, one wins, the loser reads the winner's round.
  const cap = MAX_ROUNDS + grantsOf(dir, marker);
  let spent = roundsOf(dir, marker);
  // The latest round's brief sent again unchanged (a spawn that died, a
  // reply lost) is no new round: free once per brief, its marker created
  // exclusively; the same resend a second time is counted. An older
  // round's brief is counted: going back is no retry.
  const last = spent.rounds[spent.rounds.length - 1];
  if (last && last.brief === brief) {
    const retry = path.join(dir, marker + ".retry-" + brief);
    let fresh = true;
    try {
      fs.writeFileSync(retry, stampFor("retry"), { flag: "wx" });
    } catch (e) {
      if (!e || e.code !== "EEXIST") { denyState("unwritable", retry); return; }
      fresh = false;
    }
    if (fresh) { allow(); return; }
  }
  let taken = spent.taken;
  let total = spent.total;
  // A round that went out on progress is charged to the ceiling, not to the
  // cap: a user grant after any stop reopens exactly one round.
  let free = spent.rounds.filter((r) => r.progress).length;
  let stop = stopOf(cur, spent.rounds);
  // After a lost claim, everything is read again: the winner's round, its
  // set included, is evidence this brief must now face. A winner's stamp
  // still being written reads as no set, so no progress: denied.
  const recount = () => {
    spent = roundsOf(dir, marker);
    taken = spent.taken;
    total = spent.total;
    free = spent.rounds.filter((r) => r.progress).length;
    stop = stopOf(cur, spent.rounds);
  };
  for (let n = 1; ; n++) {
    const normal = total - free < cap;
    // Past the cap, a round goes out on its own only on progress, and never
    // past CEILING rounds in all (plus one per grant).
    const auto = stop === null && total < cap - MAX_ROUNDS + CEILING;
    if (!normal && !auto) break;
    if (taken.has(n)) continue;
    const slot = path.join(dir, marker + ".round" + n);
    try {
      fs.writeFileSync(slot, stampFor(normal ? "budget" : "progress"), { flag: "wx" });
    } catch (e) {
      if (e && e.code === "EEXIST") { recount(); continue; }
      denyState("unwritable", slot);
      return;
    }
    allow();
    return;
  }
  const said = {
    evidence: "ce brief ne porte aucune ligne TTW-FAILING lisible",
    noprev: "la ronde précédente n'a enregistré aucun ensemble TTW-FAILING",
    repeat: "même ensemble TTW-FAILING que la ronde précédente",
    nodrop: "aucun id de la ronde précédente n'a disparu"
  };
  const why = stop === null
    ? "Plafond absolu atteint : " + total + " rondes, plafond " + (cap - MAX_ROUNDS + CEILING) + "."
    : "Pas de ronde de plus sur progrès : " + (stop.startsWith("oscillation:") ? "oscillation, même ensemble TTW-FAILING que la ronde " + stop.slice("oscillation:".length) : said[stop]) + ".";
  const setOf = (s) => (s === null ? "(aucun)" : "[" + s.join(", ") + "]");
  const sets = "Ensembles TTW-FAILING : " + spent.rounds.map((r) => "r" + r.n + " " + setOf(r.failing)).concat(["ce brief " + setOf(cur)]).join(" ; ") + ".";
  deny("budget de correction épuisé (" + (total - free) + "/" + cap + ") pour le run " + marker + " : STOP. " + why + " " + sets + " Livrer avec la liste des résiduels, ou demander à l'utilisateur de taper `ttw: +1 tour` seul sur une ligne (une ronde de plus, sur opus) ; un « continue » n'accorde rien. Ne jamais faire la ronde soi-même inline : le coordinateur ne corrige pas son propre travail.");
}

function start() {
  if (ran) return;
  ran = true;
  try {
    main();
  } catch (e) {
    failed(e && e.message);
  }
  failed("no decision reached");
}

process.on("uncaughtException", (e) => {
  if (settled) return;
  failed(e && e.message);
});

const watchdog = setTimeout(() => {
  failed("stdin not closed within " + BUDGET_MS + " ms");
}, BUDGET_MS);
if (typeof watchdog.unref === "function") watchdog.unref();

process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => { if (input.length < 4 * 1024 * 1024) input += c; });
process.stdin.on("end", start);
process.stdin.on("error", start);
