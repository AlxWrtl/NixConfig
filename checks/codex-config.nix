# Non-regression check for the Codex config under home/codex/.
#
# THE ONE THIS FILE EXISTS FOR: `~/.codex/hooks.json` named seven scripts that
# did not exist. Codex printed `hook exited with code 127` once per turn and
# ran with NO branch protection while looking fully protected — a security
# failure that a green build never noticed, because nothing tied the command
# strings to the files the configuration installs. C2 below ties them, and
# fails the build when a command names a path the module does not install.
#
# The rest guards the properties that are silent when they break:
#   - order (trust is POSITIONAL: a reordered list un-trusts hooks in silence)
#   - the matcher (wrong matcher = the hook simply never fires)
#   - the timeouts (below 4 s the host kills a hook before its own watchdog
#     fires, and a killed hook GRANTS what it exists to refuse)
#   - the interpreter (a pinned store path would move on every nixpkgs bump
#     and re-hash the file, un-trusting the security hook on an unrelated
#     update)
#
# Runs in `nix flake check`, before any rebuild, from the nix sources.
{ pkgs }:

let
  hooks = import ../home/codex/hooks.nix { inherit pkgs; };

  inherit (pkgs.lib) hasInfix hasSuffix splitString;

  # --- the generated JSON --------------------------------------------------
  # The commands embed store paths, so the JSON string carries string context
  # and builtins.fromJSON refuses it outright ("not allowed to refer to a store
  # path"). Dropping the context is safe HERE and only here: nothing built from
  # `parsed` becomes a build input — the script paths used in the builder below
  # come from hooks.scriptFiles, which keeps its context and therefore its
  # dependency edge.
  parsed = builtins.tryEval (builtins.fromJSON (builtins.unsafeDiscardStringContext hooks.hooksJson));
  jsonOk = parsed.success && builtins.isAttrs parsed.value;
  root = if jsonOk then parsed.value else { };
  events = root.hooks or { };
  eventNames = builtins.attrNames events;
  groupsOf = e: if builtins.isList (events.${e} or null) then events.${e} else [ ];
  allGroups = builtins.concatMap groupsOf eventNames;
  entriesOf = g: if builtins.isList (g.hooks or null) then g.hooks else [ ];
  allEntries = builtins.concatMap entriesOf allGroups;
  commands = map (h: h.command or "") allEntries;

  firstEntryOf =
    e:
    let
      gs = groupsOf e;
      es = if gs == [ ] then [ ] else entriesOf (builtins.head gs);
    in
    if es == [ ] then null else builtins.head es;
  firstCommandOf = e: if firstEntryOf e == null then null else (firstEntryOf e).command or null;
  firstMatcherOf =
    e:
    let
      gs = groupsOf e;
    in
    if gs == [ ] then null else (builtins.head gs).matcher or null;

  # --- what the module actually installs -----------------------------------
  installed = map (f: toString f.source) hooks.scriptFiles;
  pathOfBasename =
    b:
    let
      hits = builtins.filter (f: hasSuffix b f.target) hooks.scriptFiles;
    in
    if hits == [ ] then null else toString (builtins.head hits).source;

  # "<node> <script>" — two fields, the second one a file this module installs.
  commandPathOf =
    c:
    let
      parts = splitString " " c;
    in
    if builtins.length parts == 2 then builtins.elemAt parts 1 else null;

  danglingCommands = builtins.filter (
    c:
    let
      p = commandPathOf c;
    in
    p == null || !(builtins.elem p installed)
  ) commands;

  commandPaths = builtins.filter (p: p != null) (map commandPathOf commands);

  wrongInterpreter = builtins.filter (
    c:
    let
      parts = splitString " " c;
    in
    parts == [ ] || builtins.head parts != hooks.nodeBin
  ) commands;

  timeouts = map (h: h.timeout or null) allEntries;
  badTimeouts = builtins.filter (t: t == null || !(builtins.isInt t) || t < 4) timeouts;

  # --- the ordering contract (AC16) ----------------------------------------
  hooksSrc = builtins.readFile ../home/codex/hooks.nix;

  assertions = [
    {
      name = "C1 hooks.json: the generated JSON parses";
      ok = jsonOk;
      msg = "home/codex/hooks.nix produced a string that is not parseable JSON — Codex reads this file at every turn and an unreadable one means no hook runs at all, silently";
    }
    {
      name = "C2 hooks.json: every command references a script the module installs";
      ok = jsonOk && danglingCommands == [ ];
      msg =
        "command(s) naming a path that home/codex.nix does not install: "
        + (if danglingCommands == [ ] then "none" else builtins.concatStringsSep " | " danglingCommands)
        + " — installed: "
        + builtins.concatStringsSep ", " installed
        + ". This is the exact live failure this module repairs: seven such commands made Codex print `hook exited with code 127` every turn while branch protection was OFF and the configuration looked correct";
    }
    {
      name = "C3 hooks.json: exactly the two declared hooks, PreToolUse and Stop";
      ok =
        jsonOk
        &&
          eventNames == [
            "PreToolUse"
            "Stop"
          ]
        && builtins.length allGroups == 2
        && builtins.length allEntries == 2;
      msg =
        "expected one PreToolUse group and one Stop group, found events ["
        + builtins.concatStringsSep ", " eventNames
        + "] with "
        + toString (builtins.length allEntries)
        + " hook(s) — every extra or missing entry shifts a positional trust key and un-trusts its neighbours in silence";
    }
    {
      name = "C4 order: protect-main is PreToolUse[0], quality-gate is Stop[0]";
      ok =
        jsonOk
        && firstCommandOf "PreToolUse" == "${hooks.nodeBin} ${pathOfBasename "protect-main.js"}"
        && firstCommandOf "Stop" == "${hooks.nodeBin} ${pathOfBasename "quality-gate.js"}";
      msg =
        "PreToolUse[0] is "
        + (if firstCommandOf "PreToolUse" == null then "<absent>" else firstCommandOf "PreToolUse")
        + " and Stop[0] is "
        + (if firstCommandOf "Stop" == null then "<absent>" else firstCommandOf "Stop")
        + " — trust is recorded by position, so swapping or inserting ahead of these two invalidates their approval and Codex then SKIPS them without a word";
    }
    {
      name = "C5 matcher: PreToolUse[0] matches Edit|Write, Stop[0] carries none";
      ok = jsonOk && firstMatcherOf "PreToolUse" == "Edit|Write" && firstMatcherOf "Stop" == null;
      msg =
        "PreToolUse[0] matcher is "
        + (if firstMatcherOf "PreToolUse" == null then "<absent>" else firstMatcherOf "PreToolUse")
        + " — a matcher that does not name the edit tools means the branch guard never fires on the very calls it exists to refuse; Stop takes no matcher";
    }
    {
      name = "C6 timeouts: every hook is registered with at least 4 seconds";
      ok = jsonOk && allEntries != [ ] && badTimeouts == [ ];
      msg =
        "timeout(s) missing, non-integer or below 4: "
        + builtins.concatStringsSep ", " (map (t: if t == null then "<absent>" else toString t) timeouts)
        + " — protect-main self-denies at 3000 ms and quality-gate self-exits at 4000 ms; register anything under 4 s and the host kills the hook BEFORE its own watchdog fires, and a killed hook exits with a code Codex reads as 'did not block'. Change this and you must change the constants in the scripts";
    }
    {
      name = "C7 interpreter: the absolute system node, not a pinned store path";
      ok = jsonOk && commands != [ ] && wrongInterpreter == [ ];
      msg =
        "command(s) not starting with "
        + hooks.nodeBin
        + ": "
        + builtins.concatStringsSep " | " wrongInterpreter
        + " — a pinned \${pkgs.nodejs_22}/bin/node would move on every nixpkgs bump, rewriting the command, changing the file's content hash and un-trusting the security hook on an unrelated update";
    }
    {
      name = "C8 trust keys: one per hook, derived from the same expression";
      ok =
        hooks.trustKeySuffixes == [
          "pre_tool_use:0:0"
          "stop:0:0"
        ]
        && builtins.length hooks.trustKeySuffixes == builtins.length allEntries;
      msg =
        "trust key suffixes are ["
        + builtins.concatStringsSep ", " hooks.trustKeySuffixes
        + "] for "
        + toString (builtins.length allEntries)
        + " hook(s) — the verifier is handed these keys; if they stop matching the generated file it reports approval for hooks that are not the ones installed";
    }
    {
      name = "C9 ordering contract: hookList is a list and the header says append-only";
      ok =
        builtins.isList hooks.hookList
        && hasInfix "APPEND ONLY" hooksSrc
        && hasInfix "attribute set" hooksSrc;
      msg = "home/codex/hooks.nix no longer builds its hooks from an explicit ordered list, or its header lost the append-only rule — an attribute set would be sorted alphabetically by nix and reorder the file, and a mid-list insertion un-trusts every hook after it with no error anywhere";
    }
  ];

  failures = builtins.filter (a: !a.ok) assertions;

  fail = msg: throw "codex-config: ${msg}";

  # Build-time, not eval-time: the referenced files must exist, be executable
  # and be valid JavaScript. `node --check` here is the BUILD tool
  # (pkgs.nodejs_22); the hooks deliberately run under the absolute system
  # node instead — see C7. Do not "align" the two.
  # Deliberately over hooks.scriptFiles and NOT over the paths read back out of
  # the JSON: those went through unsafeDiscardStringContext, so nix would not
  # see them as inputs and the files would simply be absent from the build.
  # C2 and C3 above already prove the two sets are the same.
  scriptProbes = builtins.concatStringsSep "\n" (
    map (p: ''
      test -x ${p} || { echo "codex-config: ${p} is not executable — Codex hooks resolve into the store, and a non-executable hook is a dead hook"; exit 1; }
      ${pkgs.nodejs_22}/bin/node --check ${p}
    '') installed
  );

in
pkgs.runCommand "codex-config-check" { } (
  if failures != [ ] then
    fail (
      "${toString (builtins.length failures)} broken invariant(s):\n"
      + builtins.concatStringsSep "\n" (map (a: "  - ${a.name}: ${a.msg}") failures)
    )
  else
    ''
      ${scriptProbes}
      echo "codex-config: ${toString (builtins.length assertions)} invariants, ${toString (builtins.length allEntries)} hooks, ${toString (builtins.length commandPaths)} scripts syntax-checked — OK"
      touch $out
    ''
)
