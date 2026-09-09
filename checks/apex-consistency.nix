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
  # EVERY argument hooks.nix takes must be stubbed here. Adding one over there
  # without adding it here does not merely let a regression through — it makes
  # this whole file unevaluable, so `nix flake check` dies on "called without
  # required argument" and the check stops running at all. That is exactly what
  # `vaultSnapshotPkg` did when it was introduced.
  hooks = import ../home/claude-code/hooks.nix {
    graphifyReindexPkg = "/nix/store/00000000000000000000000000000000-stub";
    vaultSnapshotPkg = "/nix/store/00000000000000000000000000000000-stub";
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
      # Dependency-independent is not the same as file-disjoint. Two tasks in
      # one wave writing the same file lose one edit silently, and the
      # coordinator schedules the concurrency, so it owns the collision.
      name = "tasks: a wave is file-disjoint, not merely dependency-independent";
      needle = "FILE-DISJOINT, not merely dependency-independent";
      scope = skills.apexStep02bTasks;
    }
    {
      # The heading above is satisfied by a section with no test under it.
      # This is the operative sentence, and it is pairwise on purpose: a union
      # deduplicates, so it hides exactly the repeat being looked for.
      name = "tasks: the disjointness test is pairwise and voids the wave";
      needle = "If one path is named by more than one task, the wave is";
      scope = skills.apexStep02bTasks;
    }
    {
      # A planner-declared partition binds nothing unless the implementer is
      # told the list is a boundary it may not widen.
      name = "execute: the task's Files list is a boundary, not a hint";
      needle = "is a BOUNDARY, not a hint";
      scope = skills.apexStep03Execute;
    }
    {
      name = "orchestration: a worktree is not the fix for a colliding wave";
      needle = "Do NOT reach for a worktree to make a wave safe";
      scope = skills.apexOrchestration;
    }
    {
      # The reason, not just the prohibition. Without it the rule reads as
      # arbitrary and gets waived by the next reader.
      name = "orchestration: why not — isolation does not integrate";
      needle = "Isolation buys separation, not integration";
      scope = skills.apexOrchestration;
    }
    {
      # Worktree commits are invisible to the coordinator's git diff and to
      # step-09's add/push. Unowned, the work reaches neither commit nor PR.
      name = "orchestration: whoever spawns a worktree owns the merge";
      needle = "owns the merge";
      scope = skills.apexOrchestration;
    }
    {
      name = "orchestration: a fresh worktree has no dependencies";
      needle = "A new worktree has no `node_modules`";
      scope = skills.apexOrchestration;
    }
    {
      # Guarded separately from the dependency bullet: one needle covering a
      # two-part clause leaves half of it free to disappear.
      name = "orchestration: a fresh worktree's baseline is unproven";
      needle = "The baseline is unproven";
      scope = skills.apexOrchestration;
    }
    {
      # Taken after the first edit, the reading cannot separate "I broke it"
      # from "it was already broken". Scoped to step-00 because moving the
      # clause to step-04 is precisely the failure the name forbids.
      name = "init: the gate is read before the first edit, not after";
      needle = "run BEFORE the first edit";
      scope = skills.apexStep00Init;
    }
    {
      # Recorded and never read is the same as not recorded. This is the only
      # clause that makes the baseline do anything.
      name = "validate: the baseline verdict is consumed, not just stored";
      needle = "Baseline comparison";
      scope = skills.apexStep04Validate;
    }
    {
      # apex-consistency proves a clause is PRESENT. Three rules shipped in one
      # day that were present and did nothing. Presence is not effect, and this
      # is the only clause in the skill that tests effect.
      name = "orchestration: a rule that governs future runs is pressure-tested";
      needle = "Pressure-test";
      scope = skills.apexOrchestration;
    }
    {
      # The predicate is where the previous behavioural runner died: its
      # assertions matched free-form prose, so the words the model happened to
      # use counted as the result. 4/4, 2/4, 3/4, 3/4 on one identical case.
      name = "orchestration: the pressure-test predicate is mechanical, declared first";
      needle = "Declare the predicate FIRST";
      scope = skills.apexOrchestration;
    }
    {
      # Without the flip requirement the probe reports "the rule ran" rather
      # than "the rule changed something", which is the same nothing.
      name = "orchestration: the rule passes only if the predicate flips";
      needle = "passes only if the predicate FLIPS";
      scope = skills.apexOrchestration;
    }
    {
      # Measured on this very rule: one control run said clean flip, the second
      # said the opposite. A single run would have shipped a false claim.
      name = "orchestration: two runs per arm, and inconclusive is a result";
      needle = "INCONCLUSIVE is a result";
      scope = skills.apexOrchestration;
    }
    {
      # The predicate the eval-suite routing guard depends on. Reword it and
      # that guard goes quiet, letting the suite claim /debug again. Measured
      # 2026-09-05: "INSIDE apex" -> "inside APEX" left the derivation
      # byte-identical while the suite was free to drift.
      name = "handoffs: diagnosis is a mode, not an exit";
      needle = "Diagnosis stays INSIDE apex";
      scope = skills.skillApex;
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

  # An invariant may pin itself to ONE step instead of the whole corpus.
  # hasInfix over the concatenated corpus cannot tell "in step-00" from "moved
  # into step-04" — and for a clause whose whole point is WHERE it runs, that
  # distinction IS the rule. Measured 2026-09-05: relocating the baseline
  # clause from apexStep00Init into apexStep04Validate left the derivation
  # byte-identical, while the invariant guarding it is named "before the first
  # edit, not after".
  invariantScope = i: if i ? scope then i.scope else corpus;

  missingInvariants = builtins.filter (
    i: !(pkgs.lib.hasInfix i.needle (invariantScope i))
  ) invariants;

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

  # Premises come before Tasks: a task list written before the premises are
  # stated is a plan whose premises were reverse-engineered to fit it. The
  # invariants above cannot see ordering — they search `corpus`, every step
  # concatenated, so a section can be moved wholesale into another step and
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

  premisesMisplaced = !(idxOf "**Premises**" < idxOf "**Tasks**");

  # ---------------------------------------------------------------------------
  # The eval-suite drifted for months while nothing looked at it. schliff reads
  # it and scores 91/100, but schliff scores the SHAPE — how many triggers, how
  # many typed assertions — and cannot know that a case asserts behaviour the
  # skill stopped having. It happily graded a suite claiming diagnosis exits to
  # /debug, months after diagnosis became a mode of APEX.
  #
  # fromJSON rather than string matching: it inspects the structure, and a
  # malformed suite becomes an eval error instead of a file nobody parses.
  evalSuite = builtins.fromJSON skills.apexEvalSuite;

  # EVERY prompt, not just the triggers. Measured 2026-09-05: a dead flag
  # planted in a test_case prompt left the derivation byte-identical while the
  # same flag in a trigger went red — the guard covered a third of its target.
  suitePrompts = builtins.concatStringsSep "\n" (
    map (c: c.prompt) (evalSuite.triggers ++ evalSuite.test_cases ++ evalSuite.edge_cases)
  );

  # Flags typed in a prompt must be flags the skill still declares. This is the
  # drift that recurs — the suite outlived -a and -s by months. The rows of the
  # skill's own table are the source; nothing is restated here.
  suiteFlags = pkgs.lib.unique (
    map (m: "-" + builtins.head m) (
      builtins.filter builtins.isList (builtins.split "[^A-Za-z0-9-]-([A-Za-z0-9]+)" suitePrompts)
    )
  );
  unknownSuiteFlags = builtins.filter (
    f: !(pkgs.lib.hasInfix "| ${f} |" skills.skillApex)
  ) suiteFlags;

  # The section sizes schliff scores, verified against its own cliffs:
  # triggers < 8 caps the sub-score at 60, quality wants 3+ test_cases, edges
  # wants 5+. schliff counts WELL-FORMED cases, so three assertion-less stubs
  # would satisfy a length check here and score zero there.
  wellFormedCases = builtins.filter (c: (c.assertions or [ ]) != [ ]) evalSuite.test_cases;
  suiteTooThin =
    builtins.length evalSuite.triggers < 8
    || builtins.length wellFormedCases < 3
    || builtins.length evalSuite.edge_cases < 5;

  # Conditional on the skill's own clause: this only fires while the skill says
  # diagnosis is internal, so changing the routing changes the check with it.
  #
  # Scoped to the NARRATIVE fields. Searching the whole suite banned the string
  # everywhere, including inside an assertion whose job is to forbid /debug at
  # runtime — the guard was rejecting the strongest possible defence against
  # the regression it exists to catch.
  #
  # Honest limit: this catches the literal path, not a paraphrase. "hands it to
  # the debug command" passes. The predicate below is guarded as an invariant
  # so at least the clause it depends on cannot be reworded into silence.
  diagnosisIsInternal = pkgs.lib.hasInfix "Diagnosis stays INSIDE apex" corpus;
  suiteNarrative = builtins.concatStringsSep "\n" (
    map (c: c.expected_behavior or "") evalSuite.edge_cases
    ++ map (a: a.description) (builtins.concatMap (c: c.assertions) evalSuite.test_cases)
  );
  suiteContradictsRouting = diagnosisIsInternal && pkgs.lib.hasInfix "/debug" suiteNarrative;

  fail = msg: throw "apex-consistency: ${msg}";

in
pkgs.runCommand "apex-consistency-check" { } (
  if missingInvariants != [ ] then
    fail ("lost invariant(s): " + builtins.concatStringsSep "; " (map (i: i.name) missingInvariants))
  else if unknownSuiteFlags != [ ] then
    fail (
      "the eval-suite types flag(s) the skill no longer declares: "
      + builtins.concatStringsSep ", " unknownSuiteFlags
      + ". schliff scores the suite's shape and cannot see this — a trigger prompt for a removed flag grades as well as a correct one."
    )
  else if suiteContradictsRouting then
    fail "the eval-suite still routes diagnosis to /debug while the skill says diagnosis stays INSIDE apex. It graded 91/100 in that state for months, because schliff counts cases and cannot read them against the skill."
  else if suiteTooThin then
    fail "the eval-suite lost a section: schliff scores triggers, test_cases (3+) and edge_cases (5+), so gutting one costs skill score silently. It fails here instead."
  else if premisesMisplaced then
    fail "Premises no longer precede Tasks in step-02-plan. Premises written after the task list are premises reverse-engineered to fit it."
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
