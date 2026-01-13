# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) for ultra-high performance assistance across all contexts and technologies.

## Architecture Overview

This is a modular nix-darwin configuration for macOS using a flake-based approach. The system uses a hybrid package management strategy with Nix for reproducible CLI tools and development environments, and Homebrew for GUI applications.

### Core Structure
```
flake.nix              # Main flake with inputs & module orchestration
hosts/alex-mbp/        # Host-specific configuration
modules/               # Modular system configuration
├── system.nix         # Core Nix settings, TouchID, trackpad
├── packages.nix       # System utilities & CLI tools
├── development.nix    # Development environments & tools
├── shell.nix          # Zsh, Starship, aliases, functions
├── starship.nix       # Starship prompt configuration
├── fonts.nix          # Programming fonts & typography
├── ui.nix             # macOS UI/UX & system defaults
├── brew.nix           # Homebrew for GUI applications
└── claude-code.nix    # Claude Code CLI integration
```

### Package Management Strategy
- **Nix**: CLI tools, development environments, fonts, system utilities
- **Homebrew**: GUI applications, macOS-specific tools, casks
- **Language Package Managers**: npm/pnpm, pip/uv for libraries

## Common Commands

### System Management
```bash
# Apply configuration changes
sudo darwin-rebuild switch --flake .#alex-mbp

# Preview changes without applying
darwin-rebuild build --flake .#alex-mbp
nix store diff-closures /var/run/current-system ./result

# Update dependencies
nix flake update
nix flake lock --update-input nixpkgs

# Rollback to previous generation
darwin-rebuild rollback
```

### Development Workflow
```bash
# Nix development shell with zsh
nix-shell --run zsh

# Quick rebuild alias (defined in development.nix)
rebuild

# Git shortcuts (defined in development.nix)
g, gs, ga, gc, gp, gl, gd, gco, gb

# Modern tool replacements
lt        # eza --tree
cat       # bat (syntax highlighted)
find      # fd (faster find)
grep      # rg (ripgrep)
```

### Maintenance
```bash
# Cleanup (automatic weekly GC configured)
nix-collect-garbage -d
sudo nix-collect-garbage -d
nix-store --optimise

# Homebrew cleanup (automatic on rebuild)
brew cleanup --prune=all
```

## Development Environment

The system includes comprehensive development tools configured in `modules/development.nix`:

### Languages & Runtimes
- **Python**: python3, uv (package manager), ruff (linter/formatter)
- **JavaScript/Node**: nodejs, pnpm, TypeScript, Angular CLI, ESLint, Prettier
- **Nix**: nixd/nil (language servers), nixfmt-rfc-style

### Version Control & Collaboration
- git, git-lfs, gh (GitHub CLI), lazygit

### Database & API Tools
- sqlite, postgresql, curl, wget, httpie, jq, yq

### Environment Variables
```bash
EDITOR="nvim"
VISUAL="nvim"
PAGER="less"
GIT_EDITOR="code --wait"
NODE_ENV="development"
```

## Key Configuration Features

### Shell Configuration (`modules/shell.nix`)
- Zsh with autosuggestions, syntax highlighting, completion
- Starship prompt with Git integration and performance optimization
- FZF integration with enhanced previews
- Key bindings: ESC+ESC for sudo, enhanced history search

### System Optimizations (`modules/system.nix`)
- TouchID for sudo authentication
- Automatic Nix garbage collection (weekly, 7-day retention)
- Store optimization and deduplication
- Trackpad sensitivity and gesture configuration
- Disabled Gatekeeper warnings and quarantine

### macOS Interface (`modules/ui.nix`)
- Dock: Left position, auto-hide, 25px icons
- Finder: Column view, path bar, show extensions
- Dark mode interface, fast key repeat

## Troubleshooting

### Common Issues
- **Command not found**: `exec $SHELL` or restart terminal
- **Font issues**: `fc-cache -f -v` and restart applications
- **Permission errors**: `sudo chown -R $(whoami) ~/.config/nix-darwin`

