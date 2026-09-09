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
case "$OUT" in *"auto-saved vault on vault/"*) ok "journalisé" ;; *) bad "pas journalisé" "$OUT" ;; esac

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
echo "=== 7. isolation : un commit par projet, jamais un fourre-tout ==="
# Le defaut que ce groupement corrige : 6 commits de l'historique reel du vault
# touchent plusieurs projets, un d'eux trois. Un `add -A` en aurait fait la regle.
V6=$(mkvault t6)
mkdir -p "$V6/02-Projets/Alpha" "$V6/02-Projets/Beta" "$V6/04-Resources"
echo a > "$V6/02-Projets/Alpha/note.md"
echo b > "$V6/02-Projets/Beta/note.md"
echo r > "$V6/04-Resources/ref.md"
run_block "$V6" >/dev/null
N=$(git -C "$V6" rev-list --count HEAD)
[ "$N" = "4" ] && ok "3 commits ajoutes (1 par groupe)" "total $N" \
  || bad "nombre de commits" "$N (attendu 4 = base + 3)"
# Le journal est capture AVANT d'etre filtre. `git log | grep -q` est un piege
# ici : grep -q sort au premier match, git recoit SIGPIPE, et le `pipefail` de
# ce banc transforme ce succes en echec. Seul le sujet situe en DERNIERE ligne
# passait, ce qui a produit 2 faux echecs sur 3 assertions saines.
SUBJ=$(git -C "$V6" log --format=%s -3)
case "$SUBJ" in *"vault(Alpha): auto-save"*) ok "commit Alpha etiquete" ;; *) bad "Alpha mal etiquete" ;; esac
case "$SUBJ" in *"vault(Beta): auto-save"*)  ok "commit Beta etiquete"  ;; *) bad "Beta mal etiquete"  ;; esac
case "$SUBJ" in *"vault(vault): auto-save"*) ok "hors-projet etiquete vault" ;; *) bad "hors-projet mal etiquete" ;; esac

echo "  -- aucun commit ne melange deux projets --"
MIX=0
for h in $(git -C "$V6" rev-list -3 HEAD); do
  p=$(git -C "$V6" show --name-only --format= "$h" | sed -n 's|^02-Projets/\([^/]*\)/.*|\1|p' | sort -u | grep -c .)
  [ "$p" -gt 1 ] && MIX=$((MIX+1))
done
[ "$MIX" = "0" ] && ok "zero commit multi-projet" || bad "$MIX commit(s) melangent des projets"

echo
echo "=== 8. noms de fichiers reels : espaces, accents, apostrophe ==="
V7=$(mkvault t7)
mkdir -p "$V7/02-Projets/Gamma/sessions"
printf 'x\n' > "$V7/02-Projets/Gamma/sessions/2026-09-09 - récupération d'un état.md"
run_block "$V7" >/dev/null
[ -z "$(git -C "$V7" status --porcelain)" ] && ok "fichier accentue commite" || bad "reste sale"
S7=$(git -C "$V7" log --format=%s -1)
case "$S7" in "vault(Gamma): auto-save"*) ok "groupe correctement" ;; *) bad "mauvais groupe" "$S7" ;; esac
# Ne PAS comparer aux octets du nom : macOS stocke les accents en NFD alors que
# ce fichier source les ecrit en NFC, et `ls-tree` les C-quote comme ls-files.
# On verifie la structure — un chemin, sous le bon dossier — et que git relit
# exactement ce que le disque contient.
NP=$(git -C "$V7" ls-tree -r --name-only -z HEAD | tr '\0' '\n' | grep -c '^02-Projets/Gamma/sessions/')
[ "$NP" = "1" ] && ok "chemin accentue intact dans l'arbre" \
  || bad "chemin accentue perdu" "$NP entree(s) sous Gamma/sessions"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
