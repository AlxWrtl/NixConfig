#!/usr/bin/env node

// Branch-per-change workflow: create a branch BEFORE editing code, then
// push that branch — never master/main. commit/push/merge/rebase while on
// master/main are all hard-denied. Bringing code to master = a manual PR
// step by the user on GitHub, never a Claude action.

// Crash handler and watchdog FIRST, before the rule table below builds
// its RegExps: a throw there used to reach no handler (exit 1, no JSON,
// i.e. an allow), and the clock started only after it. What the handler
// touches is declared here too, out of the temporal dead zone; the
// functions it calls are hoisted.
const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawnSync } = require("child_process");

const PROTECTED = ["main", "master"];
const BUDGET_MS = 3000;
const GIT_MS = 1500;
const DEADLINE = Date.now() + BUDGET_MS;
const CUT = "Create a branch first: git checkout -b <type>/<desc> (e.g. feat/auth-redirect). Merge to master happens via PR on GitHub.";
// The one repo exempt from this guard, by PATH (user decision
// 2026-09-30): see the decision block at the bottom.
const VAULT = "@alxVaultPath@";

let settled = false;
let branchSeen = null;

process.on("uncaughtException", (e) => {
  if (settled) return;
  deny("BLOCKED: the branch-protection hook crashed (" + safe(e && e.message) + "), so the branch could not be checked. " + CUT);
});

const watchdog = setTimeout(() => {
  deny("BLOCKED: the branch-protection hook hit its own " + BUDGET_MS + " ms deadline before it could read its input. " + CUT);
}, BUDGET_MS);
if (typeof watchdog.unref === "function") watchdog.unref();

//
// The guard is a TABLE: one rule per family of commands, each rule readable
// on its own line, each carrying the WHY that put it there. A command is
// denied as soon as ONE rule matches ANYWHERE in it — inside a quoted
// string included, which is a deliberate over-approximation.

