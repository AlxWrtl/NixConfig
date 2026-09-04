# Structural consistency check for the APEX skill.
#
# Not a behavioural test. A behavioural runner was built and measured: four
# runs of one identical eval case returned 4/4, 2/4, 3/4, 3/4 — the noise
# floor exceeds any regression it could detect, because the assertions match
# free-form model prose. This checks the one thing that IS deterministic:
# whether APEX still refers only to parts of itself that exist, and whether
# the clauses it must never lose are still there.
#
# Runs in `nix flake check`, before any rebuild, from the nix sources.
{ pkgs }:

let
  skills = import ../home/claude-code/skills.nix;
  # Stub, not a default argument in hooks.nix: this check only ever reads hook
  # TEXT, so any store path does. Making the argument optional over there would
  # let a missing wiring in claude-code.nix pass in silence and ship a hook whose
  # binary path points nowhere — precisely the mute failure this hook exists to
  # remove.
  hooks = import ../home/claude-code/hooks.nix {
    graphifyReindexPkg = "/nix/store/00000000000000000000000000000000-stub";
  };

  # Step file basename -> the nix attribute holding its content.
  steps = {
    "step-00-init" = skills.apexStep00Init;
    "step-00b-branch" = skills.apexStep00bBranch;
    "step-00b-save" = skills.apexStep00bSave;
    "step-01-analyze" = skills.apexStep01Analyze;
    "step-01b-obsidian-context" = skills.apexStep01bObsidianContext;
    "step-02-plan" = skills.apexStep02Plan;
    "step-02b-tasks" = skills.apexStep02bTasks;
    "step-02c-verify" = skills.apexStep02cVerify;
    "step-03-execute" = skills.apexStep03Execute;
    "step-04-validate" = skills.apexStep04Validate;
    "step-05-examine" = skills.apexStep05Examine;
    "step-06-resolve" = skills.apexStep06Resolve;
    "step-07-tests" = skills.apexStep07Tests;
    "step-08-run-tests" = skills.apexStep08RunTests;
    "step-09-finish" = skills.apexStep09Finish;
    "step-09b-obsidian-note" = skills.apexStep09bObsidianNote;
    "ROUTING" = skills.apexRouting;
    "ORCHESTRATION" = skills.apexOrchestration;
  };

  # Every text APEX ships, concatenated — used for reference resolution.
  corpus = skills.skillApex + "\n" + builtins.concatStringsSep "\n" (builtins.attrValues steps);

  existing = builtins.attrNames steps;

  # Clauses whose loss would be silent and expensive. Each was added for a
  # reason; a config edit that drops one must fail loudly, not quietly.
  invariants = [
    {
      name = "verify: correction rounds are bounded";
      needle = "Max 3 correction rounds";
    }
    {
      name = "verify: checks are never weakened to pass";
      needle = "Never weaken a check";
    }
    {
      name = "verify: machine gate runs before any model";
      needle = "Machine gate FIRST";
    }
    {
      name = "verify: the real diff is read, not just the summary";
      needle = "Never trust the summary alone";
    }
    {
      name = "orchestration: subagents never inherit the session model";
      needle = "never inherit";
    }
    {
      name = "orchestration: Fable stays read-only";
      needle = "READ-ONLY";
    }
    {
      name = "flags: uppercase disables an auto-enabled flag";
      needle = "uppercase forces OFF";
    }
    {
      name = "flags: the never-auto list is stated";
      needle = "Never auto-enabled";
    }
    {
      name = "gate: pure research skips execute/validate";
      needle = "Pure research";
    }
    {
      name = "summary: the phase schema is fixed";
      needle = "OBJECTIVE_MET";
    }
    {
      name = "plan: premises are stated before the task list";
      needle = "Assumed business rules";
    }
    {
      name = "plan: every factual premise is sourced, never recalled";
      needle = "Every premise carries its source";
    }
    {
      name = "plan: new construction is justified rung by rung";
      needle = "Scope ladder";
    }
    {
      # A heading with no rungs under it satisfies the needle above while
      # checking nothing, so the rungs are asserted separately. Measured: with
      # every rung deleted and the heading kept, this file was still green.
      name = "plan: the ladder still has rungs, not just a heading";
      needle = "Does this codebase already do it?";
    }
    {
      # Defines when a rung HOLDS. Without it the first rung reads with the
      # opposite polarity to the others — "yes it must exist" would stop the
      # walk — and the ladder silently never runs past rung 1.
      name = "plan: a rung holds when the answer means do not build";
      needle = "HOLDS when its answer means you do NOT build";
    }
    {
      # The rung that makes the ladder safe. Without it, "can the target be met
      # without it" reads as a licence to hand back less than was asked, which
      # turns a guard against accretion into a guard against delivery.
      name = "plan: the ladder questions the solution, never the request";
      needle = "questions the SOLUTION, never the REQUEST";
    }
    {
      # The slogan above is satisfied by a section that keeps it and drops the
      # operative sentence. This is the sentence that does the work.
      name = "plan: a rung that drops requested scope is a question for the user";
      needle = "a scope cut is a question for the user";
    }
    {
      # An item killed at rung 1 or 2 leaves the plan, the ACs and the diff.
      # Without this, under-delivery is invisible end to end — examine measures
      # the diff against ACs the same planner already shrank.
      name = "plan: what the ladder kills stays visible to the user";
      needle = "A drop the user cannot see at approval";
    }
    {
      name = "orchestration: Fable reviews premises but never authors the plan";
      needle = "Fable NEVER writes the plan";
    }
    {
      name = "plan: a user-contradicted premise is persisted before execute";
      needle = "persist the correction before execute";
    }
    {
      name = "verify: the premises pass replays cited read-only evidence";
      needle = "cited read-only commands";
    }
    {
      name = "flags: test-first tests are read-only for the implementer";
      needle = "read-only for the implementer";
    }
    {
      name = "examine: reviewers never see the implementer's rationale";
      needle = "never the implementer's rationale";
    }
    {
      name = "clarify: unsourceable premises become questions";
      needle = "Unsourceable premises become questions";
    }
  ];

  missingInvariants = builtins.filter (i: !(pkgs.lib.hasInfix i.needle corpus)) invariants;

  # ---------------------------------------------------------------------------
  # Mode table vs the UserPromptSubmit reminder.
  #
  # hookApexReminder restates the Mode Gate table for the model on every prompt.
  # It is a hand-maintained COPY, and it has drifted TWICE: the trivial tier was
  # removed on 2026-08-17 and the line kept advertising it for months, then
  # -o/-n became mode defaults while the line still listed them as opt-in.
  # Deriving the line from a shared nix value was evaluated and rejected — only
  # the three flag strings are genuinely shared, the rest (French labels, option
  # glosses) is hook-only, so a "shared" file would become a third place to edit.
  # A check is the cheaper answer: the table stays the single source of truth,
  # the line stays free prose, and a third drift breaks `nix flake check`
  # instead of lying silently.
  #
  # Flags are READ FROM THE TABLE, never restated here. The only thing this
  # check owns is the EN->FR label mapping, which is small and stable.
  reminder = hooks.hookApexReminder;

  modeMap = [
    {
      en = "Diagnosis";
      fr = "diagnosis";
    }
    {
      en = "Standard / complex";
      fr = "standard";
    }
    {
      en = "High-stakes";
      fr = "haut-enjeu";
    }
  ];

  # A reformatted table is exactly the case to catch, so a null match throws
  # rather than silently passing.
  rowFlags =
    label:
    let
      m = builtins.match ".*\\| ${label} \\| `([^`]*)` \\|.*" skills.apexStep00Init;
    in
    if m == null then
      throw "apex-consistency: no Mode Gate row for '${label}' — the table in apexStep00Init was reformatted or renamed; this check reads flags from it and cannot guess."
    else
      builtins.head m;

  modeDrift = builtins.filter (d: d != null) (
    map (
      m:
      let
        expected = "${m.fr}=${rowFlags m.en}";
      in
      if pkgs.lib.hasInfix expected reminder then null else expected
    ) modeMap
  );

  # The trivial tier is gone; announcing it is a lie. Scoped to the hook SCRIPT,
  # not the file — hooks.nix mentions "trivial" in legitimate comments.
  trivialAdvertised = pkgs.lib.hasInfix "trivial" reminder;

  # Opt-in flags must be listed as options; -o/-n must NOT be, they are defaults.
  neverAuto = [
    "-q"
    "-f"
    "-2"
    "-p"
    "-k"
    "-v"
  ];
  missingOptions = builtins.filter (f: !(pkgs.lib.hasInfix "${f} " reminder)) neverAuto;
  staleOptions = builtins.filter (f: pkgs.lib.hasInfix f reminder) [
    "-o vault"
    "-n note"
  ];

  # Step files named in the corpus that do not exist as attributes.
  # The capture group is required: builtins.split yields an empty list for a
  # match with no groups, and head on it throws.
  referenced = builtins.filter (n: n != null) (
    map (m: if builtins.isList m && m != [ ] then builtins.head m else null) (
      builtins.split "(step-[0-9]+[a-z]?-[a-z-]+)" corpus
    )
  );

  danglingSteps = pkgs.lib.unique (builtins.filter (r: !(builtins.elem r existing)) referenced);

  # The scope ladder has to sit between Premises and Tasks: it needs the
  # restated target to judge against, and it decides which tasks exist at all.
  # The invariants above cannot see that — they search `corpus`, every step
  # concatenated, so the ladder can be moved wholesale into another step and
  # every one of them stays green. Measured. An index comparison inside the ONE
  # step is the only thing that pins the placement.
  #
  # splitString, not builtins.match: POSIX matching is leftmost-longest and `.`
  # crosses newlines, so a regex would bind a marker to its last occurrence. A
  # marker that is not unique is an error rather than a silent choice.
  planStep = skills.apexStep02Plan;
  idxOf =
    marker:
    let
      parts = pkgs.lib.splitString marker planStep;
    in
    if builtins.length parts != 2 then
      throw "apex-consistency: '${marker}' occurs ${
        toString (builtins.length parts - 1)
      } time(s) in step-02-plan, expected exactly 1 — the ordering assertion cannot pick one."
    else
      builtins.stringLength (builtins.head parts);

  ladderMisplaced =
    !(idxOf "**Premises**" < idxOf "**Scope ladder**" && idxOf "**Scope ladder**" < idxOf "**Tasks**");

  fail = msg: throw "apex-consistency: ${msg}";

