# Hook scripts for Claude Code
{
  hookProtectMain = ''
    #!/usr/bin/env node
    // Auto-exit après 5 secondes pour éviter les freezes
    setTimeout(() => process.exit(0), 5000);

    module.exports = async (context) => {
      const { exec } = require('child_process');
      const util = require('util');
      const execPromise = util.promisify(exec);

      try {
        const { stdout } = await execPromise('git branch --show-current');
        const currentBranch = stdout.trim();

        if (currentBranch === 'main' || currentBranch === 'master') {
          return {
            block: true,
            message: "Cannot edit on main/master. Create feature branch first."
          };
        }
      } catch (error) {
        return {};
      }

      return {};
    };
  '';

  hookFormatTypescript = ''
    #!/usr/bin/env node
    // Auto-exit après 5 secondes pour éviter les freezes
    setTimeout(() => process.exit(0), 5000);

    module.exports = async (context) => {
      const { file } = context;
      const { execSync } = require('child_process');
      const path = require('path');

      if (file && (file.endsWith('.ts') || file.endsWith('.tsx'))) {
        try {
          execSync('which prettier', { stdio: 'pipe' });
          execSync('prettier --write ' + file, { stdio: 'inherit' });
          console.log('✓ Formatted ' + path.basename(file));
        } catch (error) {
          // Prettier not available, skip
        }
      }

      return {};
    };
  '';

  # -------------------------
}
