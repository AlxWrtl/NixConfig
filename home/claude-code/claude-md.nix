# Global CLAUDE.md content (< 100 lines — every line costs context in EVERY session)
#
# Ce fichier ne porte plus QUE le delta Claude : le texte commun vit dans
# `agent-instructions.nix` et est splicé, jamais recopié. Toute règle qui vaut
# aussi pour Codex remonte au tronc, sinon elle repart en dérive silencieuse.
#
# Le delta ne contient que des mécanismes que Claude a et Codex n'a pas :
# WebFetch/WebSearch, les serveurs MCP du vault, la délégation à des subagents,
# `~/.claude/rules/` chargé à l'ouverture d'un fichier. Les nommer à Codex lui
# ferait chercher des outils absents (assertion G4).
#
# L'interpolation est à la COLONNE 0 : une chaîne `''…''` est désindentée du
# minimum de ses lignes littérales, donc splicer le tronc dans un bloc indenté
# décalerait son texte et G1 (`hasInfix` sur le corps partagé) rougirait pour
# une raison purement cosmétique.
let
  shared = import ./agent-instructions.nix;

  deltaSections = [
    {
      name = "Git";
      body = ''
        - Branch FIRST — `git checkout -b <type>/<desc>` BEFORE coding; never
          commit on main/master (hooks deny it), master via PR only.
        - End-of-run commit+PR is pre-authorized by the apex `-pr` default; any
          other add/commit/push still needs an explicit ask.
      '';
    }
    {
      name = "Model Allocation";
      body = ''
        - Subagents: JAMAIS inherit — `model` explicite à chaque spawn. Détail de
          l'allocation: apex `steps/ORCHESTRATION.md`.
      '';
    }
    {
      name = "Rules (path-scoped)";
      body = ''
        - nix / TS specifics: `~/.claude/rules/` — loaded on opening a matching
          file. Ne pas recopier ces règles ici : elles arriveraient dans chaque
          session au lieu des seules qui touchent un `.nix` ou un `.ts`.
      '';
    }
    {
      name = "Tool Selection (forbidden → required)";
      body = ''
        - `echo >` / heredoc → Write tool | `curl` for docs → WebFetch tool
        - Multi-line script → write to scratchpad, run the file. Never `node -e` /
          `python3 -c` inline: operators in the body break the permission matcher.
      '';
    }
    {
      name = "Retrieval rung 0 (Claude-only)";
      body = ''
        - Rung 0, AVANT l'échelle `scrapling` du tronc : WebFetch/WebSearch =
          défaut. Rend la RÉPONSE, pas la page, ~20× moins de tokens que lire un
          fichier de 33 Ko. Les rungs 1-3 du tronc ne servent qu'après son échec.
        - Chrome/Playwright JAMAIS pour lire. Seulement pour AGIR : login, clic.
      '';
    }
    {
      name = "Vault Retrieval (enquire vs graphify — never both on one question)";
      body = ''
        - `mcp__enquire__*` = what the vault WROTE: find/read notes, keyword +
          semantic search, explicit wikilinks, backlinks. Default choice.
        - `mcp__graphify__*` = what the vault IMPLIES: LLM-extracted entities and
          relations across note CONTENTS, communities, hubs. Use for "how does X
          relate to Y", "what clusters around X".
        - graphify covers `02-Projets` ONLY (Preliz + nix-darwin). Silence there is
          not absence — outside that scope, or graph mute, fall back to enquire.
      '';
    }
    {
      name = "Delegation";
      body = ''
        - Pattern répété N>=4 séquentiel mêmes fichiers → ralph-loop. Sous-tâches
          indépendantes fichiers disjoints → /fork background. Combinables.
        - Review routine qualité → /code-review natif (subagent background, hors
          contexte). Agent code-reviewer = spec compliance + sécu pre-merge.
      '';
    }
  ];
in
{
  inherit deltaSections;

  claudeMdGlobal = ''
    ${shared.preamble}
    # Claude Code — Global Guardrails

    ${shared.trunk}
    ${shared.render deltaSections}'';
}
