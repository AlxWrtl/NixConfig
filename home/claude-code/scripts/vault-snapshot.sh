# vault-snapshot — encrypted, off-machine snapshot of the Obsidian vault.
#
# Chain: git bundle --all  ->  age  ->  gh release asset.
#
# Deliberately NOT a git remote. `git remote` inside the vault must stay empty:
# block-main-bash (hooks.nix) enforces the main/master ban only on repos that
# HAVE a remote, and that exemption is why commits to the vault work at all.
# An encrypted carrier also cannot offer the PR route the guard's message
# points at. `bundle` is absent from the guard's RULES table, so this whole
# chain sits outside its jurisdiction by construction rather than by exception.
#
# Carrier design: one release per snapshot, the KEEP most recent kept, older
# ones removed with --cleanup-tag. The carrier repo's git object store never
# grows — its default branch holds exactly one commit forever and release
# assets live outside the object store. A snapshot committed as a file would
# instead add ~3 MB of undeltifiable ciphertext per run, permanently, with no
# way to purge it short of rewriting history and calling GitHub support.

VAULT="/Users/alx/Vaults/AlxVault"
REPO="AlxWrtl/attic"
TARGET="master"
KEY_PUB="$HOME/.config/age/alxvault-backup.pub"
KEEP=3
LOG="$HOME/GraphVault/vault-snapshot.log"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$LOG"; }

