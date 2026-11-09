"""Offline tests of fetch.py parsers (run by checks/veille.nix).

Fixtures under fixtures/ have fixed dates; every test passes a fixed `since`,
never the current time.
"""

import calendar
import contextlib
import io
import json
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "fixtures")
sys.path.insert(0, HERE)

_import_out = io.StringIO()
_import_err = io.StringIO()
with contextlib.redirect_stdout(_import_out), contextlib.redirect_stderr(_import_err):
    import fetch  # noqa: E402

# 2026-11-07T00:00:00Z: the fixtures straddle this instant.
SINCE = float(calendar.timegm((2026, 11, 7, 0, 0, 0)))


def fixture(name: str) -> bytes:
    with open(os.path.join(FIXTURES, name), "rb") as fh:
        return fh.read()


def hn_hits() -> list[dict]:
    hits: list[dict] = []
    for name in ("hn-claude-code.json", "hn-coding-agent.json"):
        hits += json.loads(fixture(name))["hits"]
    return hits


def lines_with(lines: list[str], needle: str) -> list[str]:
    return [line for line in lines if needle in line]


class TestImport(unittest.TestCase):
    def test_import_has_no_side_effect(self):
        self.assertEqual(_import_out.getvalue(), "", "import printed to stdout")
        self.assertEqual(_import_err.getvalue(), "", "import printed to stderr")

    def test_parsers_exist(self):
        for name in ("parse_hn", "parse_reddit", "parse_arxiv", "parse_releases"):
            self.assertTrue(callable(getattr(fetch, name, None)), f"fetch.{name} missing")


class TestNoX(unittest.TestCase):
    def test_no_x_names(self):
        bad = [
            n for n in dir(fetch)
            if re.match(r"(?i)^x(_|$)", n) or "tweet" in n.lower() or n.lower().endswith("_x")
        ]
        self.assertEqual(bad, [], "fetch exposes X names")

    def test_no_x_source(self):
        with open(fetch.__file__, encoding="utf-8") as fh:
            src = fh.read()
        for needle in ("api.x.com", "X_BEARER_TOKEN", "tweet"):
            self.assertNotIn(needle, src, f"fetch.py still mentions {needle!r}")
        self.assertIsNone(re.search(r"(?<![\w.-])x\.com\b", src), "fetch.py still targets x.com")

    def test_no_x_source_entry(self):
        sources = getattr(fetch, "SOURCES", [])
        names = [s[0] if isinstance(s, tuple) else s for s in sources]
        self.assertNotIn("X", names)


class TestHN(unittest.TestCase):
    def setUp(self):
        self.lines = fetch.parse_hn(hn_hits())

    def test_hn_dedup_by_object_id(self):
        # 45869954 is returned by both queries: one line only.
        self.assertEqual(len(lines_with(self.lines, "https://github.com/mpaulsen/agent-firewall")), 1)
        self.assertEqual(len(self.lines), 4, self.lines)

    def test_hn_sorted_by_points_desc(self):
        order = [
            "Claude Code now supports background subagents",  # 412
            "Measuring the token cost of agentic coding loops",  # 128
            "Show HN: A hook-based permission firewall for coding agents",  # 57
            "Ask HN: How do you review agent-written diffs?",  # 3
        ]
        got = []
        for line in self.lines:
            match = [t for t in order if t in line]
            self.assertEqual(len(match), 1, f"line matches no known title: {line!r}")
            got.append(match[0])
        self.assertEqual(got, order)

    def test_hn_threshold_3_points(self):
        self.assertEqual(lines_with(self.lines, "Best way to cache prompts"), [], "2-point story kept")
        self.assertEqual(len(lines_with(self.lines, "How do you review agent-written diffs?")), 1,
                         "3-point story dropped")

    def test_hn_link(self):
        line = lines_with(self.lines, "Claude Code now supports background subagents")[0]
        self.assertIn("https://www.anthropic.com/news/claude-code-background-subagents", line)
        ask = lines_with(self.lines, "How do you review agent-written diffs?")[0]
        self.assertIn("https://news.ycombinator.com/item?id=45870777", ask)

    def test_hn_one_line_per_hit(self):
        for line in self.lines:
            self.assertNotIn("\n", line)


