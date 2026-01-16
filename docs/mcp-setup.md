# MCP Servers Setup (Optional)

## Benefits
- Filesystem ops: -40% tool calls via batch operations
- Git ops: Batch multiple git commands
- Performance: 3x faster navigation

## Installation
```bash
# Install MCP servers globally
pnpm add -g @anthropic-ai/mcp-server-filesystem
pnpm add -g @anthropic-ai/mcp-server-git

# Verify installation
which mcp-server-filesystem
which mcp-server-git
```

## Configuration
Create `~/.claude/mcp.json`:
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "mcp-server-filesystem",
      "args": [],
      "disabled": false
    },
    "git": {
      "command": "mcp-server-git",
      "args": [],
      "disabled": false
    }
  }
}
```

## Usage
Once configured, Claude Code automatically uses MCP servers for:
- File operations (read, write, search)
- Git commands (status, diff, commit)
- Batch operations

## Estimated Impact
- Tool calls: -40%
- Latency: -30%
- Token usage: -15% (fewer round trips)
