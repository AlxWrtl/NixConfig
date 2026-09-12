#!/usr/bin/env bash
# Real-session probe for the generated Codex skills.
#
# WHY THIS IS NOT IN `nix flake check`: every check below spends a model call
# against the user's OpenAI allocation and needs the network. Same reason
# checks/codex-hooks-probe.sh sits outside the flake. Run it by hand after a
# `darwin-rebuild switch`.
#
# WHAT IT IS FOR, and why the cheap version would not do: a file in the right
# place proves nothing. ~/.agents/skills/ held twelve skill directories for
# four months, every one of them present, correctly named, and four months
# stale — and the failure was invisible until a Codex session quoted a flag
# table that had not existed since May. So the predicates here are answers
# from a REAL session, and the two that decide are AC-8 (does it recite the
# CURRENT flag table) and AC-10 (does it find the vault without asking).
#
# Each predicate is decided by grep on the output of a real command. Never by
# "the answer looks better" — a behavioural runner scored 4/4, 2/4, 3/4, 3/4
# on one identical case in this repo before, because its assertions matched
# free-form prose.
#
# Usage:  checks/codex-skills-probe.sh
# Exit:   0 if every check passed, 1 on the first FAIL (all are still run).

set -uo pipefail

SKILLS_ROOT="$HOME/.agents/skills"
FOSSIL="$HOME/.agents/skills.fossil-2026-09-10"
MODEL="${CODEX_PROBE_MODEL:-gpt-5.6-terra}"
WORK="$(mktemp -d)" || {
  echo "codex-skills-probe: cannot create a work directory. Refusing to run:" >&2
  echo "  without it the redirections below write to / and every predicate" >&2
  echo "  that reads a session answer passes on an absent file." >&2
  exit 2
}
trap 'rm -rf "$WORK"' EXIT

failures=0

# THE TRAP THIS FUNCTION EXISTS FOR. `/usr/bin/grep` is the only grep on this
# machine (BSD 2.6.0; no GNU grep in the system profile, the user profile or
# homebrew), and BSD `grep -R` does NOT descend into a symlinked directory:
#
#   $ /usr/bin/grep -R NEEDLE dir/    # dir/link -> elsewhere/  => exit 1
#   $ /usr/bin/grep -RS NEEDLE dir/                             => found
#
# Every deployed skill is a directory symlink — AC-5 requires exactly that —
# so a plain `grep -R` over the skills root reads ZERO deployed files, and
# every absence check built on it reports PASS on a completely inert tree.
# That is the failure this whole run exists to remove, reproduced inside its
# own harness.
#
# `-S` fixes the blindness. The positive control below fixes the rest: a
# predicate that cannot tell "nothing to find" from "nothing read" is not a
# predicate. Callers assert `read_at_least_one` before trusting an absence.
grep_tree() { /usr/bin/grep -RS "$@"; }

# Sentinel every generated SKILL.md carries, used to prove the walk reached
# real files before any absence is believed.
files_reached() {
  grep_tree -l '^name:' "$SKILLS_ROOT/" 2>/dev/null | grep -c .
}

pass() { printf 'PASS %s — %s\n' "$1" "$2"; }
fail() {
  printf 'FAIL %s — %s\n' "$1" "$2"
  failures=$((failures + 1))
}

# An absence check that runs against nothing passes for the wrong reason.
# Measured on this very script: with the tree not yet deployed, AC-12 ("no
# Claude model name survives") and AC-9 ("no fossil flag in the answer") both
# reported PASS — one because the tree was empty, the other because the file
# holding the session's answer had never been written. Both would have gone on
# reporting PASS after a deployment that produced nothing at all.
#
# So every absence check states what must EXIST for its absence to mean
# something, and says UNRUN when it does not.
unrun() {
  printf 'UNRUN %s — %s\n' "$1" "$2"
  failures=$((failures + 1))
}

# Non-empty regular file, i.e. a session answer worth grepping.
answered() { [ -s "$1" ]; }

