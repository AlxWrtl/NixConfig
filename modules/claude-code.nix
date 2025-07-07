{ config, pkgs, lib, ... }:

let
  pnpmHome = config.environment.variables.PNPM_HOME or "$HOME/Library/pnpm";
  cliPath = "${pnpmHome}/global/5/node_modules/@anthropic-ai/claude-code/cli.js";

  claudeCode = pkgs.writeShellScriptBin "claude-code" ''
    if [ ! -f "${cliPath}" ]; then
      echo "❌ Le CLI 'claude-code' est introuvable. Exécute : pnpm install -g @anthropic‑ai/claude‑code" >&2
      exit 1
    fi
    exec node "${cliPath}" "$@"
  '';
in {
  environment.systemPackages = [ claudeCode ];
}