in
pkgs.runCommand "apex-consistency-check" { } (
  if missingInvariants != [ ] then
    fail ("lost invariant(s): " + builtins.concatStringsSep "; " (map (i: i.name) missingInvariants))
  else if ladderMisplaced then
    fail "the scope ladder is no longer between Premises and Tasks in step-02-plan. It needs the restated target to judge against and it decides which tasks exist, so it runs after the first and before the second."
  else if danglingSteps != [ ] then
    fail ("reference(s) to non-existent step file(s): " + builtins.concatStringsSep ", " danglingSteps)
  else if modeDrift != [ ] then
    fail (
      "the UserPromptSubmit reminder no longer matches the Mode Gate table. Missing from hookApexReminder: "
      + builtins.concatStringsSep "; " (map (d: "'${d}'") modeDrift)
      + ". The table in apexStep00Init is the source of truth — update the hook line in hooks.nix to match it."
    )
  else if trivialAdvertised then
    fail "the UserPromptSubmit reminder still advertises a 'trivial' mode. That tier was removed on 2026-08-17; remove it from the hook line in hooks.nix."
  else if missingOptions != [ ] then
    fail (
      "opt-in flag(s) absent from the reminder's Options list: "
      + builtins.concatStringsSep ", " missingOptions
      + ". These are never auto-enabled, so the model has to be told they exist."
    )
  else if staleOptions != [ ] then
    fail (
      "the reminder still lists as opt-in: "
      + builtins.concatStringsSep ", " staleOptions
      + ". -o and -n are mode DEFAULTS now — listing them as options tells the model to type what it already gets."
    )
  else
    ''
      echo "apex-consistency: ${toString (builtins.length existing)} step files, ${toString (builtins.length invariants)} invariants, ${toString (builtins.length modeMap)} mode rows vs reminder — OK"
      touch $out
    ''
)
