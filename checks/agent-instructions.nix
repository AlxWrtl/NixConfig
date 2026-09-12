# Le tronc partagé atteint-il RÉELLEMENT les deux sorties ?
#
# Ce dépôt a déjà produit deux mécanismes parfaitement en place et parfaitement
# inertes. Un tronc commun est le candidat idéal au même sort : `claude-md.nix`
# et `agents-md.nix` peuvent cesser de le splicer sans qu'aucun build ne bouge,
# et les deux documents repartent en dérive silencieuse — exactement l'état que
# le refactor prétend fermer. Sans cette garde, on DÉPLACE la dérive au lieu de
# la supprimer.
#
# Les sept assertions se lisent comme une seule phrase : le tronc arrive entier
# (G1), une seule fois (G2), rien d'autre ne s'invite (G3), rien de ce que Codex
# n'a pas n'est nommé (G4), la seule divergence légitime reste épinglée (G5), le
# budget de contexte tient (G6), et le bloc retiré ne revient pas (G7).
#
# CE QUI EST COMPARÉ EST RENDU, PAS SOURCE. Les assertions portent sur
# `claudeMdGlobal` et `agentsMd` tels que le modèle les recevra, pas sur le
# texte des modules : un tronc importé mais jamais interpolé passerait une
# comparaison de sources et échoue ici.
#
# Tourne dans `nix flake check`, avant tout rebuild, depuis les sources nix.
{ pkgs }:

let
  lib = pkgs.lib;

  shared = import ../home/claude-code/agent-instructions.nix;
  claudeMd = import ../home/claude-code/claude-md.nix;
  agentsMdMod = import ../home/codex/agents-md.nix;
  rules = import ../home/claude-code/rules.nix;

  claudeOut = claudeMd.claudeMdGlobal;
  codexOut = agentsMdMod.agentsMd;

  # `deltaSections` n'existe pas encore des deux côtés. Un accès nu lèverait
  # une trace nix au lieu d'une assertion rouge lisible, et une trace ne dit
  # pas QUOI réparer : défaut explicite, puis assertion sur le défaut.
  deltaOf = mod: lib.attrByPath [ "deltaSections" ] null mod;
  claudeDelta = deltaOf claudeMd;
  codexDelta = deltaOf agentsMdMod;

  outputs = [
    {
      label = "claudeMdGlobal";
      text = claudeOut;
      delta = claudeDelta;
    }
    {
      label = "agentsMd";
      text = codexOut;
      delta = codexDelta;
    }
  ];

  # ------------------------------------------------------------- extracteurs
  splitLines = lib.splitString "\n";

  # Ancré en début de ligne : le titre de niveau 1 (`# Codex — …`) ne doit pas
  # être ramassé, et builtins.match compare la ligne ENTIÈRE, donc `# X` ne
  # peut pas satisfaire `## (.*)`.
  headingsOf =
    text:
    builtins.filter (x: x != null) (
      map (
        l:
        let
          m = builtins.match "## (.*)" l;
        in
        if m == null then null else builtins.head m
      ) (splitLines text)
    );

  sectionNames = builtins.map (s: s.name) shared.trunkSections;

  # --------------------------------------------------------------------- G0
  # G1..G7 itèrent `trunkSections`. Une liste vide rend `concatMap` == [ ] et
  # les rend TOUTES vertes pendant que le tronc n'atteint personne ; pire,
  # `lib.hasInfix "" text` est vrai partout, donc vider le `body` d'une seule
  # section est invisible pour les sept. On prouve la liste avant de s'en
  # servir.
  isBlank = s: builtins.match "[[:space:]]*" s != null;
  emptyBodies = builtins.map (s: s.name) (builtins.filter (s: isBlank s.body) shared.trunkSections);
  # `map` rend déjà des CHAÎNES : filtrer avec `s.name` ici lèverait
  # « expected a set but found a string ». Le prédicat porte sur la chaîne.
  emptyNames = builtins.filter isBlank (builtins.map (s: s.name) shared.trunkSections);
  trunkEmpty = shared.trunkSections == [ ];

  # ------------------------------------------------------------------ G1/G2
  # Les corps VIDES sont le domaine de G0, pas le nôtre, et il faut les écarter
  # ici pour une raison mécanique : `lib.hasInfix` construit `".*''${body}.*"`,
  # donc un body vide produit la regex `.*.*` que le moteur de nix REFUSE — le
  # check mourait alors sur une trace nix au lieu de nommer la section fautive.
  # Mesuré en vidant `Code Quality` : `error: invalid regular expression '.*.*'`.
  # Partage net : G0 dit « ce corps est vide », G1 dit « ce corps non vide
  # n'arrive pas dans une des sorties ». Ensemble ils couvrent tout.
  bodiedSections = builtins.filter (s: !(isBlank s.body)) shared.trunkSections;
  missingBodies = lib.concatMap (
    o:
    map (s: "${o.label}/${s.name}") (builtins.filter (s: !(lib.hasInfix s.body o.text)) bodiedSections)
  ) outputs;

  duplicatedHeadings = lib.concatMap (
    o:
    let
      rendered = headingsOf o.text;
      count = n: builtins.length (builtins.filter (h: h == n) rendered);
      bad = builtins.filter (n: count n != 1) rendered;
    in
    map (n: "${o.label}/## ${n} x${toString (count n)}") bad
  ) outputs;

  # --------------------------------------------------------------------- G3
  declaredFor =
    o: if o.delta == null then null else sectionNames ++ (builtins.map (s: s.name) o.delta);

  headingMismatch = builtins.filter (
    o:
    let
      declared = declaredFor o;
    in
    declared == null || headingsOf o.text != declared
  ) outputs;

  mismatchReport = builtins.concatStringsSep " ; " (
    map (
      o:
      if o.delta == null then
        "${o.label}: le module n'exporte pas `deltaSections`"
      else
        "${o.label}: rendu [${builtins.concatStringsSep ", " (headingsOf o.text)}] vs déclaré [${builtins.concatStringsSep ", " (declaredFor o)}]"
    ) headingMismatch
  );

  # --------------------------------------------------------------------- G4
  absentMechanisms = [
    "mcp__enquire"
    "mcp__graphify"
    "ralph-loop"
    "code-review"
    "WebFetch"
    "WebSearch"
  ];
  namedToCodex = builtins.filter (n: lib.hasInfix n codexOut) absentMechanisms;
  namedInTrunk = builtins.filter (n: lib.hasInfix n shared.trunk) absentMechanisms;

  # --------------------------------------------------------------------- G5
  confidenceNeedle = "Rate confidence before writing nix";
  confidenceInline = lib.hasInfix confidenceNeedle codexOut;
  confidenceInRules = lib.hasInfix confidenceNeedle rules.ruleNix;
  # Le corps reste interdit dans Claude, mais ne suffit pas : une copie peut
  # garder le titre et paraphraser la règle. Le préfixe attrape donc aussi
  # `Confidence Gate (nix)` et toute variante suffixée.
  confidenceInClaude = lib.hasInfix confidenceNeedle claudeOut;
  confidenceHeadingInClaude = builtins.any (lib.hasPrefix "Confidence Gate") (headingsOf claudeOut);

  # --------------------------------------------------------------------- G6
  lineBudget = 100;
  overBudget = builtins.filter (o: builtins.length (splitLines o.text) >= lineBudget) outputs;

  # --------------------------------------------------------------------- G7
  projectMapIn = builtins.filter (o: lib.hasInfix "Project Map" o.text) outputs;

  labels = xs: builtins.concatStringsSep ", " (map (o: o.label) xs);

  assertions = [
    {
      name = "G0 guard: `trunkSections` is non-empty and every section carries a name and a body";
      ok = !trunkEmpty && emptyBodies == [ ] && emptyNames == [ ];
      msg =
        "liste vide: "
        + (if trunkEmpty then "OUI" else "non")
        + " | `body` vide ou blanc: "
        + (if emptyBodies == [ ] then "aucun" else builtins.concatStringsSep ", " emptyBodies)
        + " | `name` vide: ${toString (builtins.length emptyNames)}"
        + " — les sept assertions qui suivent itèrent cette liste : vide, `concatMap` rend [ ] et les sept passent pendant que le tronc n'atteint aucune des deux sorties. Le `body` est pire : G1 teste `lib.hasInfix s.body o.text`, et `hasInfix \"\" text` est vrai pour N'IMPORTE quel texte, donc un body vidé est invisible partout. Un check qui parcourt une liste sans d'abord prouver qu'elle n'est pas vide est la forme exacte d'une assertion qui ne peut pas échouer — ce dépôt l'a déjà livrée deux fois (C7, réparé par C7b ; deux checks d'absence qui ne lisaient aucun fichier)";
    }
    {
      name = "G1 trunk: every shared section body reaches BOTH outputs";
      ok = missingBodies == [ ];
      msg =
        "section(s) absente(s) du rendu: "
        + builtins.concatStringsSep ", " missingBodies
        + " — c'est LE point du refactor. Un tronc importé mais pas interpolé laisse les deux documents repartir en dérive sans qu'un seul build bouge, et la dérive est invisible parce qu'aucune des deux sorties n'est fausse prise isolément";
    }
    {
      name = "G2 outputs: each rendered heading name appears EXACTLY once per output";
      ok = duplicatedHeadings == [ ];
      msg =
        "titre(s) hors compte: "
        + builtins.concatStringsSep ", " duplicatedHeadings
        + " — chaque nom de titre rendu, tronc ou delta, doit être unique. Une copie coûte double : elle consomme du contexte à chaque session ET elle rend une source éditable sans effet, donc la prochaine correction ne s'applique qu'à moitié";
    }
    {
      name = "G3 outputs: headings equal the declared trunk-plus-delta list, in order";
      ok = headingMismatch == [ ];
      msg =
        mismatchReport
        + " — chaque module doit exporter `deltaSections` (liste de { name; body; }) et son rendu doit s'y réduire. Sans ça une section peut être ajoutée directement dans la chaîne finale, déclarée nulle part, guardée par rien : c'est la forme exacte qu'avait la dérive qu'on ferme";
    }
    {
      name = "G4 codex: no mechanism named that Codex does not have";
      ok = namedToCodex == [ ] && namedInTrunk == [ ];
      msg =
        "nommé(s) à Codex: "
        + (if namedToCodex == [ ] then "aucun" else builtins.concatStringsSep ", " namedToCodex)
        + " | nommé(s) dans le tronc: "
        + (if namedInTrunk == [ ] then "aucun" else builtins.concatStringsSep ", " namedInTrunk)
        + " — une instruction qui nomme un mécanisme absent n'est pas neutre : le modèle la lit, cherche l'outil, et dépense le tour à échouer. Mesuré sur cet hôte, un AGENTS.md truffé d'outils Claude produisait exactement ça. Le tronc est vérifié à part pour qu'il ne puisse jamais servir de canal de contrebande";
    }
    {
      name = "G5 divergence: the nix Confidence Gate stays Codex-inline only";
      ok = confidenceInline && confidenceInRules && !confidenceInClaude && !confidenceHeadingInClaude;
      msg =
        "inline dans agentsMd: "
        + (if confidenceInline then "oui" else "NON")
        + " | dans rules.nix ruleNix: "
        + (if confidenceInRules then "oui" else "NON")
        + " | corps recopié dans claudeMdGlobal: "
        + (if confidenceInClaude then "PRÉSENTE" else "absente")
        + " | titre Confidence Gate dans claudeMdGlobal: "
        + (if confidenceHeadingInClaude then "PRÉSENT" else "absent")
        + " — cette asymétrie est DÉLIBÉRÉE et c'est la seule du lot : Claude charge la règle depuis `~/.claude/rules/` à l'ouverture d'un `.nix`, Codex n'a pas de `rules/` et doit la porter en permanence. Une passe d'« harmonisation » qui la supprime d'un côté ou la duplique de l'autre doit rougir ici, sinon elle coûte la règle à Codex ou du contexte permanent à Claude";
    }
    {
      name = "G6 budget: each rendered output stays under ${toString lineBudget} lines";
      ok = overBudget == [ ];
      msg =
        "au-dessus du budget: "
        + labels overBudget
        + " — `claude-md.nix` porte cette règle en commentaire ligne 1 depuis toujours et rien ne l'appliquait. Ces lignes sont payées dans CHAQUE session des deux agents, jamais une fois : un dépassement n'est pas une dette, c'est un prélèvement permanent";
    }
    {
      name = "G7 outputs: `Project Map` is gone from both";
      ok = projectMapIn == [ ];
      msg =
        "`Project Map` encore présent dans: "
        + labels projectMapIn
        + " — le bloc a été retiré de CLAUDE.md comme dérivable de l'arborescence et laissé dans AGENTS.md par le MÊME lot. Une carte de chemins tenue à la main ne peut qu'être fausse en silence, et elle l'était (`home/Codex/` n'a jamais existé)";
    }
  ];

  failures = builtins.filter (a: !a.ok) assertions;

  fail = msg: throw "agent-instructions: ${msg}";

in
pkgs.runCommand "agent-instructions-check" { } (
  if failures != [ ] then
    fail (
      "${toString (builtins.length failures)} broken invariant(s):\n"
      + builtins.concatStringsSep "\n" (map (a: "  - ${a.name}: ${a.msg}") failures)
    )
  else
    ''
      echo "agent-instructions: ${toString (builtins.length assertions)} invariants, ${toString (builtins.length shared.trunkSections)} shared sections, 2 outputs — OK"
      touch $out
    ''
)
