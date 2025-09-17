{ config, pkgs, lib, ... }:

let
  # ============================================================================
  # CLAUDE CODE COMPLETE CONFIGURATION
  # ============================================================================
  # Approche déclarative complète basée sur les meilleures pratiques 2025
  # Contourne la limitation des symlinks de Claude Code via activation scripts
  # Configuration reproductible pour clean installs

  # === Configuration JSON principale ===
  claudeConfigJson = {
    # Modèle par défaut 2025
    defaultModel = "claude-sonnet-4-20250514";

    # Outils autorisés optimisés
    allowedTools = [
      "bash" "edit" "read" "write" "glob" "grep"
      "task" "webfetch" "websearch" "multiedit" "notebookedit"
    ];

    # Paramètres d'optimisation
    autoSave = true;
    skipPermissions = false;  # Sécurité

    # Interface utilisateur 2025
    ui = {
      theme = "dark";
      compactMode = false;
      showTokens = true;
      showCost = true;
      animations = true;
    };

    # Notifications système
    notifications = {
      enabled = true;
      channel = "terminal_bell";
      showProgress = true;
    };

    # Status line configuration
    statusline = {
      enabled = true;
      showModel = true;
      showTokens = true;
      showCost = true;
      showGitBranch = true;
      showTime = true;
      format = "simple";
    };

    # Hooks système
    hooks = {
      preEdit = [];
      postEdit = [];
    };

    # Performance 2025
    performance = {
      parallelTools = true;
      cacheEnabled = true;
      compactHistory = true;
    };
  };

  # === Settings JSON pour Claude Code ===
  settingsJson = {
    statusLine = {
      type = "command";
      command = "pnpm dlx ccstatusline@latest";
      padding = 0;
    };
    env = {
      npm_config_prefer_pnpm = "true";
      npm_config_user_agent = "pnpm";
      BASH_DEFAULT_TIMEOUT_MS = "300000";
      BASH_MAX_TIMEOUT_MS = "600000";
    };
  };


  # === Commandes personnalisées TDD ===
  tddCommand = ''
    ---
    allowed-tools: ["bash", "edit", "read", "write", "grep", "glob", "multiedit"]
    description: "Test-Driven Development workflow avec tests automatisés"
    argument-hint: "<feature-description>"
    ---

    # Test-Driven Development Command

    Développement guidé par les tests pour: $ARGUMENTS

    ## Processus TDD 2025
    1. 🔍 **Analyse**: Comprendre les exigences et patterns de test existants
    2. ❌ **Red**: Écrire le test qui échoue d'abord
    3. ✅ **Green**: Code minimal pour faire passer le test
    4. 🔄 **Refactor**: Améliorer en gardant les tests verts
    5. 🧪 **Validation**: Lancer la suite complète de tests
    6. 📝 **Documentation**: Mettre à jour la doc si nécessaire

    Toujours lancer les tests après chaque étape et maintenir 100% de couverture.
  '';

  optimizeCommand = ''
    ---
    allowed-tools: ["bash", "edit", "read", "grep", "glob", "webfetch"]
    description: "Optimisation de performance avec pratiques 2025"
    argument-hint: "<optimization-target>"
    ---

    # Performance Optimization Command

    Optimiser: $ARGUMENTS

    ## Zones d'optimisation 2025
    - 🚀 **Bundle size**: Code splitting, tree shaking
    - ⚡ **Runtime**: Optimisation algorithmique, mise en cache
    - 🖼️ **Assets**: Optimisation d'images, lazy loading
    - 📡 **Network**: CDN, compression, HTTP/3
    - 💾 **Memory**: Garbage collection, fuites mémoire
    - 🔄 **Rendering**: Virtual DOM, Web Workers

    ## Processus
    1. Profiler les performances actuelles
    2. Identifier les goulots d'étranglement
    3. Appliquer des optimisations ciblées
    4. Mesurer les améliorations
    5. Documenter les changements
  '';

  contextPrimeCommand = ''
    # Context Prime Command

    Charger une compréhension complète du projet:
    1. Lire CLAUDE.md et la documentation du projet
    2. Analyser la structure des répertoires et fichiers clés
    3. Comprendre la stack technologique et dépendances
    4. Examiner l'historique git et changements récents
    5. Identifier les patterns de test et processus de build

    Fournit un contexte approfondi pour une assistance code informée.
  '';

  # === Wrapper Claude Code ===
  claudeCodeWrapper = pkgs.writeShellScriptBin "claude-code" ''
    # Wrapper Claude Code avec validation et installation automatique
    CLAUDE_DIR="$HOME/.claude"
    CLI_PATH="$CLAUDE_DIR/local/node_modules/@anthropic-ai/claude-code/cli.js"

    # Vérification et installation automatique si nécessaire
    if [ ! -f "$CLI_PATH" ]; then
        echo "🚀 Installation de Claude Code CLI..."
        mkdir -p "$CLAUDE_DIR/local"
        cd "$CLAUDE_DIR/local"

        # Installation via pnpm (recommandé 2025)
        if command -v ${pkgs.pnpm}/bin/pnpm >/dev/null 2>&1; then
            ${pkgs.pnpm}/bin/pnpm add @anthropic-ai/claude-code
        elif command -v npm >/dev/null 2>&1; then
            npm install @anthropic-ai/claude-code
        else
            echo "❌ npm ou pnpm requis pour installer Claude Code CLI" >&2
            exit 1
        fi

        if [ ! -f "$CLI_PATH" ]; then
            echo "❌ Échec de l'installation de Claude Code CLI" >&2
            exit 1
        fi

        echo "✅ Claude Code CLI installé avec succès"
    fi

    # Exécution avec Node.js et tous les arguments
    exec ${pkgs.nodejs}/bin/node "$CLI_PATH" "$@"
  '';

