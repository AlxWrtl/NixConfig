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
#   M5 no source holds a forbidden noun: sound, host processes, network,
#      file writes, dynamic import, toasts; no `deny` in a hooks module
#      (the mods observe, they never refuse a call);
#   M6 settings env CLAUDE_CODE_PLUGIN_DIRS is exactly the absolute
#      ~/.claude/mods/<name> folders of mods.nix, ":"-joined, recomputed here
#      rather than read back through mods.pluginDirs;
#   M7 activation copies the mods (claudeCodeMods, DRY_RUN skip, engine types
#      excluded) and home/claude-code.nix hands it the source folder.
# Canaries: the M5 scan must flag `$.audio.speak`, M4 must flag a .js name,
# and M1 must flag an extra name, or the check fails: a scan that stopped
# matching would otherwise be green forever.
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
  ];
  isHooksModule = f: hasInfix "/hooks/" f && (hasSuffix ".ts" f || hasSuffix ".tsx" f);
  nounsIn =
    path: text:
    builtins.filter (n: hasInfix n text) (forbidden ++ lib.optional (isHooksModule path) "deny");
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
    "--exclude='/*/.claude-plugin/types/'"
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
      name = "C2 the M4 filter flags a .js file";
      ok = jsFiles [ "task-board/hooks/index.js" ] != [ ];
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
