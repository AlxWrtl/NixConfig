# Structure check for the Claude Code mods (home/claude-code/mods.nix and
# home/claude-code/mods/<name>/).
#
# `claude plugin validate --strict` and `claude plugin test` are the real
# gate for a mod's code, but `claude` is not in the build sandbox: they run in
# the session. What can be asserted offline is asserted here, at eval time:
#   M1 mods.nix `names` equals the directories under mods/, both ways;
#   M2 every .claude-plugin/plugin.json parses and its `name` is its folder;
#   M3 every hooks/hooks.json names exactly one module, and it exists;
#   M4 no .js/.cjs/.mjs under mods/ (js-lint counts every tracked .js, and
#      the mods are TypeScript ES modules, outside its commonjs config);
#   M5 no source holds a forbidden noun: sound, host processes (and their
#      aliases `process.spawn`, `'process'`, `"process"`, a computed `$[` or
#      `Reflect.get($`),
#      network, file writes, dynamic import, toasts; in a hooks module of any
#      mod no refusal or rewrite token either (`deny`, `permissionDecision`,
#      `decision:`, `updatedToolOutput`, `preventContinuation`) nor the bare
#      word `process`: the mods observe, they never refuse, rewrite or stop a
#      call. Two exceptions, the deck's « ↻ relancer » and « ⧉ ouvrir »: the
#      exact `$.process.run([…claude-bg, 'resume', id], …)` call is stripped
#      before the scan in deck/hooks/resume.ts only, the exact
#      `$.process.run([…claude-bg, 'open', id], …)` call in deck/hooks/open.ts
#      only, each only while it is its file's single `$.process`;
#   M5b each of those calls occurs exactly once in its file;
#   M6 settings env CLAUDE_CODE_PLUGIN_DIRS is exactly the absolute
#      ~/.claude/mods/<name> folders of mods.nix, ":"-joined, recomputed here
#      rather than read back through mods.pluginDirs;
#   M7 activation copies the mods (claudeCodeMods, DRY_RUN skip, engine types
#      excluded) and home/claude-code.nix hands it the source folder.
# Canaries: the M5 scan must flag `$.audio.speak`, and a `deny` and a
# `permissionDecision` in the deck mod's hooks, M4 a .js name, and M1 an extra name, or the check fails: a
# scan that stopped matching would otherwise be green forever. For the resume
# exception, the scan must flag the call in another file (C5), a second call
# in resume.ts that survives the strip (C6), another subcommand (C7), the
# aliases `$['process']` and `{ process: p } = $` (C9) and
# `Reflect.get($, 'pro' + 'cess')` (C10); it must pass the call alone in
# resume.ts (C8), or the exception would only hold with the call gone. For the
# open exception, it must flag the open call in resume.ts (C11) and another
# subcommand in open.ts (C12), and pass the call alone in open.ts (C13).
{ pkgs }:

