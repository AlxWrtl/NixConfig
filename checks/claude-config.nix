# Non-regression check for the Claude Code config under home/claude-code/.
#
# Four fixes are locked in here. Each was a silent failure: nothing crashed,
# nothing warned, the config just stopped doing what it claimed.
#   1. sandbox.filesystem.denyRead had no ~/.ssh entry — the private key was
#      readable from inside the sandbox (`wc -c < ~/.ssh/id_ed25519` -> 399,
#      exit 0). denyWrite on ~/.ssh/id_* did NOT cover it: write != exfil.
#   2. fallbackModel must stay a short list of non-empty model ids.
#   3. skills.nix used `globs:` in frontmatter — an inert field the loader
#      ignores; the real one is `paths:`. Rules silently never loaded.
#   4. agents.nix must declare model AND effort on every agent, with values
#      the CLI actually accepts.
#
# Runs in `nix flake check`, before any rebuild, from the nix sources.
{ pkgs }:

let
  # homeDirectory is only interpolated into path strings; any absolute path
  # gives a deterministic corpus to assert on.
  settings = import ../home/claude-code/settings.nix { homeDirectory = "/Users/alx"; };
  skills = import ../home/claude-code/skills.nix;
  agents = import ../home/claude-code/agents.nix;
  rules = import ../home/claude-code/rules.nix;

  inherit (pkgs.lib) hasInfix hasSuffix;

  # --- settings.json -------------------------------------------------------
  parsed = builtins.tryEval (builtins.fromJSON settings.settingsJson);
  settingsAttrs = if parsed.success && builtins.isAttrs parsed.value then parsed.value else { };

  denyRead = pkgs.lib.attrByPath [ "sandbox" "filesystem" "denyRead" ] [ ] settingsAttrs;
  fallbackModel = pkgs.lib.attrByPath [ "fallbackModel" ] null settingsAttrs;

  # --- frontmatter --------------------------------------------------------
  # The lines between the opening `---` and the closing one. No takeWhile in
  # this nixpkgs lib, hence the fold.
  frontmatter =
    text:
    let
      lines = pkgs.lib.splitString "\n" text;
      afterOpen = if lines != [ ] && builtins.head lines == "---" then builtins.tail lines else [ ];
      step =
        acc: line:
        if acc.done || line == "---" then
          acc // { done = true; }
        else
          acc // { out = acc.out ++ [ line ]; };
    in
    (builtins.foldl' step {
      out = [ ];
      done = false;
    } afterOpen).out;

  # First value of `field:` in a frontmatter block, or null.
  field =
    name: text:
    let
      hits = builtins.filter (m: m != null) (
        map (l: builtins.match "${name}:[[:space:]]*([^[:space:]].*)" l) (frontmatter text)
      );
    in
    if hits == [ ] then null else builtins.head (builtins.head hits);

  textAttrs = attrs: pkgs.lib.filterAttrs (_: v: builtins.isString v) attrs;

  # --- agents -------------------------------------------------------------
  agentNames = builtins.attrNames (textAttrs agents);
  agentField = name: n: field name agents.${n};

  validEfforts = [
    "low"
    "medium"
    "high"
    "xhigh"
    "max"
  ];
  validPermissionModes = [
    "default"
    "acceptEdits"
    "auto"
    "dontAsk"
    "bypassPermissions"
    "plan"
    "manual"
  ];
  validMemories = [
    "user"
    "project"
    "local"
  ];

  agentsMissingModel = builtins.filter (n: agentField "model" n == null) agentNames;
  agentsMissingEffort = builtins.filter (n: agentField "effort" n == null) agentNames;
  agentsBadEffort = builtins.filter (
    n:
    let
      v = agentField "effort" n;
    in
    v != null && !(builtins.elem v validEfforts)
  ) agentNames;
  agentsBadPermissionMode = builtins.filter (
    n:
    let
      v = agentField "permissionMode" n;
    in
    v != null && !(builtins.elem v validPermissionModes)
  ) agentNames;
  agentsBadMemory = builtins.filter (
    n:
    let
      v = agentField "memory" n;
    in
    v != null && !(builtins.elem v validMemories)
  ) agentNames;

  # --- rules --------------------------------------------------------------
  ruleNames = builtins.attrNames (textAttrs rules);
  rulesWithoutPaths = builtins.filter (n: field "paths" rules.${n} == null) ruleNames;

  # --- skills -------------------------------------------------------------
  skillsCorpus = builtins.concatStringsSep "\n" (builtins.attrValues (textAttrs skills));

  # Each entry fails on its own, with what broke and why it matters.
  assertions = [
    {
      name = "A1 settings: JSON parses";
      ok = parsed.success && builtins.isAttrs parsed.value;
      msg = "settings.nix settingsJson is not parseable JSON — the whole ~/.claude/settings.json merge is garbage, every permission and sandbox rule below is unenforced";
    }
    {
      name = "A1 sandbox: denyRead covers ~/.ssh";
      ok = builtins.any (e: builtins.isString e && hasSuffix "/.ssh" e) denyRead;
      msg = "sandbox.filesystem.denyRead has no entry ending in /.ssh — the SSH private key becomes readable from inside the sandbox (verified: `wc -c < ~/.ssh/id_ed25519` returned 399, exit 0), i.e. one Bash call can exfiltrate it; denyWrite on ~/.ssh/id_* does not stop a read";
    }
    {
      name = "A2 sandbox: denyRead keeps its historic secret paths";
      ok =
        builtins.any (e: builtins.isString e && hasSuffix "/.aws/credentials" e) denyRead
        && builtins.any (e: builtins.isString e && hasInfix "gnupg/private-keys-v1.d" e) denyRead
        && builtins.elem "**/.env" denyRead;
      msg = "sandbox.filesystem.denyRead lost one of .aws/credentials, gnupg/private-keys-v1.d, **/.env — adding the ~/.ssh entry must not shadow the pre-existing secret paths";
    }
    {
      name = "A3 settings: fallbackModel is a short list of model ids";
      ok =
        fallbackModel != null
        && builtins.isList fallbackModel
        && builtins.length fallbackModel <= 3
        && builtins.all (m: builtins.isString m && m != "") fallbackModel;
      msg = "fallbackModel is missing, not a list, longer than 3, or holds a non-string/empty id — a bad chain means no usable fallback when the default model is saturated";
    }
    {
      name = "A4 skills: no inert `globs:` frontmatter field";
      ok = !(hasInfix "globs:" skillsCorpus);
      msg = "skills.nix uses `globs:` in frontmatter — the loader ignores that field entirely (the documented one is `paths:`), so the scoped content silently never loads";
    }
    {
      name = "A5 agents: every agent declares model and effort";
      ok = agentsMissingModel == [ ] && agentsMissingEffort == [ ];
      msg =
        "agent(s) without `model:`: "
        + (if agentsMissingModel == [ ] then "none" else builtins.concatStringsSep ", " agentsMissingModel)
        + " | without `effort:`: "
        + (
          if agentsMissingEffort == [ ] then "none" else builtins.concatStringsSep ", " agentsMissingEffort
        )
        + " — an agent with no explicit model inherits the session model (banned: a haiku-class task then burns opus quota), and no explicit effort loses the depth tiering";
    }
    {
      name = "A5 agents: effort values are in {low, medium, high, xhigh, max}";
      ok = agentsBadEffort == [ ];
      msg =
        "agent(s) with an unknown `effort:` value: "
        + builtins.concatStringsSep ", " agentsBadEffort
        + " — an unparsed value is dropped, so the agent silently runs at the default depth";
    }
    {
      name = "A6 agents: permissionMode and memory values stay valid";
      ok = agentsBadPermissionMode == [ ] && agentsBadMemory == [ ];
      msg =
        "agent(s) with an invalid `permissionMode:`: "
        + (
          if agentsBadPermissionMode == [ ] then
            "none"
          else
            builtins.concatStringsSep ", " agentsBadPermissionMode
        )
        + " | invalid `memory:`: "
        + (if agentsBadMemory == [ ] then "none" else builtins.concatStringsSep ", " agentsBadMemory)
        + " — an unrecognised permissionMode falls back to the strictest/default mode and the agent stalls on prompts it cannot answer";
    }
    {
      name = "A7 rules: every rule ships a `paths:` frontmatter";
      ok = rulesWithoutPaths == [ ];
      msg =
        "rule(s) with no `paths:` in frontmatter: "
        + builtins.concatStringsSep ", " rulesWithoutPaths
        + " — without it the rule is either never loaded or loaded at every launch, which is exactly the context bloat rules/ exists to avoid";
    }
  ];

  failures = builtins.filter (a: !a.ok) assertions;

  fail = msg: throw "claude-config: ${msg}";

in
pkgs.runCommand "claude-config-check" { } (
  if failures != [ ] then
    fail (
      "${toString (builtins.length failures)} broken invariant(s):\n"
      + builtins.concatStringsSep "\n" (map (a: "  - ${a.name}: ${a.msg}") failures)
    )
  else
    ''
      echo "claude-config: ${toString (builtins.length assertions)} invariants, ${toString (builtins.length agentNames)} agents, ${toString (builtins.length ruleNames)} rules — OK"
      touch $out
    ''
)
