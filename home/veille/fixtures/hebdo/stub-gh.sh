# Bouchon de gh pour checks/veille-hebdo.nix (lancé par `bash`, hors réseau).
# Journalise argv (un par ligne) et le répertoire courant dans $STUB_GH_LOG ;
# STUB_GH_FAIL=1 : échoue (rc 1) ; sinon imprime deux PR mergées.
set -euo pipefail
printf '%s\n' "$@" > "$STUB_GH_LOG/args"
pwd -P > "$STUB_GH_LOG/cwd"
if [ "${STUB_GH_FAIL:-}" = 1 ]; then
  echo "stub-gh: HTTP 401: Bad credentials" >&2
  exit 1
fi
printf '%s\n' '[{"number":403,"title":"feat(claude): bump to v2.1.321"},{"number":404,"title":"docs: AGENTS.md instruction compliance"}]'