let
  inherit (pkgs) lib;
  inherit (lib) hasInfix hasSuffix attrByPath;

  home = "/Users/alx";
  mods = import ../home/claude-code/mods.nix;
  settings = import ../home/claude-code/settings.nix { homeDirectory = home; };
  activation = builtins.readFile ../home/claude-code/activation.nix;
  entrypoint = builtins.readFile ../home/claude-code.nix;
  root = ../home/claude-code/mods;

  nonEmpty = what: list: if list == [ ] then throw "claude-mods: ${what} is empty" else list;

  dirsOf =
    dir: builtins.attrNames (lib.filterAttrs (_: kind: kind == "directory") (builtins.readDir dir));

  # Every regular file under a directory, as paths relative to `root`.
  walk =
    dir: prefix:
    lib.concatLists (
      lib.mapAttrsToList (
        name: kind:
        if kind == "directory" then
          walk (dir + "/${name}") "${prefix}${name}/"
        else if kind == "regular" then
          [ "${prefix}${name}" ]
        else
          [ ]
      ) (builtins.readDir dir)
    );

  modDirs = nonEmpty "the mods/ folder listing" (dirsOf root);
  files = nonEmpty "the mods/ file walk" (walk root "");

  # --- M1
  sameSet =
    a: b:
    builtins.filter (x: !(builtins.elem x b)) a == [ ]
    && builtins.filter (x: !(builtins.elem x a)) b == [ ];
  namesMatch = names: sameSet names modDirs;

  # --- M2 / M3
  readJson =
    path:
    let
      r = builtins.tryEval (builtins.fromJSON (builtins.readFile path));
    in
    if r.success && builtins.isAttrs r.value then r.value else null;
  manifestOk =
    name:
    let
      m = readJson (root + "/${name}/.claude-plugin/plugin.json");
    in
    m != null && (m.name or null) == name;
  hooksOk =
    name:
    let
      h = readJson (root + "/${name}/hooks/hooks.json");
      modules = if h == null then null else h.modules or null;
    in
    builtins.isList modules
    && builtins.length modules == 1
    && builtins.isString (builtins.head modules)
    && builtins.pathExists (root + "/${name}/hooks/${builtins.head modules}");
  badManifests = builtins.filter (n: !(manifestOk n)) mods.names;
  badHooks = builtins.filter (n: !(hooksOk n)) mods.names;

  # --- M4
  isJs = f: hasSuffix ".js" f || hasSuffix ".cjs" f || hasSuffix ".mjs" f;
  jsFiles = list: builtins.filter isJs list;

  # --- M5
  forbidden = [
    "$.audio"
    "$.process"
    "$.http"
    "$.fs.write"
    "fetch("
    "import("
    "toast"
    # Aliases of $.process: another engine member, a computed key, a quoted name.
    "process.spawn"
    "'process'"
    "\"process\""
    "$["
    "Reflect.get($"
  ];
  isHooksModule = f: hasInfix "/hooks/" f && (hasSuffix ".ts" f || hasSuffix ".tsx" f);
  # Refusal and rewrite spellings of the hook results, barred from every hooks
  # module, plus the bare word `process` (a destructured `{ process } = $`).
  hookResultNouns = [
    "deny"
    "permissionDecision"
    "decision:"
    "updatedToolOutput"
    "preventContinuation"
    "process"
  ];
  # Occurrences of a literal needle: length delta, not a regex.
  count =
    needle: hay:
    (builtins.stringLength hay - builtins.stringLength (builtins.replaceStrings [ needle ] [ "" ] hay))
    / builtins.stringLength needle;
  # The two host commands of any mod: the deck's « ↻ relancer » and « ⧉ ouvrir »
  # run the claude-bg allow-list wrapper. Each exact call only in its own file,
  # once, and no other `$.process` there; anything else keeps every noun it holds.
  resumeFile = "deck/hooks/resume.ts";
  resumeNeedle = "$.process.run(['/etc/profiles/per-user/alx/bin/claude-bg', 'resume', id], { timeoutMs: 60000 })";
  openFile = "deck/hooks/open.ts";
  openNeedle = "$.process.run(['/etc/profiles/per-user/alx/bin/claude-bg', 'open', id], { timeoutMs: 15000 })";
  allowed = [
    {
      file = resumeFile;
      needle = resumeNeedle;
    }
    {
      file = openFile;
      needle = openNeedle;
    }
  ];
  allowedText =
    path: text:
    let
      own = builtins.filter (a: a.file == path) allowed;
      needle = (builtins.head own).needle;
    in
    if own != [ ] && count "$.process" text == 1 && count needle text == 1 then
      builtins.replaceStrings [ needle ] [ "" ] text
    else
      text;
  nounsIn =
    path: text:
    builtins.filter (n: hasInfix n (allowedText path text)) (
      forbidden ++ lib.optionals (isHooksModule path) hookResultNouns
    );
  textOf =
    file: if builtins.pathExists (root + "/${file}") then builtins.readFile (root + "/${file}") else "";
  # M5b: each allowed call in its real file, exactly once (missing file = 0).
  badAllowed = builtins.filter (a: count a.needle (textOf a.file) != 1) allowed;
  scan = lib.concatMap (
    f: map (n: "${f}: ${n}") (nounsIn f (builtins.readFile (root + "/${f}")))
  ) files;

  # --- M6
  parsed = builtins.tryEval (builtins.fromJSON settings.settingsJson);
  s = if parsed.success && builtins.isAttrs parsed.value then parsed.value else { };
  pluginDirs = attrByPath [ "env" "CLAUDE_CODE_PLUGIN_DIRS" ] null s;
  expectedDirs = builtins.concatStringsSep ":" (
    map (n: "${home}/.claude/mods/${n}") (nonEmpty "mods.nix names" mods.names)
  );

  # --- M7
  activationNeedles = [
    "claudeCodeMods = lib.hm.dag.entryAfter"
    "if [[ -v DRY_RUN ]]; then echo \"dry-run: skip claudeCodeMods\"; exit 0; fi"
    "--filter='-s /*/.claude-plugin/types/'"
    "--filter='P /\${n}/.claude-plugin/types/'"
    "--chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r"
    "\"$HOME/.claude/mods/\""
    "modsRc=$?"
  ];
  missingActivation = builtins.filter (n: !(hasInfix n activation)) activationNeedles;

  assertions = [
    {
      name = "M1 mods.nix names equal the mods/ directories";
      ok = namesMatch mods.names;
      msg = "names ${builtins.toJSON mods.names} vs directories ${builtins.toJSON modDirs}";
    }
    {
      name = "M2 plugin.json parses and its name is its folder";
      ok = badManifests == [ ];
      msg = "bad manifest(s): ${builtins.toJSON badManifests}";
    }
    {
      name = "M3 hooks.json names exactly one existing module";
      ok = badHooks == [ ];
      msg = "bad hooks.json: ${builtins.toJSON badHooks}";
    }
    {
      name = "M4 no .js/.cjs/.mjs under mods/";
      ok = jsFiles files == [ ];
      msg = "found ${builtins.toJSON (jsFiles files)}";
    }
    {
      name = "M5 no forbidden noun in a mod source";
      ok = scan == [ ];
      msg = "found ${builtins.toJSON scan}";
    }
    {
      name = "M5b each allowed deck call is in its file, exactly once";
      ok = badAllowed == [ ];
      msg = builtins.concatStringsSep "; " (
        map (
          a:
          "${a.file} holds ${toString (count a.needle (textOf a.file))} times (missing file = 0), expected exactly once: ${a.needle}"
        ) badAllowed
      );
    }
    {
      name = "M6 settings env CLAUDE_CODE_PLUGIN_DIRS = the mods folders";
      ok = pluginDirs == expectedDirs;
      msg = "got ${builtins.toJSON pluginDirs}, expected ${builtins.toJSON expectedDirs}";
    }
    {
      name = "M7 activation copies the mods and claude-code.nix passes modsSrc";
      ok = missingActivation == [ ] && hasInfix "modsSrc = ./claude-code/mods;" entrypoint;
      msg = "activation.nix lacks ${builtins.toJSON missingActivation}, or home/claude-code.nix no longer passes modsSrc";
    }
    # Canaries: each detector must fire on a planted fault.
    {
      name = "C1 the M5 scan flags $.audio.speak";
      ok = nounsIn "x/hooks/index.ts" "await $.audio.speak('hi')" == [ "$.audio" ];
      msg = "the forbidden-noun scan no longer detects anything";
    }
    {
      name = "C4 the M5 scan flags deny in the deck mod's hooks";
      ok =
        nounsIn "deck/hooks/register.tsx" "return { deny: 'no' }" == [ "deny" ]
        && nounsIn "deck/hooks/register.tsx" "{ permissionDecision: 'ask' }" == [ "permissionDecision" ]
        && nounsIn "deck/hooks/core.ts" "$.http.get(u)" == [ "$.http" ];
      msg = "the refusal-token scan no longer covers the deck mod";
    }
    {
      name = "C5 the M5 scan flags the resume call outside ${resumeFile}";
      ok =
        nounsIn "deck/hooks/register.tsx" "const r = await ${resumeNeedle}" == [
          "$.process"
          "process"
        ];
      msg = "the resume exception is no longer bound to its one file";
    }
    {
      name = "C6 the M5 scan flags a second call in ${resumeFile} that survives the strip";
      ok =
        nounsIn resumeFile "const r = await ${resumeNeedle}\nawait $.process.run(['sh'])" == [
          "$.process"
          "process"
        ];
      msg = "a second call in resume.ts that survives the strip is no longer flagged";
    }
    {
      name = "C7 the M5 scan flags another claude-bg subcommand in ${resumeFile}";
      ok =
        nounsIn resumeFile (
          "const r = await " + builtins.replaceStrings [ "'resume'" ] [ "'stop'" ] resumeNeedle
        ) == [
          "$.process"
          "process"
        ];
      msg = "the resume exception no longer requires the exact argv";
    }
    {
      name = "C8 the M5 scan passes the resume call alone in ${resumeFile}";
      ok = nounsIn resumeFile "const r = await ${resumeNeedle}" == [ ];
      msg = "the resume exception no longer strips the one allowed call — M5 could only pass with it gone";
    }
    {
      name = "C9 the M5 scan flags computed and destructured $.process aliases";
      ok =
        nounsIn "deck/hooks/core.ts" "await $['process'].run(['sh'])" == [
          "'process'"
          "$["
          "process"
        ]
        && nounsIn "deck/hooks/core.ts" "const { process: p } = $" == [ "process" ];
      msg = "the alias spellings of $.process are no longer flagged";
    }
    {
      name = "C10 the M5 scan flags a Reflect.get on the engine";
      ok = nounsIn "deck/hooks/core.ts" "Reflect.get($, 'pro' + 'cess')" == [ "Reflect.get($" ];
      msg = "a computed Reflect.get($, …) alias of $.process is no longer flagged";
    }
    {
      name = "C11 the M5 scan flags the open call in ${resumeFile}";
      ok =
        nounsIn resumeFile "const r = await ${openNeedle}" == [
          "$.process"
          "process"
        ];
      msg = "the open exception is no longer bound to its one file";
    }
    {
      name = "C12 the M5 scan flags another claude-bg subcommand in ${openFile}";
      ok =
        nounsIn openFile ("const r = await " + builtins.replaceStrings [ "'open'" ] [ "'stop'" ] openNeedle)
        == [
          "$.process"
          "process"
        ];
      msg = "the open exception no longer requires the exact argv";
    }
    {
      name = "C13 the M5 scan passes the open call alone in ${openFile}";
      ok = nounsIn openFile ("const r = await " + openNeedle) == [ ];
      msg = "the open exception no longer strips its one allowed call — M5 could only pass with it gone";
    }
    {
      name = "C2 the M4 filter flags a .js file";
      ok = jsFiles [ "deck/hooks/register.js" ] != [ ];
      msg = "the .js filter no longer detects anything";
    }
    {
      name = "C3 the M1 comparison flags an extra name";
      ok = !(namesMatch (mods.names ++ [ "ghost-mod" ]));
      msg = "the names/directories comparison no longer detects a mismatch";
    }
  ];

  failures = builtins.filter (a: !a.ok) assertions;
in
pkgs.runCommand "claude-mods-check" { } (
  if failures != [ ] then
    throw (
      "claude-mods: ${toString (builtins.length failures)} broken invariant(s):\n"
      + builtins.concatStringsSep "\n" (map (a: "  - ${a.name}: ${a.msg}") failures)
    )
  else
    ''
      echo "claude-mods: ${toString (builtins.length assertions)} invariants over ${toString (builtins.length files)} files — OK"
      touch $out
    ''
)
