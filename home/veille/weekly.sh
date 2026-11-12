# Tri hebdomadaire : les URL de l'inbox pas encore jugées passent devant Opus, qui n'a que
# WebFetch, restreint aux domaines des candidats et à une liste fixe de sources primaires.
# Packagé par home/veille.nix (writeShellApplication : shebang, `set -euo pipefail`, PATH,
# VEILLE_HEBDO_PROMPT, VEILLE_HEBDO_SCHEMA et VEILLE_SEED = chemins du store). Sans argument.
# Sortie : $HEBDO_VAULT/veille/hebdo/<semaine>.md (entrées retenues seulement, jamais écrasé :
# suffixe -2, -3…) et une ligne url⇥verdict⇥semaine⇥note par verdict valide ajoutée à
# $VEILLE_DIR/ledger.tsv. Tout se prépare dans $work : un échec (gh, claude, ancre Settled,
# résultat illisible) sort en 1 avant toute écriture.
# Surcharges des tests hors réseau (checks/veille-hebdo.nix) : VEILLE_DIR, VEILLE_CLAUDE,
# VEILLE_GH, HEBDO_VAULT, HEBDO_REPO, HEBDO_REPLAY, HEBDO_WEEK.
prompt_file="${VEILLE_HEBDO_PROMPT:?chemin de weekly-prompt.md}"
schema_file="${VEILLE_HEBDO_SCHEMA:?chemin de weekly-schema.json}"
seed="${VEILLE_SEED:?chemin de ledger-seed.tsv}"
claude="${VEILLE_CLAUDE:-/opt/homebrew/bin/claude}"
gh="${VEILLE_GH:-gh}"
out="${VEILLE_DIR:-$HOME/.local/share/veille-ttw}"
vault="${HEBDO_VAULT:-$HOME/Vaults/AlxVault/02-Projets/nix-darwin}"
repo="${HEBDO_REPO:-$HOME/.config/nix-darwin}"
replay="${HEBDO_REPLAY:-$HOME/.local/share/ttw-replay}"
week="${HEBDO_WEEK:-$(date +%G-W%V)}"
inbox="$out/inbox.md"
ledger="$out/ledger.tsv"
hebdo="$vault/veille/hebdo"
max_candidats=30

# La semaine entre dans un nom de fichier et dans le prompt : forme stricte.
if [[ ! "$week" =~ ^[0-9]{4}-W[0-9]{2}$ ]]; then
  echo "semaine invalide : $week" >&2
  exit 1
fi
if [ ! -f "$inbox" ]; then
  echo "hebdo: pas d'inbox ($inbox), rien à trier"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# URL déjà jugées : graine (tri du 12/11) ∪ registre. Normalisées comme daily.sh (sans
# espaces ni <>), la graine et le registre portant la forme normalisée.
declare -A connues=()
for f in "$seed" "$ledger"; do
  if [ ! -f "$f" ]; then continue; fi
  while IFS=$'\t' read -r u _ || [ -n "$u" ]; do
    if [ -n "$u" ]; then connues["$u"]=1; fi
  done < "$f"
done

# Candidats : lignes brutes de l'inbox dont l'URL est inconnue, une fois chacune, les plus
# anciennes d'abord, plafond $max_candidats (au-delà : comptées en attente, triées la semaine
# suivante). Hôte hors forme nom.tld en [a-z0-9-] (identifiants, majuscules, IDN, localhost,
# nom sans point, IP littérale) : candidat abandonné, sinon il entrerait dans la liste WebFetch.
url_re='^https?://([^/?#]+)'
auth_re='^([a-z0-9-]+\.)+[a-z]{2,}(:[0-9]+)?$'
declare -A envoyes=()
declare -A en_attente=()
declare -A domaines_vus=()
domaines=()
for d in arxiv.org github.com code.claude.com docs.claude.com docs.anthropic.com www.anthropic.com openai.com developers.openai.com; do
  domaines_vus["$d"]=1
  domaines+=("$d")
