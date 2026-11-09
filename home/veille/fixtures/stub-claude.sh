# Bouchon de claude pour checks/veille.nix (lancé par `bash`, hors réseau).
# Journalise argv et stdin dans $STUB_LOG ; rend en JSON le texte de $STUB_RESULT, où
# @DATE@ = jour lu dans le prompt ; si STUB_FAIL est non vide, échoue (rc 3).
set -euo pipefail
printf '%s\n' "$@" > "$STUB_LOG/args"
cat > "$STUB_LOG/stdin"
day="$(sed -n 's/^- \[\([0-9]\{4\}-[0-9][0-9]-[0-9][0-9]\)\] .*/\1/p' "$STUB_LOG/args" | sed -n 1p)"
if [ -z "$day" ]; then
  echo "stub-claude: pas de date dans le prompt" >&2
  exit 4
fi
printf '%s\n' "$day" > "$STUB_LOG/day"
if [ -n "${STUB_FAIL:-}" ]; then
  printf '{"type":"result","is_error":true,"subtype":"error_during_execution"}\n'
  exit 3
fi
sed "s/@DATE@/$day/g" "$STUB_RESULT" |
  jq -Rs '{type: "result", is_error: false, subtype: "success", result: ., total_cost_usd: 0.01, duration_ms: 1500}'