# Ask a real Codex session, non-interactively.
#
# `< /dev/null` is load-bearing, not tidiness: it makes the session unable to
# ask a question back. A run that WOULD have asked for the vault path instead
# answers without it, and the predicate sees the absence. With a tty attached,
# a question would look like a hang, not like a failure.
ask() {
  codex exec --skip-git-repo-check --model "$MODEL" "$1" < /dev/null 2>/dev/null
}

# --- AC-5: deployed shape -----------------------------------------------
# The scanner ignores a symlinked SKILL.md (measured: a symlink to the nix
# store AND a symlink to an ordinary file are both invisible; only a regular
# file is read). A symlinked skill DIRECTORY is followed. So the deployed
# shape must be exactly: directory symlink, regular file inside.
if [ "$(stat -f '%HT' "$SKILLS_ROOT/apex" 2>/dev/null)" = "Symbolic Link" ]; then
  pass AC-5a "apex is a directory symlink"
else
  fail AC-5a "apex is not a directory symlink — home.file used .text, output is inert"
fi

# Guarded on AC-5a: an unmanaged tree is full of regular files too, so this
# would pass on the fossil and mean nothing.
if [ ! -L "$SKILLS_ROOT/apex" ]; then
  unrun AC-5b "the tree is not the managed one — a regular file here proves nothing"
elif [ "$(stat -f '%HT' "$SKILLS_ROOT/apex/SKILL.md" 2>/dev/null)" = "Regular File" ]; then
  pass AC-5b "apex/SKILL.md is a regular file inside the store"
else
  fail AC-5b "apex/SKILL.md is not a regular file — the scanner will skip it"
fi

# --- AC-6: the stale table is in the backup, not in the live tree --------
if grep -q '| -a | -A |' "$FOSSIL/apex/SKILL.md" 2>/dev/null; then
  pass AC-6a "the May flag table is preserved in the backup"
else
  fail AC-6a "the backup does not hold the May flag table — was it moved?"
fi

reached=$(files_reached)
if [ "$reached" -lt 14 ]; then
  unrun AC-6b "the walk reached only $reached skill files (expected >= 14) — an absence here would mean nothing"
elif grep_tree -qE '\| -a \| -A \|' "$SKILLS_ROOT/" 2>/dev/null; then
  fail AC-6b "the stale flag table is still inside the scanned root"
else
  pass AC-6b "no stale flag table under the scanned root ($reached files read)"
fi

# --- AC-17: nothing home-manager backed up inside the scanned root ------
# A <name>.backup directory here is loaded by Codex under the name its
# frontmatter declares, which puts the stale skill back under the live name.
if ls -a "$SKILLS_ROOT/" 2>/dev/null | grep -qE '\.backup$'; then
  fail AC-17 "a .backup directory sits inside the scanned root"
else
  pass AC-17 "no .backup directory inside the scanned root"
fi

# --- AC-12: no Claude model identifier survives the translation ---------
# Guarded: an empty or unmanaged tree would satisfy the absence for free.
reached=$(files_reached)
if [ ! -L "$SKILLS_ROOT/apex" ]; then
  unrun AC-12 "the tree is not the managed one — absence of model names proves nothing"
elif [ "$reached" -lt 14 ]; then
  unrun AC-12 "the walk reached only $reached skill files (expected >= 14) — absence proves nothing"
elif grep_tree -E '(^|[^A-Za-z])(Fable|fable|haiku|sonnet|opus)([^A-Za-z]|$)' \
  "$SKILLS_ROOT/" > "$WORK/models.txt" 2>/dev/null; then
  fail AC-12 "Claude model names survive in the deployed tree: $(wc -l < "$WORK/models.txt" | tr -d ' ') lines"
  head -3 "$WORK/models.txt" | sed 's/^/       /'
else
  pass AC-12 "no Claude model identifier in the deployed tree ($reached files read)"
fi