done
candidats="$work/candidats.md"
: > "$candidats"
n=0
attente=0
while IFS= read -r l || [ -n "$l" ]; do
  case "$l" in *—*) ;; *) continue ;; esac
  u="${l##*—}"
  u="${u//[[:space:]<>]/}"
  if [ -z "$u" ]; then continue; fi
  if [ -n "${connues[$u]+x}" ]; then
    continue
  fi
  if [ -n "${envoyes[$u]+x}" ]; then continue; fi
  auth=""
  if [[ "$u" =~ $url_re ]]; then auth="${BASH_REMATCH[1]}"; fi
  if [[ ! "$auth" =~ $auth_re ]]; then
    echo "candidat abandonné (hôte) : $u" >&2
    continue
  fi
  if [ "$n" -ge "$max_candidats" ]; then
    if [ -z "${en_attente[$u]+x}" ]; then
      en_attente["$u"]=1
      attente=$((attente + 1))
    fi
    continue
  fi
  hote="${auth%%:*}"
  if [ -z "${domaines_vus[$hote]+x}" ]; then
    domaines_vus["$hote"]=1
    domaines+=("$hote")
  fi
  envoyes["$u"]=1
  printf '%s\n' "$l" >> "$candidats"
  n=$((n + 1))
done < "$inbox"
if [ "$n" = 0 ]; then
  echo "hebdo: aucun candidat nouveau, claude non appelé"
  exit 0
fi

# Contexte, chaque section plafonnée. Lecteurs complets (sed -n, tail) : pas de SIGPIPE
# sous pipefail.
settled="$work/settled.md"
if [ -f "$repo/CLAUDE.md" ]; then
  awk '/^- Settled, do not re-propose:/ { f = 1; print; next } f && /^  / { print; next } f { exit }' "$repo/CLAUDE.md" | sed -n '1,40p' > "$settled"
fi
if [ ! -s "$settled" ]; then
  echo "ancre « - Settled, do not re-propose: » absente de $repo/CLAUDE.md" >&2
  exit 1
fi
if [ ! -d "$vault" ]; then
  echo "vault introuvable : $vault" >&2
  exit 1
fi
if ! (cd "$repo" && "$gh" pr list --state merged --json number,title --limit 100) > "$work/prs.json"; then
  echo "gh pr list en erreur, claude non appelé" >&2
  exit 1
fi
if ! jq -r '.[] | "#\(.number) \(.title)"' "$work/prs.json" > "$work/prs.md"; then
  echo "sortie de gh pr list illisible, claude non appelé" >&2
  exit 1
fi

bundle="$work/bundle.md"
{
  echo "## Settled"
  cat "$settled"
  echo
  echo "## Notes du vault"
  (cd "$vault" && find . -name '*.md' -not -path './veille/hebdo/*' -not -path '*/.*/*' | LC_ALL=C sort | sed -n '1,400p')
  echo
  echo "## Semaines précédentes"
  if [ -d "$hebdo" ]; then
    find "$hebdo" -maxdepth 1 -name '*.md' | LC_ALL=C sort -r | while IFS= read -r f; do
      printf '### %s\n' "${f##*/}"
      sed -n '/^## \|^- Source : /p' "$f"
    done | sed -n '1,300p'
  fi
  echo
  echo "## PR mergées"
  sed -n '1,100p' "$work/prs.md"
  echo
  echo "## Runs TTW"
  if [ -d "$repo/.claude/output/ttw" ]; then
    find "$repo/.claude/output/ttw" -mindepth 2 -maxdepth 2 -name 00-context.md -printf '%T@\t%p\n' |
      sort -rn | sed -n '1,120p' | cut -f2- | while IFS= read -r f; do
      sed -n '1{/^# TTW:/p}' "$f"
    done
  fi
  echo
  echo "## Rejeu TTW"
  if [ -d "$replay" ]; then
    # Le plus récent par mtime (le nom trie 2026-11-16-2.md avant 2026-11-16.md) ; rien à
    # partir de « ## Examples », qui porte des chemins de transcripts d'autres projets.
    dernier="$(find "$replay" -maxdepth 1 -name '*.md' -printf '%T@\t%p\n' | sort -rn | sed -n '1p' | cut -f2-)"
    if [ -n "$dernier" ]; then awk '/^## Examples/ { exit } NR <= 40' "$dernier"; fi
  fi
  echo
  echo "## Registre"
  cat "$seed"
  if [ -f "$ledger" ]; then tail -n 500 "$ledger"; fi
  echo
  echo "## Candidats"
  cat "$candidats"
} > "$bundle"