# The key must never live inside the vault: it would sit inside the very thing
# it protects, and inside the git repo that gets bundled.
case "$KEY_PUB" in
  "$VAULT"/*) log "FATAL key sits inside the vault: $KEY_PUB"; exit 1 ;;
esac
[ -f "$KEY_PUB" ] || { log "FATAL age recipient missing: $KEY_PUB"; exit 1; }
[ -d "$VAULT/.git" ] || { log "FATAL not a git repo: $VAULT"; exit 1; }
command -v gh >/dev/null 2>&1 || { log "FATAL gh not on PATH"; exit 1; }

# A dirty tree used to be REPORTED and nothing more, on the reasoning that a
# bundle carries committed history only and refusing would mean no backup at
# all. That reasoning was sound but incomplete: reporting the omission does not
# back the notes up. So commit them first, then bundle — the WARN becomes a
# commit, and the snapshot carries everything.
#
# Each save lands on its own `vault/<stamp>` branch, then the base branch is
# fast-forwarded onto it. The branch is therefore a NAMED MARKER, not a
# divergence: the base branch stays the canonical full history, and each
# session leaves a pointer to the state it produced, so recovering "the vault
# as it was before that session" is `git checkout vault/<previous stamp>`.
# `git bundle --all` picks up every branch, so the markers are backed up too.
#
# Stated plainly because it was raised and overruled: a branch adds no
# recoverability that the commit does not already give, and these accumulate
# with nothing to reap them. That is a deliberate choice, not an oversight.
#
# NOTHING here may abort the snapshot. Every git call is guarded and the worst
# case falls back to the old behaviour — report the dirt, back up what is
# committed. An unbacked-up vault is worse than an uncommitted note.
DIRTY=$(git -C "$VAULT" status --porcelain 2>/dev/null || true)
if [ -n "$DIRTY" ]; then
  BASE=$(git -C "$VAULT" branch --show-current 2>/dev/null || true)
  BR="vault/$(date -u +%Y%m%dT%H%M%SZ)"
  COMMITTED=0

  # Detached HEAD has no base to fast-forward, and committing there would
  # strand the commit on no branch at all. Report and move on.
  if [ -z "$BASE" ]; then
    log "WARN vault is on a detached HEAD — no auto-commit, these stay out:"
    printf '%s\n' "$DIRTY" >>"$LOG"
  elif git -C "$VAULT" checkout -q -b "$BR" 2>>"$LOG"; then
    if git -C "$VAULT" add -A 2>>"$LOG" \
       && git -C "$VAULT" commit -q -m "vault: auto-save $BR" 2>>"$LOG"; then
      COMMITTED=1
      log "auto-saved on $BR"
    else
      log "WARN commit failed on $BR"
    fi
    # Always return to the base branch, committed or not: leaving the vault on
    # a session branch would make the NEXT run branch off it and the base
    # would silently stop being the full history.
    if git -C "$VAULT" checkout -q "$BASE" 2>>"$LOG"; then
      if [ "$COMMITTED" = "1" ]; then
        git -C "$VAULT" merge --ff-only -q "$BR" 2>>"$LOG" \
          || log "WARN $BASE could not fast-forward onto $BR — commit lives on the branch only"
      else
        # Nothing was committed, so the branch is an empty duplicate.
        git -C "$VAULT" branch -q -d "$BR" 2>/dev/null || true
      fi
    else
      log "WARN could not return to $BASE — vault left on $BR"
    fi
  else
    log "WARN could not create $BR — no auto-commit, these stay out:"
    printf '%s\n' "$DIRTY" >>"$LOG"
  fi

  # Re-read: whatever the outcome above, name what is STILL not going in.
  DIRTY=$(git -C "$VAULT" status --porcelain 2>/dev/null || true)
  if [ -n "$DIRTY" ]; then
    log "WARN these uncommitted files are NOT in this snapshot:"
    printf '%s\n' "$DIRTY" >>"$LOG"
  fi
fi

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

git -C "$VAULT" bundle create "$W/snapshot.bundle" --all >/dev/null 2>&1 || {
  log "FATAL bundle create failed"; exit 1; }
git -C "$VAULT" bundle verify "$W/snapshot.bundle" >/dev/null 2>&1 || {
  log "FATAL bundle verify failed — refusing to upload a bundle git cannot read"; exit 1; }

age -R "$KEY_PUB" -o "$W/snapshot.age" "$W/snapshot.bundle" || {
  log "FATAL age encryption failed"; exit 1; }
rm -f "$W/snapshot.bundle"   # the plaintext never outlives the encryption

LOCAL_SHA=$(sha256sum "$W/snapshot.age" | cut -d' ' -f1)
[ -n "$LOCAL_SHA" ] || { log "FATAL empty local checksum"; exit 1; }

TAG="snapshot-$(date -u +%Y%m%dT%H%M%SZ)"
gh release create "$TAG" --repo "$REPO" --target "$TARGET" \
   --title "$TAG" --notes "" "$W/snapshot.age#snapshot.age" >>"$LOG" 2>&1 || {
  log "FATAL gh release create failed for $TAG"; exit 1; }

# Proof, not exit 0. Download it back and compare. This project's notes carry
# three separate entries saying parse OK / build OK / exit 0 proved nothing.
mkdir -p "$W/back"
gh release download "$TAG" --repo "$REPO" --pattern snapshot.age --dir "$W/back" >>"$LOG" 2>&1 || {
  log "FATAL could not download back $TAG — snapshot unverified, no rotation"; exit 1; }
REMOTE_SHA=$(sha256sum "$W/back/snapshot.age" | cut -d' ' -f1)

# BOTH must be non-empty. Comparing two empty strings succeeds, and that exact
# bug once reported a verified snapshot when nothing had been uploaded at all.
if [ -z "$REMOTE_SHA" ] || [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
  log "FATAL round-trip mismatch local=$LOCAL_SHA remote=$REMOTE_SHA — no rotation"
  exit 1
fi

# Rotate only AFTER the round trip is proven, never before. And never
# `gh release upload --clobber`: it deletes the existing asset before uploading
# the replacement (cli/cli#8822), so an interruption loses both copies.
#
# Sort on tagName, NOT on createdAt. A release's createdAt is the date of the
# COMMIT it targets, and this carrier holds exactly one commit for ever, so
# every release reports the SAME createdAt. Sorting on that constant yields
# jq's stable order — gh's own newest-first listing — which `reverse` then
# inverts, so `.[KEEP:]` picked the NEWEST release and deleted the snapshot
# just uploaded. Measured 2026-09-09: four releases, all
# createdAt=2026-09-09T08:59:57Z, and the run rotated out the tag it had
# created seconds earlier. In steady state the backup would have stayed frozen
# on its first three generations for ever, without ever raising an error.
# tagName is an ISO-8601 UTC stamp by construction, so lexicographic order is
# chronological order and depends on nothing GitHub decides.
gh release list --repo "$REPO" --limit 100 --json tagName \
   --jq "sort_by(.tagName) | reverse | .[${KEEP}:] | .[].tagName" 2>/dev/null \
| while read -r old; do
    [ -n "$old" ] || continue
    # Belt and braces: whatever any future ordering does, never delete the
    # generation this run just proved.
    if [ "$old" = "$TAG" ]; then
      log "REFUSED to rotate out the tag just created: $TAG"
      continue
    fi
    gh release delete "$old" --repo "$REPO" --cleanup-tag --yes >>"$LOG" 2>&1 || true
    log "rotated out $old"
  done

log "OK $TAG sha=$LOCAL_SHA"