# --- AC-13: the anti-recursion clause survived verbatim -----------------
# The external-verify pass on the Claude side runs `codex exec`. Without this
# clause in the description, a verification pass could start an APEX run
# inside itself.
if grep -q 'Not for pure questions or research with zero file modification' \
  "$SKILLS_ROOT/apex/SKILL.md" 2>/dev/null; then
  pass AC-13 "the anti-recursion clause is present"
else
  fail AC-13 "the anti-recursion clause was lost in translation"
fi

# --- AC-14a: trello frontmatter parses ----------------------------------
if [ "$(head -c 4 "$SKILLS_ROOT/trello/SKILL.md" 2>/dev/null)" = "---" ]; then
  pass AC-14a "trello frontmatter starts at column 0"
else
  fail AC-14a "trello frontmatter is still indented — dedent did not run"
fi

# --- AC-8 / AC-9: a real session recites the CURRENT flag table ---------
echo "… asking a real Codex session for the apex flag table (this costs a call)"
ask 'Read your apex skill and print its Available Flags table verbatim as markdown. Table only, no commentary.' \
  > "$WORK/ac8.txt"

if ! answered "$WORK/ac8.txt"; then
  unrun AC-8 "the session returned nothing — no answer to judge"
  unrun AC-9 "the session returned nothing — absence of fossil flags proves nothing"
else
  missing=""
  for flag in '| -q |' '| -f |' '| -2 |' '| -p |'; do
    grep -qF "$flag" "$WORK/ac8.txt" || missing="$missing $flag"
  done
  if [ -z "$missing" ]; then
    pass AC-8 "the session recites the current flags (-q -f -2 -p)"
  else
    fail AC-8 "current flags missing from the session's answer:$missing"
  fi

  if grep -qE '\| -a \| -A \||\| -s \| -S \||\| -m \| -M \||Economy|Agent Teams' "$WORK/ac8.txt"; then
    fail AC-9 "the session recited flags from the May fossil"
  else
    pass AC-9 "no fossil flag in the session's answer"
  fi
fi

# --- AC-10: a real session knows where the vault is ---------------------
echo "… asking a real Codex session for the vault path"
ask 'Absolute path of the Obsidian vault on this machine. Path only, one line.' \
  > "$WORK/ac10.txt"

if ! answered "$WORK/ac10.txt"; then
  unrun AC-10a "the session returned nothing"
  unrun AC-10b "the session returned nothing — absence of the fossil path proves nothing"
else
  if grep -q '/Users/alx/Vaults/AlxVault' "$WORK/ac10.txt"; then
    pass AC-10a "the session gives the real vault path without asking"
  else
    fail AC-10a "the session did not give /Users/alx/Vaults/AlxVault"
    # A failing predicate that hides the answer sends the reader to the wrong
    # place. This one is model output, so it varies; show it.
    echo "       it said:"
    sed 's/^/         /' "$WORK/ac10.txt" | head -6
  fi

  if grep -q 'Documents/AlxVault' "$WORK/ac10.txt"; then
    fail AC-10b "the session gave the fossil vault path"
  else
    pass AC-10b "no fossil vault path in the answer"
  fi
fi

# --- AC-11: no duplicate name, inventory complete -----------------------
# The names this repo installs, read from the deployed tree rather than typed
# here — a hand-kept list next to a generated one is the very defect this run
# exists to remove.
ls -1 "$SKILLS_ROOT" 2>/dev/null | LC_ALL=C sort > "$WORK/ours.txt"

echo "… asking a real Codex session to list its skills"
# The `sed` is not cosmetic. The session answers in markdown and ends lines
# with two trailing spaces — a markdown line break — so an anchored `$` match
# silently drops whichever names happened to be formatted that way. Measured
# after the first real deployment: three of the fourteen went missing from this
# predicate while a direct question confirmed all fourteen were loaded. The
# predicate was failing, not the deployment, which is the worse of the two
# because it points the investigation at the wrong place.
ask 'Print the name of every skill available to you, one lowercase name per line, nothing else.' \
  | sed 's/[[:space:]]*$//' \
  | grep -oE '^[a-z][a-z0-9-]*$' | LC_ALL=C sort > "$WORK/ac11.txt"

