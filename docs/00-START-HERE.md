# Claude Code Ultra-Optimization Documentation

**Location**: `.config/nix-darwin/docs/`
**Reproductible**: ✅ Tout géré par Git + nix-darwin

---

## 📚 Guide de Lecture

### 1. **README.md** ⭐ START HERE
- Vue d'ensemble complète
- Quick start guide
- Metrics avant/après
- Troubleshooting

### 2. **verification-report.md**
- Audit complet vs docs officielles 2025
- Features Claude Code v2.1.9
- Comparaison config actuelle vs best practices

### 3. **optimizations.md**
- Changelog toutes optimisations appliquées
- Impact estimé par optimisation

### 4. **mcp-implementation.md** (Paused)
- Status MCP servers recherche
- Pourquoi paused (packages unavailable)
- Future considerations

### 5. **context.md**
- Project state snapshot
- Architecture overview
- Next optimizations queue

---

## 🚀 Quick Commands

```bash
# Lire guide principal
cat docs/README.md

# Vérifier config actuelle
cat home/claude-code.nix | grep -A 20 "autoRoutingText"

# Rebuild après modifications
sudo darwin-rebuild switch --flake .#alex-mbp

# Vérifier changements appliqués
ls -la ~/.claude/
cat ~/.claude/settings.json | jq '.betaHeaders'
```

---

## 📦 Structure Reproductible

Tout dans ce dossier est versionné Git et déployé automatiquement:

```
.config/nix-darwin/
├── flake.nix              # Configuration principale
├── home/
│   └── claude-code.nix    # Config Claude Code ⭐
├── modules/               # Modules système
├── CLAUDE.md              # Prompt optimisé (1K tokens)
└── docs/                  # Documentation (ce dossier)
    ├── 00-START-HERE.md   # Ce fichier
    ├── README.md          # Guide principal
    ├── verification-report.md
    ├── optimizations.md
    ├── mcp-implementation.md
    └── context.md
```

---

## ✅ Reproductibilité Garantie

### Sur Nouvelle Machine
```bash
# 1. Clone repo
git clone <your-repo> ~/.config/nix-darwin
cd ~/.config/nix-darwin

# 2. Install nix-darwin
nix run nix-darwin -- switch --flake .#alex-mbp

# 3. Toute la config Claude Code est appliquée automatiquement
# - settings.json
# - CLAUDE.md global
# - auto-routing.md
# - official-sources.txt
# - agents (12)
# - commands (3)
# - hooks (web_guard.py)

# 4. Docs disponibles
cat docs/README.md
```

### Rien en Dehors du Repo
- ❌ Pas de fichiers dans `~/.claude/projects/`
- ❌ Pas de config manuelle
- ✅ Tout déclaratif dans nix-darwin
- ✅ Versionné Git
- ✅ Déployable sur n'importe quelle machine

---

**Maintenu par**: nix-darwin + home-manager
**Dernière MAJ**: January 16, 2025
