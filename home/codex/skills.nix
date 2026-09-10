# The Codex half of the skills: same manifest, same text, translated on the
# way out, mounted where Codex actually looks.
#
# THE ONE MEASUREMENT THIS FILE IS BUILT AROUND, because getting it wrong
# produces a device that is perfectly correct and perfectly inert, with no
# error anywhere:
#
#   SKILL.md as a symlink to the nix store      -> the scanner SKIPS it
#   SKILL.md as a symlink to an ordinary file   -> the scanner SKIPS it
#   SKILL.md as a regular file                  -> read
#   the skill DIRECTORY as a symlink to a store directory   -> read
#
# Four arms, one session, a binary PRESENT/ABSENT predicate. The refusal is
# about the file-level symlink, not about the store and not about permissions
# — the ordinary-file arm isolates that. And the two-hop chain home-manager
# really builds (~/.agents/skills/x -> …-home-manager-files/… -> …-drv/) was
# measured too, at directory level: read.
#
# So: NEVER `.text` on a SKILL.md here, and never `recursive = true` — both
# produce file-level symlinks. One derivation per skill, mounted as a single
# directory symlink. `install` COPIES, so the files inside the store path are
# regular files; `linkFarm` and `symlinkJoin` are banned for the opposite
# reason.
#
# The store path is also the right place for these on their own merit: it is
# read-only, so the agent reading these instructions cannot rewrite them, and
# that property does not depend on any sandbox rule. Same argument as the hook
# scripts in hooks.nix.
#
# WHERE: `$HOME/.agents/skills`, the USER root Codex documents
# (learn.chatgpt.com/docs/build-skills lists REPO `.agents/skills`, USER
# `$HOME/.agents/skills`, ADMIN `/etc/codex/skills`, then the bundled ones).
# `$CODEX_HOME/skills` is read too — measured — but is undocumented as a
# general user root and is where Codex installs its own `.system` tree, so
# writing there means sharing a directory the tool manages. Choosing the
# documented root also means the twelve unmanaged May-17 directories that
# already live there are replaced in place rather than left to collide; see
# codexSkillsFossilBackup in activation.nix for what happens if they are not.
{ pkgs, lib }:

let
  manifest = (import ../claude-code/skills-manifest.nix).manifest;
  translate = import ./skills-translate.nix { inherit lib; };

  skillsRoot = ".agents/skills";

  # One derivation per skill. Not one for the whole tree: a single symlink at
  # `.agents/skills` would shadow anything else that root holds, and Codex is
  # not the only writer there.
  skillDrv =
    skill:
    pkgs.runCommand "codex-skill-${skill.name}" { } (
      lib.concatMapStrings (
        file:
        let
          text = translate.translate {
            skill = skill.name;
            file = file.path;
            inherit (file) text;
          };
        in
        # -D makes the parent dirs (apex has files under steps/), -m444 keeps
        # them read-only, and `install` copies rather than links — which is the
        # whole point, see the header.
        ''
          install -Dm444 ${builtins.toFile "skill-file" text} "$out/${file.path}"
        ''
      ) skill.files
      # A build-time assertion, because the failure it guards against is
      # silent at runtime: a skill whose SKILL.md ends up a symlink is simply
      # never listed, and nothing anywhere says so.
      + ''
        test -f "$out/SKILL.md" || { echo "no SKILL.md in ${skill.name}" >&2; exit 1; }
        test ! -L "$out/SKILL.md" || { echo "SKILL.md is a symlink in ${skill.name} — the scanner would skip it" >&2; exit 1; }
      ''
    );
in
{
  # `home.file."<dir>".source = <derivation>` with recursive left at its
  # default false: one symlink for the directory, which is the form that works.
  files = builtins.listToAttrs (
    map (skill: {
      name = "${skillsRoot}/${skill.name}";
      value.source = skillDrv skill;
    }) manifest
  );

  # Exposed so checks/codex-skills.nix can assert on the same text this module
  # installs, without rebuilding the derivations.
  translatedTexts = builtins.concatMap (
    skill:
    map (file: {
      skill = skill.name;
      inherit (file) path;
      text = translate.translate {
        skill = skill.name;
        file = file.path;
        inherit (file) text;
      };
    }) skill.files
  ) manifest;

  inherit manifest;
  translation = translate;
}