if ! answered "$WORK/ours.txt"; then
  unrun AC-11a "the skills root is empty — nothing to compare against"
  unrun AC-11b "the skills root is empty — nothing to compare against"
elif ! answered "$WORK/ac11.txt"; then
  unrun AC-11a "the session listed nothing — absence of duplicates proves nothing"
  unrun AC-11b "the session listed nothing"
else
  # Scoped to OUR names on purpose. Codex also carries bundled and plugin
  # skills, and a plugin exposing two entries under one prefix makes the model
  # print the same bare word twice (measured: `spreadsheets`). That is not the
  # collision this run is about, and counting it would make the check red for
  # a reason nothing here can fix.
  dupes="$(grep -xF -f "$WORK/ours.txt" "$WORK/ac11.txt" | uniq -d)"
  if [ -z "$dupes" ]; then
    pass AC-11a "no skill of this repo appears twice"
  else
    fail AC-11a "duplicated repo skills: $(echo "$dupes" | tr '\n' ' ')"
  fi

fi

# --- AC-11b: completeness, asked as a CLOSED question -------------------
# Two predicates were tried here and both measured the wrong thing.
#
#   `>= 14 names`  — decided nothing. Codex carries six bundled skills plus
#                    plugin entries, so an unloaded tree clears fourteen.
#   open list      — flaky. Asked to enumerate ~26 items, the session drops
#                    one or two: measured three missing on one run, one on
#                    another, while a direct question confirmed all fourteen
#                    were loaded. The predicate was measuring the model's
#                    appetite for exhaustive enumeration, not the deployment,
#                    and it pointed the investigation at the wrong place twice.
#
# A closed question removes the enumeration entirely: the names come from the
# deployed tree, the session only answers PRESENT or ABSENT for each. The list
# is still not hand-kept — `ls` of the root builds it.
if ! answered "$WORK/ours.txt"; then
  unrun AC-11b "the skills root is empty — nothing to ask about"
else
  names="$(tr '\n' ' ' < "$WORK/ours.txt")"
  echo "… asking a real Codex session about each installed skill by name"
  ask "Without running any command and without reading any file: for EACH of these names, answer on its own line \`<name>: PRESENT\` or \`<name>: ABSENT\` according to whether it is in your list of skills. $names" \
    | sed 's/[[:space:]]*$//' > "$WORK/ac11b.txt"

  absent=""
  unanswered=""
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    case "$(grep -m1 "^\`\{0,1\}$n\`\{0,1\}:" "$WORK/ac11b.txt" 2>/dev/null)" in
      *PRESENT*) : ;;
      *ABSENT*) absent="$absent $n" ;;
      *) unanswered="$unanswered $n" ;;
    esac
  done < "$WORK/ours.txt"

  if [ -n "$unanswered" ]; then
    unrun AC-11b "the session did not answer for:$unanswered"
  elif [ -n "$absent" ]; then
    fail AC-11b "installed but not loaded by the session:$absent"
  else
    pass AC-11b "every skill this repo installs answers PRESENT"
  fi
fi

# --- AC-14b: the session can quote the repaired trello description ------
echo "… asking a real Codex session for the trello description"
if ask 'Print verbatim the description of your trello skill, one line, nothing else.' \
  | grep -q 'Pilot Trello'; then
  pass AC-14b "the session quotes the trello description"
else
  fail AC-14b "the session cannot quote the trello description"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "codex-skills-probe: all checks passed"
  exit 0
fi
echo "codex-skills-probe: $failures check(s) failed or could not be run"
echo "  UNRUN is counted as a failure on purpose: a check that did not run is"
echo "  not a check that passed."
exit 1