### Debug Mode
```bash
# Verbose rebuild with trace
darwin-rebuild switch --flake .#alex-mbp --show-trace -v

# Check system differences
nix store diff-closures /var/run/current-system ./result
```

## Adding New Configurations

### New Packages
- **CLI tools**: Add to `modules/packages.nix` or `modules/development.nix`
- **GUI apps**: Add to `modules/brew.nix` casks array
- **Fonts**: Add to `modules/fonts.nix`

### New Hosts
1. Create `hosts/hostname/configuration.nix`
2. Add to `flake.nix` darwinConfigurations
3. Update networking.hostName and networking.computerName

### Module Customization
Override settings in host-specific configuration or disable modules by commenting them out in `flake.nix`.

## nix-darwin Configuration Reference

### Official Documentation
**Primary Reference**: https://nix-darwin.github.io/nix-darwin/manual/
- Complete list of all `system.defaults` options
- Covers dock, finder, screencapture, screensaver, NSGlobalDomain, and more
- Shows exact syntax and available values
- Includes `CustomUserPreferences` for advanced settings
- Always up-to-date with latest nix-darwin versions

### Quick Access
- Run `darwin-help` in terminal to open local documentation
- Run `man 5 configuration.nix` for manpages
- Check `/Users/alx/.config/nix-darwin/Nix-Darwin-Doc.md` for local reference

### Key Configuration Patterns
- **System defaults**: Use `system.defaults.*` for built-in options
- **Custom preferences**: Use `system.defaults.CustomUserPreferences` for app-specific settings not covered by nix-darwin
- **UI/UX settings**: Most macOS interface settings are in `modules/ui.nix`

**IMPORTANT**: Always reference the official documentation when modifying system defaults or adding new UI configurations. The documentation contains every available option and proper syntax.

---

## PERFORMANCE OPTIMIZATION INSTRUCTIONS

### Core Principles
- **Speed First**: Prioritize fastest solution that works correctly
- **Parallel Execution**: Use multiple tool calls simultaneously when possible
- **Minimal Context**: Only read/search what's absolutely necessary
- **Direct Action**: Execute immediately, explain only when asked
- **Smart Caching**: Leverage existing knowledge before searching

### Tool Usage Optimization
- **Batch Operations**: Combine multiple bash commands with `&&` or `;`
- **Targeted Searches**: Use specific glob patterns instead of broad searches
- **Parallel Tools**: Run multiple read/grep/glob operations simultaneously
- **Task Delegation**: Use Task tool for complex multi-step searches

### Code Quality Standards
- **Zero Tolerance**: All code must pass linting/type checking before completion
- **Test First**: Run existing tests, don't assume frameworks
- **Convention Matching**: Mirror existing patterns exactly
- **Security Conscious**: Never expose secrets, always validate inputs

### Communication Style
- **Ultra Concise**: Maximum 2-3 lines unless detail explicitly requested
- **Action Oriented**: Do first, explain only if asked
- **Status Updates**: Use TodoWrite for complex multi-step tasks
- **Error Transparent**: Show exact error messages and solutions

### Language-Specific Optimizations
- **Python**: Use `uv` for packages, `ruff` for linting, check pyproject.toml
- **JavaScript/Node**: Use `pnpm`, check package.json scripts, prefer TypeScript
- **Git**: Use `gh` CLI for GitHub operations, conventional commit messages
- **Nix**: Use `nixfmt-rfc-style`, reference official docs first

### System Integration
- **Environment Aware**: Check available tools before assuming (package.json, Cargo.toml, etc.)
- **Path Resolution**: Use absolute paths, respect working directory
- **Permission Handling**: Use TouchID sudo when available
- **Modern Tools**: Prefer `rg` over `grep`, `fd` over `find`, `bat` over `cat`

### Error Recovery
- **Fast Diagnosis**: Use `--show-trace -v` flags for detailed errors
- **Smart Retry**: Adjust approach based on error type
- **Dependency Check**: Verify all required packages/tools are available
- **Clean State**: Offer cleanup commands when things break

