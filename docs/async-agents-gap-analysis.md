# Analyse Gaps: Agents Async & Features 2025

## Format Agents: Incompatibilité Détectée ⚠️

### Notre Format Actuel (Custom)
```markdown
---
name: code-reviewer
model: haiku
max_tokens: 1800
context_limit: 5000
description: "Code review: bugs, quality, security"
tools: Read, Grep, WebFetch, Write, Edit
thinking: disabled
---
```

### Format Officiel Claude Code v2.1.9
```markdown
---
name: code-reviewer
description: "Expert code reviewer. Use proactively after code changes."
tools: Read, Grep, Glob, Bash
disallowedTools: Write, Edit
model: sonnet
permissionMode: default
skills: []
hooks: {}
---
```

### Champs Non Standards (à vérifier)
- ❌ `max_tokens` - Pas dans spec officielle
- ❌ `context_limit` - Pas dans spec officielle
- ❌ `thinking` - Pas dans spec officielle

### Champs Manquants (officiels)
- ⚠️ `permissionMode` - Contrôle permissions (default/acceptEdits/dontAsk/bypassPermissions)
- ⚠️ `disallowedTools` - Blacklist vs whitelist
- ⚠️ `skills` - Skills à injecter
- ⚠️ `hooks` - PreToolUse/PostToolUse/Stop

---

## Features Async Manquantes

### 1. Background Execution
**Status**: ❌ Non configuré explicitement

**Config officielle**:
```bash
# Disable background (optionnel)
export CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
```

**Par défaut**: Background enabled (Ctrl+B pour backgrounder)

**Notre config**: Rien de configuré = **background enabled par défaut** ✅

---

### 2. Subagent Hooks (Lifecycle)
**Status**: ❌ Non configuré

**Use case**: Setup/cleanup automatique
```markdown
---
name: db-agent
hooks:
  SubagentStart:
    - type: command
      command: "./scripts/setup-db.sh"
  SubagentStop:
    - type: command
      command: "./scripts/cleanup-db.sh"
---
```

**Impact**: Pas de setup/cleanup auto pour agents spécialisés

---

### 3. Permission Modes
**Status**: ❌ Non configuré (utilise default)

**Options disponibles**:
- `default` - Prompts standards
- `acceptEdits` - Auto-accept file edits
- `dontAsk` - Auto-deny prompts (background safe)
- `bypassPermissions` - Skip all checks
- `plan` - Read-only mode

**Recommandation**:
```markdown
# Read-only agents
permissionMode: plan

# Quick-fix agents
permissionMode: acceptEdits

# Review agents
permissionMode: default
```

---

### 4. Tool Control Avancé
**Status**: ⚠️ Partial (whitelist seulement)

**Notre config**:
```markdown
tools: Read, Grep, WebFetch, Write, Edit
```

**Meilleure pratique** (blacklist + whitelist):
```markdown
# Start with all tools, remove dangerous ones
disallowedTools: Write, Edit
# Or be explicit with whitelist
tools: Read, Grep, Glob, Bash
```

---

### 5. Hooks PreToolUse (Validation)
**Status**: ❌ Non configuré

**Example**: Read-only SQL validator
```markdown
---
name: db-reader
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-readonly-query.sh"
---
```

**Impact**: Pas de validation automatique des commandes

---

### 6. Context Management
**Status**: ✅ Partially configured

**Config actuelle**:
```json
{
  "performance": {
    "compactFrequency": 30
  }
}
```

**Subagent context**:
- Auto-compact enabled ✅
- Transcript storage: `~/.claude/projects/{project}/{sessionId}/subagents/`
- Cleanup: 30 days default

---

## Vérifications Nécessaires

### Test 1: Format Agents Compatible?
```bash
# Lancer Claude Code
claude

# Essayer de lister agents
/agents

# Vérifier si nos agents custom sont reconnus
```

**Attendu**: 12 agents custom + built-in agents

**Si erreur**: Format incompatible, need migration

---

