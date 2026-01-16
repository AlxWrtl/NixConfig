# nix-darwin Project Context

## Current State
- Config optimized pour Claude Code v2.1+
- CLAUDE.md réduit ~6.5K→1K tokens (-85%)
- Auto-routing models configuré (Haiku/Sonnet/Opus)
- Official sources étendu (docs.anthropic.com + GitHub)
- Compact frequency: 30 messages

## Architecture
- Modular nix-darwin flake
- 12 agents spécialisés
- 3 skills (/tdd, /optimize, /context-prime)
- Web guard hook actif

## Next Optimizations
- MCP servers (filesystem, git) → -40% tool calls (v2.1.7+ auto mode active)
- Memory files workflow adoption
