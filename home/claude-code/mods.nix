# Claude Code mods (plugins of function hooks, TypeScript, zero deps).
#
# Sources live in ./mods/<name>/; activation copies them to ~/.claude/mods as
# real, user-writable files (the engine writes `.claude-plugin/types/` into
# every loaded mod folder, which a read-only store symlink would refuse), and
# settings.nix loads them through env CLAUDE_CODE_PLUGIN_DIRS.
#
# `names` must equal the directories under ./mods both ways: asserted by
# checks/claude-mods.nix.
let
  names = [
    "apex-band"
    "status-bar"
  ];
in
{
  inherit names;
  src = ./mods;
  relDir = ".claude/mods";
  # Absolute, ":"-separated: the engine reads CLAUDE_CODE_PLUGIN_DIRS from the
  # `env` block of ~/.claude/settings.json (never a project's settings).
  pluginDirs = home: builtins.concatStringsSep ":" (map (n: "${home}/.claude/mods/${n}") names);
}
