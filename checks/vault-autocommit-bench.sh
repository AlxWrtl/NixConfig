#!/usr/bin/env bash
# Bench for the vault auto-commit in scripts/vault-snapshot.sh.
#
# Runs against THROWAWAY repos under TMPDIR — never the real vault. The
# snapshot chain (age, gh) is not exercised: this covers the git half only, by
# extracting the auto-commit block and running it against fixtures.
#
# Every failure path is a case, because the whole point of the block is that it
# must never abort the backup. A guard that only works on the happy path would
# turn "one uncommitted note" into "no backup at all".

set -uo pipefail
SRC="$(dirname "${BASH_SOURCE[0]}")/../home/claude-code/scripts/vault-snapshot.sh"
[ -f "$SRC" ] || { echo "bench: cannot find $SRC" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vaultac.XXXXXX") || exit 2
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "bench: no work dir" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf 'ok    %-44s %s\n' "$1" "${2:-}"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL  %-44s %s\n' "$1" "${2:-}"; }

# The block under test, lifted verbatim from the real script so the bench can
# never drift from it: from the DIRTY assignment to the closing fi.
BLOCK="$WORK/block.sh"
awk '/^DIRTY=\$\(git -C "\$VAULT" status/{f=1} f{print} f&&/^fi$/{exit}' "$SRC" > "$BLOCK"
grep -q 'checkout -q -b' "$BLOCK" || { echo "bench: extraction failed — block not found" >&2; exit 2; }

run_block() { # run_block <vault> ; prints the log
  local v="$1"
  cat > "$WORK/driver.sh" <<DRV
VAULT="$v"
LOG="$v/../run.log"
log() { printf '%s\n' "\$*" >>"\$LOG"; }
$(cat "$BLOCK")
DRV
  : > "$v/../run.log"
  bash "$WORK/driver.sh" >/dev/null 2>&1
  cat "$v/../run.log" 2>/dev/null
}

mkvault() { # mkvault <name> -> path, one commit on `main`
  local d="$WORK/$1/v"; mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email b@e; git -C "$d" config user.name B
  # The real config signs commits with an SSH key the sandbox cannot read, so
  # every fixture commit failed with "No private key found" and the bench
  # reported 12 failures that were all its own. Signing is irrelevant to what
  # is under test.
  git -C "$d" config commit.gpgsign false
  git -C "$d" config tag.gpgsign false
  echo base > "$d/base.md"
  git -C "$d" add -A
  git -C "$d" commit -q -m base || { echo "bench: fixture commit failed" >&2; exit 2; }
  printf '%s' "$d"
}

echo "=== 1. arbre sale : commit, marqueur, base avancée ==="
V=$(mkvault t1); echo nouvelle > "$V/note.md"
BEFORE=$(git -C "$V" rev-parse HEAD)
OUT=$(run_block "$V")
[ -z "$(git -C "$V" status --porcelain)" ] && ok "arbre propre après" || bad "arbre encore sale"
[ "$(git -C "$V" branch --show-current)" = "main" ] && ok "revenu sur main" \
  || bad "branche courante" "$(git -C "$V" branch --show-current)"
BR=$(git -C "$V" branch --list 'vault/*' | tr -d ' *')
[ -n "$BR" ] && ok "marqueur créé" "$BR" || bad "aucun marqueur vault/*"
[ "$(git -C "$V" rev-parse main)" = "$(git -C "$V" rev-parse "$BR")" ] \
  && ok "main == marqueur (fast-forward)" || bad "main n'a pas suivi"
[ "$(git -C "$V" rev-parse HEAD)" != "$BEFORE" ] && ok "un commit a été créé" || bad "aucun commit"
git -C "$V" ls-tree -r --name-only HEAD | grep -q '^note.md$' \
  && ok "la note est dans le commit" || bad "note absente du commit"
echo "$OUT" | grep -q "auto-saved on vault/" && ok "journalisé" || bad "pas journalisé" "$OUT"

echo
echo "=== 2. l'état d'AVANT reste atteignable (le filet demandé) ==="
[ "$(git -C "$V" rev-parse "$BR~1")" = "$BEFORE" ] \
  && ok "vault/<stamp>~1 == état d'avant" || bad "état d'avant perdu"

echo
echo "=== 3. arbre propre : aucun bruit ==="
V2=$(mkvault t2)
OUT=$(run_block "$V2")
[ -z "$(git -C "$V2" branch --list 'vault/*')" ] && ok "aucune branche créée" || bad "branche créée à tort"
[ "$(git -C "$V2" rev-list --count HEAD)" = "1" ] && ok "aucun commit vide" || bad "commit inutile"

echo
echo "=== 4. HEAD détaché : ne commite pas, ne casse pas ==="
V3=$(mkvault t3); echo x > "$V3/n.md"
git -C "$V3" checkout -q --detach HEAD
OUT=$(run_block "$V3")
echo "$OUT" | grep -q "detached HEAD" && ok "détecté et journalisé" || bad "détaché non détecté" "$OUT"
[ -z "$(git -C "$V3" branch --list 'vault/*')" ] && ok "aucune branche créée" || bad "branche créée sur détaché"
[ -n "$(git -C "$V3" status --porcelain)" ] && ok "modifs préservées" || bad "modifs perdues"

echo
echo "=== 5. gitignore respecté ==="
V4=$(mkvault t4); printf 'ignored.md\n' > "$V4/.gitignore"
git -C "$V4" add .gitignore; git -C "$V4" commit -q -m gi
echo secret > "$V4/ignored.md"; echo reel > "$V4/reel.md"
run_block "$V4" >/dev/null
git -C "$V4" ls-tree -r --name-only HEAD | grep -q '^reel.md$' && ok "fichier réel commité" || bad "réel absent"
git -C "$V4" ls-tree -r --name-only HEAD | grep -q '^ignored.md$' && bad "ignoré commité !" || ok "ignoré resté dehors"

echo
echo "=== 6. commit impossible : ni bloqué, ni laissé sur la branche ==="
# A failing pre-commit hook is the deterministic way to make `git commit`
# return non-zero. Unsetting user.email is not: git finds an identity elsewhere.
V5=$(mkvault t5); echo x > "$V5/n.md"
mkdir -p "$WORK/t5/hooks"
printf '#!/bin/sh\nexit 1\n' > "$WORK/t5/hooks/pre-commit"
chmod +x "$WORK/t5/hooks/pre-commit"
git -C "$V5" config core.hooksPath "$WORK/t5/hooks"
OUT=$(run_block "$V5")
CUR=$(git -C "$V5" branch --show-current)
[ "$CUR" = "main" ] && ok "revenu sur main malgré l'échec" || bad "laissé sur" "$CUR"
echo "$OUT" | grep -q "commit failed" && ok "échec journalisé" || bad "échec silencieux" "$OUT"
[ -z "$(git -C "$V5" branch --list 'vault/*')" ] \
  && ok "branche vide supprimée" || bad "branche vide laissée"
[ -n "$(git -C "$V5" status --porcelain)" ] && ok "modifs préservées" || bad "modifs perdues"
echo "$OUT" | grep -q "NOT in this snapshot" && ok "omission nommée" || bad "omission taise"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