# Opus : répertoire neutre, réglages ignorés (sinon l'allow `WebFetch` de l'utilisateur ouvre
# tout hôte), WebFetch seul et par domaine ; le dossier entre par stdin, jamais par argv.
allow=()
for d in "${domaines[@]}"; do allow+=(--allowedTools "WebFetch(domain:$d)"); done
prompt="$(sed "s/{{SEMAINE}}/${week}/g" "$prompt_file")"
schema="$(cat "$schema_file")"
res="$work/res.json"
cd "$work" || exit 1
rc=0
"$claude" -p "$prompt" \
  --model opus \
  --tools WebFetch \
  "${allow[@]}" \
  --setting-sources '' \
  --permission-prompts none \
  --safe-mode \
  --strict-mcp-config \
  --no-session-persistence \
  --max-budget-usd 5 \
  --output-format json \
  --json-schema "$schema" < "$bundle" > "$res" || rc=$?
erreur="$(jq -r '.is_error' "$res" 2> /dev/null || true)"
if [ "$rc" != 0 ] || [ "$erreur" != false ]; then
  subtype="$(jq -r '.subtype // "illisible"' "$res" 2> /dev/null || echo illisible)"
  echo "hebdo en erreur : claude rc=$rc subtype=$subtype" >&2
  exit 1
fi
if ! jq -e '.structured_output.entries | type == "array"' "$res" > /dev/null 2>&1; then
  echo "hebdo en erreur : pas de structured_output.entries dans le résultat" >&2
  exit 1
fi

# Une ligne par entrée, champs séparés par 0x1f (séparateur non blanc : un champ vide garde sa
# place). Backticks retirés, longueurs en caractères (jq), puis : entrée hors forme ou portant
# un caractère de contrôle (C0, DEL, C1, U+2028/9) réduite à son statut, sans valeur.
jq -r '.structured_output.entries[]
  | if type != "object" then ["forme"]
    else [.url, .verdict, .titre, .type, .source_primaire, .verification, .lien_ttw, .raison]
      | if all(.[]; type == "string") | not then ["forme"]
        else map(gsub("`"; ""))
          | if any(.[]; explode | any(. < 32 or (. >= 127 and . < 160) or . == 8232 or . == 8233)) then ["contrôle"]
            else ["ok", (.[2] | length), (.[5] | length), (.[6] | length), (.[7] | length)] + . | map(tostring)
            end
        end
    end
  | join("\u001f")' "$res" > "$work/entrees"

