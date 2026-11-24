"""ttw-test-weaken — flags a branch diff that weakens its tests.

  ttw-test-weaken --base REF

Reads the diff from merge-base(REF, HEAD) to the working tree (committed,
staged and unstaged changes alike, `-U0`) plus every untracked, non-ignored
file (all its lines count as added), and reports three patterns:

  assert-removed     a test file loses more assertion lines than it gains
  skip-added         an added test line skips or focuses tests
  threshold-lowered  a coverage threshold goes down, or a max-warnings cap up

Output: one `ttw-test-weaken: <rule> ...` line per finding, then
`ttw-test-weaken: findings=N`. Exit 0 = none, 1 = findings, 2 = error
(bad usage, unknown ref, not a git repo): never read as green.

Advisory, never a gate on its own: agent-roast is a static heuristic of this
kind and its author reports 25-66 % false positives on unknown repos, so TTW
triages every finding (confirmed | dismissed — reason). Offline and read-only: git
diff/merge-base/ls-files/rev-parse only. Stdlib only.
"""

import fnmatch
import itertools
import os
import re
import subprocess
import sys

GIT = "@GIT@"
PREFIX = "ttw-test-weaken:"

TEST_DIRS = frozenset(("test", "tests", "__tests__", "spec"))
TEST_GLOBS = ("*.test.*", "*.spec.*", "test_*.py", "*_test.py", "*_test.go", "*_spec.rb")
THRESHOLD_GLOBS = (
    "jest.config.*", "vitest.config.*", ".nycrc*", ".coveragerc",
    "pyproject.toml", "setup.cfg", "package.json", "codecov.yml",
)

ASSERT_RE = re.compile(r"\bexpect\(|\bassert|\.should\b|\bt\.(?:Error|Fatal|Fail)|\brequire\.\w+\(")
SKIP_RE = re.compile(r"\.skip\(|\.skipIf\(|\bskipTest\(|\.only\(|\.todo\(|\bxit\(|\bxdescribe\(|\bxtest\(|\bfit\(|\bfdescribe\(|@pytest\.mark\.(?:skip|xfail)|\bpytest\.skip\(|\bt\.Skip|@unittest\.skip|@Disabled\b")
MIN_KEY_RE = re.compile(r"\b(threshold|coverage|branches|functions|lines|statements|fail_under|min_coverage)\w*[\"']?\s*[:=]?\s*[\"']?(\d+(?:\.\d+)?)\b")
MAX_KEY_RE = re.compile(r"(max[-_]?[Ww]arnings)[\"']?\s*[:= ]\s*[\"']?(\d+)\b")
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
TEXT_CAP = 200


class GitError(Exception):
    """A git call failed: exit 2."""


def git(*args):
    cmd = [GIT, "-c", "core.fsmonitor=false", "-c", "core.quotePath=false", *args]
    # A missing or unexecutable git is an error (exit 2), not findings (1).
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    except OSError as err:
        raise GitError(f"cannot run {GIT}: {err}") from err
    if proc.returncode != 0:
        raise GitError(f"git {' '.join(args)}: {proc.stderr.strip()}")
    return proc.stdout


def is_test(path):
    *dirs, name = path.split("/")
    if any(part in TEST_DIRS for part in dirs):
        return True
    return any(fnmatch.fnmatch(name, g) for g in TEST_GLOBS)


def is_threshold_file(path):
    name = os.path.basename(path)
    return any(fnmatch.fnmatch(name, g) for g in THRESHOLD_GLOBS)


def is_lowered(old, new):
    return new < old


def is_raised(old, new):
    return new > old


def unquote(path):
    if len(path) >= 2 and path[0] == '"' and path[-1] == '"':
        return path[1:-1]
    return path


