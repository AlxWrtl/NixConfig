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
#      flood; the argv call in format-typescript. Every other case is run and
#      graded, with no mutant to show it bites.
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
    # Flake inputs feed only non-hook `.source` links (design-md library);
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
  knownUnwired = [
    # Rewrites `nix-instantiate`/`nixfmt` into `rtk …`. Written, installed, and
    # named by no command in settings.nix — measured, not assumed.
    "rtk-nix-rewrite.sh"
  ];

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
    A5-require = {
      hook = "format-typescript.js";
      text = "const { spawnSync } = require(\"child_process\");";
    };
    A5-call = {
      hook = "format-typescript.js";
      text = "spawnSync(\"prettier\", [\"--write\", file], { stdio: \"ignore\", timeout: 8000, killSignal: \"SIGKILL\" });";
    };
  };

  # The M5 mutant names its shell: execSync's default /bin/sh dispatches
  # through /private/var/select/sh on macOS, which the build sandbox may not
  # expose — a mutant that cannot start a shell would survive for the wrong
  # reason. The injection is a property of ANY shell; bash is pinned.
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
          to = "const { execSync } = require(\"child_process\");";
        }
        {
          anchor = "A5-call";
          to = "execSync(\"prettier --write \" + JSON.stringify(file), { stdio: \"ignore\", timeout: 8000, shell: \"${pkgs.bash}/bin/bash\" });";
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
    "bb-master-commit"
    "bb-master-malformed"
    "bb-master-nogit"
    "bb-master-hung"
    "bb-master-nl-flood"
    "bb-master-status"
    "bb-local-commit"
    "bb-feat-commit"
    "bb-norepo-commit"
    "bb-detached-commit"
    "bb-cd-nonexistent"
    "bb-cd-broken"
    "fmt-inject"
  ];

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

  hookFile = n: pkgs.writeText n (bodyText n);
  mutantFile = m: pkgs.writeText "${m.id}-${m.hook}" (mutantBody m);
  canarySpecs = builtins.concatStringsSep " " (map (m: "${m.id}:${m.kills}:${mutantFile m}") mutants);

  jq = "${pkgs.jq}/bin/jq";

  # Grades. Deny, in Claude's form: exit 0, a deny decision on stdout, nothing
  # on stderr, and a reason naming WHY — without it a hook that dies before
  # reading git and one that refuses on purpose look alike. Allow: exit 0 and
  # silence on both streams, byte for byte.
  # Positive controls: pm-master-inrepo and bb-master-commit (the guard really
  # reaches its branch read), fmt-inject's prettier.log (prettier really ran).
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
    GITBIN=${pkgs.git}/bin
    g init -q -b master "$MASTER"
    g -C "$MASTER" remote add origin https://example.invalid/x.git
    g init -q -b master "$LOCAL"
    g init -q -b feat/probe "$FEAT"
    g init -q -b master "$DETACHED"
    g -C "$DETACHED" -c user.name=p -c user.email=p@p -c commit.gpgsign=false commit -q --allow-empty -m probe
    g -C "$DETACHED" checkout -q --detach
    ln -s "$MASTER" "$LINK"
    # Dangling, outside the repo, aimed INTO it: a Write there lands in MASTER.
    ln -s "$MASTER/dangling-target.ts" "$NOREPO/dangling"
    # `exec`: SIGKILL on timeout must reach the sleeper, not orphan it on the pipe.
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exec ${pkgs.coreutils}/bin/sleep 30' > "$root/hangbin/git"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'printf "%s\n" "$2" >> "''${0%/*}/prettier.log"' > "$root/fakebin/prettier"
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
    bb_in() { ${jq} -cn --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
    fmt_in() { ${jq} -cn --arg f "$1" '{hook_event_name:"PostToolUse",tool_name:"Write",tool_input:{file_path:$f}}'; }
    # A commit followed by 64 KB of newlines, built by jq: a shell `$(…)`
    # would strip the very newlines the case is about.
    bb_flood() { ${jq} -cn '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:("git commit -m x" + ("\n" * 65536))}}'; }

    # $1 label, $2 body, $3 cwd, $4 PATH, $5 stdin. Leaves the exit status in $rc.
    # $tmo is the host's timeout for the hook under test (probe_case sets it);
    # 124 is `timeout` killing it, which the host reads as no decision.
    # No set +e/-e toggling: this runs both inside and outside `if`.
    run() {
      printf '%s' "$5" > "$d/$1.in"
      rc=0
      (cd "$3" && env -i GIT_CONFIG_NOSYSTEM=1 HOME="$TMPDIR" PATH="$4" ${pkgs.coreutils}/bin/timeout "$tmo" ${pkgs.nodejs_22}/bin/node "$2") \
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

    is_allow() {
      [ "$rc" -eq 0 ] || { why="exit $rc, expected 0"; return 1; }
      [ ! -s "$d/$lbl.out" ] || { why="stdout not empty — an allow is silence"; return 1; }
      [ ! -s "$d/$lbl.err" ] || { why="stderr not empty"; return 1; }
    }

    # $1 case, $2 body under test, $3 tag. 0 passed, 1 failed ($why), 2 no such case.
    probe_case() {
      lbl="$3.$1"
      why=""
      kind=""
      case "$1" in
        pm-*) tmo=${hostTimeout "protect-main.js"} ;;
        bb-*) tmo=${hostTimeout "block-main-bash.js"} ;;
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
        bb-master-status)
          run "$lbl" "$2" "$MASTER" "$GITBIN" "$(bb_in "git status")"; is_allow ;;
        bb-local-commit)
          run "$lbl" "$2" "$LOCAL" "$GITBIN" "$(bb_in "git commit -m x")"; is_allow ;;
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
        fmt-inject)
          rm -f "$TMPDIR/PWNED" "$root/fakebin/prettier.log"
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
        *)
          why="no such case"; return 2 ;;
      esac
    }

    body_for() {
      case "$1" in
        pm-*) echo ${hookFile "protect-main.js"} ;;
        bb-*) echo ${hookFile "block-main-bash.js"} ;;
        fmt-*) echo ${hookFile "format-typescript.js"} ;;
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
          echo "hook-wiring: canary $id turned $c red for the wrong reason ($why): only a missed deny or a PWNED file counts as a kill" >&2
          dump "$lbl"
          exit 1 ;;
        0:*)
          echo "hook-wiring: canary $id survived — $c still passes with its fail-closed branch put back to exit 0, so the case no longer tests what it names" >&2
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
