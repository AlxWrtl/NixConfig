# Provenance tagging check for APEX plan premises.
#
# step-02-plan requires every premise to carry a provenance tag as its first
# token: `[M]` measured, `[I]` inferred. This file guards that rule.
#
# LIMIT — read this before trusting the green.
#
# This check proves a tag is PRESENT. It never proves the tag is TRUE. A
# premise tagged `[M]` with nothing measured behind it passes here without a
# murmur; nothing in nix can replay the command a tag claims to stand on.
# Measured in this repo on 2026-09-05: three rules were shipped, read well and
# did nothing at all. `nix flake check` was green each time — because it proves
# a clause is present, never that the clause does something. The reader able to
# falsify a tag is Agent 1's slot in step-05-examine and the Fable premises
# pass. Not this file.
#
# This check does NOT walk `.claude/output`. The fact is replayable in one
# command: `.claude/` is gitignored, so `git ls-files .claude/output` returns
# ZERO tracked files while the directory is full of `02-plan.md` on disk. No
# count is quoted here on purpose — plans accumulate through the day, so a
# number written into this comment rots within hours and no reader can replay
# it, while the command stays true and re-runnable. A walk over that directory
# from the flake would see zero plans and be vacuously true forever — the exact
# failure shape this file is supposed to catch. The corpus
# is therefore two INLINE fixtures, one correct and one deliberately broken, so
# the detector is exercised in both directions on every evaluation.
#
# Runs in `nix flake check`, before any rebuild, from the nix sources.
{ pkgs }:

let
  lib = pkgs.lib;
  skills = import ../home/claude-code/skills.nix;

  splitLines = lib.splitString "\n";
  fail = msg: throw ("apex-plan-provenance: " + msg);

  # Borrowed verbatim from readme-consistency.nix: when an extractor stops
  # matching, its corpus becomes [] and every comparison against [] is green
  # forever. A parse that found nothing is a failure, not a pass.
  nonEmpty =
    what: xs:
    if xs == [ ] then
      fail "parsed zero ${what} — the fixture slicer stopped matching and the detector assertions are now checking nothing. Fix the extraction; do not delete the assertion."
    else
      xs;

  # ------------------------------------------------------------ the rule
  # The clause step-02-plan must keep. hasInfix is only ever called here with a
  # non-empty literal: `hasInfix ""` is true against anything, and an empty
  # needle handed to the regex engine makes nix refuse the pattern outright, so
  # the check would die on a trace instead of naming the problem.
  taggingClause = "[M] measured or [I] inferred";
  ruleMissing = !(lib.hasInfix taggingClause skills.apexStep02Plan);

  # ------------------------------------------------------------ the slice
  # splitString, not builtins.match: POSIX matching is leftmost-longest and `.`
  # crosses newlines, so ".*Premises(.*)Tasks.*" would bind the marker to its
  # LAST occurrence and silently shrink the slice.
  startMarker = "**Premises**";
  stopMarker = "**Tasks**";

  premisesSlice =
    planText:
    let
      opened = lib.splitString startMarker planText;
      closed = lib.splitString stopMarker (builtins.elemAt opened 1);
    in
    if builtins.length opened != 2 then
      fail "marker '${startMarker}' occurs ${
        toString (builtins.length opened - 1)
      }x in a fixture, expected exactly 1 — an ambiguous boundary silently shrinks what the detector sees."
    else if builtins.length closed < 2 then
      fail "end marker '${stopMarker}' not found in a fixture — the Premises slice has no end and the detector would read the task list as premises."
    else
      builtins.head closed;

  # ---------------------------------------------------------- the detector
  # A premise line is a bullet. It is TAGGED when its first token, after the
  # bullet and an optional opening `**`, is `[M]` or `[I]`.
  #
  # `[[]` and `[]]`, not `\[` and `\]`: nix rejects a backslash-escaped bracket
  # outright — "invalid regular expression" — and the check would die on a
  # trace instead of naming the untagged premise. Same for `[*][*]` vs `\*\*`.
  isBullet = l: builtins.match " *[-*] .*" l != null;
  isTagged = l: builtins.match " *[-*] +([*][*])?[[][MI][]].*" l != null;

  premiseBullets =
    planText:
    nonEmpty "premise bullet line(s) in the Premises slice" (
      builtins.filter isBullet (splitLines (premisesSlice planText))
    );

  untaggedPremises = planText: builtins.filter (l: !(isTagged l)) (premiseBullets planText);

  # ---------------------------------------------------------- the fixtures
  # Inline, for the reason stated at the top: the real plans are gitignored.
  goodFixture = ''
    ## Plan

    **Premises**

    - **[M] The target, restated** — add one flake check guarding the premise
      tag rule. Source: the user message, quoted in 01-analyze.
    - **[M] Assumed environment state** — `git ls-files checks` lists the files
      the README Structure tree has to mirror.
    - **[I] Explicitly excluded scope** — hooks.nix belongs to another task and
      is not touched here.

    **Tasks**

    T1: write the check.
  '';

  # The one premise whose tag the bad fixture drops. A LITERAL, so it cannot
  # arrive empty from a computation — emptiness would be visible on this very
  # line. It previously carried an `if sentinel == ""` guard; that guard was a
  # constant-false predicate over a literal, i.e. a dead branch wearing the
  # costume of a check, and it is gone.
  #
  # Emptiness is still not unguarded — it is caught downstream by a LIVE guard.
  # An empty sentinel makes the substitution in badFixture search for
  # "**[I] **", which does not occur in the good fixture, so `stripped` comes
  # back byte-identical and the badFixture assertion throws. Measured
  # 2026-09-22: setting this to "" yields "the bad fixture came out
  # byte-identical to the good one", never a sentinel message.
  droppedPremise = "Explicitly excluded scope";

  # DERIVED from the good fixture, never retyped: that is what makes "identical
  # except one missing tag" true by construction rather than by proofreading.
  badFixture =
    let
      stripped =
        builtins.replaceStrings
          [ "**[I] ${droppedPremise}**" ]
          [
            "**${droppedPremise}**"
          ]
          goodFixture;
    in
    if stripped == goodFixture then
      fail "the bad fixture came out byte-identical to the good one — the tag-stripping substitution no longer matches the good fixture, so the red control below has nothing to detect. Re-align the substitution with the fixture text."
    else
      stripped;

  untaggedGood = untaggedPremises goodFixture;
  untaggedBad = untaggedPremises badFixture;

  goodBullets = premiseBullets goodFixture;
  badBullets = premiseBullets badFixture;

  # Assertion 3, second half: not merely "some line", THE line.
  badMisidentified =
    builtins.length untaggedBad != 1 || !(lib.hasInfix droppedPremise (builtins.head untaggedBad));

  # Assertion 4, and it is a DRIFT guard, not an emptiness guard. An emptiness
  # test here would be dead code: `premiseBullets` routes both fixtures through
  # `nonEmpty`, which throws first, so neither list can reach this point empty.
  # Measured 2026-09-22 — mutating `isBullet` to `l: false`, the one change that
  # should empty both lists, yields "parsed zero premise bullet line(s) in the
  # Premises slice", never a message from this branch.
  #
  # What IS reachable: two fixtures that no longer hold the same number of
  # premises are two fixtures that drifted apart, and the pair is only a control
  # while they differ by exactly one tag and nothing else.
  fixturesVacuous = builtins.length goodBullets != builtins.length badBullets;

