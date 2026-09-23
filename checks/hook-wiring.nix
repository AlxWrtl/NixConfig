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
#
# The corpus is EVALUATED, not read as text: home/claude-code.nix is imported
# as a module and its `home.file` is the same attrset home-manager installs.
# So this file holds no list of hook names, no line number, and keeps working
# across any edit to hooks.nix or settings.nix.
#
# Runs in `nix flake check`, before any rebuild, from the nix sources.
{ pkgs }:

let
  lib = pkgs.lib;
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
  };

  # Matched on "/hooks/" rather than on the module's own `claudeDir` constant:
  # this file must not carry a second copy of a value the module owns. If the
  # match ever stops working the corpus goes empty, and A0 below fails on that
  # before any bijection can be vacuously true.
  installedPaths = builtins.filter (n: hasInfix "/hooks/" n) (
    builtins.attrNames claudeModule.home.file
  );
  installed = map baseNameOf installedPaths;
  bodyOf = n: claudeModule.home.file.${n}.text or "";
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
  hookRefsIn = cmd: map firstToken (builtins.tail (splitString marker cmd));

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
  #     hook in knownUnwired has no event to compare to and is skipped.
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
    ''
      echo "hook-wiring: ${toString (builtins.length installed)} installed and ${toString (builtins.length wiredNames)} registered hook file(s) in bijection, ${toString totalContextSites} additionalContext site(s) nested, ${toString totalDeclaredEvents} declared event(s) coherent — OK"
      touch $out
    ''
)
