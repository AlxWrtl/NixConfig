# Skill deployment manifest — the ONE list of which skill text goes to which
# file. Everything that installs skills reads it; nothing hand-copies it.
#
# THE ONE THIS FILE EXISTS FOR: the same 33 paths were typed out by hand in
# `home/claude-code.nix`, and a second copy of the tree under `~/.agents/skills/`
# was kept by hand next to it. The two drifted for four months without a single
# error: a hand-maintained list cannot fail loudly, it can only be incomplete,
# and an absent skill file is a skill that silently never loads. A third
# consumer (Codex) is being added, which is exactly the moment a second
# hand-written list becomes a third.
#
# AGENT-AGNOSTIC, DESPITE THE DIRECTORY. This file lives under `claude-code/`
# and describes NOTHING Claude-specific. `path` is RELATIVE to the skill's own
# directory; each consumer prefixes it itself (`.claude/skills/<name>/<path>`,
# `.agents/skills/<name>/<path>`, …). It sits here rather than in a new
# top-level directory for two mechanical reasons, not for a conceptual one:
#   - `flake.nix` runs nixfmt over `home/claude-code/*.nix` and over no
#     directory that does not exist yet, so a new home would be unformatted
#     and unchecked;
#   - `checks/readme-consistency.nix` does not walk the tree recursively, so a
#     file in a new directory would be invisible to the inventory it enforces.
# Move it only together with both of those.
#
# `force` IS NOT DATA HERE — IT IS A RULE, DERIVED FROM THE FILE NAME.
# Measured on the state this manifest replaces: 15 of the 33 entries carried
# `force = true`, and they are exactly the 14 `SKILL.md` plus
# `apex/eval-suite.json`; no file under `steps/` carried it. The flag exists
# because the desymlink activation script replaces those files with real
# copies, so home-manager must be allowed to clobber them. A consumer computes
# it — `force = baseNameOf path == "SKILL.md" || path == "eval-suite.json"` —
# and never stores it, because a stored flag is one more hand-kept list.
#
# ORDER IS PART OF THE CONTRACT. `manifest` is a LIST and must never become an
# attribute set: nix sorts attribute names alphabetically, and the Codex module
# writes its output in the order it is given. A set would reorder the tree
# behind your back on the next read.
#
# No argument on purpose: `checks/apex-consistency.nix` imports `skills.nix`
# bare, and any check must be able to import this the same way.
let
  skills = import ./skills.nix;
in
{
  manifest = [
    {
      name = "feature-workflow";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillFeatureWorkflow;
        }
      ];
    }
    {
      name = "apex";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillApex;
        }
        {
          path = "steps/step-00-init.md";
          text = skills.apexStep00Init;
        }
        {
          path = "steps/step-00b-branch.md";
          text = skills.apexStep00bBranch;
        }
        {
          path = "steps/step-00b-save.md";
          text = skills.apexStep00bSave;
        }
        {
          path = "steps/step-01-analyze.md";
          text = skills.apexStep01Analyze;
        }
        {
          path = "steps/step-01b-obsidian-context.md";
          text = skills.apexStep01bObsidianContext;
        }
        {
          path = "steps/step-02-plan.md";
          text = skills.apexStep02Plan;
        }
        {
          path = "steps/step-02c-verify.md";
          text = skills.apexStep02cVerify;
        }
        {
          path = "steps/step-02b-tasks.md";
          text = skills.apexStep02bTasks;
        }
        {
          path = "steps/step-03-execute.md";
          text = skills.apexStep03Execute;
        }
        {
          path = "steps/step-04-validate.md";
          text = skills.apexStep04Validate;
        }
        {
          path = "steps/step-05-examine.md";
          text = skills.apexStep05Examine;
        }
        {
          path = "steps/step-06-resolve.md";
          text = skills.apexStep06Resolve;
        }
        {
          path = "steps/step-07-tests.md";
          text = skills.apexStep07Tests;
        }
        {
          path = "steps/step-08-run-tests.md";
          text = skills.apexStep08RunTests;
        }
        {
          path = "steps/step-09-finish.md";
          text = skills.apexStep09Finish;
        }
        {
          path = "steps/step-09b-obsidian-note.md";
          text = skills.apexStep09bObsidianNote;
        }
        {
          path = "steps/ROUTING.md";
          text = skills.apexRouting;
        }
        {
          path = "steps/ORCHESTRATION.md";
          text = skills.apexOrchestration;
        }
        {
          path = "eval-suite.json";
          text = skills.apexEvalSuite;
        }
      ];
    }
    {
      name = "debug";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillDebug;
        }
      ];
    }
    {
      name = "nix-darwin";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillNixDarwin;
        }
      ];
    }
    {
      name = "claude-code-meta";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillClaudeCodeMeta;
        }
      ];
    }
    {
      name = "obsidian";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillObsidian;
        }
      ];
    }
    {
      name = "schliff";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillSchliff;
        }
      ];
    }
    {
      name = "autoresearch";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillAutoresearch;
        }
      ];
    }
    {
      name = "testing-patterns";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillTestingPatterns;
        }
      ];
    }
    {
      name = "codebase-audit";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillCodebaseAudit;
        }
      ];
    }
    {
      name = "caveman";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillCaveman;
        }
      ];
    }
    {
      name = "cavemem";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillCavemem;
        }
      ];
    }
    {
      name = "trello";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillTrello;
        }
      ];
    }
    {
      name = "scrapling";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillScrapling;
        }
      ];
    }
  ];
}
