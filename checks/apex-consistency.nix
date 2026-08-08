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

  # Step file basename -> the nix attribute holding its content.
  steps = {
    "step-00-init" = skills.apexStep00Init;
    "step-00b-interactive" = skills.apexStep00bInteractive;
    "step-00b-branch" = skills.apexStep00bBranch;
    "step-00b-economy" = skills.apexStep00bEconomy;
    "step-00b-save" = skills.apexStep00bSave;
    "step-01-analyze" = skills.apexStep01Analyze;
    "step-01b-obsidian-context" = skills.apexStep01bObsidianContext;
    "step-02-plan" = skills.apexStep02Plan;
    "step-02b-tasks" = skills.apexStep02bTasks;
    "step-02c-verify" = skills.apexStep02cVerify;
    "step-03-execute" = skills.apexStep03Execute;
    "step-03-execute-teams" = skills.apexStep03ExecuteTeams;
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
  ];

  missingInvariants = builtins.filter (i: !(pkgs.lib.hasInfix i.needle corpus)) invariants;

  # Step files named in the corpus that do not exist as attributes.
  # The capture group is required: builtins.split yields an empty list for a
  # match with no groups, and head on it throws.
  referenced = builtins.filter (n: n != null) (
    map (m: if builtins.isList m && m != [ ] then builtins.head m else null) (
      builtins.split "(step-[0-9]+[a-z]?-[a-z-]+)" corpus
    )
  );

  danglingSteps = pkgs.lib.unique (builtins.filter (r: !(builtins.elem r existing)) referenced);

  fail = msg: throw "apex-consistency: ${msg}";

in
pkgs.runCommand "apex-consistency-check" { } (
  if missingInvariants != [ ] then
    fail ("lost invariant(s): " + builtins.concatStringsSep "; " (map (i: i.name) missingInvariants))
  else if danglingSteps != [ ] then
    fail ("reference(s) to non-existent step file(s): " + builtins.concatStringsSep ", " danglingSteps)
  else
    ''
      echo "apex-consistency: ${toString (builtins.length existing)} step files, ${toString (builtins.length invariants)} invariants — OK"
      touch $out
    ''
)