// Shared prefix, `git` plus its global options: they may sit between `git`
// and the verb, so `git -C <dir> commit` has to match too — the narrower
// /git\s+(commit|...)/ let every `git -C ... commit` through, on master
// included. Alternation order is load-bearing: `-C <path>` and `-c <k=v>`
// take a SEPARATE argument, so they must be tried BEFORE the generic option
// branch — that branch would otherwise consume `-C` alone and leave the
// path sitting where the verb is expected, reopening the hole.
// The value of `-c` / `-C` may be QUOTED, and a quoted value may hold the
// space `\S+` stopped at. `git -c user.name='x y' commit` left `y'` sitting
// where the verb is expected, so the prefix never reached `commit` and the
// command committed on master unseen. A value is therefore a RUN of quoted
// regions and plain characters.
//
// The five alternatives are mutually exclusive on purpose, and that is not
// cosmetic: the first shape tried here was (?:'[^']*'|"[^"]*"|\S)+, where
// `\S` also matches a quote, so a value like a'b'a'b'... could be cut in
// exponentially many ways and a FAILING match never came back --
// `git -c 'x'"y"` repeated 50 times already blew past five seconds. Each
// character now has exactly one branch: a quote with a later twin opens a
// region, a quote without one is a literal (that is the `(?![^']*')`
// guard, which also keeps an UNBALANCED quote consuming exactly what the
// old `\S+` consumed, so no denial is lost), anything else is itself.
const GIT = /\bgit(?:\s+(?:-[Cc]\s+(?:'[^']*'|'(?![^']*')|"[^"]*"|"(?![^"]*")|[^\s'"])+|--?[A-Za-z][\w-]*(?:=\S+)?))*\s+/;

// End of a verb, or of a short-option cluster. NOT `\b`: `\b` only asks for
// a word/non-word boundary, and `-` is a non-word char, so it cannot tell
// the end of a verb from the start of a compound subcommand. Concrete case:
// `git merge-base HEAD origin/master` — a pure read — was denied because
// `\b` matched inside `merge-base`. Same for `merge-tree`, `commit-tree`
// and `commit-graph`: they read, or at most write an object, and none of
// them moves a ref. `commit-tree` opens no hole either — publishing that
// object needs `update-ref` or a `reset` onto it, both denied below.
const EOW = /(?![\w-])/;

// The run of option tokens a rule skips over between the verb and the flag
// it is looking for: `git branch -q -f master`.
const OPTS = /(?:\s+-\S+)*\s+/;

// One positional argument. Counting positionals is the whole difficulty and
// a naive `\S+` gets it wrong twice: it reads `--short` as a positional, and
// it reads the `|` of `... | grep master` as one too. So an argument may not
// start with `-`, contains no shell word terminator, and must END on one —
// or `-q HEAD 2>/dev/null` would count `2` as the second argument. `$(cat
// f)` still counts, so a substituted ref fails closed, while pipes,
// redirections and `&&`/`;` chains after a read stay transparent.
const ARG = /[^-\s;&|<>()][^\s;&|<>()]*(?=[\s;&|()]|$)/;

const src = (x) => (typeof x === "string" ? x : x.source);
const seq = (...parts) => parts.map(src).join("");
const oneOf = (...alts) => "(?:" + alts.map(src).join("|") + ")";
// A short flag can hide inside a single-dash cluster (`-qf`, `-qB`), so it
// is matched as "one dash, that letter anywhere in the cluster"; long
// options are matched literally, or `git branch --format=%(refname)` would
// read as `-f`. Case IS the distinction and nothing here carries an `i`
// flag: `-b` creates a branch and must pass, `-B` resets one and must deny.
const cluster = (letters) => "-[A-Za-z]*[" + letters + "][A-Za-z]*";
// Shape of every rule gated on a FLAG: `<verb> [options] <flag>`.
const flagged = (verb, ...flags) =>
  seq(oneOf(verb), EOW, OPTS, oneOf(...flags), EOW);
// Reset targets that cannot put foreign code on the current branch: HEAD
// and its ancestors (the branch is already there, or is being moved BACK,
// which only removes commits), the upstream shorthands, and an
// `origin/`/`upstream/` remote-tracking ref — the resync gesture
// `git reset --hard origin/master` that kept reset out of the table in the
// first place. Anything else is an arbitrary commit-ish. The trailing
// lookahead makes the name END here, or `HEADX` and `originals/x` would
// read as safe.
const RESET_SAFE =
  /(?:HEAD(?:[~^][0-9]*)*|@\{u(?:pstream)?\}|(?:origin|upstream)\/(?:master|main|HEAD))(?=[\s;&|()]|$)/;

const RULES = [
  // Verbs that commit, publish or move a ref on their own. The verb IS the
  // decision here, there is no flag to inspect. `pull` is a fetch plus a
  // merge or rebase into the CURRENT branch: on master it lands commits
  // that never went through a PR (run 61, B2).
  { id: "write-verb",
    why: "authors a commit, publishes, or moves a ref outright",
    pat: seq(oneOf(/commit|push|merge|rebase|update-ref|pull/), EOW) },

  // Three verbs put commits on the current branch without being spelled
  // `commit`: cherry-pick, revert and am each REPLAY work onto HEAD, so on
  // master they land code that never passed through a PR. `--abort` and
  // `--quit` are exempt: they end an in-flight operation and create
  // nothing, and a conflict state inherited from before this hook still
  // needs a way out. `--continue` and `--skip` stay denied — they finish
  // applying the commits, which is precisely what is being prevented, and
  // `git rebase --continue` was already denied, so this stays consistent.
  { id: "replay-verb",
    why: "replays commits onto HEAD, unless it is aborting one",
    pat: seq(oneOf(/cherry-pick|revert|am/), EOW,
             /(?!\s+--(?:abort|quit)(?![\w-]))/) },

  // symbolic-ref is gated on its SHAPE, not on the verb: `symbolic-ref
  // HEAD`, `--short HEAD` and `-q HEAD` are pure reads — the standard way
  // to ask which branch HEAD points at. Only two forms move a ref: the
  // delete form, and the write form, recognised by its TWO positionals.
  { id: "symbolic-ref-delete",
    why: "-d/--delete drops the ref HEAD points through",
    pat: flagged(/symbolic-ref/, /-d/, /--delete/) },
  { id: "symbolic-ref-write",
    why: "two positionals = repointing HEAD at another branch",
    pat: seq(oneOf(/symbolic-ref/), EOW, OPTS, ARG, OPTS, ARG) },

  // branch, checkout and switch are gated on the FLAG, not on the verb:
  // they are daily read/create commands, and denying them wholesale would
  // break the very workflow this hook exists to enforce — its own error
  // message tells the user to run `git checkout -b <type>/<desc>`.
  //
  // The branch cluster is [fMC], three letters, all uppercase-or-`f`:
  // `-f`/`--force`, `-M` (force-rename) and `-C` (force-copy) all overwrite
  // an existing ref, so `git branch -C master abc` moves master exactly
  // like `-f` does. The long form `--copy --force` was already caught by
  // `--force`; the short form was the hole. Their lowercase twins stay OUT
  // of the class on purpose: `-c old new` and `-m old new` are the
  // NON-forced copy/rename, they refuse to clobber an existing master, and
  // `git branch -m old new` is common enough that denying it would be a
  // false positive of the same kind as `merge-base`.
  { id: "branch-force",
    why: "-f / --force / -M / -C overwrite an existing branch ref",
    pat: flagged(/branch/, /--force/, cluster("fMC")) },
  { id: "checkout-force",
    why: "-B resets an existing branch onto HEAD, where -b only creates",
    pat: flagged(/checkout/, cluster("B")) },
  { id: "switch-force",
    why: "-C / --force-create is the switch spelling of checkout -B",
    pat: flagged(/switch/, /--force-create/, cluster("C")) },

  // `reset` was kept out of this table because `git reset --hard
  // origin/master` is the normal resync gesture. That exemption was the
  // whole rule, and it left `git reset --hard <feature-branch>` open: on
  // master that drags master onto arbitrary code, authoring no commit and
  // passing through no PR — precisely what this hook exists to stop.
  // Closed on the SHAPE instead of the verb: a mode flag FOLLOWED BY a
  // target, and only when that target is not one of the safe ones. The
  // daily gestures keep passing, each for its own reason: no mode flag
  // (`git reset`, `git reset HEAD file`) is an unstage and moves no ref; a
  // mode flag with NO target (`git reset --hard`) throws away local edits
  // and leaves the ref where it is; HEAD~n only ever removes commits; and
  // origin/* is the resync above.
  { id: "reset-arbitrary-target",
    why: "a mode flag aimed at an arbitrary commit-ish moves the branch there",
    pat: seq(flagged(/reset/, /--hard/, /--merge/, /--keep/, /--soft/, /--mixed/),
             /\s+/, "(?!" + src(RESET_SAFE) + ")", ARG) },
];

const GUARD = RULES.map((r) => new RegExp(src(GIT) + r.pat));

// The rules above test the WHOLE command string. That over-approximation
// is right for CODE, but it also fires on TEXT. Real case, hit three times
// today on master: a PR description piped through a heredoc whose body
// merely MENTIONS cherry-pick and rebase --
//     gh pr edit 133 --body-file - <<BODY   (delimiter quoted)
//     ... prose about git rebase ...
//     BODY
// -> BLOCKED, with not one byte of git about to run. The watched list
// going from 4 to 12 verbs turned this into a daily event.
//
// Anchoring the verb at the START of the command was considered and
// rejected: `sudo git commit`, `env X=1 git commit` and `for f in x; do
// git commit; done` would all stop being seen -- a benign false positive
// traded for real false negatives.
//
// Retained instead: blank out the text the shell CANNOT execute, then run
// the unchanged rules on what is left. Inert = single quotes and
// quoted-delimiter heredocs (no substitution happens there at all), plus
// double quotes and bare-delimiter heredocs ONLY when they hold no $ and
// no backtick -- those two DO run command substitutions, and a
// substitution is never masked: --body "$(git commit -m x)" stays DENY.
//
// Masking rewrites every non-space run as _ and keeps the whitespace, so
// token structure survives: no match can be forged by closing a gap (an
// emptied "x y" must not turn `git -c k=v <arg> commit` into a hit).
//
// Shell quoting is a minefield, so DOUBT RETURNS THE RAW STRING, i.e.
// exactly today's verdict. Three ways in:
//   1. unbalanced quotes or an unterminated heredoc -> raw;
//   2. a quoted token sitting where the git VERB goes -> raw, because
//      text and verb are indistinguishable there;
//   3. a command word that EXECUTES its argument (sh -c, eval, xargs,
//      sudo, ssh...) -> raw, the quoted string is code there, not text.
const mask = (s) => s.replace(/\S+/g, "_");
// Only COMMAND position counts -- start of line, or right after ; | & or (
// -- so the word `find` inside a PR body disarms nothing.
// Blanks after the separator are `[ \t]*`, never `\s*`: `\s` also eats
// newlines, which are separators themselves, so a run of newlines was
// rescanned from every one of them -- 32 KB of them took 5.2 s, past the
// host's 5 s timeout, i.e. an allow. A newline inside the run is still a
// separator on its own; what no longer matches is a \r, \v, \f or Unicode
// space before the word, and the shell does not split words on those.
const EXECUTOR =
  /(?:^|[\n;|&(])[ \t]*(?:sh|bash|zsh|dash|ksh|fish|eval|exec|source|\.|sudo|doas|su|env|nohup|timeout|watch|nice|stdbuf|script|xargs|find|parallel|ssh|nix-shell|node|deno|bun|python3?|perl|ruby|awk)(?![\w-])/;
const QUOTED_VERB = new RegExp(src(GIT) + src(/["']/));
// The same doubt one slot earlier: a quote INSIDE a `-c` / `-C` value.
// Masking there is what hid `git -c user.name='x y' commit` even after the
// prefix was widened — the mask keeps the whitespace, so the value came
// back as two tokens and the verb slot landed on the second one. Testing
// the raw string instead is the same fail-closed answer as case 2, and the
// widened `-c` value above then swallows the quoted region whole.
const QUOTED_GIT_OPT = new RegExp(src(GIT) + src(/-[Cc]\s+[^\s'"]*["']/));

const stripInertText = (cmd) => {
  if (EXECUTOR.test(cmd) || QUOTED_VERB.test(cmd) || QUOTED_GIT_OPT.test(cmd))
    return cmd;
  let out = "";
  let i = 0;
  const n = cmd.length;
  const pending = [];
  while (i < n) {
    const ch = cmd[i];
    // Outside quotes a backslash escapes the next char, apostrophes and
    // double quotes included: it must never be read as a quote opener.
    if (ch === "\\") { out += cmd.slice(i, i + 2); i += 2; continue; }
    if (ch === "'") {
      const j = cmd.indexOf("'", i + 1);
      if (j < 0) return cmd;
      out += mask(cmd.slice(i, j + 1)); i = j + 1; continue;
    }
    if (ch === '"') {
      // Inside double quotes only a backslash can hide the closing quote.
      let j = i + 1;
      while (j < n && cmd[j] !== '"') j += cmd[j] === "\\" ? 2 : 1;
      if (j >= n) return cmd;
      const region = cmd.slice(i, j + 1);
      out += /[$`]/.test(region) ? region : mask(region);
      i = j + 1; continue;
    }
    if (ch === "`") {
      const j = cmd.indexOf("`", i + 1);
      if (j < 0) return cmd;
      out += cmd.slice(i, j + 1); i = j + 1; continue;
    }
    // Heredoc operator. Three `<` is a here-STRING, whose operand is an
    // ordinary word and is scanned as one.
    if (ch === "<" && cmd[i + 1] === "<" && cmd[i + 2] !== "<") {
      let k = i + 2;
      if (cmd[k] === "-") k++;
      while (cmd[k] === " " || cmd[k] === "\t") k++;
      let quoted = false;
      let delim;
      if (cmd[k] === "'" || cmd[k] === '"') {
        const q = cmd[k];
        const e = cmd.indexOf(q, k + 1);
        if (e < 0) return cmd;
        quoted = true; delim = cmd.slice(k + 1, e); k = e + 1;
      } else {
        const m = /^[A-Za-z0-9_.-]+/.exec(cmd.slice(k));
        if (!m) return cmd;
        delim = m[0]; k += m[0].length;
      }
      pending.push([delim, quoted]);
      out += mask(cmd.slice(i, k)); i = k; continue;
    }
    // Bodies start at the next newline, in the order the operators came.
    if (ch === "\n" && pending.length) {
      out += "\n"; i++;
      while (pending.length) {
        const h = pending.shift();
        let body = "";
        let closed = false;
        while (i <= n) {
          let e = cmd.indexOf("\n", i);
          if (e < 0) e = n;
          const line = cmd.slice(i, e);
          if (line.trim() === h[0]) { i = e < n ? e + 1 : n; closed = true; break; }
          body += line + "\n";
          if (e >= n) { i = n; break; }
          i = e + 1;
        }
        if (!closed) return cmd;
        out += (h[1] || !/[$`]/.test(body)) ? mask(body) : body;
      }
      continue;
    }
    out += ch; i++;
  }
  if (pending.length) return cmd;
  return out;
};

// SECOND VIEW, tested IN ADDITION to the one above and never instead: a
// command is denied as soon as either view matches, so this can only ever
// ADD denials. Quoting is invisible to the shell but not to a regex, and
// three real bypasses lived exactly there — `git 'commit' -m x`,
// `git "commit" -m x`, and an empty apostrophe pair dropped inside the
// command word itself (g, i, two apostrophes, t, then a bare `commit`),
// where the quotes cut the word in half while the shell still ran a
// commit on master.
//
// The view drops the quote CHARACTERS, but only around a region whose
// content holds no whitespace. That condition is the entire safety of it,
// and it is what keeps this morning's inert-text fix intact: a PR body such
// as --body "git rebase sur master" holds spaces, keeps its quotes, stays
// inert text and stays allowed, while `commit` or an emptied pair does not
// survive as text in the first place.
//
// Two regions are skipped. A heredoc delimiter: turning <<'B' into <<B
// would stop masking a body that merely contains a `$`, inventing a false
// positive of the very kind that was just removed. And a quote preceded by
// a backslash: it is a literal character, and removing it unbalances the
// rest of the string, which then falls back to the raw text.
//
// Known, accepted side effect: `echo 'git' commit` becomes a denial. The
// string is artificial and the direction is the safe one.
const dequoteTight = (s) =>
  s.replace(/(<<-?[ \t]*|\\)?(?:'([^'\s\\]*)'|"([^"\s\\]*)")/g,
            (m, keep, a, b) => (keep ? m : a === undefined ? b : a));
// One strip per view, not one per rule: it is the costly pass.
const hits = (c) => {
  const v = stripInertText(c);
  return GUARD.some((re) => re.test(v));
};
const movesRefOnCurrentBranch = (c) => hits(c) || hits(dequoteTight(c));

// A push whose DESTINATION names master/main is refused from ANY branch,
// in any repo, with or without a remote: the branch test below only sees
// the CURRENT branch, so `git push origin master` from a feature branch
// (or `HEAD:master`, `+x:refs/heads/main`, `:master`) published straight
// to master unseen. The destination is a whole word: `master-foo`,
// `mainline` and `feat/master` are other branches. The scan stays inside
// one command (no `;`, `&`, `|`, newline or paren), so
// `git push origin feat/x && git log master` is not a push to master.
// Same two views as the rules: inert text masked, tight quotes dropped.
// A closing quote or backtick also ends the word: behind an EXECUTOR the
// raw string is scanned, and `bash -c "git push origin master"` ends on
// `master"`. Known, accepted: `env X=1 git commit -m "git push origin
// master"` keeps the raw string the same way, so that text denies.
// A redirection also ends the word: `git push origin master>/dev/null`
// still pushes to master, so `<` and `>` sit in the lookahead too.
const PROTECTED_DST = /\+?(?:[^\s:;&|<>()]*:)?(?:refs\/heads\/|heads\/)?(?:master|main)(?=[\s;&|()<>"'`]|$)/;
// LINEAR scan, in two passes. The first shape was ONE regex with a lazy
// `[^;&|\n()]*?\s` before the destination: every `git push` restarted it
// to the end of the segment, so 128 KB of `git push ` with no separator
// was quadratic. Now each push segment is cut ONCE, greedily (the global
// match resumes where the last one ended), and the destination word is
// looked for inside that segment alone. A `\` + newline is a line
// continuation to the shell, so it is folded to a space first.
const PUSH_SEG = new RegExp(src(GIT) + "push" + src(EOW) + "([^;&|\\n()]*)", "g");
const DST_WORD = new RegExp("\\s" + src(PROTECTED_DST));
const scan = (v) => [...v.matchAll(PUSH_SEG)].some((m) => DST_WORD.test(m[1]));
const pushTargetsProtectedRef = (c) => {
  const v = c.replace(/\\\n/g, " ");
  return scan(stripInertText(v)) || scan(stripInertText(dequoteTight(v)));
};

// ---- decision: FAILS CLOSED (run 57) --------------------------------
// The old stdin block exited 0 on a bad JSON input, a missing, broken or
// hung git, and any throw, and exit 0 with no JSON lets the command
// through. Ported from home/codex/scripts/block-main-shell.js (git(),
// branchOf, decideBlind, watchdog), output kept in the Claude form: deny =
// ONE JSON object written synchronously to fd 1, exit 0, nothing on
// stderr; allow = exit 0, no output. Every git call is spawnSync (no
// shell) under LC_ALL=C with a timeout drawn from one DEADLINE, so a hung
// git is killed before the host's 5 s hook timeout, whose expiry would
// NOT block the command. Its requires, constants, crash handler and
// watchdog sit at the top of the file.

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
  deny("BLOCKED: on " + safe(branchSeen) + " and " + why + ", so this command cannot be shown to be safe. " + CUT);
}

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

// { kind: "norepo" } | { kind: "branch", branch } | { kind: "broken", why }
// A nonexistent cwd ALSO fails with ENOENT, i.e. it reads as "git is not on
// PATH": callers only pass a directory known to exist.
function branchOf(dir) {
  const probe = git(["rev-parse", "--is-inside-work-tree"], dir);
  const probeBroken = gitBroken(probe);
  if (probeBroken) return { kind: "broken", why: probeBroken };
  if (probe.status !== 0) {
    if (/not a git repository/i.test(String(probe.stderr || ""))) return { kind: "norepo" };
    return { kind: "broken", why: "git rev-parse failed" };
  }
  // "false" is a directory INSIDE a .git (or a bare repo): not a norepo.
  // `git -C repo/.git update-ref refs/heads/master X` moves master from
  // there, so its branch is read like any other (run 61).
  const br = git(["branch", "--show-current"], dir);
  const brBroken = gitBroken(br);
  if (brBroken) return { kind: "broken", why: brBroken };
  if (br.status !== 0) return { kind: "broken", why: "git branch --show-current failed" };
  // Detached HEAD prints nothing, and is not a protected branch.
  return { kind: "branch", branch: String(br.stdout || "").trim() };
}

// The branch of a GIT DIRECTORY named by --git-dir / GIT_DIR: rev-parse
// --is-inside-work-tree says false there, so it is asked directly.
function branchOfGitDir(p) {
  const br = git(["--git-dir=" + p, "branch", "--show-current"]);
  const brBroken = gitBroken(br);
  if (brBroken) return { kind: "broken", why: brBroken };
  if (br.status !== 0) {
    if (/not a git repository/i.test(String(br.stderr || ""))) return { kind: "norepo" };
    return { kind: "broken", why: "git branch --show-current failed" };
  }
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

// ---- the directories a command may write to (run 61, B1) ----------
// The old retarget read only the FIRST `git -C` and the first `cd`, so a
// `-c k=v` before `-C`, a second `cd`, `pushd`, a subshell, `--git-dir`
// or GIT_DIR sent a commit to master from a feature cwd. Now every one of
// them is collected, and each candidate is checked: adding a directory
// can only add a refusal. A missing directory is not a repo and is
// skipped; one the shell would compute ($, backtick, glob, `cd -`,
// `popd`, `pushd +N`) cannot be placed and denies.
//
// One shell word. Same five mutually exclusive branches as the GIT value
// (see the ReDoS note there) plus a backslash escape, and the bare branch
// stops at the shell separators so `(cd x)` and `cd x;` end on `x`.
const TOK = /(?:\\[\s\S]|'[^']*'|'(?![^']*')|"[^"]*"|"(?![^"]*")|[^\s'"\\;&|<>()])+/;
const PART = /\\([\s\S])|'([^']*)'|"([^"]*)"|(['"])|([^\\'"]+)/g;
// Its text, or null when the shell would compute it.
const shellWord = (tok) => {
  if (typeof tok !== "string" || /^~[^/]/.test(tok)) return null;
  let out = "";
  let p;
  PART.lastIndex = 0;
  while ((p = PART.exec(tok)) !== null) {
    if (p[1] !== undefined) out += p[1];
    else if (p[2] !== undefined) out += p[2];
    else if (p[3] !== undefined) { if (/[$`\\]/.test(p[3])) return null; out += p[3]; }
    else if (p[4] !== undefined) return null;
    else { if (/[$`*?[{]/.test(p[5])) return null; out += p[5]; }
  }
  if (out === "") return null;
  if (/^~(?:\/|$)/.test(tok)) out = os.homedir() + out.slice(1);
  return out;
};
// `cd` / `pushd` / `popd` as a word the shell runs: after a separator, a
// blank, a quote (`bash -c "cd x && ..."`) or `{ ( !`, so `then cd x`
// counts too. Its options, then its one argument if any.
const CD_WORD = new RegExp(seq(/(?<![^\s;&|({!"'`])(cd|pushd|popd)(?![\w./-])(?:[ \t]+(?:-[LPe@]+|--)(?=[\s;&|<>()]|$))*/, "(?:[ \\t]+(", TOK, "))?"), "g");
// Every `git` word the rules could read as a command; `--git-dir` and a
// `.git` path segment are not.
const GIT_AT = /(?<!\.)\bgit(?![\w-])/g;
// One global option after `git`, read from where the last one ended.
const GIT_OPT = new RegExp(seq(/\s+/, oneOf(seq(/-C\s+/, "(", TOK, ")"), seq(/--(git-dir|work-tree)(?:=|\s+)/, "(", TOK, ")"), seq(/-c\s+/, TOK), /--?[A-Za-z][\w-]*(?:=\S+)?/)), "y");
const GIT_ENV = new RegExp(seq(/(?<![\w$])GIT_(DIR|WORK_TREE)=/, "(", TOK, ")?"), "g");
// GIT_DIR=x written right before the git word it applies to.
const GIT_DIR_PREFIX = new RegExp(seq(/(?:^|[\s;&|(])GIT_DIR=/, "(", TOK, ")", /[ \t]+$/));
const LEAD_CD = new RegExp(seq(/^[ \t]*cd(?:[ \t]+--)?[ \t]+/, "(", TOK, ")", /[ \t]*&&/));
// A lone `&` backgrounds what precedes it, in a subshell: the `cd` there
// does not move the rest of the command.
const BACKGROUND = /(?<![&><|])&(?![&>])/;

function targetsOf(cmd) {
  const cwd = process.cwd();
  const found = [];
  const seen = new Map();
  let bad = null;
  let n = 0;
  const isDir = (p, gd) => {
    try {
      const s = fs.statSync(p);
      return gd || s.isDirectory();
    } catch {
      return false;
    }
  };
  // Relative arguments are resolved against the cwd AND every directory
  // found so far: `cd a && cd b` and `git -C a -C b` both chain. True
  // when one of its candidates exists.
  const add = (tok, gd, raw) => {
    if (bad !== null) return false;
    if (++n > 64) { bad = "more than 64 directory changes"; return false; }
    const w = shellWord(tok);
    if (w === null) { bad = raw; return false; }
    const bases = [cwd].concat(found.filter((f) => !f.gd).map((f) => f.p));
    const cands = path.isAbsolute(w) ? [path.resolve(w)] : bases.map((b) => path.resolve(b, w));
    let any = false;
    for (const c of cands) {
      const key = (gd ? "g:" : "d:") + c;
      if (seen.has(key)) { any = any || seen.get(key); continue; }
      const ok = isDir(c, gd);
      seen.set(key, ok);
      if (!ok) continue;
      any = true;
      if (found.length >= 64) { bad = "more than 64 target directories"; return false; }
      found.push({ p: c, gd: gd });
    }
    return any;
  };
  // The raw text, and the view with tight quotes dropped that the rules
  // also read (`git "-C" dir commit`). A `\` + newline joins lines.
  const views = [cmd.split("\\\n").join(" ")];
  views.push(dequoteTight(views[0]));
  const gitWords = [];
  const flagged = [];
  for (const v of views) {
    n = 0;
    let words = 0;
    let flags = 0;
    CD_WORD.lastIndex = 0;
    let c;
    while (bad === null && (c = CD_WORD.exec(v)) !== null) {
      if (c[1] === "popd") { bad = "popd"; break; }
      if (c[2] === undefined) {
        if (c[1] === "pushd") { bad = "pushd"; break; }
        add("~", false, "cd");
        continue;
      }
      if (c[2] === "-" || (c[1] === "pushd" && /^[+-][0-9]+$/.test(c[2]))) { bad = c[1] + " " + c[2]; break; }
      add(c[2], false, c[2]);
    }
    GIT_ENV.lastIndex = 0;
    let e;
    while (bad === null && (e = GIT_ENV.exec(v)) !== null) {
      add(e[2] === undefined ? "" : e[2], e[1] === "DIR", "GIT_" + e[1] + "=" + (e[2] || ""));
    }
    GIT_AT.lastIndex = 0;
    let g;
    while (bad === null && (g = GIT_AT.exec(v)) !== null) {
      words++;
      let pos = GIT_AT.lastIndex;
      let o;
      GIT_OPT.lastIndex = pos;
      while (bad === null && (o = GIT_OPT.exec(v)) !== null) {
        pos = GIT_OPT.lastIndex;
        if (o[1] !== undefined) { if (add(o[1], false, o[1])) flags++; }
        else if (o[2] !== undefined) {
          if (add(o[3], o[2] === "git-dir", o[3]) && o[2] === "git-dir") flags++;
        }
      }
      const pre = GIT_DIR_PREFIX.exec(v.slice(Math.max(0, g.index - 8192), g.index));
      if (pre !== null && add(pre[1], true, "GIT_DIR=" + pre[1])) flags++;
      GIT_AT.lastIndex = pos;
    }
    gitWords.push(words);
    flagged.push(flags);
  }
  // The cwd leaves the set only when the command provably never runs git
  // there: (a) it OPENS with `cd <existing dir> &&` and nothing sends the
  // shell back (`cd -`, `popd`, a computed `cd` all set `bad`; a lone `&`
  // runs the `cd` in a subshell); or (b) it holds exactly ONE git word,
  // in both views, and that word carries -C / --git-dir / a GIT_DIR=
  // prefix to an existing path. `git -C feat log; git commit` has two.
  let dropCwd = false;
  const lead = LEAD_CD.exec(views[0]);
  if (lead !== null && !BACKGROUND.test(views[0])) {
    const w = shellWord(lead[1]);
    if (w !== null && isDir(path.resolve(cwd, w), false)) dropCwd = true;
  }
  if (gitWords[0] === 1 && gitWords[1] === 1 && flagged[0] > 0 && flagged[1] > 0) dropCwd = true;
  return { found: found, bad: bad, dropCwd: bad === null && dropCwd };
}

// The command could not be read at all: nothing can be shown to be safe,
// so the only question left is whether a protected branch is in play.
function decideBlind(dirs, why) {
  for (const d of dirs) {
    const b = branchOf(d);
    if (b.kind === "broken") denyUnverifiable(b.why);
    if (b.kind === "norepo") continue;
    if (PROTECTED.indexOf(b.branch) === -1) continue;
    branchSeen = b.branch;
    denyOnBranch(why);
  }
  allow();
}

let input = "";
let ran = false;

function main() {
  let data;
  try { data = JSON.parse(input); } catch { decideBlind([process.cwd()], "the hook input was not valid JSON"); return; }
  if (!data || typeof data !== "object" || Array.isArray(data)) { decideBlind([process.cwd()], "the hook input was not an object"); return; }
  // A missing tool_input or command is NOT an empty command: `|| ""` used
  // to turn `{}` into "" and allow it on master.
  const ti = data.tool_input;
  const cmd = ti && typeof ti === "object" && !Array.isArray(ti) ? ti.command : undefined;
  if (typeof cmd !== "string") { decideBlind([process.cwd()], "the command field was not a string"); return; }
  if (pushTargetsProtectedRef(cmd)) {
    deny("BLOCKED: this push targets main/master. Push your own branch by name (git push -u origin <your-branch>) and merge via a PR on GitHub.");
  }
  if (!movesRefOnCurrentBranch(cmd)) allow();
  // Check the branch of EVERY repo the command may write to, not only the
  // session cwd (run 61): the cwd, unless the command provably leaves it
  // (targetsOf), then each directory it names. Reading the cwd alone
  // blocked legitimate commits in another repo, and reading only the
  // first `-C`/`cd` let a second one commit to master. An existing
  // directory git cannot read (hung, corrupt) DENIES.
  //
  // No remote is no longer an exemption (user decision 2026-09-30): it
  // let any throwaway repo on master take commits. Only the vault is
  // exempt, by the realpath of its toplevel: ~/Vaults/AlxVault is the
  // local-only git safety net of the Obsidian vault, with no PR to go
  // through. A --git-dir / GIT_DIR target is never exempt.
  const t = targetsOf(cmd);
  if (!t.dropCwd) {
    const st = branchOf(process.cwd());
    if (st.kind === "broken") denyUnverifiable(st.why);
    if (st.kind === "branch" && PROTECTED.indexOf(st.branch) !== -1) {
      branchSeen = st.branch;
      if (!isVaultTop(process.cwd())) deny("BLOCKED: on " + safe(st.branch) + ". " + CUT);
    }
  }
  for (const x of t.found) {
    const c = x.gd ? branchOfGitDir(x.p) : branchOf(x.p);
    if (c.kind === "broken") denyUnverifiable(c.why + " in the directory the command targets");
    if (c.kind !== "branch" || PROTECTED.indexOf(c.branch) === -1) continue;
    if (!x.gd && isVaultTop(x.p)) continue;
    deny("BLOCKED: on " + safe(c.branch) + ". " + CUT);
  }
  if (t.bad !== null) {
    denyUnverifiable("the command targets a directory that cannot be resolved (" + safe(String(t.bad).slice(0, 120)) + ")");
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

process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => { if (input.length < 4 * 1024 * 1024) input += c; });
process.stdin.on("end", start);
process.stdin.on("error", start);