### Test 2: Background Execution Works?
```bash
# Dans Claude Code session
"Research the authentication module in background"

# Vérifier si Ctrl+B fonctionne
# Vérifier logs
ls ~/.claude/projects/*/subagents/
```

---

### Test 3: Parallel Subagents
```bash
"Research auth, database, and API modules in parallel using separate subagents"
```

**Attendu**: 3 subagents spawned concurrently

---

## Recommandations Prioritaires

### Priority 1: Valider Format Agents (URGENT)
**Action**: Tester si notre format custom fonctionne ou migrer

**Test**:
```bash
claude
/agents
# Verify all 12 custom agents listed
```

**Si incompatible**: Migrer vers format officiel

---

### Priority 2: Ajouter permissionMode
**Impact**: Optimise agents pour background/foreground

**Changes**:
```nix
agentQuickFix = ''
  ---
  name: quick-fix
  description: "Tiny changes only. Use proactively for typos/small fixes."
  tools: Read, Edit, Grep, Bash
  model: haiku
  permissionMode: acceptEdits  # ← NEW
  ---
'';

agentReviewer = ''
  ---
  name: code-reviewer
  description: "Code review specialist. Use proactively after changes."
  tools: Read, Grep, Glob, Bash
  disallowedTools: Write, Edit  # ← NEW (read-only)
  model: haiku
  permissionMode: plan  # ← NEW (read-only mode)
  ---
'';
```

---

### Priority 3: Hooks pour Validation (Optionnel)
**Use case**: DB agents, security-critical tasks

**Example**: Prevent destructive SQL
```bash
# .claude/scripts/validate-readonly-query.sh
#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -iE 'DROP|DELETE|UPDATE|INSERT' > /dev/null; then
  echo "Blocked: Only SELECT allowed" >&2
  exit 2
fi
exit 0
```

**Agent config**:
```markdown
---
name: db-reader
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./.claude/scripts/validate-readonly-query.sh"
---
```

---

### Priority 4: Optimize Descriptions for Auto-Delegation
**Current**:
```markdown
description: "Code review: bugs, quality, security, minimal actionable feedback."
```

**Better** (encourages proactive use):
```markdown
description: "Expert code reviewer. Use proactively after code changes, before commits, and when debugging quality issues."
```

**Keywords**:
- "Use proactively" - Encourages auto-delegation
- Specific triggers - "after code changes", "before commits"
- Clear scope - What the agent is expert at

---

## Gap Summary

| Feature | Status | Priority | Impact |
|---------|--------|----------|--------|
| **Agent format compatibility** | ⚠️ Unknown | 🔴 P0 | May break agents |
| **permissionMode** | ❌ Missing | 🟡 P1 | Background efficiency |
| **disallowedTools** | ❌ Missing | 🟡 P1 | Security |
| **Background execution** | ✅ Default on | ✅ OK | Works |
| **Parallel tools** | ✅ Enabled | ✅ OK | Works |
| **Hooks PreToolUse** | ❌ Missing | 🟢 P3 | Validation |
| **Subagent hooks** | ❌ Missing | 🟢 P3 | Lifecycle |
| **Description optimization** | ⚠️ Partial | 🟡 P2 | Auto-delegation |

---

## Action Plan

### Phase 1: Validation (NOW)
```bash
# Test agents work
claude
/agents

# Test background execution
# In session: "Research X in background"

# Verify parallel execution
# In session: "Research A, B, C in parallel"
```

### Phase 2: Fix Format (If Needed)
- Migrate agents to official format
- Add `permissionMode`
- Add `disallowedTools` where appropriate
- Optimize descriptions

### Phase 3: Advanced Features (Optional)
- Add validation hooks
- Configure subagent lifecycle hooks
- Setup project-specific permissions

---

## Questions à Répondre

1. **Notre format custom fonctionne-t-il?** → Test /agents
2. **Background execution marche?** → Test en session
3. **Parallel subagents ok?** → Test delegation
4. **Performance ok sans permissionMode?** → Mesurer latence

**Next**: Run tests, document results, fix gaps
