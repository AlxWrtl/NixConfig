#!/usr/bin/env bash
# Guard: graceful handling outside git repos
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Not a git repo"
  exit 0
fi
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
LAST_COMMIT=$(git log --oneline -1 2>/dev/null || echo "no commits")
MODIFIED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
STATUS_LINE="branch: $BRANCH | last: $LAST_COMMIT | modified: $MODIFIED files"
echo "$STATUS_LINE"
# Project memory index: the notes of the vault folder named after the main
# checkout (a worktree resolves to its main repo), for the model to read on
# demand. Non-session notes first, then sessions/ newest first; the whole
# stdout stays under MAX characters, because Claude Code truncates a hook's
# plain stdout at 10,000 characters to a 2,000-character preview. No folder,
# or no note → nothing more. bash 3.2-safe (no mapfile); always exit 0.
VAULT="@alxVaultPath@"
MAX=9000
COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
case "$COMMON" in
*/.git) TOP="${COMMON%/.git}" ;;
*) TOP=$(git rev-parse --show-toplevel 2>/dev/null) ;;
esac
NAME=$(basename "$TOP")
[ "$NAME" = "stock-market" ] && NAME="trading-agent"
DIR="$VAULT/02-Projets/$NAME"
[ -n "$TOP" ] && [ -n "$NAME" ] && [ -d "$DIR" ] || exit 0
# Paths relative to DIR, one per line; a name holding a control character
# (newline included) is dropped, so a note name cannot forge a line. A
# function, not inline: bash 3.2 cannot parse `case … )` inside `$( … )`.
list_notes() {
  (cd "$DIR" 2>/dev/null && find -L . -type f -name '*.md' -print0 2>/dev/null) |
    while IFS= read -r -d '' F; do
      case "$F" in *[[:cntrl:]]*) continue ;; esac
      printf '%s\n' "${F#./}"
    done
}
ALL=$(list_notes)
NOTES=()
while IFS= read -r F; do
  [ -n "$F" ] && NOTES[${#NOTES[@]}]="$F"
done < <(
  printf '%s\n' "$ALL" | grep -v '^sessions/' | LC_ALL=C sort
  printf '%s\n' "$ALL" | grep '^sessions/' | LC_ALL=C sort -r
)
TOTAL=${#NOTES[@]}
[ "$TOTAL" -gt 0 ] || exit 0
# ${#VAR} counts characters only under a UTF-8 locale (bytes under C).
LC_ALL=en_US.UTF-8
HEADER="Mémoire du projet — notes dans $DIR/ (à lire si utiles) :"
TAIL_A="… "
TAIL_B=" autres notes (ls \"$DIR\")"
USED=$((${#STATUS_LINE} + 1 + ${#HEADER} + 1))
FULL=$USED
for F in "${NOTES[@]}"; do FULL=$((FULL + ${#F} + 3)); done
if [ "$FULL" -le "$MAX" ]; then
  K=$TOTAL
else
  # Room for the tail line, its count sized as TOTAL (never fewer digits).
  RESERVE=$((${#TAIL_A} + ${#TOTAL} + ${#TAIL_B} + 1))
  K=0
  while [ "$K" -lt "$TOTAL" ]; do
    LEN=$((${#NOTES[K]} + 3))
    [ $((USED + LEN + RESERVE)) -le "$MAX" ] || break
    USED=$((USED + LEN))
    K=$((K + 1))
  done
fi
[ "$K" -gt 0 ] || exit 0
echo "$HEADER"
I=0
while [ "$I" -lt "$K" ]; do
  printf -- '- %s\n' "${NOTES[I]}"
  I=$((I + 1))
done
[ "$K" -lt "$TOTAL" ] && printf '%s%s%s\n' "$TAIL_A" "$((TOTAL - K))" "$TAIL_B"
exit 0
