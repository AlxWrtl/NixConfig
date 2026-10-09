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
#      (the mods observe, they never refuse a call); flightdeck alone is
#      exempt from `deny` (verdict data), and M5b bans a returned refusal in
#      its hooks instead: an allow-list, the known data spellings stripped,
#      then any `deny:` / `decision:` / `permissionDecision` / `{ deny }`
#      left fails, multiline included;
#   M5c every flightdeck file under hooks/, types/, .claude-plugin/ has the
#      sha256 recorded here (upstream tag v0.3.2), both ways;
#   M6 settings env CLAUDE_CODE_PLUGIN_DIRS is exactly the absolute
#      ~/.claude/mods/<name> folders of mods.nix, ":"-joined, recomputed here
#      rather than read back through mods.pluginDirs;
#   M7 activation copies the mods (claudeCodeMods, DRY_RUN skip, engine types
#      excluded) and home/claude-code.nix hands it the source folder.
# Canaries: the M5 scan must flag `$.audio.speak`, M5b a `{ decision: 'deny' }`
# and a bare `deny: reason`, M5c a one-byte change, M4 a .js name, and M1 an
# extra name, or the check fails: a scan that stopped matching would
# otherwise be green forever.
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
  # Flightdeck (vendored, byte-identical to upstream) counts permission
  # verdicts, so `deny` is data there (`verdict.decision === 'deny'`, a
  # `deny` tally field). Only that noun, only that mod, is exempt; M5b bans a
  # returned refusal in its hooks instead.
  isFlightdeckHooks = f: lib.hasPrefix "flightdeck/hooks/" f && isHooksModule f;
  nounsIn =
    path: text:
    builtins.filter (n: hasInfix n text) (
      forbidden ++ lib.optional (isHooksModule path && !(isFlightdeckHooks path)) "deny"
    );
  scan = lib.concatMap (
    f: map (n: "${f}: ${n}") (nounsIn f (builtins.readFile (root + "/${f}")))
  ) files;

  # --- M5b
  # Allow-list: the only `deny`/`decision` keys flightdeck's hooks hold today
  # are its verdict tally (hooks/core.ts). They are stripped, verbatim; any
  # refusal-shaped key left is a finding. POSIX regexes, `[[:space:]]` spans
  # newlines, so a multiline `return {\n deny:` is caught too.
  fdDataSpellings = [
    "cleared: 0, deny: 0 }"
    "deny: s.deny + g.totals[k].deny,"
  ];
  refusalPatterns = [
    "deny[\"'`]?[]]?[[:space:]]*:"
    "[dD]ecision[\"'`]?[]]?[[:space:]]*:"
    "permissionDecision"
    "[{,][[:space:]]*deny[[:space:]]*[,}]"
    "[(][[:space:]]*[{][[:space:]]*deny"
  ];
  stripData = builtins.replaceStrings fdDataSpellings (map (_: "") fdDataSpellings);
  refusalsIn =
    text:
    let
      t = stripData text;
    in
    builtins.filter (re: builtins.length (builtins.split re t) > 1) refusalPatterns;
  fdHooks = nonEmpty "the flightdeck hooks files" (builtins.filter isFlightdeckHooks files);
  fdHooksText = lib.concatMapStrings (f: builtins.readFile (root + "/${f}")) fdHooks;
  refusalScan = lib.concatMap (
    f: map (n: "${f}: ${n}") (refusalsIn (builtins.readFile (root + "/${f}")))
  ) fdHooks;
  # A stale allow-list entry would allow a future match for nothing.
  staleSpellings = builtins.filter (d: !(hasInfix d fdHooksText)) fdDataSpellings;

  # --- M5c
  # sha256 of the vendored code at upstream tag v0.3.2 (commit b8d6d26).
  # Changing a hash here means re-auditing upstream first: the update
  # procedure in home/claude-code/mods/flightdeck/VENDORED.md.
  fdPins = {
    ".claude-plugin/plugin.json" = "70ab346401dea3e1cae77ee2bde2aaebc37afc9594461efce44609e4d137c77d";
    "hooks/core.ts" = "ac1415c8d5bdf82e56c5a10ff438f2054a34654e930db869da1c45b732aa98a6";
    "hooks/elapsed.tsx" = "212ec2954e7d41ffff139791702be8a402eba57b2d9c1119f440a0ebd154c73e";
    "hooks/hooks.json" = "d842d789476d67282d0f04b7e5fdc68a3d981ccec65dd79cfa2d11eed13fb828";
    "hooks/rail.tsx" = "6875743b9efb1847f317d96c961000eba658183ab64e8cfc82c344359881ff49";
    "hooks/register.tsx" = "4a7238ecfb040de3afc2370c3787d7a083b13476cba6838813e7ff603c1d39b0";
    "types/index.d.ts" = "4b7c330ef5fc570cb12219d909f5cb9bea4a9e274e0750b3e29dcc7d503cbc52";
  };
  isPinScope =
    f:
    lib.any (d: lib.hasPrefix "flightdeck/${d}/" f) [
      "hooks"
      "types"
      ".claude-plugin"
    ];
  fdPinned = nonEmpty "the flightdeck pinned files" (
    map (lib.removePrefix "flightdeck/") (builtins.filter isPinScope files)
  );
  pinMatches = f: hash: (fdPins.${f} or null) == hash;
  pinDrift = builtins.filter (
    f: !(pinMatches f (builtins.hashFile "sha256" (root + "/flightdeck/${f}")))
  ) fdPinned;
  pinMissing = builtins.filter (f: !(builtins.elem f fdPinned)) (builtins.attrNames fdPins);
  pinText = builtins.readFile (root + "/flightdeck/hooks/hooks.json");
  pinOneByte = "X" + builtins.substring 1 (builtins.stringLength pinText) pinText;

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
      name = "M5b no flightdeck hooks file returns a refusal";
      ok = refusalScan == [ ] && staleSpellings == [ ];
      msg = "found ${builtins.toJSON refusalScan}, or allow-listed spelling(s) gone: ${builtins.toJSON staleSpellings}";
    }
    {
      name = "M5c flightdeck code matches the sha256 pinned at v0.3.2";
      ok = pinDrift == [ ] && pinMissing == [ ];
      msg = "changed or unpinned: ${builtins.toJSON pinDrift}; pinned but gone: ${builtins.toJSON pinMissing} (re-audit upstream, then update fdPins)";
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
      name = "C4 the M5 scan still flags deny outside flightdeck, not inside";
      ok =
        nounsIn "apex-band/hooks/index.tsx" "return { deny: 'no' }" == [ "deny" ]
        && nounsIn "flightdeck/hooks/core.ts" "s.deny + 1" == [ ]
        && nounsIn "flightdeck/hooks/core.ts" "$.http.get(u)" == [ "$.http" ];
      msg = "the deny exemption leaks to other mods, or drops other nouns for flightdeck";
    }
    {
      name = "C5 the M5b scan flags a returned refusal";
      ok =
        refusalsIn "return { deny: 'no' }" != [ ]
        && refusalsIn "return {deny: true}" != [ ]
        && refusalsIn "{ deny: \"x\" }" != [ ]
        && refusalsIn "{ decision: 'deny' }" != [ ]
        && refusalsIn "deny: reason" != [ ]
        && refusalsIn "return {\n    deny:\n      reason,\n  }" != [ ]
        && refusalsIn "{ permissionDecision: 'deny' }" != [ ]
        && refusalsIn "return ({ deny })" != [ ]
        && refusalsIn "cleared: 0, deny: 0 }; return { deny: r }" != [ ]
        && refusalsIn "s.deny > 0" == [ ]
        && refusalsIn "c.verdict === 'deny' ? 'x' : 'y'" == [ ]
        && refusalsIn "const ZERO: Tally = { rule: 0, ask: 0, cleared: 0, deny: 0 }" == [ ];
      msg = "the refusal scan no longer detects anything, or flags verdict data";
    }
    {
      name = "C6 the M5c pin flags a one-byte change";
      ok =
        pinMatches "hooks/hooks.json" (builtins.hashString "sha256" pinText)
        && pinOneByte != pinText
        && !(pinMatches "hooks/hooks.json" (builtins.hashString "sha256" pinOneByte));
      msg = "the sha256 pin no longer detects a changed file";
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
