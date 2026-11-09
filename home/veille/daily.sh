# Collecte quotidienne : API -> bruts/, tri Haiku sans outils -> tris/ + inbox.md, dans ~/.local/share/veille-ttw.
# Packagé par home/veille.nix (writeShellApplication : shebang, `set -euo pipefail`, PATH,
# VEILLE_FETCH et VEILLE_PROMPT = chemins du store). Argument : fenêtre en heures (48).
# Tout s'écrit d'abord dans $work ; la sortie n'est touchée qu'après un tri réussi, sans rien
# écraser : bruts/ et tris/ prennent un suffixe -2, -3…, inbox.md n'est qu'étendu.
# VEILLE_DIR et VEILLE_CLAUDE : surcharges des tests hors réseau (checks/veille.nix).
fetch="${VEILLE_FETCH:?chemin de fetch.py}"
prompt_file="${VEILLE_PROMPT:?chemin de filter-prompt.md}"
claude="${VEILLE_CLAUDE:-/opt/homebrew/bin/claude}"
# Texte web brut : gardé hors des notes indexées par graphify et enquire ; seule la
# sélection hebdomadaire y entre.
out="${VEILLE_DIR:-$HOME/.local/share/veille-ttw}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
today="$(date +%F)"
brut="$work/brut.md"
tri="$work/tri.json"

python3 -I "$fetch" "${1:-48}" > "$brut"
prompt="$(sed "s/{{DATE}}/${today}/g" "$prompt_file")"
# Répertoire neutre + --safe-mode : ni CLAUDE.md, ni hooks, ni plugins dans le tri.
# Le brut (donnée non fiable) entre par stdin, jamais par argv.
cd "$work" || exit 1
rc=0
"$claude" -p "$prompt" \
  --model haiku \
  --tools "" \
  --strict-mcp-config \
  --safe-mode \
  --no-session-persistence \
  --max-budget-usd 0.5 \
  --output-format json < "$brut" > "$tri" || rc=$?
erreur="$(jq -r '.is_error' "$tri" 2> /dev/null || true)"
if [ "$rc" != 0 ] || [ "$erreur" != false ]; then
  subtype="$(jq -r '.subtype // "illisible"' "$tri" 2> /dev/null || echo illisible)"
  echo "tri en erreur : claude rc=$rc subtype=$subtype" >&2
  exit 1
fi

# Ligne admise : `- [<jour>] titre — résumé — type — URL`, 4 champs exactement, type connu,
# URL http(s) ; rien qui s'affiche ou se lie dans Obsidian (![, [[, <) ; backticks retirés.
# Dédoublonnage sur l'URL normalisée (sans espaces ni <>), sans pipe grep (141).
inbox="$out/inbox.md"
url_re='^https?://[^ <>]+$'
plein='[^[:space:]]'
declare -A vues=()
if [ -f "$inbox" ]; then
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in *—*) ;; *) continue ;; esac
    u="${l##*—}"
    u="${u//[[:space:]<>]/}"
    if [ -n "$u" ]; then vues["$u"]=1; fi
  done < "$inbox"
fi
ajout="$work/ajout.md"
: > "$ajout"
ajoutees=0
doublons=0
rejetees=0
rejet() {
  rejetees=$((rejetees + 1))
  printf 'rejetée (%s) : %s\n' "$1" "$l" >&2
}
while IFS= read -r l || [ -n "$l" ]; do
  if [[ ! "$l" =~ $plein ]] || [ "$l" = "- [$today] (rien)" ]; then continue; fi
  if [[ "$l" != "- [$today] "* ]]; then
    rejet "préfixe"
    continue
  fi
  l="${l//\`/}" # Haiku met parfois chemins ou types entre backticks : retirés, pas rejetés
  if [[ "$l" == *'!['* || "$l" == *'[['* || "$l" == *'<'* ]]; then
    rejet "caractère interdit"
    continue
  fi
  reste="$l"
  tirets=0
  while [[ "$reste" == *—* ]]; do
    reste="${reste#*—}"
    tirets=$((tirets + 1))
  done
  if [ "$tirets" != 3 ]; then
    rejet "$((tirets + 1)) champs"
    continue
  fi
  url="${l##*—}"
  r="${l%—*}"
  type="${r##*—}"
  r="${r%—*}"
  resume="${r##*—}"
  titre="${r%—*}"
  titre="${titre#"- [$today] "}"
  type="${type//[[:space:]]/}"
  url="${url//[[:space:]<>]/}"
  case "$type" in
    officiel | étude | blog | forum | code) ;;
    *)
      rejet "type $type"
      continue
      ;;
  esac
  if [[ ! "$url" =~ $url_re ]]; then
    rejet "URL"
    continue
  fi
  if [[ ! "$titre" =~ $plein ]] || [[ ! "$resume" =~ $plein ]]; then
    rejet "champ vide"
    continue
  fi
  if [ -n "${vues[$url]+x}" ]; then
    doublons=$((doublons + 1))
    continue
  fi
  vues["$url"]=1
  printf '%s\n' "$l" >> "$ajout"
  ajoutees=$((ajoutees + 1))
done < <(jq -r '.result' "$tri")

# Premier suffixe libre pour les deux dossiers ; mv -n n'écrase jamais, même en course.
mkdir -p "$out/bruts" "$out/tris"
suffixe=""
i=1
while [ -e "$out/bruts/$today$suffixe.md" ] || [ -e "$out/tris/$today$suffixe.json" ]; do
  i=$((i + 1))
  suffixe="-$i"
done
place() {
  mv -n "$1" "$2"
  if [ -e "$1" ]; then
    echo "$2 apparu pendant le run : rien écrasé" >&2
    exit 1
  fi
}
place "$brut" "$out/bruts/$today$suffixe.md"
place "$tri" "$out/tris/$today$suffixe.json"
if [ "$ajoutees" -gt 0 ]; then
  if [ -s "$inbox" ] && [ -n "$(tail -c 1 "$inbox")" ]; then printf '\n' >> "$inbox"; fi
  cat "$ajout" >> "$inbox"
fi
echo "inbox: $ajoutees ajoutée(s), $doublons doublon(s), $rejetees rejetée(s)"
jq -r '"tri: \(.subtype) cost=\(.total_cost_usd) dur_s=\(.duration_ms/1000)"' "$out/tris/$today$suffixe.json"
