"""Run dryer on the files git lists, never on a raw directory walk.

stdin: `git ls-files -co --exclude-standard -z` from the repo top, so
git-ignored trees (.claude/worktrees/, build output) are never read. The
selection reuses dryer.discover's own rules (language, test files, skipped
directories), plus its language check on the resolved path, since dryer
resolves a file symlink before reading its suffix. The `./` prefix keeps a
`-`-leading name from being read as an option; only existing files are
passed, so none turns into a substring filter.
"""

import os
import sys
from pathlib import Path

import dryer.cli
from dryer.discover import SKIP_DIRS, TEST_DIRS, is_test_file, language_of

NO_CANDIDATES = "No duplicate candidates found."
SKIPPED = SKIP_DIRS | TEST_DIRS


def keep(path):
    if not os.path.isfile(path):
        return False
    if language_of(path) is None or is_test_file(path):
        return False
    if language_of(os.path.realpath(path)) is None:
        return False
    return SKIPPED.isdisjoint(Path(path).parts)


def main():
    listed = [os.fsdecode(entry) for entry in sys.stdin.buffer.read().split(b"\0") if entry]
    kept = sorted({path for path in listed if keep(path)})
    if not kept:
        print(NO_CANDIDATES)
        return 0
    return dryer.cli.run(["./" + path for path in kept])


if __name__ == "__main__":
    sys.exit(main())
