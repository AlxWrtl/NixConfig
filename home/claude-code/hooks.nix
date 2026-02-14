# Hook scripts for Claude Code
{
  hookProtectMain = ''
    #!/usr/bin/env node
    setTimeout(() => process.exit(0), 5000);

    const { exec } = require('child_process');
    const util = require('util');
    const execPromise = util.promisify(exec);

    module.exports = async () => {
      try {
        const { stdout } = await execPromise('git branch --show-current');
        const branch = stdout.trim();
        if (branch === 'main' || branch === 'master') {
          return { block: true, message: "Cannot edit on main/master. Create feature branch first." };
        }
      } catch (e) {}
      return {};
    };
  '';

  hookFormatTypescript = ''
    #!/usr/bin/env node
    setTimeout(() => process.exit(0), 10000);

    const { execSync } = require('child_process');
    const path = require('path');
    const exts = ['.ts', '.tsx', '.js', '.jsx', '.css', '.json'];

    module.exports = async (context) => {
      const { file } = context;
      if (file && exts.some(ext => file.endsWith(ext))) {
        try {
          execSync('which prettier', { stdio: 'pipe' });
          execSync('prettier --write ' + file, { stdio: 'inherit' });
          console.log('formatted ' + path.basename(file));
        } catch (e) {}
      }
      return {};
    };
  '';

  hookBlockMainBash = ''
    #!/usr/bin/env node
    setTimeout(() => process.exit(0), 5000);

    const { exec } = require('child_process');
    const util = require('util');
    const execPromise = util.promisify(exec);

    module.exports = async (context) => {
      const { tool_input } = context;
      const cmd = (tool_input && tool_input.command) || "";
      const isGitWrite = /git\s+(commit|push|merge|rebase)/.test(cmd);
      if (!isGitWrite) return {};

      try {
        const { stdout } = await execPromise('git branch --show-current');
        const branch = stdout.trim();
        if (branch === 'main' || branch === 'master') {
          return { block: true, message: "Cannot commit/push on main/master. Create a feature branch first." };
        }
      } catch (e) {}
      return {};
    };
  '';

  hookPreCompactBackup = ''
    #!/usr/bin/env bash
    set -euo pipefail
    BACKUP_DIR="$HOME/.claude/backups"
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    TRANSCRIPT="$BACKUP_DIR/session-$TIMESTAMP.jsonl"
    # Copy current transcript if available
    if [ -n "''${CLAUDE_TRANSCRIPT_PATH:-}" ] && [ -f "$CLAUDE_TRANSCRIPT_PATH" ]; then
      cp "$CLAUDE_TRANSCRIPT_PATH" "$TRANSCRIPT"
      echo "Backup saved: $TRANSCRIPT"
    fi
  '';

  hookSessionStart = ''
    #!/usr/bin/env bash
    set -euo pipefail
    BRANCH=$(git branch --show-current 2>/dev/null || echo "no git")
    LAST_COMMIT=$(git log --oneline -1 2>/dev/null || echo "no commits")
    MODIFIED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    echo "branch: $BRANCH | last: $LAST_COMMIT | modified: $MODIFIED files"
  '';
}
