{
  config,
  pkgs,
  lib,
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
  };
  agents = import ./claude-code/agents.nix;
  shell = import ./claude-code/shell.nix;
  claudeMd = import ./claude-code/claude-md.nix;
  rules = import ./claude-code/rules.nix;
  libdocs = import ./claude-code/libdocs.nix { inherit pkgs; };
  scraplingShim = import ./claude-code/scrapling-shim.nix { inherit pkgs; };
  apexVerifyExternal = import ./claude-code/apex-verify-external.nix { inherit pkgs; };
  activationScripts = import ./claude-code/activation.nix {
    inherit pkgs lib;
    inherit (scraplingShim) scraplingShimPkg;
  };

  inherit (claudeMd) claudeMdGlobal;
  inherit (rules) ruleNix ruleTypescript ruleReact;
  inherit (libdocs) libdocsPkg;
  inherit (apexVerifyExternal) apexVerifyExternalPkg;
  inherit (graphifyReindex) graphifyReindexPkg;
  inherit (vaultSnapshot) vaultSnapshotPkg;
  inherit (settings)
    settingsJson
    statuslineScript
    mcpServersJson
    keybindingsJson
    ;
  inherit (commands)
    cmdTdd
    cmdOptimize
    cmdContextPrime
    cmdAuto
    cmdRalphLoop
    cmdCancelRalph
    cmdCard
    commandDiscuss
    commandVerifyFeature
    featureChainScript
    ;
  inherit (hooks)
    hookRtkNixRewrite
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
    hookTaskCompleted
    hookNotification
    hookCompactContext
    hookStopFailure
    hookCircuitBreaker
    hookCircuitBreakerReset
    hookPreCompactState
    hookPostCompactRestore
    hookQualityGate
    hookGovernanceAudit
    hookReactDocsGate
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
  # It must stay true for exactly the 14 SKILL.md plus apex/eval-suite.json,
  # because claudeCodeDesymlinkSkills replaces those with real copies and
  # home-manager has to be allowed to clobber them. A file under steps/ never
  # carries it.
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
in
{
  # Shell integration
  programs.zsh.shellAliases = aliases;
  programs.zsh.sessionVariables = sessionVars;

  # npm global prefix (nix store is immutable, npm install -g needs a writable prefix)
  # ~/.local/bin = uv tool bin dir (`uv tool install` drops graphify/graphify-mcp there)
  home.sessionPath = [
    "$HOME/.npm-global/bin"
    "$HOME/.local/bin"
  ];

  # Write ~/.claude content declaratively
  home.file = skillFiles // {
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

    # Rules (path-scoped, loaded on demand when a matching file is read)
    "${claudeDir}/rules/nix.md".text = ruleNix;
    "${claudeDir}/rules/typescript.md".text = ruleTypescript;
    "${claudeDir}/rules/react.md".text = ruleReact;

    # Commands
    "${claudeDir}/commands/tdd.md".text = cmdTdd;
    "${claudeDir}/commands/optimize.md".text = cmdOptimize;
    "${claudeDir}/commands/context-prime.md".text = cmdContextPrime;
    "${claudeDir}/commands/auto.md".text = cmdAuto;
    "${claudeDir}/commands/ralph-loop.md".text = cmdRalphLoop;
    "${claudeDir}/commands/cancel-ralph.md".text = cmdCancelRalph;
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

    # Agents (13)
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
    "${claudeDir}/hooks/task-completed.sh" = {
      text = hookTaskCompleted;
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
    "${claudeDir}/hooks/pre-compact-state.js" = {
      text = hookPreCompactState;
      executable = true;
    };
    "${claudeDir}/hooks/post-compact-restore.js" = {
      text = hookPostCompactRestore;
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
    "${claudeDir}/hooks/rtk-nix-rewrite.sh" = {
      text = hookRtkNixRewrite;
      executable = true;
    };
    "${claudeDir}/hooks/react-docs-gate.js" = {
      text = hookReactDocsGate;
      executable = true;
    };

    # Statusline script
    "${claudeDir}/statusline.sh" = {
      text = statuslineScript;
      executable = true;
    };
  };

  # `libdocs` + `graphify-reindex` on PATH — usable by Claude, by APEX and its
  # subagents, and by the user in a plain terminal. home.packages is a list:
  # this merges with the definitions in the other home modules.
  home.packages = [
    libdocsPkg
    apexVerifyExternalPkg
    graphifyReindexPkg
    vaultSnapshotPkg
  ];

  # Activation scripts
  home.activation = activationScripts;
}