# Rien qui s'affiche ou se lie dans Obsidian ([[, ![, ](, <balise>), ni \ ni | ; URL jugée =
# une URL envoyée, une seule fois ; plafonds titre 120, verification 400, lien_ttw 300, raison 200.
plein='[^[:space:]]'
source_re='^https?://[^ <>"]+$'
declare -A jugees=()
rendu="$work/rendu.md"
ajout="$work/ledger.add"
: > "$rendu"
: > "$ajout"
retenues=0
ecartees=0
inverifiables=0
rejetees=0
i=0
while IFS=$'\x1f' read -r statut lt lv ll lr url verdict titre type primaire verif lien raison; do
  i=$((i + 1))
  motif=""
  if [ "$statut" != ok ]; then
    motif="$statut"
  else
    for champ in "$url" "$verdict" "$titre" "$type" "$primaire" "$verif" "$lien" "$raison"; do
      if [[ "$champ" == *[][\<\>\\\|]* ]]; then
        motif="caractère interdit"
      fi
      if [[ "$champ" == *%%* ]]; then
        motif="caractère interdit"
      fi
    done
  fi
  if [ -z "$motif" ]; then
    case "$verdict" in retenue | écartée | invérifiable) ;; *) motif="verdict" ;; esac
  fi
  if [ -z "$motif" ]; then
    case "$type" in officiel | étude | blog | forum | code) ;; *) motif="type" ;; esac
  fi
  if [ -z "$motif" ] && [[ ! "$primaire" =~ $source_re ]]; then motif="source primaire"; fi
  # Une retenue cite une source que WebFetch pouvait lire ; invérifiable peut citer un domaine
  # refusé (c'est la consigne du prompt), écartée/invérifiable ne s'affichent pas.
  if [ -z "$motif" ] && [ "$verdict" = retenue ]; then
    auth_p=""
    if [[ "$primaire" =~ $url_re ]]; then auth_p="${BASH_REMATCH[1]}"; fi
    if [[ ! "$auth_p" =~ $auth_re ]] || [ -z "${domaines_vus[${auth_p%%:*}]+x}" ]; then
      motif="source hors domaines"
    fi
  fi
  if [ -z "$motif" ] && { [ "$lt" -gt 120 ] || [ "$lv" -gt 400 ] || [ "$ll" -gt 300 ] || [ "$lr" -gt 200 ]; }; then
    motif="plafond"
  fi
  if [ -z "$motif" ] && { [[ ! "$titre" =~ $plein ]] || [[ ! "$verif" =~ $plein ]] || [[ ! "$lien" =~ $plein ]] || [[ ! "$raison" =~ $plein ]]; }; then
    motif="champ vide"
  fi
  if [ -z "$motif" ] && [ -z "${envoyes[$url]+x}" ]; then motif="URL non envoyée"; fi
  if [ -z "$motif" ] && [ -n "${jugees[$url]+x}" ]; then motif="URL en double"; fi
  if [ -n "$motif" ]; then
    rejetees=$((rejetees + 1))
    if [ "$statut" = ok ]; then
      printf 'rejetée (%s) : entrée %s, %s\n' "$motif" "$i" "${url:0:200}" >&2
    else
      printf 'rejetée (%s) : entrée %s\n' "$motif" "$i" >&2
    fi
    continue
  fi
  jugees["$url"]=1
  case "$verdict" in
    retenue)
      retenues=$((retenues + 1))
      printf '## %s\n\n- Source : %s\n- Source primaire : %s\n- Type : %s\n- Vérifié : %s\n- Lien TTW : %s\n\n' \
        "$titre" "$url" "$primaire" "$type" "$verif" "$lien" >> "$rendu"
      ;;
    écartée) ecartees=$((ecartees + 1)) ;;
    *) inverifiables=$((inverifiables + 1)) ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$url" "$verdict" "$week" "$raison" >> "$ajout"
done < "$work/entrees"
reportees=$((n - retenues - ecartees - inverifiables))

# Placement : fichier hebdo sous le premier suffixe libre (mv -n n'écrase jamais, même en
# course), puis registre étendu. Rien de retenu : pas de fichier hebdo.
if [ "$retenues" -gt 0 ]; then
  page="$work/hebdo.md"
  {
    printf -- '---\ndate: %s\nsemaine: %s\nprojet: nix-darwin\ntags: [ttw, veille]\n---\n\n' "$(date +%F)" "$week"
    printf '# Veille TTW %s\n\n' "$week"
    printf '%s retenue(s) sur %s candidat(s) : %s écartée(s), %s invérifiable(s), %s rejetée(s), %s reportée(s).\n\n' \
      "$retenues" "$n" "$ecartees" "$inverifiables" "$rejetees" "$reportees"
    cat "$rendu"
  } > "$page"
  mkdir -p "$hebdo"
  suffixe=""
  k=1
  while [ -e "$hebdo/$week$suffixe.md" ]; do
    k=$((k + 1))
    suffixe="-$k"
  done
  mv -n "$page" "$hebdo/$week$suffixe.md"
  if [ -e "$page" ]; then
    echo "$hebdo/$week$suffixe.md apparu pendant le run : rien écrasé, registre inchangé" >&2
    exit 1
  fi
fi
if [ -s "$ajout" ]; then
  if [ -s "$ledger" ] && [ -n "$(tail -c 1 "$ledger")" ]; then printf '\n' >> "$ledger"; fi
  cat "$ajout" >> "$ledger"
fi
echo "hebdo: $retenues retenue(s), $ecartees écartée(s), $inverifiables invérifiable(s), $rejetees rejetée(s), $reportees reportée(s), $attente en attente"
jq -r '"tri hebdo: \(.subtype) cost=\(.total_cost_usd // "?") dur_s=\((.duration_ms // 0) / 1000)"' "$res"
