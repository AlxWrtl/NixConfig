# Structural consistency check for README.md.
#
# The README had drifted on nearly every factual claim it made — six APEX
# flags that no longer existed, four shell aliases defined nowhere, three
# inventories undercounted by five each — and not one check went red. checks/
# guarded the APEX skill and the Claude config; the document DESCRIBING them
# was guarded by nobody. That asymmetry is the whole reason it rotted.
#
# Two rules hold this file together, both learned the hard way from four
# independent reviews of its first draft:
#
# 1. OWN NO VALUE. Every assertion compares the README against a live source —
#    the flag table against skills.nix, the inventory against the directories,
#    the aliases against the files that declare them. The first draft carried
#    a literal list of removed flags; it made the repo unmergeable if any of
#    those letters ever came back, and it still missed every other flag.
#
# 2. PROVE THE PARSE. When an extractor stops matching, its corpus becomes []
#    and a comparison of [] against [] is green forever. That is precisely the
#    "no check went red" failure this file exists to prevent, so every corpus
#    is guarded by nonEmpty, and the flag tables additionally assert that the
#    number of parsed rows equals the number of rows present.
#
# Runs in `nix flake check`, before any rebuild, from the nix sources.
{ pkgs }:

let
  lib = pkgs.lib;

  readme = builtins.readFile ../README.md;
  skills = import ../home/claude-code/skills.nix;

  splitLines = lib.splitString "\n";
  fail = msg: throw "readme-consistency: ${msg}";

  nonEmpty =
    what: xs:
    if xs == [ ] then
      fail "parsed zero ${what} — the source format changed and this assertion is now checking nothing. Fix the extraction; do not delete the assertion."
    else
      xs;

  # Deterministic slice. builtins.match must NOT be used for this: POSIX
  # leftmost-longest grows the leading `.*` maximally, so ".*START(.*)STOP.*"
  # binds START to its LAST occurrence. Measured on this very file's first
  # draft: adding a "### APEX related commands" heading shrank the APEX slice
  # from 3629 to 646 bytes and the check still printed OK.
  #
  # splitString is exact. Markers are newline-anchored so a longer heading
  # cannot shadow a shorter one, and a marker that occurs twice is an error
  # rather than a silent choice between two boundaries.
  section =
    what: start: stop: text:
    let
      opened = lib.splitString start text;
      closed = lib.splitString stop (builtins.elemAt opened 1);
    in
    if builtins.length opened != 2 then
      fail "marker '${start}' occurs ${
        toString (builtins.length opened - 1)
      }x while slicing the ${what} section, expected exactly 1 — an ambiguous boundary silently shrinks what gets checked."
    else if builtins.length closed < 2 then
      fail "end marker '${stop}' not found while slicing the ${what} section."
    else
      builtins.head closed;

  apexSection = section "APEX" "\n## APEX\n" "\n## Shell Aliases\n" readme;
  structureTree = section "structure tree" "\n## Structure\n\n```\n" "\n```\n" readme;
  aliasSection = section "shell alias" "\n## Shell Aliases\n" "\n## Troubleshooting\n" readme;
  aliasFence = section "shell alias code block" "```bash\n" "\n```" aliasSection;

  # ---------------------------------------------------------------- A1 flags
  # The assertion that would have caught the real failure: six flags were
  # deleted from the skill and the README kept advertising them for months.
  readmeFlagTable = section "README flag table" "\n### Flags\n" "\n### Invariants\n" readme;
  skillFlagTable =
    section "skill flag table" "\n## Available Flags\n" "\nBranch-first and on-disk"
      skills.skillApex;

  # Header + separator are the two non-data rows every markdown table carries.
  tableRowCount =
    t: builtins.length (builtins.filter (l: builtins.match " *\\|.*\\|.*" l != null) (splitLines t));

  # "| `-q` | `-Q` | ..." and "| -q | -Q | ..." both reduce to "-q/-Q".
  # An empty disable cell (-2 has none) reduces to "-2/".
  pairOf =
    re: line:
    let
      m = builtins.match re line;
    in
    if m == null then
      null
    else
      "${builtins.elemAt m 0}/${
        lib.replaceStrings
          [
            " "
            "`"
          ]
          [
            ""
            ""
          ]
          (builtins.elemAt m 1)
      }";

  # A partial parse silently drops flags, which is indistinguishable from a
  # table that legitimately lost a row — so a row count mismatch fails here.
  pairsFrom =
    what: re: table:
    let
      parsed = builtins.filter (x: x != null) (map (pairOf re) (splitLines table));
      expected = tableRowCount table - 2;
    in
    if builtins.length parsed != expected then
      fail "parsed ${toString (builtins.length parsed)} of ${toString expected} flag row(s) in the ${what} — the table shape changed (re-padded cells, an extra column, a stray row). A partial parse would drop flags without a word."
    else
      lib.sort (a: b: a < b) (nonEmpty "${what} flags" parsed);

  readmePairs = pairsFrom "README table" " *\\| *`(-[a-zA-Z0-9]+)` *\\|([^|]*)\\|.*" readmeFlagTable;
  skillPairs = pairsFrom "skill table" " *\\| *(-[a-zA-Z0-9]+) *\\|([^|]*)\\|.*" skillFlagTable;

  flagsOnlyInReadme = builtins.filter (p: !(builtins.elem p skillPairs)) readmePairs;
  flagsOnlyInSkill = builtins.filter (p: !(builtins.elem p readmePairs)) skillPairs;

  # ----------------------------------------------------- A2 flags in examples
  # A flag can leave the table and survive in a usage example — which is what
  # happened: all six examples typed -a and -s.
  #
  # Scoped to lines that actually invoke /apex. An earlier draft scanned the
  # whole section for a fixed list of letters, and -a -s -b -m -i -r are the
  # commonest CLI letters there are: `git checkout -b`, `ls -a`, `grep -i` in
  # ordinary prose all turned the gate red on a correct document.
  knownFlags = lib.unique (
    lib.concatMap (p: builtins.filter (s: s != "") (lib.splitString "/" p)) skillPairs
  );
  apexInvocations = nonEmpty "/apex usage examples" (
    builtins.filter (l: builtins.match ".*/apex .*" l != null) (splitLines apexSection)
  );
  invocationFlags = lib.unique (
    map (m: "-" + builtins.head m) (
      builtins.filter builtins.isList (
        builtins.split "[^A-Za-z0-9-]-([A-Za-z0-9]+)" (builtins.concatStringsSep "\n" apexInvocations)
      )
    )
  );
  unknownFlags = builtins.filter (f: !(builtins.elem f knownFlags)) invocationFlags;

  # -------------------------------------------------------- A3 module inventory
  # A module added to the repo and never written into the README —
  # home/claude-code.nix lived there unmentioned.
  #
  # Scoped to the Structure tree and anchored on the "── " that precedes every
  # entry. Searching the whole document for a bare basename let a name be
  # satisfied by an unrelated mention, and let a longer name cover a shorter
  # one (claude-config.nix covering config.nix). Counting occurrences is what
  # keeps two files sharing a basename — home/ and hosts/ both have
  # default.nix — from being satisfied by a single line.
  #
  # NOT recursive, deliberately: home/claude-code/ is documented as one unit,
  # a directory pointer, and forcing its eleven internal modules into the tree
  # would be noise. The README says exactly that, so the claim matches.
  nixFilesIn =
    dir: builtins.filter (lib.hasSuffix ".nix") (builtins.attrNames (builtins.readDir dir));
  inventoried = lib.concatMap nixFilesIn [
    ../modules
    ../home
    ../checks
    ../hosts/alex-mbp
  ];
  occurrencesOf = needle: text: builtins.length (lib.splitString needle text) - 1;
  underDocumented = builtins.filter (
    n: occurrencesOf "── ${n}" structureTree < builtins.length (builtins.filter (x: x == n) inventoried)
  ) (lib.unique inventoried);

  # Every check must earn a row in the Quality Gates table — including this
  # one. Without it the README can drop the row that describes its own guard.
  undocumentedChecks = builtins.filter (
    f: !(lib.hasInfix "| `${lib.removeSuffix ".nix" f}` |" readme)
  ) (nixFilesIn ../checks);

  # The reverse direction: something the README points at that is gone.
  citedFiles = nonEmpty "cited files" (
    lib.unique (
      map (m: builtins.head m) (
        builtins.filter builtins.isList (builtins.split "`([A-Za-z0-9_./-]+\\.(nix|sh))`" readme)
      )
    )
  );
  treeScripts = lib.unique (
    map (m: builtins.head m) (
      builtins.filter builtins.isList (builtins.split "── ([A-Za-z0-9_.-]+\\.(sh|md))" structureTree)
    )
  );
  danglingFiles = builtins.filter (p: !(builtins.pathExists (../. + "/${p}"))) (
    citedFiles ++ treeScripts
  );

  # ------------------------------------------------------------- A4 aliases
  # Four files declare aliases; the README documented one of them, badly.
  # Reading only home/zsh.nix is how `rebuild` gets called nonexistent.
  #
  # The search is scoped to the alias attrsets themselves. Scanning whole
  # files let any attribute assigned a string — dotDir, description, home —
  # pass as a declared alias.
  aliasBlockOf =
    text:
    builtins.concatStringsSep "\n" (
      (builtins.foldl'
        (
          acc: l:
          if acc.inside then
            if builtins.match " *\\};" l != null then
              acc // { inside = false; }
            else
              acc // { out = acc.out ++ [ l ]; }
          else if builtins.match ".*[aA]liases = \\{" l != null then
            acc // { inside = true; }
          else
            acc
        )
        {
          inside = false;
          out = [ ];
        }
        (splitLines text)
      ).out
    );
  aliasSources =
    "\n"
    + builtins.concatStringsSep "\n" (
      map (p: aliasBlockOf (builtins.readFile p)) [
        ../modules/packages.nix
        ../modules/system.nix
        ../home/zsh.nix
        ../home/claude-code/shell.nix
      ]
    );
  beforeHash =
    l:
    let
      m = builtins.match "([^#]*)#.*" l;
    in
    if m == null then l else builtins.head m;
  # Only lines that carry a "# gloss" are alias lines. Without this, a prose
  # sentence dropped into the fence turned every one of its words into an
  # "undeclared alias".
  aliasNames = nonEmpty "documented aliases" (
    lib.unique (
      builtins.filter (t: builtins.match "[a-z][a-z0-9-]*" t != null) (
        lib.concatMap (l: lib.splitString " " (beforeHash l)) (
          builtins.filter (l: builtins.match "[^#]*#.*" l != null) (splitLines aliasFence)
        )
      )
    )
  );
  # Names are [a-z][a-z0-9-]* by construction above, so none can carry a regex
  # metacharacter into this pattern.
  undeclaredAliases = builtins.filter (
    a: builtins.match ".*\n *${a} = \".*" aliasSources == null
  ) aliasNames;

  # --------------------------------------------------------- A5 hard counts
  # "(29 casks)" for 34 declared is what rotted first. A count duplicated from
  # a module is a promise the README cannot keep; the module is the list.
  #
  # Known limit, stated rather than papered over: spelled-out numerals
  # ("twelve steps") are not caught. Digits are the shape that rotted.
  countNouns = "casks?|apps?|packages?|fonts?|formulae|aliases|checks|modules|skills|commands|agents|hooks|extensions|tools";
  hardCounts = builtins.filter (
    l: builtins.match ".*[0-9]+ +(${countNouns})([^a-zA-Z].*)?" l != null
  ) (splitLines readme);

  problems =
    lib.optional (flagsOnlyInReadme != [ ] || flagsOnlyInSkill != [ ])
      "the README flag table no longer matches the APEX skill. In the README only: ${builtins.concatStringsSep ", " flagsOnlyInReadme}. In the skill only: ${builtins.concatStringsSep ", " flagsOnlyInSkill}. Pairs are 'enable/disable', so a mismatch can be a missing flag OR a wrong disable letter; skills.nix is the source of truth."
    ++
      lib.optional (unknownFlags != [ ])
        "/apex example(s) type flag(s) the skill does not declare: ${builtins.concatStringsSep ", " unknownFlags}. A usage example that types a removed flag teaches a command that does nothing."
    ++
      lib.optional (underDocumented != [ ])
        "module(s) missing from the Structure tree: ${builtins.concatStringsSep ", " underDocumented}. Add an entry per file — two files sharing a basename need two lines."
    ++
      lib.optional (undocumentedChecks != [ ])
        "check(s) with no row in the Quality Gates table: ${builtins.concatStringsSep ", " undocumentedChecks}. A guard the README does not describe is a guard nobody knows to run."
    ++
      lib.optional (danglingFiles != [ ])
        "the README points at file(s) that do not exist: ${builtins.concatStringsSep ", " danglingFiles}. They were renamed or deleted without updating the document."
    ++
      lib.optional (undeclaredAliases != [ ])
        "the README documents alias(es) declared in none of the four alias attrsets: ${builtins.concatStringsSep ", " undeclaredAliases}. Checked in modules/packages.nix, modules/system.nix, home/zsh.nix and home/claude-code/shell.nix — all four, because reading only one is how `rebuild` gets wrongly called missing."
    ++
      lib.optional (hardCounts != [ ])
        "hard count(s) in the README: ${builtins.concatStringsSep " | " (map lib.strings.trim hardCounts)}. Every inventory count measured here was wrong; name a representative sample and point at the module that owns the real list.";
in
pkgs.runCommand "readme-consistency-check" { } (
  if problems != [ ] then
    fail ("\n  - " + builtins.concatStringsSep "\n  - " problems)
  else
    ''
      echo "readme-consistency: ${toString (builtins.length readmePairs)} flags vs skill, ${toString (builtins.length invocationFlags)} example flags, ${toString (builtins.length inventoried)} modules, ${
        toString (builtins.length danglingFiles + builtins.length citedFiles)
      } cited paths, ${toString (builtins.length aliasNames)} aliases — OK"
      touch $out
    ''
)