### Performance Metrics
- **Tool Calls**: Minimize round trips through batching
- **Context Usage**: Only read necessary files, use targeted searches
- **Execution Time**: Prefer built-in commands over external tools
- **Memory Efficiency**: Stream large outputs, limit line reads when appropriate

### Advanced 2025 Optimizations

#### Extended Thinking Mode
- Use "think" triggers for complex problems: `think` < `think hard` < `think harder` < `ultrathink`
- Each level allocates progressively more computation budget
- Apply to architecture decisions, debugging, and optimization tasks

#### Workflow Patterns
- **Explore → Plan → Execute**: Research first, then plan, then code (significantly improves success rate)
- **Profile First**: Always measure performance before optimizing
- **Test-Driven Development**: Write tests based on expected I/O pairs before implementation
- **Proactive Context Management**: Use `/compact` at natural breakpoints to maintain efficiency

#### Custom Commands (.claude/commands/)
- Create reusable slash commands for frequent workflows
- Use frontmatter for metadata: `allowed-tools`, `argument-hint`, `description`, `model`
- Organize in subdirectories for better structure
- Use `$ARGUMENTS` placeholder for dynamic values
- Share commands across team via repository

#### Performance Monitoring
- Response time target: < 100ms (p95)
- Throughput target: > 1000 requests/sec
- Real-time performance dashboards
- Automated benchmark suites
- CPU/memory profiling with flame graphs

#### Advanced Caching Strategy
- Multi-layer caching (memory + Redis)
- Cache aggressively at all levels
- Use prepared statements for database queries
- Connection pooling for external services
- Worker threads for CPU-intensive tasks

#### Context Engineering
- Use `/context` command for detailed token breakdown
- Monitor MCP tools, Custom Agents, and memory files usage
- Hierarchical CLAUDE.md files (project-level + nested directories)
- Automatic context compaction awareness

### TOKEN COST OPTIMIZATION (Up to 95% Savings)

#### Prompt Caching Strategy
- **Cache System Prompts**: Store CLAUDE.md, documentation, examples (90% cost reduction)
- **Cache Pricing**: Write to cache +25%, read from cache -90% (10% of base price)
- **Cache Requirements**: Min 1024 tokens (Sonnet 4), 2048 tokens (Haiku 3.5)
- **Cache Breakpoints**: Up to 4 cache_control parameters per prompt
- **Cache TTL**: 5 minutes default, 1 hour available for longer sessions

#### Batch Processing (50% Additional Savings)
- **Non-urgent Tasks**: Use batch API for 24h turnaround, 50% discount
- **Combined Savings**: Caching + Batch = up to 95% total cost reduction
- **Ideal for**: Documentation, code analysis, bulk operations, reports

#### Session Management (76% Token Reduction)
- **CLAUDE.md**: Keep under 5K tokens, auto-loaded at session start
- **Auto-compact**: Triggered at 95% context capacity
- **Manual Compact**: Use `/compact` every ~40 messages
- **Session Workflow**:
  - End: `/compact` + save to `docs/progress.md`
  - Start: Load CLAUDE.md + progress.md
  - Modular: Split context into separate `docs/` files

#### Output Optimization (5x Cost Impact)
- **Output Tokens**: Cost 5x more than input tokens
- **Format Constraints**: Request JSON, bullet points, specific lengths
- **Concise Responses**: Set length limits when detail isn't required
- **Avoid Verbosity**: Skip explanations unless explicitly requested

#### Model Selection Strategy
- **Haiku 3.5** ($0.80/$4): Prototyping, simple tasks, testing
- **Sonnet 4**: Production quality, most development tasks
- **Opus 4**: Reserved for complex architecture, critical decisions only
- **Intelligent Routing**: 60-70% cost reduction through appropriate model selection

#### Cost Monitoring
- **Daily Target**: Average $6/dev/day, 90% users stay under $12/day
- **Team Scale**: $100-200/dev/month with enterprise discounts (30-40%)
- **Tools**: `/cost` command, Claude Console usage tracking
- **Rate Limits**: Tiered TPM based on team size and concurrency needs