in {
  # ============================================================================
  # ACTIVATION SCRIPTS - SOLUTION RECOMMANDÉE 2025
  # ============================================================================
  # Contourne la limitation des symlinks de Claude Code
  # Copie les fichiers dans ~/.claude lors de l'activation système

  system.activationScripts.claudeCodeSetup = {
    text = ''
      echo "🤖 Configuration Claude Code (approche déclarative)..."

      # Répertoire Claude
      CLAUDE_DIR="$HOME/.claude"

      # Création de la structure complète
      mkdir -p "$CLAUDE_DIR"/{hooks,commands,mcp,projects,local}

      # Configuration principale (settings.json)
      cat > "$CLAUDE_DIR/settings.json" << 'EOF'
${builtins.toJSON settingsJson}
EOF

      # Configuration Claude (.claude.json)
      cat > "$CLAUDE_DIR/.claude.json" << 'EOF'
${builtins.toJSON claudeConfigJson}
EOF


      # Commandes personnalisées
      cat > "$CLAUDE_DIR/commands/tdd.md" << 'EOF'
${tddCommand}
EOF

      cat > "$CLAUDE_DIR/commands/optimize.md" << 'EOF'
${optimizeCommand}
EOF

      cat > "$CLAUDE_DIR/commands/context-prime.md" << 'EOF'
${contextPrimeCommand}
EOF

      # Configuration MCP de base
      cat > "$CLAUDE_DIR/mcp/servers.json" << 'EOF'
{
  "mcpServers": {}
}
EOF

      # Permissions correctes
      chmod -R 755 "$CLAUDE_DIR"
      chmod 644 "$CLAUDE_DIR"/{settings.json,.claude.json}
      chmod 644 "$CLAUDE_DIR/commands"/*.md

      echo "✅ Configuration Claude Code installée dans $CLAUDE_DIR"
    '';
  };

  # ============================================================================
  # PACKAGES ET ENVIRONNEMENT
  # ============================================================================

  environment.systemPackages = [
    claudeCodeWrapper
  ];

  environment.variables = {
    # Claude Code 2025
    CLAUDE_MODEL = "claude-sonnet-4-20250514";
    CLAUDE_MAX_TOKENS = "8192";
    CLAUDE_CONFIG_DIR = "$HOME/.claude";
    CLAUDE_NOTIFY_CHANNEL = "terminal_bell";
    CLAUDE_ENABLE_MCP = "true";
    CLAUDE_SESSION_AUTOSAVE = "true";
    CLAUDE_HOOKS_ENABLED = "true";
    CLAUDE_PARALLEL_TOOLS = "true";
    CLAUDE_CACHE_ENABLED = "true";
    CLAUDE_PLAN_MODE_DEFAULT = "false";

    # Package managers
    npm_config_prefer_pnpm = "true";
    npm_config_user_agent = "pnpm";
  };

  # ============================================================================
  # ALIASES OPTIMISÉS 2025
  # ============================================================================

  environment.shellAliases = {
    # Raccourcis essentiels
    cc = "claude-code";
    claude = "claude-code";

    # Opérations de base
    cc-init = "claude-code /init";
    cc-help = "claude-code --help";
    cc-doctor = "claude-code doctor";
    cc-version = "claude-code --version";

    # Workflows avancés
    cc-resume = "claude-code --resume";
    cc-continue = "claude-code --continue";
    cc-plan = "claude-code --plan-mode";

    # Sélection de modèles
    cc-opus = "claude-code --model claude-opus-4";
    cc-sonnet = "claude-code --model claude-sonnet-4";
    cc-haiku = "claude-code --model claude-haiku";

    # Commandes spécialisées 2025
    cc-tdd = "claude-code /tdd";
    cc-optimize = "claude-code /optimize";
    cc-context = "claude-code /context-prime";
    cc-safe = "claude-code --plan-mode --read-only";

    # Gestion des sessions
    cc-clear = "claude-code /clear";
    cc-compact = "claude-code /compact";
  };
}