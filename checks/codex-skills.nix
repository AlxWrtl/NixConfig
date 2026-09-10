# Non-regression check for the Codex skills generated under home/codex/.
#
# THE ONE THIS FILE EXISTS FOR: `~/.agents/skills/` held a HAND-KEPT copy of
# the skill tree for four months. Every directory was present, correctly named
# and stale: the apex skill there advertised a flag table removed in May, and
# the obsidian skill named a vault path that had since moved. Nothing was ever
# red, because a hand-maintained list cannot fail — it can only be incomplete,
# and an incomplete list of instructions reads exactly like a complete one. The
# repair is that both agents now derive their files from ONE manifest; C1 below
# is what makes a third hand-kept list impossible, by demanding a bijection
# between the prose attributes of `home/claude-code/skills.nix` and the entries
# of `home/claude-code/skills-manifest.nix`. Add a skill and forget the
# manifest, or leave an entry behind after deleting the prose, and the build
# says so.
#
# WHY C5 IS THE MOST IMPORTANT ASSERTION HERE. The translation to Codex is
# expressed as `from`/`to` pairs whose `from` is copied VERBATIM out of the
# Claude text (see the header of home/codex/skills-translate.nix). A `from`
# that no longer matches is NOT an error in nix: `replaceStrings` simply
# returns the string unchanged. So a reworded upstream sentence turns a careful
# override into a no-op that still reads perfectly in review — the anchor is
# there, the replacement is there, the reason is there, and the untranslated
# passage ships. That is the same failure as the fossil tree, one anchor at a
# time. C5 (anchor present), C6 (present exactly once) and C7 (nothing the
# table names survives translation) are the three sides of it.
#
# The rest guards the properties that are silent when they break:
#   - the `force` rule, computed and never stored (C2)
#   - substitution rules that are neither dead (C4) nor unbounded (C3): the
#     day someone writes `corpus` in a skill, an unbounded `opus` rule rewrites
#     the middle of that word and no build notices
#   - frontmatter (C8, C8b, C10): a frontmatter that does not parse costs the
#     WHOLE skill — the scanner lists it with a garbage description or not at
#     all, and says nothing
#   - the description budget Codex documents (C9)
#   - the two removals this host depends on: the anti-recursion clause (C11)
#     and the external-verify flag (C12)
#
# Runs in `nix flake check`, before any rebuild, from the nix sources. The
# builder then compares every file inside the installed derivations to the text
# asserted above, so the check cannot be green about a text the module does not
# actually deploy.
{ pkgs }:

