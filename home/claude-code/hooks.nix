# Hook scripts for Claude Code
# All command hooks: read JSON from stdin, exit 0 + JSON stdout
# permissionDecision: "allow" | "deny" | "ask"
# In Nix '' strings: escape single quotes as ''' (two apostrophes + the quote)
{ graphifyReindexPkg, vaultSnapshotPkg }:
{
  hookProtectMain = ''
    #!/usr/bin/env node
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const { execSync } = require("child_process");
      const path = require("path");
      const fs = require("fs");
      try { execSync("git rev-parse --is-inside-work-tree", { stdio: "pipe" }); } catch { process.exit(0); }
      try {
        const branch = execSync("git branch --show-current", { encoding: "utf8" }).trim();
        if (branch !== "main" && branch !== "master") process.exit(0);
        let filePath;
        try {
          const data = JSON.parse(input);
          filePath = data && data.tool_input && data.tool_input.file_path;
        } catch { process.exit(0); }
        if (!filePath) process.exit(0);
        let toplevel;
        try { toplevel = execSync("git rev-parse --show-toplevel", { encoding: "utf8" }).trim(); } catch { process.exit(0); }
        let realTop = toplevel;
        try { realTop = fs.realpathSync(toplevel); } catch {}
        const resolved = path.resolve(filePath);
        let realResolved = resolved;
        try { realResolved = fs.realpathSync(resolved); } catch {}
        if (!realResolved.startsWith(realTop + path.sep)) process.exit(0);
        const reason = "BLOCKED: on " + branch + ". Run: git checkout -b <type>/<desc> (e.g. feat/auth-redirect, fix/nav-crash) then retry.";
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
  '';

  # Turns the APEX routing rule from advice into enforcement. The
  # UserPromptSubmit reminder is text: it is read and then skipped. Measured on
  # 2026-08-08 — 6 file-modifying tasks in one session, APEX invoked on 2.
  #
  # Fires ONCE PER TASK (2026-08-16). It used to fire once per SESSION: the
  # check was a substring scan of the whole transcript, so the first APEX run
  # cleared every later edit — a second request in the same conversation went
  # through with no workflow at all. The scan now walks BACKWARDS from the end
  # and stops at the last real user turn, so only an APEX invoked since that
  # turn counts.
  #
  # "Real user turn" excludes tool_result blocks (138 of the 164 user-typed
  # lines in a measured 937-line transcript) and `! command` lines, which are
  # user input but not a new request.
  #
  # Cost of the change: one deny -> apex -> retry round trip per modifying
  # task, instead of one per session. That is the point.
  #
  # INTERPRETER WRITES (2026-09-25). The Bash door read shell syntax only, so a
  # python/node/ruby script edited the repo unseen. What shipped, as replayed
  # with this hook's own source over the recorded Bash calls: 0 earlier denies
  # lost, in both replays. New denies: +29 over 20 645 rows with the scripts as
  # they are on disk today — most out-of-repo scripts have since been deleted,
  # so the script rule's bulk cannot be re-run that way; +66 over 20 072 unique
  # (cmd, cwd) pairs with deleted scripts served from their recovered text, 42
  # of them script runs, 0 on read-only or module calls (`-m`). The split of
  # those 66 into real edits and false positives has NOT been audited row by
  # row; a false positive costs one stray apex call. `perl -0pi` counts as
  # in-place (21 unique passes before).
  #
  # What still goes through, named so it is not mistaken for coverage:
  #   - a script path held in any `$VAR` other than `$TMPDIR` or a `NAME=value`
  #     set earlier in the same command; a path built at run time;
  #   - a `cd` followed by a relative script path;
  #   - a write done by a CHILD: subprocess, os.system, exec of another tool;
  #   - `python3 <<< "code"` (a here-string) and `<<\EOF` (escaped delimiter);
  #   - `/usr/bin/env python3 -c`, `bun run` / `deno run` of a script,
  #     `uv run python -c`;
  #   - an interpreter after `then`, `do`, `{` or `!` — command position is
  #     read after separators and env/timeout/VAR= prefixes only;
  #   - more than 16 flags before `-c`, or a 5th script in one command;
  #   - a flag taking a SEPARATE argument before `-c` or the script
  #     (`python3 -W ignore -c ...`): the argument reads as the script;
  #   - a quoted variable followed by a bare tail (`python3 "$TMPDIR"/edit.py`);
  #   - `codex exec`, deferred.
  # And one imprecision the other way: the write API is looked for in the
  # WHOLE command, so `python3 -c "print(1)"; echo "open(f, 'w')"` counts the
  # echoed text against the interpreter.
  #
  # FAIL-OPEN on any error, unlike protect-main and block-main-bash. This is a
  # workflow hook, not a safety one: a missed APEX costs little, a session
  # where no edit can land costs a lot.
  hookRequireApex = ''
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
          const noTemp = command.replace(
            /[^\s'"|;&)]*(\$\{?TMPDIR\}?|\/var\/folders\/|\/(private\/)?tmp\/|scratchpad|\/dev\/[a-z]+|\/\.claude\/projects\/[^\s'"|;&)]*\/memory\/)[^\s'"|;&)]*/g,
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
          const AT_CMD = "(^|[\\n|;&]\\s*|\\$\\(\\s*|&&\\s*|\\|\\|\\s*)";
          const WRITES = [
            // `\w`, not `[a-zA-Z]`: `perl -0pi -e` puts a DIGIT before the
            // `i`, and the letter class let 21 recorded in-place edits through.
            /\b(sed|perl|ruby)\b[^|;&]*\s-\w*i\b/,
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
          // those shapes, not a proof of linearity — and the older shell-door
          // passes above still take seconds on some of the same inputs.
          const POS = "(?:^|[\\n|;&(`][ \\t]*|\\$\\([ \\t]*)(?:(?:env|nohup|time|exec|timeout[ \\t]+[^\\s;&|(`]+)[ \\t]+|\\w+=[^\\s;&|(`]*[ \\t]+){0,16}";
          const INTERP = "(?:[^\\s;&|(`]*/)?(?:python[0-9.]*|node|ruby|perl|deno|bun|tsx)";
          // Blanks between words: spaces, tabs, or a backslash-newline.
          const WS = "(?:[ \\t]|\\\\\\n)+";
          const R_INLINE = new RegExp(POS + INTERP
            + "(?:" + WS + "-[\\w=.-]+){0,16}?" + WS + "(?:-[a-zA-Z]*[ce]|--eval)\\b");
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

          let shape = WRITES.some(r => r.test(probe));
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
              + "(?:" + WS + "(?:-[\\w-]+(?:=[^\\s;&|<>()]*)?|--import" + WS + "[^\\s;&|<>()-][^\\s;&|<>()]*|-r" + WS + "[^\\s;&|<>()-][^\\s;&|<>()]*)){0,16}" + WS
              + "(?:\"([^\"\\n]+\\.(?:py|[cm]?js|[cm]?ts|rb|pl))\"|'([^'\\n]+\\.(?:py|[cm]?js|[cm]?ts|rb|pl))'"
              + "|([^\\s;&|<>()'\"`-][^\\s;&|<>()'\"`]*\\.(?:py|[cm]?js|[cm]?ts|rb|pl)))(?=[\\s;&|)]|$)", "g");
            // Quoted text that spans a newline is prose — a commit message
            // listing `python3 /x/e.py` on its second line runs nothing. It is
            // blanked to spaces of the same length, so offsets still line up
            // with `command`.
            // One left-to-right pass, so whichever starts first wins: a quote
            // opens a span only at a word start (after a blank, `=`, `(` or a
            // separator), never mid-word as in `don't`; a `#` at a word start
            // outside quotes is a comment, blanked to the end of its line. An
            // apostrophe in a comment paired with a later quote used to blank
            // the script call between them.
            const scan = command.replace(/(^|[\s=(;&|])('[^']*'|"[^"]*"|#[^\n]*)/g,
              (q, pre, s) => pre + (s[0] !== "#" && s.indexOf("\n") === -1 ? s : " ".repeat(s.length)));
            // The hook runs with the login $TMPDIR; a sandboxed Bash call has
            // its own under /tmp/claude-<uid>. Each is tried, and the first
            // under which the script exists wins. An unset or empty $TMPDIR is
            // dropped, not tried: it would leave `$TMPDIR` in the path.
            const uid = typeof process.getuid === "function" ? process.getuid() : null;
            const tmpdirs = [process.env.TMPDIR];
            if (uid !== null) tmpdirs.push("/tmp/claude-" + uid, "/private/tmp/claude-" + uid);
            const tdCands = tmpdirs.filter(Boolean);
            const ASSIGN = /(?:^|[\s;&|(])([A-Za-z_]\w*)=(?:"([^"]*)"|'([^']*)'|([^\s;&|<>()'"`]*))/g;
            let m;
            let tries = 0;
            while (tries++ < 4 && (m = R_SCRIPT_RAW.exec(scan)) !== null) {
              const tds = /\$\{?TMPDIR\b/.test(command) ? tdCands : [tdCands[0]];
              for (const td of tds) {
                const vars = {};
                const expand = s => s.replace(/\$(?:\{(\w+)\}|(\w+))/g, (all, a, b) => {
                  const n = a || b;
                  if (Object.prototype.hasOwnProperty.call(vars, n)) return vars[n];
                  if (n === "TMPDIR" && td) return td;
                  return all;
                });
                const before = command.slice(0, m.index);
                ASSIGN.lastIndex = 0;
                let a;
                while ((a = ASSIGN.exec(before)) !== null) {
                  const v = a[3] !== undefined ? a[3] : expand(a[2] !== undefined ? a[2] : a[4]);
                  if (v.length <= 4096) vars[a[1]] = v;
                  else delete vars[a[1]];
                }
                const lit = m[2] !== undefined;
                let p = lit ? m[2] : expand(m[1] !== undefined ? m[1] : m[3]);
                // Unresolved under this candidate: try the next, never stop.
                if (!lit && /[$`]/.test(p)) continue;
                // Bash expands `~` only unquoted.
                if (m[3] !== undefined && (p === "~" || p.startsWith("~/"))) p = os.homedir() + p.slice(1);
                const abs = path.resolve(process.cwd(), p);
                if (fs.existsSync(abs)) { scripts.push(abs); break; }
              }
            }
            if (scripts.length === 0) process.exit(0);
          }

          // Only guard writes aimed at a repo. The cwd is the best signal a
          // hook has: it cannot resolve every target path in a shell string.
          try {
            execSync("git rev-parse --is-inside-work-tree", { stdio: "pipe" });
          } catch { process.exit(0); }

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
          + "API — inline code, a heredoc, or a script outside the repo that names this repo) "
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
  '';

  # Turns the React Confidence Gate from advice into a delivered reminder.
  #
  # rules/react.md carries the same content, but a path-scoped rule loads only
  # when a matching file is READ — an edit written from memory, with no prior
  # read, never triggers it. This hook closes that hole: it fires on the write
  # itself.
  #
  # Emits `additionalContext` ONLY, with no permissionDecision. Returning
  # "allow" here would bypass every downstream check — require-apex,
  # protect-main, block-main-bash — on any .tsx edit. Staying silent on the
  # decision keeps the normal permission flow intact.
  #
  # Once per session, keyed on session_id: a React session edits many files and
  # a per-edit reminder would be noise. FAIL-OPEN — a missed reminder costs a
  # doc lookup, never an edit.
  hookReactDocsGate = ''
    #!/usr/bin/env node
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const fs = require("fs");
      const os = require("os");
      const path = require("path");
      try {
        const data = JSON.parse(input);
        const filePath = data.tool_input && data.tool_input.file_path;
        if (!filePath || !/\.(tsx|jsx)$/i.test(filePath)) process.exit(0);

        const sid = String(data.session_id || "nosession").replace(/[^A-Za-z0-9_-]/g, "");
        const stamp = path.join(os.tmpdir(), "claude-react-docs-gate-" + sid);
        if (fs.existsSync(stamp)) process.exit(0);
        try { fs.writeFileSync(stamp, ""); } catch {}

        const ctx = [
          "Stack: React 19 + React Router 7 + TypeScript.",
          "Before writing an API you are not certain of, look it up:",
          "`libdocs react \"<question>\"` or `libdocs rr \"<question>\"`.",
          "The ids are pinned because a raw doc search ranks React Router v5 above v7.",
          "Do not write `useFormState` (v18 name) and do not import from",
          "`react-router-dom` (v7 ships `react-router`).",
          "After writing: pnpm typecheck && pnpm lint --max-warnings 0."
        ].join(" ");

        // Only the nested form carrying hookEventName is documented.
        process.stdout.write(JSON.stringify({
          hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: ctx }
        }));
      } catch (e) {}
      process.exit(0);
    });
  '';

  # PostToolUse gate on the three browser-probe tools. A probe that returns
  # nothing is the most misread result there is: a zero gets reported as a
  # finding when the instrument was never shown to be able to return anything
  # at all. `matched: 0, total: 0` is the signature of that failure.
  #
  # Two INDEPENDENT triggers, because the worst case is the one where they
  # disagree: an `offsetParent` probe returns a non-zero count that is still
  # wrong (it undercounts `position: fixed`). B must be able to fire on a
  # non-null result.
  #
  # BUILT FROM REPLAYED TRAFFIC, not from the shapes that would be convenient
  # to read. The first version scored 33/33 on its own probe and was mute on
  # 190/190 real calls, because the fixtures were invented. Measured over 717
  # local transcripts:
  #   - `tool_response` is a BARE parts array `[{type:"text",text:"…"}]`
  #     (188/190) or a bare string (2/190). The documented `{content:[…]}`
  #     envelope: 0/190.
  #   - the text it carries is a markdown REPORT, not a value:
  #     `### Result\n<json>\n### Ran Playwright code\n…` (186/190).
  # Every rung below is anchored, so both of those made all of them fail.
  #
  # The symmetric failure is a gate that shouts, so each widening is paired
  # with a measured value it must NOT fire on: `{errors:0,warnings:0}` is a
  # CLEAN console, `{x:0,y:0}` is the origin, `getComputedStyle(el).display`
  # is `"none"`, a 404 page title is `"Not Found"`, and `isError:true` is a
  # crash. None of those is an absence. `checks/null-result-gate-probe.sh`
  # asserts both polarities and grades the mutants that prove it.
  #
  # Silence is the default and the only alternative to firing: no stdout, no
  # stderr, exit 0, in every path including a parse failure.
  hookNullResultGate = ''
    #!/usr/bin/env node
    let input = "";
    // Without an explicit encoding, a multi-byte character straddling a 64 KiB
    // chunk boundary is silently replaced by U+FFFD. The messages below are
    // French and every accent is two bytes.
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      try {
        const data = JSON.parse(input);

        // Scope guard. This list must stay EQUAL, in BOTH directions, to the
        // PostToolUse matcher registered for this hook in settings.nix.
        // FAIL-CLOSED: a payload with no `tool_name` is not classified at all.
        const TOOLS = ["mcp__claude-in-chrome__javascript_tool","mcp__playwright__browser_evaluate","mcp__playwright__browser_run_code_unsafe"];
        if (typeof data.tool_name !== "string" || TOOLS.indexOf(data.tool_name) === -1) process.exit(0);

        // Verdicts: only "NULL" fires trigger A. "NON_NULL" and "UNREADABLE"
        // never do — an unreadable shape is not evidence of absence.

        // An MCP content part. A text part must really carry text; a non-text
        // part (image, resource) carries none.
        function isPart(p) {
          return p !== null && typeof p === "object" && !Array.isArray(p)
            && typeof p.type === "string"
            && (p.type !== "text" || typeof p.text === "string");
        }

        // Shared by the BARE parts array and the {content:[…]} envelope — the
        // same payload, with and without its wrapper.
        function readParts(parts, depth) {
          if (parts.length === 0) return "NULL";
          let text = "";
          let seenText = false;
          for (const part of parts) {
            if (part && part.type === "text" && typeof part.text === "string") {
              text += part.text;
              seenText = true;
            }
          }
          // No text part at all: image/resource only. UNREADABLE, never NULL.
          if (!seenText) return "UNREADABLE";
          return classify(text, depth + 1);
        }

        // The body of the FIRST `### …` section, or null when the string does
        // not open on one. A `###` further down is content, not a wrapper, and
        // the section stops at the next one — the real report carries a
        // `### Ran Playwright code` block after the value.
        function resultSection(s) {
          const m = /^###[^\n]*\n/.exec(s);
          if (m === null) return null;
          const body = s.slice(m[0].length);
          const cut = body.search(/\n###/);
          if (cut === -1) return body;
          return body.slice(0, cut);
        }

        // A zero is an absence only when the field it sits in COUNTS
        // something, so the key NAME is part of the test. Measured false
        // positives of the previous "every own value is 0" rung: {x:0,y:0}
        // (the origin), {errors:0,warnings:0} (a CLEAN console — a positive
        // finding reported as a broken instrument), {scrollY:0}. And a
        // non-numeric neighbour no longer disqualifies the record: a
        // {matched:0,total:0,selector:".promo"} is the same signature with a
        // label attached, and {result:{matched:0,total:0}} is it nested.
        const COUNTER_KEY = /^(n|count|total|matched|found|hits|results)$/i;
        function scanCounters(o, depth, acc) {
          if (depth > 2) return;
          for (const k of Object.keys(o)) {
            const n = o[k];
            if (typeof n === "number") {
              if (!Number.isFinite(n)) continue;
              acc.numeric += 1;
              if (n !== 0) acc.allZero = false;
              if (COUNTER_KEY.test(k)) acc.counter = true;
            } else if (n !== null && typeof n === "object" && !Array.isArray(n)) {
              scanCounters(n, depth + 1, acc);
            }
          }
        }
        function allZeroCounters(o) {
          const acc = { numeric: 0, counter: false, allZero: true };
          scanCounters(o, 0, acc);
          return acc.numeric > 0 && acc.counter && acc.allZero;
        }

        function classify(v, depth) {
          // Bounded. A report wrapping a report wrapping a report is not a
          // measurement: stop reading and stay silent.
          if (depth > 5) return "UNREADABLE";
          // R1 — nothing at all.
          if (v === null || v === undefined) return "NULL";
          // R2 — string.
          if (typeof v === "string") {
            const sect = resultSection(v);
            const s = (sect === null ? v : sect).trim();
            if (s === "") return "NULL";
            // A crash is not an absence. The two real errors in the corpus
            // arrive as `Error: ### Error\n…` and used to survive by accident.
            if (/^error\b/i.test(s)) return "UNREADABLE";
            // The section body is the probe's RETURN VALUE, JSON-serialised.
            // Classify the value, never its rendering: this is what tells
            // `"0"` from `"sombre"` and `[]` from `[1,2,3]`.
            let parsed = null;
            let parsedOk = false;
            try { parsed = JSON.parse(s); parsedOk = true; } catch (e) { parsedOk = false; }
            if (parsedOk) return classify(parsed, depth + 1);
            // `none` and `not found` are deliberately ABSENT from this list:
            // `getComputedStyle(el).display === "none"` is the commonest
            // browser measurement there is and it is DECIDED (the element is
            // hidden), and a page title of "Not Found" means the 404 IS the
            // answer. They describe a measured state, not an absence.
            const NULLISH = "0|\\[\\]|\\{\\}|null|undefined";
            const NULLISH_EXTRA = "";
            if (new RegExp("^(" + NULLISH + NULLISH_EXTRA + ")$", "i").test(s)) return "NULL";
            if (/^no (matches|results|hits)\b/i.test(s)) return "NULL";
            return "NON_NULL"; // rung R2
          }
          // R3 — number.
          if (typeof v === "number") {
            if (Number.isNaN(v)) return "UNREADABLE";
            if (v === 0) return "NULL";
            return "NON_NULL"; // rung R3
          }
          // R4 — boolean. DELIBERATE exclusion: a boolean is a decided answer,
          // not an absence. `false` must never be read as a null result.
          if (typeof v === "boolean") return "NON_NULL";
          // R5 — array.
          if (Array.isArray(v)) {
            if (v.length === 0) return "NULL";
            // A BARE parts array is R6's payload with the wrapper stripped,
            // and it is what 188 of 190 measured calls actually return.
            // Reading it as "a non-empty array, therefore an answer" is what
            // made this gate mute on 100 % of its traffic. An array whose
            // elements are not parts stays NON_NULL; a parts array carrying no
            // text part stays UNREADABLE.
            if (v.every(isPart)) return readParts(v, depth);
            return "NON_NULL"; // rung R5
          }
          if (typeof v === "object") {
            // An ERROR is not an absence. Announcing "Résultat NUL" for a
            // probe that crashed is, word for word, the fault this hook exists
            // to correct.
            if (v.isError === true) return "UNREADABLE";
            // R6 — the documented MCP envelope: { content: [ { type, text } ] }.
            // Never seen in the local corpus; kept so the gate does not go
            // mute again the day it starts arriving.
            if (Array.isArray(v.content)) return readParts(v.content, depth);
            const keys = Object.keys(v);
            // R7 — object with no own key.
            if (keys.length === 0) return "NULL";
            // R8 — the `{matched:0,total:0}` signature, and only that.
            if (allZeroCounters(v)) return "NULL";
            // R9 — any other object.
            return "NON_NULL"; // rung R9
          }
          return "UNREADABLE";
        }

        // R0 — the key itself is absent. Nothing was measured, so nothing is
        // null: UNREADABLE, and the hook stays silent.
        const verdict = Object.prototype.hasOwnProperty.call(data, "tool_response")
          ? classify(data.tool_response, 0)
          : "UNREADABLE";

        // Trigger B reads the probe SOURCE without assuming a field name: the
        // three tools disagree on it. MEASURED over the same 190 calls:
        // browser_evaluate carries `function` (188/188), javascript_tool
        // carries `action`/`tabId`/`text` and the source is in `text` (2/2),
        // browser_run_code_unsafe carries `code`.
        let source = null;
        const ti = data.tool_input;
        if (ti && typeof ti === "object") {
          const FIELDS = ["code", "function", "script", "expression", "text"];
          for (const f of FIELDS) {
            if (typeof ti[f] !== "undefined") { source = String(ti[f]); break; }
          }
          if (source === null) {
            try { source = JSON.stringify(ti); } catch (e) { source = null; }
          }
          // ONE bound, on BOTH branches. The previous version capped the
          // fallback at 20 000 characters and left the named-field branch —
          // the only one that runs in production — unbounded: it lost
          // detections exactly where it applied, and protected nothing where
          // it did not.
          const SOURCE_CAP = 1000000;
          if (typeof source === "string" && source.length > SOURCE_CAP) {
            source = source.slice(0, SOURCE_CAP);
          }
        }

        // The idiom must sit in a PROPERTY-ACCESS position. MEASURED false
        // positives of a bare /\boffsetParent\b/: an avoidance comment
        // ("NOT using offsetParent: null for position:fixed"), a string
        // literal (document.title === 'offsetParent tutorial'), a selector
        // ([data-test="offsetParent-demo"]). Scolding a probe that has ALREADY
        // applied the advice is the guard punishing good practice.
        // IRREDUCIBLE and accepted as such: 'offset' + 'Parent' is not caught.
        // A source-text matcher cannot see through concatenation and nothing
        // here pretends to.
        // Extensible: one entry today, the shape takes more.
        const ACCESS = "(?:\\.|\\[\\s*[\"'])";
        const BROKEN = [
          {
            re: new RegExp(ACCESS + "offsetParent\\b"),
            msg: "`offsetParent` est nul pour tout élément `position: fixed` : cette sonde "
              + "sous-compte et peut rendre 0 sur une page pleine de correspondances. Le "
              + "test natif est `el.checkVisibility({checkOpacity:true, checkVisibilityCSS:true})` "
              + "plus `getBoundingClientRect()`."
          }
        ];

        const msgs = [];
        if (verdict === "NULL") {
          msgs.push(
            "Résultat NUL. Un nul n'est pas un constat tant que l'instrument n'a pas rendu "
            + "du positif sur un cas qui DOIT matcher. Avant de le rapporter : exhiber le "
            + "dénominateur (combien ont été scannés), ou relancer la sonde sur un cas qui "
            + "doit matcher. `matched: 0, total: 0` est un instrument cassé, pas un constat."
          );
        }
        if (typeof source === "string" && source.length > 0) {
          for (const b of BROKEN) if (b.re.test(source)) msgs.push(b.msg); // trigger B
        }

        if (msgs.length === 0) process.exit(0);

        // Only the nested form carrying hookEventName is documented.
        process.stdout.write(JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PostToolUse",
            additionalContext: msgs.join(" ")
          }
        }));
      } catch (e) {}
      // NOT process.exit: an exit right after a write truncates on a pipe past
      // ~64 KiB. The message is 389 bytes today; setting the code and letting
      // the loop drain keeps that harmless if it ever grows.
      process.exitCode = 0;
    });
  '';

  # Rewrites APEX's flags before it starts, from risk signals in the task text.
  #
  # The mode gate picks flags from prose, before anything is known about the
  # change — and a typed flag wins over the mode default. Measured on
  # 2026-08-08: `-e` was typed on 3 of 3 invocations, under-powering 2 of them
  # (a 45-rule rewrite and a blocking hook both ran in economy). That evidence
  # is what eventually retired economy mode entirely on 2026-08-17.
  #
  # Rule: a typed flag is a FLOOR, never a ceiling. A risk signal can only
  # raise the tier. `-e` (external verify) is passed through untouched: never
  # stripped, and never added by a risk signal — see the comment below.
  # Uppercase disables the user typed on purpose are preserved.
  #
  # False positives are the intended failure direction: a task that merely
  # mentions "settings" runs more thoroughly than needed. Cheap. The reverse
  # is not.
  #
  # FAIL-OPEN: any error leaves the call untouched.
  hookApexFlags = ''
    #!/usr/bin/env node
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      try {
        const data = JSON.parse(input);
        const ti = data.tool_input || {};
        if (ti.skill !== "apex") process.exit(0);

        const args = typeof ti.args === "string" ? ti.args : "";
        // `nix`, `flake` and `rebuild` were in STANDARD and had to go: in a
        // nix-darwin config repo every task names a .nix file, so they matched
        // everything and made the trivial tier unreachable (that tier was itself
        // removed on 2026-08-17). Measured against the real briefs of
        // 2026-08-08 — a two-line CLAUDE.md edit escalated to -b -s -t -pr
        // purely because the path contained "claude-md.nix".
        // A signal that fires on every task is not a signal.
        const HIGH = /(hook|settings|permission|sandbox|deny|secret|credential)/i;
        const STANDARD = /(supprime|delete|remove|\brm\b|migration|\bmaster\b|\bmain\b|\bprod\b)/i;

        let target;
        // Leading tokens that look like flags; everything after is the task.
        const parts = args.trim().split(/\s+/);
        let i = 0;
        while (i < parts.length && /^-[a-zA-Z0-9]+$/.test(parts[i])) i++;
        const typed = parts.slice(0, i);
        const rest = parts.slice(i).join(" ");

        // -e now means external verify: one cross-vendor read-only pass over
        // the same diff. The hook must never STRIP it — deleting a typed flag
        // makes the feature inert with no error anywhere. And, the operative
        // half, the hook must never ADD it either: a risk signal may raise the
        // depth of a run, but it may not spend another vendor's allowance
        // without the user typing the letter.
        const kept = typed.slice();

        // Branch and save left the flag surface: both are mode invariants now,
        // so the tiers only carry what is still a real flag.
        const isHigh = HIGH.test(args);
        if (isHigh) target = ["-t", "-x", "-pr"];
        else if (STANDARD.test(args)) target = ["-t", "-pr"];
        else process.exit(0);

        // Add what is missing, but never override an explicit uppercase OFF.
        for (const f of (target || [])) {
          const off = "-" + f.slice(1).toUpperCase();
          if (kept.indexOf(f) === -1 && kept.indexOf(off) === -1) kept.push(f);
        }

        const next = (kept.join(" ") + " " + rest).trim();

        // The Fable spend is decided here, by regex, not by the coordinator's
        // judgement mid-run — that judgement is exactly what kept getting
        // skipped. HIGH only: not because the quota is scarce (measured here,
        // 21 Fable spawns against 6489 coordinator messages — it never bound),
        // but because an independent read is worth its round-trip only where a
        // miss is expensive, which is what ORCHESTRATION.md keeps it for.
        const fable = isHigh
          ? "HIGH risk signal in this brief (hook/settings/permission/sandbox/deny/secret/"
            + "credential). The Fable read-only pass is MANDATORY for this run: once the "
            + "machine gate is green, spawn a subagent with an explicit model: fable over "
            + "the REAL diff plus the ACs, then apply its bounded fix-list. Fable is "
            + "read-only — it returns PASS or a fix-list and never edits."
          : null;

        // Emit even when the flags are already right: without this the context
        // is dropped whenever the user typed -t -x -pr themselves.
        const unchanged = next === args.trim();
        if (unchanged && !fable) process.exit(0);

        // When there is nothing to rewrite, send the context ALONE. Adding
        // permissionDecision "allow" here would auto-approve the Skill call and
        // bypass every downstream check, to rewrite nothing.
        if (unchanged) {
          // Only the nested form carrying hookEventName is documented.
          process.stdout.write(JSON.stringify({
            hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: fable }
          }));
          process.exit(0);
        }

        const out = {
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            updatedInput: { skill: ti.skill, args: next }
          }
        };
        // Nested, like its twin twelve lines up. A root-level
        // `additionalContext` is not read by any event: on THIS branch — the
        // frequented one, taken by every bare `/apex` whose flags get
        // rewritten — the Fable instruction reached nobody.
        if (fable) out.hookSpecificOutput.additionalContext = fable;
        process.stdout.write(JSON.stringify(out));
      } catch (e) {}
      process.exit(0);
    });
  '';

  hookFormatTypescript = ''
    #!/usr/bin/env node
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const { execSync } = require("child_process");
      const exts = [".ts", ".tsx", ".js", ".jsx", ".css", ".json"];
      try {
        const data = JSON.parse(input);
        const file = (data.tool_input && data.tool_input.file_path) || "";
        if (file && exts.some(ext => file.endsWith(ext))) {
          execSync("which prettier", { stdio: "pipe" });
          execSync("prettier --write " + JSON.stringify(file), { stdio: "pipe" });
        }
      } catch (e) { process.exit(0); }
      process.exit(0);
    });
  '';

  hookBlockMainBash = ''
    #!/usr/bin/env node

    // Branch-per-change workflow: create a branch BEFORE editing code, then
    // push that branch — never master/main. commit/push/merge/rebase while on
    // master/main are all hard-denied. Bringing code to master = a manual PR
    // step by the user on GitHub, never a Claude action.
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
      // decision here, there is no flag to inspect.
      { id: "write-verb",
        why: "authors a commit, publishes, or moves a ref outright",
        pat: seq(oneOf(/commit|push|merge|rebase|update-ref/), EOW) },

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
    const EXECUTOR =
      /(?:^|[\n;|&(])\s*(?:sh|bash|zsh|dash|ksh|fish|eval|exec|source|\.|sudo|doas|su|env|nohup|timeout|watch|nice|stdbuf|script|xargs|find|parallel|ssh|nix-shell|node|deno|bun|python3?|perl|ruby|awk)(?![\w-])/;
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
          let delim = "";
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
    const hits = (c) => GUARD.some((re) => re.test(stripInertText(c)));
    const movesRefOnCurrentBranch = (c) => hits(c) || hits(dequoteTight(c));

    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const { execSync } = require("child_process");
      const path = require("path");
      const os = require("os");
      try {
        const data = JSON.parse(input);
        const cmd = (data.tool_input && data.tool_input.command) || "";
        if (!movesRefOnCurrentBranch(cmd)) process.exit(0);
        // Check the branch of the repo the COMMAND targets, not the session cwd.
        // `git -C <dir>` and a leading `cd <dir> &&` both retarget it; reading
        // the session cwd blocked legitimate commits in another repo, and let
        // `cd /elsewhere && git commit` through when the cwd was not a repo.
        // Unresolvable target falls back to cwd, so ambiguity fails closed.
        let dir = process.cwd();
        const viaC = cmd.match(/git\s+-C\s+("[^"]+"|'[^']+'|[^\s;&|]+)/);
        const viaCd = cmd.match(/(?:^|&&|;|\|\|)\s*cd\s+("[^"]+"|'[^']+'|[^\s;&|]+)/);
        const raw = (viaC && viaC[1]) || (viaCd && viaCd[1]);
        if (raw) {
          let p = raw.replace(/^["']/, "").replace(/["']$/, "");
          if (p === "~" || p.startsWith("~/")) p = path.join(os.homedir(), p.slice(1));
          const candidate = path.resolve(process.cwd(), p);
          try {
            execSync("git rev-parse --is-inside-work-tree",
              { cwd: candidate, stdio: "pipe" });
            dir = candidate;
          } catch {}
        }
        try {
          execSync("git rev-parse --is-inside-work-tree", { cwd: dir, stdio: "pipe" });
        } catch { process.exit(0); }
        const branch = execSync("git branch --show-current",
          { cwd: dir, encoding: "utf8" }).trim();
        // A repo with NO remote cannot receive a PR, so "merge via PR" has no
        // meaning there and this rule would forbid committing at all. Concrete
        // case: ~/Vaults/AlxVault, the local-only git safety net for the
        // Obsidian vault — this hook blocked three legitimate commits to it.
        // Narrowed, not weakened: repos WITH a remote are still protected
        // exactly as before. Fail-closed on doubt — if `git remote` errors we
        // keep blocking, because a protection that guesses wrong must guess in
        // the safe direction.
        let hasRemote = true;
        try {
          hasRemote = execSync("git remote", { cwd: dir, encoding: "utf8" }).trim().length > 0;
        } catch { hasRemote = true; }
        if (!hasRemote) process.exit(0);
        if (branch === "main" || branch === "master") {
          const reason = "BLOCKED: on " + branch + ". Create a branch first: git checkout -b <type>/<desc> (e.g. feat/auth-redirect). Merge to master happens via PR on GitHub.";
          process.stdout.write(JSON.stringify({
            hookSpecificOutput: {
              hookEventName: "PreToolUse",
              permissionDecision: "deny",
              permissionDecisionReason: reason
            }
          }));
        }
      } catch (e) {}
      process.exit(0);
    });
  '';

  # Save working state before compaction so it can be restored
  hookPreCompactState = ''
    #!/usr/bin/env node
    const fs = require("fs");
    const path = require("path");
    const { execSync } = require("child_process");
    const stateFile = path.join(process.env.HOME, ".claude/compact-state.json");
    try {
      const state = { ts: new Date().toISOString() };
      // Capture modified files
      try {
        state.modifiedFiles = execSync("git diff --name-only 2>/dev/null || true", { encoding: "utf8" }).trim().split("\n").filter(Boolean);
        state.stagedFiles = execSync("git diff --cached --name-only 2>/dev/null || true", { encoding: "utf8" }).trim().split("\n").filter(Boolean);
        state.branch = execSync("git branch --show-current 2>/dev/null || true", { encoding: "utf8" }).trim();
      } catch { state.modifiedFiles = []; state.stagedFiles = []; state.branch = ""; }
      // Capture active plan/context if exists
      try {
        const planDir = ".claude/output";
        if (fs.existsSync(planDir)) {
          const plans = fs.readdirSync(planDir).filter(f => f.endsWith(".md")).slice(-3);
          state.activePlans = plans;
        }
      } catch {}
      // Capture circuit breaker state
      const cbFile = path.join(process.env.HOME, ".claude/circuit-breaker-state.json");
      try { state.circuitBreaker = JSON.parse(fs.readFileSync(cbFile, "utf8")); } catch {}
      fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
    } catch {}
    process.exit(0);
  '';

  # Restore state after compaction via additionalContext
  hookPostCompactRestore = ''
    #!/usr/bin/env node
    const fs = require("fs");
    const path = require("path");
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const stateFile = path.join(process.env.HOME, ".claude/compact-state.json");
      try {
        const state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
        // Skip if state is stale (>1 hour)
        const age = Date.now() - new Date(state.ts).getTime();
        if (age > 3600000) { process.exit(0); return; }
        const parts = [];
        if (state.branch) parts.push("Branch: " + state.branch);
        if (state.modifiedFiles && state.modifiedFiles.length > 0)
          parts.push("Modified files: " + state.modifiedFiles.join(", "));
        if (state.stagedFiles && state.stagedFiles.length > 0)
          parts.push("Staged files: " + state.stagedFiles.join(", "));
        if (state.activePlans && state.activePlans.length > 0)
          parts.push("Active plans in .claude/output/: " + state.activePlans.join(", "));
        if (state.circuitBreaker && state.circuitBreaker.totalTrips > 0)
          parts.push("Circuit breaker trips: " + state.circuitBreaker.totalTrips);
        if (parts.length > 0) {
          const ctx = "POST-COMPACT STATE RESTORE:\n" + parts.join("\n");
          // MEASURED 2026-09-22, and this shape does NOT make the hook work.
          // The official reference lists PostCompact, verbatim, under
          // "None | No decision control. Used for side effects like logging or
          // cleanup", and the document carries no `PostCompact decision
          // control` section at all — both replay in one command each, with no
          // count to rot. So this event
          // honours no additionalContext: whatever is written here reaches
          // nobody. The nested form is kept only so the shape is right the day
          // the event gains one. What actually restores context after a
          // compaction is the SessionStart hook with matcher "compact"
          // (compact-context.sh) — that one is on a channel that exists.
          process.stdout.write(JSON.stringify({
            hookSpecificOutput: { hookEventName: "PostCompact", additionalContext: ctx }
          }));
        }
      } catch {}
      process.exit(0);
    });
  '';

  hookSessionStart = ''
    #!/usr/bin/env bash
    # Guard: graceful handling outside git repos
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      echo "Not a git repo"
      exit 0
    fi
    BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
    LAST_COMMIT=$(git log --oneline -1 2>/dev/null || echo "no commits")
    MODIFIED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    echo "branch: $BRANCH | last: $LAST_COMMIT | modified: $MODIFIED files"
  '';

  # SessionEnd: refresh the AlxVault knowledge graph. Reason for existing: the
  # APEX step-09b text instruction only fires when the model remembers it —
  # measured 2026-08-24, session notes written at 23:09, reindex never launched.
  # A hook fires whether or not the model thinks of it.
  # SessionEnd hooks share a 1.5 s budget, raised to the declared `timeout`
  # (60 s ceiling), so everything here must be a few milliseconds of shell and
  # the real work must leave. `async` detaches the hook from Claude Code's
  # lifecycle; `nohup` is what makes the GRANDCHILD (the reindex itself, minutes
  # long) survive the hook's own death, while the `( … & )` around it double-forks
  # out of the process group, which `nohup` alone does not cover — it only blocks
  # SIGHUP, and a group kill would still take the reindex with it. No matcher on
  # purpose: a malformed matcher silently never matches and the hook never runs —
  # the trap already measured in settings.nix (see the Stop/Bash `if` comment).
  # All five `reason` values mean the same thing here, so `reason` is logged as a
  # trace and never used as logic.
  # No jq, no `stat -c`: this file is deployed by home.file, NOT by
  # writeShellApplication, so it has none of the GNU runtimeInputs. A `stat -c`
  # would produce a rotation that never rotates — a silent failure.
  # Child output goes to this hook's own log deliberately: reindex.log stays
  # empty when the graph is already fresh, so without it nothing would prove the
  # hook ever fired.
  # The order below is the whole point, and each step earns its place. The
  # recursion guard reads only the environment, so it stays first and costs
  # nothing. The log directory is then created, and the log falls back to
  # /dev/null if it still cannot be opened: measured, a missing ~/GraphVault made
  # the `>>` redirection fail, and bash then skips the command entirely — the
  # reindex never left, and nothing recorded that it hadn't. Being unable to
  # trace must never be able to stop the work. Rotation copies and truncates in
  # place instead of renaming, because a `mv` unlinks the inode that the still
  # running `nohup` child holds open in O_APPEND, and every line it would emit —
  # including the `OK — N nodes` verdict that is the only evidence of a real run
  # — disappears with it; the temporary carries `.$$` so two sessions rotating at
  # once cannot clobber each other. The occupancy guard matches `graphify
  # extract` and never `graphify` alone, which would hit the always alive
  # graphify-mcp server and leave the hook permanently mute; if pgrep is missing
  # the hook proceeds rather than fail closed. Finally the work is launched
  # BEFORE stdin is read: everything used to sit downstream of `INPUT=$(cat)`, so
  # an unclosed stdin got the hook killed at the declared timeout and the
  # timeout mitigation turned into a silent no-fire. Reading stdin last means a
  # hanging stdin costs the trace line, not the trigger — and the child's own
  # output into this same log remains proof either way.
  hookGraphifyReindex = ''
    #!/usr/bin/env bash
    if [ -n "''${GRAPHIFY_REINDEX_ACTIVE:-}" ]; then
      SKIP=recursion
    else
      SKIP=
    fi

    HOOKLOG="$HOME/GraphVault/reindex-hook.log"
    mkdir -p "$HOME/GraphVault" 2>/dev/null
    if ! ( : >>"$HOOKLOG" ) 2>/dev/null; then
      HOOKLOG=/dev/null
    fi

    REINDEX="${graphifyReindexPkg}/bin/graphify-reindex"
    TS=$(date '+%Y-%m-%dT%H:%M:%S')

    if [ -f "$HOOKLOG" ]; then
      SIZE=$(wc -c <"$HOOKLOG" 2>/dev/null | tr -d ' ')
      if [ "''${SIZE:-0}" -gt 65536 ] 2>/dev/null; then
        ROTTMP="$HOOKLOG.$$"
        if cp "$HOOKLOG" "$ROTTMP" 2>/dev/null; then
          : >"$HOOKLOG"
          tail -c 32768 "$ROTTMP" >>"$HOOKLOG" 2>/dev/null
        fi
        rm -f "$ROTTMP" 2>/dev/null
      fi
    fi

    if [ -n "$SKIP" ]; then
      printf '%s event=SessionEnd skip=recursion cwd=%s\n' "$TS" "$PWD" >>"$HOOKLOG"
      exit 0
    fi

    if command -v pgrep >/dev/null 2>&1; then
      if pgrep -f 'graphify extract' >/dev/null 2>&1; then
        printf '%s event=SessionEnd skip=busy cwd=%s\n' "$TS" "$PWD" >>"$HOOKLOG"
        exit 0
      fi
    fi

    ( nohup "$REINDEX" >>"$HOOKLOG" 2>&1 </dev/null & )

    INPUT=$(cat)
    REASON=$(printf '%s' "$INPUT" | sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    SESSION=$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    printf '%s event=SessionEnd fire reason=%s session=%s cwd=%s\n' \
      "$TS" "$REASON" "$SESSION" "$PWD" >>"$HOOKLOG"

    exit 0
  '';

  # UserPromptSubmit: stdout is injected into the turn's context. Kept to one
  # short line because this cost is paid on EVERY prompt. Unconditional by
  # design: keyword-matching the prompt would miss exactly the ambiguous cases
  # where the reminder matters most, and a false negative is the failure mode
  # that actually hurts (the rule silently not firing).
  # DUPLICATION: the mode table below is a hand-maintained COPY of the Mode
  # Gate table in skills.nix (apexStep00Init -> step-00-init.md), not derived
  # from it. Any change to that table MUST be mirrored here by hand. It has
  # already drifted twice: (1) the trivial tier was removed on 2026-08-17 but
  # this line kept advertising it for months; (2) -o/-n became mode defaults
  # while this line still listed them as opt-in options. When editing the
  # table over there, grep for this line.
  hookApexReminder = ''
    #!/usr/bin/env bash
    echo "Routage: fichier modifié → /apex. Modes: diagnosis=-x -o -n | standard=-t -pr -o -n | haut-enjeu=-t -x -pr -o -n (branch+save = invariants). Options: -q clarif | -f tests-first | -2 divergence | -p prémisses | -k découpage | -v recherche | -e vérif externe. Majuscule désactive. Question sans modification → réponse directe."
    exit 0
  '';

  hookSubagentStop = ''
    #!/usr/bin/env node
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const fs = require("fs");
      const path = require("path");
      try {
        const data = JSON.parse(input);
        const logDir = path.join(process.env.HOME, ".claude/output");
        fs.mkdirSync(logDir, { recursive: true });
        const entry = {
          ts: new Date().toISOString(),
          agent: data.agent_type || data.agent_name || "unknown",
          duration_ms: data.duration_ms || 0,
          summary: (data.task_description || "").slice(0, 200)
        };
        fs.appendFileSync(path.join(logDir, "agent-log.jsonl"), JSON.stringify(entry) + "\n");
      } catch (e) { process.exit(0); }
      process.exit(0);
    });
  '';

  hookTaskCompleted = ''
    #!/usr/bin/env bash
    osascript -e '''display notification "Task completed" with title "Claude Code"''' 2>/dev/null || true
  '';

  hookNotification = ''
    #!/usr/bin/env bash
    osascript -e '''display notification "Attention requise" with title "Claude Code" sound name "Tink"''' 2>/dev/null || true
  '';

  hookCompactContext = ''
    #!/usr/bin/env bash
    echo "Post-compact context: Shell=zsh+starship+nix-darwin | PM=pnpm | Rebuild=sudo darwin-rebuild switch --flake .#alex-mbp | Protected branches: main/master | Commits: EN imperative, type prefix | Read CLAUDE.md + skills before coding"
  '';

  # Quality gate — scan recent changes for anti-patterns on Stop
  hookQualityGate = ''
    #!/usr/bin/env node
    const { execSync } = require("child_process");
    const fs = require("fs");
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      try {
        // Only check if we are in a git repo with changes
        const diff = execSync("git diff --name-only HEAD 2>/dev/null || true", { encoding: "utf8" }).trim();
        if (!diff) { process.exit(0); return; }
        const files = diff.split("\n")
          .filter(f => /\.(ts|tsx|js|jsx)$/.test(f))
          // CLI scripts legitimately use console.log (progress output and
          // machine-readable results parsed by test harnesses). ESLint already
          // ignores scripts/** — keep the quality gate consistent.
          .filter(f => !/(^|\/)scripts\//.test(f))
          // Generated declaration files (wrangler types → worker-configuration.d.ts,
          // worker-secrets.d.ts) carry vendor console.log/any — not our code.
          .filter(f => !/\.d\.ts$/.test(f));
        if (files.length === 0) { process.exit(0); return; }
        // Blocking anti-patterns only (CLAUDE.md non-negotiables). TODO/HACK/FIXME
        // are legitimate work markers — do NOT block the Stop on them.
        const patterns = [
          { re: /console\.log\(/g, msg: "console.log in production code" },
          { re: /:\s*any\b/g, msg: "TypeScript 'any' type" },
          { re: /\balert\s*\(/g, msg: "alert() call" },
          { re: /\bconfirm\s*\(/g, msg: "confirm() call" },
        ];
        const issues = [];
        for (const file of files) {
          try {
            const content = fs.readFileSync(file, "utf8");
            const lines = content.split("\n");
            for (const p of patterns) {
              for (let i = 0; i < lines.length; i++) {
                if (p.re.test(lines[i])) {
                  issues.push(file + ":" + (i+1) + " — " + p.msg);
                }
                p.re.lastIndex = 0;
              }
            }
          } catch {}
        }
        if (issues.length > 0) {
          const ctx = "QUALITY GATE — " + issues.length + " issue(s) in changed files:\n" + issues.slice(0, 10).join("\n");
          // exit 2 BLOCKS the Stop and feeds stderr back to the model so it fixes
          // the anti-patterns before finishing (Stop hooks have no additionalContext).
          process.stderr.write(ctx);
          process.exit(2);
        }
      } catch {}
      process.exit(0);
    });
  '';

  # Governance audit log — append-only log of significant tool calls
  hookGovernanceAudit = ''
    #!/usr/bin/env node
    const fs = require("fs");
    const path = require("path");
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      try {
        const data = JSON.parse(input);
        const logDir = path.join(process.env.HOME, ".claude/audit");
        fs.mkdirSync(logDir, { recursive: true });
        const entry = {
          ts: new Date().toISOString(),
          tool: data.tool_name || "unknown",
          target: "",
          session: data.session_id || ""
        };
        const ti = data.tool_input || {};
        if (ti.file_path) entry.target = ti.file_path;
        else if (ti.command) entry.target = ti.command.slice(0, 200);
        else if (ti.prompt) entry.target = "agent: " + (ti.prompt || "").slice(0, 100);
        fs.appendFileSync(
          path.join(logDir, "audit.jsonl"),
          JSON.stringify(entry) + "\n"
        );
      } catch {}
      process.exit(0);
    });
  '';

  hookCircuitBreaker = ''
    #!/usr/bin/env node
    const fs = require("fs");
    const path = require("path");
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const stateFile = path.join(process.env.HOME, ".claude/circuit-breaker-state.json");
      let state = { consecutiveFailures: 0, totalTrips: 0, lastTool: "", lastError: "" };
      try { state = JSON.parse(fs.readFileSync(stateFile, "utf8")); } catch {}
      try {
        const data = JSON.parse(input);
        state.consecutiveFailures++;
        state.lastTool = data.tool_name || "unknown";
        state.lastError = (data.error || "").slice(0, 200);
        let ctx = "";
        if (state.consecutiveFailures >= 5) {
          state.totalTrips++;
          state.consecutiveFailures = 0;
          ctx = "CIRCUIT BREAKER TRIPPED (" + state.totalTrips + " total). STOP retrying the same approach. Step back, re-read the code, and try a structurally different solution.";
        } else if (state.consecutiveFailures >= 3) {
          ctx = "WARNING: " + state.consecutiveFailures + " consecutive tool failures on " + state.lastTool + ". Consider a different approach before continuing.";
        }
        fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
        if (ctx) {
          // Only the nested form carrying hookEventName is documented.
          process.stdout.write(JSON.stringify({
            hookSpecificOutput: { hookEventName: "PostToolUseFailure", additionalContext: ctx }
          }));
        }
      } catch {}
      process.exit(0);
    });
  '';

  hookCircuitBreakerReset = ''
    #!/usr/bin/env node
    const fs = require("fs");
    const path = require("path");
    let input = "";
    process.stdin.on("data", c => input += c);
    process.stdin.on("end", () => {
      const stateFile = path.join(process.env.HOME, ".claude/circuit-breaker-state.json");
      try {
        const state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
        if (state.consecutiveFailures > 0) {
          state.consecutiveFailures = 0;
          fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
        }
      } catch {}
      process.exit(0);
    });
  '';

  hookStopFailure = ''
    #!/usr/bin/env bash
    # Alert on rate limits or API failures
    INPUT=$(cat)
    if echo "$INPUT" | grep -qi "rate.limit\|429\|overloaded"; then
      osascript -e '''display notification "Rate limit hit — pause recommended" with title "Claude Code" sound name "Basso"''' 2>/dev/null || true
    fi
  '';

  # Complements the native `rtk hook claude`: the native hook only rewrites
  # rtk's built-in command list, NOT commands covered by custom filters.toml
  # entries (verified 2026-07). This rewrites the nix commands our user-global
  # filters handle. Disjoint from the native list — no double-rewrite possible.
  hookRtkNixRewrite = ''
    #!/usr/bin/env bash
    INPUT=$(cat)
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

    [ "$TOOL_NAME" = "Bash" ] || exit 0
    command -v rtk >/dev/null 2>&1 || exit 0

    # Simple commands only (compound/for/pipe lines won't match) — never double-wrap
    if echo "$COMMAND" | grep -qE '^(nix-instantiate|nixfmt) '; then
      echo "$INPUT" | jq '{hookSpecificOutput: {hookEventName: "PreToolUse", updatedInput: (.tool_input | .command = "rtk " + .command)}}'
    fi
    exit 0
  '';

  # SECURITY hook (prompt-injection), therefore FAIL-CLOSED: it DENIES, it never
  # rewrites. The deny payload shape is the one proven in production here
  # (hookBlockMainBash); a bare `updatedInput` without permissionDecision has no
  # observable effect on Bash, and adding permissionDecision:"allow" would
  # auto-approve every scrapling call — wrong for a security hook.
  #
  # Detection is deliberately NOT anchored at ^: `hookRtkNixRewrite` above uses
  # `^(nix-instantiate|nixfmt) ` and that shape was MEASURED to be bypassed by
  # compound lines (`cd /tmp && …`, `FOO=1 …`, `…; …`). Harmless for a workflow
  # hook, disqualifying for this one. We match `scrapling extract <subcommand>`
  # anywhere in the line instead, so prefixes, pipes, subshells and absolute
  # paths are all caught.
  # The subcommand list is what keeps it from over-matching: prose mentioning
  # the two words (`grep -r "scrapling extract" home/`) passes, and
  # `scrapling install|shell|mcp|--version` pass untouched — none of them is
  # followed by get/post/put/delete/fetch/stealthy-fetch.
  # Regex is a flat alternation of literals: linear, no nested quantifier, no
  # backtracking (a PreToolUse hook that blows up blocks every Bash call).

  # Encrypted off-machine snapshot at session end. Detached with nohup for the
  # same reason as the reindex: the work must outlive Claude Code's exit, and
  # `timeout` here only bounds the stdin read. Never blocks the session — a
  # failed backup is logged, not surfaced as a hook error.
  #
  # It is the vault's ONLY off-machine copy: ~/Vaults is outside iCloud and no
  # Time Machine destination is configured on this machine.
  hookVaultSnapshot = ''
    #!/usr/bin/env bash
    SNAP="${vaultSnapshotPkg}/bin/vault-snapshot"
    LOG="$HOME/GraphVault/vault-snapshot.log"
    mkdir -p "$HOME/GraphVault" 2>/dev/null

    # One snapshot at a time: parallel sessions ending together would race on
    # the release rotation and could delete a generation that was still the
    # newest proven one.
    if command -v pgrep >/dev/null 2>&1; then
      if pgrep -f "bin/vault-snapshot" >/dev/null 2>&1; then
        printf '%s event=SessionEnd skip=busy\n' "$(date '+%Y-%m-%dT%H:%M:%S')" >>"$LOG"
        exit 0
      fi
    fi

    ( nohup "$SNAP" >>"$LOG" 2>&1 </dev/null & )

    INPUT=$(cat)
    : "$INPUT"
    exit 0
  '';
}
