package main

// Board rules on test.js's cases (the parity check covers the rest by comparing with board.js),
// and the JS string semantics the port relies on.

import (
	"slices"
	"strings"
	"testing"
)

func TestStatusKind(t *testing.T) {
	cases := map[string]string{
		"complete": "done", "**Done**": "done", "✅ ok": "done", "pending": "pending", "in progress": "running",
		"in_progress": "running", "En cours": "running", "skipped": "skipped", "n/a": "skipped", "red": "failed",
		"échoué": "failed", "**failed** (gate)": "failed", "redone": "other", "blocked": "blocked", "bloqué": "blocked",
		"blockedx": "other", "İN PROGRESS": "other",
	}
	for in, want := range cases {
		if got := statusKind(in); got != want {
			t.Fatalf("statusKind(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestParseContextShapes(t *testing.T) {
	c := parseContext("# APEX: t\nFlags: -t -pr (mode Standard, défaut)\n", "t")
	if c.Tier == nil || *c.Tier != "Standard" {
		t.Fatal("tier from (mode X)")
	}
	c = parseContext("# APEX: t\nFlags: -t -x  (mode: high-stakes — touches)\n", "t")
	if c.Tier == nil || *c.Tier != "high-stakes" {
		t.Fatal("tier from (mode: X —")
	}
	c = parseContext("# APEX: x\nTier: High-stakes (sandbox allowWrite key) — Files: a — Est-lines: ~8\nBranch: fix/a (trunk: master), clean\n", "d")
	if *c.Tier != "High-stakes" || *c.Branch != "fix/a" || c.Steps != nil {
		t.Fatalf("%+v", c)
	}
	if c := parseContext("no heading\n", "dir"); c.Title != "dir" {
		t.Fatal("title falls back on the dir name")
	}
}

func TestBlockedLine(t *testing.T) {
	for _, line := range []string{"BLOCKED: waiting for the user", "**Status:** BLOCKED (needs key)", "- BLOCKED by the sandbox"} {
		if _, ok := blockedLine([]string{line}); !ok {
			t.Fatalf("%q not blocked", line)
		}
	}
	for _, line := range []string{"Tree clean. Command is SANDBOX-BLOCKED (writes)", "4. Fable only when Codex is BLOCKED", "| x | BLOCKED |"} {
		if _, ok := blockedLine([]string{line}); ok {
			t.Fatalf("%q blocked", line)
		}
	}
	if _, ok := blockedLine([]string{"```", "BLOCKED", "```"}); ok {
		t.Fatal("BLOCKED in a fence")
	}
}

func TestStepColumn(t *testing.T) {
	cases := map[string]string{
		"00-init": "init", "01-analyze": "plan", "01b-obsidian": "plan", "02c-verify": "plan", "03-execute": "execute",
		"05-examine": "validate", "07/08-tests": "validate", "09b-note": "done", "Execute": "execute", "whatever": "",
	}
	for in, want := range cases {
		if got := stepColumn(in); got != want {
			t.Fatalf("stepColumn(%q) = %q, want %q", in, got, want)
		}
	}
	if fileColumn([]string{"00-context.md", "02-plan.md", "04-external-verify.json"}) != "plan" {
		t.Fatal("fileColumn ignores non-md")
	}
}

func TestParseIndex(t *testing.T) {
	html := `<li><a href="01-worktree-env-sync/">x</a></li><li><a href="02-plan.md">x</a></li>` +
		`<li><a href="caf%C3%A9%20run/">x</a></li><li><a href="a%26b.md">x</a></li><li><a href="link/">link@</a></li>`
	want := []IndexEntry{{"01-worktree-env-sync", true}, {"02-plan.md", false}, {"café run", true}, {"a&b.md", false}, {"link", true}}
	if got := parseIndex(html); !slices.Equal(got, want) {
		t.Fatalf("%v", got)
	}
	if got := parseIndex(`<a href="../">up</a><a href="%E0%A4%A">bad</a><a href="/abs">x</a><A HREF="http://x">y</A>`); len(got) != 0 {
		t.Fatalf("%v", got)
	}
}

func TestParseBudget(t *testing.T) {
	b := parseBudget([]string{"01-w.round1", "01-w.round2", "28-snap.grant1", "28-snap.grant2", "28-snap.round1", "noise.txt"})
	if *b["01-w"] != (Budget{2, 0}) || *b["28-snap"] != (Budget{1, 2}) || b["noise.txt"] != nil {
		t.Fatal("budget counts")
	}
}

func TestVerdictFile(t *testing.T) {
	cases := []struct {
		files []string
		want  string
	}{
		{[]string{"04-external-verify.json", "06-external-verify.json"}, "06-external-verify.json"},
		{[]string{"00-context.md", "acs.txt"}, ""},
		{[]string{"external-verify.json.bak", "external-verify.md"}, ""},
		{[]string{"external-verify.json", "external-verify-2.json"}, "external-verify-2.json"},
		{[]string{"04-external-verify-2.json", "04-external-verify.json"}, "04-external-verify-2.json"},
		{[]string{"external-verify.json", "external-verify3.json", "external-verify2.json"}, "external-verify3.json"},
		{[]string{"external-verify-r1.json", "external-verify.json"}, "external-verify-r1.json"},
		{[]string{"external-verify-10.json", "external-verify-9.json"}, "external-verify-10.json"},
		{[]string{"06-external-verify-2.json", "04-external-verify-2.json"}, "06-external-verify-2.json"},
		{[]string{"04-external-verify.json", "external-verify.json"}, "external-verify.json"},
	}
	for _, c := range cases {
		if got := verdictFile(c.files); got != c.want {
			t.Fatalf("verdictFile(%v) = %q, want %q", c.files, got, c.want)
		}
	}
}

func TestParseVerdict(t *testing.T) {
	if v := parseVerdict(`{"verdict":"FAIL","findings":[{},{}]}`); v == nil || v.Findings != 2 {
		t.Fatal("FAIL 2")
	}
	for _, bad := range []string{`{"verdict": "FA`, `{"VERDICT":"PASS"}`, `["PASS"]`, `null`, `{"verdict":"pass"}`, "\xef\xbb\xbf{\"verdict\":\"PASS\"}"} {
		if parseVerdict(bad) != nil {
			t.Fatalf("%q read as a verdict", bad)
		}
	}
}

func TestFileTone(t *testing.T) {
	cases := []struct{ name, text, want string }{
		{"04-validate.md", "\n**Verdict: APPROVED**\nbody", "good"},
		{"05-examine.md", "NEEDS_FIXES\n", "warn"},
		{"x.md", "# BLOCKED by the sandbox", "stop"},
		{"x.md", "Plan\nAPPROVED", ""},
		{"external-verify.json", `{"verdict":"FAIL"}`, "stop"},
		{"external-verify.json", `{"verdict":"PASS","findings":[]}`, "good"},
		{"acs.txt", "AC1", ""},
	}
	for _, c := range cases {
		if got := fileTone(c.name, c.text); got != c.want {
			t.Fatalf("fileTone(%q) = %q, want %q", c.name, got, c.want)
		}
	}
}

func TestSortFiles(t *testing.T) {
	got := sortFiles([]string{"sub/a.md", "acs.txt", "02-plan.md", "00-context.md", "01-analyze.md", "pr.md"})
	if !slices.Equal(got, []string{"00-context.md", "01-analyze.md", "02-plan.md", "acs.txt", "pr.md", "sub/a.md"}) {
		t.Fatalf("%v", got)
	}
}

func TestJSSemantics(t *testing.T) {
	// UTF-16 order: U+FF5E (one unit) sorts after U+1F680 (surrogates D83D…), unlike UTF-8 bytes.
	if !jsLess("\U0001F680", "～") || jsLess("～", "\U0001F680") {
		t.Fatal("UTF-16 order")
	}
	if utf16Slice("ab\U0001F680", 3) != "ab"+wtf8(0xD83D) || utf16Slice("abc", 2) != "ab" {
		t.Fatal("utf16Slice")
	}
	var sb strings.Builder
	jsonString(&sb, "a\"\\\n\x01 "+wtf8(0xD83D))
	if sb.String() != `"a\"\\\n\u0001`+" "+`\ud83d"` {
		t.Fatalf("jsonString %s", sb.String())
	}
	// WHATWG: one U+FFFD per maximal subpart.
	if got := decodeUTF8([]byte("a\xe2\x82b\xed\xa0\x80c\xff")); got != "a�b���c�" {
		t.Fatalf("decodeUTF8 %q", got)
	}
	if jsTrim("\xef\xbb\xbf  x 　") != "x" || jsTrim("\u0085x") != "\u0085x" {
		t.Fatal("jsTrim")
	}
	if jsNumber(1792500000000.123) != "1792500000000.123" || jsNumber(3) != "3" || jsNumber(1e21) != "1e+21" {
		t.Fatal("jsNumber")
	}
}

func TestGroupRunsCap(t *testing.T) {
	var cards []*Card
	for i := range 35 {
		ms := float64(1000 - i)
		cards = append(cards, &Card{ID: "d" + itoaT(i), Column: "done", MtimeMs: &ms})
	}
	g := groupRuns(cards)
	if len(g["done"].Cards) != DoneCap || g["done"].More != 5 || g["done"].Cards[0].ID != "d0" {
		t.Fatal("Terminé cap")
	}
}
