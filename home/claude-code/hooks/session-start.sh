#!/usr/bin/env bash
# Guard: graceful handling outside git repos
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Not a git repo"
  exit 0
fi
BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
LAST_COMMIT=$(git log --oneline -1 2>/dev/null || echo "no commits")
MODIFIED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
echo "branch: $BRANCH | last: $LAST_COMMIT | modified: $MODIFIED files"