in
pkgs.runCommand "apex-plan-provenance-check" { } (
  if ruleMissing then
    fail "step-02-plan no longer contains '${taggingClause}'. This check has lost its subject: it guards a provenance-tagging rule that the skill no longer states, so every assertion below would be enforcing a convention nothing asks for. Restore the clause in apexStep02Plan, or delete this check deliberately."
  else if untaggedGood != [ ] then
    fail (
      "the detector rejects a correctly tagged plan (false positive) on: "
      + builtins.concatStringsSep " | " (map lib.strings.trim untaggedGood)
      + ". Every premise in the good fixture carries [M] or [I]; the line pattern is wrong, not the fixture."
    )
  else if untaggedBad == [ ] then
    fail "le détecteur ne sait pas échouer — il a laissé passer un plan avec une prémisse non taguée. La fixture MAUVAISE est la bonne moins le tag de '${droppedPremise}', et le détecteur n'y voit rien. Un garde qu'on n'a jamais vu rougir n'est pas un garde."
  else if badMisidentified then
    fail (
      "the detector fired on the bad fixture but not on the expected line. Expected exactly the premise '${droppedPremise}', got: "
      + builtins.concatStringsSep " | " (map lib.strings.trim untaggedBad)
      + ". A detector that goes red for the wrong reason reports nothing about the rule."
    )
  else if fixturesVacuous then
    fail "the two fixtures no longer hold the same number of premises (good: ${toString (builtins.length goodBullets)}, bad: ${toString (builtins.length badBullets)}). The bad fixture is only a control while it is the good one minus exactly one tag; once the two drift apart, the assertions above are comparing two different texts and the red they report says nothing about the detector."
  else
    ''
      echo "apex-plan-provenance: tagging clause present, detector silent on the tagged fixture and red on the untagged one — OK"
      touch $out
    ''
)
