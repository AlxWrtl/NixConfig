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

  voice = pkgs.lib.attrByPath [ "voice" ] null settingsAttrs;
  voiceOk =
    voice != null
    && builtins.isAttrs voice
    && (voice.enabled or null) == true
    && builtins.elem (voice.mode or null) [
      "hold"
      "toggle"
    ]
    && builtins.isBool (voice.autoSubmit or null);

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

  # Le corpus des SKILL.md vient du MANIFESTE, pas des attributs aplatis de
  # skills.nix ci-dessus : `textAttrs skills` ramasse aussi les `steps/*.md`
  # d'apex, qui n'ont légitimement AUCUN frontmatter. Les itérer ferait échouer
  # A10 sur des fichiers sains. Le manifeste est la seule source qui dise quel
  # texte part vers quel chemin déployé ; on ne garde que les `SKILL.md`, les
  # seuls que le loader parse comme frontmatter. Import nu, sans argument :
  # c'est documenté en tête du manifeste et les autres checks en dépendent.
  skillMds = builtins.concatMap (
    s:
    map (f: {
      inherit (s) name;
      inherit (f) text;
    }) (builtins.filter (f: f.path == "SKILL.md") s.files)
  ) (import ../home/claude-code/skills-manifest.nix).manifest;

  # Même prédicat que checks/codex-skills.nix:273, mot pour mot : un frontmatter
  # doit ouvrir sur `---` en colonne 0. Une seconde orthographe de la même idée
  # (regex, helper lib, paire leading/stripLead) divergerait du côté Codex.
  skillsBadFrontmatter = builtins.filter (f: builtins.substring 0 4 f.text != "---\n") skillMds;

  # --- A11: le pied de contrat --------------------------------------------
  # Même corpus que A10, et pour la même raison : seuls les SKILL.md portent
  # un contrat. Titres bornés par des sauts de ligne des DEUX côtés, sinon
  # `## Scope` se laisserait satisfaire par `## Scoped tools` et la garde ne
  # garderait plus rien.
  contractHeadings = [
    "\n## Input/Output Contract\n"
    "\n## Scope\n"
    "\n## Handoffs\n"
  ];

  # caveman et cavemem sont des bascules de mode de sortie (38 et 31 lignes)
  # dont tout le contrat tient déjà dans la `description` : ce qu'elles font,
  # quand se déclencher, quand s'arrêter, ce pour quoi elles ne sont PAS. Un
  # bloc de contrat y serait du cérémonial. Liste tenue à la main, donc gardée
  # dans les deux sens (cf. C10 / indentedFrontmatter dans codex-skills.nix) :
  # une exemption ne peut pas échouer toute seule, elle ne peut que devenir
  # fausse en silence, et celle que personne ne relit devient un trou.
  footerExempt = [
    "caveman"
    "cavemem"
  ];

  skillsMissingFooter = builtins.filter (
    f: !(builtins.elem f.name footerExempt) && builtins.any (h: !(hasInfix h f.text)) contractHeadings
  ) skillMds;

  # Entrée MORTE : la skill exemptée a fini par se doter d'un pied de contrat,
  # ou a disparu du manifeste (renommée, retirée). Dans les deux cas la liste
  # ne décrit plus rien et le prochain lecteur lui fait confiance.
  deadFooterExempt = builtins.filter (
    n:
    let
      hits = builtins.filter (f: f.name == n) skillMds;
    in
    hits == [ ] || builtins.any (f: builtins.any (h: hasInfix h f.text) contractHeadings) hits
  ) footerExempt;

  # --- scrapling: one version, pinned in two files -------------------------
  # activation.nix installs an exact pin; the skill TEXT repeats that version
  # in its install instructions and states its measurements were taken on it.
  # Bump one and forget the other and the skill teaches a wrong command with a
  # green build — the silent-failure class this file exists to close.
  # Plain string ops only — no regex. `builtins.split` on a bracketed literal
  # is not portable here (nix rejected `scrapling\[shell\]==...` outright).
  activationSrc = builtins.readFile ../home/claude-code/activation.nix;
  afterMarker =
    marker: text:
    let
      parts = pkgs.lib.splitString marker text;
    in
    if builtins.length parts < 2 then [ ] else builtins.tail parts;

  # activation.nix:  SCRAPLING_VERSION="0.4.15"
  scraplingPin =
    let
      tails = afterMarker ''SCRAPLING_VERSION="'' activationSrc;
    in
    if tails == [ ] then null else builtins.head (pkgs.lib.splitString ''"'' (builtins.head tails));

  # skill text:  uv tool install "scrapling[shell]==0.4.15"
  scraplingSkill = skills.skillScrapling or "";
  scraplingSkillPins = map (
    t: builtins.head (pkgs.lib.splitString ''"'' (builtins.head (pkgs.lib.splitString " " t)))
  ) (afterMarker "scrapling[shell]==" scraplingSkill);
  scraplingDrift = builtins.filter (v: v != scraplingPin) scraplingSkillPins;

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
      name = "A1b sandbox: the SSH PUBLIC key stays readable";
      ok = builtins.any (e: builtins.isString e && hasSuffix ".pub" e) (
        pkgs.lib.attrByPath [ "sandbox" "filesystem" "allowRead" ] [ ] settingsAttrs
      );
      msg = "sandbox.filesystem.allowRead has no *.pub entry — the denyRead on ~/.ssh also swallows the PUBLIC key, and git signs commits over SSH (gpg.format=ssh, signingkey ~/.ssh/id_ed25519.pub), so EVERY commit inside the sandbox fails with `Couldn't load public key`. This regressed once, in PR #101. A public key is public; only the private one must stay denied";
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
    {
      name = "A8 settings: voice block is complete";
      ok = voiceOk;
      msg = "settings.nix `voice` is missing, or one of: enabled != true, mode not in {hold, toggle}, autoSubmit not a boolean — la dictée /voice dépend entièrement de ce bloc, et la clé legacy `voiceEnabled` est supprimée du live par la passe jq d'activation (del(.voiceEnabled)), donc il n'y a plus de filet : si ce bloc saute, la dictée meurt SILENCIEUSEMENT au prochain rebuild, sans erreur ni warning";
    }
    {
      name = "A9 scrapling: skill version matches the activation pin";
      ok = scraplingPin != null && scraplingSkillPins != [ ] && scraplingDrift == [ ];
      msg =
        "activation.nix pins SCRAPLING_VERSION="
        + (if scraplingPin == null then "<not found>" else scraplingPin)
        + " but the scrapling skill instructs "
        + (
          if scraplingSkillPins == [ ] then
            "<no scrapling[shell]==X.Y.Z found in the skill>"
          else
            builtins.concatStringsSep ", " (map (v: "scrapling[shell]==" + v) scraplingSkillPins)
        )
        + " — the skill tells the agent which command to run and claims its measurements were taken on that version; bump one without the other and it teaches a wrong install with a green build and no signal";
    }
    {
      name = "A10 skills: every SKILL.md frontmatter opens at column 0";
      ok = skillsBadFrontmatter == [ ];
      msg =
        "skill(s) whose text does not start with `---` on line 1: "
        + builtins.concatStringsSep ", " (map (f: f.name) skillsBadFrontmatter)
        + " — a frontmatter that does not parse costs the WHOLE skill, not one field: the loader falls back to the directory name and takes the first body line as the description, so the model routes on garbage, and `allowed-tools`, `model` and `disable-model-invocation` silently stop applying. The mechanism is nix itself: a `''…''` string is dedented by the MINIMUM common indentation across ALL its lines, so one line indented shallower than the body shifts every other line to the right, frontmatter included — fix the shallow line, not the `---`";
    }
    {
      name = "A11 skills: every SKILL.md keeps its contract footer";
      ok = skillsMissingFooter == [ ] && deadFooterExempt == [ ];
      msg =
        "skill(s) missing `## Input/Output Contract`, `## Scope` or `## Handoffs`: "
        + builtins.concatStringsSep ", " (map (f: f.name) skillsMissingFooter)
        + " | listed in footerExempt but now carrying a footer, or gone from the manifest: "
        + builtins.concatStringsSep ", " deadFooterExempt
        + " — a skill that ships without its footer ships without a contract: the model gets no statement of what the skill expects and produces, no boundary saying when NOT to use it, and no routing to the skill that should take over, so it improvises all three. The mechanism is nix again: a `''` block closed too early ends the attribute mid-document and the trailing sections land inside the NEXT attribute — it parses, A10 still sees a frontmatter at column 0, C1 still maps every attribute to a manifest entry, the 500-line ceiling is still met, and the text is simply deployed to the wrong file. That is how scrapling lost its guardrails and its contract with an all-green build. A DEAD exemption is the same failure one level up: a hand-maintained list cannot fail loudly, only be silently wrong";
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
