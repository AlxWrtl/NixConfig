#!/usr/bin/env node
"use strict";
//
// Codex PreToolUse hook — branch protection for SHELL COMMANDS. It FAILS CLOSED.
//
// WHY THIS FILE EXISTS, MEASURED
//
//   protect-main.js is registered on `Edit|Write` and guards the edit tools.
//   In a throwaway repo on `master`, Codex was asked to change a file and did
//   not use an edit tool at all — it ran
//       perl -0pi -e 's/1/2/g' note.txt
//   The matcher never selected the hook, the hook never ran, the file changed
//   on master. On this host the shell is the path the model prefers, so the
//   gap was not an edge case, it was the main road. This is the port of the
//   Claude-side sibling home/claude-code/hooks.nix:hookBlockMainBash, whose
//   whole job is that road.
//
// WHAT THIS GUARD IS, AND WHAT IT IS NOT
//
//   It is a TEXTUAL inspection of a command line, and textual inspection of
//   shell has irreducible limits. It cannot see through:
//     * command substitution — `$(printf 'r''m') -rf x`,
//     * `eval` and friends — `eval "$CMD"`,
//     * variable indirection — `W=rm; $W file`,
//     * a word assembled from quoted fragments the shell rejoins.
//   The repo already knows this (the same limit is recorded for the Claude
//   hooks). So: this is a SERIOUS OBSTACLE, not a seal. It raises the cost of
//   writing to a protected branch from "type the command" to "deliberately
//   obfuscate the command", and the store-resident, read-only script cannot be
//   edited by the agent it constrains. Nothing here should be described as
//   proof that master cannot be written to.
//
// THE DOCTRINE IS THE ONE PROTECT-MAIN USES: DENY UNLESS SAFETY IS PROVEN
//
//   Codex treats every non-zero exit other than 2 as "did not block", so a
//   hook that crashes, hangs or is killed GRANTS what it exists to refuse.
//   Allowing is therefore only ever done from positive knowledge:
//     - the command matches no write-shaped rule      -> nothing to refuse
//     - git says no candidate directory is a worktree -> nothing to protect
//     - git says no candidate branch is protected     -> nothing to protect
//     - the protected repo has NO REMOTE and the command only moves git refs
//       (the vault carve-out, see below)
//   Everything else denies: unparseable stdin, no command field, a command too
//   long to inspect, git missing, git slow, git broken, an uncaught throw.
//
// READ-ONLY MUST STAY ALLOWED
//
//   A branch on which nothing may run is a branch nobody can work on, and a
//   guard that denies `git status` gets disabled by its owner within the day.
//   So the rules describe WRITES — the table below — and a command matching
//   none of them is allowed without so much as a git call.
//
// THE CARVE-OUTS, AND WHICH SIDE EACH WAS TAKEN FROM
//
//   The two Claude hooks carve out different things, because they see
//   different information:
//     * hookProtectMain (Edit|Write) knows the exact target path, so it allows
//       a write that PROVABLY lands outside the worktree. That carve-out is
//       NOT portable here and is deliberately not attempted: a shell command
//       has no single target — globs, relative paths, a `cd` in the middle,
//       substitution — so "outside the worktree" could never be PROVEN, and
//       this hook only ever allows from proof.
//     * hookBlockMainBash (shell) knows the repo, and carves out a repo with
//       NO REMOTE: it cannot receive a PR, so "merge via PR" is meaningless
//       there and the rule would forbid committing at all (the local-only
//       Obsidian vault, three legitimate commits blocked). That one IS ported,
//       and NARROWED: it applies only when every matched rule is in the `git`
//       family, i.e. the command only moves refs. A filesystem write —
//       `perl -pi`, `sed -i`, `rm` — is protect-main's territory, and
//       protect-main has no remote carve-out, so neither does this hook. That
//       is also what keeps the measured failure above covered: a throwaway
//       repo has no remote, and its `perl -0pi` is still refused.
//     * git errors while asking about the remote mean "assume it has one", so
//       doubt keeps the protection rather than dissolving it.
//
// THE WATCHDOG IS LOAD-BEARING (identical argument to protect-main.js)
//
//   Registered with `timeout: 5`; a process the host kills exits with a code
//   that is not 2, i.e. its death grants permission. So the hook refuses
//   ITSELF first, twice over: an unref'd timer at BUDGET_MS for async hangs
//   (stdin that never closes), and a wall-clock DEADLINE shared by every git
//   call, because no JS timer can fire while spawnSync blocks. Change
//   BUDGET_MS and you must change the registered timeout in
//   home/codex/hooks.nix, which must stay strictly above it.
//
// STDOUT HYGIENE
//
//   Codex parses ANY non-empty stdout as JSON — an ANSI escape from a Stop
//   hook is the live bug this module was built to repair. Nothing but the one
//   sanctioned object may reach fd 1. Writes go through fs.writeSync because
//   process.exit() truncates pending asynchronous pipe writes, which would
//   drop the deny payload itself.
//
// THE TOOL NAME IS NOT KNOWN
//
//   The Codex binary carries `shell`, `local_shell` and `bash` as candidate
//   tool names and nothing establishes which one a PreToolUse payload uses.
//   The matcher in hooks.nix covers all three; this file makes the same
//   defence one layer down and reads the command from every plausible field,
//   accepting a STRING or an ARRAY OF STRINGS (the argv form is likely on a
//   `local_shell`-shaped tool). A payload it cannot read is a payload it
//   refuses, not one it waves through.
//
// Invoked as: /run/current-system/sw/bin/node <this file>