def parse_diff(text):
    """Returns {path: {"added": [(line_no, text)], "removed": [text]}}."""
    files = {}
    current = None
    in_header = False
    old_path = None
    new_line = 0
    for line in text.split("\n"):
        if line.startswith("diff --git "):
            in_header = True
            current = None
            old_path = None
            continue
        if in_header:
            # git ends a ---/+++ path holding a space with a TAB; header lines
            # never reach the counters below.
            if line.startswith("--- "):
                old_path = unquote(line[4:].rstrip("\t"))
                if old_path.startswith("a/"):
                    old_path = old_path[2:]
                continue
            if line.startswith("+++ "):
                path = unquote(line[4:].rstrip("\t"))
                if path == "/dev/null":
                    path = old_path
                elif path.startswith("b/"):
                    path = path[2:]
                current = files.setdefault(path, {"added": [], "removed": []})
                continue
            if line.startswith("@@"):
                in_header = False
            else:
                continue
        if line.startswith("@@"):
            match = HUNK_RE.match(line)
            new_line = int(match.group(1)) if match else 0
            continue
        if current is None:
            continue
        if line.startswith("+"):
            current["added"].append((new_line, line[1:]))
            new_line += 1
        elif line.startswith("-"):
            current["removed"].append(line[1:])
    return files


def add_untracked(files):
    listing = git("ls-files", "-z", "--others", "--exclude-standard")
    for path in listing.split("\0"):
        if not path or not (is_test(path) or is_threshold_file(path)):
            continue
        try:
            with open(path, "rb") as handle:
                raw = handle.read()
        except OSError as err:
            raise GitError(f"cannot read {path}: {err}") from err
        if b"\0" in raw:
            continue
        lines = raw.decode("utf-8", errors="replace").splitlines()
        entry = files.setdefault(path, {"added": [], "removed": []})
        entry["added"].extend((i + 1, text) for i, text in enumerate(lines))


def pairs(regex, lines):
    found = {}
    for text in lines:
        for match in regex.finditer(text):
            found.setdefault(match.group(1), []).append(match.group(2))
    return found


def threshold_findings(path, entry):
    added = [text for _, text in entry["added"]]
    out = []
    for regex, weaker in ((MIN_KEY_RE, is_lowered), (MAX_KEY_RE, is_raised)):
        old_by_key = pairs(regex, entry["removed"])
        new_by_key = pairs(regex, added)
        for key in sorted(old_by_key):
            olds, news = old_by_key[key], new_by_key.get(key, [])
            for old, new in itertools.zip_longest(olds, news):
                if old is None:
                    continue
                # A removed key with no added value left the gate unbounded.
                if new is None:
                    out.append(f"{PREFIX} threshold-lowered {path} {key} {old}->none")
                elif weaker(float(old), float(new)):
                    out.append(f"{PREFIX} threshold-lowered {path} {key} {old}->{new}")
    return out


def findings_for(path, entry):
    out = []
    test = is_test(path)
    if test:
        removed = sum(1 for text in entry["removed"] if ASSERT_RE.search(text))
        added = sum(1 for _, text in entry["added"] if ASSERT_RE.search(text))
        if removed > added:
            out.append(f"{PREFIX} assert-removed {path} removed={removed} added={added}")
        for line_no, text in entry["added"]:
            if SKIP_RE.search(text):
                out.append(f"{PREFIX} skip-added {path}:{line_no} {text.strip()[:TEXT_CAP]}")
    if test or is_threshold_file(path):
        out.extend(threshold_findings(path, entry))
    return out


def main(argv):
    if len(argv) != 2 or argv[0] != "--base" or not argv[1]:
        print(f"{PREFIX} usage: ttw-test-weaken --base REF", file=sys.stderr)
        return 2
    try:
        top = git("rev-parse", "--show-toplevel").strip()
        os.chdir(top)
        base = git("rev-parse", "--verify", "--quiet", f"{argv[1]}^{{commit}}").strip()
        merge_base = git("merge-base", base, "HEAD").strip()
        diff = git(
            "diff", "--unified=0", "--no-color", "--no-ext-diff", "--no-textconv", "--no-renames",
            "--src-prefix=a/", "--dst-prefix=b/", merge_base,
        )
        files = parse_diff(diff)
        add_untracked(files)
    except GitError as err:
        print(f"{PREFIX} error: {err}", file=sys.stderr)
        return 2
    lines = []
    for path in sorted(files):
        lines.extend(findings_for(path, files[path]))
    for line in lines:
        print(line)
    print(f"{PREFIX} findings={len(lines)}")
    return 1 if lines else 0


def run(argv):
    # Any unexpected failure is an unrun scan (2), never findings (1).
    try:
        return main(argv)
    except Exception as err:
        print(f"{PREFIX} error: {type(err).__name__}: {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
