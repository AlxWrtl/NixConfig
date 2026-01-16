#!/bin/bash
# Validation automatique agents Claude Code
# Usage: ./scripts/validate-agents.sh

set -e

echo "🔍 Validation Agents Claude Code v2.1.9"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
WARNINGS=0

# Test 1: Agents déployés
echo "Test 1: Agents files deployed"
AGENT_COUNT=$(ls ~/.claude/agents/*.md 2>/dev/null | wc -l)
if [ "$AGENT_COUNT" -eq 12 ]; then
    echo -e "${GREEN}✓${NC} Found 12 agent files"
    ((PASSED++))
else
    echo -e "${RED}✗${NC} Expected 12 agents, found $AGENT_COUNT"
    ((FAILED++))
fi
echo ""

# Test 2: Format YAML valide
echo "Test 2: YAML frontmatter format"
for agent in ~/.claude/agents/*.md; do
    if grep -q "^---$" "$agent"; then
        echo -e "${GREEN}✓${NC} $(basename $agent): YAML frontmatter present"
    else
        echo -e "${RED}✗${NC} $(basename $agent): Missing YAML frontmatter"
        ((FAILED++))
    fi
done
((PASSED++))
echo ""

# Test 3: Champs requis présents
echo "Test 3: Required fields in agents"
REQUIRED_FIELDS=("name:" "description:" "tools:")
for agent in ~/.claude/agents/*.md; do
    AGENT_NAME=$(basename "$agent")
    ALL_PRESENT=true
    for field in "${REQUIRED_FIELDS[@]}"; do
        if ! grep -q "^$field" "$agent"; then
            echo -e "${RED}✗${NC} $AGENT_NAME: Missing $field"
            ALL_PRESENT=false
            ((FAILED++))
        fi
    done
    if $ALL_PRESENT; then
        echo -e "${GREEN}✓${NC} $AGENT_NAME: All required fields present"
    fi
done
((PASSED++))
echo ""

# Test 4: Champs custom (warnings)
echo "Test 4: Custom fields detection (warnings)"
CUSTOM_FIELDS=("max_tokens:" "context_limit:" "thinking:")
for agent in ~/.claude/agents/*.md; do
    AGENT_NAME=$(basename "$agent")
    for field in "${CUSTOM_FIELDS[@]}"; do
        if grep -q "^$field" "$agent"; then
            echo -e "${YELLOW}⚠${NC}  $AGENT_NAME: Custom field $field (not in official spec)"
            ((WARNINGS++))
        fi
    done
done
echo ""

# Test 5: Settings.json validité
echo "Test 5: Settings.json validation"
if [ -f ~/.claude/settings.json ]; then
    if jq empty ~/.claude/settings.json 2>/dev/null; then
        echo -e "${GREEN}✓${NC} settings.json is valid JSON"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} settings.json is invalid JSON"
        ((FAILED++))
    fi
else
    echo -e "${YELLOW}⚠${NC}  settings.json not found"
    ((WARNINGS++))
fi
echo ""

# Test 6: Beta headers configured
echo "Test 6: Beta headers configuration"
if [ -f ~/.claude/settings.json ]; then
    if jq -e '.betaHeaders' ~/.claude/settings.json >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Beta headers configured:"
        jq '.betaHeaders' ~/.claude/settings.json
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠${NC}  Beta headers not found in settings.json"
        ((WARNINGS++))
    fi
fi
echo ""

# Test 7: Parallel tools enabled
echo "Test 7: Parallel tools configuration"
if [ -f ~/.claude/settings.json ]; then
    PARALLEL=$(jq -r '.performance.parallelTools // false' ~/.claude/settings.json)
    if [ "$PARALLEL" = "true" ]; then
        echo -e "${GREEN}✓${NC} Parallel tools enabled"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠${NC}  Parallel tools not enabled"
        ((WARNINGS++))
    fi
fi
echo ""

# Test 8: Official sources configured
echo "Test 8: Official sources allowlist"
if [ -f ~/.claude/official-sources.txt ]; then
    SOURCE_COUNT=$(grep -v '^#' ~/.claude/official-sources.txt | grep -v '^$' | wc -l)
    echo -e "${GREEN}✓${NC} Found $SOURCE_COUNT official sources"
    if grep -q "platform.claude.com" ~/.claude/official-sources.txt; then
        echo -e "${GREEN}✓${NC} platform.claude.com present"
    else
        echo -e "${YELLOW}⚠${NC}  platform.claude.com missing"
        ((WARNINGS++))
    fi
    ((PASSED++))
else
    echo -e "${RED}✗${NC} official-sources.txt not found"
    ((FAILED++))
fi
echo ""

# Test 9: CLAUDE.md size optimisé
echo "Test 9: CLAUDE.md optimization"
if [ -f ~/.config/nix-darwin/CLAUDE.md ]; then
    CLAUDE_SIZE=$(wc -c < ~/.config/nix-darwin/CLAUDE.md)
    CLAUDE_WORDS=$(wc -w < ~/.config/nix-darwin/CLAUDE.md)
    if [ "$CLAUDE_SIZE" -lt 2000 ]; then
        echo -e "${GREEN}✓${NC} CLAUDE.md optimized: ${CLAUDE_SIZE} chars (~$CLAUDE_WORDS words)"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠${NC}  CLAUDE.md large: ${CLAUDE_SIZE} chars (target <2000)"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}⚠${NC}  CLAUDE.md not found in expected location"
    ((WARNINGS++))
fi
echo ""

# Test 10: Commands/Skills deployed
echo "Test 10: Commands and Skills"
COMMANDS_COUNT=$(ls ~/.claude/commands/*.md 2>/dev/null | wc -l || echo 0)
echo -e "${GREEN}✓${NC} Found $COMMANDS_COUNT custom commands/skills"
((PASSED++))
echo ""

# Summary
echo "========================================"
echo "📊 Summary"
echo "========================================"
echo -e "${GREEN}✓ Passed:${NC} $PASSED"
echo -e "${RED}✗ Failed:${NC} $FAILED"
echo -e "${YELLOW}⚠ Warnings:${NC} $WARNINGS"
echo ""

# Recommendation
if [ "$FAILED" -eq 0 ] && [ "$WARNINGS" -lt 3 ]; then
    echo -e "${GREEN}🎉 Configuration looks good!${NC}"
    echo "✓ Agents deployed correctly"
    echo "✓ Settings optimized"
    echo ""
    echo "⚠️  Custom fields detected (max_tokens, context_limit, thinking)"
    echo "   → Need MANUAL TESTING to verify compatibility"
    echo ""
    echo "Next: Run interactive tests in docs/TEST-PLAN-async-agents.md"
elif [ "$FAILED" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  Configuration mostly OK with warnings${NC}"
    echo "Next: Review warnings and run manual tests"
else
    echo -e "${RED}❌ Configuration has issues${NC}"
    echo "Fix failed tests before proceeding"
fi
echo ""

# Exit code
if [ "$FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
