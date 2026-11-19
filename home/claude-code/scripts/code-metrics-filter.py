"""Filters between Uncle Bob's metric tools and the code-metrics wrapper.

  dup --changed FILE      dryer text report on stdin; keep the pairs that
                          touch a changed file, drop those with a ui side
  sources --changed FILE  changed paths that are existing, non-test, non-ui
                          source files, in list order
  lines                   `git diff -U0` on stdin; prints `path<TAB>n,n,...`
                          of the added or modified lines of each file

Exit codes: 0 clean, 1 kept duplicates (dup only), 2 bad usage or input.
Stdlib only: the wrapper calls it on every run.
"""

import os
import re
import sys

UI_SEGMENT = "/components/ui/"

NO_CANDIDATES = "No duplicate candidates found."
SOURCE_EXTENSIONS = frozenset(
    (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".py", ".go", ".rs", ".java", ".clj")
)
TEST_DIRS = frozenset(("test", "tests", "spec", "__tests__"))
SCORE_LINE = re.compile(r"DUPLICATE score=\d+\.\d\d")
SPAN_LINE = re.compile(r"  (.+):\d+-\d+")
HUNK_HEADER = re.compile(r"@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


class UsageError(Exception):
    """Bad arguments or malformed input: exit 2, nothing on stdout."""


def is_ui(path):
    return UI_SEGMENT in "/" + path


def is_test(path):
    *dirs, name = path.split("/")
    if ".test." in name or ".spec." in name:
        return True
    return any(part in TEST_DIRS for part in dirs)


def read_changed(args):
    if len(args) != 2 or args[0] != "--changed":
        raise UsageError("expected --changed FILE")
    try:
        with open(args[1], encoding="utf-8") as handle:
            text = handle.read()
    except (OSError, UnicodeDecodeError) as err:
        raise UsageError(f"cannot read the changed list: {err}") from None
    return [line for line in text.splitlines() if line]


def parse_block(block):
    """Return the two paths of one dryer block, or raise UsageError."""
    rows = block.split("\n")
    if len(rows) != 3 or not SCORE_LINE.fullmatch(rows[0]):
        raise UsageError(f"malformed dryer block: {block!r}")
    paths = []
    for row in rows[1:]:
        span = SPAN_LINE.fullmatch(row)
        if span is None:
            raise UsageError(f"malformed dryer span: {row!r}")
        paths.append(span.group(1))
    return paths


def run_dup(args):
    changed = set(read_changed(args))
    report = sys.stdin.read().rstrip("\n")
    if not report:
        raise UsageError("empty dryer report")
    if report == NO_CANDIDATES:
        blocks = []
    else:
        blocks = report.split("\n\n")
    parsed = [(block, parse_block(block)) for block in blocks]
    kept = []
    dropped_ui = 0
    for block, paths in parsed:
        if not any(path in changed for path in paths):
            continue
        if any(is_ui(path) for path in paths):
            dropped_ui += 1
        else:
            kept.append(block)
    count = f"code-metrics dup: kept={len(kept)} dropped_ui={dropped_ui} total={len(blocks)}"
    sys.stdout.write("\n\n".join(kept + [count]) + "\n")
    return 1 if kept else 0


def is_source(path):
    if os.path.splitext(path)[1] not in SOURCE_EXTENSIONS:
        return False
    if is_test(path) or is_ui(path):
        return False
    return os.path.isfile(path)


def run_sources(args):
    for path in read_changed(args):
        if is_source(path):
            sys.stdout.write(path + "\n")
    return 0


def changed_lines(diff_rows):
    """Map each file of a -U0 diff to the new-side line numbers it adds."""
    found = {}
    current = None
    old_left = new_left = 0
    for row in diff_rows:
        if old_left or new_left:
            if row.startswith("-"):
                old_left -= 1
            elif row.startswith("+"):
                new_left -= 1
            elif not row.startswith("\\"):
                raise UsageError(f"unexpected line inside a hunk: {row!r}")
            continue
        if row.startswith("+++ "):
            target = row[4:]
            current = target[2:] if target.startswith("b/") else None
            continue
        header = HUNK_HEADER.match(row)
        if header is None:
            continue
        old_count, start, new_count = header.groups()
        old_left = 1 if old_count is None else int(old_count)
        new_left = 1 if new_count is None else int(new_count)
        if current is not None and new_left:
            first = int(start)
            found.setdefault(current, set()).update(range(first, first + new_left))
    return found


def run_lines(args):
    if args:
        raise UsageError("lines takes no argument (diff on stdin)")
    found = changed_lines(sys.stdin.read().splitlines())
    for path, numbers in found.items():
        sys.stdout.write(path + "\t" + ",".join(str(n) for n in sorted(numbers)) + "\n")
    return 0


COMMANDS = {"dup": run_dup, "sources": run_sources, "lines": run_lines}


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        sys.stderr.write("usage: code-metrics-filter dup|sources --changed FILE | lines\n")
        return 2
    try:
        return COMMANDS[argv[0]](argv[1:])
    except UsageError as err:
        sys.stderr.write(f"code-metrics-filter {argv[0]}: {err}\n")
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