class TestReddit(unittest.TestCase):
    def setUp(self):
        self.lines = fetch.parse_reddit(fixture("reddit-top.atom"), SINCE)

    def test_reddit_keeps_recent_with_sub_title_link(self):
        self.assertEqual(len(self.lines), 2, self.lines)
        line = lines_with(self.lines, "Compaction halved my token bill on long sessions")
        self.assertEqual(len(line), 1)
        self.assertIn("r/ClaudeAI", line[0])
        self.assertIn("https://www.reddit.com/r/ClaudeAI/comments/1oqk7zd/compaction_halved_my_token_bill/", line[0])
        hook = lines_with(self.lines, "PreToolUse hooks that saved me from myself")
        self.assertEqual(len(hook), 1)
        self.assertIn("r/ClaudeCode", hook[0])

    def test_reddit_drops_old_entry(self):
        self.assertEqual(lines_with(self.lines, "Stale quantization thread"), [])
        self.assertEqual(lines_with(self.lines, "r/LocalLLaMA"), [])

    def test_reddit_since_is_honoured(self):
        later = float(calendar.timegm((2026, 11, 8, 12, 0, 0)))
        lines = fetch.parse_reddit(fixture("reddit-top.atom"), later)
        self.assertEqual(len(lines), 1, lines)
        self.assertIn("Compaction halved my token bill", lines[0])


class TestArxiv(unittest.TestCase):
    def test_arxiv_full_recent_page_not_finished(self):
        lines, fini = fetch.parse_arxiv(fixture("arxiv-page-recent.atom"), SINCE, page_size=3)
        self.assertFalse(fini, "full page, all in window: the next page must be read")
        self.assertEqual(len(lines), 3, lines)
        self.assertEqual(len(lines_with(lines, "http://arxiv.org/abs/2611.05812v1")), 1)
        # Multi-line Atom title is flattened to one line.
        self.assertEqual(len(lines_with(lines, "Routing Coding Agents by Diff Size: An Empirical Study")), 1)
        for line in lines:
            self.assertNotIn("\n", line)

    def test_arxiv_short_page_finished(self):
        lines, fini = fetch.parse_arxiv(fixture("arxiv-page-recent.atom"), SINCE)
        self.assertTrue(fini, "3 entries < default page_size: nothing left to read")
        self.assertEqual(len(lines), 3, lines)

    def test_arxiv_old_entry_finishes_and_drops_old(self):
        lines, fini = fetch.parse_arxiv(fixture("arxiv-page-cutoff.atom"), SINCE, page_size=4)
        self.assertTrue(fini, "an entry older than since must end the paging")
        self.assertEqual(len(lines), 2, lines)
        self.assertEqual(len(lines_with(lines, "Hook-Level Permission Policies")), 1)
        self.assertEqual(len(lines_with(lines, "Evaluating Subagent Delegation")), 1)
        for old in ("Outdated Survey", "Ancient Benchmark", "2611.04391", "2611.03268"):
            self.assertEqual(lines_with(lines, old), [], f"old entry kept: {old}")


class TestReleases(unittest.TestCase):
    def setUp(self):
        self.rels = json.loads(fixture("releases-claude-code.json"))
        self.out = fetch.parse_releases(self.rels, "anthropics/claude-code", SINCE)

    def test_releases_keeps_recent(self):
        self.assertEqual(len(self.out), 2, self.out)
        text = "\n".join(self.out)
        for tag in ("v2.1.40", "v2.1.39"):
            block = lines_with(self.out, tag)
            self.assertEqual(len(block), 1, f"{tag}: {self.out}")
            self.assertIn("anthropics/claude-code", block[0])
            self.assertIn(f"https://github.com/anthropics/claude-code/releases/tag/{tag}", block[0])
        self.assertIn("Subagents can run in the background", text)

    def test_releases_drops_old(self):
        self.assertEqual(lines_with(self.out, "v2.1.30"), [])
        self.assertEqual(lines_with(self.out, "Old release outside the window"), [])

    def test_releases_since_is_honoured(self):
        later = float(calendar.timegm((2026, 11, 8, 0, 0, 0)))
        out = fetch.parse_releases(self.rels, "anthropics/claude-code", later)
        self.assertEqual(len(out), 1, out)
        self.assertIn("v2.1.40", out[0])


if __name__ == "__main__":
    unittest.main()
