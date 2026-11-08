# Skill deployment manifest — the ONE list of which skill text goes to which
# file. Everything that installs skills reads it; nothing hand-copies it.
#
# THE ONE THIS FILE EXISTS FOR: the same 33 paths were typed out by hand in
# `home/claude-code.nix`, and a second copy of the tree (for Codex, since retired)
# was kept by hand next to it. The two drifted for four months without a single
# error: a hand-maintained list cannot fail loudly, it can only be incomplete,
# and an absent skill file is a skill that silently never loads.
#
# `path` is RELATIVE to the skill's own directory; the consumer prefixes it
# itself (`.claude/skills/<name>/<path>`). Skills are Claude-only: Codex is a
# reviewer, not a TTW runner, and no longer receives a translated copy. It
# sits here rather than in a new top-level directory for one mechanical
# reason: `checks/readme-consistency.nix` does not walk the tree recursively,
# so a file in a new directory would be invisible to the inventory it enforces.
# Move it only together with the readme-consistency inventory.
# Exception: a third-party skill fetched as a pinned flake input (`watch`) is
# linked in home/claude-code.nix, since this file cannot see `inputs`.
#
# `force` IS NOT DATA HERE — IT IS A RULE, DERIVED FROM THE FILE NAME.
# Measured on the state this manifest replaces: 15 of the 33 entries carried
# `force = true`, and they are exactly the 14 `SKILL.md` plus
# `apex/eval-suite.json`; no file under `steps/` carried it. The flag exists
# because the desymlink activation script replaces every `*/SKILL.md` with a
# real copy, so home-manager must be allowed to clobber them. It does NOT
# touch ttw/eval-suite.json: that `force` is not required by desymlink, kept
# as-is, harmless. A consumer computes
# it — `force = baseNameOf path == "SKILL.md" || path == "eval-suite.json"` —
# and never stores it, because a stored flag is one more hand-kept list.
#
# ORDER IS PART OF THE CONTRACT. `manifest` is a LIST and must never become an
# attribute set: nix sorts attribute names alphabetically, and consumers see
# entries in the order they are given. A set would reorder the tree behind
# your back on the next read.
#
# No argument on purpose: `checks/ttw-consistency.nix` imports `skills.nix`
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
      name = "ttw";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillTtw;
        }
        {
          path = "steps/step-00-init.md";
          text = skills.ttwStep00Init;
        }
        {
          path = "steps/step-00b-save.md";
          text = skills.ttwStep00bSave;
        }
        {
          path = "steps/step-01-analyze.md";
          text = skills.ttwStep01Analyze;
        }
        {
          path = "steps/step-01b-obsidian-context.md";
          text = skills.ttwStep01bObsidianContext;
        }
        {
          path = "steps/step-02-plan.md";
          text = skills.ttwStep02Plan;
        }
        {
          path = "steps/step-02c-verify.md";
          text = skills.ttwStep02cVerify;
        }
        {
          path = "steps/step-02b-tasks.md";
          text = skills.ttwStep02bTasks;
        }
        {
          path = "steps/step-03-execute.md";
          text = skills.ttwStep03Execute;
        }
        {
          path = "steps/step-04-validate.md";
          text = skills.ttwStep04Validate;
        }
        {
          path = "steps/step-05-examine.md";
          text = skills.ttwStep05Examine;
        }
        {
          path = "steps/step-06-resolve.md";
          text = skills.ttwStep06Resolve;
        }
        {
          path = "steps/step-07-tests.md";
          text = skills.ttwStep07Tests;
        }
        {
          path = "steps/step-08-run-tests.md";
          text = skills.ttwStep08RunTests;
        }
        {
          path = "steps/step-09-finish.md";
          text = skills.ttwStep09Finish;
        }
        {
          path = "steps/step-09b-obsidian-note.md";
          text = skills.ttwStep09bObsidianNote;
        }
        {
          path = "steps/ROUTING.md";
          text = skills.ttwRouting;
        }
        {
          path = "steps/ORCHESTRATION.md";
          text = skills.ttwOrchestration;
        }
        {
          path = "steps/DIRECT.md";
          text = skills.ttwDirect;
        }
        {
          path = "steps/HIGH-STAKES.md";
          text = skills.ttwHighStakes;
        }
        {
          path = "steps/COMMANDS.md";
          text = skills.ttwCommands;
        }
        {
          path = "eval-suite.json";
          text = skills.ttwEvalSuite;
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
        {
          path = "references/cli-usage.md";
          text = skills.scraplingCliUsage;
        }
        {
          path = "references/code-overview.md";
          text = skills.scraplingCodeOverview;
        }
      ];
    }
    {
      # library/ (the awesome-design-md flake input) is a directory link,
      # declared in home/claude-code.nix: it is not skill text.
      name = "design-md";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillDesignMd;
        }
      ];
    }
    {
      # Router + our hig-audit; the upstream skill directories, LICENSE and
      # performance-cheatsheet.md (the emil-skills flake input) are
      # directory/file links declared in home/claude-code.nix.
      name = "ui-expert";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillUiExpert;
        }
        {
          path = "hig-audit/SKILL.md";
          text = skills.skillUiExpertHigAudit;
        }
      ];
    }
    {
      name = "ecriture-fr";
      files = [
        {
          path = "SKILL.md";
          text = skills.skillEcritureFr;
        }
      ];
    }
  ];
}
