# Tronc commun des instructions d'agent — le SEUL endroit où vit le texte que
# Claude et Codex reçoivent tous les deux. `claude-md.nix` et `agents-md.nix`
# le splicent, ils ne le recopient pas.
#
# CE POUR QUOI CE FICHIER EXISTE : les deux sorties ont dérivé dans les DEUX
# sens pendant des mois sans qu'une seule assertion rougisse. « Code Quality »
# n'existait que côté Codex, « Project Map » a été retiré de CLAUDE.md comme
# dérivable et laissé dans AGENTS.md par le même lot d'uniformisation. Deux
# textes tenus à la main ne peuvent pas échouer bruyamment : ils ne peuvent
# qu'être incomplets, et une instruction absente est une instruction qu'on
# croit donnée.
#
# AGENT-AGNOSTIQUE, MALGRÉ LE RÉPERTOIRE. Rien ici n'est spécifique à Claude :
# chaque consommateur préfixe, ordonne et complète avec son propre delta. Le
# fichier est rangé sous `claude-code/` pour deux raisons MÉCANIQUES, pas
# conceptuelles :
#   - `flake.nix` passe nixfmt sur `home/claude-code/*.nix` et sur aucun
#     répertoire qui n'existe pas encore, donc un nouveau foyer serait ni
#     formaté ni vérifié ;
#   - `checks/readme-consistency.nix` inventorie les `.nix` posés DIRECTEMENT
#     dans `home/`, sans récursion : un fichier ici n'exige aucune entrée dans
#     l'arbre Structure, alors que `home/agent-instructions.nix` en exigerait
#     une. Le précédent est `skills-manifest.nix`, rangé là pour exactement
#     ces deux raisons.
# Ne le déplacer qu'avec les deux à la fois.
#
# L'ORDRE FAIT PARTIE DU CONTRAT. `trunkSections` est une LISTE et ne doit
# JAMAIS devenir un attrset : nix trie les noms d'attributs alphabétiquement,
# et le document rendu suit l'ordre qu'on lui donne. Un attrset réordonnerait
# les sections derrière votre dos à la prochaine lecture — même raison que
# pour `manifest` dans `skills-manifest.nix`.
#
# CE QUI N'ENTRE PAS ICI : tout ce qui nomme un mécanisme qu'un des deux
# agents n'a pas. Model Allocation, Tool Selection, Vault Retrieval,
# Delegation sont des mécanismes Claude ; le Confidence Gate inline est un
# delta Codex, parce que Codex n'a pas de `rules/` chargé à l'ouverture d'un
# fichier. Une instruction qui nomme un outil absent n'est pas neutre : le
# modèle la lit et cherche l'outil.
#
# Aucun argument, exprès : les checks importent ce fichier nu.
let
  # Rendu d'une liste ordonnée de sections. Le corps porte déjà son saut de
  # ligne final, d'où le séparateur simple.
  render = sections: builtins.concatStringsSep "\n" (map (s: "## ${s.name}\n${s.body}") sections);

  preamble = ''
    Always respond in caveman full mode: terse prose, no filler, fragments over sentences,
    no articles unless ambiguous. Preserve all code, paths, commands, errors verbatim.
    Deactivate only for: security warnings, irreversible action confirmations.
  '';

  trunkSections = [
    {
      name = "Non-negotiables";
      body = ''
        - Repo file edits: proceed — the branch hooks gate them, do not ask first.
          Ask before: sudo, chmod, installs, deletes outside the repo, large
          refactors, anything irreversible.
        - Never touch secrets: ~/.ssh, ~/.aws, ~/.gnupg, **/.env*, secrets/,
          *token*, *key*, *cert*.
        - Keep diffs minimal. Small, reversible changes.
      '';
    }
    {
      name = "Identity";
      body = ''
        - macOS with nix-darwin + flakes + home-manager (M1)
        - Package manager: pnpm (never npm or yarn)
        - TypeScript strict mode
      '';
    }
    {
      name = "Verify Checklist";
      body = ''
        - ts: `pnpm typecheck && pnpm lint --max-warnings 0`
        - commit: English, imperative, type prefix (feat/fix/chore/refactor)
      '';
    }
    {
      name = "Code Quality";
      body = ''
        - No debug prints left in production code. No `any` in TypeScript.
        - Explicit error handling, no silent catches. Validate external input.
        - Source of truth: repo docs OR official vendor docs only.
      '';
    }
    {
      name = "Web Retrieval";
      body = ''
        - Échelle : s'arrêter au PREMIER rung qui rend la donnée. Ne pas monter
          d'un cran tant que le précédent marche.
        - 0. API officielle : vérifier AVANT de scraper (Crunchbase/SimilarWeb/G2
          en ont une).
        - 1. `scrapling extract get URL out.md` si 403, brut/complet requis, ou
          batch (`-s SELECTEUR` = ne ramener que le fragment) |
          `fetch --network-idle` si get rend vide (JS) |
          `stealthy-fetch --solve-cloudflare` si anti-bot. Ces deux flags sont
          OFF par défaut : les omettre gâche le rung.
        - Statut et taille ne prouvent rien — un 403 peut porter 75 Ko de page de
          blocage : ouvrir le fichier, y chercher la donnée demandée.
      '';
    }
    {
      name = "Execution Discipline";
      body = ''
        - Act on established facts. Never re-derive a decision already made.
        - After a fix, re-run the EXACT failing command. Same error twice → stop,
          question the assumption, change approach.
        - Blocked after 3 attempts → report what was tried. Never fake success,
          never weaken a test to make it pass.
        - Lead with the outcome. Show the command output that proves it.
        - Fix what was asked. Adjacent problems: mention, do not touch.
      '';
    }
    {
      name = "Style (FR)";
      body = ''
        - Réponses courtes et actionnables.
        - Quand tu modifies du code : quoi / pourquoi / comment vérifier (3 bullets).
      '';
    }
  ];
in
{
  inherit preamble trunkSections render;

  trunk = render trunkSections;
}