let
  inherit (pkgs) lib;

  skillsSrc = import ../home/claude-code/skills.nix;
  manifest = (import ../home/claude-code/skills-manifest.nix).manifest;
  codexSkills = import ../home/codex/skills.nix { inherit pkgs lib; };
  tr = codexSkills.translation;

  # --- helpers -------------------------------------------------------------
  # Occurrence counting WITHOUT a regex, on purpose. `lib.splitString` and
  # `builtins.match` both compile the needle as a POSIX regex, and the anchors
  # in this corpus are whole paragraphs full of `(`, `{`, `*`, `|` and `&` —
  # nix rejects several of those even escaped ("invalid regular expression").
  # `replaceStrings` is the same primitive the translation itself uses, so this
  # counts exactly the occurrences a translation would rewrite.
  occ =
    needle: text:
    if needle == "" then
      0
    else
      (
        builtins.stringLength text - builtins.stringLength (builtins.replaceStrings [ needle ] [ "" ] text)
      )
      / builtins.stringLength needle;

  has = needle: text: occ needle text > 0;

  linesOf = lib.splitString "\n";

  leading =
    l:
    let
      len = builtins.stringLength l;
      go = i: if i < len && builtins.substring i 1 l == " " then go (i + 1) else i;
    in
    go 0;
  stripLead = l: builtins.substring (leading l) (builtins.stringLength l) l;

  # Lines matched at COLUMN 0: `builtins.match` anchors on the whole string, so
  # an indented `name:` does not match — which is the point of C8.
  linesStartingWith =
    key: text: builtins.filter (l: builtins.match "${key}:.*" l != null) (linesOf text);

  sortUniq =
    xs:
    builtins.sort builtins.lessThan (
      builtins.attrNames (
        builtins.listToAttrs (
          map (x: {
            name = x;
            value = true;
          }) xs
        )
      )
    );

  join = builtins.concatStringsSep ", ";
  showList = xs: if xs == [ ] then "none" else join xs;

  # --- the three corpora ---------------------------------------------------
  srcFiles = builtins.concatMap (
    skill:
    map (file: {
      skill = skill.name;
      inherit (file) path text;
    }) skill.files
  ) manifest;

  # What the module actually installs, not a second translation of our own.
  translated = codexSkills.translatedTexts;

  srcCorpus = builtins.concatStringsSep "\n" (map (f: f.text) srcFiles);

  idOf = f: "${f.skill}/${f.path}";
  srcTextOf =
    skill: file:
    let
      hits = builtins.filter (f: f.skill == skill && f.path == file) srcFiles;
    in
    if hits == [ ] then null else (builtins.head hits).text;

  skillMdSrc = builtins.filter (f: f.path == "SKILL.md") srcFiles;
  skillMdTr = builtins.filter (f: f.path == "SKILL.md") translated;

  # --- C1: bijection prose attribute <-> manifest entry --------------------
  stringAttrs = builtins.filter (n: builtins.isString skillsSrc.${n}) (builtins.attrNames skillsSrc);

  # By TEXT, never by file name: fourteen entries are called SKILL.md, so a
  # name-based comparison would pair the wrong ones and stay green.
  attrHits = n: builtins.filter (f: f.text == skillsSrc.${n}) srcFiles;
  fileHits = f: builtins.filter (n: skillsSrc.${n} == f.text) stringAttrs;

  strayAttrs = builtins.filter (n: builtins.length (attrHits n) != 1) stringAttrs;
  strayFiles = builtins.filter (f: builtins.length (fileHits f) != 1) srcFiles;

  installedRoots = builtins.attrNames codexSkills.files;

  # --- C2: `force` is a rule, not data -------------------------------------
  forceRule = path: baseNameOf path == "SKILL.md" || path == "eval-suite.json";
  forced = builtins.filter (f: forceRule f.path) srcFiles;
  forcedUnderSteps = builtins.filter (f: lib.hasPrefix "steps/" f.path) forced;
  claudeSrc = builtins.readFile ../home/claude-code.nix;
  forceExpr = ''force = baseNameOf file.path == "SKILL.md" || file.path == "eval-suite.json";'';
  storedForce = builtins.any (f: f ? force) (builtins.concatMap (s: s.files) manifest);

  # --- C3 / C4: the substitution table against the SOURCE corpus -----------
  wordChars = builtins.genList (
    i: builtins.substring i 1 "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
  ) 64;

  # The character that really FOLLOWS (resp. precedes) an occurrence, so a
  # `from` that is already delimited by its own text — `Agent tool`,
  # `~/.claude/CLAUDE.md` — is not reported for the space or the backtick
  # around it. Only a rule that could eat into a longer word is.
  gluedAfter = from: builtins.filter (c: has (from + c) srcCorpus) wordChars;
  gluedBefore = from: builtins.filter (c: has (c + from) srcCorpus) wordChars;

  unbounded = builtins.filter (
    r: gluedAfter r.from != [ ] || gluedBefore r.from != [ ]
  ) tr.substitutions;
  showUnbounded = map (
    r: "`${r.from}` glued to [${showList (gluedBefore r.from ++ gluedAfter r.from)}]"
  ) unbounded;

  deadRules = builtins.filter (r: !(has r.from srcCorpus)) tr.substitutions;

  # --- C5 / C6: override anchors against their own source file -------------
  overrideStats = map (o: {
    id = "${o.skill}/${o.file}";
    inherit (o) from;
    src = srcTextOf o.skill o.file;
  }) tr.overrides;

  noSuchFile = builtins.filter (o: o.src == null) overrideStats;
  inertAnchors = builtins.filter (o: o.src != null && occ o.from o.src == 0) overrideStats;
  multiAnchors = builtins.filter (o: o.src != null && occ o.from o.src > 1) overrideStats;
  # First line of an anchor, enough to find it in the source without printing
  # a whole paragraph into the build log.
  firstLine = s: builtins.head (linesOf s);
  showAnchor = o: "${o.id}: `${firstLine o.from}…`";

  # --- C7: nothing the table names survives --------------------------------
  # NARROW, and it should be read as narrow. `replaceStrings` does one
  # left-to-right pass and never rescans what it wrote, and no `to` in the
  # table currently contains another `from`, so on today's table this is close
  # to vacuous. What it still catches is the day someone adds a rule whose
  # replacement text carries a term another rule was supposed to remove — the
  # one case where a single pass leaves a survivor. The BROAD version of this
  # question is C7b, which does not consult the table at all.
  survivors = builtins.concatMap (
    f:
    map (r: "${idOf f} still contains `${r.from}`") (
      builtins.filter (r: has r.from f.text) tr.substitutions
    )
  ) translated;

  # --- C7b: the same question asked WITHOUT consulting the table -----------
  # MEASURED HOLE, and the reason this assertion is not a duplicate of C7.
  # Mutation run, 2026-09-10: deleting the `haiku` → `gpt-5.6-luna` rule from
  # `substitutions` left this check GREEN. C7 iterates over the table to decide
  # what must not survive, so a term stops being forbidden the moment its rule
  # is removed — the check derives its question from the very thing it is
  # checking, and cannot see a deletion. C4 catches a rule that matches
  # nothing; nothing caught a rule that is gone.
  #
  # So this list is written out, by hand, on purpose. It is the one place in
  # this file that is allowed to duplicate the table, because independence is
  # exactly what it buys. Keep the two in sync in ONE direction only: a term
  # may live here without a rule (nothing renames it, it simply must not
  # appear), never the reverse.
  forbiddenTerms = [
    "Fable"
    "fable"
    "haiku"
    "sonnet"
    "opus"
    "Opus"
    "Claude Code"
    "TodoWrite"
    "WebSearch"
  ];

  # Word-boundary-ish: a term glued to a letter is another word (`corpus`,
  # `Opusculum`) and is not a leak.
  wordHits =
    term: text:
    let
      parts = lib.splitString term text;
      tails = builtins.tail parts;
      isLetter = c: builtins.match "[A-Za-z]" c != null;
      leaks = builtins.filter (t: t == "" || !(isLetter (builtins.substring 0 1 t))) tails;
    in
    builtins.length leaks;

  # claude-code-meta documents the Claude layer of THIS repo, which Codex
  # edits; naming it there is correct, and `notSubstituted` says so.
  independentSurvivors = builtins.concatMap (
    f:
    map (t: "${idOf f} still contains `${t}`") (
      builtins.filter (t: wordHits t f.text > 0) (
        if f.skill == "claude-code-meta" then
          builtins.filter (t: t != "Claude Code") forbiddenTerms
        else
          forbiddenTerms
      )
    )
  ) translated;

  # --- C8: frontmatter of every translated SKILL.md ------------------------
  # Codex names a skill by this `name:`, NOT by the directory it sits in —
  # measured. So the equality asserted below is repo hygiene rather than a
  # functional requirement: what it buys is that `~/.agents/skills/<dir>` and
  # the name a session prints are the same word, which is what every other
  # check, probe and bug report in this repo assumes.
  valueOf =
    key: text:
    let
      ls = linesStartingWith key text;
      m =
        if ls == [ ] then
          null
        else
          builtins.match "${key}:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*" (builtins.head ls);
    in
    if m == null then null else builtins.head m;

  badFrontmatter = builtins.filter (
    f:
    builtins.substring 0 4 f.text != "---\n"
    || linesStartingWith "name" f.text == [ ]
    || linesStartingWith "description" f.text == [ ]
    || valueOf "name" f.text != f.skill
  ) skillMdTr;
  showFrontmatter =
    f:
    "${idOf f}: starts `${builtins.substring 0 4 f.text}`, name=${
      let
        v = valueOf "name" f.text;
      in
      if v == null then "<absent or not at column 0>" else v
    }, description ${
      if linesStartingWith "description" f.text == [ ] then "<absent or not at column 0>" else "present"
    }";

  # --- C8b: the set of keys normalisation removes --------------------------
  # Top-level keys of the FIRST `---` block, parsed the way stripFrontmatter
  # parses them: a line deeper than the opening marker is a continuation of the
  # key above it (scrapling's `metadata:` has a nested `homepage:`), never a
  # key of its own.
  frontmatterKeys =
    text:
    let
      ls = linesOf text;
      first = if ls == [ ] then "" else builtins.head ls;
      base = leading first;
      step =
        st: l:
        if st.done then
          st
        else if stripLead l == "---" then
          st // { done = true; }
        else if leading l > base then
          st
        else
          let
            m = builtins.match "[[:space:]]*([A-Za-z0-9_-]+):.*" l;
          in
          if m == null then st else st // { keys = st.keys ++ [ (builtins.head m) ]; };
      folded = lib.foldl' step {
        done = false;
        keys = [ ];
      } (if ls == [ ] then [ ] else builtins.tail ls);
    in
    if ls == [ ] || stripLead first != "---" then [ ] else folded.keys;

  srcKeys = sortUniq (builtins.concatMap (f: frontmatterKeys f.text) srcFiles);
  trKeys = sortUniq (builtins.concatMap (f: frontmatterKeys f.text) translated);
  removedKeys = builtins.filter (k: !(builtins.elem k trKeys)) srcKeys;

  # --- C9: the description budget ------------------------------------------
  descLines = builtins.concatMap (f: linesStartingWith "description" f.text) skillMdTr;
  descBudget = lib.foldl' (a: l: a + builtins.stringLength l) 0 descLines;
  descLimit = 8000;

  # --- C10: indentedFrontmatter is symmetric -------------------------------
  isIndentedSrc =
    f:
    let
      first = builtins.head (linesOf f.text);
    in
    stripLead first == "---" && leading first > 0;
  indentedInSrc = map (f: f.skill) (builtins.filter isIndentedSrc skillMdSrc);
  missingException = builtins.filter (n: !(builtins.elem n tr.indentedFrontmatter)) indentedInSrc;
  deadException = builtins.filter (n: !(builtins.elem n indentedInSrc)) tr.indentedFrontmatter;

  # --- C11 / C12 -----------------------------------------------------------
  antiRecursion = "Not for pure questions or research with zero file modification";
  apexDescription =
    let
      hits = builtins.filter (f: f.skill == "apex" && f.path == "SKILL.md") translated;
      ls = if hits == [ ] then [ ] else linesStartingWith "description" (builtins.head hits).text;
    in
    if ls == [ ] then "" else builtins.head ls;

  externalResidue = map (f: idOf f) (
    builtins.filter (f: has "apex-verify-external" f.text) translated
  );
  eFlagRows = builtins.concatMap (
    f:
    map (l: "${idOf f}: ${l}") (
      builtins.filter (l: builtins.substring 0 6 l == "| -e |") (linesOf f.text)
    )
  ) translated;

  # --- the assertions ------------------------------------------------------
  assertions = [
    {
      name = "C1 bijection: every prose attribute is deployed exactly once, every manifest entry comes from one attribute";
      ok =
        strayAttrs == [ ]
        && strayFiles == [ ]
        && builtins.length installedRoots == builtins.length manifest;
      msg =
        "attribute(s) of home/claude-code/skills.nix not deployed by exactly one manifest entry: "
        + showList (map (n: "${n} (${toString (builtins.length (attrHits n))} entries)") strayAttrs)
        + " | manifest entr(ies) whose text is not exactly one attribute: "
        + showList (map (f: "${idOf f} (${toString (builtins.length (fileHits f))} attributes)") strayFiles)
        + " | "
        + toString (builtins.length installedRoots)
        + " installed skill root(s) for "
        + toString (builtins.length manifest)
        + " manifest entr(ies)"
        + " — compared BY TEXT, because fourteen entries are named SKILL.md and a name-based pairing would match the wrong ones and stay green. This is the assertion that makes a third hand-kept list impossible: `~/.agents/skills/` already held one for four months, complete-looking and four months stale. A new skill without a manifest entry, or an entry whose attribute was deleted, lands here";
    }
    {
      name = "C2 force: computed from the file name, never stored, true for exactly the 15 clobbered files";
      ok =
        occ forceExpr claudeSrc == 1
        && !storedForce
        && builtins.length forced == 15
        && builtins.length skillMdSrc == 14
        && forcedUnderSteps == [ ];
      msg =
        "home/claude-code.nix contains the derived rule "
        + toString (occ forceExpr claudeSrc)
        + " time(s) (expected exactly 1: `${forceExpr}`), the manifest "
        + (if storedForce then "STORES a force flag" else "stores none")
        + ", the rule is true for "
        + toString (builtins.length forced)
        + " of the 33 files (expected 15 = 14 SKILL.md + apex/eval-suite.json; found "
        + toString (builtins.length skillMdSrc)
        + " SKILL.md), and "
        + toString (builtins.length forcedUnderSteps)
        + " file(s) under steps/ are forced (expected 0)"
        + " — `force` exists because claudeCodeDesymlinkSkills replaces those files with real copies and home-manager must be allowed to clobber them. Stored as data it becomes one more hand-kept list; derived, it cannot drift. If a file legitimately joins the clobbered set, change the rule in home/claude-code.nix AND this count together";
    }
    {
      name = "C3 substitutions are bounded: no `from` occurs glued to a word character in the source corpus";
      ok = unbounded == [ ];
      msg =
        "unbounded rule(s): "
        + showList showUnbounded
        + " — `replaceStrings` knows nothing about word boundaries, so a rule matching inside a longer word rewrites the middle of it. The day a skill says `corpus`, the `opus` rule turns it into `cgpt-5.6` and every build stays green. FIX: delimit the rule the way `Agent tool` and `` `Agent` `` are delimited — carry the surrounding character (backtick, space, `: `) in BOTH `from` and `to` — or, if the collision is one word, add an override that breaks the token at that site (O9B does exactly that)";
    }
    {
      name = "C4 no dead substitution: every `from` still occurs in the source corpus";
      ok = deadRules == [ ];
      msg =
        "rule(s) matching nothing: "
        + showList (map (r: "`${r.from}` → `${r.to}`") deadRules)
        + " — a rule that matches nothing is not harmless, it is a rename someone believes is happening. Either the upstream text dropped the term (delete the rule, and check the passage was not merely reworded into a form the rule no longer sees) or the term moved to a spelling this table does not cover";
    }
    {
      name = "C5 no inert override: every anchor occurs in the source text of the file it names";
      ok = noSuchFile == [ ] && inertAnchors == [ ];
      msg =
        "override(s) naming a {skill, file} the manifest does not have: "
        + showList (map (o: o.id) noSuchFile)
        + " | override(s) whose anchor matches NOTHING in that file: "
        + showList (map showAnchor inertAnchors)
        + " — THE assertion of this file. `replaceStrings` returns the text unchanged when a `from` does not match: no error, no warning, and the override still reads perfectly in review. The untranslated Claude passage ships, and the reason it was written down is the reason it will not be noticed. FIX: open the file named above, copy the current wording VERBATIM into `from` (indentation included — these are `''` blocks and nix strips the common indent), and re-read the `why` to check the replacement still says what it meant";
    }
    {
      name = "C6 anchors are unique: every override `from` occurs exactly once in its file";
      ok = multiAnchors == [ ];
      msg =
        "anchor(s) matching more than once: "
        + showList (map (o: "${showAnchor o} (${toString (occ o.from o.src)} sites)") multiAnchors)
        + " — `replaceStrings` rewrites EVERY occurrence, so a second site is a passage nobody read being replaced by text written for another context. Narrow the anchor with a neighbouring line until it is unique, or split it into two overrides with two `why` entries";
    }
    {
      name = "C7 nothing survives: no `from` of the substitution table remains in any translated file";
      ok = survivors == [ ];
      msg =
        showList survivors
        + " — the deployed text still names something this host does not have. An instruction naming a mechanism that does not exist is worse than no instruction: the model spends context obeying it and reaches for a tool it cannot call. Either the term reached the output through an override's `to` (overrides run FIRST, so a `to` is substituted afterwards — check the order argument at the top of skills-translate.nix) or a new site appeared that the rule cannot see";
    }
    {
      name = "C7b nothing survives, asked independently of the table";
      ok = independentSurvivors == [ ];
      msg =
        showList independentSurvivors
        + " — this list of forbidden terms is written out by hand rather than derived from `substitutions`, and that is the whole point. Measured on 2026-09-10: deleting a substitution rule left C7 green, because C7 asks the table what must not survive and a deleted rule forbids nothing. If a term here is legitimate in some passage, do NOT loosen this list — record the exemption next to the one already made for claude-code-meta, which documents the Claude layer of this repo and is right to name it";
    }
    {
      name = "C8 frontmatter: every translated SKILL.md opens with `---`, carries name+description at column 0, and `name` is the directory";
      ok = badFrontmatter == [ ];
      msg =
        showList (map showFrontmatter badFrontmatter)
        + " — a frontmatter that does not parse costs the WHOLE skill: the scanner lists it with a garbage description or skips it, and says nothing. Claude currently shows trello's description as literally `---` for this exact reason. The key lines must be at COLUMN 0 (see indentedFrontmatter and C10). The name/directory equality is repo hygiene, not a Codex requirement — Codex names a skill by this `name:`, measured — but every probe and bug report here assumes the two words are the same";
    }
    {
      name = "C8b stripped keys: the keys present in the source frontmatters and absent from the translated ones are exactly `strippedKeys`";
      ok = removedKeys == sortUniq tr.strippedKeys;
      msg =
        "removed by normalisation: ["
        + join removedKeys
        + "] but strippedKeys declares ["
        + join (sortUniq tr.strippedKeys)
        + "] — stripFrontmatter keeps `name` and `description` and drops everything else, so a NEW key upstream is silently dropped the day it appears. This assertion forces the decision to be taken and written down: either the key is Codex-meaningful and must join `keptKeys`, or its loss is accepted and it joins `strippedKeys` with a line saying why (see the `disable-model-invocation` entry in notSubstituted). An entry that no longer appears anywhere means the source dropped it and nobody told this list";
    }
    {
      name = "C9 description budget: the translated descriptions fit in the documented allowance";
      ok = descBudget < descLimit;
      msg =
        "translated descriptions total "
        + toString descBudget
        + " characters over "
        + toString (builtins.length descLines)
        + " skill(s), limit "
        + toString descLimit
        + " — Codex loads every skill description into every session's context and documents the cap as 2% of the context window or 8000 characters. Over it, descriptions are truncated or skills dropped, and which ones is not something this repo controls. Shorten the longest descriptions; the budget was ~3032 when this check was written, so reaching the limit means something grew by a factor of two";
    }
    {
      name = "C10 indentedFrontmatter is symmetric with the source";
      ok = missingException == [ ] && deadException == [ ];
      msg =
        "skill(s) whose SOURCE frontmatter is indented but that are NOT listed: "
        + showList missingException
        + " | listed but no longer indented in the source: "
        + showList deadException
        + " — the list exists so `stripFrontmatter` re-emits those frontmatters flush left; an unlisted indented skill deploys a frontmatter nothing parses. A DEAD entry is just as bad: it means the source was repaired upstream and this file was not told, and the next reader trusts a list that no longer describes anything. Update home/codex/skills-translate.nix in both directions";
    }
    {
      name = "C11 anti-recursion: apex's translated description keeps the zero-file-modification exclusion";
      ok = has antiRecursion apexDescription;
      msg =
        "apex/SKILL.md description does not contain `"
        + antiRecursion
        + "`; it reads: "
        + (if apexDescription == "" then "<no description line at column 0>" else apexDescription)
        + " — this is a LOOP GUARD, not prose. The Claude-side external verification pass runs `codex exec` on a diff, and that Codex session now carries apex; without the clause excluding work with zero file modification, a read-only verification pass can open a full APEX run inside itself and spend an allowance nobody asked for. O1 carries the sentence in the anchor AND in the replacement so a reword upstream breaks the build instead of dropping the guard";
    }
    {
      name = "C12 the external-verify flag is gone from the translated corpus";
      ok = externalResidue == [ ] && eFlagRows == [ ];
      msg =
        "file(s) still naming the wrapper: "
        + showList externalResidue
        + " | flag row(s) still present: "
        + showList eFlagRows
        + " — `apex-verify-external` is a Claude-side wrapper that does not exist on this host, and its flag would point this build at `codex exec`: a Codex verifying a Codex buys the round-trip and none of the independence. Three source sites carry it (the flag table O3a, the usage block O3b, the typed-flag list O6) plus the step-04 block O10 deletes; a residue here means one of those anchors went inert — see C5";
    }
  ];

  failures = builtins.filter (a: !a.ok) assertions;

  fail = msg: throw "codex-skills: ${msg}";

  # --- build time: the installed files ARE the asserted texts --------------
  # Everything above reasons about `codexSkills.translatedTexts`. Nothing so
  # far proves the derivations home.file installs contain that text — and a
  # check that is green about a string the module does not deploy is the same
  # class of defect as the fossil tree. So each file is compared byte for byte
  # against the derivation, which also pulls the 14 skill derivations into this
  # build: a skill whose own SKILL.md guard fails takes this check down with it.
  drvOf =
    name:
    let
      hits = builtins.filter (n: lib.hasSuffix "/${name}" n) installedRoots;
    in
    if hits == [ ] then
      fail "no home.file entry for skill ${name} — home/codex/skills.nix stopped installing it"
    else
      codexSkills.files.${builtins.head hits}.source;

  textOfTranslated =
    skill: path:
    let
      hits = builtins.filter (f: f.skill == skill && f.path == path) translated;
    in
    if hits == [ ] then fail "no translated text for ${skill}/${path}" else (builtins.head hits).text;

  fileProbes = lib.concatMapStrings (
    skill:
    lib.concatMapStrings (
      file:
      let
        expected = builtins.toFile "expected-${skill.name}-${lib.replaceStrings [ "/" ] [ "-" ] file.path}" (
          textOfTranslated skill.name file.path
        );
      in
      ''
        cmp -s ${drvOf skill.name}/${file.path} ${expected} || {
          echo "codex-skills: ${skill.name}/${file.path} as installed differs from the text this check asserted on — the module and the check disagree about what is deployed, so every assertion above is about a string nobody reads" >&2
          exit 1
        }
      ''
    ) skill.files
    + ''
      test -f ${drvOf skill.name}/SKILL.md || { echo "codex-skills: ${skill.name} has no SKILL.md" >&2; exit 1; }
      test ! -L ${drvOf skill.name}/SKILL.md || { echo "codex-skills: ${skill.name}/SKILL.md is a symlink — measured: the scanner SKIPS a symlinked SKILL.md, so the skill is silently absent" >&2; exit 1; }
    ''
  ) manifest;

in
pkgs.runCommand "codex-skills-check" { } (
  if failures != [ ] then
    fail (
      "${toString (builtins.length failures)} broken invariant(s):\n"
      + builtins.concatStringsSep "\n" (map (a: "  - ${a.name}: ${a.msg}") failures)
    )
  else
    ''
      ${fileProbes}
      echo "codex-skills: ${toString (builtins.length assertions)} invariants, ${toString (builtins.length manifest)} skills, ${toString (builtins.length translated)} files compared byte for byte with the installed derivations, ${toString (builtins.length tr.substitutions)} substitutions, ${toString (builtins.length tr.overrides)} overrides, ${toString descBudget} characters of description — OK"
      touch $out
    ''
)
