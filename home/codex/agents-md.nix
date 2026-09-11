# ~/.codex/AGENTS.md — the instruction file Codex loads in every session.
#
# The Codex counterpart of home/claude-code/claude-md.nix, and kept SHORT for
# the same reason: every line costs context in every session.
#
# It is NOT a copy of the Claude file. What was there before was, and it had
# drifted into nonsense on this host: an Anthropic model-allocation table, a
# tool list naming Claude's Grep/Glob/Read/Edit/Write tools, delegation to
# agents that do not exist here, and a project path that never existed
# (`home/Codex/`). An instruction naming a mechanism this host does not have
# is worse than no instruction: the model spends context obeying it and
# reaches for tools it cannot call.
#
# The line that mattered most, measured 2026-09-10: "Ask before: write/delete"
# made Codex request confirmation for every single edit even with
# `approval_policy = "never"` set in config.toml. The approval system was off;
# the model was obeying this file. Repo edits now proceed, because the branch
# hooks gate them — the same reasoning the Claude side already uses.
#
# LE TEXTE COMMUN N'EST PLUS ICI. Il vient de `agent-instructions.nix`, splicé
# à la colonne 0 (une chaîne indentée est désindentée du minimum de ses lignes,
# un splice indenté décalerait le tronc et ferait rougir G1). Ne rien recopier
# du tronc dans le delta : la copie coûte double, elle mange du contexte à
# chaque session ET elle rend la source partagée éditable sans effet.
#
# `Project Map` SUPPRIMÉ. C'était une liste de chemins tenue à la main, que
# n'importe quel `ls` reconstruit, retirée de CLAUDE.md comme dérivable et
# laissée ici par le même lot. Elle annonçait `home/Codex/`, un répertoire qui
# n'a JAMAIS existé : une carte manuelle ne peut qu'être fausse en silence.
# G7 interdit son retour dans l'une ou l'autre sortie.
#
# LA DIVERGENCE DU CONFIDENCE GATE EST DÉLIBÉRÉE, pas un oubli. Claude reçoit
# la règle depuis `~/.claude/rules/` à l'ouverture d'un `.nix` ; Codex n'a pas
# de `rules/` et doit donc la porter EN PERMANENCE, inline. G5 l'épingle des
# deux côtés : une passe d'« harmonisation » qui la remonte au tronc ou la
# duplique côté Claude rougira — c'est voulu, ne pas la « corriger ».
let
  shared = import ../claude-code/agent-instructions.nix;

  deltaSections = [
    {
      name = "Git (sandbox Codex)";
      body = ''
        - Branch first. Never edit on main/master: a hook refuses it. You CANNOT
          cut the branch yourself — `.git` is read-only in this sandbox by
          design — so ask the human to run `git checkout -b <type>/<desc>` and
          to say when it is done. Wait for that answer.
        - master is reached through a PR on GitHub, never by a local merge.
        - No `git add`/`commit`/`push` unless explicitly asked.
      '';
    }
    {
      name = "Ask First (sandbox Codex)";
      body = ''
        - En plus de la liste du tronc : tout appel réseau. La sortie réseau est
          filtrée ici, un appel qui part sans accord échoue tard et en silence.
      '';
    }
    {
      name = "Verify — nix";
      body = ''
        - `nix-instantiate --parse file.nix`, puis demander à l'humain de
          rebuild — `darwin-rebuild` exige un mot de passe et prend des minutes.
      '';
    }
    {
      name = "Confidence Gate (nix)";
      body = ''
        - Rate confidence before writing nix. Below 80%, stop and check the docs.
      '';
    }
  ];
in
{
  inherit deltaSections;

  agentsMd = ''
    ${shared.preamble}
    # Codex — Global Guardrails

    ${shared.trunk}
    ${shared.render deltaSections}'';
}
