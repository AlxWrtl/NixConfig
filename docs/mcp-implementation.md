# MCP Servers Implementation Guide

## Status: Recherche en Cours

### Constat
Les MCP servers officiels (filesystem, git) existent dans le repo `modelcontextprotocol/servers` mais:
- ❌ Pas de packages NPM publics `@anthropic-ai/mcp-server-*`
- ✅ Code source disponible: `src/filesystem/` et `src/git/`
- ✅ Installation via `claude mcp add` avec stdio transport

### Options d'Installation

#### Option 1: MCP Servers via NPX (Packages Community)
```bash
# Chercher dans le registry MCP
# https://registry.modelcontextprotocol.io/

# Exemples de packages community (à vérifier):
claude mcp add --transport stdio filesystem -- npx -y @modelcontextprotocol/server-filesystem
claude mcp add --transport stdio git -- npx -y @modelcontextprotocol/server-git
```

#### Option 2: Build from Source
```bash
# Cloner le repo officiel
git clone https://github.com/modelcontextprotocol/servers.git
cd servers

# Build filesystem server
cd src/filesystem
npm install
npm run build

# Utiliser le serveur local
claude mcp add --transport stdio filesystem -- node /path/to/servers/src/filesystem/dist/index.js
```

#### Option 3: Configuration Project-Level (.mcp.json)
```json
{
  "mcpServers": {
    "filesystem": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem"],
      "env": {
        "ALLOWED_DIRECTORIES": "${HOME}/Projects,${HOME}/Documents"
      }
    },
    "git": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-git"],
      "env": {
        "GIT_REPOS_DIR": "${HOME}/Projects"
      }
    }
  }
}
```

---

## Impact Estimé (Si Activé)

### Performance
- **Tool calls**: -40% (batch file operations)
- **Latency**: -30% (direct file access vs API)
- **Context usage**: -20% (structured file reads)

### Use Cases
**Filesystem MCP**:
- Read multiple files in one operation
- Search across files efficiently
- Batch file modifications

**Git MCP**:
- Batch git operations (status + diff + log)
- Repository analysis
- Commit history searches

---

## Recommandation Actuelle

**Status**: ⏸️ **Pause sur MCP Servers**

**Raisons**:
1. Packages NPM officiels introuvables
2. Community packages non vérifiés
3. Build from source = complexité supplémentaire
4. Claude Code v2.1.7+ a déjà MCP auto mode actif

**Alternative**:
- ✅ MCP auto mode DÉJÀ ACTIF (v2.1.7)
- ✅ Tool search optimization automatique
- ✅ Pas de config additionnelle nécessaire

**Bénéfices actuels sans MCP servers custom**:
- Context optimization automatique
- Tool deferral >10% context
- Zero configuration overhead

---

## Si Besoin Futur

### Étapes de Validation
1. Vérifier registry: https://registry.modelcontextprotocol.io/
2. Tester package community sur projet test
3. Mesurer impact réel (baseline vs MCP)
4. Décider activation si gain >20%

### Monitoring
```bash
# Vérifier outils MCP disponibles
/mcp  # dans Claude Code session

# Lister servers configurés
claude mcp list
```

---

## Prochaine Étape

✅ **Focus on MCP auto mode optimization** (v2.1.7+ provides most benefits)
