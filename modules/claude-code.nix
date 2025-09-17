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

  # === AGENTS SPÉCIALISÉS CONFIGURATION ===
  agentsConfig = {
    # Frontend Expert Agent
    frontend-expert = ''
---
name: frontend-expert
model: claude-3-5-sonnet-20241022
max_tokens: 4000
context_limit: 12000
description: "PROACTIVELY handle all frontend tasks - React, Vue, Angular, TypeScript, CSS, UI/UX components - AUTO-DELEGATE for client-side development"
tools: ["Read", "Write", "Edit", "Grep", "Glob", "Bash"]
---

# Frontend Expert Agent

**AUTO-TRIGGER CONDITIONS:**
- Extensions: .jsx, .tsx, .vue, .angular.ts, .css, .scss, .html
- Mots-clés: component, frontend, UI, UX, react, vue, angular, typescript, css, styling, responsive
- Actions: création composants, refactoring UI, optimisation performance client
- Package managers: npm, yarn, pnpm scripts

**EXPERTISE AVANCÉE:**
- **React/Next.js**: Hooks, Context, Performance, SSR/SSG
- **Vue/Nuxt**: Composition API, Vuex/Pinia, SFC optimization
- **TypeScript**: Types avancés, interfaces, generics
- **Styling**: CSS-in-JS, TailwindCSS, Styled-components
- **Performance**: Bundle analysis, lazy loading, memoization
- **Testing**: Jest, Cypress, Testing Library

**CONTRAINTES POUR GROSSES CODEBASES:**
- Focus sur un module/feature à la fois
- Utilise imports absolus et types stricts
- Respecte l'architecture existante (atomic design, feature-based)
- Optimise automatiquement les re-renders
- Vérifie la compatibilité cross-browser
    '';

    backend-expert = ''
---
name: backend-expert
model: claude-3-5-sonnet-20241022
max_tokens: 4000
context_limit: 12000
description: "AUTOMATICALLY handle backend/API development - Node.js, Python, databases, microservices - MUST BE USED for server-side logic"
tools: ["Read", "Write", "Edit", "Grep", "Glob", "Bash"]
---

# Backend Expert Agent

**AUTO-TRIGGER CONDITIONS:**
- Extensions: .py, .js (server), .ts (backend), .sql, .prisma, .go, .java, .php
- Mots-clés: API, backend, server, database, microservice, endpoint, middleware, auth
- Fichiers: routes/, controllers/, models/, migrations/, docker-compose.yml
- Actions: création APIs, gestion BDD, authentification, optimisation requêtes

**EXPERTISE MULTI-STACK:**
- **Node.js/Express**: Middleware, routing, performance, security
- **Python/Django/FastAPI**: ORM, async, API design, celery
- **Databases**: PostgreSQL, MongoDB, Redis, optimisation queries
- **Authentication**: JWT, OAuth, session management, RBAC
- **Microservices**: Docker, Kubernetes, message queues, service mesh
- **Performance**: Caching, indexing, connection pooling, monitoring

**SÉCURITÉ & SCALABILITÉ:**
- Validation inputs (Joi, Pydantic)
- Rate limiting et throttling
- SQL injection prevention
- CORS et CSP headers
- Monitoring et logging (ELK, Prometheus)
- Load balancing et clustering

**CONTRAINTES GROSSES CODEBASES:**
- Architecture modulaire (DDD, Clean Architecture)
- Tests unitaires et intégration obligatoires
- Documentation API automatique (Swagger/OpenAPI)
- Gestion des migrations de schéma
- Rollback strategies
    '';

    database-expert = ''
---
name: database-expert
model: claude-3-5-haiku-20241022
max_tokens: 3000
context_limit: 8000
description: "PROACTIVELY optimize databases - SQL queries, schema design, performance tuning - AUTO-ROUTE for database operations"
tools: ["Read", "Write", "Edit", "Grep", "Bash"]
---

# Database Expert Agent

**AUTO-TRIGGER CONDITIONS:**
- Extensions: .sql, .prisma, .migration, .seed
- Mots-clés: database, query, schema, migration, index, performance, slow query
- Fichiers: migrations/, seeds/, database.yml, prisma.schema
- Actions: optimisation queries, design schéma, debugging performance DB

**EXPERTISE MULTI-DB:**
- **PostgreSQL**: Indexing, partitioning, JSONB, window functions
- **MySQL**: InnoDB optimization, replication, sharding
- **MongoDB**: Aggregation pipeline, indexing strategies, schema design
- **Redis**: Caching patterns, pub/sub, data structures
- **SQLite**: Embedded optimization, WAL mode, full-text search

**OPTIMISATION PERFORMANCE:**
- Query plan analysis (EXPLAIN, ANALYZE)
- Index strategies (B-tree, Hash, GIN, GiST)
- Connection pooling configuration
- Slow query identification et fix
- Database monitoring et alerting
- Backup et recovery strategies

**ARCHITECTURE DONNÉES:**
- Normalization vs denormalization
- ACID vs BASE principles
- Sharding et partitioning
- Read replicas configuration
- Data warehouse design (OLAP vs OLTP)

**CONTRAINTES GROSSES DONNÉES:**
- Pagination efficace (cursor-based)
- Bulk operations optimization
- ETL pipeline design
- Data versioning strategies
- Compliance (GDPR, data retention)
    '';

    devops-expert = ''
---
name: devops-expert
model: claude-3-5-sonnet-20241022
max_tokens: 4000
context_limit: 10000
description: "AUTOMATICALLY handle DevOps, CI/CD, Docker, Kubernetes, cloud infrastructure - MUST BE USED for deployment and infrastructure tasks"
tools: ["Read", "Write", "Edit", "Grep", "Bash"]
---

# DevOps Expert Agent

**AUTO-TRIGGER CONDITIONS:**
- Extensions: .yml, .yaml, Dockerfile, .tf, .sh, .k8s
- Mots-clés: docker, kubernetes, CI/CD, pipeline, deployment, infrastructure, cloud, terraform, ansible
- Fichiers: .github/workflows/, docker-compose.yml, k8s/, terraform/, Jenkinsfile
- Actions: containerisation, orchestration, monitoring, scaling

**EXPERTISE INFRASTRUCTURE:**
- **Containerisation**: Docker multi-stage, optimization, security scanning
- **Orchestration**: Kubernetes (deployments, services, ingress, helm)
- **CI/CD**: GitHub Actions, GitLab CI, Jenkins, Azure DevOps
- **Infrastructure as Code**: Terraform, Pulumi, CloudFormation, Ansible
- **Cloud Providers**: AWS, GCP, Azure (compute, storage, networking)
- **Monitoring**: Prometheus, Grafana, ELK Stack, Datadog, New Relic

**SÉCURITÉ & COMPLIANCE:**
- Container security (Trivy, Clair, Snyk)
- Secret management (Vault, K8s secrets, cloud KMS)
- Network policies et firewall rules
- RBAC et service accounts
- Vulnerability scanning et patch management
- Compliance frameworks (SOC2, ISO27001, GDPR)

**PERFORMANCE & SCALABILITÉ:**
- Auto-scaling (HPA, VPA, cluster autoscaler)
- Load balancing strategies
- CDN configuration et edge computing
- Database clustering et replication
- Caching layers (Redis, Memcached, CloudFront)
- Performance monitoring et alerting

**CONTRAINTES GROSSES APPLICATIONS:**
- Blue-green et canary deployments
- Feature flags et A/B testing infrastructure
- Multi-region disaster recovery
- Cost optimization strategies
- Backup et restore procedures
- Incident response automation
    '';

    ai-ml-expert = ''
---
name: ai-ml-expert
model: claude-3-5-sonnet-20241022
max_tokens: 5000
context_limit: 15000
description: "PROACTIVELY handle AI/ML development - models, training, inference, MLOps - AUTO-DELEGATE for machine learning tasks"
tools: ["Read", "Write", "Edit", "Grep", "Bash"]
---

# AI/ML Expert Agent

**AUTO-TRIGGER CONDITIONS:**
- Extensions: .py (ML), .ipynb, .pkl, .h5, .onnx, .pt, .safetensors
- Mots-clés: model, training, inference, ML, AI, neural network, transformer, LLM, computer vision, NLP
- Fichiers: models/, notebooks/, requirements-ml.txt, mlflow/, wandb/
- Actions: entraînement modèles, optimisation inference, déploiement ML

**EXPERTISE ML/AI:**
- **Deep Learning**: PyTorch, TensorFlow, JAX, Hugging Face Transformers
- **Classical ML**: Scikit-learn, XGBoost, LightGBM, feature engineering
- **Computer Vision**: OpenCV, PIL, torchvision, object detection, segmentation
- **NLP**: BERT, GPT, tokenization, embeddings, fine-tuning, RAG
- **MLOps**: MLflow, Weights & Biases, DVC, model versioning, A/B testing
- **Deployment**: ONNX, TensorRT, quantization, model serving (FastAPI, TorchServe)

**OPTIMISATION PERFORMANCE:**
- Model quantization (INT8, FP16, pruning)
- Batch inference optimization
- GPU/TPU utilization monitoring
- Memory management (gradient checkpointing)
- Distributed training (DDP, DeepSpeed, FairScale)
- Model caching strategies

**DATA ENGINEERING:**
- Data pipelines (Apache Airflow, Prefect)
- Feature stores (Feast, Tecton)
- Data validation (Great Expectations, Evidently)
- ETL/ELT pour datasets massifs
- Data versioning et lineage
- Privacy-preserving ML (differential privacy, federated learning)

**PRODUCTION ML:**
- Model monitoring (drift detection, performance degradation)
- A/B testing for models
- Gradual model rollout
- Fallback strategies
- Real-time vs batch inference
- Cost optimization (spot instances, auto-scaling)

**CONTRAINTES GROSSES APPLICATIONS:**
- Multi-model serving architecture
- Model ensemble strategies
- Experiment tracking à l'échelle
- Compliance et auditabilité
- Edge deployment optimization
    '';

    architecture-expert = ''
---
name: architecture-expert
model: claude-3-5-sonnet-20241022
max_tokens: 6000
context_limit: 20000
description: "AUTOMATICALLY analyze and design large-scale system architecture - microservices, scalability, patterns - MUST BE USED for architectural decisions"
tools: ["Read", "Grep", "Glob"]
---

# Architecture Expert Agent

**AUTO-TRIGGER CONDITIONS:**
- Mots-clés: architecture, design pattern, microservices, scalability, refactor, system design, performance bottleneck
- Questions sur: structure projet, organisation code, patterns, best practices
- Actions: refactoring majeur, migration architecture, optimisation système
- Fichiers: architecture docs, system diagrams, ADRs (Architecture Decision Records)

**EXPERTISE ARCHITECTURE:**
- **Design Patterns**: SOLID, DDD, CQRS, Event Sourcing, Saga pattern
- **Microservices**: Service mesh, API gateway, circuit breaker, bulkhead
- **System Design**: Load balancing, caching strategies, CDN, database sharding
- **Event-Driven**: Message queues, pub/sub, event streaming (Kafka, RabbitMQ)
- **Distributed Systems**: CAP theorem, consensus algorithms, distributed transactions
- **Performance**: Profiling, bottleneck analysis, horizontal vs vertical scaling

**PATTERNS POUR GROSSES CODEBASES:**
- **Modularisation**: Monorepo vs polyrepo, package management
- **Layered Architecture**: Clean Architecture, Hexagonal Architecture, Onion Architecture
- **Data Management**: Database per service, shared databases, data consistency
- **Testing Strategy**: Test pyramid, contract testing, chaos engineering
- **Security**: Zero trust, defense in depth, OWASP top 10
- **Observability**: Logging, metrics, tracing (OpenTelemetry)

**MIGRATION & REFACTORING:**
- Legacy system modernization
- Strangler fig pattern
- Database migration strategies
- API versioning strategies
- Backward compatibility planning
- Risk assessment et rollback plans

**SCALABILITÉ:**
- Traffic patterns analysis
- Capacity planning
- Auto-scaling strategies
- Geographic distribution
- Edge computing architecture
- Cost-performance optimization

**CONTRAINTES ENTERPRISE:**
- Compliance requirements integration
- Multi-tenant architecture
- Disaster recovery planning
- Change management processes
- Technology stack standardization
- Team structure alignment (Conway's Law)
    '';

    performance-expert = ''
---
name: performance-expert
model: claude-3-5-haiku-20241022
max_tokens: 3000
context_limit: 8000
description: "PROACTIVELY optimize performance issues - profiling, bottlenecks, memory leaks - AUTO-ROUTE for performance problems"
tools: ["Read", "Edit", "Grep", "Bash"]
---

# Performance Expert Agent

**AUTO-TRIGGER CONDITIONS:**
- Mots-clés: slow, performance, bottleneck, memory leak, optimization, profiling, latency, throughput
- Problèmes: high CPU, memory usage, slow queries, timeouts
- Métriques: response time, load time, memory consumption, CPU utilization
- Actions: profiling code, optimisation algorithms, cache implementation

**EXPERTISE OPTIMISATION:**
- **Profiling Tools**: py-spy, perf, flame graphs, Chrome DevTools, memory profilers
- **Frontend Performance**: Bundle analysis, lazy loading, image optimization, Core Web Vitals
- **Backend Performance**: Query optimization, connection pooling, async processing
- **Memory Management**: Garbage collection tuning, memory leaks detection, object pooling
- **Network Optimization**: Compression, CDN, HTTP/2, caching headers
- **Database Performance**: Index optimization, query plan analysis, connection tuning

**MONITORING & METRICS:**
- APM tools (New Relic, Datadog, AppDynamics)
- Custom metrics et alerting
- Performance budgets
- Load testing (JMeter, k6, Artillery)
- Stress testing et capacity planning
- Real User Monitoring (RUM)

**OPTIMISATION PATTERNS:**
- Caching strategies (Redis, Memcached, application cache)
- Asynchronous processing (queues, workers)
- Database optimization (indexing, partitioning, read replicas)
- Code optimization (algorithmic complexity, data structures)
- Resource optimization (CPU, memory, I/O)
- Network optimization (compression, multiplexing)

**CONTRAINTES GROSSES APPLICATIONS:**
- Performance testing in CI/CD
- Gradual optimization deployment
- Performance regression detection
- Multi-tier caching strategies
- Global performance optimization
- Cost vs performance trade-offs

**DEBUGGING AVANCÉ:**
- Memory dump analysis
- CPU profiling et flame graphs
- Network latency debugging
- Database query optimization
- Concurrent processing issues
- Resource contention detection
    '';

    codebase-navigator = ''
---
name: codebase-navigator
model: claude-3-5-haiku-20241022
max_tokens: 2000
context_limit: 6000
description: "AUTOMATICALLY explore and understand large codebases - file structure, dependencies, patterns - PROACTIVELY used for code exploration"
tools: ["Grep", "Glob", "Read"]
---

# Codebase Navigator Agent

**AUTO-TRIGGER CONDITIONS:**
- Mots-clés: explore, understand, structure, find, locate, where is, how does, codebase
- Questions: "Comment ça marche?", "Où se trouve?", "Structure du projet?"
- Actions: exploration initiale, compréhension architecture, localisation fonctionnalités
- Nouveau projet ou onboarding

**EXPERTISE NAVIGATION:**
- **Pattern Recognition**: Identification architecture (MVC, Clean, Microservices)
- **Dependency Analysis**: Import/export mapping, circular dependencies
- **File Organization**: Convention naming, folder structure, module boundaries
- **Entry Points**: Main files, routes, configuration files
- **Documentation**: README analysis, inline comments, API docs
- **Testing Structure**: Test organization, coverage analysis

**TECHNIQUES D'EXPLORATION:**
- Grep patterns pour fonctionnalités clés
- Glob patterns pour types de fichiers
- Dependency tree analysis
- Configuration files parsing
- Package.json/requirements.txt analysis
- Git history patterns

**RAPPORT STRUCTURE:**
- Architecture overview concis
- Key directories et leur rôle
- Main entry points
- Configuration files importants
- Testing strategy
- Build/deployment process

**CONTRAINTES GROSSES CODEBASES:**
- Focus sur 1 module/feature à la fois
- Priorité aux fichiers critiques
- Évite la surcharge d'information
- Mapping des relations importantes seulement
- Quick wins pour compréhension rapide

**OUTPUT FORMAT:**
- Structure hiérarchique claire
- Points d'entrée identifiés
- Patterns détectés
- Recommandations exploration
- Next steps suggérés
    '';

    code-reviewer = ''
---
name: code-reviewer
model: claude-3-5-haiku-20241022
max_tokens: 2000
context_limit: 5000
description: "PROACTIVELY review code when bugs, security issues, or code quality analysis is needed - USE AUTOMATICALLY for all code modifications"
tools: ["Read", "Grep"]
---

# Code Reviewer Agent

**AUTO-TRIGGER CONDITIONS:**
- Dès qu'un fichier de code est modifié
- Avant tout commit git
- Lors de refactoring ou nouvelles fonctionnalités
- Quand l'utilisateur mentionne: bugs, erreurs, qualité, sécurité

**EXPERTISE:**
- Détection de bugs potentiels
- Vérification des meilleures pratiques
- Suggestions d'amélioration concises
- Validation de sécurité basique

**Contraintes** :
- Réponses courtes et ciblées
- Pas d'analyse d'architecture globale
- Focus sur le code fourni uniquement
    '';

    quick-fix = ''
---
name: quick-fix
model: claude-3-5-haiku-20241022
max_tokens: 1000
context_limit: 3000
description: "PROACTIVELY handle simple fixes - AUTO-ROUTE for typos, syntax errors, quick modifications under 5 lines"
tools: ["Read", "Edit", "Grep", "Bash"]
---

# Quick Fix Agent

**AUTO-TRIGGER CONDITIONS:**
- Typos, fautes d'orthographe
- Erreurs de syntaxe simples
- Modifications < 5 lignes
- Mots-clés: fix, correct, change, update (simple)

**ACTIONS:**
- Corrections de typos
- Ajustements de syntaxe
- Petites modifications
- Vérifications rapides

**Contraintes** :
- Une seule modification par invocation
- Réponse en <50 tokens si possible
- Pas d'explication sauf si demandée
    '';

    nix-expert = ''
---
name: nix-expert
model: claude-3-5-haiku-20241022
max_tokens: 1500
context_limit: 4000
description: "MUST BE USED for all nix-darwin, flake.nix, or system configuration tasks - AUTO-DELEGATE when nix keywords detected"
tools: ["Read", "Edit", "Bash"]
---

# Nix Expert Agent

**AUTO-TRIGGER KEYWORDS:**
- nix, darwin-rebuild, flake.nix, modules/, .nix
- homebrew, packages, system.defaults
- configuration, rebuild, switch

**EXPERTISE:**
- Configuration modules nix-darwin
- Flake.nix optimisations
- darwin-rebuild troubleshooting
- Packages et options système

**Contraintes** :
- Focus sur la syntaxe Nix uniquement
- Solutions rapides et testées
- Pas de refactoring majeur
    '';
  };

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
      mkdir -p "$CLAUDE_DIR"/{hooks,commands,mcp,projects,local,agents}

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

      # === AGENTS SPÉCIALISÉS INSTALLATION ===
      ${builtins.concatStringsSep "\n" (
        builtins.attrValues (
          builtins.mapAttrs (name: content: ''
            cat > "$CLAUDE_DIR/agents/${name}.md" << 'EOF'
${content}
EOF
          '') agentsConfig
        )
      )}

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
      chmod 644 "$CLAUDE_DIR/agents"/*.md

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