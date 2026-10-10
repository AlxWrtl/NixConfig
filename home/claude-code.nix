{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  claudeDir = ".claude";

  # Import modular definitions
  settings = import ./claude-code/settings.nix { homeDirectory = config.home.homeDirectory; };
  commands = import ./claude-code/commands.nix;
  skillsManifest = import ./claude-code/skills-manifest.nix;
  graphifyReindex = import ./claude-code/graphify-reindex.nix { inherit pkgs; };
  vaultSnapshot = import ./claude-code/vault-snapshot.nix { inherit pkgs; };
  hooks = import ./claude-code/hooks.nix {
    inherit (graphifyReindex) graphifyReindexPkg;
    inherit (vaultSnapshot) vaultSnapshotPkg;
    inherit (settings) alxVaultPath;
  };
  agents = import ./claude-code/agents.nix;
  shell = import ./claude-code/shell.nix;
  claudeMd = import ./claude-code/claude-md.nix;
  rules = import ./claude-code/rules.nix;
  libdocs = import ./claude-code/libdocs.nix { inherit pkgs; };
  trello = import ./claude-code/trello.nix { inherit pkgs; };
  nixOptions = import ./claude-code/nix-options.nix { inherit pkgs; };
  scraplingShim = import ./claude-code/scrapling-shim.nix { inherit pkgs; };
  apexVerifyExternal = import ./claude-code/apex-verify-external.nix { inherit pkgs; };
  apexTier = import ./claude-code/apex-tier.nix { inherit pkgs; };
  activationScripts = import ./claude-code/activation.nix {
    inherit pkgs lib;
    inherit (scraplingShim) scraplingShimPkg;
    modsSrc = ./claude-code/mods;
    modNames = (import ./claude-code/mods.nix).names;
  };

  inherit (claudeMd) claudeMdGlobal;
  inherit (rules) ruleNix ruleTypescript ruleReact;
  inherit (libdocs) libdocsPkg;
  inherit (trello) trelloPkg;
  inherit (nixOptions) nixOptionsPkg;
  inherit (apexVerifyExternal) apexVerifyExternalPkg;
  inherit (apexTier) apexTierPkg;
  inherit (graphifyReindex) graphifyReindexPkg;
  inherit (vaultSnapshot) vaultSnapshotPkg;
  inherit (settings)
    settingsJson
    mcpServersJson
    keybindingsJson
    ;
  inherit (commands)
    cmdTdd
    cmdOptimize
    cmdContextPrime
    cmdAuto
    cmdCard
    commandDiscuss
    commandVerifyFeature
    featureChainScript
    ;
  inherit (hooks)
    hookProtectMain
    hookRequireApex
    hookApexFlags
    hookFormatTypescript
    hookBlockMainBash
    hookSessionStart
    hookGraphifyReindex
    hookVaultSnapshot
    hookApexReminder
    hookSubagentStop
    hookNotification
    hookCompactContext
    hookStopFailure
    hookCircuitBreaker
    hookCircuitBreakerReset
    hookQualityGate
    hookGovernanceAudit
    hookCorrectionBudget
    hookCorrectionGrant
    hookResearchModel
    hookReactDocsGate
    hookNullResultGate
    ;
  inherit (agents)
    agentFrontend
    agentBackend
    agentNavigator
    agentReviewer
    agentQuickFix
    agentNix
    agentGitShip
    agentTestRunner
    agentSecurityAuditor
    agentDebugger
    ;
  inherit (shell) aliases sessionVars;
  # Every skill file, derived from the manifest rather than typed out.
  #
  # `force` is COMPUTED, not stored: see the header of skills-manifest.nix.
  # It must stay true for every SKILL.md: claudeCodeDesymlinkSkills replaces
  # only `*/SKILL.md` with real copies, so home-manager has to be allowed to
  # clobber them. apex/eval-suite.json is NOT desymlinked; its `force` is not
  # required, kept as-is and harmless. A file under steps/ never carries it.
  skillFiles = builtins.listToAttrs (
    builtins.concatMap (
      skill:
      map (file: {
        name = "${claudeDir}/skills/${skill.name}/${file.path}";
        value = {
          inherit (file) text;
          force = baseNameOf file.path == "SKILL.md" || file.path == "eval-suite.json";
        };
      }) skill.files
    ) skillsManifest.manifest
  );

  # Write ~/.claude content declaratively
  claudeHomeFiles = skillFiles // {
    # Settings base (read-only reference, merged by activation script)
    "${claudeDir}/settings-base.json" = {
      text = settingsJson;
    };

    # MCP servers base (merged into .claude.json by activation script)
    "${claudeDir}/mcp-servers-base.json" = {
      text = mcpServersJson;
    };

    # Keybindings (symlink store, comme les commands/agents : le CLI ne fait que
    # LIRE ce fichier au démarrage, et son écriture de template est en flag "wx"
    # → EEXIST géré, jamais d'écrasement). Modif = édition de settings.nix.
    "${claudeDir}/keybindings.json" = {
      text = keybindingsJson;
    };

    "${claudeDir}/CLAUDE.md" = {
      text = claudeMdGlobal;
    };

    # design-md skill library: one directory link to the pinned flake input
    # (~70 brands × DESIGN.md). Not in the manifest: it is data, not skill
    # text, and a single link keeps the desymlink loop (`*/SKILL.md`) and the
    # `*.backup` purge (find does not follow links) off it.
    "${claudeDir}/skills/design-md/library".source = "${inputs.awesome-design-md}/design-md";

    # Rules (path-scoped, loaded on demand when a matching file is read)
    "${claudeDir}/rules/nix.md".text = ruleNix;
    "${claudeDir}/rules/typescript.md".text = ruleTypescript;
    "${claudeDir}/rules/react.md".text = ruleReact;

    # Commands
    "${claudeDir}/commands/tdd.md".text = cmdTdd;
    "${claudeDir}/commands/optimize.md".text = cmdOptimize;
    "${claudeDir}/commands/context-prime.md".text = cmdContextPrime;
    "${claudeDir}/commands/auto.md".text = cmdAuto;
    "${claudeDir}/commands/card.md".text = cmdCard;

    # Feature methodology commands
    "${claudeDir}/commands/discuss.md".text = commandDiscuss;
    "${claudeDir}/commands/verify-feature.md".text = commandVerifyFeature;

    # Skills come from skillFiles above, derived from skills-manifest.nix.

    # Feature chain script
    "${claudeDir}/feature-chain.sh" = {
      text = featureChainScript;
      executable = true;
    };

    # Agents (10)
    "${claudeDir}/agents/frontend-expert.md".text = agentFrontend;
    "${claudeDir}/agents/backend-expert.md".text = agentBackend;
    "${claudeDir}/agents/codebase-navigator.md".text = agentNavigator;
    "${claudeDir}/agents/code-reviewer.md".text = agentReviewer;
    "${claudeDir}/agents/quick-fix.md".text = agentQuickFix;
    "${claudeDir}/agents/nix-expert.md".text = agentNix;
    "${claudeDir}/agents/git-ship.md".text = agentGitShip;
    "${claudeDir}/agents/test-runner.md".text = agentTestRunner;
    "${claudeDir}/agents/security-auditor.md".text = agentSecurityAuditor;
    "${claudeDir}/agents/debugger.md".text = agentDebugger;

    # Hooks
    "${claudeDir}/hooks/protect-main.js" = {
      text = hookProtectMain;
      executable = true;
    };
    "${claudeDir}/hooks/require-apex.js" = {
      text = hookRequireApex;
      executable = true;
    };
    "${claudeDir}/hooks/apex-flags.js" = {
      text = hookApexFlags;
      executable = true;
    };
    "${claudeDir}/hooks/format-typescript.js" = {
      text = hookFormatTypescript;
      executable = true;
    };
    "${claudeDir}/hooks/block-main-bash.js" = {
      text = hookBlockMainBash;
      executable = true;
    };
    "${claudeDir}/hooks/session-start.sh" = {
      text = hookSessionStart;
      executable = true;
    };
    "${claudeDir}/hooks/graphify-reindex.sh" = {
      text = hookGraphifyReindex;
      executable = true;
    };
    "${claudeDir}/hooks/vault-snapshot.sh" = {
      text = hookVaultSnapshot;
      executable = true;
    };
    "${claudeDir}/hooks/apex-reminder.sh" = {
      text = hookApexReminder;
      executable = true;
    };
    "${claudeDir}/hooks/subagent-stop.js" = {
      text = hookSubagentStop;
      executable = true;
    };
    "${claudeDir}/hooks/notification.sh" = {
      text = hookNotification;
      executable = true;
    };
    "${claudeDir}/hooks/compact-context.sh" = {
      text = hookCompactContext;
      executable = true;
    };
    "${claudeDir}/hooks/stop-failure.sh" = {
      text = hookStopFailure;
      executable = true;
    };
    "${claudeDir}/hooks/circuit-breaker.js" = {
      text = hookCircuitBreaker;
      executable = true;
    };
    "${claudeDir}/hooks/circuit-breaker-reset.js" = {
      text = hookCircuitBreakerReset;
      executable = true;
    };
    "${claudeDir}/hooks/quality-gate.js" = {
      text = hookQualityGate;
      executable = true;
    };
    "${claudeDir}/hooks/governance-audit.js" = {
      text = hookGovernanceAudit;
      executable = true;
    };
    "${claudeDir}/hooks/correction-budget.js" = {
      text = hookCorrectionBudget;
      executable = true;
    };
    "${claudeDir}/hooks/correction-grant.js" = {
      text = hookCorrectionGrant;
      executable = true;
    };
    "${claudeDir}/hooks/research-model.js" = {
      text = hookResearchModel;
      executable = true;
    };
    "${claudeDir}/hooks/react-docs-gate.js" = {
      text = hookReactDocsGate;
      executable = true;
    };
    "${claudeDir}/hooks/null-result-gate.js" = {
      text = hookNullResultGate;
      executable = true;
    };
  };
in
{
  # Shell integration
  programs.zsh.shellAliases = aliases;
  programs.zsh.sessionVariables = sessionVars;

  home = {
    # npm global prefix (nix store is immutable, npm install -g needs a writable prefix)
    # ~/.local/bin = uv tool bin dir (`uv tool install` drops graphify/graphify-mcp there)
    sessionPath = [
      "$HOME/.npm-global/bin"
      "$HOME/.local/bin"
    ];

    file = claudeHomeFiles;

    # `libdocs` + `nix-options` + `trello` + `graphify-reindex` on PATH — usable
    # by Claude, by APEX and its subagents, and by the user in a plain terminal.
    # home.packages is a list: this merges with the other home modules.
    packages = [
      libdocsPkg
      trelloPkg
      nixOptionsPkg
      apexVerifyExternalPkg
      apexTierPkg
      graphifyReindexPkg
      vaultSnapshotPkg
    ];

    # Activation scripts
    activation = activationScripts;
  };
}