const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawnSync } = require("child_process");

const PROTECTED = ["main", "master"];
const BUDGET_MS = 3000; // self-deny deadline; the host kills at 5000
const GIT_MS = 1500; // ceiling for any single git call
const MAX_CMD = 128 * 1024; // longer than this is refused, not truncated
const MAX_DIRS = 4; // candidate worktrees inspected, deadline aside
const DEADLINE = Date.now() + BUDGET_MS;

const CUT =
  "Create a branch first: git checkout -b <type>/<desc> (e.g. feat/auth-redirect, fix/nav-crash), then retry. " +
  "Read-only commands are allowed on this branch; bringing code to master happens through a PR on GitHub.";

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

// Nothing derived from a command line or from git output is echoed verbatim:
// the reason reaches a terminal, and a command is attacker-shaped text.
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

// On a protected branch and unable to prove the command is harmless.
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
      ", so this shell command cannot be shown to be safe. " +
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
function git(args, cwd) {
  const left = DEADLINE - Date.now();
  return spawnSync("git", args, {
    cwd,
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

// { kind: "norepo" } | { kind: "branch", branch } | { kind: "broken", why }
function branchOf(dir) {
  const probe = git(["rev-parse", "--is-inside-work-tree"], dir);
  const probeBroken = gitBroken(probe);
  if (probeBroken) return { kind: "broken", why: probeBroken };
  if (probe.status !== 0) {
    // The ONE benign failure: no repository here, so no branch to protect.
    if (/not a git repository/i.test(String(probe.stderr || "")))
      return { kind: "norepo" };
    return { kind: "broken", why: "git rev-parse failed" };
  }
  // "false" is a bare repo or the inside of a .git directory: no worktree.
  if (String(probe.stdout || "").trim() !== "true") return { kind: "norepo" };

  const br = git(["branch", "--show-current"], dir);
  const brBroken = gitBroken(br);
  if (brBroken) return { kind: "broken", why: brBroken };
  if (br.status !== 0)
    return { kind: "broken", why: "git branch --show-current failed" };
  // Detached HEAD prints nothing, and is not a protected branch.
  return { kind: "branch", branch: String(br.stdout || "").trim() };
}

// "none" | "some" | "unknown". Doubt is "some": the carve-out below only fires
// on a proven absence of remote.
function remoteState(dir) {
  const r = git(["remote"], dir);
  if (gitBroken(r)) return "unknown";
  if (r.status !== 0) return "unknown";
  return String(r.stdout || "").trim().length > 0 ? "some" : "none";
}

// --- the rule table ---------------------------------------------------------
//
// One rule per family of commands, each readable on its own line, each
// carrying the WHY that put it there. A command is refused as soon as ONE rule
// matches ANYWHERE in it — inside a quoted string included, a deliberate
// over-approximation. Two families:
//   git — moves a ref or replays commits. Ported from hookBlockMainBash.
//   fs  — mutates the filesystem. New here, because the Claude side reaches
//         those through protect-main's Edit|Write matcher and this host does
//         not: `perl -0pi` is not an edit tool call, it is a shell command.
// The family decides one thing only: whether the no-remote carve-out applies.

const src = (x) => (typeof x === "string" ? x : x.source);
const seq = (...parts) => parts.map(src).join("");
const oneOf = (...alts) => "(?:" + alts.map(src).join("|") + ")";

// Shared prefix, `git` plus its global options: they may sit between `git` and
// the verb, so `git -C <dir> commit` has to match too. Alternation order is
// load-bearing: `-C <path>` and `-c <k=v>` take a SEPARATE argument and must
// be tried BEFORE the generic option branch. A value is a RUN of quoted
// regions and plain characters, and each character has exactly ONE branch —
// the naive (?:'[^']*'|"[^"]*"|\S)+ shape backtracked exponentially on
// `git -c 'x'"y"` repeated, and a FAILING match never came back.
const GIT =
  /\bgit(?:\s+(?:-[Cc]\s+(?:'[^']*'|'(?![^']*')|"[^"]*"|"(?![^"]*")|[^\s'"])+|--?[A-Za-z][\w-]*(?:=\S+)?))*\s+/;

// End of a verb, or of a short-option cluster. NOT `\b`: `-` is a non-word
// character, so `\b` cannot tell the end of `merge` from the start of
// `merge-base` — a pure read that was denied for exactly that reason.
const EOW = /(?![\w-])/;

// The run of option tokens a rule skips between the verb and the flag it wants.
const OPTS = /(?:\s+-\S+)*\s+/;

// One positional argument: may not start with `-`, holds no shell word
// terminator, and must END on one — otherwise `-q HEAD 2>/dev/null` would count
// `2` as a positional.
const ARG = /[^-\s;&|<>()][^\s;&|<>()]*(?=[\s;&|()]|$)/;

// A short flag can hide in a single-dash cluster (`-qf`, `-qB`). Case IS the
// distinction and nothing here carries an `i` flag: `-b` creates a branch and
// must pass, `-B` resets one and must deny.
const cluster = (letters) => "-[A-Za-z]*[" + letters + "][A-Za-z]*";
const flagged = (verb, ...flags) =>
  seq(oneOf(verb), EOW, OPTS, oneOf(...flags), EOW);

// Reset targets that cannot put foreign code on the current branch: HEAD and
// its ancestors, the upstream shorthands, and origin/upstream refs — the
// resync gesture `git reset --hard origin/master`.
const RESET_SAFE =
  /(?:HEAD(?:[~^][0-9]*)*|@\{u(?:pstream)?\}|(?:origin|upstream)\/(?:master|main|HEAD))(?=[\s;&|()]|$)/;

const GIT_RULES = [
  // Verbs that commit, publish or move a ref on their own.
  {
    id: "git-write-verb",
    why: "authors a commit, publishes, or moves a ref outright",
    pat: seq(oneOf(/commit|push|merge|rebase|update-ref/), EOW),
  },

  // cherry-pick, revert and am REPLAY work onto HEAD, so on master they land
  // code that never passed through a PR. `--abort`/`--quit` create nothing and
  // are the way out of a conflict inherited from before the hook.
  {
    id: "git-replay-verb",
    why: "replays commits onto HEAD, unless it is aborting one",
    pat: seq(
      oneOf(/cherry-pick|revert|am/),
      EOW,
      /(?!\s+--(?:abort|quit)(?![\w-]))/,
    ),
  },

  // symbolic-ref is gated on SHAPE: `symbolic-ref HEAD` and `-q HEAD` are the
  // standard way to READ where HEAD points. Only the delete form and the
  // two-positional write form move a ref.
  {
    id: "git-symbolic-ref-delete",
    why: "-d/--delete drops the ref HEAD points through",
    pat: flagged(/symbolic-ref/, /-d/, /--delete/),
  },
  {
    id: "git-symbolic-ref-write",
    why: "two positionals = repointing HEAD at another branch",
    pat: seq(oneOf(/symbolic-ref/), EOW, OPTS, ARG, OPTS, ARG),
  },

  // branch/checkout/switch are gated on the FLAG, not the verb: denying them
  // wholesale would break the very workflow this hook's own message prescribes.
  {
    id: "git-branch-force",
    why: "-f / --force / -M / -C overwrite an existing branch ref",
    pat: flagged(/branch/, /--force/, cluster("fMC")),
  },
  {
    id: "git-checkout-force",
    why: "-B resets an existing branch onto HEAD, where -b only creates",
    pat: flagged(/checkout/, cluster("B")),
  },
  {
    id: "git-switch-force",
    why: "-C / --force-create is the switch spelling of checkout -B",
    pat: flagged(/switch/, /--force-create/, cluster("C")),
  },

  // A mode flag AIMED AT a commit-ish that is not one of the safe ones drags
  // the branch there, authoring no commit and passing through no PR.
  {
    id: "git-reset-arbitrary-target",
    why: "a mode flag aimed at an arbitrary commit-ish moves the branch there",
    pat: seq(
      flagged(/reset/, /--hard/, /--merge/, /--keep/, /--soft/, /--mixed/),
      /\s+/,
      "(?!" + src(RESET_SAFE) + ")",
      ARG,
    ),
  },

  // These four are spelled `git` and are NOT ref moves: they overwrite or
  // delete files in the worktree, which is protect-main's territory. So they
  // are tagged `fs` and the no-remote carve-out does not reach them — measured
  // here: with the family left at `git`, `git checkout -- .` was ALLOWED on
  // master in a remote-less repo while destroying every uncommitted change.
  {
    id: "worktree-checkout-paths",
    family: "fs",
    why: "`checkout --` overwrites worktree files from the index",
    pat: seq(oneOf(/checkout/), EOW, /[^;&|]*?\s--(?=\s|$)/),
  },
  {
    id: "worktree-restore",
    family: "fs",
    why: "restore exists only to overwrite worktree files",
    pat: seq(oneOf(/restore/), EOW),
  },
  {
    id: "worktree-clean",
    family: "fs",
    why: "clean deletes untracked files (`-n` included: over-approximated)",
    pat: seq(oneOf(/clean/), EOW),
  },
  {
    id: "worktree-stash",
    family: "fs",
    why: "stash rewrites the worktree, unless it is listing or showing one",
    pat: seq(oneOf(/stash/), EOW, /(?!\s+(?:list|show)(?![\w-]))/),
  },
];

// A redirection that lands on a FILE. `2>&1`, `>&2` and the /dev/ sinks are
// excluded by name: without that carve-out `git status > /dev/null 2>&1` — the
// commonest read there is — would be refused and the branch would be unusable.
const REDIRECT =
  /(?:^|[^0-9<>&])[0-9]?>{1,2}\|?\s*(?![&0-9])(?!\/dev\/(?:null|stdout|stderr|tty|fd\/))[^\s;&|<>()]+/;

// An interpreter editing a file IN PLACE — the shape that defeated the edit-
// tool guard: `perl -0pi -e 's/1/2/g' note.txt`. Matched as "the command word,
// then an option token whose short cluster ENDS on `i`", so `-0pi`, `-pi`,
// `-i` and `-i.bak` all hit while `perl -Ilib -e ...` (a read) does not.
const INPLACE =
  /(?:^|[\s;&|(])(?:perl|ruby|sed|gsed|gawk|awk|ex)(?:\s+-[A-Za-z0-9][^\s]*)*\s+-[A-Za-z0-9]*i(?:\.[A-Za-z0-9]*)?(?=[\s;&|)]|$)/;

// A program handed to an interpreter ON THE COMMAND LINE is opaque to textual
// inspection: `python3 -c "open('f','w').write(x)"` writes a file and looks
// like nothing. On a protected branch it is refused rather than guessed at.
// Read-only one-liners lose too — an accepted over-approximation, and this
// repo's own guardrails already forbid `node -e` / `python3 -c` as tooling.
const INLINE_SCRIPT =
  /(?:^|[\s;&|(])(?:python3?|node|deno|bun|ruby|perl|php|osascript|Rscript)(?:\s+-[A-Za-z0-9][^\s]*)*\s+(?:-c|-e|-E|-p|--eval|--exec)(?![\w-])/;

// Commands whose PURPOSE is to change the filesystem. The prefix class admits
// `/bin/rm` and `sudo rm`; the trailing lookahead keeps `rm` from matching
// `rmdir` (the alternation then does) or a file named `rm-tool`.
const WRITER =
  /(?:^|[\s;&|(<>/])(?:tee|cp|mv|rm|rmdir|unlink|ln|install|dd|truncate|shred|touch|mkdir|chmod|chown|chgrp|patch)(?![\w-])/;

const FS_RULES = [
  {
    id: "fs-redirect",
    why: "redirects output into a file",
    pat: REDIRECT,
  },
  {
    id: "fs-inplace-edit",
    why: "edits a file in place through an interpreter (-i)",
    pat: INPLACE,
  },
  {
    id: "fs-inline-script",
    why: "runs an inline program that cannot be inspected for writes",
    pat: INLINE_SCRIPT,
  },
  {
    id: "fs-writer-command",
    why: "runs a command whose purpose is to write, move or delete files",
    pat: WRITER,
  },
];

// Every rule in GIT_RULES needs the `git …` prefix in front of its pattern;
// its FAMILY is a separate question and defaults to "git" — the four worktree
// rules above override it, because what they mutate is files.
const RULES = GIT_RULES.map((r) => ({
  id: r.id,
  why: r.why,
  family: r.family || "git",
  re: new RegExp(src(GIT) + src(r.pat)),
})).concat(
  FS_RULES.map((r) => ({
    id: r.id,
    why: r.why,
    family: "fs",
    re: new RegExp(src(r.pat)),
  })),
);

// --- what the shell can and cannot execute ----------------------------------
//
// The rules test the WHOLE command string. That over-approximation is right
// for CODE and wrong for TEXT: a PR body piped through a heredoc that merely
// MENTIONS `rm -rf` is not a write. Blank out the text the shell CANNOT
// execute, then run the unchanged rules on what is left. Inert = single quotes
// and quoted-delimiter heredocs, plus double quotes and bare heredocs ONLY
// when they hold no `$` and no backtick — those two DO run substitutions, and
// a substitution is never masked.
//
// Masking rewrites every non-space run as `_` and keeps the whitespace, so
// token structure survives and no match can be forged by closing a gap.
//
// Shell quoting is a minefield, so DOUBT RETURNS THE RAW STRING. Three ways
// in: unbalanced quotes or an unterminated heredoc; a quoted token sitting
// where the git VERB goes; a command word that EXECUTES its argument.
const mask = (s) => s.replace(/\S+/g, "_");
const EXECUTOR =
  /(?:^|[\n;|&(])\s*(?:sh|bash|zsh|dash|ksh|fish|eval|exec|source|\.|sudo|doas|su|env|nohup|timeout|watch|nice|stdbuf|script|xargs|find|parallel|ssh|nix-shell|node|deno|bun|python3?|perl|ruby|awk|sed)(?![\w-])/;
const QUOTED_VERB = new RegExp(src(GIT) + src(/["']/));
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
    // Outside quotes a backslash escapes the next char, quotes included.
    if (ch === "\\") {
      out += cmd.slice(i, i + 2);
      i += 2;
      continue;
    }
    if (ch === "'") {
      const j = cmd.indexOf("'", i + 1);
      if (j < 0) return cmd;
      out += mask(cmd.slice(i, j + 1));
      i = j + 1;
      continue;
    }
    if (ch === '"') {
      let j = i + 1;
      while (j < n && cmd[j] !== '"') j += cmd[j] === "\\" ? 2 : 1;
      if (j >= n) return cmd;
      const region = cmd.slice(i, j + 1);
      out += /[$`]/.test(region) ? region : mask(region);
      i = j + 1;
      continue;
    }
    if (ch === "`") {
      const j = cmd.indexOf("`", i + 1);
      if (j < 0) return cmd;
      out += cmd.slice(i, j + 1);
      i = j + 1;
      continue;
    }
    // Heredoc operator. Three `<` is a here-STRING, an ordinary word.
    if (ch === "<" && cmd[i + 1] === "<" && cmd[i + 2] !== "<") {
      let k = i + 2;
      if (cmd[k] === "-") k++;
      while (cmd[k] === " " || cmd[k] === "\t") k++;
      let quoted = false;
      let delim = "";
      if (cmd[k] === "'" || cmd[k] === '"') {
        const q = cmd[k];
        const e = cmd.indexOf(q, k + 1);
        if (e < 0) return cmd;
        quoted = true;
        delim = cmd.slice(k + 1, e);
        k = e + 1;
      } else {
        const m = /^[A-Za-z0-9_.-]+/.exec(cmd.slice(k));
        if (!m) return cmd;
        delim = m[0];
        k += m[0].length;
      }
      pending.push([delim, quoted]);
      out += mask(cmd.slice(i, k));
      i = k;
      continue;
    }
    // Bodies start at the next newline, in the order the operators came.
    if (ch === "\n" && pending.length) {
      out += "\n";
      i++;
      while (pending.length) {
        const h = pending.shift();
        let body = "";
        let closed = false;
        while (i <= n) {
          let e = cmd.indexOf("\n", i);
          if (e < 0) e = n;
          const line = cmd.slice(i, e);
          if (line.trim() === h[0]) {
            i = e < n ? e + 1 : n;
            closed = true;
            break;
          }
          body += line + "\n";
          if (e >= n) {
            i = n;
            break;
          }
          i = e + 1;
        }
        if (!closed) return cmd;
        out += h[1] || !/[$`]/.test(body) ? mask(body) : body;
      }
      continue;
    }
    out += ch;
    i++;
  }
  if (pending.length) return cmd;
  return out;
};

// SECOND VIEW, tested IN ADDITION and never instead, so it can only ever ADD
// refusals: quoting is invisible to the shell but not to a regex, and
// `git 'commit' -m x` was a real bypass. The quote CHARACTERS are dropped only
// around a region whose content holds no whitespace — that condition is the
// whole safety of it, and it is what keeps a PR body such as
// --body "git rebase onto master" inert text. Heredoc delimiters and
// backslash-escaped quotes are skipped.
const dequoteTight = (s) =>
  s.replace(
    /(<<-?[ \t]*|\\)?(?:'([^'\s\\]*)'|"([^"\s\\]*)")/g,
    (m, keep, a, b) => (keep ? m : a === undefined ? b : a),
  );

// Every rule that fires, on either view. The deadline is re-checked between
// rules: a pathological regex cannot be interrupted by the async watchdog, so
// the loop refuses on its own once the budget is spent.
function matchRules(cmd) {
  const views = [stripInertText(cmd), stripInertText(dequoteTight(cmd))];
  const hitList = [];
  for (const r of RULES) {
    if (Date.now() > DEADLINE)
      denyOnBranch("inspecting the command exhausted the hook's time budget");
    if (views.some((v) => r.re.test(v))) hitList.push(r);
  }
  return hitList;
}

// --- reading the payload ----------------------------------------------------

// A string, or an argv array of strings joined back into one line. Anything
// else is "not found", which on a protected branch means refused.
function asCommand(v) {
  if (typeof v === "string" && v.trim() !== "") return v;
  if (Array.isArray(v)) {
    const parts = v.filter((x) => typeof x === "string");
    if (parts.length > 0 && parts.length === v.length) {
      const joined = parts.join(" ");
      if (joined.trim() !== "") return joined;
    }
  }
  return null;
}

const CMD_KEYS = [
  "command",
  "cmd",
  "shell_command",
  "command_line",
  "commandLine",
  "script",
  "argv",
  "args",
];

function commandIn(obj) {
  if (!obj || typeof obj !== "object") return null;
  for (const k of CMD_KEYS) {
    const c = asCommand(obj[k]);
    if (c !== null) return c;
  }
  return null;
}

// The field name is the vendor's, not ours, and so is the nesting: read the
// plausible containers rather than betting on one.
function extractCommand(data) {
  const ti = data.tool_input;
  const containers = [
    ti,
    ti && typeof ti === "object" ? ti.input : null,
    ti && typeof ti === "object" ? ti.arguments : null,
    ti && typeof ti === "object" ? ti.params : null,
    data.input,
    data,
  ];
  for (const c of containers) {
    const cmd = commandIn(c);
    if (cmd !== null) return cmd;
  }
  return null;
}

// --- candidate directories --------------------------------------------------

function isDir(p) {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

function expandHome(p) {
  if (p === "~") return os.homedir();
  if (p.startsWith("~/")) return path.join(os.homedir(), p.slice(2));
  return p;
}

function pushDir(list, p) {
  if (typeof p !== "string" || p.trim() === "") return;
  let abs;
  try {
    abs = path.resolve(expandHome(p));
  } catch {
    return;
  }
  // A directory that does not exist cannot be a worktree, and a nonexistent
  // cwd handed to spawnSync is indistinguishable from a missing git binary.
  if (!isDir(abs)) return;
  if (list.indexOf(abs) === -1 && list.length < MAX_DIRS) list.push(abs);
}

// The session cwd, plus whatever the payload claims it is. Both, not one:
// adding a directory can only add refusals.
function sessionDirs(data) {
  const dirs = [];
  let cwd = null;
  try {
    cwd = process.cwd();
  } catch {
    denyUnverifiable("the hook has no working directory");
  }
  pushDir(dirs, cwd);
  if (data && typeof data === "object") pushDir(dirs, data.cwd);
  if (dirs.length === 0)
    denyUnverifiable("no candidate working directory exists");
  return dirs;
}

// `git -C <dir>` and a leading `cd <dir> &&` retarget the command at another
// repository. Ported from the Claude side, but as an ADDITION: there, the
// retarget REPLACES the cwd; here every candidate is checked, because dropping
// the session cwd would be an allow granted on a guess.
function retargetDirs(cmd) {
  const out = [];
  const viaC = cmd.match(/git\s+-C\s+("[^"]+"|'[^']+'|[^\s;&|]+)/);
  const viaCd = cmd.match(/(?:^|&&|;|\|\|)\s*cd\s+("[^"]+"|'[^']+'|[^\s;&|]+)/);
  for (const m of [viaC, viaCd]) {
    if (!m || !m[1]) continue;
    pushDir(out, m[1].replace(/^["']/, "").replace(/["']$/, ""));
  }
  return out;
}

// --- decisions --------------------------------------------------------------

// The command could not be read at all. Nothing can be shown to be safe, so
// the only question left is whether a protected branch is in play.
function decideBlind(dirs, why) {
  for (const d of dirs) {
    const st = branchOf(d);
    if (st.kind === "broken") denyUnverifiable(st.why);
    if (st.kind === "norepo") continue;
    if (PROTECTED.indexOf(st.branch) === -1) continue;
    branchSeen = st.branch;
    denyOnBranch(why);
  }
  allow();
}

function decide(dirs, hitList) {
  const gitOnly = hitList.every((r) => r.family === "git");
  const lead = hitList[0];
  for (const d of dirs) {
    const st = branchOf(d);
    if (st.kind === "broken") {
      deny(
        "BLOCKED: this shell command " +
          lead.why +
          " (rule " +
          lead.id +
          ") and the branch could not be verified (" +
          st.why +
          "), so main/master cannot be ruled out. " +
          CUT,
      );
    }
    if (st.kind === "norepo") continue;
    if (PROTECTED.indexOf(st.branch) === -1) continue;
    branchSeen = st.branch;
    // The vault carve-out, narrowed to ref-moving commands — see the header.
    if (gitOnly && remoteState(d) === "none") continue;
    deny(
      "BLOCKED: on " +
        safe(st.branch) +
        ": this shell command " +
        lead.why +
        " (rule " +
        lead.id +
        "). " +
        CUT,
    );
  }
  allow();
}

// --- main -------------------------------------------------------------------

let input = "";
let ran = false;

function main() {
  let data = null;
  let parseFail = null;
  try {
    data = JSON.parse(input);
  } catch {
    parseFail = "the hook input was not valid JSON";
  }
  if (!parseFail && (!data || typeof data !== "object"))
    parseFail = "the hook input was not an object";

  const dirs = sessionDirs(data);
  if (parseFail) {
    decideBlind(dirs, parseFail);
    return;
  }

  const cmd = extractCommand(data);
  if (cmd === null) {
    decideBlind(dirs, "the hook input carries no command field");
    return;
  }
  if (cmd.length > MAX_CMD) {
    decideBlind(
      dirs,
      "the command is " + cmd.length + " bytes, too long to inspect",
    );
    return;
  }

  // The read-only fast path: no write-shaped rule fires, so there is nothing
  // to refuse and not one git call is spent on it.
  const hitList = matchRules(cmd);
  if (hitList.length === 0) allow();

  for (const d of retargetDirs(cmd)) pushDir(dirs, d);
  decide(dirs, hitList);
}

function start() {
  if (ran) return;
  ran = true;
  try {
    main();
  } catch (e) {
    // An uncaught throw must never become permission.
    denyOnBranch("the hook itself failed (" + safe(e && e.message) + ")");
  }
  // Unreachable: main() always exits. Belt and braces.
  denyOnBranch("the hook reached no decision");
}

process.on("uncaughtException", (e) => {
  if (settled) return;
  deny(
    "BLOCKED: the shell branch-protection hook crashed (" +
      safe(e && e.message) +
      "), so the branch could not be checked. " +
      CUT,
  );
});

// Covers the async hang only — a sync git hang is bounded by DEADLINE instead,
// because no timer can fire while spawnSync blocks.
const watchdog = setTimeout(() => {
  deny(
    "BLOCKED: the shell branch-protection hook hit its own " +
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
