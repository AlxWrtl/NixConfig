#!/usr/bin/env node
let input = "";
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  const fs = require("fs");
  const path = require("path");
  const os = require("os");
  const { execSync } = require("child_process");
  try {
    const data = JSON.parse(input);

    // Plan mode never writes.
    if (data.permission_mode === "plan") process.exit(0);

    const ti = data.tool_input || {};
    const command = typeof ti.command === "string" ? ti.command : null;

    if (command !== null) {
      // Over 256 K characters the command is not read at all: every pass
      // below is skipped and it counts as a write shape. No recorded
      // call comes near (the longest unique one is 44 497 chars); only
      // a repo without APEX pays for it, as a deny.
      const HUGE = command.length > 262144;

      // THE SECOND DOOR. Edit/Write are not the only way to change a file:
      // `sed -i`, a heredoc or a plain redirection writes just as well, and
      // under bypass-permissions the agent is actively instructed to prefer
      // them over the dedicated tools. Guarding only the Edit door leaves
      // the main entrance open.
      //
      // This is a heuristic and cannot be otherwise: no static check can
      // know what an arbitrary binary writes. It narrows the surface, it
      // does not seal it.

      // ORDER MATTERS. Non-repo targets are blanked FIRST, while their
      // quotes are still attached: stripping quotes earlier turns
      // `touch "$TMPDIR/marker"` into a bare `touch` and the target is lost.
      // Covers $TMPDIR, /tmp, scratchpad, /dev/*, and the memory directory
      // the Edit branch already excludes.
      // No optional ['"] at the ends: an optional quote eats one half of a
      // pair when a temp path sits INSIDE a larger quoted string, the prose
      // pass then finds nothing to pair, and the surviving text re-fires the
      // arrow FP. Real trigger: git commit -m "old -> new, log in /tmp/x".
      // The lookbehind starts a match only at a word start: without it
      // every offset of a 64 KB word retried the whole word (quadratic,
      // 6.8 s). The project-dir class refuses `/`, so `/.claude/projects/`
      // repeated cannot nest one scan inside another (over 30 s).
      const noTemp = HUGE ? "" : command.replace(
        /(?<![^\s'"|;&)])[^\s'"|;&)]*(\$\{?TMPDIR\}?|\/var\/folders\/|\/(private\/)?tmp\/|scratchpad|\/dev\/[a-z]+|\/\.claude\/projects\/[^\s'"|;&)/]*\/memory\/)[^\s'"|;&)]*/g,
        " "
      );

      // Quoted text is prose, not shell syntax. Without this pass a commit
      // message reading "3.21.7 -> 3.21.8" is a redirection, and `gh pr
      // create --body "... -> ..."` is a write. Both were REAL denies when
      // replayed over 869 recorded Bash calls. A quoted redirect TARGET is
      // unwrapped first, so `echo x > "src/f.ts"` still counts as a write.
      const probe = noTemp
        .replace(/(>>?\s*)['"]([^'"]+)['"]/g, "$1$2")
        .replace(/'[^']*'/g, " ")
        .replace(/"[^"]*"/g, " ")
        .replace(/\d?>&\d/g, " ")
        // Blanking a temp TARGET leaves its operator dangling, and `;`, `)`,
        // `<` and a newline's first char all satisfy the redirect test — so
        // `rebuild ... > /tmp/x.log 2>&1; echo` denied. That command is the
        // repair path itself. A target-less redirect before a separator is a
        // bash syntax error, so it can only be a blanking artifact.
        // Must run AFTER the `\d?>&\d` blank above, and the `(?![|&])` is
        // load-bearing: without it backtracking retries `>>?` once `>\|`
        // fails its lookahead and eats the `>` of a legitimate `>| file`.
        .replace(/\d?(>\||>&|>>?(?![|&]))\s*(?=$|[\n;)&|<])/g, " ");

      // Word-shaped commands are anchored to command POSITION. Unanchored,
      // JS `\b` is ASCII-only, so the French "touché" fired \btouch\b — a
      // standing false positive given every reply here is in French.
      // `\n` belongs in the separator class: these transcripts routinely
      // send newline-joined compounds, and `^` is not multiline here.
      // Blanks after a separator are `[ \t]`, not `\s`: `\s` also eats
      // newlines, so 64 K of them was one `\n\s*` try per offset.
      const AT_CMD = "(^|[\\n|;&][ \\t]*|\\$\\([ \\t]*|&&[ \\t]*|\\|\\|[ \\t]*)";
      const WRITES = [
        // `\w`, not `[a-zA-Z]`: `perl -0pi -e` puts a DIGIT before the
        // `i`, and the letter class let 21 recorded in-place edits through.
        // The gap is capped at 1024 chars: `sed ` x16 000 re-scanned the
        // tail from every `sed` (1.7 s).
        /\b(sed|perl|ruby)\b[^|;&]{0,1024}\s-\w*i\b/,
        // The argument class excludes separators, not just whitespace: once
        // a temp target is blanked the word is bare (`tee   && echo`), and
        // a plain \S would happily match the `&` of the next command.
        new RegExp(AT_CMD + "(cp|mv|rsync|truncate|touch|tee|patch)\\s+[^\\s;&|)]"),
        /\d?(>>?|>\||>&(?!\d))\s*[^\s>|&]/,
        /(?:^|[^<])<<-?\s*['"]?[A-Za-z_]/,
        /--(write|fix|in-place)\b/,
        /\bgit\s+(apply|restore|checkout\s+--)/
      ];

      // THE THIRD DOOR: an interpreter. `python3 -c`, `node -e`, `ruby -e`
      // or a heredoc fed to one writes through its own file API, and none
      // of that is shell syntax. These run on `noTemp` — quotes INTACT,
      // because the code is inside them — never on `probe`.
      //
      // POS is command position, past `env`/`timeout N`/`VAR=x` prefixes.
      // R_INLINE and R_HEREDOC were measured over 20 645 recorded Bash
      // calls: 4 and 345 fires, 0 false positives. The obvious simpler
      // detector (inline flag plus any `open(`) made 41.
      //
      // A NEWLINE ENDS A COMMAND. Every class after the separator stops at
      // it: `A=x` on one line and `python3 "$A/e.py"` on the next is an
      // assignment THEN a command, not one prefixed command — and a word
      // list that runs past a newline pins `<<` on the NEXT command.
      //
      // BACKTRACKING, MEASURED. Every option or word loop is written so a
      // run of text splits one way only (`-x` tokens, no `--?` in front of a
      // class that holds `-` itself: that made `python3 --a` x28 run past
      // 20 s), and is capped at 16. Timed on 64 KB adversarial inputs
      // (separators, newlines, `$(node `, `a=b` lines, flag runs, 40 K
      // spaces, `File.open(` x20 000, 64 shapes in all): every regex of
      // this door under 10 ms warm on each. That is a measurement on
      // those shapes, not a proof of linearity. The shell-door passes
      // above are held to the same bar by the probe's fast-64k-* cases.
      const POS = "(?:^|[\\n|;&(`][ \\t]*|\\$\\([ \\t]*)(?:(?:env|nohup|time|exec|timeout[ \\t]+[^\\s;&|(`]+)[ \\t]+|\\w+=[^\\s;&|(`]*[ \\t]+){0,16}";
      const INTERP = "(?:[^\\s;&|(`]*/)?(?:python[0-9.]*|node|ruby|perl|deno|bun|tsx)";
      // Blanks between words: spaces, tabs, or a backslash-newline.
      const WS = "(?:[ \\t]|\\\\\\n)+";
      // A flag that takes its argument as the NEXT word: `-W ignore`,
      // `-r esm`, `--import x`. Read as a plain flag, the argument ended
      // the flag run, so `python3 -W ignore -c ...` and `-W ignore e.py`
      // went unseen. The argument cannot start with `-`, so a flag run
      // still splits one way. `-m` stays a plain flag: a module call ends
      // the scan, and what follows it is the module's argument.
      const SEP_ARG = "(?:-[rWXI]|--(?:import|require|loader|experimental-loader|env-file))" + WS + "[^\\s;&|<>()'\"-][^\\s;&|<>()]*";
      const R_INLINE = new RegExp(POS + INTERP
        + "(?:" + WS + "(?:" + SEP_ARG + "|-[\\w=.-]+)){0,16}?" + WS + "(?:-[a-zA-Z]*[ce]|--eval)\\b");
      const R_HEREDOC = new RegExp(POS + INTERP
        + "(?:[ \\t]+[^\\s<|;&(`]+){0,16}?[ \\t]*<<-?[ \\t]*(['\"]?)\\w+\\1");
      // A file-writing CALL, not a mention. Every call whose first argument
      // is a path refuses `(" ", ...)`: a temp target blanked to a space.
      // There is no bare `cp(` — it matched a script's own helper named cp;
      // Node's is `fs.cp` / `cpSync`, named in full. Bare `rename(`,
      // `truncate(`, `rm(`, `mkdir(`, `unlink(` need an `fs.`/`fsp.` prefix
      // or the `Sync` suffix: `df.rename(columns=...)` renames no file.
      // `File.open(` needs its mode as the SECOND argument: `'app.rb'` is
      // not mode `a`.
      // The blanked-temp refusal allows a Python string prefix (`f' '`,
      // `rb" "`): the blanking keeps the `f` that sat before the quote.
      // `open (` with blanks before the paren is still a call.
      const WRITE_API = /\bopen\s{0,8}\((?!\s*[fFrRbBu]{0,2}\\?['"]\s+\\?['"])[^,()]*(?:\([^()]*\)[^,()]*)?,\s*(?:mode\s*=\s*)?\\?['"][rbt]*[wax+][rwabxt+]*\\?['"]|\bFile\.open\((?!\s*[fFrRbBu]{0,2}\\?['"]\s+\\?['"])[^,()]*(?:\([^()]*\)[^,()]*)?,\s*['"][wa]|\.write_(?:text|bytes)\(|(?:\bshutil\.(?:copy\w*|move|rmtree)|\bos\.(?:rename|replace|remove|unlink|makedirs|mkdir|rmdir|truncate)|\b(?:writeFile|appendFile|copyFile)(?:Sync)?|\b(?:fs|fsp)(?:\.promises)?\.(?:rename|unlink|rm|rmdir|mkdir|truncate|cp)|\b(?:rename|unlink|rm|rmdir|mkdir|truncate|cp)Sync|\bcreateWriteStream|\bFile\.write|\bIO\.write)\((?!\s*[fFrRbBu]{0,2}\\?['"]\s+\\?['"])|\bFileUtils\.|\bopen(?:\s*\(\s*|\s+)(?:my\s+)?\$?\w+\s*,\s*['"]\+?>/;
      // `cd` to a blanked temp dir, bare or still quoted (`cd "$TMPDIR"`
      // leaves `cd " "`): every relative write after it lands in temp,
      // not in the repo. Only a `cd` BEFORE the interpreter counts.
      // `cd " " || exit 1` counts too: a failed cd runs nothing after it.
      const CD_TEMP = /(?:^|[\n;&|][ \t]*)cd[ \t]*(?:"[ \t]*"[ \t]*|'[ \t]*'[ \t]*)?(?=&&|\|\||;|\n|$)/;

      // Shared by the script rule and the codex gate: where a command
      // placed at offset `at` runs, and what its `$NAME`s expand to.
      //
      // Quoted text that spans a newline is prose — a commit message
      // listing `python3 /x/e.py` on its second line runs nothing. It is
      // blanked to spaces of the same length, so offsets still line up
      // with `command`.
      // One left-to-right pass, so whichever starts first wins: a quote
      // opens a span only at a word start (after a blank, `=`, `(` or a
      // separator), never mid-word as in `don't`; a `#` at a word start
      // outside quotes is a comment, blanked to the end of its line. An
      // apostrophe in a comment paired with a later quote used to blank
      // the script call between them. Built once, on first use.
      let scanMemo = null;
      const scanOf = () => {
        if (scanMemo === null) {
          const scan = command.replace(/(^|[\s=(;&|])('[^']*'|"[^"]*"|#[^\n]*)/g,
            (q, pre, s) => pre + (s[0] !== "#" && s.indexOf("\n") === -1 ? s : " ".repeat(s.length)));
          scanMemo = scan;
        }
        return scanMemo;
      };
      // The hook runs with the login $TMPDIR; a sandboxed Bash call has
      // its own under /tmp/claude-<uid>. Each is tried, and the first
      // under which the script exists wins. An unset or empty $TMPDIR is
      // dropped, not tried: it would leave `$TMPDIR` in the path.
      const uid = typeof process.getuid === "function" ? process.getuid() : null;
      const tmpdirs = [process.env.TMPDIR];
      if (uid !== null) tmpdirs.push("/tmp/claude-" + uid, "/private/tmp/claude-" + uid);
      const tdCands = tmpdirs.filter(Boolean);
      const ASSIGN = /(?:^|[\s;&|(])([A-Za-z_]\w*)=(?:"([^"]*)"|'([^']*)'|([^\s;&|<>()'"`]*))/g;
      // `$NAME` as the shell at offset `at` sees it: a `NAME=value` set
      // earlier in the same command (a value over 4096 chars stays
      // UNRESOLVED: the shell has it, the hook does not, so it never
      // falls back to the environment), else `$TMPDIR` as `td`, else the
      // environment. `$PWD` is `expand.pwd`, which the `cd` fold moves.
      // What the names expand to is capped at 4096 chars in all, counted
      // as they are substituted: `$B$B…` over a 4096-char B would build
      // megabytes first. Past the cap the result is `$`, unresolved.
      const makeExpand = (at, td) => {
        const vars = {};
        const expand = s => {
          let len = 0;
          let over = false;
          const r = s.replace(/\$(?:\{(\w+)\}|(\w+))/g, (all, a, b) => {
            if (over) return "";
            const n = a || b;
            let v = all;
            if (Object.prototype.hasOwnProperty.call(vars, n)) { if (vars[n] !== null) v = vars[n]; }
            else if (n === "TMPDIR" && td) v = td;
            // Not set in this command: the Bash call's shell inherits
            // the hook's own environment (TMPDIR aside, handled above),
            // so `$HOME` there is `$HOME` here. Same 4096 cap.
            else if (n === "PWD") v = expand.pwd;
            else if (n !== "TMPDIR" && process.env[n] && process.env[n].length <= 4096) v = process.env[n];
            len += v.length;
            if (len > 4096) { over = true; return ""; }
            return v;
          });
          return over ? "$" : r;
        };
        expand.pwd = process.cwd();
        const before = command.slice(0, at);
        ASSIGN.lastIndex = 0;
        let a;
        while ((a = ASSIGN.exec(before)) !== null) {
          const v = a[3] !== undefined ? a[3] : expand(a[2] !== undefined ? a[2] : a[4]);
          if (v.length <= 4096) vars[a[1]] = v;
          else vars[a[1]] = null;
        }
        return expand;
      };
      // A `cd` in command position, its one argument (double-quoted,
      // single-quoted or bare) and nothing else before a separator.
      // The bare argument is capped at 4096 chars; timed at 1-2 ms on
      // 64 KB of blanks after `cd`, `cd ` x16 000 and `;cd ` x16 000.
      // For the script rule `(cd x)` is read as moving the shell too,
      // which errs toward a deny; the codex whitelist refuses it.
      const CD_ARG = /(?:^|[\n;&|(][ \t]*)cd(?:[ \t]+(?:"([^"\n]*)"|'([^'\n]*)'|([^\s;&|<>()'"`]{1,4096})))?[ \t]*(?=&&|\|\||;|\n|\)|$)/g;
      // Each `cd` in `head` moves the directory, in order, from the
      // cwd. A bare `cd` goes home; `cd -`, or an argument still holding
      // `$` or a backtick, leaves the directory where it was. `$PWD`
      // follows the fold. Only the first 64 are folded: `;cd a` x13 000
      // made a path 13 000 deep, resolved once per `cd` (6 s, fail-open).
      const cdFold = (head, expand) => {
        let dir = process.cwd();
        CD_ARG.lastIndex = 0;
        let c;
        let n = 0;
        while (n++ < 64 && (c = CD_ARG.exec(head)) !== null) {
          expand.pwd = dir;
          let arg;
          if (c[2] !== undefined) arg = c[2];
          else if (c[1] !== undefined) arg = expand(c[1]);
          else if (c[3] !== undefined) {
            arg = c[3] === "~" || c[3].startsWith("~/") ? os.homedir() + c[3].slice(1) : c[3];
            arg = expand(arg);
          } else arg = os.homedir();
          if (arg === "-" || /[$`]/.test(arg)) continue;
          dir = path.resolve(dir, arg);
        }
        expand.pwd = dir;
        return dir;
      };

      // THE FOURTH DOOR: `codex exec` (or `e`, `exec resume`) is an agent
      // that edits the repo itself unless it runs with an explicit
      // `-s read-only` that nothing widens back: a `-c`/`--config` key
      // naming sandbox, approval, permission or profile, `-p`, or a
      // bypass/auto/worktree/add-dir flag. `--help`/`--version` pass.
      // Quoted text and comments are blanked first (same length, so
      // offsets line up with `command`): a prompt saying "-s read-only"
      // whitelists nothing, and a quoted `codex exec` is a mention, not a
      // call. A `$(...)` or backtick span inside double quotes is NOT
      // blanked: `out="$(codex exec "x")"` runs codex. Its end is found
      // by paren depth, past nested quotes and `$(`, within 4098 chars;
      // unclosed by then, the whole string stays visible. After a bare
      // `--` nothing is an option. A backslash-newline
      // is two blanks, so a call split over lines is one call. Option
      // VALUES are read from the raw command, quoted or bare, attached
      // (`-sX`, `--sandbox=X`) or not. At most 64 `codex` words and 4
      // exec calls are read; past either cap the unread rest is graded
      // at the session cwd.
      //
      // WHERE IT IS GRADED: at the session cwd (a repo there denies), and
      // at `-C <dir>` and the dir the `cd`s lead to when those are repos.
      // ONE exemption, a whitelist that fails closed: no `-C`, no
      // danger flag, every `cd` before the call at top level (not in a
      // `(...)` or `$(...)`), at most 64 of them, each resolved, and the
      // last one lands in an EXISTING dir under a temp root ($TMPDIR and
      // the sandbox's, /tmp, /var/folders, a `scratchpad` segment) that
      // is not a git repo. `cd <scratch> && codex exec` works there, not
      // in the repo: 15 of the 16 new codex denies of an earlier draft
      // were that (replay-c3-vs-head.log, new-c3-vs-head.jsonl in the
      // hardening session's scratchpad). Anything the
      // whitelist cannot establish grades at the session cwd.
      // `git rev-parse --show-toplevel` decides, once per distinct dir,
      // 3 dirs at most (past that, a dir counts as a repo); a dir that is
      // gone is not a repo. A call graded nowhere in a repo is no hit,
      // and the command's other shapes are graded as usual.
      let codexHit = false;
      if (!HUGE && command.indexOf("codex") !== -1) {
        const bs = command.replace(/\\\n/g, "  ");
        // One left-to-right pass, linear: a quote opens only at a word
        // start; once a quote finds no partner none later can, so it is
        // not searched for again.
        let cq = "";
        {
          let i = 0;
          let noSq = false;
          let noDq = false;
          let noBt = false;
          const blankIn = t => t.replace(/'[^']*'|"[^"]*"/g, u => " ".repeat(u.length));
          // The `)` closing the `$(` at `k`, or -1 if none within 4098
          // chars. Counts paren depth, skipping quoted sub-strings and
          // nested `$(` (one stack: "p" a paren, "d" a double quote).
          const substEnd = k => {
            const lim = Math.min(bs.length, k + 4098);
            const st = ["p"];
            let j = k + 2;
            while (j < lim) {
              const d = bs[j];
              if (d === "\\") { j += 2; continue; }
              if (st[st.length - 1] === "d") {
                if (d === "\"") st.pop();
                else if (d === "$" && bs[j + 1] === "(") { st.push("p"); j += 2; continue; }
              } else if (d === "'") {
                let e = j + 1;
                while (e < lim && bs[e] !== "'") e++;
                if (e >= lim) return -1;
                j = e;
              } else if (d === "\"") st.push("d");
              else if (d === "(") st.push("p");
              else if (d === ")") { st.pop(); if (st.length === 0) return j; }
              j++;
            }
            return -1;
          };
          while (i < bs.length) {
            const ch = bs[i];
            const ws = i === 0 || /[\s=(;&|`]/.test(bs[i - 1]);
            if (ws && ch === "#") {
              const e = bs.indexOf("\n", i);
              const j = e === -1 ? bs.length : e;
              cq += " ".repeat(j - i);
              i = j;
            } else if (ws && ch === "'" && !noSq) {
              const e = bs.indexOf("'", i + 1);
              if (e === -1) { noSq = true; cq += ch; i++; }
              else { cq += " ".repeat(e + 1 - i); i = e + 1; }
            } else if (ws && ch === "\"" && !noDq) {
              let k = i + 1;
              let out = " ";
              let closed = false;
              while (k < bs.length) {
                const d = bs[k];
                if (d === "\"") { closed = true; break; }
                if (d === "\\" && k + 1 < bs.length) { out += "  "; k += 2; continue; }
                if (d === "$" && bs[k + 1] === "(") {
                  const j = substEnd(k);
                  // Unclosed within the bound: the string is not blanked
                  // (fail closed), as if its quote never closed.
                  if (j === -1) break;
                  out += blankIn(bs.slice(k, j + 1));
                  k = j + 1;
                  continue;
                } else if (d === "`" && !noBt) {
                  const e = bs.indexOf("`", k + 1);
                  if (e === -1) noBt = true;
                  else { out += blankIn(bs.slice(k, e + 1)); k = e + 1; continue; }
                }
                out += " ";
                k++;
              }
              if (!closed) { noDq = true; cq += ch; i++; }
              else { cq += out + " "; i = k + 1; }
            } else { cq += ch; i++; }
          }
        }
        const R_CODEX = new RegExp(POS + "(?:[^\\s;&|(`<>]*/)?codex(?=[ \\t])", "g");
        // Flags that can write outside the dir codex runs in: no
        // exemption. WIDE only undoes `-s read-only`.
        const DANGER = /(?:^|[ \t])(?:--yolo|--add-dir|--dangerously-bypass-approvals-and-sandbox|--approve-for-me|--dangerously-bypass-hook-trust)(?=[ \t=]|$)/;
        const WIDE = /(?:^|[ \t])(?:-p|--profile|--full-auto|--worktree)(?=[ \t=]|$)/;
        const OPT = /(?:^|[ \t])(?:-([scCp])|--(sandbox|config|cd|profile)(?=[ \t=]|$))/g;
        const LONG = { sandbox: "s", config: "c", cd: "C", profile: "p" };
        const blankRaw = q => command[q] === " " || command[q] === "\t" || (command[q] === "\\" && command[q + 1] === "\n");
        // Every `cd`-like word, counted on the blanked text: one the
        // fold below cannot read (`cd -P x`, `then cd x`, `pushd`) voids
        // the exemption.
        const CD_ANY = /(?:^|[\s;&|(`])(?:cd|pushd|popd)(?=[\s;&|)]|$)/g;
        const TEMP_ROOTS = tdCands.filter(t => t.length > 1).map(t => path.resolve(t))
          .concat(["/tmp", "/private/tmp", "/var/folders", "/private/var/folders"]);
        const underTemp = d => TEMP_ROOTS.some(r => d === r || d.startsWith(r + "/")) || /\/scratchpad(?:\/|$)/.test(d);
        const isDir = d => { try { return fs.statSync(d).isDirectory(); } catch { return false; } };
        // Where the `cd`s before offset `end` leave the shell, and
        // whether that is established: every one top level, read, resolved.
        const cdWalk = (end, expand) => {
          const qh = cq.slice(0, end + 1);
          let any = 0;
          CD_ANY.lastIndex = 0;
          while (CD_ANY.exec(qh) !== null) if (++any > 64) return { dir: process.cwd(), ok: false };
          const head = scanOf().slice(0, end + 1);
          let dir = process.cwd();
          let ok = true;
          let n = 0;
          let tries = 0;
          let depth = 0;
          let dp = 0;
          CD_ARG.lastIndex = 0;
          let c = null;
          while (tries++ < 256 && (c = CD_ARG.exec(head)) !== null) {
            const at = c.index + c[0].indexOf("cd");
            // Blank in `cq`: inside quotes, not a command.
            if (qh.slice(at, at + 2) !== "cd") continue;
            n++;
            for (; dp < at; dp++) {
              if (qh[dp] === "(") depth++;
              else if (qh[dp] === ")") depth--;
            }
            expand.pwd = dir;
            let arg;
            if (c[2] !== undefined) arg = c[2];
            else if (c[1] !== undefined) arg = expand(c[1]);
            else if (c[3] !== undefined) {
              arg = c[3] === "~" || c[3].startsWith("~/") ? os.homedir() + c[3].slice(1) : c[3];
              arg = expand(arg);
            } else arg = os.homedir();
            if (depth !== 0) ok = false;
            else if (arg === "-" || /[`$]/.test(arg)) ok = false;
            else dir = path.resolve(dir, arg);
          }
          if (c !== null || n !== any) ok = false;
          expand.pwd = dir;
          return { dir, ok };
        };
        const inRepo = new Map();
        let probes = 0;
        const repoAt = dir => {
          if (!inRepo.has(dir)) {
            let ok = true;
            if (++probes <= 3) {
              try { execSync("git rev-parse --show-toplevel", { cwd: dir, stdio: "pipe" }); } catch { ok = false; }
            }
            inRepo.set(dir, ok);
          }
          return inRepo.get(dir);
        };
        const graded = new Set();
        let x;
        let seen = 0;
        let calls = 0;
        let capped = false;
        while ((x = R_CODEX.exec(cq)) !== null) {
          if (++seen > 64) { capped = true; break; }
          const from = x.index + x[0].length;
          const stop = cq.slice(from).search(/[\n;&|]/);
          // A `$(...)` or backtick span after the call is an argument,
          // never an option.
          let seg = cq.slice(from, stop === -1 ? cq.length : from + stop)
            .replace(/\$\([^()]*\)|`[^`]*`/g, t => " ".repeat(t.length));
          if (!/(?:^|[ \t])(?:exec|e)(?=[ \t]|$)/.test(seg)) continue;
          // A bare `--` ends the options: what follows is the prompt.
          const dd = seg.search(/(?:^|[ \t])--(?=[ \t]|$)/);
          if (dd !== -1) seg = seg.slice(0, dd);
          if (/(?:^|[ \t])(?:-h|--help|-V|--version)(?=[ \t]|$)/.test(seg)) continue;
          if (++calls > 4) { capped = true; break; }
          let ro = false;
          let other = false;
          let danger = DANGER.test(seg);
          let wide = WIDE.test(seg);
          let hasC = false;
          let cdir = null;
          const expand = makeExpand(x.index, tdCands[0]);
          let o;
          OPT.lastIndex = 0;
          while ((o = OPT.exec(seg)) !== null) {
            const f = o[1] || LONG[o[2]];
            // The value's first char, in the RAW command.
            let q = from + OPT.lastIndex;
            if (command[q] === "=") q++;
            else if (!o[1] || blankRaw(q) || q >= command.length) {
              let k = 0;
              while (k++ < 4096 && blankRaw(q)) q += command[q] === "\\" ? 2 : 1;
            }
            const rv = /^(?:'([^'\n]*)'|"([^"\n]*)"|([^\s;&|<>()'"`]*))/.exec(command.slice(q, q + 4098));
            if (f === "s") {
              const sv = rv[1] !== undefined ? rv[1] : rv[2] !== undefined ? rv[2] : rv[3];
              if (sv === "read-only") ro = true;
              else {
                other = true;
                // Unresolved, empty or unknown: fail closed.
                if (sv !== "workspace-write") danger = true;
              }
            } else if (f === "c") {
              const key = /^['"]?[ \t]*([\w.-]*)/.exec(command.slice(q, q + 256))[1];
              if (/sandbox|approval|permission|profile/i.test(key)) { wide = true; danger = true; }
            } else if (f === "C") {
              hasC = true;
              let dp = rv[1] !== undefined ? rv[1] : rv[2] !== undefined ? expand(rv[2]) : rv[3];
              if (rv[3] !== undefined) {
                if (dp === "~" || dp.startsWith("~/")) dp = os.homedir() + dp.slice(1);
                dp = expand(dp);
              }
              if (dp !== "" && (rv[1] !== undefined || !/[$`]/.test(dp))) cdir = dp;
            } else if (f === "p") danger = true;
          }
          if (danger) wide = true;
          if (ro && !other && !wide) continue;
          const w = cdWalk(x.index, expand);
          const exempt = !danger && !hasC && w.ok && isDir(w.dir) && underTemp(w.dir) && !repoAt(w.dir);
          if (exempt) continue;
          graded.add(process.cwd());
          graded.add(w.dir);
          if (cdir !== null) graded.add(path.resolve(w.dir, cdir));
        }
        if (capped) graded.add(process.cwd());
        // The session cwd first: in a repo, one git call settles it.
        codexHit = (graded.has(process.cwd()) && repoAt(process.cwd())) || [...graded].some(repoAt);
      }

      let shape = HUGE || codexHit || WRITES.some(r => r.test(probe));
      if (!shape) {
        const im = R_INLINE.exec(noTemp) || R_HEREDOC.exec(noTemp);
        // `+ 1` keeps the separator the match starts on, so the `&&` after
        // `cd " "` is still there for CD_TEMP's lookahead.
        shape = im !== null && WRITE_API.test(noTemp)
          && !CD_TEMP.test(noTemp.slice(0, im.index + 1));
      }

      // A script FILE run by an interpreter. Its path is read from the RAW
      // command: `noTemp` blanks exactly the scratchpad paths these scripts
      // live in. Quoted or bare; `$TMPDIR`, a bare `~` and a `NAME=value`
      // set earlier in the same command are expanded (a value over 4096
      // chars is dropped, not expanded). Anything else still holding a `$`
      // is unresolvable here, and is let through. Only the first 4 script
      // invocations of a command are looked at: past that, each one costs a
      // rescan of everything before it.
      const scripts = [];
      if (!shape) {
        const R_SCRIPT_RAW = new RegExp(POS + "(?:" + INTERP
          + "|uv[ \\t]+run(?:[ \\t]+python[0-9.]*)?|(?:pnpm[ \\t]+(?:exec|dlx)|npx|pnpx)[ \\t]+(?:tsx|ts-node|vite-node|node))"
          + "(?:" + WS + "(?:-[\\w-]+(?:=[^\\s;&|<>()]*)?|" + SEP_ARG + ")){0,16}" + WS
          + "(?:\"([^\"\\n]+\\.(?:py|[cm]?js|[cm]?ts|rb|pl))\"|'([^'\\n]+\\.(?:py|[cm]?js|[cm]?ts|rb|pl))'"
          + "|([^\\s;&|<>()'\"`-][^\\s;&|<>()'\"`]*\\.(?:py|[cm]?js|[cm]?ts|rb|pl))"
          // A quoted head with a bare tail, `"$TMPDIR"/edit.py`: groups 4
          // and 5, joined before expansion. Three or more pieces are not read.
          + "|\"([^\"\\n]*)\"([^\\s;&|<>()'\"`]+\\.(?:py|[cm]?js|[cm]?ts|rb|pl)))(?=[\\s;&|)]|$)", "g");
        const scan = scanOf();
        let m;
        let tries = 0;
        while (tries++ < 4 && (m = R_SCRIPT_RAW.exec(scan)) !== null) {
          const tds = /\$\{?TMPDIR\b/.test(command) ? tdCands : [tdCands[0]];
          for (const td of tds) {
            const expand = makeExpand(m.index, td);
            // The directory the relative path is read from. `+ 1` keeps
            // the separator the match starts on, for CD_ARG's lookahead.
            const dir = cdFold(scan.slice(0, m.index + 1), expand);
            const lit = m[2] !== undefined;
            let p = lit ? m[2] : expand(m[1] !== undefined ? m[1] : m[3] !== undefined ? m[3] : m[4] + m[5]);
            // Unresolved under this candidate: try the next, never stop.
            if (!lit && /[$`]/.test(p)) continue;
            // Bash expands `~` only unquoted.
            if (m[3] !== undefined && (p === "~" || p.startsWith("~/"))) p = os.homedir() + p.slice(1);
            const abs = path.resolve(dir, p);
            if (fs.existsSync(abs)) { scripts.push(abs); break; }
          }
        }
        if (scripts.length === 0) process.exit(0);
      }

      // Only guard writes aimed at a repo. The cwd is the best signal a
      // hook has: it cannot resolve every target path in a shell string.
      // A codex hit was already graded where codex runs.
      if (!codexHit) {
        try {
          execSync("git rev-parse --is-inside-work-tree", { stdio: "pipe" });
        } catch { process.exit(0); }
      }

      // The script branch denies only a script OUTSIDE the repo that both
      // writes and names this repo's toplevel — as a whole path, so
      // `<top>-tools/x` is not `<top>`. An in-repo script passed the gate
      // when it was created. Both sides are realpath'd: git answers
      // /private/var where the command may say /var. The file is opened
      // ONCE, non-blocking (a FIFO named x.py must not hang the hook), and
      // type and size are read from that same descriptor.
      if (scripts.length > 0) {
        const top = fs.realpathSync(execSync("git rev-parse --show-toplevel", { encoding: "utf8", stdio: "pipe" }).trim());
        const NAMES_TOP = new RegExp(top.replace(/[.*+?^$()[\]{}|\\]/g, "\\$&") + "(?![\\w.-])");
        let hit = false;
        for (const s of scripts) {
          try {
            const real = fs.realpathSync(s);
            if (real === top || real.startsWith(top + "/")) continue;
            const fd = fs.openSync(real, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK);
            let src = "";
            try {
              const st = fs.fstatSync(fd);
              if (!st.isFile() || st.size > 262144) continue;
              const buf = Buffer.alloc(st.size);
              src = buf.toString("utf8", 0, fs.readSync(fd, buf, 0, st.size, 0));
            } finally { fs.closeSync(fd); }
            if (WRITE_API.test(src) && NAMES_TOP.test(src)) { hit = true; break; }
          } catch (e) {
            // Unreadable or vanished: this script proves nothing, and an
            // error never denies. The next one is still looked at.
          }
        }
        if (!hit) process.exit(0);
      }
    } else {
      // NotebookEdit sends notebook_path, not file_path. It has been in the
      // matcher and unread the whole time — a dead letter until now.
      const filePath = ti.file_path || ti.notebook_path;
      if (!filePath) process.exit(0);
      const resolved = path.resolve(filePath);

      // Memory writes are not project work.
      if (/\/\.claude\/projects\/[^/]+\/memory\//.test(resolved)) process.exit(0);

      // Outside any git repo — scratchpad, /tmp, $TMPDIR. Not project work.
      try {
        execSync("git rev-parse --is-inside-work-tree", {
          cwd: path.dirname(resolved), stdio: "pipe"
        });
      } catch { process.exit(0); }
    }

    // Match the structured Skill call, never the word "apex": a
    // conversation that merely discusses APEX would match a bare grep.
    const t = data.transcript_path;
    if (!t || !fs.existsSync(t)) process.exit(0);

    const APEX = "\"name\":\"Skill\",\"input\":{\"skill\":\"apex\"";
    const lines = fs.readFileSync(t, "utf8").split("\n");

    // Walk backwards: whichever comes first decides. An APEX call before
    // any user turn means APEX ran for THIS task -> pass. A user turn
    // first means this is a new request with no APEX yet -> deny.
    let ranForThisTask = false;
    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i];
      if (!line) continue;

      if (line.indexOf(APEX) !== -1) { ranForThisTask = true; break; }

      // Cheap reject before the JSON.parse cost.
      if (line.indexOf("\"type\":\"user\"") === -1) continue;

      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      if (msg.type !== "user") continue;

      // Harness-injected content, written with the user role but never
      // typed by anyone. This one is load-bearing: invoking a Skill writes
      // the skill's own body back as an isMeta user line, AFTER the Skill
      // marker. Without this skip the backwards walk hits that line first
      // and denies forever — apex plants a fresh one on every retry.
      // Replayed over 4 real transcripts: 161/161 historical edits denied.
      if (msg.isMeta === true) continue;

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

      break; // a real user turn, reached before any APEX call
    }
    if (ranForThisTask) process.exit(0);

    // The message says "can write", not "writes". WRITES matches SHAPES —
    // a redirect, an in-place edit, a heredoc, cp/mv/tee — because a hook
    // cannot resolve a shell string into an actual target. `cat <<EOF`
    // with no redirect writes nothing and still trips it; saying "this
    // edit modifies a project file" there is simply false, and it sent a
    // reader hunting for a file that was never touched.
    const reason = "BLOCKED: this command has a file-writing SHAPE (redirect, in-place "
      + "edit, heredoc, cp/mv/tee, or a python/node/ruby/perl script that calls a write "
      + "API — inline code, a heredoc, or a script outside the repo that names this repo; "
      + "or `codex exec` without an explicit, unwidened `-s read-only`) "
      + "inside a repo, and APEX has not run for THIS request. "
      + "The gate matches shapes, not proven writes — a heredoc trips it even with no "
      + "redirect, so prefer the Write tool. "
      + "Invoke the apex skill first — nothing to type: the Mode Gate picks the depth on "
      + "its own. "
      + "Fires once per task; every edit after APEX starts passes until your next message.";
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: reason
      }
    }));
  } catch (e) {}
  process.exit(0);
});
