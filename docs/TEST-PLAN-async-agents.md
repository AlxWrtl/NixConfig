# Plan de Tests: Validation Agents Async

**Objectif**: Vérifier compatibilité format custom vs features async Claude Code v2.1.9

**Durée estimée**: 5-10 minutes

---

## Setup

```bash
# Terminal 1: Lancer Claude Code
cd ~
claude

# Terminal 2 (optionnel): Monitor logs
tail -f ~/.claude/logs/*.log
```

---

## Test 1: Agents Reconnus ✓

**Dans Claude Code**:
```
/agents
```

**Succès attendu**:
```
Built-in agents:
- Explore
- Plan
- general-purpose
- Bash
- statusline-setup
- claude-code-guide

Custom agents:
- quick-fix
- code-reviewer
- frontend-expert
- backend-expert
- devops-expert
- database-expert
- performance-expert
- nix-expert
- codebase-navigator
- architecture-expert
- ai-ml-expert
- git-ship

Total: 6 built-in + 12 custom = 18 agents
```

**Si erreur**: Format incompatible → Note error message

**Résultat**: ___________________________________________

---

## Test 2: Agent Simple (Foreground)

**Dans Claude Code**:
```
Use the code-reviewer agent to check CLAUDE.md for optimization opportunities
```

**Succès attendu**:
1. Agent spawned (voir "[Using code-reviewer agent]")
2. Agent completes avec résultats
3. Retour à conversation principale
4. Agent ID displayed (ex: "agent-abc123")

**Si erreur**: Note error + stack trace

**Résultat**: ___________________________________________

---

## Test 3: Background Execution

**Dans Claude Code**:
```
Research the nix-darwin configuration structure in background
```

**Succès attendu**:
1. Message: "Running in background..."
2. Peut continuer à taper pendant recherche
3. Notification quand terminé
4. Output available via agent ID

**Alternative (si auto-background pas triggered)**:
```
Research the nix-darwin configuration structure
[Pendant que agent tourne, presser Ctrl+B]
```

**Succès attendu**:
- Agent backgrounded
- Prompt revient immédiatement
- Notification à la fin

**Résultat**: ___________________________________________

---

## Test 4: Parallel Subagents

**Dans Claude Code**:
```
Research the following modules in parallel using separate agents:
1. modules/system.nix
2. modules/brew.nix
3. modules/claude-code.nix
```

**Succès attendu**:
1. 3 agents spawned concurrently
2. Progress updates de chaque agent
3. Résultats consolidés à la fin
4. 3 agent IDs différents

**Si séquentiel au lieu de parallel**: Note behavior

**Résultat**: ___________________________________________

---

## Test 5: Permission Behavior

**Dans Claude Code**:
```
Use quick-fix agent to add a comment to CLAUDE.md
```

**Observer**:
1. Permission prompt affiché? (devrait = default mode)
2. Auto-accepted? (non attendu sans permissionMode)
3. Agent completes?

**Résultat**: ___________________________________________

---

## Test 6: Resume Agent

**Dans Claude Code**:
```
Use code-reviewer agent to analyze modules/system.nix
[Attendre completion + noter agent ID]

Continue that code review and check modules/brew.nix
```

**Succès attendu**:
- Même agent ID resumed
- Context preserved (référence au review précédent)
- Pas de re-spawn

**Résultat**: ___________________________________________

---

## Test 7: Vérifier Transcripts

**Terminal 2**:
```bash
# Trouver session active
ls -lt ~/.claude/projects/

# Dernier projet
cd ~/.claude/projects/$(ls -t ~/.claude/projects/ | head -1)

# Lister sessions
ls -lt

# Check subagents transcripts
find . -name "agent-*.jsonl" -type f

# Read last agent transcript
cat $(find . -name "agent-*.jsonl" | head -1) | tail -20
```

**Succès attendu**:
- Fichiers `agent-*.jsonl` existent
- Contenu JSON valide
- Messages avec tool_use/tool_result

**Résultat**: ___________________________________________

---

## Test 8: Format Validation

**Terminal 2**:
```bash
# Lire un agent déployé
cat ~/.claude/agents/code-reviewer.md
```

**Vérifier**:
1. YAML frontmatter parsé? (pas d'erreurs)
2. Champs reconnus ou ignorés?
3. Warnings dans logs?

**Check logs pour warnings**:
```bash
grep -i "unknown.*field\|invalid.*agent\|unsupported" ~/.claude/logs/*.log
```

**Résultat**: ___________________________________________

---

## Test 9: Model Selection

**Dans Claude Code**:
```
Use the quick-fix agent (should use Haiku model)
```

**Puis**:
```
Use the frontend-expert agent (should use Sonnet model)
```

**Vérifier dans réponses**:
- Latence quick-fix < frontend-expert (Haiku plus rapide)
- Coût visible dans status line si ccusage actif

**Résultat**: ___________________________________________

---

## Test 10: Tools Restriction

**Dans Claude Code**:
```
Use code-reviewer agent to read and then edit modules/system.nix
```

**Observer**:
- Agent peut Read? ✓ (dans tools)
- Agent peut Edit? ✓ (dans tools)
- Expected: Both work (pas de disallowedTools configured)

**Résultat**: ___________________________________________

---

## Résultats Attendus vs Réels

| Test | Attendu | Réel | Status |
|------|---------|------|--------|
| 1. Agents reconnus | 18 agents | _____ | ⬜ |
| 2. Agent simple | Success | _____ | ⬜ |
| 3. Background exec | Success | _____ | ⬜ |
| 4. Parallel agents | 3 concurrent | _____ | ⬜ |
| 5. Permissions | Prompt shown | _____ | ⬜ |
| 6. Resume agent | Context preserved | _____ | ⬜ |
| 7. Transcripts | Files exist | _____ | ⬜ |
| 8. Format valid | No errors | _____ | ⬜ |
| 9. Model selection | Haiku/Sonnet | _____ | ⬜ |
| 10. Tools work | Read+Edit OK | _____ | ⬜ |

---

## Analyse Résultats

### Si TOUS ✅ (10/10)
→ Format custom compatible!
→ Passer à optimisations (permissionMode, disallowedTools)

### Si 8-9/10 ✅
→ Format mostly compatible
→ Fix issues mineurs
→ Optimiser ensuite

### Si 5-7/10 ✅
→ Format partiellement compatible
→ Migration sélective requise
→ Garder ce qui marche, migrer ce qui casse

### Si <5/10 ✅
→ Format incompatible
→ Migration complète vers format officiel requis

---

## Après Tests: Report Format

**Copier/coller ce template rempli**:
```
# Test Results: Async Agents Validation

## Summary
- Tests passed: __/10
- Critical failures: ___
- Warnings: ___
- Recommendation: ___

## Issues Found
1. ___
2. ___
3. ___

## Working Features
1. ___
2. ___
3. ___

## Next Actions
- [ ] ___
- [ ] ___
```

---

## Notes Debug

Si erreurs, capturer:
```bash
# Logs complets
cat ~/.claude/logs/claude-*.log > /tmp/claude-debug.log

# Agent errors
grep -i "agent\|subagent" ~/.claude/logs/*.log

# Format errors
grep -i "yaml\|frontmatter\|parse" ~/.claude/logs/*.log
```

---

**Prêt à tester?** Lance `claude` et suis les tests 1-10 ⬆️
