# Wiring gate for the Claude Code hooks under home/claude-code/.
#
# THE ONE THIS FILE EXISTS FOR: nothing in `nix flake check` tied a hook FILE
# to the `command` that registers it. `checks/claude-config.nix` asserts on the
# settings JSON and never looks at a hook path; the only detector that ever
# noticed an inert hook, `checks/null-result-gate-probe.sh`, says in its own
# header that it is not wired into `nix flake check` — so it runs on a human
# keystroke or never. An edit that unregisters a hook, or registers one that is
# not installed, left the build GREEN. That invariant exists on the Codex side
# (C2 of checks/codex-config.nix) and existed nowhere on the Claude side.
#
# Three properties, all of them silent when they break:
#   A. the wiring is a bijection — an installed hook nobody registers is dead
#      text, a registered hook nobody installs is a path that will not exist;
#   B. the emission shape — the reference documents only the NESTED form
#      {"hookSpecificOutput":{"hookEventName":…,"additionalContext":…}}, and a
#      root-level `additionalContext` is dropped without a word;
#   C. the declared event — a hook that writes hookEventName: "PostToolUse"
#      while registered under PreToolUse is ignored, silently.
#   D. the branch guards fail CLOSED — protect-main and block-main-bash used to
#      `exit 0` on bad JSON, on a missing or hung git, on any throw: every
#      doubt became an allow, and nothing but a run shows it. So the installed
#      bodies are RUN against fixture repos, each under the timeout its
#      registration gives the host, and format-typescript is fed a file path
#      carrying `$(…)` to prove the path never reaches a shell. A canary (the
#      body with one branch put back the way it was) must turn its case red
#      for the right reason, and exists for these branches only: malformed
#      JSON and a missing git in protect-main; its time budget under the host
#      timeout; malformed JSON, a broken git in the cwd and a broken git in a
#      `cd` target in block-main-bash; its linear executor scan on a newline
#      flood; the two argv calls in format-typescript. Run 61 adds: `pull` as a
#      ref move, every command target (not the first), the file's own repo
#      in protect-main, `notebook_path`, and the vault exemption — the last
#      two killed on an allow case, as an over-block. Run 62 adds
#      correction-budget: the cap on correction rounds per run (the third
#      marked round is denied, a SendMessage re-brief counted alongside) and
#      the marker a brief naming 06-resolve.md or a correction round must
#      carry. Run 64 adds format-typescript's prettier-config gate: a file
#      whose project has no prettier config is never written. Run 65 adds
#      the linear `git` prefix: 1000 `-C` before a commit on master. Run 66
#      adds research-model: an Explore or codebase-navigator spawn whose
#      model is not haiku, absent included, is denied. The correction-rounds
#      run adds a correction brief on any model but opus denied before it
#      counts, a user grant read as one more round, and correction-grant: a
#      grant only on a whole `apex: +1 tour` line, only for a spent run.
#      The sandbox-shape run adds lone-excluded-bash: a chain with a
#      non-target segment, a file redirection and a command substitution
#      denied; a quoted `;`, fd duplication and malformed input allowed,
#      the last three killed as over-blocks.
#      The claude-bg removal retires that wrapper: claude-dispatch next to
#      another command, behind VAR= or an absolute path denied, alone
#      allowed; claude-bg chained to git push denied, behind cd && silent.
#      The preliz-localdb run adds pnpm localdb:start/stop to
#      lone-excluded-bash: behind cd &&, piped, with an argument or via
#      pnpm run denied; each alone, chained to each other, and other pnpm
#      scripts allowed.
#      The preliz-deploy run adds pnpm run deploy / deploy:prod: behind
#      cd &&, redirected to a file, piped or with an argument denied; each
#      alone or with 2>&1, and pnpm deploy:prod without run, allowed.
#      The sandbox-escape run adds sandbox-escape-evidence: an escape with
#      no sandbox error in the newest Bash batch denied, an older batch's
#      error, a skill body naming the flag, an allowlisted verb inside
#      quotes and a prompt only naming the flag ignored; evidence anywhere in
#      the batch, behind a non-Bash result, and malformed input allowed.
#      The worktree-env-sync run adds worktree-env-sync.sh, the first bash
#      body D runs: the main checkout's ignored root .env files copied into a
#      new worktree, never over a file there, never through a symlink, never
#      one the main checkout tracks or the worktree does not ignore.
#      The session-state run adds session-state.js, run with its own fixture
#      HOME and ABDUCO_SESSION: the state per event, the first prompt kept as
#      the intent, a 0600 file in a 0700 dir, stdout always empty; nothing
#      written outside abduco, under a bad name, on malformed input, or
#      through a symlinked state dir or file. Its one canary drops the
#      ABDUCO_SESSION gate.
#      The apex-output run adds protect-main's APEX run-state exemption: a
#      file git ignores and does not track under its own repo's
#      `.claude/output/apex/` allowed on master, a new run dir, another cwd
#      and another case included; a force-added tracked file there, an
#      ignored file elsewhere, a repo that ignores nothing, a symlink or
#      hardlink out and a nested repo on master denied.
#      The apex-pr-record run adds apex-pr-record.js, run against a fixture
#      repo of APEX runs and a stub gh: after a lone `gh pr merge` that
#      merged, pr.md written in the run whose `Branch:` line names the head
#      (every such run), else in a run with no `Branch:` line whose dir is
#      the head's last segment or that names it in its first 12 lines; nothing over an existing pr.md, beside a
#      commit.txt, on a prefix of the name, for a run on another branch, on
#      an OPEN PR, a failed gh, a failed tool, another command or malformed
#      input; the value flags' values never read as the selector. One canary
#      per branch.
#      The worktree-live-guard run adds worktree-in-use.js, run as a copy
#      whose one `const LSOF` literal points at a fake lsof (the build
#      sandbox has no /usr/sbin and no process info): a `git worktree
#      remove` or `rm -r` of a real worktree that a real `sleep` has as cwd
#      denied, naming its pid and command, by path, -C, cd, env -C, $PWD,
#      name (looked up before a plain directory of that name), symlink,
#      parent, braces, or a glob under rm or remove; a non-shell direct
#      parent in the target denied; a missing, hung or bad-exit lsof, or one
#      not listing the hook, denied once a shape matched; a free worktree,
#      prune, a held non-checkout dir, a name-prefix sibling, the hook's own
#      parent shell, `$VAR`, malformed input and a non-shape with no lsof at
#      all allowed. One canary per branch.
#      The board-refresh-budget-runs run adds the cross-repo correction run:
#      an absolute <repo>/.claude/output/apex/<run-id> marker allowed and
#      counted by its run-id, one outside such a dir, through `..` or
#      missing denied; a grant for such a run only from the session whose
#      round stamps name an existing run dir of that shape. One canary per
#      branch, both allows killed as over-blocks.
#      The apex-ac-proof run adds apex-metrics-probe.py, the first python
#      body D runs (`python3 -I <body> --hook`): a Write or Edit of an APEX
#      run's 02-acs.md lists the ACs that name no command and carry no
#      `[lecture] — reason` or `[deferred to user]`, count first and capped;
#      a command, lecture, deferred or AC-docs AC, another file of a run dir,
#      a 02-acs.md outside one, a missing file and malformed input stay
#      silent; `--self-test` of the same body exits 0, so the B2 classifier
#      is graded in the flake. One canary per branch.
#      The step-utility run adds the probe's 04-validate.md branch: a run
#      whose newest external verify is not BLOCKED and whose triage has no
#      `confirmed=N … dismissed=D` tally, or whose 05-examine.md has none,
#      is named in a B5 line; a tally, a BLOCKED verify or a symlinked
#      05-examine.md stays silent. One
#      canary: the tally regex that never matches, killed on the silent case.
#      The memory-consolidation run adds the probe's memory branch: a Write
#      or Edit of a note under .claude/projects/<p>/memory/ names its
#      [[links]] that are no sibling's `name:` slug (the slug offered when
#      the link is a sibling's file stem) and its absence from MEMORY.md;
#      one of MEMORY.md names its links to absent notes. A clean note, the
#      same note outside a memory dir and a symlinked one stay silent. One
#      canary per branch.
#      The run-files-end-check run adds the probe's Bash branch: after a
#      lone, successful `gh pr create`, the newest unfinished run of the
#      branch (git in the cwd, or a `--head` argv token, never one inside a
#      quoted title) that is tiered and not Direct is told the B6 files it
#      lacks, the external tally included; a complete run, a Standard run
#      owing no tally, Direct, untiered, another branch, a finished run, an
#      older incomplete run behind a newer complete one, another command, a
#      failed call, an unsplittable command, no git and a symlinked
#      00-context.md stay silent. One canary per branch, plus the
#      last-Tier-line rule through `--self-test`; D8 asserts at eval that
#      the probe's Bash group puts its `if` on the handler.
#      Every other case is run and graded, with
#      no mutant to show it bites.
#
# The corpus is EVALUATED, not read as text: home/claude-code.nix is imported
# as a module and its `home.file` is the same attrset home-manager installs.
# So this file holds no list of hook names, no line number, and keeps working
# across any edit to hooks.nix or settings.nix.
#
# Runs in `nix flake check`, before any rebuild, from the nix sources.
{ pkgs }:

let
  inherit (pkgs) lib;
  inherit (lib) hasInfix splitString;

  fail = msg: throw "hook-wiring: ${msg}";

  # Only interpolated into path strings; any absolute path gives a
  # deterministic corpus, exactly as in checks/claude-config.nix.
  homeDirectory = "/Users/alx";

  # --- what the module actually installs -----------------------------------
  claudeModule = import ../home/claude-code.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    config = {
      home = {
        inherit homeDirectory;
      };
    };
    # Flake inputs feed only non-hook `.source` links (design-md library, watch skill);
    # this check reads `/hooks/` entries only, so the value is never forced.
    inputs = { };
  };

  # Matched on "/hooks/" rather than on the module's own `claudeDir` constant:
  # this file must not carry a second copy of a value the module owns. If the
  # match ever stops working the corpus goes empty, and A0 below fails on that
  # before any bijection can be vacuously true.
  installedPaths = builtins.filter (n: hasInfix "/hooks/" n) (
    builtins.attrNames claudeModule.home.file
  );
  installed = map baseNameOf installedPaths;
  # `text` first, then a `source` read from disk: a hook moved to `source =`
  # must not scan as an empty body. Neither: a loud failure, never a silent "".
  bodyOf =
    n:
    let
      f = claudeModule.home.file.${n};
    in
    f.text or (
      if f ? source then
        builtins.readFile f.source
      else
        fail "hook ${n} has neither text nor source — its body cannot be scanned"
    );
  bodies = builtins.listToAttrs (
    map (p: {
      name = baseNameOf p;
      value = bodyOf p;
    }) installedPaths
  );

  # --- what settings.json registers ----------------------------------------
  settings = import ../home/claude-code/settings.nix { inherit homeDirectory; };
  parsed = builtins.tryEval (builtins.fromJSON settings.settingsJson);
  jsonOk = parsed.success && builtins.isAttrs parsed.value;
  hookTree = if jsonOk then parsed.value.hooks or { } else { };
  eventNames = builtins.attrNames hookTree;
  groupsOf = e: if builtins.isList (hookTree.${e} or null) then hookTree.${e} else [ ];
  entriesOf = g: if builtins.isList (g.hooks or null) then g.hooks else [ ];
  commandsOf =
    e:
    builtins.concatMap (
      g:
      map (h: {
        event = e;
        command = h.command or "";
        timeout = h.timeout or null;
      }) (entriesOf g)
    ) (groupsOf e);
  registrations = builtins.concatMap commandsOf eventNames;

  # "<interpreter> ~/.claude/hooks/<basename>" — the basename is everything up
  # to the first delimiter, so a command that chains or quotes still resolves.
  marker = "~/.claude/hooks/";
  firstToken =
    s:
    builtins.head (
      splitString " " (builtins.head (splitString "\"" (builtins.head (splitString ";" s))))
    );
  # The same directory spelled through the shell or as an absolute path is
  # folded onto the marker first; otherwise `bash $HOME/.claude/hooks/x.sh`
  # names nothing and a dangling registration passes A2 unseen.
  normalize =
    builtins.replaceStrings
      [
        "$HOME/.claude/hooks/"
        "\${HOME}/.claude/hooks/"
        "${homeDirectory}/.claude/hooks/"
      ]
      [ marker marker marker ];
  hookRefsIn = cmd: map firstToken (builtins.tail (splitString marker (normalize cmd)));

  wired = builtins.concatMap (
    r:
    map (h: {
      inherit (r) event;
      hook = h;
    }) (hookRefsIn r.command)
  ) registrations;
  wiredNames = lib.unique (map (x: x.hook) wired);
  eventsOfHook = n: lib.unique (map (x: x.event) (builtins.filter (x: x.hook == n) wired));

  # --- A: the bijection ----------------------------------------------------
  # Hooks installed on purpose and registered nowhere. Each line is a standing
  # claim that the dead text is intentional; delete the hook or register it and
  # this list must shrink, which is why A4 and A5 below fail on a stale entry.
  knownUnwired = [ ];

  deadHooks = builtins.filter (
    n: !(builtins.elem n wiredNames) && !(builtins.elem n knownUnwired)
  ) installed;
  danglingHooks = builtins.filter (n: !(builtins.elem n installed)) wiredNames;
  ghostExemptions = builtins.filter (n: !(builtins.elem n installed)) knownUnwired;
  resolvedExemptions = builtins.filter (n: builtins.elem n wiredNames) knownUnwired;

  # --- B and C: textual scan of the hook bodies ----------------------------
  #
  # WHAT THIS DETECTOR DOES NOT SEE, stated rather than papered over. It is a
  # guard rail, never a barrier:
  #   - a comment-only line is dropped, a TRAILING comment on a code line is
  #     not: `foo(); // no additionalContext here` still counts as a site;
  #   - nesting is inferred from the text between the last `hookSpecificOutput`
  #     and the site. A sibling key carrying braces before it — `{ …,
  #     updatedInput: { a: 1 }, additionalContext: x }` — reads as closed and
  #     fails. Fail-closed is the safe direction for a guard, but it is a false
  #     positive and the fix is to put additionalContext first;
  #   - a name built at runtime (`o["additional" + "Context"] = x`, a key from
  #     a variable) is invisible, as is anything a hook prints from a file it
  #     reads. Textual matching cannot follow either;
  #   - C compares against the events under which the hook is REGISTERED, so a
  #     hook in knownUnwired has no event to compare to and is skipped;
  #   - A resolves a registered path in four spellings only: `~/`, `$HOME/`,
  #     `${HOME}/` and the literal home directory, each followed by
  #     `.claude/hooks/`. A path built from any other variable, a relative
  #     path or a symlink elsewhere names no hook — neither wired nor dangling.
  #
  # Only comment-only lines are dropped: a `//` mid-line is a URL as often as a
  # comment, and `#` is a shebang on the first line of every script here.
  isCommentLine = l: builtins.match "[[:space:]]*(//|#).*" l != null;
  codeOf =
    body:
    builtins.concatStringsSep "\n" (builtins.filter (l: !(isCommentLine l)) (splitString "\n" body));

  # Every prefix of `text` that ends just before an occurrence of `needle`.
  # Cumulative on purpose: the second site in a body must be judged against
  # everything before it, not against the gap since the first one.
  prefixesOf =
    needle: text:
    let
      segs = splitString needle text;
    in
    builtins.genList (i: builtins.concatStringsSep needle (lib.take (i + 1) segs)) (
      builtins.length segs - 1
    );

  # The site is nested iff a `hookSpecificOutput` is still OPEN in front of it.
  insideHookSpecificOutput =
    prefix:
    let
      ps = splitString "hookSpecificOutput" prefix;
      after = lib.last ps;
    in
    builtins.length ps >= 2 && !(hasInfix "}" after || hasInfix ";" after || hasInfix ")" after);

  contextSites = n: prefixesOf "additionalContext" (codeOf bodies.${n} or "");
  rootLevelSites = n: builtins.filter (p: !(insideHookSpecificOutput p)) (contextSites n);
  # The tail of a prefix, for an error message that points at the offending
  # line instead of at the file.
  excerpt =
    p:
    let
      l = builtins.stringLength p;
    in
    builtins.substring (if l > 90 then l - 90 else 0) 90 p;

  rootLevelOffenders = builtins.filter (n: rootLevelSites n != [ ]) installed;
  totalContextSites = builtins.foldl' (a: n: a + builtins.length (contextSites n)) 0 installed;

  # Every literal `hookEventName: "<X>"` in a body.
  declaredEventsIn =
    n:
    let
      segs = builtins.tail (splitString "hookEventName" (codeOf bodies.${n} or ""));
      valueOf =
        s:
        let
          ps = splitString "\"" s;
        in
        if builtins.length ps >= 2 then builtins.elemAt ps 1 else null;
      ok = v: v != null && builtins.match "[A-Za-z]+" v != null;
    in
    lib.unique (builtins.filter ok (map valueOf segs));

  eventMismatches = builtins.concatMap (
    n:
    let
      under = eventsOfHook n;
      wrong = builtins.filter (e: !(builtins.elem e under)) (declaredEventsIn n);
    in
    if under == [ ] || wrong == [ ] then
      [ ]
    else
      [
        "${n} declares ${builtins.concatStringsSep "/" wrong} but is registered under ${builtins.concatStringsSep "/" under}"
      ]
  ) installed;
  totalDeclaredEvents = builtins.foldl' (a: n: a + builtins.length (declaredEventsIn n)) 0 installed;

  show = xs: if xs == [ ] then "none" else builtins.concatStringsSep ", " xs;

  # --- D: the branch guards, RUN -------------------------------------------
  #
  # Anchors are the contract with home/claude-code/hooks.nix: each is one line
  # of a hook body, written there verbatim. A canary swaps its anchor(s) back
  # to the fail-open form the hook had before; D0 fails at eval if an anchor
  # is gone, so a rewrite of the hook can never leave a canary with nothing to
  # mutate and a green check.
  anchors = {
    A1 = {
      hook = "protect-main.js";
      text = "try { data = JSON.parse(input); } catch { denyOnBranch(\"the hook input was not valid JSON\"); return; }";
    };
    A2 = {
      hook = "protect-main.js";
      text = "if (probeBroken) denyUnverifiable(probeBroken);";
    };
    A3 = {
      hook = "block-main-bash.js";
      text = "try { data = JSON.parse(input); } catch { decideBlind([process.cwd()], \"the hook input was not valid JSON\"); return; }";
    };
    A4 = {
      hook = "block-main-bash.js";
      text = "if (st.kind === \"broken\") denyUnverifiable(st.why);";
    };
    A6 = {
      hook = "block-main-bash.js";
      text = "if (c.kind === \"broken\") denyUnverifiable(c.why + \" in the directory the command targets\");";
    };
    A7-budget = {
      hook = "protect-main.js";
      text = "const BUDGET_MS = 3000;";
    };
    A7-git = {
      hook = "protect-main.js";
      text = "const GIT_MS = 1500;";
    };
    A8 = {
      hook = "block-main-bash.js";
      text = "/(?:^|[\\n;|&(])[ \\t]*(?:sh|";
    };
    A9 = {
      hook = "block-main-bash.js";
      text = "oneOf(/commit|push|merge|rebase|update-ref|pull/)";
    };
    A10 = {
      hook = "block-main-bash.js";
      text = "for (const x of t.found) {";
    };
    A11 = {
      hook = "protect-main.js";
      text = "const f = branchOf(home);";
    };
    A12 = {
      hook = "protect-main.js";
      text = "ti.file_path || ti.notebook_path";
    };
    A-pm-apex-prefix = {
      hook = "protect-main.js";
      text = "if (!realTarget.startsWith(realTop + path.sep + APEX_OUT)) return false;";
    };
    A-pm-apex-ignore = {
      hook = "protect-main.js";
      text = "return gitBroken(ig) === null && ig.status === 0;";
    };
    A-pm-apex-nlink = {
      hook = "protect-main.js";
      text = "if (fs.lstatSync(realTarget).nlink > 1) return false;";
    };
    A-pm-apex-cwd = {
      hook = "protect-main.js";
      text = "if (!isApexOutput(realTop, realTarget)) deny(";
    };
    A-pm-apex-file = {
      hook = "protect-main.js";
      text = "&& !isApexOutput(home, realTarget)";
    };
    A-pm-apex-fsmonitor = {
      hook = "protect-main.js";
      text = "git([\"-c\", \"core.fsmonitor=false\", \"check-ignore\", \"-q\", \"--\", realTarget], realTop)";
    };
    A-pm-apex-sep = {
      hook = "protect-main.js";
      text = "const APEX_OUT = path.join(\".claude\", \"output\", \"apex\") + path.sep;";
    };
    A13 = {
      hook = "block-main-bash.js";
      text = "function isVaultTop(dir) {";
    };
    A14 = {
      hook = "block-main-bash.js";
      text = "-[Cc]\\s+(?!--?[A-Za-z][\\w-]*(?:=\\S+)?\\s)";
    };
    A5-require = {
      hook = "format-typescript.js";
      text = "const { spawnSync } = require(\"child_process\");";
    };
    A5-find = {
      hook = "format-typescript.js";
      text = "const found = spawnSync(\"prettier\", [\"--find-config-path\", file], { stdio: \"ignore\", timeout: 8000, killSignal: \"SIGKILL\" });";
    };
    A5-gate = {
      hook = "format-typescript.js";
      text = "if (found.status === 0) {";
    };
    A5-call = {
      hook = "format-typescript.js";
      text = "spawnSync(\"prettier\", [\"--write\", file], { stdio: \"ignore\", timeout: 8000, killSignal: \"SIGKILL\" });";
    };
    A-cb-cap = {
      hook = "correction-budget.js";
      text = "const MAX_ROUNDS = 2;";
    };
    A-cb-marker = {
      hook = "correction-budget.js";
      text = "if (!marker && MENTIONS.test(prompt)) { denyNoMarker(); return; }";
    };
    A-cb-tools = {
      hook = "correction-budget.js";
      text = "if (data.tool_name !== \"Agent\" && data.tool_name !== \"Task\" && data.tool_name !== \"SendMessage\") { allow(); return; }";
    };
    A-cb-grants = {
      hook = "correction-budget.js";
      text = "const cap = MAX_ROUNDS + grantsOf(dir, marker);";
    };
    A-cb-opus = {
      hook = "correction-budget.js";
      text = "if (data.tool_name !== \"SendMessage\" && ti.model !== \"opus\") {";
    };
    A-cb-abs = {
      hook = "correction-budget.js";
      text = "if (path.isAbsolute(marker) && path.dirname(marker).endsWith(path.sep + APEX_OUT) && path.join(path.dirname(marker), path.basename(marker)) === marker) {";
    };
    A-cg-stamped = {
      hook = "correction-grant.js";
      text = "where = stampedDir(dir, id, r.rounds, data.session_id);";
    };
    A-cg-session = {
      hook = "correction-grant.js";
      text = "if (s.session !== safe(session)) continue;";
    };
    A-cg-abs = {
      hook = "correction-grant.js";
      text = "if (!path.dirname(found).endsWith(path.sep + APEX_OUT) || path.join(path.dirname(found), id) !== found) return null;";
    };
    A-cg-token = {
      hook = "correction-grant.js";
      text = "const TOKEN = /^\\s*apex\\s*:\\s*\\+1\\s+tour\\s*$/i;";
    };
    A-cg-exhausted = {
      hook = "correction-grant.js";
      text = "if (target === null || tie || target.rounds < MAX_ROUNDS + target.grants) {";
    };
    A-cg-first = {
      hook = "correction-grant.js";
      text = "if (!TOKEN.test(firstLine(data.prompt))) { quiet(); return; }";
    };
    A-cg-wrappers = {
      hook = "correction-grant.js";
      text = "const WRAPPERS = [\"<task-notification\", \"<agent-message\", \"Another Claude session sent a message\", \"[SYSTEM NOTIFICATION\", \"<teammate-message\", \"<command-name>\", \"<local-command\", \"<scheduled-task\", \"<system-reminder\"];";
    };
    A-iw-url = {
      hook = "instagram-watch.js";
      text = "const IG_URL = /(?:^|[^A-Za-z0-9.@-])((?:https?:\\/\\/)?(?:(?:www|m)\\.)?instagram\\.com\\/(?:[A-Za-z0-9._]{1,30}\\/)?(?:p|reels?|tv)\\/[A-Za-z0-9_-]+)/gi;";
    };
    A-iw-agent = {
      hook = "instagram-watch.js";
      text = "if (Object.prototype.hasOwnProperty.call(data, \"agent_id\") && data.agent_id !== undefined) { quiet(); return; }";
    };
    A-iw-wrappers = {
      hook = "instagram-watch.js";
      text = "if (WRAPPERS.some((w) => data.prompt.includes(w))) { quiet(); return; }";
    };
    A-iw-json = {
      hook = "instagram-watch.js";
      text = "try { data = JSON.parse(input); } catch { quiet(); return; }";
    };
    A-ac-flag = {
      hook = "apex-metrics-probe.py";
      text = "flagged = [b for b in parse_ac_blocks(_read(pathlib.Path(path))) if classify(b) == \"unproven\"]";
    };
    A-ac-symlink = {
      hook = "apex-metrics-probe.py";
      text = "if p.is_symlink() or not p.is_file():";
    };
    A-ac-cap = {
      hook = "apex-metrics-probe.py";
      text = "HOOK_CAP = 10";
    };
    A-ac-lecture-re = {
      hook = "apex-metrics-probe.py";
      text = "LECTURE = re.compile(r\"\\[lecture\\]\\s*[—–:-]\\s*\\S\")";
    };
    A-ac-lecture = {
      hook = "apex-metrics-probe.py";
      text = "if LECTURE.search(text):";
    };
    A-ac-deferred = {
      hook = "apex-metrics-probe.py";
      text = "if DEFERRED.search(text):";
    };
    A-ac-docs = {
      hook = "apex-metrics-probe.py";
      text = "if AC_DOCS.match(block.prose[0]):";
    };
    A-ac-path = {
      hook = "apex-metrics-probe.py";
      text = "ACS_PATH = re.compile(r\"/\\.claude/output/apex/[^/]+/02-acs\\.md$\")";
    };
    A-ac-failopen = {
      hook = "apex-metrics-probe.py";
      text = "except Exception:";
    };
    A-ac-gate = {
      hook = "apex-metrics-probe.py";
      text = "or GATE.search(joined) is not None";
    };
    A-ac-tally = {
      hook = "apex-metrics-probe.py";
      text = "TALLY = re.compile(r\"\\bconfirmed=(\\d+)\")";
    };
    A-mem-path = {
      hook = "apex-metrics-probe.py";
      text = "MEMORY_PATH = re.compile(r\"/\\.claude/projects/[^/]+/memory/[^/]+\\.md$\")";
    };
    A-mem-slugs = {
      hook = "apex-metrics-probe.py";
      text = "for link in sorted(note_links(text) - names):";
    };
    A-mem-index = {
      hook = "apex-metrics-probe.py";
      text = "if idx is not None and p.name not in index_links(idx):";
    };
    A-mem-dead = {
      hook = "apex-metrics-probe.py";
      text = "dead = sorted(index_links(text) - files)";
    };
    A-mem-symlink = {
      hook = "apex-metrics-probe.py";
      text = "if p.is_symlink():";
    };
    A-mem-fold = {
      hook = "apex-metrics-probe.py";
      text = "by_stem.setdefault(stem.replace(\"_\", \"-\"), slug)";
    };
    A-pr-cmd = {
      hook = "apex-metrics-probe.py";
      text = "GH_PR_CREATE = re.compile(r\"^\\s*gh\\s+pr\\s+create(\\s|$)\")";
    };
    A-pr-branch = {
      hook = "apex-metrics-probe.py";
      text = "if ctx is None or run_branch(ctx) != branch:";
    };
    A-pr-done = {
      hook = "apex-metrics-probe.py";
      text = "if any((r / n).exists() or (r / n).is_symlink() for n in (\"pr.md\", \"commit.txt\")):";
    };
    A-pr-direct = {
      hook = "apex-metrics-probe.py";
      text = "NON_DIRECT = frozenset({\"Standard\", \"High-stakes\", \"Diagnosis\"})";
    };
    A-pr-xflag = {
      hook = "apex-metrics-probe.py";
      text = "X_FLAG = re.compile(r\"(?<![\\w-])[-+]x(?![\\w-])\")";
    };
    A-pr-head = {
      hook = "apex-metrics-probe.py";
      text = "head = head_flag(argv)";
    };
    A-pr-shlex = {
      hook = "apex-metrics-probe.py";
      text = "argv = shlex.split(cmd)";
    };
    A-pr-ext = {
      hook = "apex-metrics-probe.py";
      text = "for step in (\"x\", \"e\"):";
    };
    A-pr-newest = {
      hook = "apex-metrics-probe.py";
      text = "return max(found)[2] if found else None";
    };
    A-pr-failed = {
      hook = "apex-metrics-probe.py";
      text = "if _tool_failed(data.get(\"tool_response\")):";
    };
    A-b6-tier = {
      hook = "apex-metrics-probe.py";
      text = "return found[-1] if found else None";
    };
    A-cb-cron = {
      hook = "correction-budget.js";
      text = "if (typeof sp === \"string\" && sp.split(/\\r?\\n/).some((l) => TOKEN.test(l))) {";
    };
    A-rm-haiku = {
      hook = "research-model.js";
      text = "if (ti.model === \"haiku\") { allow(); return; }";
    };
    A-rm-types = {
      hook = "research-model.js";
      text = "const RESEARCH = [\"Explore\", \"codebase-navigator\"];";
    };
    A-rm-overflow = {
      hook = "research-model.js";
      text = "if (input.length + c.length > MAX_INPUT) { overflow = true; input = \"\"; return; }";
    };
    A-le-chain = {
      hook = "lone-excluded-bash.js";
      text = "if (!segs.every(isCleanTarget)) return CAUSE.shape;";
    };
    A-le-redir = {
      hook = "lone-excluded-bash.js";
      text = "if (!dup) r.fileRedir = true;";
    };
    A-le-subst = {
      hook = "lone-excluded-bash.js";
      text = "if (r.subst) return CAUSE.subst;";
    };
    A-le-quote = {
      hook = "lone-excluded-bash.js";
      text = "if (ch === '\"') {";
    };
    A-le-failopen = {
      hook = "lone-excluded-bash.js";
      text = "try { data = JSON.parse(input); } catch { allow(); return; }";
    };
    A-le-dup = {
      hook = "lone-excluded-bash.js";
      text = "const dup = (op === \">&\" || op === \"<&\") && /^(?:[0-9]+-?|-)$/.test(w.val);";
    };
    A-le-dispatch-target = {
      hook = "lone-excluded-bash.js";
      text = "if (cmd === \"claude-dispatch\") return [cmd];";
    };
    A-le-dispatch-prefilter = {
      hook = "lone-excluded-bash.js";
      text = "const PREFILTER = /\\bg(?:it|h)\\b|\\bclaude-dispatch\\b|\\bpnpm\\b/;";
    };
    A-le-dispatch-clean = {
      hook = "lone-excluded-bash.js";
      text = "if (w0.val === \"gh\" || w0.val === \"claude-dispatch\") return true;";
    };
    A-le-pnpm-prefilter = {
      hook = "lone-excluded-bash.js";
      text = "const PREFILTER = /\\bg(?:it|h)\\b|\\bclaude-dispatch\\b|\\bpnpm\\b/;";
    };
    A-le-pnpm-target = {
      hook = "lone-excluded-bash.js";
      text = "if (cmd === \"pnpm\") {";
    };
    A-le-pnpm-clean = {
      hook = "lone-excluded-bash.js";
      text = "if (w0.val === \"pnpm\") return words.length === 2 && w1.plain && PNPM_SCRIPTS.includes(w1.val);";
    };
    A-le-run-scripts = {
      hook = "lone-excluded-bash.js";
      text = "const RUN_SCRIPTS = [\"deploy\", \"deploy:prod\"];";
    };
    A-se-failopen = {
      hook = "sandbox-escape-evidence.js";
      text = "try { data = JSON.parse(input); } catch { allow(); return; }";
    };
    A-se-evidence = {
      hook = "sandbox-escape-evidence.js";
      text = "if (texts.some((t) => EVIDENCE.test(t))) { allow(); return; }";
    };
    A-se-batch = {
      hook = "sandbox-escape-evidence.js";
      text = "const texts = results.filter((r) => r.mid === newest.mid).map((r) => r.text);";
    };
    A-se-scope = {
      hook = "sandbox-escape-evidence.js";
      text = "if (msg.isMeta === true) continue;";
    };
    A-se-bashonly = {
      hook = "sandbox-escape-evidence.js";
      text = "if (!u || u.name !== \"Bash\" || b.tool_use_id === current) continue;";
    };
    A-se-segments = {
      hook = "sandbox-escape-evidence.js";
      text = "return segments(cmd).some((s) => ALLOW.some((re) => re.test(s.trim())));";
    };
    A-se-ask = {
      hook = "sandbox-escape-evidence.js";
      text = "const USER_ASK = /(sans|hors|without|bypass|outside|disable)\\W+(?:the\\s+|le\\s+|du\\s+)?sandbox/i;";
    };
    A-se-noproxy = {
      hook = "sandbox-escape-evidence.js";
      text = "/^curl\\b(?=.*\\s--noproxy(?:[\\s=]|$))/,";
    };
    A-se-wrangler = {
      hook = "sandbox-escape-evidence.js";
      text = "/^(?:pnpm\\s+(?:exec\\s+|dlx\\s+)?|npx\\s+)?wrangler\\b/,";
    };
    A-se-deploy = {
      hook = "sandbox-escape-evidence.js";
      text = "/^pnpm\\s+run\\s+deploy(?::[\\w-]+)?(?=\\s|$)/,";
    };
    A-se-mkdir = {
      hook = "sandbox-escape-evidence.js";
      text = "const EVIDENCE = /Operation not permitted|\\bEPERM\\b|\\bEACCES\\b|Read-only file system|sandbox_violations|Unable to create .*\\.lock|Permission denied|cannot connect to socket|unable to open database file|readonly database|Couldn't load public key|unable to create directory|getaddrinfo ENOTFOUND/i;";
    };
    A-wes-symlink = {
      hook = "worktree-env-sync.sh";
      text = "if [ -L \"$src\" ] || [ ! -f \"$src\" ]; then continue; fi";
    };
    A-wes-present = {
      hook = "worktree-env-sync.sh";
      text = "if [ -e \"$dst\" ] || [ -L \"$dst\" ]; then continue; fi";
    };
    A-wes-ign-main = {
      hook = "worktree-env-sync.sh";
      text = "\"$GIT\" -c core.fsmonitor=false -C \"$MAIN\" check-ignore -q -- \"$name\" 2>/dev/null || continue";
    };
    A-wes-ign-wt = {
      hook = "worktree-env-sync.sh";
      text = "\"$GIT\" -c core.fsmonitor=false -C \"$WT\" check-ignore -q -- \"$name\" 2>/dev/null || continue";
    };
    A-ss-gate = {
      hook = "session-state.js";
      text = "if (!NAME_RE.test(name)) return;";
    };
    A-ss-headless = {
      hook = "session-state.js";
      text = "if (process.env.CLAUDE_CODE_SESSION_ATTENDED === \"0\") return;";
    };
    A-wes-link = {
      hook = "worktree-env-sync.sh";
      text = "if cp -p \"$src\" \"$tmp\" 2>/dev/null && ln -n \"$tmp\" \"$dst\" 2>/dev/null; then LIST=\"$LIST, $name\"; fi";
    };
    A-apr-cmd = {
      hook = "apex-pr-record.js";
      text = "if (!w || w[0] !== \"gh\" || w[1] !== \"pr\" || w[2] !== \"merge\") return;";
    };
    A-apr-failed = {
      hook = "apex-pr-record.js";
      text = "if (toolFailed(data.tool_response)) return;";
    };
    A-apr-state = {
      hook = "apex-pr-record.js";
      text = "if (!pr || pr.state !== \"MERGED\") return;";
    };
    A-apr-valueflags = {
      hook = "apex-pr-record.js";
      text = "if (VALUE_FLAGS.has(a)) {";
    };
    A-apr-branchline = {
      hook = "apex-pr-record.js";
      text = "let hits = runs.filter(r => r.lines.some(l => branchLine(l, head)));";
    };
    A-apr-prefix = {
      hook = "apex-pr-record.js";
      text = "return rest.startsWith(head) && /^(\\s|$)/.test(rest.slice(head.length));";
    };
    A-apr-branchless = {
      hook = "apex-pr-record.js";
      text = "const unbranched = runs.filter(r => !r.lines.some(l => l.startsWith(\"Branch:\")));";
    };
    A-apr-fallback = {
      hook = "apex-pr-record.js";
      text = "if (hits.length === 0) hits = unbranched";
    };
    A-apr-dirname = {
      hook = "apex-pr-record.js";
      text = "path.basename(r.dir) === leaf ||";
    };
    A-apr-header = {
      hook = "apex-pr-record.js";
      text = "const HEADER_LINES = 12;";
    };
    A-apr-token = {
      hook = "apex-pr-record.js";
      text = "if (endsToken(after)) return true;";
    };
    A-apr-multi = {
      hook = "apex-pr-record.js";
      text = "for (const r of hits) {";
    };
    A-apr-commit = {
      hook = "apex-pr-record.js";
      text = "if (present(path.join(r.dir, \"commit.txt\"))) continue;";
    };
    A-apr-wx = {
      hook = "apex-pr-record.js";
      text = "fs.writeFileSync(path.join(r.dir, \"pr.md\"), body, { flag: \"wx\" });";
    };
    A-wh-failopen = {
      hook = "worktree-in-use.js";
      text = "try { data = JSON.parse(input); } catch { allow(); return; }";
    };
    A-wh-blind = {
      hook = "worktree-in-use.js";
      text = "if (ls.broken) denyBlind(ls.why);";
    };
    A-wh-holder = {
      hook = "worktree-in-use.js";
      text = "const t = targets.find((x) => holds(x, p.cwd));";
    };
    A-wh-self = {
      hook = "worktree-in-use.js";
      text = "const isSelf = (p) => p.pid === process.pid || p.pid === child || p.ppid === process.pid || (p.pid === process.ppid && SHELLS.includes(base(p.cmd).replace(/^-/, \"\")));";
    };
    A-wh-checkout = {
      hook = "worktree-in-use.js";
      text = "if (hasGit(d)) return true;";
    };
    A-wh-prefix = {
      hook = "worktree-in-use.js";
      text = "return c === r || c.startsWith(r + \"/\");";
    };
    A-wh-realpath = {
      hook = "worktree-in-use.js";
      text = "const real = fs.realpathSync.native(p);";
    };
    A-wh-suffix = {
      hook = "worktree-in-use.js";
      text = "if (p.endsWith(want)) {";
    };
    A-wh-cd = {
      hook = "worktree-in-use.js";
      text = "return place(a, cur);";
    };
    A-wh-C = {
      hook = "worktree-in-use.js";
      text = "dir = place(a, dir);";
    };
    A-wh-glob = {
      hook = "worktree-in-use.js";
      text = "if (!hasGlob(w)) {";
    };
    A-wh-brace = {
      hook = "worktree-in-use.js";
      text = "if (!x.brace[i] || x.val[i] !== \"{\") continue;";
    };
    A-wh-remove-glob = {
      hook = "worktree-in-use.js";
      text = "if (hasGlob(b)) { for (const g of globWords(b, cur)) resolveWt(g, dir, out); continue; }";
    };
    A-wh-suffix-first = {
      hook = "worktree-in-use.js";
      text = "if (real !== null) out.push({ path: real, kind: \"remove\" });";
    };
    A-wh-env-C = {
      hook = "worktree-in-use.js";
      text = "if (chdir.includes(o)) { here = words[k + 1] === undefined ? null : place(words[k + 1], here); k += 2; continue; }";
    };
    A-wh-pwd = {
      hook = "worktree-in-use.js";
      text = "const words = raw.map((w) => (w.pwd ? atPwd(w, cur) : w));";
    };
    A-wh-noself = {
      hook = "worktree-in-use.js";
      text = "if (!procs.some((x) => x.pid === process.pid)) return";
    };
    A-wh-badexit = {
      hook = "worktree-in-use.js";
      text = "if (r.status !== 0 && r.status !== 1) return";
    };
  };

  # The M5 mutants name their shell: execSync's default /bin/sh dispatches
  # through /private/var/select/sh on macOS, which the build sandbox may not
  # expose — a mutant that cannot start a shell would survive for the wrong
  # reason. The injection is a property of ANY shell; bash is pinned. Each
  # puts ONE of the two prettier calls through a shell, the other stays argv.
  mutants = [
    {
      id = "M1";
      hook = "protect-main.js";
      kills = "pm-master-malformed";
      swaps = [
        {
          anchor = "A1";
          to = "try { data = JSON.parse(input); } catch { process.exit(0); }";
        }
      ];
    }
    {
      id = "M2";
      hook = "protect-main.js";
      kills = "pm-master-nogit";
      swaps = [
        {
          anchor = "A2";
          to = "if (probeBroken) process.exit(0);";
        }
      ];
    }
    {
      id = "M3";
      hook = "block-main-bash.js";
      kills = "bb-master-malformed";
      swaps = [
        {
          anchor = "A3";
          to = "try { data = JSON.parse(input); } catch { process.exit(0); }";
        }
      ];
    }
    {
      id = "M4";
      hook = "block-main-bash.js";
      kills = "bb-master-nogit";
      swaps = [
        {
          anchor = "A4";
          to = "if (st.kind === \"broken\") process.exit(0);";
        }
      ];
    }
    {
      id = "M5";
      hook = "format-typescript.js";
      kills = "fmt-inject";
      swaps = [
        {
          anchor = "A5-require";
          to = "const { spawnSync, execSync } = require(\"child_process\");";
        }
        {
          anchor = "A5-call";
          to = "execSync(\"prettier --write \" + JSON.stringify(file), { stdio: \"ignore\", timeout: 8000, shell: \"${pkgs.bash}/bin/bash\" });";
        }
      ];
    }
    {
      id = "M5-find";
      hook = "format-typescript.js";
      kills = "fmt-inject";
      swaps = [
        {
          anchor = "A5-require";
          to = "const { spawnSync, execSync } = require(\"child_process\");";
        }
        {
          anchor = "A5-find";
          to = "const found = { status: (execSync(\"prettier --find-config-path \" + JSON.stringify(file), { stdio: \"ignore\", timeout: 8000, shell: \"${pkgs.bash}/bin/bash\" }), 0) };";
        }
      ];
    }
    # Run 64. No config gate: every file is written, prettier config or not —
    # this nix repo reformatted on every Edit.
    {
      id = "M5-gate";
      hook = "format-typescript.js";
      kills = "fmt-no-config";
      swaps = [
        {
          anchor = "A5-gate";
          to = "if (true) {";
        }
      ];
    }
    {
      id = "M6";
      hook = "block-main-bash.js";
      kills = "bb-cd-broken";
      swaps = [
        {
          anchor = "A6";
          to = "if (c.kind === \"broken\") {}";
        }
      ];
    }
    # A budget past the host's timeout: the hung git is still being waited on
    # when the host gives up, and the host then proceeds. Killed only because
    # `run` grants each body its registered timeout and no more.
    {
      id = "M7";
      hook = "protect-main.js";
      kills = "pm-master-hung";
      swaps = [
        {
          anchor = "A7-budget";
          to = "const BUDGET_MS = 9000;";
        }
        {
          anchor = "A7-git";
          to = "const GIT_MS = 9000;";
        }
      ];
    }
    # The quadratic executor scan: `\s*` after a separator rescans a newline
    # run from each of its newlines, so the flood outlives the host timeout.
    {
      id = "M8";
      hook = "block-main-bash.js";
      kills = "bb-master-nl-flood";
      swaps = [
        {
          anchor = "A8";
          to = "/(?:^|[\\n;|&(])\\s*(?:sh|";
        }
      ];
    }
    # Run 61. `pull` merges into the current branch: without it a pull on
    # master is not a ref move and passes.
    {
      id = "M9";
      hook = "block-main-bash.js";
      kills = "bb-pull-master";
      swaps = [
        {
          anchor = "A9";
          to = "oneOf(/commit|push|merge|rebase|update-ref/)";
        }
      ];
    }
    # Only the first target read, as the old viaC/viaCd did: a second `cd`
    # to master goes unchecked.
    {
      id = "M10";
      hook = "block-main-bash.js";
      kills = "bb-second-cd";
      swaps = [
        {
          anchor = "A10";
          to = "for (const x of t.found.slice(0, 1)) {";
        }
      ];
    }
    # The repo the FILE belongs to is never read: only the cwd decides, so a
    # feature-branch cwd writes into master.
    {
      id = "M11";
      hook = "protect-main.js";
      kills = "pm-cross-feat-cwd";
      swaps = [
        {
          anchor = "A11";
          to = "const f = { kind: \"norepo\" };";
        }
      ];
    }
    # notebook_path unread: every NotebookEdit has "no file_path" and is
    # denied, even outside any repo. Killed on the ALLOW partner, as an
    # over-block: on master the no-path deny still denies, for another reason.
    {
      id = "M12";
      hook = "protect-main.js";
      kills = "pm-notebook-outside";
      swaps = [
        {
          anchor = "A12";
          to = "ti.file_path";
        }
      ];
    }
    # No vault exemption: a commit in the vault on main is denied. Killed on
    # an ALLOW case, as an over-block.
    {
      id = "M13";
      hook = "block-main-bash.js";
      kills = "bb-vault-commit";
      swaps = [
        {
          anchor = "A13";
          to = "function isVaultTop(dir) { return false;";
        }
      ];
    }
    # The apex-output run. No prefix test: every ignored file of a repo on
    # master is writable, `.claude/settings.local.json` included.
    {
      id = "M-pm-apex-prefix";
      hook = "protect-main.js";
      kills = "pm-apex-ignored-outside";
      swaps = [
        {
          anchor = "A-pm-apex-prefix";
          to = "if (false) return false;";
        }
      ];
    }
    # Any check-ignore answer counts: a force-added TRACKED file there passes.
    {
      id = "M-pm-apex-ignore";
      hook = "protect-main.js";
      kills = "pm-apex-tracked";
      swaps = [
        {
          anchor = "A-pm-apex-ignore";
          to = "return gitBroken(ig) === null;";
        }
      ];
    }
    # No link count: a hardlink of a tracked file writes through to it.
    {
      id = "M-pm-apex-nlink";
      hook = "protect-main.js";
      kills = "pm-apex-hardlink";
      swaps = [
        {
          anchor = "A-pm-apex-nlink";
          to = "if (false) return false;";
        }
      ];
    }
    # The cwd site keeps its deny: run state is refused from its own repo.
    # Killed on an ALLOW case, as an over-block.
    {
      id = "M-pm-apex-cwd";
      hook = "protect-main.js";
      kills = "pm-apex-new";
      swaps = [
        {
          anchor = "A-pm-apex-cwd";
          to = "if (true) deny(";
        }
      ];
    }
    # The cwd site allows instead of falling through: a nested repo on
    # master under the ignored dir is never asked.
    {
      id = "M-pm-apex-fallthrough";
      hook = "protect-main.js";
      kills = "pm-apex-nested";
      swaps = [
        {
          anchor = "A-pm-apex-cwd";
          to = "if (isApexOutput(realTop, realTarget)) allow(); deny(";
        }
      ];
    }
    # The file site keeps its deny: run state is refused from another cwd.
    # Killed on an ALLOW case, as an over-block.
    {
      id = "M-pm-apex-file";
      hook = "protect-main.js";
      kills = "pm-apex-crosscwd";
      swaps = [
        {
          anchor = "A-pm-apex-file";
          to = "";
        }
      ];
    }
    # The fsmonitor override dropped from check-ignore: the target repo's
    # core.fsmonitor command runs, outside the sandbox.
    {
      id = "M-pm-apex-fsmonitor";
      hook = "protect-main.js";
      kills = "pm-apex-fsmonitor-pwned";
      swaps = [
        {
          anchor = "A-pm-apex-fsmonitor";
          to = "git([\"check-ignore\", \"-q\", \"--\", realTarget], realTop)";
        }
      ];
    }
    # No separator after `apex`: a sibling `apexfoo/` reads as run state.
    {
      id = "M-pm-apex-sep";
      hook = "protect-main.js";
      kills = "pm-apex-sibling";
      swaps = [
        {
          anchor = "A-pm-apex-sep";
          to = "const APEX_OUT = path.join(\".claude\", \"output\", \"apex\");";
        }
      ];
    }
    # Run 65. The `git` prefix without its option-shaped-value guard: each
    # `-C` reads as a value or as an option, a failing rule backtracks
    # through Fibonacci-many splits, and 1000 of them outlive the host timeout.
    {
      id = "M14";
      hook = "block-main-bash.js";
      kills = "bb-master-C-flood";
      swaps = [
        {
          anchor = "A14";
          to = "-[Cc]\\s+";
        }
      ];
    }
    # Run 62. A third round allowed: the cap is one round looser than stated.
    {
      id = "M-cb-cap";
      hook = "correction-budget.js";
      kills = "cb-round3-deny";
      swaps = [
        {
          anchor = "A-cb-cap";
          to = "const MAX_ROUNDS = 3;";
        }
      ];
    }
    # No marker required: a correction brief that omits the line is never
    # counted, and the cap is bypassed by leaving it out.
    {
      id = "M-cb-marker";
      hook = "correction-budget.js";
      kills = "cb-nomarker-deny";
      swaps = [
        {
          anchor = "A-cb-marker";
          to = ";";
        }
      ];
    }
    # Agent-only: a correction re-brief sent by SendMessage to a live agent
    # is never counted, and the cap is bypassed by re-briefing.
    {
      id = "M-cb-sendmessage";
      hook = "correction-budget.js";
      kills = "cb-sendmessage-round3-deny";
      swaps = [
        {
          anchor = "A-cb-tools";
          to = "if (data.tool_name !== \"Agent\") { allow(); return; }";
        }
      ];
    }
    # Grants ignored: the round the user granted is denied all the same.
    {
      id = "M-cb-grants";
      hook = "correction-budget.js";
      kills = "cb-grant-round3-allow";
      swaps = [
        {
          anchor = "A-cb-grants";
          to = "const cap = MAX_ROUNDS;";
        }
      ];
    }
    # Any model: a correction round goes out on sonnet and is counted.
    {
      id = "M-cb-opus";
      hook = "correction-budget.js";
      kills = "cb-sonnet-deny";
      swaps = [
        {
          anchor = "A-cb-opus";
          to = "if (false) {";
        }
      ];
    }
    # The token anywhere in a line: a deny text read back grants a round.
    {
      id = "M-cg-whole-line";
      hook = "correction-grant.js";
      kills = "cg-inline-token-ignored";
      swaps = [
        {
          anchor = "A-cg-token";
          to = "const TOKEN = /apex\\s*:\\s*\\+1\\s+tour/i;";
        }
      ];
    }
    # No spent-budget test: a run with rounds left, or an unused grant, is
    # granted again.
    {
      id = "M-cg-exhausted";
      hook = "correction-grant.js";
      kills = "cg-not-exhausted";
      swaps = [
        {
          anchor = "A-cg-exhausted";
          to = "if (target === null || tie) {";
        }
      ];
    }
    # The token on any line: a model-written text quoting it below its first
    # line grants a round.
    {
      id = "M-cg-first-line";
      hook = "correction-grant.js";
      kills = "cg-token-not-first-ignored";
      swaps = [
        {
          anchor = "A-cg-first";
          to = "if (!data.prompt.split(/\\r?\\n/).some((l) => TOKEN.test(l))) { quiet(); return; }";
        }
      ];
    }
    # No wrapper filter: an agent hand-back that opens on the token grants.
    {
      id = "M-cg-wrappers";
      hook = "correction-grant.js";
      kills = "cg-wrapped-ignored";
      swaps = [
        {
          anchor = "A-cg-wrappers";
          to = "const WRAPPERS = [];";
        }
      ];
    }
    # Any absolute dir: a marker naming a dir outside an apex output dir is
    # taken for a run, and a fresh budget is one mkdir away.
    {
      id = "M-cb-abs-parent";
      hook = "correction-budget.js";
      kills = "cb-abs-run-bad-deny";
      swaps = [
        {
          anchor = "A-cb-abs";
          to = "if (path.isAbsolute(marker) && path.join(path.dirname(marker), path.basename(marker)) === marker) {";
        }
      ];
    }
    # No normalization: `…/apex/64-z/` or `…//.claude/…` is taken for run
    # 64-z, the stamped dir no longer the one the grant hook rebuilds.
    {
      id = "M-cb-abs-norm";
      hook = "correction-budget.js";
      kills = "cb-abs-run-unnormalized-deny";
      swaps = [
        {
          anchor = "A-cb-abs";
          to = "if (path.isAbsolute(marker) && path.dirname(marker).endsWith(path.sep + APEX_OUT)) {";
        }
      ];
    }
    # Run-ids only: a correction round for a run outside the session's repo
    # is denied, the stub-dir workaround back.
    {
      id = "M-cb-abs-off";
      hook = "correction-budget.js";
      kills = "cb-abs-run-allow";
      swaps = [
        {
          anchor = "A-cb-abs";
          to = "if (false) {";
        }
      ];
    }
    # No stamped dir read: a spent run outside the prompt's repo is never
    # granted.
    {
      id = "M-cg-stamped-off";
      hook = "correction-grant.js";
      kills = "cg-cross-repo-grants";
      swaps = [
        {
          anchor = "A-cg-stamped";
          to = "where = null;";
        }
      ];
    }
    # Any session: another session's spent run outside the repo is granted.
    {
      id = "M-cg-session";
      hook = "correction-grant.js";
      kills = "cg-cross-repo-other-session";
      swaps = [
        {
          anchor = "A-cg-session";
          to = ";";
        }
      ];
    }
    # Any stamped dir: a run stamped outside an apex output dir is granted.
    {
      id = "M-cg-abs-parent";
      hook = "correction-grant.js";
      kills = "cg-cross-repo-bad-dir";
      swaps = [
        {
          anchor = "A-cg-abs";
          to = "if (path.join(path.dirname(found), id) !== found) return null;";
        }
      ];
    }
    # Any instagram.com path: a profile or explore page asks for the watch skill.
    {
      id = "M-iw-path";
      hook = "instagram-watch.js";
      kills = "iw-mention-silent";
      swaps = [
        {
          anchor = "A-iw-url";
          to = "const IG_URL = /(?:^|[^A-Za-z0-9.@-])((?:https?:\\/\\/)?(?:(?:www|m)\\.)?instagram\\.com\\/[A-Za-z0-9._-]*)/gi;";
        }
      ];
    }
    # No left boundary: notinstagram.com/reel/… is read as an Instagram link.
    {
      id = "M-iw-boundary";
      hook = "instagram-watch.js";
      kills = "iw-other-url-silent";
      swaps = [
        {
          anchor = "A-iw-url";
          to = "const IG_URL = /((?:https?:\\/\\/)?(?:(?:www|m)\\.)?instagram\\.com\\/(?:[A-Za-z0-9._]{1,30}\\/)?(?:p|reels?|tv)\\/[A-Za-z0-9_-]+)/gi;";
        }
      ];
    }
    # No wrapper filter: an agent hand-back quoting a reel asks for the skill.
    {
      id = "M-iw-wrappers";
      hook = "instagram-watch.js";
      kills = "iw-wrapped-silent";
      swaps = [
        {
          anchor = "A-iw-wrappers";
          to = ";";
        }
      ];
    }
    # No agent_id test: a subagent's prompt asks for the skill.
    {
      id = "M-iw-agent";
      hook = "instagram-watch.js";
      kills = "iw-subagent-silent";
      swaps = [
        {
          anchor = "A-iw-agent";
          to = ";";
        }
      ];
    }
    # Malformed input exits 2: the host blocks the user's prompt.
    {
      id = "M-iw-json";
      hook = "instagram-watch.js";
      kills = "iw-malformed-silent";
      swaps = [
        {
          anchor = "A-iw-json";
          to = "try { data = JSON.parse(input); } catch { process.exit(2); }";
        }
      ];
    }
    # Wrong filter: the ACs proven by a command are listed, the unproven not.
    {
      id = "M-ac-flag";
      hook = "apex-metrics-probe.py";
      kills = "ac-prose-emits";
      swaps = [
        {
          anchor = "A-ac-flag";
          to = "flagged = [b for b in parse_ac_blocks(_read(pathlib.Path(path))) if classify(b) == \"command\"]";
        }
      ];
    }
    # Symlink followed: another file's first line reaches the model context.
    {
      id = "M-ac-symlink";
      hook = "apex-metrics-probe.py";
      kills = "ac-symlink-silent";
      swaps = [
        {
          anchor = "A-ac-symlink";
          to = "if not p.is_file():";
        }
      ];
    }
    # Cap above the case's count: every unproven AC is listed, no "+N more".
    {
      id = "M-ac-cap";
      hook = "apex-metrics-probe.py";
      kills = "ac-cap-emits";
      swaps = [
        {
          anchor = "A-ac-cap";
          to = "HOOK_CAP = 100";
        }
      ];
    }
    # A bare `[lecture]` with no reason exempts its AC.
    {
      id = "M-ac-reason";
      hook = "apex-metrics-probe.py";
      kills = "ac-bare-lecture-emits";
      swaps = [
        {
          anchor = "A-ac-lecture-re";
          to = "LECTURE = re.compile(r\"\\[lecture\\]\")";
        }
      ];
    }
    # No lecture test: a `[lecture] — reason` AC is listed as unproven.
    {
      id = "M-ac-lecture";
      hook = "apex-metrics-probe.py";
      kills = "ac-lecture-silent";
      swaps = [
        {
          anchor = "A-ac-lecture";
          to = "if False:";
        }
      ];
    }
    # No deferred test: a `[deferred to user]` AC is listed as unproven.
    {
      id = "M-ac-deferred";
      hook = "apex-metrics-probe.py";
      kills = "ac-deferred-silent";
      swaps = [
        {
          anchor = "A-ac-deferred";
          to = "if False:";
        }
      ];
    }
    # No AC-docs test: the docs line is listed as unproven.
    {
      id = "M-ac-docs";
      hook = "apex-metrics-probe.py";
      kills = "ac-docs-silent";
      swaps = [
        {
          anchor = "A-ac-docs";
          to = "if False:";
        }
      ];
    }
    # Any .md of a run dir is read as its 02-acs.md.
    {
      id = "M-ac-name";
      hook = "apex-metrics-probe.py";
      kills = "ac-other-file-silent";
      swaps = [
        {
          anchor = "A-ac-path";
          to = "ACS_PATH = re.compile(r\"/\\.claude/output/apex/[^/]+/[^/]+\\.md$\")";
        }
      ];
    }
    # Any 02-acs.md, inside an APEX run dir or not.
    {
      id = "M-ac-dir";
      hook = "apex-metrics-probe.py";
      kills = "ac-outside-run-silent";
      swaps = [
        {
          anchor = "A-ac-path";
          to = "ACS_PATH = re.compile(r\"/02-acs\\.md$\")";
        }
      ];
    }
    # Fail-open narrowed to OSError: malformed input exits 1 with a traceback.
    {
      id = "M-ac-failopen";
      hook = "apex-metrics-probe.py";
      kills = "ac-malformed-silent";
      swaps = [
        {
          anchor = "A-ac-failopen";
          to = "except OSError:";
        }
      ];
    }
    # No gate rule in the B2 classifier: `--self-test` mislabels a gate AC.
    {
      id = "M-ac-gate";
      hook = "apex-metrics-probe.py";
      kills = "ac-self-test";
      swaps = [
        {
          anchor = "A-ac-gate";
          to = "or False";
        }
      ];
    }
    # Tally never detected: every 04-validate.md of a run that ran a pass is flagged.
    {
      id = "M-ac-tally";
      hook = "apex-metrics-probe.py";
      kills = "ac-validate-tally-silent";
      swaps = [
        {
          anchor = "A-ac-tally";
          to = "TALLY = re.compile(r\"(?!x)x(\\d+)\")";
        }
      ];
    }
    # Any .md is read as a memory note: a plain notes dir gets the memory line.
    {
      id = "M-mem-path";
      hook = "apex-metrics-probe.py";
      kills = "ac-mem-outside-silent";
      swaps = [
        {
          anchor = "A-mem-path";
          to = "MEMORY_PATH = re.compile(r\"\\.md$\")";
        }
      ];
    }
    # Slugs ignored: a link to a sibling's own slug is reported.
    {
      id = "M-mem-slugs";
      hook = "apex-metrics-probe.py";
      kills = "ac-mem-clean-silent";
      swaps = [
        {
          anchor = "A-mem-slugs";
          to = "for link in sorted(note_links(text)):";
        }
      ];
    }
    # Index never read: a note missing from MEMORY.md goes unnamed.
    {
      id = "M-mem-index";
      hook = "apex-metrics-probe.py";
      kills = "ac-mem-unindexed-emits";
      swaps = [
        {
          anchor = "A-mem-index";
          to = "if False:";
        }
      ];
    }
    # Dead index links never computed: MEMORY.md pointing at nothing is silent.
    {
      id = "M-mem-dead";
      hook = "apex-metrics-probe.py";
      kills = "ac-mem-index-dead-emits";
      swaps = [
        {
          anchor = "A-mem-dead";
          to = "dead = []";
        }
      ];
    }
    # Symlink followed: another file's links are reported as the note's.
    {
      id = "M-mem-symlink";
      hook = "apex-metrics-probe.py";
      kills = "ac-mem-symlink-silent";
      swaps = [
        {
          anchor = "A-mem-symlink";
          to = "if False:";
        }
      ];
    }
    # No `_` → `-` fold: a dashed link to an underscored stem is "no such note".
    {
      id = "M-mem-fold";
      hook = "apex-metrics-probe.py";
      kills = "ac-mem-dangling-emits";
      swaps = [
        {
          anchor = "A-mem-fold";
          to = "by_stem.setdefault(stem, slug)";
        }
      ];
    }
    # Any memory/ dir: a notes/memory/ dir outside .claude/projects/ is read.
    {
      id = "M-mem-path-proj";
      hook = "apex-metrics-probe.py";
      kills = "ac-mem-notes-memory-silent";
      swaps = [
        {
          anchor = "A-mem-path";
          to = "MEMORY_PATH = re.compile(r\"/memory/[^/]+\\.md$\")";
        }
      ];
    }
    # Any `gh pr` command reads as a PR creation: `gh pr view` gets the B6 line.
    {
      id = "M-pr-cmd";
      hook = "apex-metrics-probe.py";
      kills = "pr-other-command-silent";
      swaps = [
        {
          anchor = "A-pr-cmd";
          to = "GH_PR_CREATE = re.compile(r\"^\\s*gh\\s+pr\\s\")";
        }
      ];
    }
    # Branch ignored: another branch's newer unfinished run is named.
    {
      id = "M-pr-branch";
      hook = "apex-metrics-probe.py";
      kills = "pr-other-branch-silent";
      swaps = [
        {
          anchor = "A-pr-branch";
          to = "if ctx is None:";
        }
      ];
    }
    # A finished run (pr.md, commit.txt) is still told what it lacks.
    {
      id = "M-pr-done";
      hook = "apex-metrics-probe.py";
      kills = "pr-finished-run-silent";
      swaps = [
        {
          anchor = "A-pr-done";
          to = "if False:";
        }
      ];
    }
    # Direct owes the Standard files: a Direct run is told it lacks 02-acs.md.
    {
      id = "M-pr-direct";
      hook = "apex-metrics-probe.py";
      kills = "pr-direct-silent";
      swaps = [
        {
          anchor = "A-pr-direct";
          to = "NON_DIRECT = frozenset({\"Standard\", \"High-stakes\", \"Diagnosis\", \"Direct\"})";
        }
      ];
    }
    # `+x` never read: an escalated run with no 05-examine.md owes nothing.
    {
      id = "M-pr-xflag";
      hook = "apex-metrics-probe.py";
      kills = "pr-xflag-noexamine-emits";
      swaps = [
        {
          anchor = "A-pr-xflag";
          to = "X_FLAG = re.compile(r\"(?!x)x\")";
        }
      ];
    }
    # `--head` ignored: the cwd's branch, whose run is complete, is read.
    {
      id = "M-pr-head";
      hook = "apex-metrics-probe.py";
      kills = "pr-head-flag-emits";
      swaps = [
        {
          anchor = "A-pr-head";
          to = "head = None";
        }
      ];
    }
    # The raw command split on blanks: a `-H` inside a quoted title names the branch.
    {
      id = "M-pr-shlex";
      hook = "apex-metrics-probe.py";
      kills = "pr-head-in-title-emits";
      swaps = [
        {
          anchor = "A-pr-shlex";
          to = "argv = cmd.split()";
        }
      ];
    }
    # External tally never owed: a run whose verify passed and has no triage is silent.
    {
      id = "M-pr-ext";
      hook = "apex-metrics-probe.py";
      kills = "pr-external-untallied-emits";
      swaps = [
        {
          anchor = "A-pr-ext";
          to = "for step in (\"x\",):";
        }
      ];
    }
    # Oldest unfinished run read: the complete older run hides the newer one's gap.
    {
      id = "M-pr-newest";
      hook = "apex-metrics-probe.py";
      kills = "pr-newest-incomplete-emits";
      swaps = [
        {
          anchor = "A-pr-newest";
          to = "return min(found)[2] if found else None";
        }
      ];
    }
    # An interrupted `gh pr create` (no PR) still gets the B6 line.
    {
      id = "M-pr-failed";
      hook = "apex-metrics-probe.py";
      kills = "pr-failed-tool-silent";
      swaps = [
        {
          anchor = "A-pr-failed";
          to = "if False:";
        }
      ];
    }
    # First Tier: line wins: an escalated run keeps its provisional tier.
    {
      id = "M-b6-tier";
      hook = "apex-metrics-probe.py";
      kills = "ac-self-test";
      swaps = [
        {
          anchor = "A-b6-tier";
          to = "return found[0] if found else None";
        }
      ];
    }
    # Schedulers unchecked: the model schedules the user's grant line.
    {
      id = "M-cb-cron";
      hook = "correction-budget.js";
      kills = "cb-cron-token-deny";
      swaps = [
        {
          anchor = "A-cb-cron";
          to = "if (false) {";
        }
      ];
    }
    # Run 66. An absent model let through: the spawn falls back to whatever
    # the agent definition names, and the explicit-model rule is not held.
    {
      id = "M-rm-absent";
      hook = "research-model.js";
      kills = "rm-navigator-nomodel-deny";
      swaps = [
        {
          anchor = "A-rm-haiku";
          to = "if (ti.model === \"haiku\" || ti.model === undefined) { allow(); return; }";
        }
      ];
    }
    # Explore alone: a codebase-navigator spawn on opus goes through.
    {
      id = "M-rm-types";
      hook = "research-model.js";
      kills = "rm-navigator-opus-deny";
      swaps = [
        {
          anchor = "A-rm-types";
          to = "const RESEARCH = [\"Explore\"];";
        }
      ];
    }
    # The pre-#219 reader: past 4 MiB it drops the tail and keeps the
    # prefix, so a valid object padded past the cap is parsed and denied
    # although the whole input is malformed.
    {
      id = "M-rm-overflow";
      hook = "research-model.js";
      kills = "rm-oversize-allow";
      swaps = [
        {
          anchor = "A-rm-overflow";
          to = "if (input.length + c.length > MAX_INPUT) return;";
        }
      ];
    }
    # Sandbox-shape run. One clean segment enough: `git add . && git commit`
    # passes, and the whole chain stays sandboxed.
    {
      id = "M-le-chain";
      hook = "lone-excluded-bash.js";
      kills = "le-add-commit-deny";
      swaps = [
        {
          anchor = "A-le-chain";
          to = "if (!segs.some(isCleanTarget)) return CAUSE.shape;";
        }
      ];
    }
    # A file redirection unseen: `gh api x > out.json` passes.
    {
      id = "M-le-redir";
      hook = "lone-excluded-bash.js";
      kills = "le-redir-deny";
      swaps = [
        {
          anchor = "A-le-redir";
          to = "if (false) r.fileRedir = true;";
        }
      ];
    }
    # A substitution unseen: `git commit -m "$(cat m)"` passes.
    {
      id = "M-le-subst";
      hook = "lone-excluded-bash.js";
      kills = "le-subst-deny";
      swaps = [
        {
          anchor = "A-le-subst";
          to = "if (false) return CAUSE.subst;";
        }
      ];
    }
    # Double quotes ignored: the `;` inside a commit message splits it.
    # Killed on an ALLOW case, as an over-block.
    {
      id = "M-le-quote";
      hook = "lone-excluded-bash.js";
      kills = "le-quoted-msg-allow";
      swaps = [
        {
          anchor = "A-le-quote";
          to = "if (false) {";
        }
      ];
    }
    # Fail-closed on malformed input: a workflow hook blocking work.
    {
      id = "M-le-failopen";
      hook = "lone-excluded-bash.js";
      kills = "le-malformed-allow";
      swaps = [
        {
          anchor = "A-le-failopen";
          to = "try { data = JSON.parse(input); } catch { deny(\"BLOCKED: malformed input\"); return; }";
        }
      ];
    }
    # fd duplication read as a file redirection: `git fetch 2>&1` denied.
    {
      id = "M-le-dup";
      hook = "lone-excluded-bash.js";
      kills = "le-dup-allow";
      swaps = [
        {
          anchor = "A-le-dup";
          to = "const dup = false;";
        }
      ];
    }
    # claude-dispatch not a target: `cd /x && claude-dispatch …` passes.
    {
      id = "M-le-dispatch-target";
      hook = "lone-excluded-bash.js";
      kills = "le-dispatch-cd-deny";
      swaps = [
        {
          anchor = "A-le-dispatch-target";
          to = "if (false) return [cmd];";
        }
      ];
    }
    # The prefilter blind to claude-dispatch: a call with no git/gh word is
    # never lexed, `VAR=x claude-dispatch …` passes.
    {
      id = "M-le-dispatch-prefilter";
      hook = "lone-excluded-bash.js";
      kills = "le-dispatch-env-deny";
      swaps = [
        {
          anchor = "A-le-dispatch-prefilter";
          to = "const PREFILTER = /\\bg(?:it|h)\\b|\\bpnpm\\b/;";
        }
      ];
    }
    # A lone claude-dispatch not clean: the call it must let out is denied.
    # Killed on an ALLOW case, as an over-block.
    {
      id = "M-le-dispatch-clean";
      hook = "lone-excluded-bash.js";
      kills = "le-dispatch-allow";
      swaps = [
        {
          anchor = "A-le-dispatch-clean";
          to = "if (w0.val === \"gh\") return true;";
        }
      ];
    }
    # pnpm not a target: `cd /x && pnpm localdb:start` passes.
    {
      id = "M-le-pnpm-target";
      hook = "lone-excluded-bash.js";
      kills = "le-pnpm-cd-deny";
      swaps = [
        {
          anchor = "A-le-pnpm-target";
          to = "if (false) {";
        }
      ];
    }
    # The prefilter blind to pnpm: a call with no git/gh/claude-dispatch word
    # is never lexed, `pnpm localdb:start 2>&1 | tail -8` passes.
    {
      id = "M-le-pnpm-prefilter";
      hook = "lone-excluded-bash.js";
      kills = "le-pnpm-pipe-deny";
      swaps = [
        {
          anchor = "A-le-pnpm-prefilter";
          to = "const PREFILTER = /\\bg(?:it|h)\\b|\\bclaude-dispatch\\b/;";
        }
      ];
    }
    # A lone pnpm localdb:start not clean: the call it must let out is
    # denied. Killed on an ALLOW case, as an over-block.
    {
      id = "M-le-pnpm-clean";
      hook = "lone-excluded-bash.js";
      kills = "le-pnpm-start-allow";
      swaps = [
        {
          anchor = "A-le-pnpm-clean";
          to = "if (false) return false;";
        }
      ];
    }
    # The deploy run scripts not targets: `cd … && pnpm run deploy` passes.
    {
      id = "M-le-run-scripts";
      hook = "lone-excluded-bash.js";
      kills = "le-deploy-cd-deny";
      swaps = [
        {
          anchor = "A-le-run-scripts";
          to = "const RUN_SCRIPTS = [];";
        }
      ];
    }
    # Sandbox-escape run. Fail-closed on malformed input.
    {
      id = "M-se-failopen";
      hook = "sandbox-escape-evidence.js";
      kills = "se-malformed-allow";
      swaps = [
        {
          anchor = "A-se-failopen";
          to = "try { data = JSON.parse(input); } catch { deny(\"BLOCKED: malformed input\"); return; }";
        }
      ];
    }
    # Evidence never read: an EPERM retry denied.
    {
      id = "M-se-evidence";
      hook = "sandbox-escape-evidence.js";
      kills = "se-eperm-allow";
      swaps = [
        {
          anchor = "A-se-evidence";
          to = "if (false) { allow(); return; }";
        }
      ];
    }
    # The newest result alone: a parallel sibling's EPERM unseen.
    {
      id = "M-se-batch";
      hook = "sandbox-escape-evidence.js";
      kills = "se-batch-allow";
      swaps = [
        {
          anchor = "A-se-batch";
          to = "const texts = [newest.text];";
        }
      ];
    }
    # Every Bash result: an error two batches back clears a fresh escape.
    {
      id = "M-se-stale";
      hook = "sandbox-escape-evidence.js";
      kills = "se-stale-deny";
      swaps = [
        {
          anchor = "A-se-batch";
          to = "const texts = results.map((r) => r.text);";
        }
      ];
    }
    # A skill body naming dangerouslyDisableSandbox read as the user's ask.
    {
      id = "M-se-scope";
      hook = "sandbox-escape-evidence.js";
      kills = "se-sysprompt-deny";
      swaps = [
        {
          anchor = "A-se-scope";
          to = "if (false) continue;";
        }
      ];
    }
    # Any tool's result: a clean Read after the EPERM hides it.
    {
      id = "M-se-bashonly";
      hook = "sandbox-escape-evidence.js";
      kills = "se-nonbash-skip-allow";
      swaps = [
        {
          anchor = "A-se-bashonly";
          to = "if (!u || b.tool_use_id === current) continue;";
        }
      ];
    }
    # Quotes ignored: `echo 'x; docker'` yields a docker segment, allowed.
    {
      id = "M-se-segments";
      hook = "sandbox-escape-evidence.js";
      kills = "se-quoted-sep-deny";
      swaps = [
        {
          anchor = "A-se-segments";
          to = "return cmd.split(/&&|\\|\\||[;|\\n]/).some((s) => ALLOW.some((re) => re.test(s.trim())));";
        }
      ];
    }
    # The flag's bare name read as an ask: "do not use it" allowed.
    {
      id = "M-se-ask";
      hook = "sandbox-escape-evidence.js";
      kills = "se-user-token-deny";
      swaps = [
        {
          anchor = "A-se-ask";
          to = "const USER_ASK = /(sans|hors|without|bypass|outside|disable)\\W+(?:the\\s+|le\\s+|du\\s+)?sandbox|dangerouslyDisableSandbox/i;";
        }
      ];
    }
    # curl --noproxy unlisted: the refused-proxy retry denied.
    {
      id = "M-se-noproxy";
      hook = "sandbox-escape-evidence.js";
      kills = "se-noproxy-allow";
      swaps = [
        {
          anchor = "A-se-noproxy";
          to = "/^curl\\b(?!)/,";
        }
      ];
    }
    # wrangler unlisted: the OAuth-less deploy retry denied.
    {
      id = "M-se-wrangler";
      hook = "sandbox-escape-evidence.js";
      kills = "se-wrangler-exec-allow";
      swaps = [
        {
          anchor = "A-se-wrangler";
          to = "/^wrangler\\b(?!)/,";
        }
      ];
    }
    # pnpm run deploy unlisted: the wrangler-backed deploy retry denied.
    {
      id = "M-se-deploy";
      hook = "sandbox-escape-evidence.js";
      kills = "se-deploy-allow";
      swaps = [
        {
          anchor = "A-se-deploy";
          to = "/^pnpm\\b(?!)/,";
        }
      ];
    }
    # git's ref mkdir refusal unread: the retry denied.
    {
      id = "M-se-mkdir";
      hook = "sandbox-escape-evidence.js";
      kills = "se-mkdir-ref-allow";
      swaps = [
        {
          anchor = "A-se-mkdir";
          to = "const EVIDENCE = /Operation not permitted|\\bEPERM\\b|\\bEACCES\\b|Read-only file system|sandbox_violations|Unable to create .*\\.lock|Permission denied|cannot connect to socket|unable to open database file|readonly database|Couldn't load public key|getaddrinfo ENOTFOUND/i;";
        }
      ];
    }
    # A direct client's blocked DNS lookup unread: the retry denied.
    {
      id = "M-se-dns";
      hook = "sandbox-escape-evidence.js";
      kills = "se-dns-allow";
      swaps = [
        {
          anchor = "A-se-mkdir";
          to = "const EVIDENCE = /Operation not permitted|\\bEPERM\\b|\\bEACCES\\b|Read-only file system|sandbox_violations|Unable to create .*\\.lock|Permission denied|cannot connect to socket|unable to open database file|readonly database|Couldn't load public key|unable to create directory/i;";
        }
      ];
    }
    # worktree-env-sync run. The worktree's own .env.production overwritten
    # with the main checkout's: no presence check, and `ln -nf` to replace.
    {
      id = "M-wes-overwrite";
      hook = "worktree-env-sync.sh";
      kills = "wes-sessionstart-copy";
      swaps = [
        {
          anchor = "A-wes-present";
          to = ":";
        }
        {
          anchor = "A-wes-link";
          to = "if cp -p \"$src\" \"$tmp\" 2>/dev/null && ln -nf \"$tmp\" \"$dst\" 2>/dev/null; then LIST=\"$LIST, $name\"; fi";
        }
      ];
    }
    # A symlink source followed: .env.local (-> .env) lands as a copy.
    {
      id = "M-wes-symlink";
      hook = "worktree-env-sync.sh";
      kills = "wes-sessionstart-copy";
      swaps = [
        {
          anchor = "A-wes-symlink";
          to = "if [ ! -f \"$src\" ]; then continue; fi";
        }
      ];
    }
    # The main checkout's tracking unread: .env.example, tracked there and
    # dropped from the worktree's index, is copied back in.
    {
      id = "M-wes-tracked";
      hook = "worktree-env-sync.sh";
      kills = "wes-sessionstart-copy";
      swaps = [
        {
          anchor = "A-wes-ign-main";
          to = ":";
        }
      ];
    }
    # The worktree's own ignore rules unread: .env.staging, which its
    # .gitignore un-ignores, is copied in as a file git would commit.
    {
      id = "M-wes-wtignore";
      hook = "worktree-env-sync.sh";
      kills = "wes-sessionstart-copy";
      swaps = [
        {
          anchor = "A-wes-ign-wt";
          to = ":";
        }
      ];
    }
    # The fsmonitor override dropped from the main checkout's check-ignore:
    # the repo's core.fsmonitor command runs, outside the sandbox.
    {
      id = "M-wes-fsmonitor";
      hook = "worktree-env-sync.sh";
      kills = "wes-fsmonitor-pwned";
      swaps = [
        {
          anchor = "A-wes-ign-main";
          to = "\"$GIT\" -C \"$MAIN\" check-ignore -q -- \"$name\" 2>/dev/null || continue";
        }
      ];
    }
    # session-state run. The ABDUCO_SESSION gate dropped: a session outside
    # abduco writes a state file (named `.json`, the name being empty).
    {
      id = "M-ss-gate";
      hook = "session-state.js";
      kills = "ss-noabduco-silent";
      swaps = [
        {
          anchor = "A-ss-gate";
          to = ";";
        }
      ];
    }
    # The headless gate dropped: a `claude -p` inside the agent replaces its
    # file.
    {
      id = "M-ss-headless";
      hook = "session-state.js";
      kills = "ss-headless-kept";
      swaps = [
        {
          anchor = "A-ss-headless";
          to = ";";
        }
      ];
    }
    # apex-pr-record run, one canary per write or no-write branch.
    # Any command starting with gh read as a merge: `gh pr view 42` records.
    {
      id = "M-apr-cmd";
      hook = "apex-pr-record.js";
      kills = "apr-notmerge-silent";
      swaps = [
        {
          anchor = "A-apr-cmd";
          to = "if (!w) return;";
        }
      ];
    }
    # An interrupted merge call recorded all the same.
    {
      id = "M-apr-failed";
      hook = "apex-pr-record.js";
      kills = "apr-toolfailed-silent";
      swaps = [
        {
          anchor = "A-apr-failed";
          to = ";";
        }
      ];
    }
    # The state unread: `--auto`, still OPEN, recorded as merged.
    {
      id = "M-apr-state";
      hook = "apex-pr-record.js";
      kills = "apr-open-silent";
      swaps = [
        {
          anchor = "A-apr-state";
          to = "if (!pr) return;";
        }
      ];
    }
    # Value flags not skipped: `-b 'x y'` becomes the selector.
    {
      id = "M-apr-valueflags";
      hook = "apex-pr-record.js";
      kills = "apr-selector-args";
      swaps = [
        {
          anchor = "A-apr-valueflags";
          to = "if (false) {";
        }
      ];
    }
    # No `Branch:` match: the run that only names the branch gets pr.md.
    {
      id = "M-apr-branchline";
      hook = "apex-pr-record.js";
      kills = "apr-branch-write";
      swaps = [
        {
          anchor = "A-apr-branchline";
          to = "let hits = [];";
        }
      ];
    }
    # `Branch: feat/x-2` taken for feat/x.
    {
      id = "M-apr-prefix";
      hook = "apex-pr-record.js";
      kills = "apr-prefix-nomatch";
      swaps = [
        {
          anchor = "A-apr-prefix";
          to = "return rest.startsWith(head);";
        }
      ];
    }
    # A header naming feat/x-2 taken for feat/x.
    {
      id = "M-apr-token";
      hook = "apex-pr-record.js";
      kills = "apr-prefix-nomatch";
      swaps = [
        {
          anchor = "A-apr-token";
          to = "return true;";
        }
      ];
    }
    # The header fallback open to runs on another branch.
    {
      id = "M-apr-branchless";
      hook = "apex-pr-record.js";
      kills = "apr-otherbranch-silent";
      swaps = [
        {
          anchor = "A-apr-branchless";
          to = "const unbranched = runs;";
        }
      ];
    }
    # No header fallback: a run without a `Branch:` line is never recorded.
    {
      id = "M-apr-fallback";
      hook = "apex-pr-record.js";
      kills = "apr-header-write";
      swaps = [
        {
          anchor = "A-apr-fallback";
          to = "if (false) hits = unbranched";
        }
      ];
    }
    # No dir-name fallback: a Direct run (no `Branch:` line) never recorded.
    {
      id = "M-apr-dirname";
      hook = "apex-pr-record.js";
      kills = "apr-dirname-write";
      swaps = [
        {
          anchor = "A-apr-dirname";
          to = "false ||";
        }
      ];
    }
    # The whole file read as header: a name on line 13 counts.
    {
      id = "M-apr-header";
      hook = "apex-pr-record.js";
      kills = "apr-header-late-silent";
      swaps = [
        {
          anchor = "A-apr-header";
          to = "const HEADER_LINES = 1000;";
        }
      ];
    }
    # First match only: the second run on the branch is left out.
    {
      id = "M-apr-multi";
      hook = "apex-pr-record.js";
      kills = "apr-multi-write";
      swaps = [
        {
          anchor = "A-apr-multi";
          to = "for (const r of hits.slice(0, 1)) {";
        }
      ];
    }
    # commit.txt ignored: a committed run gets pr.md too.
    {
      id = "M-apr-commit";
      hook = "apex-pr-record.js";
      kills = "apr-committxt-silent";
      swaps = [
        {
          anchor = "A-apr-commit";
          to = ";";
        }
      ];
    }
    # No O_EXCL: the existing pr.md overwritten.
    {
      id = "M-apr-wx";
      hook = "apex-pr-record.js";
      kills = "apr-existing-kept";
      swaps = [
        {
          anchor = "A-apr-wx";
          to = "fs.writeFileSync(path.join(r.dir, \"pr.md\"), body, { flag: \"w\" });";
        }
      ];
    }
    # Malformed input denied: every Bash call pays for an unreadable payload.
    {
      id = "M-wh-failopen";
      hook = "worktree-in-use.js";
      kills = "wh-malformed";
      swaps = [
        {
          anchor = "A-wh-failopen";
          to = "try { data = JSON.parse(input); } catch { deny(\"BLOCKED: malformed\"); return; }";
        }
      ];
    }
    # A liveness read that failed allows: a missing lsof clears the removal.
    {
      id = "M-wh-blind";
      hook = "worktree-in-use.js";
      kills = "wh-lsof-missing-deny";
      swaps = [
        {
          anchor = "A-wh-blind";
          to = "if (ls.broken) allow();";
        }
      ];
    }
    # No holder match: the held worktree goes.
    {
      id = "M-wh-holder";
      hook = "worktree-in-use.js";
      kills = "wh-remove-held";
      swaps = [
        {
          anchor = "A-wh-holder";
          to = "const t = undefined;";
        }
      ];
    }
    # No self-exclusion: the hook, its lsof and its parent shell hold their
    # own cwd, so a session can never remove the worktree it sits in.
    {
      id = "M-wh-self";
      hook = "worktree-in-use.js";
      kills = "wh-self-cwd";
      swaps = [
        {
          anchor = "A-wh-self";
          to = "const isSelf = (p) => false;";
        }
      ];
    }
    # No checkout test: `rm -r` of a held worktree reads as a plain directory.
    {
      id = "M-wh-checkout";
      hook = "worktree-in-use.js";
      kills = "wh-rm-held";
      swaps = [
        {
          anchor = "A-wh-checkout";
          to = "if (false) return true;";
        }
      ];
    }
    # String prefix for ancestry: wts/hel is held because wts/held is.
    {
      id = "M-wh-prefix";
      hook = "worktree-in-use.js";
      kills = "wh-sibling";
      swaps = [
        {
          anchor = "A-wh-prefix";
          to = "return c.startsWith(r);";
        }
      ];
    }
    # No realpath: a symlinked spelling never meets lsof's physical cwd.
    {
      id = "M-wh-realpath";
      hook = "worktree-in-use.js";
      kills = "wh-remove-symlink-held";
      swaps = [
        {
          anchor = "A-wh-realpath";
          to = "const real = p;";
        }
      ];
    }
    # No suffix lookup: a bare worktree name is never placed.
    {
      id = "M-wh-suffix";
      hook = "worktree-in-use.js";
      kills = "wh-remove-suffix-held";
      swaps = [
        {
          anchor = "A-wh-suffix";
          to = "if (false) {";
        }
      ];
    }
    # `cd` ignored: the incident's `cd main && git worktree remove ../wt`
    # resolves against the old cwd.
    {
      id = "M-wh-cd";
      hook = "worktree-in-use.js";
      kills = "wh-incident-chain";
      swaps = [
        {
          anchor = "A-wh-cd";
          to = "return cur;";
        }
      ];
    }
    # `git -C` ignored: the target resolves against the session cwd.
    {
      id = "M-wh-C";
      hook = "worktree-in-use.js";
      kills = "wh-remove-C-force-held";
      swaps = [
        {
          anchor = "A-wh-C";
          to = "dir = cur;";
        }
      ];
    }
    # No glob expansion: `rm -rf wts/held*` names a path that does not exist.
    {
      id = "M-wh-glob";
      hook = "worktree-in-use.js";
      kills = "wh-rm-glob-held";
      swaps = [
        {
          anchor = "A-wh-glob";
          to = "if (true) {";
        }
      ];
    }
    # No brace expansion: `wts/{held,free}` names a path that does not exist.
    {
      id = "M-wh-brace";
      hook = "worktree-in-use.js";
      kills = "wh-brace-held";
      swaps = [
        {
          anchor = "A-wh-brace";
          to = "if (true) continue;";
        }
      ];
    }
    # A glob in the remove target dropped: `wts/hel?` lets held go.
    {
      id = "M-wh-remove-glob";
      hook = "worktree-in-use.js";
      kills = "wh-remove-glob-held";
      swaps = [
        {
          anchor = "A-wh-remove-glob";
          to = "if (hasGlob(b)) continue;";
        }
      ];
    }
    # Path before name: a plain sub/held stops the lookup git does first.
    {
      id = "M-wh-suffix-first";
      hook = "worktree-in-use.js";
      kills = "wh-suffix-over-plain-dir";
      swaps = [
        {
          anchor = "A-wh-suffix-first";
          to = "if (real !== null) { out.push({ path: real, kind: \"remove\" }); return; }";
        }
      ];
    }
    # `env -C` ignored: the target resolves against the session cwd.
    {
      id = "M-wh-env-C";
      hook = "worktree-in-use.js";
      kills = "wh-env-C-held";
      swaps = [
        {
          anchor = "A-wh-env-C";
          to = "if (chdir.includes(o)) { k += 2; continue; }";
        }
      ];
    }
    # `$PWD` never placed: `cd wts && rm -rf $PWD/held` goes through.
    {
      id = "M-wh-pwd";
      hook = "worktree-in-use.js";
      kills = "wh-pwd-held";
      swaps = [
        {
          anchor = "A-wh-pwd";
          to = "const words = raw;";
        }
      ];
    }
    # The direct parent excluded whatever it is: a Claude session (node)
    # removes the worktree it runs in.
    {
      id = "M-wh-selfparent";
      hook = "worktree-in-use.js";
      kills = "wh-self-nonshell-parent";
      swaps = [
        {
          anchor = "A-wh-self";
          to = "const isSelf = (p) => p.pid === process.pid || p.pid === child || p.ppid === process.pid || p.pid === process.ppid;";
        }
      ];
    }
    # A listing without the hook in it trusted: it cleared nobody.
    {
      id = "M-wh-noself";
      hook = "worktree-in-use.js";
      kills = "wh-lsof-noself-deny";
      swaps = [
        {
          anchor = "A-wh-noself";
          to = "if (false) return";
        }
      ];
    }
    # An lsof that exited 2 read as a listing.
    {
      id = "M-wh-badexit";
      hook = "worktree-in-use.js";
      kills = "wh-lsof-badexit-deny";
      swaps = [
        {
          anchor = "A-wh-badexit";
          to = "if (false) return";
        }
      ];
    }
  ];

  # Order is the run order; a name here with no branch in `probe_case` below
  # fails the suite ("no such case"), never skips.
  caseNames = [
    "pm-master-inrepo"
    "pm-master-malformed"
    "pm-master-nogit"
    "pm-norepo-nogit"
    "pm-master-hung"
    "pm-master-symlink-newfile"
    "pm-master-case"
    "pm-master-dangling-link"
    "pm-master-outside"
    "pm-feat"
    "pm-norepo"
    "pm-detached"
    "pm-cross-feat-cwd"
    "pm-cross-norepo-cwd"
    "pm-feat-to-norepo"
    "pm-notebook-master"
    "pm-notebook-outside"
    "pm-vault-main"
    "pm-vault-crosscwd"
    "pm-apex-new"
    "pm-apex-existing"
    "pm-apex-crosscwd"
    "pm-apex-norepo-cwd"
    "pm-apex-case"
    "pm-apex-tracked"
    "pm-apex-ignored-outside"
    "pm-apex-unignored"
    "pm-apex-symlink"
    "pm-apex-hardlink"
    "pm-apex-nested"
    "pm-apex-fsmonitor-pwned"
    "pm-apex-sibling"
    "bb-master-commit"
    "bb-master-malformed"
    "bb-master-nogit"
    "bb-master-hung"
    "bb-master-nl-flood"
    "bb-master-C-flood"
    "bb-master-gl-bound"
    "bb-master-status"
    "bb-local-commit"
    "bb-feat-commit"
    "bb-norepo-commit"
    "bb-detached-commit"
    "bb-cd-nonexistent"
    "bb-cd-broken"
    "bb-pull-master"
    "bb-cross-C-after-c"
    "bb-second-cd"
    "bb-gitdir-env"
    "bb-leading-cd-feat"
    "bb-vault-commit"
    "fmt-inject"
    "fmt-no-config"
    "cb-round3-deny"
    "cb-sendmessage-round3-deny"
    "cb-nomarker-deny"
    "cb-other-run-allow"
    "cb-plain-allow"
    "cb-none-allow"
    "cb-state-unwritable-deny"
    "cb-sonnet-deny"
    "cb-nomodel-deny"
    "cb-opus-allow"
    "cb-sendmessage-nomodel-allow"
    "cb-grant-round3-allow"
    "cb-cron-token-deny"
    "cb-cron-plain-allow"
    "cb-abs-run-allow"
    "cb-abs-run-cap-deny"
    "cb-abs-run-bad-deny"
    "cb-abs-run-unnormalized-deny"
    "cg-token-grants"
    "cg-no-token"
    "cg-inline-token-ignored"
    "cg-not-exhausted"
    "cg-newest-exhausted"
    "cg-stacks"
    "cg-subagent-ignored"
    "cg-malformed-quiet"
    "cg-no-rundir-told"
    "cg-double-token-once"
    "cg-existing-grant-kept"
    "cg-wrapped-ignored"
    "cg-notification-ignored"
    "cg-token-not-first-ignored"
    "cg-agentid-nonstring-ignored"
    "cg-newest-not-spent"
    "cg-cross-repo-grants"
    "cg-cross-repo-other-session"
    "cg-cross-repo-bad-dir"
    "rm-explore-sonnet-deny"
    "rm-navigator-opus-deny"
    "rm-navigator-nomodel-deny"
    "rm-explore-haiku-allow"
    "rm-plan-opus-allow"
    "rm-malformed-allow"
    "rm-oversize-allow"
    "le-cd-chain-deny"
    "le-git-C-deny"
    "le-git-c-deny"
    "le-add-commit-deny"
    "le-pipe-deny"
    "le-redir-deny"
    "le-subst-deny"
    "le-echo-subst-deny"
    "le-heredoc-deny"
    "le-env-prefix-deny"
    "le-timeout-deny"
    "le-wrapper-opt-deny"
    "le-heredoc-body-deny"
    "le-dispatch-cd-deny"
    "le-retired-bg-push-deny"
    "le-dispatch-env-deny"
    "le-dispatch-abs-deny"
    "le-pnpm-cd-deny"
    "le-pnpm-pipe-deny"
    "le-pnpm-args-deny"
    "le-pnpm-run-deny"
    "le-deploy-cd-deny"
    "le-deploy-redir-deny"
    "le-deploy-prod-pipe-deny"
    "le-deploy-prod-args-deny"
    "le-push-allow"
    "le-push-u-allow"
    "le-commit-F-allow"
    "le-body-file-allow"
    "le-json-allow"
    "le-dup-allow"
    "le-grep-allow"
    "le-rg-allow"
    "le-quoted-msg-allow"
    "le-status-diff-allow"
    "le-chain-targets-allow"
    "le-dispatch-allow"
    "le-pnpm-start-allow"
    "le-pnpm-stop-allow"
    "le-pnpm-chain-allow"
    "le-pnpm-install-allow"
    "le-pnpm-pipe-other-allow"
    "le-deploy-allow"
    "le-deploy-prod-allow"
    "le-deploy-dup-allow"
    "le-deploy-norun-allow"
    "le-retired-bg-cd-allow"
    "le-malformed-allow"
    "le-command-v-allow"
    "se-preempt-deny"
    "se-stale-deny"
    "se-sysprompt-deny"
    "se-quoted-sep-deny"
    "se-user-token-deny"
    "se-curl-proxy-deny"
    "se-pnpm-deploy-builtin-deny"
    "se-deployer-deny"
    "se-eperm-allow"
    "se-violations-allow"
    "se-mkdir-ref-allow"
    "se-dns-allow"
    "se-batch-allow"
    "se-nonbash-skip-allow"
    "se-allowlist-allow"
    "se-allowlist-verify-allow"
    "se-noproxy-allow"
    "se-deploy-allow"
    "se-wrangler-allow"
    "se-wrangler-exec-allow"
    "se-wrangler-npx-allow"
    "se-noflag-allow"
    "se-user-asked-allow"
    "se-missing-transcript-allow"
    "se-malformed-allow"
    "wes-sessionstart-copy"
    "wes-enterworktree-copy"
    "wes-rerun-silent"
    "wes-main-silent"
    "wes-norepo-silent"
    "wes-malformed-silent"
    "wes-dangling-dest"
    "wes-fsmonitor-pwned"
    "ss-prompt-working"
    "ss-intent-truncated"
    "ss-stop-waiting"
    "ss-notify-end"
    "ss-start-idle"
    "ss-new-session-fresh"
    "ss-noabduco-silent"
    "ss-headless-kept"
    "ss-attended-writes"
    "ss-badname-silent"
    "ss-malformed-silent"
    "ss-symlink-dir"
    "ss-symlink-file"
    "apr-branch-write"
    "apr-header-write"
    "apr-dirname-write"
    "apr-header-late-silent"
    "apr-existing-kept"
    "apr-committxt-silent"
    "apr-open-silent"
    "apr-ghfail-silent"
    "apr-notmerge-silent"
    "apr-toolfailed-silent"
    "apr-malformed-silent"
    "apr-prefix-nomatch"
    "apr-otherbranch-silent"
    "apr-multi-write"
    "apr-selector-args"
    "apr-noselector-write"
    "wh-remove-held"
    "wh-remove-C-force-held"
    "wh-remove-suffix-held"
    "wh-remove-symlink-held"
    "wh-rm-held"
    "wh-rm-parent-held"
    "wh-rm-glob-held"
    "wh-incident-chain"
    "wh-lsof-missing-deny"
    "wh-lsof-hung-deny"
    "wh-remove-free"
    "wh-prune"
    "wh-rm-plain-held"
    "wh-sibling"
    "wh-self-cwd"
    "wh-unrelated"
    "wh-var"
    "wh-malformed"
    "wh-nomatch-lsof-missing"
    "wh-brace-held"
    "wh-remove-glob-held"
    "wh-suffix-over-plain-dir"
    "wh-env-C-held"
    "wh-pwd-held"
    "wh-self-nonshell-parent"
    "wh-lsof-noself-deny"
    "wh-lsof-badexit-deny"
    "iw-reel-emits"
    "iw-post-query-emits"
    "iw-user-reel-emits"
    "iw-mention-silent"
    "iw-other-url-silent"
    "iw-wrapped-silent"
    "iw-subagent-silent"
    "iw-malformed-silent"
    "iw-no-prompt-silent"
    "ac-prose-emits"
    "ac-edit-emits"
    "ac-cap-emits"
    "ac-bare-lecture-emits"
    "ac-lecture-silent"
    "ac-deferred-silent"
    "ac-docs-silent"
    "ac-proven-silent"
    "ac-other-file-silent"
    "ac-outside-run-silent"
    "ac-missing-silent"
    "ac-symlink-silent"
    "ac-malformed-silent"
    "ac-self-test"
    "ac-validate-untallied-emits"
    "ac-validate-tally-silent"
    "ac-validate-blocked-silent"
    "ac-validate-examine-emits"
    "ac-validate-examine-link-silent"
    "ac-mem-dangling-emits"
    "ac-mem-clean-silent"
    "ac-mem-unindexed-emits"
    "ac-mem-index-dead-emits"
    "ac-mem-outside-silent"
    "ac-mem-symlink-silent"
    "ac-mem-notes-memory-silent"
    "pr-missing-acs-emits"
    "pr-examine-untallied-emits"
    "pr-xflag-noexamine-emits"
    "pr-complete-silent"
    "pr-standard-notally-silent"
    "pr-direct-silent"
    "pr-untiered-silent"
    "pr-other-branch-silent"
    "pr-head-flag-emits"
    "pr-finished-run-silent"
    "pr-other-command-silent"
    "pr-failed-tool-silent"
    "pr-nogit-silent"
    "pr-ctx-symlink-silent"
    "pr-head-in-title-emits"
    "pr-unsplittable-silent"
    "pr-external-untallied-emits"
    "pr-newest-incomplete-emits"
    "pr-newest-complete-silent"
  ];

  # The vault exemption is keyed on the path settings.nix bakes into both
  # guards. The vault cases run a copy of the body with that literal, and
  # only that literal, pointed at a fixture: counted here at eval, and again
  # on each body (mutants included) at run time.
  vaultLit = builtins.toJSON settings.alxVaultPath;
  occurrences =
    needle: text:
    (
      builtins.stringLength text - builtins.stringLength (builtins.replaceStrings [ needle ] [ "" ] text)
    )
    / builtins.stringLength needle;
  vaultLitMiscounts = builtins.filter (n: occurrences vaultLit (bodyText n) != 1) [
    "protect-main.js"
    "block-main-bash.js"
  ];

  # worktree-in-use.js reads liveness from lsof at one absolute path; the wh
  # cases run a copy with that literal, and only that literal, repointed at a
  # fake (the build sandbox has no /usr/sbin and no process info). Counted
  # here at eval (D7), and again on each body at run time.
  whLsofLit = "const LSOF = \"/usr/sbin/lsof\";";
  whLsofMiscount = occurrences whLsofLit (bodyText "worktree-in-use.js") != 1;

  bodyText = n: bodies.${n} or "";
  missingAnchors = builtins.filter (
    id: !(hasInfix anchors.${id}.text (bodyText anchors.${id}.hook))
  ) (builtins.attrNames anchors);
  foreignAnchors = builtins.concatMap (
    m: map (s: "${m.id}/${s.anchor}") (builtins.filter (s: anchors.${s.anchor}.hook != m.hook) m.swaps)
  ) mutants;
  mutantBody =
    m:
    builtins.replaceStrings (map (s: anchors.${s.anchor}.text) m.swaps) (map (s: s.to) m.swaps) (
      bodyText m.hook
    );
  inertMutants = map (m: m.id) (builtins.filter (m: mutantBody m == bodyText m.hook) mutants);
  strandedCanaries = map (m: "${m.id} -> ${m.kills}") (
    builtins.filter (m: !(builtins.elem m.kills caseNames)) mutants
  );

  # Each body runs under the timeout its registration gives the host, read
  # from settings: an expired hook is no decision and the host proceeds, so a
  # body granted more time than that passes a case the host would lose.
  runHooks = [
    "protect-main.js"
    "block-main-bash.js"
    "format-typescript.js"
    "correction-budget.js"
    "correction-grant.js"
    "research-model.js"
    "lone-excluded-bash.js"
    "sandbox-escape-evidence.js"
    "worktree-env-sync.sh"
    "session-state.js"
    "apex-pr-record.js"
    "worktree-in-use.js"
    "instagram-watch.js"
    "apex-metrics-probe.py"
  ];
  timeoutsOf =
    n:
    lib.unique (
      map (r: r.timeout) (builtins.filter (r: builtins.elem n (hookRefsIn r.command)) registrations)
    );
  badTimeouts = builtins.filter (
    n:
    let
      ts = timeoutsOf n;
    in
    !(builtins.length ts == 1 && builtins.isInt (builtins.head ts) && builtins.head ts > 0)
  ) runHooks;
  hostTimeout = n: toString (builtins.head (timeoutsOf n));

  # The probe's Bash trigger: `if` must sit on the handler, where the host reads it.
  prProbeIf = "Bash(gh pr create *)";
  prProbeGroups = builtins.filter (
    g:
    (g.matcher or null) == "Bash"
    && builtins.any (h: builtins.elem "apex-metrics-probe.py" (hookRefsIn (h.command or ""))) (
      entriesOf g
    )
  ) (groupsOf "PostToolUse");
  prProbeGated = g: !(g ? "if") && builtins.all (h: (h."if" or null) == prProbeIf) (entriesOf g);

  hookFile = n: pkgs.writeText n (bodyText n);
  mutantFile = m: pkgs.writeText "${m.id}-${m.hook}" (mutantBody m);
  canarySpecs = builtins.concatStringsSep " " (map (m: "${m.id}:${m.kills}:${mutantFile m}") mutants);

  jq = "${pkgs.jq}/bin/jq";

  # Grades. Deny, in Claude's form: exit 0, a deny decision on stdout, nothing
  # on stderr, and a reason naming WHY — without it a hook that dies before
  # reading git and one that refuses on purpose look alike. Allow: exit 0 and
  # silence on both streams, byte for byte.
  # Positive controls: pm-master-inrepo and bb-master-commit (the guard really
  # reaches its branch read), fmt-inject's prettier.log (prettier really ran),
  # fmt-no-config's config.log (the hook really asked for a config).
  runtimeProbe = ''
    root="$TMPDIR/hook-probe"
    d="$root/out"
    rm -rf "$root"
    mkdir -p "$d" "$root/norepo" "$root/emptybin" "$root/hangbin" "$root/fakebin" "$root/fmt" "$root/badbin"
    g() { GIT_CONFIG_NOSYSTEM=1 HOME="$TMPDIR" ${pkgs.git}/bin/git "$@"; }
    MASTER="$root/master"
    LOCAL="$root/local"
    FEAT="$root/feat"
    DETACHED="$root/detached"
    NOREPO="$root/norepo"
    LINK="$root/link"
    VAULT="$root/vault"
    VAULT_LIT=${lib.escapeShellArg vaultLit}
    GITBIN=${pkgs.git}/bin
    g init -q -b master "$MASTER"
    g -C "$MASTER" remote add origin https://example.invalid/x.git
    g init -q -b master "$LOCAL"
    g init -q -b main "$VAULT"
    g init -q -b feat/probe "$FEAT"
    g init -q -b master "$DETACHED"
    g -C "$DETACHED" -c user.name=p -c user.email=p@p -c commit.gpgsign=false commit -q --allow-empty -m probe
    g -C "$DETACHED" checkout -q --detach
    ln -s "$MASTER" "$LINK"
    # APEX run state. APEXR, on master, ignores `.claude/`; under its
    # `.claude/output/apex/` sit a force-added tracked file, an untracked
    # one, a symlink to its tracked src/, a hardlink of a tracked file and a
    # nested repo on master. UNIG is on master and ignores nothing. The last
    # two lines prove the ignore split the cases rest on.
    APEXR="$root/apexr"
    APEXO="$APEXR/.claude/output/apex"
    UNIG="$root/unig"
    {
      g init -q -b master "$APEXR" &&
        mkdir -p "$APEXR/src" "$APEXO/forced" "$APEXO/old" "$APEXO/hl" &&
        printf '%s\n' '.claude/' > "$APEXR/.gitignore" &&
        printf 'x\n' > "$APEXR/src/a.ts" &&
        printf 'x\n' > "$APEXO/forced/00-context.md" &&
        printf 'x\n' > "$APEXO/old/00-context.md" &&
        g -C "$APEXR" add .gitignore src/a.ts &&
        g -C "$APEXR" add -f .claude/output/apex/forced/00-context.md &&
        g -C "$APEXR" -c user.name=p -c user.email=p@p -c commit.gpgsign=false commit -q -m probe &&
        ln -s "$APEXR/src" "$APEXO/lnk" &&
        ln "$APEXR/src/a.ts" "$APEXO/hl/00-context.md" &&
        g init -q -b master "$APEXO/nest" &&
        g init -q -b master "$UNIG" &&
        g -C "$APEXR" check-ignore -q -- .claude/output/apex/new/00-context.md &&
        ! g -C "$APEXR" check-ignore -q -- .claude/output/apex/forced/00-context.md
    } || { echo "hook-wiring: apex fixture could not be built" >&2; exit 1; }
    # Dangling, outside the repo, aimed INTO it: a Write there lands in MASTER.
    ln -s "$MASTER/dangling-target.ts" "$NOREPO/dangling"
    # `exec`: SIGKILL on timeout must reach the sleeper, not orphan it on the pipe.
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exec ${pkgs.coreutils}/bin/sleep 30' > "$root/hangbin/git"
    # The fake prettier. `--find-config-path` logs its path to config.log and
    # exits 1 (no config) while a no-config marker sits beside it, else 0;
    # `--write` alone logs to prettier.log, so that log holds only what was
    # formatted.
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      'here="''${0%/*}"' \
      'case "$1" in' \
      '  --find-config-path) printf "%s\n" "$2" >> "$here/config.log"; [ ! -e "$here/no-config" ]; exit $? ;;' \
      '  --write) printf "%s\n" "$2" >> "$here/prettier.log" ;;' \
      'esac' > "$root/fakebin/prettier"
    # A git that fails on MASTER alone ("bad object HEAD", not "not a git
    # repository") and is real git elsewhere: `cd $MASTER && git commit` from
    # FEAT must deny, not fall back to FEAT's branch. Matched on the physical
    # path, which is what getcwd gives the wrapper.
    MASTER_REAL=$(cd "$MASTER" && pwd -P)
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      "if [ \"\$(pwd -P)\" = \"$MASTER_REAL\" ]; then echo 'fatal: bad object HEAD' >&2; exit 128; fi" \
      "exec $GITBIN/git \"\$@\"" > "$root/badbin/git"
    chmod +x "$root/hangbin/git" "$root/fakebin/prettier" "$root/badbin/git"
    malformed='{"hook_event_name":"PreToolUse","tool_input":{'

    pm_in() { ${jq} -cn --arg f "$1" '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$f,content:"x"}}'; }
    pm_nb_in() { ${jq} -cn --arg f "$1" '{hook_event_name:"PreToolUse",tool_name:"NotebookEdit",tool_input:{notebook_path:$f,new_source:"x"}}'; }
    bb_in() { ${jq} -cn --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
    fmt_in() { ${jq} -cn --arg f "$1" '{hook_event_name:"PostToolUse",tool_name:"Write",tool_input:{file_path:$f}}'; }
    # A commit followed by 64 KB of newlines, built by jq: a shell `$(…)`
    # would strip the very newlines the case is about.
    bb_flood() { ${jq} -cn '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:("git commit -m x" + ("\n" * 65536))}}'; }
    # 1000 bare `-C` before the verb: linear now, past any timeout before run 65.
    bb_cflood() { ${jq} -cn '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:("git" + (" -C" * 1000) + " commit")}}'; }
    # 4000 `git` words over 68 KB: past the G·L scan bound, refused unscanned
    # (4.7 s, i.e. a host-timeout allow, before the bound existed).
    bb_glbound() { ${jq} -cn '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:("git" + (" -c user.name=git" * 4000) + " commit")}}'; }

    # correction-budget: run dirs live in a fixture repo, the counter under
    # $HOME, which run() pins to $TMPDIR. The counter thus outlives a case and
    # reaches the canary re-runs: every cb case wipes it first.
    CBREPO="$root/cbrepo"
    CBSTATE="$TMPDIR/.claude/apex-correction-budget"
    # A run outside $CBREPO, named by its absolute run dir.
    CBOTHER="$root/cbother/.claude/output/apex/64-z"
    cb_reset() {
      if [ -e "$CBSTATE" ]; then chmod -R u+w "$CBSTATE"; fi
      rm -rf "$CBSTATE"
      mkdir -p "$CBREPO/.claude/output/apex/62-x" "$CBREPO/.claude/output/apex/63-y" "$CBOTHER" "$root/cbother/notapex/64-z"
    }
    # $1 brief, $2 marker: a run-id, none, or absent for no marker line.
    # $3 model: opus when unset, absent from the input when empty.
    cb_in() { ${jq} -cn --arg p "$1" --arg m "''${2-}" --arg mo "''${3-opus}" --arg c "$CBREPO" '{hook_event_name:"PreToolUse",tool_name:"Agent",cwd:$c,session_id:"probe",tool_input:({description:"probe",subagent_type:"general-purpose",prompt:(if $m == "" then $p else $p + "\nAPEX-CORRECTION-ROUND: " + $m end)} + (if $mo == "" then {} else {model:$mo} end))}'; }
    # Same brief as a SendMessage re-brief to a live agent ($2 required).
    cb_msg() { ${jq} -cn --arg p "$1" --arg m "$2" --arg c "$CBREPO" '{hook_event_name:"PreToolUse",tool_name:"SendMessage",cwd:$c,session_id:"probe",tool_input:{to:"implementer",summary:"probe",message:($p + "\nAPEX-CORRECTION-ROUND: " + $m)}}'; }
    # $1 body, $2 run-id, $3 round number: one marked round, due an allow.
    cb_round() {
      run "$lbl" "$1" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." "$2")"
      is_allow || { why="round $3 on $2: $why"; return 1; }
    }
    # $1 run-id, $2 rounds, $3 mtime (epoch): rounds spent without the hook,
    # as the files correction-budget.js leaves.
    cb_spend() {
      mkdir -p "$CBSTATE"
      for i in $(${pkgs.coreutils}/bin/seq 1 "$2"); do
        : > "$CBSTATE/$1.round$i"
        ${pkgs.coreutils}/bin/touch -d "@''${3-1700000000}" "$CBSTATE/$1.round$i"
      done
    }
    # $1 run-id, $2 rounds, $3 dir, $4 session: rounds stamped as
    # correction-budget.js leaves them, the run dir recorded.
    cb_stamp() {
      mkdir -p "$CBSTATE"
      for i in $(${pkgs.coreutils}/bin/seq 1 "$2"); do
        ${jq} -cn --arg d "$3" --arg s "$4" '{ts:"2026-01-01T00:00:00.000Z",tool:"Agent",session:$s,description:"probe",dir:$d}' > "$CBSTATE/$1.round$i"
      done
    }

    # A scheduler call ($1 tool) whose prompt ($2) comes back as a user turn.
    cb_sched() { ${jq} -cn --arg t "$1" --arg p "$2" --arg c "$CBREPO" '{hook_event_name:"PreToolUse",tool_name:$t,cwd:$c,session_id:"probe",tool_input:{cron:"*/5 * * * *",prompt:$p,recurring:true}}'; }

    # correction-grant: $1 prompt, $2 agent_id as raw JSON (absent when
    # empty or unset).
    cg_in() { ${jq} -cn --arg p "$1" --arg a "''${2-}" --arg c "$CBREPO" '{hook_event_name:"UserPromptSubmit",cwd:$c,session_id:"probe",prompt:$p} + (if $a == "" then {} else {agent_id:($a | fromjson)} end)'; }
    grants() { ${pkgs.findutils}/bin/find "$CBSTATE" -name '*.grant*' 2> /dev/null | ${pkgs.coreutils}/bin/wc -l | ${pkgs.coreutils}/bin/tr -d ' '; }
    # $1 run-id, $2 grant number, $3 cap: that grant file written and said.
    is_granted() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      [ -e "$CBSTATE/$1.grant$2" ] || { why="no $1.grant$2 written, expected a grant"; kind=mismatch; return 1; }
      ctx=$(${jq} -r 'select(.hookSpecificOutput.hookEventName == "UserPromptSubmit") | .hookSpecificOutput.additionalContext // ""' "$d/$lbl.out" 2> /dev/null) || ctx=""
      case "$ctx" in
        *"granted run $1 one more correction round (cap now $3)"*) ;;
        *) why="grant written, but the context does not say it: $ctx"; return 1 ;;
      esac
    }
    # $1 expected grant-file count, $2 expected context text ("" = silence).
    is_not_granted() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      n=$(grants)
      [ "$n" -eq "$1" ] || { why="$n grant file(s), expected $1: a round was granted where none was due"; kind=mismatch; return 1; }
      if [ -z "$2" ]; then
        [ ! -s "$d/$lbl.out" ] || { why="stdout not empty, expected silence"; return 1; }
      else
        grep -Fq -- "$2" "$d/$lbl.out" || { why="context lacks '$2'"; return 1; }
      fi
    }

    # instagram-watch: $1 prompt, $2 agent_id as raw JSON (absent when empty or unset).
    iw_in() { ${jq} -cn --arg p "$1" --arg a "''${2-}" '{hook_event_name:"UserPromptSubmit",cwd:"/probe/cwd",session_id:"probe",prompt:$p} + (if $a == "" then {} else {agent_id:($a | fromjson)} end)'; }
    # $1 URL the context must name; $2 text it must not carry (unchecked when unset).
    iw_emits() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      [ -s "$d/$lbl.out" ] || { why="no output: the watch context was due"; kind=mismatch; return 1; }
      ctx=$(${jq} -r 'select(.hookSpecificOutput.hookEventName == "UserPromptSubmit") | .hookSpecificOutput.additionalContext // ""' "$d/$lbl.out" 2> /dev/null) || ctx=""
      case "$ctx" in *"$1"*'`watch` skill'*) ;; *) why="context lacks $1 or the watch skill: $ctx"; return 1 ;; esac
      if [ -n "''${2-}" ]; then case "$ctx" in *"$2"*) why="context carries '$2'"; kind=mismatch; return 1 ;; esac; fi
    }
    # Exit 2 blocks the user's prompt (hooks reference): the miss fail-open prevents.
    iw_silent() {
      [ "$rc" -ne 2 ] || { why="exit 2: the host blocks the user's prompt"; kind=mismatch; return 1; }
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      [ ! -s "$d/$lbl.out" ] || { why="context emitted where silence was due"; kind=mismatch; return 1; }
    }

    # apex-metrics-probe: an APEX run tree under $ACO, a plain one under $ACR.
    # Fixture lines are real AC text from run dirs (pin-brag-skill, 75, 65,
    # 76, 27, 53); AC_BARE is AC_LECT with the reason's dash dropped.
    ACR="$root/acr"; ACO="$ACR/.claude/output/apex"
    AC_CMD='AC5: nix flake check --no-build green'
    AC_CMD2='AC1. `python3 -I checks/apex-metrics-probe.py --self-test` exits 0 and prints the fixture count (≥ 10, both labels present).'
    AC_PROSE='AC6 Header comment explains the linear-time construction in one or two sentences.'
    AC_LECT='AC13 [lecture] — the new AC rule reads as one rule in step-02, step-04 and the verify loop, its two exceptions named alike in all three; apex-consistency proves the sentences exist, not that a planner reads them unambiguously.'
    AC_BARE="''${AC_LECT/"[lecture] — "/"[lecture] "}"
    AC_DEF='- AC20 [deferred to user] Combinaisons de rôles non exercées par R1/R2 (routage par quota) : listées dans 04-validate.'
    AC_DOCS='- AC-docs: n/a (text).'
    # $1 file, then its lines.
    ac_put() { p="$1"; shift; mkdir -p "''${p%/*}" && printf '%s\n' "$@" > "$p"; }
    # $1 tool (Write / Edit), $2 file_path.
    ac_in() { ${jq} -cn --arg t "$1" --arg f "$2" '{hook_event_name:"PostToolUse",tool_name:$t,session_id:"probe",cwd:"/probe/cwd",tool_input:{file_path:$f,content:"x"},tool_response:{filePath:$f}}'; }
    # $1 expected count of unproven ACs, $2 text the context must carry, then
    # texts it must not: a proven or exempt AC listed is the miss a canary causes.
    ac_emits() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      [ -s "$d/$lbl.out" ] || { why="no output: the unproven ACs were due"; kind=mismatch; return 1; }
      ctx=$(${jq} -r 'select(.hookSpecificOutput.hookEventName == "PostToolUse") | .hookSpecificOutput.additionalContext // ""' "$d/$lbl.out" 2> /dev/null) || ctx=""
      case "$ctx" in "$1 AC(s) in "*) ;; *) why="context does not start with '$1 AC(s) in ': $ctx"; return 1 ;; esac
      must="$2"
      shift 2
      for x in "$@"; do
        case "$ctx" in *"$x"*) why="context carries '$x': $ctx"; kind=mismatch; return 1 ;; esac
      done
      case "$ctx" in *"$must"*) ;; *) why="context lacks '$must': $ctx"; return 1 ;; esac
    }
    ac_silent() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      [ ! -s "$d/$lbl.out" ] || { why="context emitted where silence was due"; kind=mismatch; return 1; }
    }
    # --self-test of the same body: a mislabelled fixture exits 1.
    ac_selftest() {
      [ "$rc" -eq 0 ] || { why="self-test exit $rc: $(tail -n 3 "$d/$lbl.out" | tr '\n' ' ')"; kind=mismatch; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      grep -q 'failures=0' "$d/$lbl.out" || { why="no failures=0 in the self-test summary"; return 1; }
    }
    # B5 on a run's 04-validate.md. Real text: the verdicts of the 67 (PASS)
    # and 54 (BLOCKED) verify json, 67's triage tally, the first line of
    # 01-worktree-env-sync's 05-examine.md (no tally).
    AC_VPASS='{"schema_version":1,"tool":"apex-verify-external","verdict":"PASS","reason":"","model":"gpt-6-astra"}'
    AC_VBLOCK='{"schema_version":1,"tool":"apex-verify-external","verdict":"BLOCKED","reason":"timeout","model":"none"}'
    AC_TALLY='confirmed=0 unique=0 dismissed=0'
    AC_EXAM='PHASE: examine (opus Plan, read-only) + external (codex gpt-5.6-terra, FAIL 1 finding)'
    # $1 the passes the B5 line must name, after "for: ".
    ac_b5_emits() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      [ -s "$d/$lbl.out" ] || { why="no output: the missing tally was due"; kind=mismatch; return 1; }
      ctx=$(${jq} -r 'select(.hookSpecificOutput.hookEventName == "PostToolUse") | .hookSpecificOutput.additionalContext // ""' "$d/$lbl.out" 2> /dev/null) || ctx=""
      case "$ctx" in "B5: $lbl records no confirmed/dismissed tally for: $1 — add "*) ;; *) why="context is not the B5 line for '$1': $ctx"; return 1 ;; esac
    }
    # Memory branch: a note dir under $ACR/.claude/projects/<case>/memory.
    # $1 file, $2 its `name:` slug, then its body lines.
    mem_note() { mn_f="$1"; mn_s="$2"; shift 2; ac_put "$mn_f" "---" "name: $mn_s" "description: probe note" "---" "" "$@"; }
    # $1 text the memory line must carry, then texts it must not.
    mem_emits() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      [ -s "$d/$lbl.out" ] || { why="no output: the memory line was due"; kind=mismatch; return 1; }
      ctx=$(${jq} -r 'select(.hookSpecificOutput.hookEventName == "PostToolUse") | .hookSpecificOutput.additionalContext // ""' "$d/$lbl.out" 2> /dev/null) || ctx=""
      case "$ctx" in "memory: "*) ;; *) why="context does not start with 'memory: ': $ctx"; return 1 ;; esac
      must="$1"
      shift
      for x in "$@"; do
        case "$ctx" in *"$x"*) why="context carries '$x': $ctx"; kind=mismatch; return 1 ;; esac
      done
      case "$ctx" in *"$must"*) ;; *) why="context lacks '$must': $ctx"; return 1 ;; esac
    }
    # `gh pr create` branch (B6): one repo per case at $PR, on feat/p with an
    # empty commit, `.claude/` ignored, its runs under $PRO.
    PR_CMD='gh pr create --title "feat: probe" --body-file b.md'
    pr_repo() {
      PR="$root/pr/$lbl"
      PRO="$PR/.claude/output/apex"
      {
        g init -q -b feat/p "$PR" &&
          printf '%s\n' '.claude/' > "$PR/.gitignore" &&
          g -C "$PR" -c user.name=p -c user.email=p@p -c commit.gpgsign=false commit -q --allow-empty -m probe &&
          mkdir -p "$PRO"
      } || { why="gh pr create fixture could not be built"; return 1; }
    }
    # $1 run id, $2 its tier line, $3 its flags line, $4 its branch, then the
    # run files it holds, each a tally line.
    pr_run() {
      r="$PRO/$1"
      mkdir -p "$r" && printf '%s\n' "# APEX: probe" "Date: 2026-10-25" "$2" "$3" "Branch: $4 (trunk: master)" > "$r/00-context.md"
      shift 4
      for f in "$@"; do printf '%s\n' "$AC_TALLY" > "$r/$f"; done
    }
    # $1 command, $2 tool_response as raw JSON (a plain success when empty or unset).
    pr_in() { ${jq} -cn --arg c "$1" --arg w "$PR" --arg r "''${2-}" '{hook_event_name:"PostToolUse",session_id:"probe",cwd:$w,tool_name:"Bash",tool_input:{command:$c,description:"probe"},tool_response:(if $r == "" then {stdout:"",stderr:"",interrupted:false,isImage:false} else ($r | fromjson) end)}'; }
    # $1 run id the B6 line must name, $2 text it must carry, then texts it must not.
    pr_emits() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      [ -s "$d/$lbl.out" ] || { why="no output: the missing run files were due"; kind=mismatch; return 1; }
      ctx=$(${jq} -r 'select(.hookSpecificOutput.hookEventName == "PostToolUse") | .hookSpecificOutput.additionalContext // ""' "$d/$lbl.out" 2> /dev/null) || ctx=""
      case "$ctx" in "APEX run .claude/output/apex/$1/ is missing: "*". Write them before merging (B6).") ;; *) why="context is not the B6 line for $1: $ctx"; return 1 ;; esac
      must="$2"
      shift 2
      for x in "$@"; do
        case "$ctx" in *"$x"*) why="context carries '$x': $ctx"; kind=mismatch; return 1 ;; esac
      done
      case "$ctx" in *"$must"*) ;; *) why="context lacks '$must': $ctx"; return 1 ;; esac
    }

    # research-model: $1 subagent_type, $2 model (absent when empty or unset).
    rm_in() { ${jq} -cn --arg t "$1" --arg m "''${2-}" '{hook_event_name:"PreToolUse",tool_name:"Agent",session_id:"probe",tool_input:({description:"probe",subagent_type:$t,prompt:"Find the hook wiring."} + (if $m == "" then {} else {model:$m} end))}'; }

    # sandbox-escape-evidence: $1 command, $2 transcript, $3 the flag
    # (true when unset, absent when empty). Transcript lines, in Claude's
    # JSONL shape: se_use $1 tool_use id, $2 assistant message id, $3 tool
    # (Bash when unset); se_res $1 tool_use id, $2 result text; se_user /
    # se_meta a typed prompt / an injected one. se_tx writes them, in order,
    # to $SE/$lbl.jsonl.
    SE="$root/se"
    mkdir -p "$SE"
    se_in() { ${jq} -cn --arg c "$1" --arg t "$2" --arg f "''${3-true}" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_use_id:"toolu_now",session_id:"probe",transcript_path:$t,tool_input:({command:$c} + (if $f == "" then {} else {dangerouslyDisableSandbox:($f == "true")} end))}'; }
    se_use() { ${jq} -cn --arg id "$1" --arg m "$2" --arg n "''${3-Bash}" '{type:"assistant",message:{id:$m,role:"assistant",content:[{type:"tool_use",id:$id,name:$n,input:{command:"x"}}]}}'; }
    se_res() { ${jq} -cn --arg id "$1" --arg t "$2" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$t}]}}'; }
    se_user() { ${jq} -cn --arg t "$1" '{type:"user",message:{role:"user",content:$t}}'; }
    se_meta() { ${jq} -cn --arg t "$1" '{type:"user",isMeta:true,message:{role:"user",content:[{type:"text",text:$t}]}}'; }
    se_tx() { printf '%s\n' "$@" > "$SE/$lbl.jsonl"; }
    # $1 command, $2 body: run against $SE/$lbl.jsonl with the flag set.
    se_run() { run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(se_in "$1" "$SE/$lbl.jsonl")"; }

    # worktree-env-sync: a main checkout $M and its worktree $T under
    # .claude/worktrees/, fresh per label. At M's root, all ignored there:
    # .env and .dev.vars (due in T); .env.local, a symlink to .env;
    # .env.production, which T already has; .env.staging, which T's
    # .gitignore un-ignores; .env.example, tracked in M and dropped from T's
    # index; and sub/.env, nested. Only the first two are due. The four
    # check-ignore lines prove the fixture has the shape the canaries need.
    wes_fixture() {
      wb="$root/wes/$lbl"
      M="$wb/main"
      T="$M/.claude/worktrees/w"
      W="$wb/outside"
      rm -rf "$wb"
      mkdir -p "$M/sub" "$W" "$M/.claude/worktrees" \
        && g init -q -b master "$M" \
        && printf '%s\n' .env '.env.*' .dev.vars .claude/worktrees/ > "$M/.gitignore" \
        && printf 'a\n' > "$M/sub/a.txt" \
        && printf 'E=example\n' > "$M/.env.example" \
        && g -C "$M" add .gitignore sub/a.txt \
        && g -C "$M" add -f .env.example \
        && g -C "$M" -c user.name=p -c user.email=p@p -c commit.gpgsign=false commit -q -m probe \
        && g -C "$M" worktree add -q -b wt "$T" \
        && printf 'SECRET=main\n' > "$M/.env" && chmod 600 "$M/.env" \
        && printf 'D=main\n' > "$M/.dev.vars" && chmod 640 "$M/.dev.vars" \
        && ln -s .env "$M/.env.local" \
        && printf 'P=main\n' > "$M/.env.production" \
        && printf 'S=main\n' > "$M/.env.staging" \
        && printf 'N=main\n' > "$M/sub/.env" \
        && printf 'P=wt\n' > "$T/.env.production" \
        && printf '%s\n' '!.env.staging' >> "$T/.gitignore" \
        && g -C "$T" rm -q -- .env.example \
        && g -C "$M" check-ignore -q -- .env.staging \
        && ! g -C "$T" check-ignore -q -- .env.staging \
        && ! g -C "$M" check-ignore -q -- .env.example \
        && g -C "$T" check-ignore -q -- .env.example \
        || { why="worktree-env-sync fixture could not be built"; return 1; }
    }
    # $1 event, $2 cwd: the SessionStart input, or EnterWorktree's PostToolUse.
    wes_in() { ${jq} -cn --arg e "$1" --arg c "$2" 'if $e == "PostToolUse" then {hook_event_name:$e,session_id:"probe",cwd:$c,tool_name:"EnterWorktree",tool_input:{name:"w"},tool_response:{}} else {hook_event_name:$e,session_id:"probe",cwd:$c,source:"startup"} end'; }
    # $1 body, $2 event, $3 cwd.
    wes_run() { run "$lbl" "$1" "$NOREPO" "${pkgs.coreutils}/bin" "$(wes_in "$2" "$3")"; }
    # Nothing in T that was not due: a followed symlink, a tracked file, a
    # file T does not ignore, a nested one, T's own file overwritten, or a
    # temp file left behind.
    wes_clean() {
      kind=pwned
      if [ -e "$T/.env.local" ] || [ -L "$T/.env.local" ]; then why="the .env.local symlink was followed: a copy of its target sits in the worktree"; return 1; fi
      if [ -e "$T/.env.example" ] || [ -L "$T/.env.example" ]; then why=".env.example copied: the main checkout tracks it"; return 1; fi
      if [ -e "$T/.env.staging" ] || [ -L "$T/.env.staging" ]; then why=".env.staging copied: the worktree does not ignore it, git would commit it"; return 1; fi
      if [ -e "$T/sub/.env" ] || [ -L "$T/sub/.env" ]; then why="sub/.env copied: only the root is synced"; return 1; fi
      [ "$(${pkgs.coreutils}/bin/cat "$T/.env.production" 2> /dev/null)" = P=wt ] || { why="the worktree's own .env.production was overwritten"; return 1; }
      for t in "$T"/.worktree-env-sync.*; do
        if [ -e "$t" ] || [ -L "$t" ]; then why="temp file left in the worktree: $t"; return 1; fi
      done
      kind=""
    }
    # $1 name, $2 mode: copied from M, byte for byte, as a regular file.
    wes_copied() {
      if [ ! -f "$T/$1" ] || [ -L "$T/$1" ] || ! ${pkgs.diffutils}/bin/cmp -s "$M/$1" "$T/$1"; then
        why="$1 not copied into the worktree as a regular file equal to the main checkout's"; kind=mismatch; return 1
      fi
      wm=$(${pkgs.coreutils}/bin/stat -c %a "$T/$1")
      [ "$wm" = "$2" ] || { why="$1 copied with mode $wm, expected $2"; return 1; }
    }
    # $1 event, $2 the names copied: the one context line, under that event.
    wes_context() {
      ev=$(${jq} -r '.hookSpecificOutput.hookEventName // ""' "$d/$lbl.out" 2> /dev/null) || ev=""
      ctx=$(${jq} -r '.hookSpecificOutput.additionalContext // ""' "$d/$lbl.out" 2> /dev/null) || ctx=""
      [ "$ev" = "$1" ] || { why="hookEventName '$ev', expected '$1'"; return 1; }
      [ "$ctx" = "worktree-env-sync: copied $2 from the main checkout" ] || { why="context '$ctx', expected 'worktree-env-sync: copied $2 from the main checkout'"; return 1; }
    }
    # $1 event: .env and .dev.vars synced, nothing else, and said.
    is_synced() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      wes_clean || return 1
      wes_copied .env 600 || return 1
      wes_copied .dev.vars 640 || return 1
      wes_context "$1" ".env, .dev.vars"
    }
    is_silent() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      [ ! -s "$d/$lbl.out" ] || { why="stdout not empty, expected silence"; return 1; }
    }
    wes_snap() { (cd "$T" && ${pkgs.coreutils}/bin/ls -Ali --time-style=+%s && ${pkgs.coreutils}/bin/cat .env .dev.vars) 2>&1; }

    # session-state: a fresh fixture HOME $H per label, the state dir $SF in
    # it. ss_run $1 body, $2 ABDUCO_SESSION (absent from the env when empty),
    # $3 stdin, $4 one more VAR=value (none when unset). The env is cleared as
    # in run(): a variable reaches the hook only when the case passes it.
    ss_home() { H="$root/ss/$lbl"; SF="$H/.claude/session-state"; rm -rf "$H"; mkdir -p "$H"; }
    ss_run() {
      printf '%s' "$3" > "$d/$lbl.in"
      rc=0
      if [ -n "$2" ]; then ab="ABDUCO_SESSION=$2"; else ab="SS_PROBE=1"; fi
      (cd "$NOREPO" && env -i HOME="$H" PATH="${pkgs.coreutils}/bin" "$ab" "''${4-SS_PROBE2=1}" ${pkgs.coreutils}/bin/timeout "$tmo" ${pkgs.nodejs_22}/bin/node "$1") \
        < "$d/$lbl.in" > "$d/$lbl.out" 2> "$d/$lbl.err" || rc=$?
    }
    # $1 event, $2 session id (s1 when unset), $3 the prompt, the message or
    # the SessionStart source, by event. Field names per the hooks reference.
    ss_in() { ${jq} -cn --arg e "$1" --arg s "''${2-s1}" --arg x "''${3-}" '{hook_event_name:$e,session_id:$s,cwd:"/probe/cwd",transcript_path:"/probe/t.jsonl",permission_mode:"default"} + (if $e == "UserPromptSubmit" then {prompt:$x} elif $e == "Notification" then {message:$x,title:"Permission needed",notification_type:"permission_prompt"} elif $e == "SessionStart" then {source:(if $x == "" then "startup" else $x end)} elif $e == "SessionEnd" then {reason:"other"} else {stop_hook_active:false,last_assistant_message:"done"} end)'; }
    # $1 body, $2 event, $3 session id, $4 payload text: as t1, silent.
    ss_step() { ss_run "$1" t1 "$(ss_in "$2" "$3" "$4")"; is_silent || { why="$2: $why"; return 1; }; }
    # $1 state, $2 event, $3 intent, $4 notice, $5 session id (s1 when
    # unset): t1.json a regular 0600 file in a 0700 dir, holding exactly
    # these, and no temp file beside it.
    is_state() {
      f="$SF/t1.json"
      if [ ! -f "$f" ] || [ -L "$f" ]; then why="no regular file $f, expected state '$1'"; kind=mismatch; return 1; fi
      ${jq} -e --arg st "$1" --arg ev "$2" --arg it "$3" --arg no "$4" --arg sid "''${5-s1}" \
        '.name == "t1" and .state == $st and .event == $ev and .intent == $it and .notice == $no and .sessionId == $sid and .cwd == "/probe/cwd" and .transcriptPath == "/probe/t.jsonl" and (.updatedAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$"))' \
        "$f" > /dev/null 2>&1 || { why="state file $(${pkgs.coreutils}/bin/cat "$f"), expected state '$1' event '$2' intent '$3' notice '$4'"; kind=mismatch; return 1; }
      [ "$(${pkgs.coreutils}/bin/stat -c %a "$SF")" = 700 ] || { why="state dir mode $(${pkgs.coreutils}/bin/stat -c %a "$SF"), expected 700"; return 1; }
      [ "$(${pkgs.coreutils}/bin/stat -c %a "$f")" = 600 ] || { why="state file mode $(${pkgs.coreutils}/bin/stat -c %a "$f"), expected 600"; return 1; }
      ss_notmp
    }
    ss_notmp() {
      for t in "$SF"/.*.tmp; do
        if [ -e "$t" ] || [ -L "$t" ]; then why="temp file left in the state dir: $t"; return 1; fi
      done
    }
    # Nothing at all under $H: no dir, no file. A write is the PWNED kind.
    ss_nothing() {
      left=$(${pkgs.findutils}/bin/find "$H" -mindepth 1 2> /dev/null)
      [ -z "$left" ] || { why="written where nothing was due: $left"; kind=pwned; return 1; }
    }

    # apex-pr-record: per label, a repo $AR (cwd $AR/sub) holding its runs
    # under $ARO, and a stub gh in $AB that appends its argv to $AB/gh.log
    # and prints $AB/view.json, or fails as on an HTTP error while $AB/fail
    # exists. PATH = the stub, then git.
    APR_LINE='#42 https://github.com/o/r/pull/42 — merged (abcdef12) — recorded by apex-pr-record'
    APR_JSON='--json number,url,state,headRefName,mergeCommit'
    apr_fixture() {
      ab="$root/apr/$lbl"
      AR="$ab/repo"
      ARO="$AR/.claude/output/apex"
      AB="$ab/bin"
      rm -rf "$ab"
      mkdir -p "$AB" "$AR/sub" \
        && g init -q -b master "$AR" \
        && mkdir -p "$ARO" \
        && printf '%s\n' '#!${pkgs.bash}/bin/bash' \
          'here="''${0%/*}"' \
          'printf "%s\n" "$*" >> "$here/gh.log"' \
          'if [ -e "$here/fail" ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi' \
          'exec ${pkgs.coreutils}/bin/cat "$here/view.json"' > "$AB/gh" \
        && chmod +x "$AB/gh" \
        || { why="apex-pr-record fixture could not be built"; return 1; }
    }
    # $1 state, $2 head branch: what `gh pr view` says of PR 42.
    apr_view() { ${jq} -cn --arg s "$1" --arg h "$2" '{number:42,url:"https://github.com/o/r/pull/42",state:$s,headRefName:$h,mergeCommit:{oid:"abcdef1234567890"}}' > "$AB/view.json"; }
    # $1 run id, then the lines of its 00-context.md.
    apr_ctx() { r="$ARO/$1"; shift; mkdir -p "$r" && printf '%s\n' "$@" > "$r/00-context.md"; }
    # $1 command, $2 tool_response as raw JSON (a plain success when empty
    # or unset), $3 event (PostToolUse when unset).
    apr_in() { ${jq} -cn --arg c "$1" --arg w "$AR/sub" --arg r "''${2-}" --arg e "''${3-PostToolUse}" '{hook_event_name:$e,session_id:"probe",cwd:$w,tool_name:"Bash",tool_input:{command:$c,description:"probe"},tool_response:(if $r == "" then {stdout:"",stderr:"",interrupted:false,isImage:false} else ($r | fromjson) end)}'; }
    # $1 body, $2 stdin.
    apr_run() { run "$lbl" "$1" "$AR/sub" "$AB:$GITBIN" "$2"; }
    # Exit 0, stdout empty; stderr too, unless $1 = noisy (gh's failure line).
    apr_quiet() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.out" ] || { why="stdout not empty, expected silence"; return 1; }
      [ "''${1-}" = noisy ] || [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
    }
    # $1 run id: pr.md there, exactly the recorded line.
    apr_has() {
      f="$ARO/$1/pr.md"
      [ -f "$f" ] || { why="no $1/pr.md, expected one"; kind=mismatch; return 1; }
      got=$(${pkgs.coreutils}/bin/cat "$f")
      [ "$got" = "$APR_LINE" ] || { why="$1/pr.md is '$got', expected '$APR_LINE'"; return 1; }
    }
    # Run ids where no pr.md was due: one there is the PWNED kind.
    apr_none() {
      for r in "$@"; do
        if [ -e "$ARO/$r/pr.md" ] || [ -L "$ARO/$r/pr.md" ]; then why="pr.md written in $r, where none was due"; kind=pwned; return 1; fi
      done
    }
    # $1 the one argv line gh was called with, empty for never called.
    apr_gh() {
      got=$(${pkgs.coreutils}/bin/cat "$AB/gh.log" 2> /dev/null) || got=""
      [ "$got" = "$1" ] || { why="gh called with '$got', expected '$1'"; kind=mismatch; return 1; }
    }

    # worktree-in-use: a repo $WR with a commit and four linked worktrees
    # under $WH/wts — held (a real sleep has it as cwd), free, held2 and hel
    # (a string prefix of held, held by nobody) — a symlink $WH/link-held to
    # held, $WH/plain/sub, no checkout, the cwd of a second real sleep, and
    # $WR/sub/held, a plain directory sharing held's name.
    # All paths physical: lsof reports getcwd's path. The sleeps outlive
    # every case and canary, and are reaped on exit, the stdenv exit handler
    # chained.
    WH="$root/wh"
    mkdir -p "$WH/wts" "$WH/plain/sub"
    WH=$(cd "$WH" && pwd -P)
    WR="$WH/repo"
    {
      g init -q -b master "$WR" &&
        g -C "$WR" -c user.name=p -c user.email=p@p -c commit.gpgsign=false commit -q --allow-empty -m probe &&
        g -C "$WR" worktree add -q -b wt-held "$WH/wts/held" &&
        g -C "$WR" worktree add -q -b wt-free "$WH/wts/free" &&
        g -C "$WR" worktree add -q -b wt-held2 "$WH/wts/held2" &&
        g -C "$WR" worktree add -q -b wt-hel "$WH/wts/hel" &&
        ln -s "$WH/wts/held" "$WH/link-held" &&
        mkdir -p "$WR/sub/held" &&
        [ -f "$WH/wts/held/.git" ] && [ ! -e "$WH/plain/.git" ] && [ ! -e "$WH/.git" ]
    } || { echo "hook-wiring: worktree-in-use fixture could not be built" >&2; exit 1; }
    (cd "$WH/wts/held" && exec ${pkgs.coreutils}/bin/sleep 3600) < /dev/null > /dev/null 2>&1 &
    WH_HOLD=$!
    (cd "$WH/plain/sub" && exec ${pkgs.coreutils}/bin/sleep 3600) < /dev/null > /dev/null 2>&1 &
    WH_PLAIN=$!
    wh_reap() { kill "$WH_HOLD" "$WH_PLAIN" 2> /dev/null || true; }
    trap 'wh_rc=$?; set +e; wh_reap; if declare -F exitHandler > /dev/null; then (exit "$wh_rc"); exitHandler; fi; exit "$wh_rc"' EXIT
    # The other processes lsof would list, in `lsof -FpcRn` order (p, R, c,
    # f, n): launchd at /, then the two sleeps.
    printf 'p%s\nR%s\nc%s\nfcwd\nn%s\n' \
      1 0 launchd / \
      "$WH_HOLD" "$$" sleep "$WH/wts/held" \
      "$WH_PLAIN" "$$" sleep "$WH/plain/sub" > "$WH/records"
    # The fake lsof logs its argv, then prints itself (the hook's lsof
    # child), the hook ($PPID, with the parent and cwd wh_run's shell
    # recorded), that shell, and the records above. The hung one never
    # answers; $WH/no-such-lsof does not exist. badexit-lsof prints the same
    # listing and exits 2; noself-lsof leaves out itself and the hook.
    wh_lsof_head=('#!${pkgs.bash}/bin/bash' \
      "here='$WH'" \
      'printf "%s\n" "$*" >> "$here/lsof.log"')
    wh_lsof_self=('pp=""; pc=""' \
      'while IFS= read -r l; do case "$l" in p*) pp=''${l#p} ;; n*) pc=''${l#n} ;; esac; done < "$here/parent.rec"' \
      'printf "p%s\nR%s\nclsof\nfcwd\nn%s\n" "$$" "$PPID" "$(pwd -P)"' \
      'printf "p%s\nR%s\ncnode\nfcwd\nn%s\n" "$PPID" "$pp" "$pc"')
    printf '%s\n' "''${wh_lsof_head[@]}" "''${wh_lsof_self[@]}" \
      'exec ${pkgs.coreutils}/bin/cat "$here/parent.rec" "$here/records"' > "$WH/lsof"
    printf '%s\n' "''${wh_lsof_head[@]}" "''${wh_lsof_self[@]}" \
      '${pkgs.coreutils}/bin/cat "$here/parent.rec" "$here/records"' 'exit 2' > "$WH/badexit-lsof"
    printf '%s\n' "''${wh_lsof_head[@]}" \
      'exec ${pkgs.coreutils}/bin/cat "$here/parent.rec" "$here/records"' > "$WH/noself-lsof"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exec ${pkgs.coreutils}/bin/sleep 30' > "$WH/hang-lsof"
    chmod +x "$WH/lsof" "$WH/hang-lsof" "$WH/badexit-lsof" "$WH/noself-lsof"
    WH_LIT=${lib.escapeShellArg whLsofLit}
    # $1 body, $2 lsof path. Writes the copy with the lsof literal, found
    # exactly once, repointed at $2; leaves its path in $wb.
    wh_body() {
      wsrc=$(cat "$1") || { why="cannot read $1"; return 1; }
      wrest=''${wsrc#*"$WH_LIT"}
      [ "$wrest" != "$wsrc" ] || { why="lsof literal missing: $WH_LIT is not in $1"; return 1; }
      case "$wrest" in *"$WH_LIT"*) why="lsof literal occurs more than once in $1"; return 1 ;; esac
      wrep="const LSOF = \"$2\";"
      wb="$d/$lbl.wh.js"
      printf '%s\n' "''${wsrc/"$WH_LIT"/"$wrep"}" > "$wb"
    }
    # $1 command, $2 session cwd.
    wh_in() { ${jq} -cn --arg c "$1" --arg w "$2" '{hook_event_name:"PreToolUse",session_id:"probe",cwd:$w,tool_name:"Bash",tool_input:{command:$c,description:"probe"}}'; }
    # $1 body, $2 cwd, $3 stdin. As run(), but the hook's direct parent is a
    # bash that first writes its own lsof record to $WH/parent.rec (and so
    # never execs node: `exit` is its last command), its command recorded as
    # $wh_pcmd (bash unless a case says otherwise). The lsof log is cleared.
    wh_pcmd=bash
    wh_run() {
      printf '%s' "$3" > "$d/$lbl.in"
      rc=0
      : > "$WH/lsof.log"
      (cd "$2" && env -i GIT_CONFIG_NOSYSTEM=1 HOME="$TMPDIR" PATH="$GITBIN:${pkgs.coreutils}/bin" ${pkgs.coreutils}/bin/timeout "$tmo" \
        ${pkgs.bash}/bin/bash -c 'printf "p%s\nR%s\nc%s\nfcwd\nn%s\n" "$$" "$PPID" "$4" "$(pwd -P)" > "$1" && "$2" "$3"; exit $?' \
        wh-parent "$WH/parent.rec" ${pkgs.nodejs_22}/bin/node "$1" "$wh_pcmd") \
        < "$d/$lbl.in" > "$d/$lbl.out" 2> "$d/$lbl.err" || rc=$?
    }
    # $1 body, $2 lsof path, $3 cwd (the session's too), $4 command: the
    # copy, run.
    wh_case() {
      wh_body "$1" "$2" || return 1
      wh_run "$wb" "$3" "$(wh_in "$4" "$3")"
    }
    # Denied for the held worktree: the sleep named by pid and command.
    wh_held() {
      is_deny "pid $WH_HOLD" || return 1
      case "$reason" in
        *"pid $WH_HOLD"[!0-9]* | *"pid $WH_HOLD") ;;
        *) why="denied, but the reason names no 'pid $WH_HOLD' (only a longer pid): $reason"; return 1 ;;
      esac
      case "$reason" in
        *sleep*) ;;
        *) why="denied, but the reason does not name the holder's command 'sleep': $reason"; return 1 ;;
      esac
    }
    # An allow after a matched shape must come from a liveness read.
    wh_called() {
      [ -s "$WH/lsof.log" ] || { why="allowed without ever calling lsof: a matched shape must read liveness before it allows"; return 1; }
    }

    # $1 label, $2 body, $3 cwd, $4 PATH, $5 stdin, $6 = a python body's
    # mode, --hook by default. Leaves the exit status in $rc.
    # $tmo is the host's timeout for the hook under test (probe_case sets it);
    # 124 is `timeout` killing it, which the host reads as no decision.
    # The interpreter goes by the body's name: a mutant's ends with its hook's.
    # No set +e/-e toggling: this runs both inside and outside `if`.
    run() {
      printf '%s' "$5" > "$d/$1.in"
      rc=0
      a=""
      case "$2" in
        *.sh) i=${pkgs.bash}/bin/bash ;;
        *.py) i=${pkgs.python3}/bin/python3; a="''${6:---hook}" ;;
        *) i=${pkgs.nodejs_22}/bin/node ;;
      esac
      (cd "$3" && env -i GIT_CONFIG_NOSYSTEM=1 HOME="$TMPDIR" PATH="$4" ${pkgs.coreutils}/bin/timeout "$tmo" "$i" ''${a:+-I} "$2" ''${a:+"$a"}) \
        < "$d/$1.in" > "$d/$1.out" 2> "$d/$1.err" || rc=$?
    }

    # A failure sets $kind only when it is the one a canary exists to cause:
    # "mismatch" (no deny where one was due: no output, decision none or
    # allow, or killed at the host timeout) or "pwned". A crash, a non-zero
    # exit, stray stderr or a wrong reason leave it empty: a mutant that
    # breaks the hook some other way has not shown that the branch bites.
    is_deny() {
      [ "$rc" -ne 124 ] || { why="killed at the host's $tmo s timeout: decision 'none', expected deny"; kind=mismatch; return 1; }
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0 — Claude honours the deny JSON on exit 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      [ -s "$d/$lbl.out" ] || { why="no output: decision 'none', expected deny"; kind=mismatch; return 1; }
      verdict=$(${jq} -r '.hookSpecificOutput.permissionDecision // "none"' "$d/$lbl.out" 2> /dev/null) || verdict="unparseable"
      case "$verdict" in
        deny) ;;
        none | allow) why="decision '$verdict', expected deny"; kind=mismatch; return 1 ;;
        *) why="decision '$verdict', expected deny"; return 1 ;;
      esac
      reason=$(${jq} -r '.hookSpecificOutput.permissionDecisionReason // ""' "$d/$lbl.out")
      case "$reason" in
        *"$1"*) ;;
        *) why="denied, but the reason lacks '$1': $reason"; return 1 ;;
      esac
    }

    # A clean deny where an allow was due is the other mismatch: the one the
    # over-block canaries (M12, M13) exist to cause.
    is_allow() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
      if [ -s "$d/$lbl.out" ]; then
        why="stdout not empty — an allow is silence"
        verdict=$(${jq} -r '.hookSpecificOutput.permissionDecision // "none"' "$d/$lbl.out" 2> /dev/null) || verdict="unparseable"
        [ "$verdict" != deny ] || { why="decision 'deny', expected allow"; kind=mismatch; }
        return 1
      fi
    }

    # $1 body. Writes the copy with the baked vault literal, found exactly
    # once, pointed at $VAULT; leaves its path in $vb.
    vaultify() {
      vsrc=$(cat "$1") || { why="cannot read $1"; return 1; }
      vrest=''${vsrc#*"$VAULT_LIT"}
      [ "$vrest" != "$vsrc" ] || { why="vault literal missing: $VAULT_LIT is not in $1"; return 1; }
      case "$vrest" in *"$VAULT_LIT"*) why="vault literal occurs more than once in $1"; return 1 ;; esac
      vrep="\"$VAULT\""
      vb="$d/$lbl.vault.js"
      printf '%s\n' "''${vsrc/"$VAULT_LIT"/"$vrep"}" > "$vb"
    }

    # $1 case, $2 body under test, $3 tag. 0 passed, 1 failed ($why), 2 no such case.
    probe_case() {
      lbl="$3.$1"
      why=""
      kind=""
      case "$1" in
        pm-*) tmo=${hostTimeout "protect-main.js"} ;;
        bb-*) tmo=${hostTimeout "block-main-bash.js"} ;;
        cb-*) tmo=${hostTimeout "correction-budget.js"} ;;
        cg-*) tmo=${hostTimeout "correction-grant.js"} ;;
        rm-*) tmo=${hostTimeout "research-model.js"} ;;
        le-*) tmo=${hostTimeout "lone-excluded-bash.js"} ;;
        se-*) tmo=${hostTimeout "sandbox-escape-evidence.js"} ;;
        wes-*) tmo=${hostTimeout "worktree-env-sync.sh"} ;;
        ss-*) tmo=${hostTimeout "session-state.js"} ;;
        apr-*) tmo=${hostTimeout "apex-pr-record.js"} ;;
        wh-*) tmo=${hostTimeout "worktree-in-use.js"} ;;
        iw-*) tmo=${hostTimeout "instagram-watch.js"} ;;
        ac-* | pr-*) tmo=${hostTimeout "apex-metrics-probe.py"} ;;
        *) tmo=${hostTimeout "format-typescript.js"} ;;
      esac
      case "$1" in
        pm-master-inrepo)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(pm_in "$MASTER/a.ts")"; is_deny "BLOCKED: on master." ;;
        pm-master-malformed)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$malformed"; is_deny "not valid JSON" ;;
        pm-master-nogit)
          run "$lbl" "$2" "$MASTER" "$root/emptybin" "$(pm_in "$MASTER/a.ts")"; is_deny "git is not on PATH" ;;
        pm-norepo-nogit)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(pm_in "$NOREPO/a.ts")"; is_deny "git is not on PATH" ;;
        pm-master-hung)
          run "$lbl" "$2" "$MASTER" "$root/hangbin" "$(pm_in "$MASTER/a.ts")"; is_deny "did not answer in time" ;;
        pm-master-symlink-newfile)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(pm_in "$LINK/new.ts")"; is_deny "BLOCKED: on master." ;;
        pm-master-case)
          # The same directory in other case, which only a case-insensitive
          # filesystem resolves. Skipped, and said, where it does not exist.
          if [ ! -e "$root/MASTER" ]; then
            echo "hook-wiring: $1 skipped — $root/MASTER does not exist, this filesystem is case-sensitive"
            return 0
          fi
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(pm_in "$root/MASTER/a.ts")"; is_deny "BLOCKED: on master." ;;
        pm-master-dangling-link)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(pm_in "$NOREPO/dangling")"; is_deny "could not be resolved" ;;
        pm-master-outside)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(pm_in "$NOREPO/a.ts")"; is_allow ;;
        pm-feat)
          run "$lbl" "$2" "$FEAT" "$GITBIN" "$(pm_in "$FEAT/a.ts")"; is_allow ;;
        pm-norepo)
          run "$lbl" "$2" "$NOREPO" "$GITBIN" "$(pm_in "$NOREPO/a.ts")"; is_allow ;;
        pm-detached)
          run "$lbl" "$2" "$DETACHED" "$GITBIN" "$(pm_in "$DETACHED/a.ts")"; is_allow ;;
        # Run 61, B4: the branch of the repo the FILE is in, whatever the cwd.
        pm-cross-feat-cwd)
          run "$lbl" "$2" "$FEAT" "$GITBIN" "$(pm_in "$MASTER/a.ts")"; is_deny "BLOCKED: on master." ;;
        pm-cross-norepo-cwd)
          run "$lbl" "$2" "$NOREPO" "$GITBIN" "$(pm_in "$MASTER/a.ts")"; is_deny "BLOCKED: on master." ;;
        pm-feat-to-norepo)
          run "$lbl" "$2" "$FEAT" "$GITBIN" "$(pm_in "$NOREPO/a.ts")"; is_allow ;;
        # B5: NotebookEdit names its target in notebook_path.
        pm-notebook-master)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(pm_nb_in "$MASTER/n.ipynb")"; is_deny "BLOCKED: on master." ;;
        pm-notebook-outside)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(pm_nb_in "$NOREPO/n.ipynb")"; is_allow ;;
        # The vault on main is exempt, from its own cwd and from another.
        pm-vault-main)
          vaultify "$2" || return 1
          run "$lbl" "$vb" "$VAULT" "$GITBIN" "$(pm_in "$VAULT/n.md")"; is_allow ;;
        pm-vault-crosscwd)
          vaultify "$2" || return 1
          run "$lbl" "$vb" "$FEAT" "$GITBIN" "$(pm_in "$VAULT/n.md")"; is_allow ;;
        # APEX run state on master: ignored and untracked under the file's own
        # repo's .claude/output/apex/ is allowed, from any cwd.
        pm-apex-new)
          run "$lbl" "$2" "$APEXR" "$GITBIN" "$(pm_in "$APEXO/new-run/00-context.md")"; is_allow ;;
        pm-apex-existing)
          run "$lbl" "$2" "$APEXR" "$GITBIN" "$(pm_in "$APEXO/old/00-context.md")"; is_allow ;;
        pm-apex-crosscwd)
          run "$lbl" "$2" "$FEAT" "$GITBIN" "$(pm_in "$APEXO/old/00-context.md")"; is_allow ;;
        pm-apex-norepo-cwd)
          run "$lbl" "$2" "$NOREPO" "$GITBIN" "$(pm_in "$APEXO/new-run/00-context.md")"; is_allow ;;
        pm-apex-case)
          # As pm-master-case: skipped, and said, where it does not exist.
          if [ ! -e "$APEXR/.CLAUDE" ]; then
            echo "hook-wiring: $1 skipped — $APEXR/.CLAUDE does not exist, this filesystem is case-sensitive"
            return 0
          fi
          run "$lbl" "$2" "$APEXR" "$GITBIN" "$(pm_in "$APEXR/.CLAUDE/output/apex/old/00-context.md")"; is_allow ;;
        # Everything else there, or like it elsewhere, stays denied.
        pm-apex-tracked)
          run "$lbl" "$2" "$APEXR" "$GITBIN" "$(pm_in "$APEXO/forced/00-context.md")"; is_deny "BLOCKED: on master." ;;
        pm-apex-ignored-outside)
          run "$lbl" "$2" "$APEXR" "$GITBIN" "$(pm_in "$APEXR/.claude/settings.local.json")"; is_deny "BLOCKED: on master." ;;
        pm-apex-unignored)
          run "$lbl" "$2" "$UNIG" "$GITBIN" "$(pm_in "$UNIG/.claude/output/apex/r/00-context.md")"; is_deny "BLOCKED: on master." ;;
        pm-apex-symlink)
          run "$lbl" "$2" "$APEXR" "$GITBIN" "$(pm_in "$APEXO/lnk/new.ts")"; is_deny "BLOCKED: on master." ;;
        pm-apex-hardlink)
          run "$lbl" "$2" "$APEXR" "$GITBIN" "$(pm_in "$APEXO/hl/00-context.md")"; is_deny "BLOCKED: on master." ;;
        pm-apex-nested)
          run "$lbl" "$2" "$APEXR" "$GITBIN" "$(pm_in "$APEXO/nest/x.md")"; is_deny "BLOCKED: on master." ;;
        # The file's repo has a core.fsmonitor script that leaves a marker:
        # never run. The bare check-ignore first proves it fires on an index
        # read here. One repo per body, so no run sees another's marker.
        pm-apex-fsmonitor-pwned)
          A="$root/apexfs.$lbl"
          {
            g init -q -b master "$A" &&
              printf '%s\n' '.claude/' > "$A/.gitignore" &&
              g -C "$A" add .gitignore &&
              g -C "$A" -c user.name=p -c user.email=p@p -c commit.gpgsign=false commit -q -m probe &&
              printf '#!%s\n%s %s\n' ${pkgs.bash}/bin/bash ${pkgs.coreutils}/bin/touch "$A.ran" > "$A.fsmonitor" &&
              chmod 755 "$A.fsmonitor" &&
              g -C "$A" config core.fsmonitor "$A.fsmonitor" &&
              { g -C "$A" check-ignore -q -- .claude/output/apex/r/00-context.md 2> /dev/null; [ -e "$A.ran" ]; } &&
              rm -f "$A.ran"
          } || { why="fsmonitor fixture: the script did not run on a bare check-ignore"; return 1; }
          run "$lbl" "$2" "$FEAT" "$GITBIN" "$(pm_in "$A/.claude/output/apex/r/00-context.md")"
          if [ -e "$A.ran" ]; then why="the repo's core.fsmonitor command ran"; kind=pwned; return 1; fi
          is_allow ;;
        # A sibling of apex/ whose name only starts with it is not run state.
        pm-apex-sibling)
          run "$lbl" "$2" "$APEXR" "$GITBIN" "$(pm_in "$APEXR/.claude/output/apexfoo/x.md")"; is_deny "BLOCKED: on master." ;;
        bb-master-commit)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(bb_in "git commit -m x")"; is_deny "BLOCKED: on master." ;;
        bb-master-malformed)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$malformed"; is_deny "not valid JSON" ;;
        bb-master-nogit)
          run "$lbl" "$2" "$MASTER" "$root/emptybin" "$(bb_in "git commit -m x")"; is_deny "git is not on PATH" ;;
        bb-master-hung)
          run "$lbl" "$2" "$MASTER" "$root/hangbin" "$(bb_in "git commit -m x")"; is_deny "did not answer in time" ;;
        bb-master-nl-flood)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(bb_flood)"; is_deny "BLOCKED: on master." ;;
        bb-master-C-flood)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(bb_cflood)"; is_deny "BLOCKED: on master." ;;
        bb-master-gl-bound)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(bb_glbound)"; is_deny "too large to scan" ;;
        bb-master-status)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(bb_in "git status")"; is_allow ;;
        # No remote is no exemption (run 61, B3): the non-vault control.
        bb-local-commit)
          run "$lbl" "$2" "$LOCAL" "$GITBIN" "$(bb_in "git commit -m x")"; is_deny "BLOCKED: on master." ;;
        bb-feat-commit)
          run "$lbl" "$2" "$FEAT" "$GITBIN" "$(bb_in "git commit -m x")"; is_allow ;;
        bb-norepo-commit)
          run "$lbl" "$2" "$NOREPO" "$GITBIN" "$(bb_in "git commit -m x")"; is_allow ;;
        bb-detached-commit)
          run "$lbl" "$2" "$DETACHED" "$GITBIN" "$(bb_in "git commit -m x")"; is_allow ;;
        bb-cd-nonexistent)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(bb_in "cd /nonexistent57 && git commit -m x")"; is_deny "BLOCKED: on master." ;;
        bb-cd-broken)
          run "$lbl" "$2" "$FEAT" "$root/badbin" "$(bb_in "cd $MASTER && git commit -m x")"; is_deny "in the directory the command targets" ;;
        # Run 61, B2: pull merges into the current branch.
        bb-pull-master)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(bb_in "git pull origin feat/x")"; is_deny "BLOCKED: on master." ;;
        # B1: every target is read, not the first `-C` or `cd` alone.
        bb-cross-C-after-c)
          run "$lbl" "$2" "$FEAT" "$GITBIN" "$(bb_in "git -c k=v -C $MASTER commit -m x")"; is_deny "BLOCKED: on master." ;;
        bb-second-cd)
          run "$lbl" "$2" "$FEAT" "$GITBIN" "$(bb_in "cd $FEAT && true; cd $MASTER && git commit -m x")"; is_deny "BLOCKED: on master." ;;
        bb-gitdir-env)
          run "$lbl" "$2" "$FEAT" "$GITBIN" "$(bb_in "GIT_DIR=$MASTER/.git git commit -m x")"; is_deny "BLOCKED: on master." ;;
        bb-leading-cd-feat)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(bb_in "cd $FEAT && git commit -m x")"; is_allow ;;
        bb-vault-commit)
          vaultify "$2" || return 1
          run "$lbl" "$vb" "$VAULT" "$GITBIN" "$(bb_in "git commit -m x")"; is_allow ;;
        fmt-inject)
          rm -f "$TMPDIR/PWNED" "$root/fakebin/prettier.log" "$root/fakebin/config.log" "$root/fakebin/no-config"
          f="$root/fmt/\$(touch $TMPDIR/PWNED).ts"
          # The file must exist: the hook skips anything but a regular file.
          # Its name holds slashes, so its parents are directories.
          mkdir -p "$(dirname "$f")"
          : > "$f"
          run "$lbl" "$2" "$root" "$root/fakebin:${pkgs.coreutils}/bin" "$(fmt_in "$f")"
          [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
          [ ! -e "$TMPDIR/PWNED" ] || { why="the file path ran as shell: its \$(touch …) created PWNED"; kind=pwned; return 1; }
          grep -Fxq -- "$f" "$root/fakebin/prettier.log" 2> /dev/null \
            || { why="prettier never received the path verbatim — a probe that never reaches prettier cannot see an injection"; return 1; }
          ;;
        # Run 64: the project has no prettier config, so the file is left
        # alone — exit 0, silent, and `--write` never called.
        fmt-no-config)
          rm -f "$root/fakebin/prettier.log" "$root/fakebin/config.log"
          f="$root/fmt/no-config.ts"
          : > "$f"
          : > "$root/fakebin/no-config"
          run "$lbl" "$2" "$root" "$root/fakebin:${pkgs.coreutils}/bin" "$(fmt_in "$f")"
          rm -f "$root/fakebin/no-config"
          [ ! -s "$root/fakebin/prettier.log" ] || { why="prettier --write ran on a file whose project has no prettier config"; kind=mismatch; return 1; }
          grep -Fxq -- "$f" "$root/fakebin/config.log" 2> /dev/null \
            || { why="the hook never asked prettier for a config — a probe that never reaches the gate cannot see it skip"; return 1; }
          is_allow ;;
        # Run 62: two marked rounds per run, the third denied.
        cb-round3-deny)
          cb_reset
          cb_round "$2" 62-x 1 || return 1
          cb_round "$2" 62-x 2 || return 1
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." 62-x)"; is_deny "budget de correction épuisé (2/2)" ;;
        # Two spawned rounds, then a third sent to a live agent: same budget.
        cb-sendmessage-round3-deny)
          cb_reset
          cb_round "$2" 62-x 1 || return 1
          cb_round "$2" 62-x 2 || return 1
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_msg "Apply the fixes in 06-resolve.md." 62-x)"; is_deny "budget de correction épuisé (2/2)" ;;
        cb-nomarker-deny)
          cb_reset
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md.")"; is_deny "has no APEX-CORRECTION-ROUND line" ;;
        # A new run is a new counter: 62-x spent, 63-y still allowed.
        cb-other-run-allow)
          cb_reset
          cb_round "$2" 62-x 1 || return 1
          cb_round "$2" 62-x 2 || return 1
          cb_round "$2" 63-y 1 ;;
        cb-plain-allow)
          cb_reset
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Summarize the README.")"; is_allow ;;
        cb-none-allow)
          cb_reset
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Check what the last correction round changed." none)"; is_allow ;;
        # A marked round whose count cannot be recorded fails closed. Skipped,
        # and said, where mode 555 does not stop the builder (root).
        cb-state-unwritable-deny)
          cb_reset
          mkdir -p "$CBSTATE"
          chmod 555 "$CBSTATE"
          if (: > "$CBSTATE/.probe") 2> /dev/null; then
            rm -f "$CBSTATE/.probe"
            echo "hook-wiring: $1 skipped — $CBSTATE stays writable at mode 555"
            return 0
          fi
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." 62-x)"; is_deny "BLOCKED: budget state unwritable" ;;
        # Correction rounds on opus: any other model, absent included, is
        # denied before a slot is claimed; SendMessage carries no model.
        cb-sonnet-deny)
          cb_reset
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." 62-x sonnet)"; is_deny 'model "sonnet"; re-spawn it with model: "opus"' || return 1
          [ ! -e "$CBSTATE/62-x.round1" ] || { why="denied, but a round was counted"; return 1; } ;;
        cb-nomodel-deny)
          cb_reset
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." 62-x "")"; is_deny 'model absent; re-spawn it with model: "opus"' || return 1
          [ ! -e "$CBSTATE/62-x.round1" ] || { why="denied, but a round was counted"; return 1; } ;;
        cb-opus-allow)
          cb_reset
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." 62-x opus)"; is_allow || return 1
          [ -e "$CBSTATE/62-x.round1" ] || { why="allowed, but no round was counted"; return 1; } ;;
        cb-sendmessage-nomodel-allow)
          cb_reset
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_msg "Apply the fixes in 06-resolve.md." 62-x)"; is_allow ;;
        # A user grant is one round more: the third allowed, the fourth denied.
        cb-grant-round3-allow)
          cb_reset
          cb_round "$2" 62-x 1 || return 1
          cb_round "$2" 62-x 2 || return 1
          : > "$CBSTATE/62-x.grant1"
          cb_round "$2" 62-x 3 || return 1
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." 62-x)"; is_deny "budget de correction épuisé (3/3)" ;;
        # A scheduled prompt is re-submitted as a user turn: the grant line
        # in it is denied, any other scheduled prompt passes uncounted.
        cb-cron-token-deny)
          cb_reset
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_sched CronCreate "$(printf 'check CI\napex: +1 tour')")"; is_deny "BLOCKED: a scheduled prompt may not carry the correction-grant token" || return 1
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_sched ScheduleWakeup " APEX : +1 Tour ")"; is_deny "only the user types it" ;;
        cb-cron-plain-allow)
          cb_reset
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_sched CronCreate "Apply the fixes in 06-resolve.md.")"; is_allow || return 1
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_sched ScheduleWakeup "The hook says: type apex: +1 tour alone on a line.")"; is_allow || return 1
          [ ! -e "$CBSTATE" ] || { why="a scheduler call touched the budget state"; return 1; } ;;
        # A run outside the session's repo, named by its absolute run dir:
        # counted by its run-id, the dir stamped for correction-grant.js.
        cb-abs-run-allow)
          cb_reset
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." "$CBOTHER")"; is_allow || return 1
          ${jq} -e --arg d "$CBOTHER" '.dir == $d' "$CBSTATE/64-z.round1" > /dev/null 2>&1 \
            || { why="allowed, but 64-z.round1 is missing or does not stamp dir $CBOTHER"; return 1; } ;;
        cb-abs-run-cap-deny)
          cb_reset
          cb_round "$2" "$CBOTHER" 1 || return 1
          cb_round "$2" "$CBOTHER" 2 || return 1
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." "$CBOTHER")"; is_deny "budget de correction épuisé (2/2) pour le run 64-z" ;;
        # An absolute dir outside an apex output dir, through `..`, or
        # missing: denied, nothing counted.
        cb-abs-run-bad-deny)
          cb_reset
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." "$root/cbother/notapex/64-z")"; is_deny "nor an absolute <repo>/.claude/output/apex/<run-id> path" || return 1
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." "$root/cbother/.claude/output/apex/../apex/64-z")"; is_deny "nor an absolute <repo>/.claude/output/apex/<run-id> path" || return 1
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." "$root/cbother/.claude/output/apex/65-none")"; is_deny "65-none: run dir not found" || return 1
          [ ! -e "$CBSTATE" ] || { why="denied, but the budget state was touched"; return 1; } ;;
        # An existing run dir spelled unnormalized (trailing `/`, `//`):
        # denied, nothing counted.
        cb-abs-run-unnormalized-deny)
          cb_reset
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." "$CBOTHER/")"; is_deny "nor an absolute <repo>/.claude/output/apex/<run-id> path" || return 1
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cb_in "Apply the fixes in 06-resolve.md." "$root/cbother//.claude/output/apex/64-z")"; is_deny "nor an absolute <repo>/.claude/output/apex/<run-id> path" || return 1
          [ ! -e "$CBSTATE" ] || { why="denied, but the budget state was touched"; return 1; } ;;
        # correction-grant: only the user's token, as the first non-empty
        # line, only for the project's live run once spent.
        cg-token-grants)
          cb_reset
          cb_spend 62-x 2
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "$(printf '\n  \napex: +1 tour\nthanks')")"; is_granted 62-x 1 3 ;;
        cg-no-token)
          cb_reset
          cb_spend 62-x 2
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "continue")"; is_not_granted 0 "" ;;
        cg-inline-token-ignored)
          cb_reset
          cb_spend 62-x 2
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in 'The hook says: type `apex: +1 tour` alone on a line.')"; is_not_granted 0 "" ;;
        # An unused grant is no spent budget, nor is a run with a round left.
        cg-not-exhausted)
          cb_reset
          cb_spend 62-x 2 1700000100
          : > "$CBSTATE/62-x.grant1"
          cb_spend 63-y 1 1700000000
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "apex: +1 tour")"; is_not_granted 1 "nothing was granted" ;;
        cg-newest-exhausted)
          cb_reset
          cb_spend 62-x 2 1700000000
          cb_spend 63-y 2 1700000100
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in " APEX : +1  Tour ")"; is_granted 63-y 1 3 || return 1
          [ ! -e "$CBSTATE/62-x.grant1" ] || { why="the older spent run was granted too"; return 1; } ;;
        cg-stacks)
          cb_reset
          cb_spend 62-x 2
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "apex: +1 tour")"; is_granted 62-x 1 3 || return 1
          cb_spend 62-x 3
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "apex: +1 tour")"; is_granted 62-x 2 4 ;;
        cg-subagent-ignored)
          cb_reset
          cb_spend 62-x 2
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "apex: +1 tour" '"agent-1"')"; is_not_granted 0 "" ;;
        cg-agentid-nonstring-ignored)
          cb_reset
          cb_spend 62-x 2
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "apex: +1 tour" 0)"; is_not_granted 0 "" ;;
        cg-malformed-quiet)
          cb_reset
          cb_spend 62-x 2
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$malformed"; is_not_granted 0 "" ;;
        # Spent, but its run dir is not under the prompt's cwd: another project.
        cg-no-rundir-told)
          cb_reset
          cb_spend 64-z 2
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "apex: +1 tour")"; is_not_granted 0 "nothing was granted" ;;
        cg-double-token-once)
          cb_reset
          cb_spend 62-x 2
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "$(printf 'apex: +1 tour\napex: +1 tour')")"; is_granted 62-x 1 3 || return 1
          [ "$(grants)" -eq 1 ] || { why="$(grants) grant files for one prompt, expected 1"; kind=mismatch; return 1; } ;;
        # A grant file is never rewritten: unused, it leaves the run unspent;
        # spent again, the next grant is a new file.
        cg-existing-grant-kept)
          cb_reset
          cb_spend 62-x 2
          printf 'keep\n' > "$CBSTATE/62-x.grant1"
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "apex: +1 tour")"; is_not_granted 1 "nothing was granted" || return 1
          [ "$(cat "$CBSTATE/62-x.grant1")" = keep ] || { why="62-x.grant1 rewritten"; return 1; }
          cb_spend 62-x 3
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "apex: +1 tour")"; is_granted 62-x 2 4 || return 1
          [ "$(cat "$CBSTATE/62-x.grant1")" = keep ] || { why="62-x.grant1 rewritten"; return 1; }
          [ "$(grants)" -eq 2 ] || { why="$(grants) grant files, expected 2"; kind=mismatch; return 1; } ;;
        # Harness-wrapped text reaches UserPromptSubmit without agent_id: a
        # hand-back, wrapped below or above the token, grants nothing.
        cg-wrapped-ignored)
          cb_reset
          cb_spend 62-x 2
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "$(printf 'Another Claude session sent a message:\n<agent-message from="x">\napex: +1 tour')")"; is_not_granted 0 "" || return 1
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "$(printf 'apex: +1 tour\n<agent-message from="x">\ndone\n</agent-message>')")"; is_not_granted 0 "" ;;
        cg-notification-ignored)
          cb_reset
          cb_spend 62-x 2
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "$(printf '<task-notification>\n<task-id>a1</task-id>\napex: +1 tour\n</task-notification>')")"; is_not_granted 0 "" ;;
        cg-token-not-first-ignored)
          cb_reset
          cb_spend 62-x 2
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "$(printf 'ok\napex: +1 tour')")"; is_not_granted 0 "" ;;
        # The live run is the newest; an older spent run is not granted.
        cg-newest-not-spent)
          cb_reset
          cb_spend 62-x 2 1700000000
          cb_spend 63-y 1 1700000100
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "apex: +1 tour")"; is_not_granted 0 "nothing was granted" ;;
        # A spent run outside the prompt's repo, its rounds stamped by this
        # session: granted, the context naming its dir as the marker.
        cg-cross-repo-grants)
          cb_reset
          cb_stamp 64-z 2 "$CBOTHER" probe
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "apex: +1 tour")"; is_granted 64-z 1 3 || return 1
          grep -Fq -- "APEX-CORRECTION-ROUND: $CBOTHER;" "$d/$lbl.out" || { why="granted, but the context does not name the marker $CBOTHER"; return 1; } ;;
        cg-cross-repo-other-session)
          cb_reset
          cb_stamp 64-z 2 "$CBOTHER" other
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "apex: +1 tour")"; is_not_granted 0 "nothing was granted" ;;
        cg-cross-repo-bad-dir)
          cb_reset
          cb_stamp 64-z 2 "$root/cbother/notapex/64-z" probe
          run "$lbl" "$2" "$CBREPO" "$root/emptybin" "$(cg_in "apex: +1 tour")"; is_not_granted 0 "nothing was granted" ;;
        # Run 66: research agents on haiku, the model named explicitly.
        rm-explore-sonnet-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(rm_in Explore sonnet)"; is_deny 'model "sonnet"' ;;
        rm-navigator-opus-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(rm_in codebase-navigator opus)"; is_deny 'model "opus"' ;;
        rm-navigator-nomodel-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(rm_in codebase-navigator)"; is_deny 'model absent; re-spawn it with model: "haiku"' ;;
        rm-explore-haiku-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(rm_in Explore haiku)"; is_allow ;;
        rm-plan-opus-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(rm_in Plan opus)"; is_allow ;;
        rm-malformed-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$malformed"; is_allow ;;
        # A deny-worthy object padded past the 4 MiB cap, then a malformed
        # tail: the input is never read whole, so it must be let through.
        rm-oversize-allow)
          { rm_in Explore sonnet; ${pkgs.coreutils}/bin/head -c 4400000 /dev/zero | ${pkgs.coreutils}/bin/tr '\0' ' '; printf '}garbage'; } > "$d/$lbl.big"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(${pkgs.coreutils}/bin/cat "$d/$lbl.big")"; is_allow ;;
        # Sandbox-shape run: an excluded command leaves the sandbox only
        # alone, or chained with other lone excluded commands.
        le-cd-chain-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'cd /x && git push')"; is_deny "next to another command" ;;
        le-git-C-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'git -C /x push')"; is_deny "next to another command" ;;
        le-git-c-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'git -c a=b push')"; is_deny "next to another command" ;;
        le-add-commit-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'git add . && git commit -m x')"; is_deny "next to another command" ;;
        le-pipe-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'gh pr list | head')"; is_deny "next to another command" ;;
        le-redir-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'gh api x > out.json')"; is_deny "file redirection" ;;
        le-subst-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'git commit -m "$(cat m)"')"; is_deny "command substitution" ;;
        le-echo-subst-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'echo $(gh auth token)')"; is_deny "command substitution" ;;
        le-heredoc-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in "$(printf "git commit -F - <<'EOF'\nfix: x\nEOF")")"; is_deny "heredoc" ;;
        le-env-prefix-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'GIT_X=1 git push')"; is_deny "next to another command" ;;
        le-timeout-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'timeout 30 gh pr list')"; is_deny "next to another command" ;;
        # A wrapper option's value read as the command hid the target.
        le-wrapper-opt-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'timeout -s KILL 30 gh pr list')"; is_deny "next to another command" ;;
        # An unquoted heredoc body expands $(...): real newlines.
        le-heredoc-body-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in "$(printf '%s\n%s\n%s' 'cat <<EOF' '$(gh auth token)' 'EOF')")"; is_deny "command substitution" ;;
        le-dispatch-cd-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'cd /x && claude-dispatch fix-a "fix the typo"')"; is_deny "next to another command" ;;
        # The retired claude-bg (daemon off, #299) is no excluded command:
        # never a clean link in a chain, silent behind cd &&.
        le-retired-bg-push-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'claude-bg status && git push')"; is_deny "next to another command" ;;
        le-retired-bg-cd-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'cd /x && claude-bg logs 4b04dbe6')"; is_allow ;;
        le-dispatch-env-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'CLAUDE_CONFIG_DIR=/x claude-dispatch fix-a "fix the typo"')"; is_deny "next to another command" ;;
        le-dispatch-abs-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in '/etc/profiles/per-user/alx/bin/claude-dispatch fix-a "fix the typo"')"; is_deny "next to another command" ;;
        # pnpm localdb:start/stop are exact entries: any prefix, pipe,
        # argument or `pnpm run` keeps the call sandboxed.
        le-pnpm-cd-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'cd /x && pnpm localdb:start')"; is_deny "next to another command" ;;
        le-pnpm-pipe-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm localdb:start 2>&1 | tail -8')"; is_deny "next to another command" ;;
        le-pnpm-args-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm localdb:stop --rm')"; is_deny "with arguments after it" ;;
        le-pnpm-run-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm run localdb:start')"; is_deny "next to another command" ;;
        # pnpm run deploy / deploy:prod are exact entries too: a prefix, a
        # file redirection, a pipe or an argument keeps the call sandboxed.
        le-deploy-cd-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'cd ~/projects/Preliz && pnpm run deploy')"; is_deny "next to another command" ;;
        le-deploy-redir-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm run deploy < /dev/null > $TMPDIR/x')"; is_deny "file redirection" ;;
        le-deploy-prod-pipe-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm run deploy:prod | tail')"; is_deny "next to another command" ;;
        le-deploy-prod-args-deny)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm run deploy:prod --force')"; is_deny "with arguments after it" ;;
        le-command-v-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'command -v gh')"; is_allow ;;
        le-push-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'git push')"; is_allow ;;
        le-push-u-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'git push -u origin feat/x')"; is_allow ;;
        le-commit-F-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'git commit -F msg.txt')"; is_allow ;;
        le-body-file-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'gh pr create --body-file b.md')"; is_allow ;;
        le-json-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'gh pr view 12 --json state')"; is_allow ;;
        le-dup-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'git fetch 2>&1')"; is_allow ;;
        le-grep-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'grep -rn "git push" .')"; is_allow ;;
        le-rg-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in "rg 'gh pr' file")"; is_allow ;;
        le-quoted-msg-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'git commit -m "fix gh thing; git push"')"; is_allow ;;
        le-status-diff-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'git status && git diff')"; is_allow ;;
        le-chain-targets-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'git commit -F m.txt && git push')"; is_allow ;;
        le-dispatch-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'claude-dispatch fix-a "fix the typo"')"; is_allow ;;
        le-pnpm-start-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm localdb:start')"; is_allow ;;
        le-pnpm-stop-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm localdb:stop')"; is_allow ;;
        le-pnpm-chain-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm localdb:stop && pnpm localdb:start')"; is_allow ;;
        # Other pnpm calls are lexed (prefilter) but no target: silent.
        le-pnpm-install-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm install')"; is_allow ;;
        le-pnpm-pipe-other-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm typecheck | tail')"; is_allow ;;
        le-deploy-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm run deploy')"; is_allow ;;
        le-deploy-prod-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm run deploy:prod')"; is_allow ;;
        le-deploy-dup-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm run deploy 2>&1')"; is_allow ;;
        # No `run`: no excluded entry matches, so not a target: silent.
        le-deploy-norun-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(bb_in 'pnpm deploy:prod')"; is_allow ;;
        le-malformed-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$malformed"; is_allow ;;
        # Sandbox-escape run: the flag needs sandbox evidence in the newest
        # Bash batch, a user ask, or an allowlisted command.
        se-preempt-deny)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run 'pnpm build' "$2"; is_deny "Run this command sandboxed first" ;;
        se-stale-deny)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'mkdir: x: Operation not permitted')" "$(se_use u2 m2)" "$(se_res u2 'built')"
          se_run 'pnpm build' "$2"; is_deny "Run this command sandboxed first" ;;
        se-sysprompt-deny)
          se_tx "$(se_user 'fix the build')" "$(se_meta 'retry ONCE outside the sandbox, with dangerouslyDisableSandbox: true')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run 'pnpm build' "$2"; is_deny "Run this command sandboxed first" ;;
        se-quoted-sep-deny)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run "echo 'x; docker'" "$2"; is_deny "Run this command sandboxed first" ;;
        se-user-token-deny)
          se_tx "$(se_user 'do not use dangerouslyDisableSandbox')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run 'pnpm build' "$2"; is_deny "Run this command sandboxed first" ;;
        se-curl-proxy-deny)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'home 000')"
          se_run 'curl -s https://example.com/' "$2"; is_deny "Run this command sandboxed first" ;;
        se-pnpm-deploy-builtin-deny)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run 'pnpm deploy out' "$2"; is_deny "Run this command sandboxed first" ;;
        se-deployer-deny)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run 'pnpm run deployer' "$2"; is_deny "Run this command sandboxed first" ;;
        se-eperm-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'mkdir: x: Operation not permitted')"
          se_run 'pnpm build' "$2"; is_allow ;;
        se-violations-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'x <sandbox_violations>deny file-write</sandbox_violations>')"
          se_run 'pnpm build' "$2"; is_allow ;;
        se-mkdir-ref-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 "fatal: cannot lock ref 'refs/heads/y': unable to create directory for .git/refs/heads/y")"
          se_run 'git -C /x checkout -b y' "$2"; is_allow ;;
        se-dns-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'Error: getaddrinfo ENOTFOUND ep-x.eu-central-1.aws.neon.tech')"
          se_run 'pnpm test:db' "$2"; is_allow ;;
        se-batch-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_use u2 m1)" "$(se_res u1 'Error: EPERM: open x')" "$(se_res u2 'built')"
          se_run 'pnpm build' "$2"; is_allow ;;
        se-nonbash-skip-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'mkdir: x: Operation not permitted')" "$(se_use u2 m2 Read)" "$(se_res u2 'file text')"
          se_run 'pnpm build' "$2"; is_allow ;;
        se-allowlist-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run 'cd /x && git branch -D old' "$2"; is_allow ;;
        se-allowlist-verify-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run 'apex-verify-external --acs a.txt' "$2"; is_allow ;;
        se-noproxy-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'home 000')"
          se_run "curl -s --noproxy '*' -o /dev/null -w '%{http_code}' https://example.com/" "$2"; is_allow ;;
        se-deploy-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run 'pnpm run deploy < /dev/null > deploy.log 2>&1' "$2"; is_allow ;;
        se-wrangler-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run 'wrangler deploy --config build/server/wrangler-preprod.json' "$2"; is_allow ;;
        se-wrangler-exec-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run 'pnpm exec wrangler whoami' "$2"; is_allow ;;
        se-wrangler-npx-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run 'npx wrangler tail' "$2"; is_allow ;;
        se-noflag-allow)
          se_tx "$(se_user 'fix the build')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(se_in 'pnpm build' "$SE/$lbl.jsonl" "")"; is_allow ;;
        se-user-asked-allow)
          se_tx "$(se_user 'lance-le hors sandbox')" "$(se_use u1 m1)" "$(se_res u1 'built')"
          se_run 'pnpm build' "$2"; is_allow ;;
        se-missing-transcript-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(se_in 'pnpm build' "$SE/absent.jsonl")"; is_allow ;;
        se-malformed-allow)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$malformed"; is_allow ;;
        # worktree-env-sync run: the hook reads the cwd the event carries, a
        # worktree subdirectory at SessionStart, the worktree root after
        # EnterWorktree; the process itself starts outside any repo.
        wes-sessionstart-copy)
          wes_fixture || return 1
          wes_run "$2" SessionStart "$T/sub"; is_synced SessionStart ;;
        wes-enterworktree-copy)
          wes_fixture || return 1
          wes_run "$2" PostToolUse "$T"; is_synced PostToolUse ;;
        # A second session in the same worktree: everything due is there.
        wes-rerun-silent)
          wes_fixture || return 1
          wes_run "$2" SessionStart "$T"; is_synced SessionStart || return 1
          wsnap=$(wes_snap)
          wes_run "$2" SessionStart "$T"; is_silent || return 1
          [ "$(wes_snap)" = "$wsnap" ] || { why="the second run changed the worktree"; kind=pwned; return 1; } ;;
        # The main checkout's own session is no worktree.
        wes-main-silent)
          wes_fixture || return 1
          wes_run "$2" SessionStart "$M"; is_silent || return 1
          if [ -e "$T/.env" ] || [ -L "$T/.env" ]; then why="a session in the main checkout wrote into its worktree"; kind=pwned; return 1; fi ;;
        wes-norepo-silent)
          wes_run "$2" SessionStart "$NOREPO"; is_silent ;;
        wes-malformed-silent)
          run "$lbl" "$2" "$NOREPO" "${pkgs.coreutils}/bin" "$malformed"; is_silent ;;
        # T/.env a dangling symlink out of the worktree: never written
        # through, never replaced; .dev.vars still copied, and alone named.
        wes-dangling-dest)
          wes_fixture || return 1
          ln -s "$W/pwned" "$T/.env" || { why="cannot plant the dangling symlink"; return 1; }
          wes_run "$2" SessionStart "$T"
          [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
          [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
          if [ -e "$W/pwned" ] || [ -L "$W/pwned" ]; then why="written through the worktree's dangling .env symlink"; kind=pwned; return 1; fi
          [ -L "$T/.env" ] && [ "$(${pkgs.coreutils}/bin/readlink "$T/.env")" = "$W/pwned" ] || { why="the worktree's .env symlink was replaced"; kind=pwned; return 1; }
          wes_clean || return 1
          wes_copied .dev.vars 640 || return 1
          wes_context SessionStart ".dev.vars" ;;
        # M's core.fsmonitor names a script that leaves a marker: never run.
        # The bare check-ignore first proves it fires on an index read here.
        wes-fsmonitor-pwned)
          wes_fixture || return 1
          printf '#!%s\n%s %s\n' ${pkgs.bash}/bin/bash ${pkgs.coreutils}/bin/touch "$W/fsmonitor-ran" > "$W/fsmonitor" \
            && chmod 755 "$W/fsmonitor" \
            && g -C "$M" config core.fsmonitor "$W/fsmonitor" \
            && { g -C "$M" check-ignore -q -- .env 2> /dev/null; [ -e "$W/fsmonitor-ran" ]; } \
            && rm -f "$W/fsmonitor-ran" \
            || { why="fsmonitor fixture: the script did not run on a bare check-ignore"; return 1; }
          wes_run "$2" SessionStart "$T"
          if [ -e "$W/fsmonitor-ran" ]; then why="the repo's core.fsmonitor command ran"; kind=pwned; return 1; fi
          is_synced SessionStart ;;
        # session-state run: each case starts from an empty fixture HOME.
        ss-prompt-working)
          ss_home
          ss_step "$2" UserPromptSubmit s1 "$(printf 'Fix the\nbuild')" || return 1
          is_state working UserPromptSubmit "Fix the build" "" ;;
        # 600 code points, a newline among them: one line of 500.
        ss-intent-truncated)
          ss_home
          ss_run "$2" t1 "$(${jq} -cn '{hook_event_name:"UserPromptSubmit",session_id:"s1",cwd:"/probe/cwd",transcript_path:"/probe/t.jsonl",prompt:("a\nb" + ("x" * 597))}')"
          is_silent || return 1
          ${jq} -e '(.intent | length) == 500 and (.intent | startswith("a bxx")) and (.intent | test("\n") | not)' "$SF/t1.json" > /dev/null 2>&1 \
            || { why="intent not one line of 500: $(${pkgs.coreutils}/bin/cat "$SF/t1.json" 2> /dev/null)"; kind=mismatch; return 1; } ;;
        ss-stop-waiting)
          ss_home
          ss_step "$2" UserPromptSubmit s1 "Fix the build" || return 1
          ss_step "$2" Stop s1 || return 1
          is_state waiting Stop "Fix the build" "" ;;
        # A notice set, cleared by the next prompt, which leaves the intent.
        ss-notify-end)
          ss_home
          ss_step "$2" UserPromptSubmit s1 "First task" || return 1
          ss_step "$2" Notification s1 "$(printf 'Claude needs\nyour permission')" || return 1
          is_state needs-you Notification "First task" "Claude needs your permission" || return 1
          ss_step "$2" UserPromptSubmit s1 "Second task" || return 1
          is_state working UserPromptSubmit "First task" "" || return 1
          ss_step "$2" SessionEnd s1 || return 1
          is_state done SessionEnd "First task" "" ;;
        # idle at startup; a compaction mid-turn keeps the state it had.
        ss-start-idle)
          ss_home
          ss_step "$2" SessionStart s1 || return 1
          is_state idle SessionStart "" "" || return 1
          ss_step "$2" UserPromptSubmit s1 "Fix the build" || return 1
          ss_step "$2" SessionStart s1 compact || return 1
          is_state working SessionStart "Fix the build" "" ;;
        # Another session id under the same name starts fresh.
        ss-new-session-fresh)
          ss_home
          ss_step "$2" UserPromptSubmit s0 "Old task" || return 1
          ss_step "$2" Notification s0 "Old notice" || return 1
          ss_step "$2" UserPromptSubmit s1 "New task" || return 1
          is_state working UserPromptSubmit "New task" "" s1 ;;
        # No ABDUCO_SESSION: a plain session, nothing written.
        ss-noabduco-silent)
          ss_home
          ss_run "$2" "" "$(ss_in UserPromptSubmit s1 "Fix the build")"; is_silent || return 1
          ss_nothing ;;
        ss-headless-kept)
          ss_home
          ss_step "$2" UserPromptSubmit s1 "Fix the build" || return 1
          ss_run "$2" t1 "$(ss_in SessionStart s2)" CLAUDE_CODE_SESSION_ATTENDED=0; is_silent || return 1
          ss_run "$2" t1 "$(ss_in UserPromptSubmit s2 "You are naming clusters")" CLAUDE_CODE_SESSION_ATTENDED=0; is_silent || return 1
          is_state working UserPromptSubmit "Fix the build" "" s1 || return 1
          ss_home
          ss_run "$2" t1 "$(ss_in UserPromptSubmit s1 "Fix the build")" CLAUDE_CODE_SESSION_ATTENDED=0; is_silent || return 1
          ss_nothing ;;
        ss-attended-writes)
          ss_home
          ss_run "$2" t1 "$(ss_in UserPromptSubmit s1 "Fix the build")" CLAUDE_CODE_SESSION_ATTENDED=1; is_silent || return 1
          is_state working UserPromptSubmit "Fix the build" "" ;;
        ss-badname-silent)
          ss_home
          for bad in ../x -x X1 a/b; do
            ss_run "$2" "$bad" "$(ss_in UserPromptSubmit s1 "Fix the build")"; is_silent || { why="name '$bad': $why"; return 1; }
            ss_nothing || { why="name '$bad': $why"; return 1; }
          done ;;
        ss-malformed-silent)
          ss_home
          ss_run "$2" t1 "$malformed"; is_silent || return 1
          ss_nothing ;;
        # The state dir a symlink out of HOME/.claude: never written through.
        ss-symlink-dir)
          ss_home
          mkdir -p "$H/.claude" "$H/elsewhere" && ln -s "$H/elsewhere" "$SF" || { why="cannot plant the state-dir symlink"; return 1; }
          ss_run "$2" t1 "$(ss_in UserPromptSubmit s1 "Fix the build")"; is_silent || return 1
          left=$(${pkgs.findutils}/bin/find "$H/elsewhere" -mindepth 1)
          [ -z "$left" ] || { why="written through the symlinked state dir: $left"; kind=pwned; return 1; }
          [ -L "$SF" ] || { why="the state-dir symlink was replaced"; kind=pwned; return 1; } ;;
        # The state file a symlink: its target untouched, the link left.
        ss-symlink-file)
          ss_home
          mkdir -p "$SF" "$H/elsewhere" && chmod 700 "$SF" \
            && printf 'keep\n' > "$H/elsewhere/target" \
            && ln -s "$H/elsewhere/target" "$SF/t1.json" \
            || { why="cannot plant the state-file symlink"; return 1; }
          ss_run "$2" t1 "$(ss_in UserPromptSubmit s1 "Fix the build")"; is_silent || return 1
          [ "$(${pkgs.coreutils}/bin/cat "$H/elsewhere/target")" = keep ] || { why="written through the symlinked state file"; kind=pwned; return 1; }
          [ -L "$SF/t1.json" ] || { why="the state-file symlink was replaced"; kind=pwned; return 1; }
          ss_notmp ;;
        # apex-pr-record run: each case its own repo, runs and gh stub. PR 42
        # merged, unless the case says otherwise.
        # The run on the `Branch:` line, not the one that only names it.
        apr-branch-write)
          apr_fixture || return 1
          apr_view MERGED feat/x
          apr_ctx a1 "# APEX: one" "Tier: Standard" "Branch: feat/x (trunk: master c74dd29)"
          apr_ctx a2 "# APEX: follow-up of feat/x" "Tier: Direct"
          apr_run "$2" "$(apr_in "gh pr merge 42 --squash --delete-branch")"
          apr_quiet || return 1
          apr_none a2 || return 1
          apr_gh "pr view 42 $APR_JSON" || return 1
          apr_has a1 ;;
        # No `Branch:` line anywhere: the head named on line 12 counts...
        apr-header-write)
          apr_fixture || return 1
          apr_view MERGED feat/h
          apr_ctx h1 "# APEX: header only" x x x x x x x x x x "Continues feat/h."
          apr_run "$2" "$(apr_in "gh pr merge 42 --squash")"
          apr_quiet || return 1
          apr_has h1 ;;
        # A Direct run: no `Branch:` line, its dir the head's last segment.
        apr-dirname-write)
          apr_fixture || return 1
          apr_view MERGED fix/dead-env
          apr_ctx dead-env "# APEX: drop a dead option" "Tier: Direct"
          apr_ctx env "# APEX: other" "Tier: Direct"
          apr_run "$2" "$(apr_in "gh pr merge 42 --squash --delete-branch")"
          apr_quiet || return 1
          apr_none env || return 1
          apr_has dead-env ;;
        # ...on line 13 it does not.
        apr-header-late-silent)
          apr_fixture || return 1
          apr_view MERGED feat/h
          apr_ctx h1 "# APEX: header only" x x x x x x x x x x x "Continues feat/h."
          apr_run "$2" "$(apr_in "gh pr merge 42 --squash")"
          apr_quiet || return 1
          apr_none h1 || return 1
          apr_gh "pr view 42 $APR_JSON" ;;
        apr-existing-kept)
          apr_fixture || return 1
          apr_view MERGED feat/x
          apr_ctx e1 "# APEX: one" "Branch: feat/x"
          printf 'keep\n' > "$ARO/e1/pr.md"
          apr_run "$2" "$(apr_in "gh pr merge 42 --squash")"
          apr_quiet || return 1
          [ "$(${pkgs.coreutils}/bin/cat "$ARO/e1/pr.md")" = keep ] || { why="the existing pr.md was overwritten"; kind=pwned; return 1; }
          apr_gh "pr view 42 $APR_JSON" ;;
        apr-committxt-silent)
          apr_fixture || return 1
          apr_view MERGED feat/x
          apr_ctx c1 "# APEX: one" "Branch: feat/x (trunk: master c74dd29)"
          printf 'c74dd29\n' > "$ARO/c1/commit.txt"
          apr_run "$2" "$(apr_in "gh pr merge 42 --squash")"
          apr_quiet || return 1
          apr_none c1 || return 1
          apr_gh "pr view 42 $APR_JSON" ;;
        # `--auto`: gh queues the merge and the PR stays OPEN.
        apr-open-silent)
          apr_fixture || return 1
          apr_view OPEN feat/x
          apr_ctx o1 "# APEX: one" "Branch: feat/x (trunk: master c74dd29)"
          apr_run "$2" "$(apr_in "gh pr merge 42 --auto --squash")"
          apr_quiet || return 1
          apr_none o1 || return 1
          apr_gh "pr view 42 $APR_JSON" ;;
        # gh fails: its line on stderr, nothing written.
        apr-ghfail-silent)
          apr_fixture || return 1
          apr_view MERGED feat/x
          : > "$AB/fail"
          apr_ctx g1 "# APEX: one" "Branch: feat/x (trunk: master c74dd29)"
          apr_run "$2" "$(apr_in "gh pr merge 42 --squash")"
          apr_quiet noisy || return 1
          apr_none g1 || return 1
          apr_gh "pr view 42 $APR_JSON" || return 1
          grep -Fq "HTTP 502" "$d/$lbl.err" || { why="gh's failure not on stderr"; return 1; } ;;
        # Not a lone `gh pr merge`: gh never called, nothing written.
        apr-notmerge-silent)
          apr_fixture || return 1
          apr_view MERGED feat/x
          apr_ctx n1 "# APEX: one" "Branch: feat/x (trunk: master c74dd29)"
          for ac in 'gh pr view 42' 'echo gh pr merge 42' 'gh pr merge 42 && echo done' 'gh pr merge 42 | cat' \
            'gh pr merge $(echo 42)' 'gh pr merged 42' "$(printf 'gh pr merge 42\ngit pull')"; do
            apr_run "$2" "$(apr_in "$ac")"
            apr_quiet || { why="'$ac': $why"; return 1; }
            apr_none n1 || { why="'$ac': $why"; return 1; }
            apr_gh "" || { why="'$ac': $why"; return 1; }
          done ;;
        # An interrupted call, and the failure event: nothing.
        apr-toolfailed-silent)
          apr_fixture || return 1
          apr_view MERGED feat/x
          apr_ctx f1 "# APEX: one" "Branch: feat/x (trunk: master c74dd29)"
          apr_run "$2" "$(apr_in "gh pr merge 42 --squash" '{"stdout":"","stderr":"","interrupted":true,"isImage":false}')"
          apr_quiet || return 1
          apr_none f1 || return 1
          apr_run "$2" "$(apr_in "gh pr merge 42 --squash" "" PostToolUseFailure)"
          apr_quiet || return 1
          apr_none f1 || return 1
          apr_gh "" ;;
        apr-malformed-silent)
          apr_fixture || return 1
          apr_view MERGED feat/x
          apr_ctx m1 "# APEX: one" "Branch: feat/x (trunk: master c74dd29)"
          apr_run "$2" "$malformed"
          apr_quiet || return 1
          apr_none m1 || return 1
          apr_gh "" ;;
        # feat/x merged: a run on feat/x-2, by its `Branch:` line or by a
        # header naming it, is not that run.
        apr-prefix-nomatch)
          apr_fixture || return 1
          apr_view MERGED feat/x
          apr_ctx p1 "# APEX: next" "Branch: feat/x-2 (trunk: master c74dd29)"
          apr_ctx p2 "# APEX: feat/x-2 follow-up" "Tier: Direct"
          apr_run "$2" "$(apr_in "gh pr merge 42 --squash")"
          apr_quiet || return 1
          apr_none p1 p2 || return 1
          apr_gh "pr view 42 $APR_JSON" ;;
        # A run on another branch that names the head in its header.
        apr-otherbranch-silent)
          apr_fixture || return 1
          apr_view MERGED feat/x
          apr_ctx o1 "# APEX: after feat/x" "Branch: fix/y (trunk: master c74dd29)"
          apr_run "$2" "$(apr_in "gh pr merge 42 --squash")"
          apr_quiet || return 1
          apr_none o1 || return 1
          apr_gh "pr view 42 $APR_JSON" ;;
        apr-multi-write)
          apr_fixture || return 1
          apr_view MERGED feat/m
          apr_ctx m1 "# APEX: one" "Branch: feat/m"
          apr_ctx m2 "# APEX: two" "Branch: feat/m (trunk: master c74dd29)"
          apr_run "$2" "$(apr_in "gh pr merge 42 --squash")"
          apr_quiet || return 1
          apr_has m1 || return 1
          apr_has m2 ;;
        # Values of -b, --subject= and -R skipped, -R passed on: PR 42.
        apr-selector-args)
          apr_fixture || return 1
          apr_view MERGED feat/s
          apr_ctx s1 "# APEX: one" "Branch: feat/s"
          apr_run "$2" "$(apr_in "gh pr merge --squash -b 'x y' --subject=s -R o/r 42 --delete-branch")"
          apr_quiet || return 1
          apr_gh "pr view 42 -R o/r $APR_JSON" || return 1
          apr_has s1 ;;
        # No selector: gh resolves the current branch.
        apr-noselector-write)
          apr_fixture || return 1
          apr_view MERGED feat/s
          apr_ctx s1 "# APEX: one" "Branch: feat/s"
          apr_run "$2" "$(apr_in "gh pr merge --squash")"
          apr_quiet || return 1
          apr_gh "pr view $APR_JSON" || return 1
          apr_has s1 ;;
        # worktree-in-use: denied while the sleep has wts/held as cwd, however
        # the target is spelled.
        wh-remove-held)
          wh_case "$2" "$WH/lsof" "$WR" "git worktree remove $WH/wts/held"; wh_held ;;
        # Relative to the -C dir, not to the cwd.
        wh-remove-C-force-held)
          wh_case "$2" "$WH/lsof" "$NOREPO" "git -C $WR worktree remove --force ../wts/held"; wh_held ;;
        # A bare name, resolved by `git worktree list --porcelain` suffix.
        wh-remove-suffix-held)
          wh_case "$2" "$WH/lsof" "$WR" "git worktree remove held"; wh_held ;;
        wh-remove-symlink-held)
          wh_case "$2" "$WH/lsof" "$WR" "git worktree remove --force $WH/link-held"; wh_held ;;
        wh-rm-held)
          wh_case "$2" "$WH/lsof" "$WR" "rm -rf $WH/wts/held"; wh_held ;;
        # The parent of the worktree: its .git sits between the target and the cwd.
        wh-rm-parent-held)
          wh_case "$2" "$WH/lsof" "$WR" "rm -rf $WH/wts"; wh_held ;;
        wh-rm-glob-held)
          wh_case "$2" "$WH/lsof" "$WR" "rm -rf $WH/wts/held*"; wh_held ;;
        # The incident's shape: cd into the main checkout, remove, drop the branch.
        wh-incident-chain)
          wh_case "$2" "$WH/lsof" "$NOREPO" "cd $WR && git worktree remove --force ../wts/held && git branch -D wt-held"; wh_held ;;
        # A matched shape on a FREE worktree with no liveness read: fail closed.
        wh-lsof-missing-deny)
          wh_case "$2" "$WH/no-such-lsof" "$WR" "git worktree remove $WH/wts/free"; is_deny "lsof" ;;
        wh-lsof-hung-deny)
          wh_case "$2" "$WH/hang-lsof" "$WR" "git worktree remove $WH/wts/free"; is_deny "lsof" ;;
        # Positive control: shape matched, lsof read, own pid present, nobody holds it.
        wh-remove-free)
          wh_case "$2" "$WH/lsof" "$WR" "git worktree remove $WH/wts/free"; is_allow || return 1; wh_called ;;
        wh-prune)
          wh_case "$2" "$WH/lsof" "$WR" "git worktree prune"; is_allow ;;
        # The sleep holds plain/sub, but no .git sits between plain and it.
        wh-rm-plain-held)
          wh_case "$2" "$WH/lsof" "$WR" "rm -rf $WH/plain"; is_allow ;;
        # wts/hel is a string prefix of the held wts/held, not its ancestor.
        wh-sibling)
          wh_case "$2" "$WH/lsof" "$WR" "git worktree remove --force $WH/wts/hel"; is_allow || return 1; wh_called ;;
        # Inside held2 only the hook, its lsof child and its direct parent
        # shell (bash, from wh_run) have it as cwd: none is a holder.
        wh-self-cwd)
          wh_case "$2" "$WH/lsof" "$WH/wts/held2" "git worktree remove --force $WH/wts/held2"; is_allow || return 1; wh_called ;;
        wh-unrelated)
          wh_case "$2" "$WH/lsof" "$WR" "ls $WH/wts/held && git status"; is_allow ;;
        # A target the hook cannot resolve: a net, not a barrier.
        wh-var)
          wh_case "$2" "$WH/lsof" "$WR" "git worktree remove --force \$WT && rm -rf \$WT"; is_allow ;;
        wh-malformed)
          wh_body "$2" "$WH/lsof" || return 1
          wh_run "$wb" "$WR" "$malformed"; is_allow ;;
        # No shape (a listing, a non-recursive rm): allowed before any lsof.
        wh-nomatch-lsof-missing)
          wh_case "$2" "$WH/no-such-lsof" "$WR" "git worktree list && rm -f $WH/wts/held"; is_allow ;;
        # Unquoted braces expand, as bash and zsh do, before the rm reads them.
        wh-brace-held)
          wh_case "$2" "$WH/lsof" "$WR" "rm -rf $WH/wts/{held,free}"; wh_held ;;
        # The shell globs a remove target too: hel? is held.
        wh-remove-glob-held)
          wh_case "$2" "$WH/lsof" "$WR" "git worktree remove --force $WH/wts/hel?"; wh_held ;;
        # git looks `held` up as a worktree name BEFORE as the plain sub/held.
        wh-suffix-over-plain-dir)
          wh_case "$2" "$WH/lsof" "$WR/sub" "git worktree remove --force held"; wh_held ;;
        # `env -C` runs git from the main checkout: ../wts/held from there.
        wh-env-C-held)
          wh_case "$2" "$WH/lsof" "$NOREPO" "env -C $WR git worktree remove --force ../wts/held"; wh_held ;;
        # $PWD is where the cd left the shell, not the session cwd.
        wh-pwd-held)
          wh_case "$2" "$WH/lsof" "$WR" "cd $WH/wts && rm -rf \$PWD/held"; wh_held ;;
        # The direct parent is no shell (a Claude session, node) and sits in
        # held2: it is a holder, named by its pid.
        wh-self-nonshell-parent)
          wh_pcmd=node
          wh_case "$2" "$WH/lsof" "$WH/wts/held2" "git worktree remove --force $WH/wts/held2"
          wh_pcmd=bash
          wpp=""
          while IFS= read -r l; do case "$l" in p*) wpp=''${l#p} ;; esac; done < "$WH/parent.rec"
          [ -n "$wpp" ] || { why="no parent record written"; return 1; }
          is_deny "pid $wpp node" ;;
        # A listing that does not show the hook itself saw too little.
        wh-lsof-noself-deny)
          wh_case "$2" "$WH/noself-lsof" "$WR" "git worktree remove $WH/wts/free"; is_deny "own process" ;;
        # Same listing as lsof, exit status 2.
        wh-lsof-badexit-deny)
          wh_case "$2" "$WH/badexit-lsof" "$WR" "git worktree remove $WH/wts/free"; is_deny "lsof exited 2" ;;
        # instagram-watch: a post/reel/tv link asks for the watch skill, once,
        # with its query dropped; anything else is silence, never exit 2.
        iw-reel-emits)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(iw_in "regarde ça https://www.instagram.com/reel/Derra61CUhb/ t'en penses quoi ?")"; iw_emits "https://www.instagram.com/reel/Derra61CUhb/" ;;
        iw-post-query-emits)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(iw_in "instagram.com/p/ABC_def-1/?igsh=MWx0&utm_source=ig_web_copy_link")"; iw_emits "https://instagram.com/p/ABC_def-1/" "igsh" ;;
        iw-user-reel-emits)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(iw_in "https://www.instagram.com/some.user/reel/C0de_9/")"; iw_emits "https://www.instagram.com/some.user/reel/C0de_9/" ;;
        # A profile or explore page is no video.
        iw-mention-silent)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(iw_in "un ami m'a parlé d'instagram.com/explore et de https://www.instagram.com/alx_profile/")"; iw_silent ;;
        iw-other-url-silent)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(iw_in "https://www.youtube.com/watch?v=x et https://notinstagram.com/reel/abc")"; iw_silent ;;
        # A harness-wrapped turn quoting a reel is not the user pasting it.
        iw-wrapped-silent)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(iw_in "$(printf '<task-notification>\n<result>https://www.instagram.com/reel/Derra61CUhb/</result>\n</task-notification>')")"; iw_silent ;;
        iw-subagent-silent)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(iw_in "https://www.instagram.com/reel/Derra61CUhb/" '"agent-1"')"; iw_silent ;;
        iw-malformed-silent)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" '{"hook_event_name":"UserPromptSubmit","prompt":"https://www.instagram.com/reel/Derra61CUhb/'; iw_silent ;;
        iw-no-prompt-silent)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" '{"hook_event_name":"UserPromptSubmit"}'; iw_silent ;;
        # apex-metrics-probe --hook: a Write or Edit of a run's 02-acs.md lists
        # the ACs with no command and no lecture/deferred marker, count first,
        # capped; anything else is silence, exit 0. --self-test exits 0.
        ac-prose-emits)
          f="$ACO/$lbl/02-acs.md"; ac_put "$f" "$AC_CMD" "$AC_PROSE" "$AC_LECT" "$AC_DEF" "$AC_DOCS"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_emits 1 "$AC_PROSE" "AC5:" "AC13" "AC20" "AC-docs" ;;
        ac-edit-emits)
          f="$ACO/$lbl/02-acs.md"; ac_put "$f" "$AC_PROSE"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Edit "$f")"; ac_emits 1 "$AC_PROSE" ;;
        # Twelve unproven: ten shown, then the remainder counted.
        ac-cap-emits)
          f="$ACO/$lbl/02-acs.md"; mkdir -p "''${f%/*}"
          for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf 'AC%s prose line with no command.\n' "$i"; done > "$f"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_emits 12 "AC10 prose line with no command. | +2 more" "AC11 prose line" ;;
        # `[lecture]` with no reason exempts nothing.
        ac-bare-lecture-emits)
          f="$ACO/$lbl/02-acs.md"; ac_put "$f" "$AC_CMD" "$AC_BARE"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_emits 1 "AC13 [lecture] the" ;;
        ac-lecture-silent)
          f="$ACO/$lbl/02-acs.md"; ac_put "$f" "$AC_CMD" "$AC_LECT"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        ac-deferred-silent)
          f="$ACO/$lbl/02-acs.md"; ac_put "$f" "$AC_CMD" "$AC_DEF"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        ac-docs-silent)
          f="$ACO/$lbl/02-acs.md"; ac_put "$f" "$AC_CMD" "$AC_DOCS"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        ac-proven-silent)
          f="$ACO/$lbl/02-acs.md"; ac_put "$f" "$AC_CMD" "$AC_CMD2"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        # Another file of a run dir, and a 02-acs.md outside one.
        ac-other-file-silent)
          f="$ACO/$lbl/02-plan.md"; ac_put "$f" "$AC_PROSE"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        ac-outside-run-silent)
          f="$ACR/$lbl/02-acs.md"; ac_put "$f" "$AC_PROSE"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        ac-missing-silent)
          f="$ACO/$lbl/02-acs.md"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        # A 02-acs.md symlink is not followed: its target's text stays out.
        ac-symlink-silent)
          f="$ACO/$lbl/02-acs.md"; ac_put "$ACR/$lbl-target.md" "$AC_PROSE"
          mkdir -p "''${f%/*}" && ln -s "$ACR/$lbl-target.md" "$f" || { why="cannot plant the 02-acs.md symlink"; return 1; }
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        # A traceback is a hook error shown to the user: fail-open is exit 0.
        ac-malformed-silent)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" '{"tool_input":{"file_path":"'
          [ "$rc" -eq 0 ] || { why="exit $rc: fail-open lost"; kind=mismatch; return 1; }
          ac_silent ;;
        ac-self-test)
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "" --self-test; ac_selftest ;;
        # 04-validate.md: a pass that ran with no tally is named, else silence.
        ac-validate-untallied-emits)
          f="$ACO/$lbl/04-validate.md"; ac_put "$f" "PASS"; ac_put "$ACO/$lbl/04-external-verify.json" "$AC_VPASS"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_b5_emits "external" ;;
        ac-validate-tally-silent)
          f="$ACO/$lbl/04-validate.md"; ac_put "$f" "PASS"; ac_put "$ACO/$lbl/04-external-verify.json" "$AC_VPASS"
          ac_put "$ACO/$lbl/04-external-triage.md" "# External triage" "" "$AC_TALLY"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        # The newest verify decides: an older PASS under a BLOCKED is an unrun
        # pass. The BLOCKED name sorts FIRST, so picking by name reads the PASS.
        ac-validate-blocked-silent)
          f="$ACO/$lbl/04-validate.md"; ac_put "$f" "PASS"; ac_put "$ACO/$lbl/04-external-verify.json" "$AC_VPASS"
          ${pkgs.coreutils}/bin/touch -t 200001010000 "$ACO/$lbl/04-external-verify.json" || { why="cannot age the PASS verify"; return 1; }
          ac_put "$ACO/$lbl/03-external-verify.json" "$AC_VBLOCK"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        ac-validate-examine-emits)
          f="$ACO/$lbl/04-validate.md"; ac_put "$f" "PASS"; ac_put "$ACO/$lbl/05-examine.md" "$AC_EXAM"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Edit "$f")"; ac_b5_emits "examine" ;;
        # A 05-examine.md the guards refuse is skipped, not reported untallied.
        ac-validate-examine-link-silent)
          f="$ACO/$lbl/04-validate.md"; ac_put "$f" "PASS"; ac_put "$ACR/$lbl-examine.md" "$AC_TALLY"
          ln -s "$ACR/$lbl-examine.md" "$ACO/$lbl/05-examine.md" || { why="cannot plant the 05-examine.md symlink"; return 1; }
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        # Memory note: a [[link]] that is no sibling's slug is named, with the
        # slug when it is a sibling's file stem; a note missing from MEMORY.md
        # and MEMORY.md links to absent notes too. Else silence, exit 0.
        ac-mem-dangling-emits)
          m="$ACR/.claude/projects/$lbl/memory"; mem_note "$m/other_note.md" other-note "Body."
          mem_note "$m/other_note_x.md" ox-slug "Body."; ac_put "$m/bare_note.md" "Body, no front matter."
          f="$m/n.md"; mem_note "$f" n "See [[other_note]], [[other-note-x]], [[bare_note]] and [[ghost]]."
          ac_put "$m/MEMORY.md" "- [N](n.md) — probe" "- [O](other_note.md) — probe"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"
          mem_emits "n.md: [[bare_note]] (note has no name: slug); [[ghost]] (no such note); [[other-note-x]] → [[ox-slug]]; [[other_note]] → [[other-note]]" "not listed" "[[other-note-x]] (no such note)" ;;
        ac-mem-clean-silent)
          m="$ACR/.claude/projects/$lbl/memory"; mem_note "$m/other_note.md" other-note "Body."
          f="$m/n.md"; mem_note "$f" n "See [[other-note]]."
          ac_put "$m/MEMORY.md" "- [N](n.md) — probe" "- [O](other_note.md) — probe"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        ac-mem-unindexed-emits)
          m="$ACR/.claude/projects/$lbl/memory"; mem_note "$m/other_note.md" other-note "Body."
          f="$m/n.md"; mem_note "$f" n "See [[other-note]]."
          ac_put "$m/MEMORY.md" "- [O](other_note.md) — probe"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Edit "$f")"; mem_emits "memory: n.md: not listed in MEMORY.md" "[[" ;;
        ac-mem-index-dead-emits)
          m="$ACR/.claude/projects/$lbl/memory"; mem_note "$m/other_note.md" other-note "Body."
          f="$m/MEMORY.md"; ac_put "$f" "- [x](absent.md) — probe" "- [y](other_note.md) — probe"
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; mem_emits "memory: MEMORY.md links missing notes: absent.md" "other_note.md" ;;
        # The same dangling note outside a memory dir, and a symlinked one.
        ac-mem-outside-silent)
          m="$ACR/$lbl/notes"; mem_note "$m/other_note.md" other-note "Body."
          f="$m/n.md"; mem_note "$f" n "See [[other_note]] and [[ghost]]."
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        ac-mem-symlink-silent)
          m="$ACR/.claude/projects/$lbl/memory"; mem_note "$m/other_note.md" other-note "Body."
          ac_put "$m/MEMORY.md" "- [N](n.md) — probe" "- [O](other_note.md) — probe"
          f="$m/n.md"; mem_note "$ACR/$lbl-target.md" n "See [[ghost]]."
          ln -s "$ACR/$lbl-target.md" "$f" || { why="cannot plant the note symlink"; return 1; }
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        # A memory/ dir that is not .claude/projects/<p>/memory/.
        ac-mem-notes-memory-silent)
          m="$ACR/$lbl/notes/memory"; mem_note "$m/other_note.md" other-note "Body."
          f="$m/n.md"; mem_note "$f" n "See [[other_note]] and [[ghost]]."
          run "$lbl" "$2" "$NOREPO" "$root/emptybin" "$(ac_in Write "$f")"; ac_silent ;;
        # apex-metrics-probe --hook on Bash: after a lone, successful `gh pr
        # create`, the branch's newest unfinished run is told the B6 files it
        # lacks (02-acs.md, the examine and external tallies). Else silence.
        pr-missing-acs-emits)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n" feat/p
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; pr_emits r1 "02-acs.md (the ACs, each with its proving command)" "05-examine" "04-external" ;;
        pr-examine-untallied-emits)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n" feat/p 02-acs.md
          ac_put "$PRO/r1/05-examine.md" "$AC_EXAM"
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; pr_emits r1 "dismissed=D tally in 05-examine.md" "02-acs.md (" "04-external" ;;
        # Real flags line (76-apex-ac-proof): `+x` owes the examine tally
        # before any 05-examine.md exists.
        pr-xflag-noexamine-emits)
          pr_repo || return 1; pr_run r1 "Tier: Standard (provisional)" "Flags: -t -pr -o -n; escalated +x +e at validate" feat/p 02-acs.md
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; pr_emits r1 "dismissed=D tally in 05-examine.md" "02-acs.md (" "04-external" ;;
        pr-complete-silent)
          pr_repo || return 1; pr_run r1 "Tier: High-stakes" "Flags: -t -f -x -pr -o -n -e" feat/p 02-acs.md 05-examine.md 04-external-triage.md
          ac_put "$PRO/r1/04-external-verify.json" "$AC_VPASS"
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; ac_silent ;;
        pr-standard-notally-silent)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n (Standard defaults)" feat/p 02-acs.md
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; ac_silent ;;
        pr-direct-silent)
          pr_repo || return 1; pr_run r1 "Tier: Direct" "Flags: -pr" feat/p
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; ac_silent ;;
        # `Mode:` predates the Tier: line (task-board-ui): untiered, silent.
        pr-untiered-silent)
          pr_repo || return 1; pr_run r1 "Mode: Standard" "Flags: -t -pr -o -n" feat/p
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; ac_silent ;;
        # The branch's run is complete and OLDER; a run on feat/p-2 (a name
        # the branch is a prefix of) lacks 02-acs.md and is newer.
        pr-other-branch-silent)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n" feat/p 02-acs.md
          ${pkgs.coreutils}/bin/touch -t 200001010000 "$PRO/r1/00-context.md" || { why="cannot age r1"; return 1; }
          pr_run r2 "Tier: Standard" "Flags: -t -pr -o -n" feat/p-2
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; ac_silent ;;
        # `--head owner:feat/q` names the branch; the cwd's feat/p run is complete.
        pr-head-flag-emits)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n" feat/p 02-acs.md
          pr_run r2 "Tier: Standard" "Flags: -t -pr -o -n" feat/q
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in 'gh pr create --head owner:feat/q --title x')"; pr_emits r2 "02-acs.md (the ACs" "/r1/" ;;
        # Finished runs: one with pr.md, one with commit.txt, both lacking 02-acs.md.
        pr-finished-run-silent)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n" feat/p
          ac_put "$PRO/r1/pr.md" "#1 https://example.invalid/1 — merged (abcdef12)"
          pr_run r2 "Tier: Standard" "Flags: -t -pr -o -n" feat/p
          ac_put "$PRO/r2/commit.txt" "abcdef1234567890"
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; ac_silent ;;
        pr-other-command-silent)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n" feat/p
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in 'gh pr view 42')"; ac_silent ;;
        pr-failed-tool-silent)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n" feat/p
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD" '{"stdout":"","stderr":"","interrupted":true,"isImage":false}')"; ac_silent ;;
        pr-nogit-silent)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n" feat/p
          run "$lbl" "$2" "$PR" "$root/emptybin" "$(pr_in "$PR_CMD")"; ac_silent ;;
        # A symlinked 00-context.md is not read: its target's Branch: stays out.
        pr-ctx-symlink-silent)
          pr_repo || return 1; mkdir -p "$PRO/r1"
          ac_put "$PR/ctx.md" "# APEX: probe" "Tier: Standard" "Flags: -t -pr -o -n" "Branch: feat/p"
          ln -s "$PR/ctx.md" "$PRO/r1/00-context.md" || { why="cannot plant the 00-context.md symlink"; return 1; }
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; ac_silent ;;
        # `-H other` inside the quoted title is no flag: the cwd's feat/p run is read.
        pr-head-in-title-emits)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n" feat/p
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in 'gh pr create --title "fix: drop -H other" --body-file b.md')"; pr_emits r1 "02-acs.md (the ACs" "05-examine" ;;
        # An unclosed quote: no argv, so no branch, fail-open silence.
        pr-unsplittable-silent)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n" feat/p
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in 'gh pr create --title "x')"; ac_silent ;;
        # Verify passed (not BLOCKED), no 04-external-triage.md: the external tally is owed.
        pr-external-untallied-emits)
          pr_repo || return 1; pr_run r1 "Tier: High-stakes" "Flags: -t -f -x -pr -o -n -e" feat/p 02-acs.md 05-examine.md
          ac_put "$PRO/r1/04-external-verify.json" "$AC_VPASS"
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; pr_emits r1 "dismissed=D tally in 04-external-triage.md" "02-acs.md (" "05-examine" ;;
        # Two unfinished runs of feat/p: the newer (r2) lacks 02-acs.md, the
        # older (r1) is complete. The newer is named.
        pr-newest-incomplete-emits)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n" feat/p 02-acs.md
          ${pkgs.coreutils}/bin/touch -t 200001010000 "$PRO/r1/00-context.md" || { why="cannot age r1"; return 1; }
          pr_run r2 "Tier: Standard" "Flags: -t -pr -o -n" feat/p
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; pr_emits r2 "02-acs.md (the ACs" "/r1/" ;;
        # The reverse: the older lacks 02-acs.md, the newer is complete. Silent.
        pr-newest-complete-silent)
          pr_repo || return 1; pr_run r1 "Tier: Standard" "Flags: -t -pr -o -n" feat/p
          ${pkgs.coreutils}/bin/touch -t 200001010000 "$PRO/r1/00-context.md" || { why="cannot age r1"; return 1; }
          pr_run r2 "Tier: Standard" "Flags: -t -pr -o -n" feat/p 02-acs.md
          run "$lbl" "$2" "$PR" "$GITBIN" "$(pr_in "$PR_CMD")"; ac_silent ;;
        *)
          why="no such case"; return 2 ;;
      esac
    }

    body_for() {
      case "$1" in
        pm-*) echo ${hookFile "protect-main.js"} ;;
        bb-*) echo ${hookFile "block-main-bash.js"} ;;
        fmt-*) echo ${hookFile "format-typescript.js"} ;;
        cb-*) echo ${hookFile "correction-budget.js"} ;;
        cg-*) echo ${hookFile "correction-grant.js"} ;;
        rm-*) echo ${hookFile "research-model.js"} ;;
        le-*) echo ${hookFile "lone-excluded-bash.js"} ;;
        se-*) echo ${hookFile "sandbox-escape-evidence.js"} ;;
        wes-*) echo ${hookFile "worktree-env-sync.sh"} ;;
        ss-*) echo ${hookFile "session-state.js"} ;;
        apr-*) echo ${hookFile "apex-pr-record.js"} ;;
        wh-*) echo ${hookFile "worktree-in-use.js"} ;;
        iw-*) echo ${hookFile "instagram-watch.js"} ;;
        ac-* | pr-*) echo ${hookFile "apex-metrics-probe.py"} ;;
      esac
    }

    dump() {
      for f in "$d/$1.in" "$d/$1.out" "$d/$1.err"; do
        echo "--- $f ---" >&2
        cat "$f" >&2 || true
        echo "" >&2
      done
    }

    ncases=0
    nfailed=0
    for c in ${builtins.concatStringsSep " " caseNames}; do
      ncases=$((ncases + 1))
      if ! probe_case "$c" "$(body_for "$c")" real; then
        echo "hook-wiring: D FAILED — $c: $why" >&2
        dump "$lbl"
        nfailed=$((nfailed + 1))
      fi
    done
    [ "$nfailed" -eq 0 ] || { echo "hook-wiring: $nfailed of $ncases runtime case(s) failed against the INSTALLED hooks" >&2; exit 1; }

    # Every case above is green, so a canary that turns its case red, in the
    # way its branch is there to prevent, was killed by the branch it removed.
    # Red for any other reason is a broken mutant or harness, and fails.
    killed=0
    for spec in ${canarySpecs}; do
      id="''${spec%%:*}"
      rest="''${spec#*:}"
      c="''${rest%%:*}"
      body="''${rest#*:}"
      if probe_case "$c" "$body" "$id"; then st=0; else st=$?; fi
      case "$st:$kind" in
        1:mismatch | 1:pwned)
          killed=$((killed + 1))
          echo "hook-wiring: canary $id killed by $c ($why)" ;;
        1:*)
          echo "hook-wiring: canary $id turned $c red for the wrong reason ($why): only a missed deny, a deny where an allow was due, or a PWNED file counts as a kill" >&2
          dump "$lbl"
          exit 1 ;;
        0:*)
          echo "hook-wiring: canary $id survived — $c still passes with its branch put back the way it was, so the case no longer tests what it names" >&2
          dump "$lbl"
          exit 1 ;;
        *)
          echo "hook-wiring: canary $id targets $c: $why" >&2
          exit 1 ;;
      esac
    done
    [ "$killed" -eq ${toString (builtins.length mutants)} ] || { echo "hook-wiring: $killed/${toString (builtins.length mutants)} canaries killed" >&2; exit 1; }
    echo "hook-wiring D: $ncases runtime case(s) green against the installed hooks, $killed/${toString (builtins.length mutants)} canaries killed"
  '';

  assertions = [
    {
      name = "A0 corpus: both sides of the wiring parsed something";
      ok = jsonOk && installed != [ ] && wiredNames != [ ];
      msg = "installed hook file(s): ${toString (builtins.length installed)}, registered hook command(s): ${toString (builtins.length wiredNames)}, settings JSON parsed: ${
        if jsonOk then "yes" else "NO"
      } — an empty corpus makes every comparison below trivially true, which is the exact shape of a check that has stopped checking. Fix the extraction, never the assertion";
    }
    {
      name = "A1 installed -> registered: no hook file is dead text";
      ok = deadHooks == [ ];
      msg = "hook file(s) installed by home/claude-code.nix that NO command in home/claude-code/settings.nix names: ${show deadHooks}. The file is written, copied into ~/.claude/hooks/ and never runs — it looks like a live guard in the tree and is inert on the machine. Register it, delete it, or state it in knownUnwired with the reason";
    }
    {
      name = "A2 registered -> installed: no command names a path that will not exist";
      ok = danglingHooks == [ ];
      msg = "command(s) in home/claude-code/settings.nix pointing at ${marker}<name> that home/claude-code.nix does not install: ${show danglingHooks}. This is the Codex failure of 2026-09-08 in Claude form: the host runs the command, the interpreter cannot find the file, and the session keeps going with that protection simply absent";
    }
    {
      name = "A3 exemptions name real files";
      ok = ghostExemptions == [ ];
      msg = "knownUnwired names file(s) the module no longer installs: ${show ghostExemptions}. The exemption outlived the hook; drop the entry";
    }
    {
      name = "A4 exemptions are still needed";
      ok = resolvedExemptions == [ ];
      msg = "knownUnwired still exempts hook(s) that ARE now registered: ${show resolvedExemptions}. The wiring was fixed and the exemption was not; remove the entry from knownUnwired in this file — one line, and the gate goes back to guarding the real set";
    }
    {
      name = "B0 detector: at least one additionalContext site is visible";
      ok = totalContextSites > 0;
      msg = "scanned every installed hook body and found no `additionalContext` at all. Either no hook emits context any more — in which case B guards nothing and should be revisited — or `codeOf`/`prefixesOf` stopped matching and this invariant is now green by accident";
    }
    {
      name = "B1 emission shape: additionalContext only inside hookSpecificOutput";
      ok = rootLevelOffenders == [ ];
      msg =
        "hook(s) emitting `additionalContext` at the ROOT of the payload: "
        + builtins.concatStringsSep " | " (
          map (n: "${n}: …${excerpt (builtins.head (rootLevelSites n))}") rootLevelOffenders
        )
        + ". The reference documents ONE shape, {\"hookSpecificOutput\":{\"hookEventName\":\"<Event>\",\"additionalContext\":…}}; a root-level key is parsed, ignored, and the context never reaches the model. Nothing warns — the hook exits 0 and the turn continues as if it had spoken";
    }
    {
      name = "C0 detector: at least one hookEventName literal is visible";
      ok = totalDeclaredEvents > 0;
      msg = "no hook body declares a literal hookEventName. Either every emission lost the documented nested form — which B1 should already be failing on — or the extractor stopped parsing and C1 is comparing an empty list against anything";
    }
    {
      name = "C1 event coherence: a hook declares the event it is registered under";
      ok = eventMismatches == [ ];
      msg = "hook(s) whose payload names an event other than the one registering them: ${show eventMismatches}. The host matches the payload's hookEventName against the event it fired; a mismatch is discarded in silence, so the hook runs, computes, writes its answer and nothing at all happens";
    }
    {
      name = "D0 canaries: every mutant anchor is in its hook body";
      ok = missingAnchors == [ ];
      msg = "mutant anchor missing: ${show missingAnchors}. Each anchor is one line home/claude-code/hooks.nix must carry verbatim; without it the canary mutates nothing and its case can no longer be shown to bite. Restore the line, or move the anchor here together with the hook";
    }
    {
      name = "D1 canaries: every mutant changes its body and swaps only its own hook's anchors";
      ok = inertMutants == [ ] && foreignAnchors == [ ];
      msg = "inert mutant(s): ${show inertMutants}; anchor(s) swapped in a hook they do not belong to: ${show foreignAnchors}. A mutant equal to the real body survives by construction";
    }
    {
      name = "D2 canaries: every mutant targets a declared case";
      ok = strandedCanaries == [ ];
      msg = "mutant(s) aimed at no case in caseNames: ${show strandedCanaries}";
    }
    {
      name = "D3 runtime: every run hook is registered with one positive integer timeout";
      ok = badTimeouts == [ ];
      msg = "hook(s) run by D whose registrations give no single positive integer `timeout`: ${show badTimeouts}. D grants each body the host's timeout and no more; without one there is nothing to grant";
    }
    {
      name = "D4 vault: the baked vault path occurs exactly once in each branch guard";
      ok = vaultLitMiscounts == [ ];
      msg = "${vaultLit} (settings.alxVaultPath, JSON) is not in exactly one place in: ${show vaultLitMiscounts}. The vault cases repoint that one literal at a fixture; missing, the exemption is keyed on nothing D can run, and twice, the copy is only half repointed";
    }
    {
      name = "D5 grant: correction-grant.js carries correction-budget's cap line verbatim";
      ok = hasInfix anchors.A-cb-cap.text (bodyText "correction-grant.js");
      msg = "correction-grant.js lacks `${anchors.A-cb-cap.text}`. The grant hook decides a run is spent with the same MAX_ROUNDS correction-budget.js denies at; a drift grants a round to a run with rounds left, or never grants";
    }
    {
      name = "D6 grant: correction-budget.js carries correction-grant's token line verbatim";
      ok = hasInfix anchors.A-cg-token.text (bodyText "correction-budget.js");
      msg = "correction-budget.js lacks `${anchors.A-cg-token.text}`. It denies a CronCreate/ScheduleWakeup prompt carrying the grant token by that same regex; a drift lets the model schedule a line the grant hook accepts as the user's";
    }
    {
      name = "D7 lsof seam: worktree-in-use.js carries its lsof path literal exactly once";
      ok = !whLsofMiscount;
      msg = "`${whLsofLit}` is not in exactly one line of the installed worktree-in-use.js (home/claude-code/hooks.nix, hooks.hookWorktreeInUse; occurrences: ${toString (occurrences whLsofLit (bodyText "worktree-in-use.js"))}). The wh cases repoint that one literal at a fake lsof; missing, they run the real path the build sandbox lacks, and twice, the copy is only half repointed";
    }
    {
      name = "D8 pr probe: the Bash apex-metrics-probe group filters on its handler's `if`";
      ok = prProbeGroups != [ ] && builtins.all prProbeGated prProbeGroups;
      msg = "PostToolUse group(s) with matcher Bash running apex-metrics-probe.py: ${toString (builtins.length prProbeGroups)}; each must carry no group-level `if` and `\"if\" = \"${prProbeIf}\"` on every handler. `if` is a handler field (hooks reference, common fields): on the group it is ignored without a word and python runs after every Bash call";
    }
  ];

  failures = builtins.filter (a: !a.ok) assertions;
in
pkgs.runCommand "hook-wiring-check" { } (
  if failures != [ ] then
    fail (
      "${toString (builtins.length failures)} broken invariant(s):\n"
      + builtins.concatStringsSep "\n" (map (a: "  - ${a.name}: ${a.msg}") failures)
    )
  else
    runtimeProbe
    + ''
      echo "hook-wiring: ${toString (builtins.length installed)} installed and ${toString (builtins.length wiredNames)} registered hook file(s) in bijection, ${toString totalContextSites} additionalContext site(s) nested, ${toString totalDeclaredEvents} declared event(s) coherent — OK"
      touch $out
    ''
)
