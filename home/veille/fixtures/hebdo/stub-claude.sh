# Bouchon de claude pour checks/veille-hebdo.nix (lancé par `bash`, hors réseau).
# Journalise argv (un par ligne), stdin et le répertoire courant dans $STUB_LOG ;
# STUB_FAIL=1 : rend un résultat en erreur et sort en rc 3 ; sinon imprime $STUB_RESULT
# (objet résultat de `claude --output-format json`, structured_output compris).
set -euo pipefail
printf '%s\n' "$@" > "$STUB_LOG/args"
cat > "$STUB_LOG/stdin"
pwd -P > "$STUB_LOG/cwd"
if [ "${STUB_FAIL:-}" = 1 ]; then
  printf '{"type":"result","is_error":true,"subtype":"error_during_execution"}\n'
  exit 3
fi
cat "$STUB_RESULT"
