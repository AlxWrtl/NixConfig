package main

// Port of tui-test.js (fixture runs built in a temp dir: a live run with a failed step, a
// shipped run, a stale one, a correction round, an external verdict, links escaping the runs
// dir), plus the wheel, the poll and the Bubble Tea key / mouse messages.

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

const hourMs = 60 * 60 * 1000

func ctxText(title string, rows [][2]string) string {
	var sb strings.Builder
	sb.WriteString("# APEX: " + title + "\nTier: Standard\nBranch: feat/" + title + "\n\n## Progress\n| Step | Status | Notes |\n|------|--------|-------|\n")
	for _, r := range rows {
		sb.WriteString("| " + r[0] + " | " + r[1] + " | |\n")
	}
	return sb.String()
}

var (
	liveCtx  = ctxText("live", [][2]string{{"00-init", "complete"}, {"04-validate", "failed"}, {"05-examine", "pending"}})
	doneCtx  = ctxText("shipped", [][2]string{{"00-init", "complete"}, {"09-finish", "complete"}})
	staleCtx = ctxText("stale", [][2]string{{"00-init", "complete"}, {"03-execute", "in progress"}})
	passJSON = `{"verdict":"PASS","findings":[]}`
)

type fixture struct {
	root, runs, budget, outside string
	now                         float64
}

func mustDo(t testing.TB, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

func newFixture(t testing.TB) *fixture {
	t.Helper()
	root := t.TempDir()
	f := &fixture{root: root, runs: filepath.Join(root, "runs"), budget: filepath.Join(root, "budget"), outside: filepath.Join(root, "outside"), now: float64(time.Now().UnixMilli())}
	write := func(rel, text string, ageMs float64) {
		p := filepath.Join(f.runs, rel)
		mustDo(t, os.MkdirAll(filepath.Dir(p), 0o755))
		mustDo(t, os.WriteFile(p, []byte(text), 0o644))
		at := time.UnixMilli(int64(f.now - ageMs))
		mustDo(t, os.Chtimes(p, at, at))
	}
	write("live-failed/00-context.md", liveCtx, 0)
	write("live-failed/04-validate.md", "PASS\n\n# Validate\n\nAll **green**.\n", 0)
	write("live-failed/sub/notes.md", "# Notes\n", 0)
	write("done-pr/00-context.md", doneCtx, 8*hourMs)
	write("done-pr/pr.md", "# PR\n", 8*hourMs)
	write("done-pr/external-verify.json", passJSON, 8*hourMs)
	write("stale/00-context.md", staleCtx, 7*hourMs)
	mustDo(t, os.MkdirAll(f.budget, 0o755))
	mustDo(t, os.WriteFile(filepath.Join(f.budget, "live-failed.round1"), nil, 0o644))
	mustDo(t, os.MkdirAll(filepath.Join(f.outside, "dir"), 0o755))
	mustDo(t, os.WriteFile(filepath.Join(f.outside, "secret.md"), []byte("TOP SECRET\n"), 0o644))
	mustDo(t, os.WriteFile(filepath.Join(f.outside, "dir", "inner.md"), []byte("INNER SECRET\n"), 0o644))
	mustDo(t, os.Symlink(filepath.Join(f.outside, "secret.md"), filepath.Join(f.runs, "live-failed", "escape.md")))
	mustDo(t, os.Symlink(filepath.Join(f.outside, "dir"), filepath.Join(f.runs, "live-failed", "escape-dir")))
	// A run dir that is itself a link out of the runs dir: never a run.
	mustDo(t, os.Symlink(f.outside, filepath.Join(f.runs, "linked-run")))
	return f
}

func (f *fixture) inputs(t testing.TB) []*RunInput {
	t.Helper()
	runs, problems, err := readRuns(f.runs, f.budget)
	mustDo(t, err)
	if len(problems) > 0 {
		t.Fatalf("problems: %v", problems)
	}
	return runs
}

func (f *fixture) model(t testing.TB, w, h int) *Model {
	m := newModel(f.runs, f.budget, "fixture", w, h)
	m.setRuns(f.inputs(t), f.now)
	m.status = &boardStatus{ok: true, count: len(m.runs), time: "12:00:00"}
	return m
}

func plain(frame string) []string {
	lines := strings.Split(frame, "\n")
	for i, l := range lines {
		lines[i] = stripAnsi(l)
	}
	return lines
}

func byID(runs []*RunInput) map[string]*RunInput {
	out := map[string]*RunInput{}
	for _, r := range runs {
		out[r.ID] = r
	}
	return out
}

// ---- disk ----------------------------------------------------------------------

func TestReadRuns(t *testing.T) {
	f := newFixture(t)
	runs := f.inputs(t)
	ids := []string{}
	for _, r := range runs {
		ids = append(ids, r.ID)
	}
	if !slices.Equal(ids, []string{"done-pr", "live-failed", "stale"}) {
		t.Fatalf("ids %v", ids)
	}
	live := byID(runs)["live-failed"]
	if live.Context == nil || *live.Context != liveCtx {
		t.Fatal("live context not read")
	}
	if !slices.Equal(live.Files, []string{"00-context.md", "04-validate.md", "escape-dir", "escape.md"}) {
		t.Fatalf("files %v", live.Files)
	}
	if live.Budget == nil || *live.Budget != (Budget{Rounds: 1}) {
		t.Fatalf("budget %v", live.Budget)
	}
	if live.Verdict != nil || live.MtimeMs == nil || *live.MtimeMs-f.now > 5000 || f.now-*live.MtimeMs > 5000 {
		t.Fatal("live verdict / mtime")
	}
	done := byID(runs)["done-pr"]
	if done.Verdict == nil || *done.Verdict != passJSON || done.Budget != nil {
		t.Fatal("done-pr verdict / budget")
	}
	if d := *done.MtimeMs - (f.now - 8*hourMs); d > 5000 || d < -5000 {
		t.Fatalf("done-pr mtime off by %v", d)
	}
}

func TestReadRunsMissingBudget(t *testing.T) {
	f := newFixture(t)
	runs, problems, err := readRuns(f.runs, filepath.Join(f.root, "no-budget"))
	mustDo(t, err)
	if len(problems) != 0 || byID(runs)["live-failed"].Budget != nil {
		t.Fatalf("problems %v", problems)
	}
}

func TestBoardIntegration(t *testing.T) {
	f := newFixture(t)
	cards := map[string]*Card{}
	for _, r := range f.inputs(t) {
		cards[r.ID] = deriveRun(r, f.now)
	}
	if c := cards["live-failed"]; c.Column != "human" || !slices.Equal(c.Reasons, []string{"étape 04-validate en échec"}) {
		t.Fatalf("live-failed %+v", c)
	}
	if c := cards["done-pr"]; c.Column != "done" || c.Flag != nil {
		t.Fatalf("done-pr %+v", c)
	}
	if c := cards["stale"]; c.Column != "done" || c.Flag == nil || *c.Flag != "inactif" {
		t.Fatalf("stale %+v", c)
	}
}

func TestListRunFiles(t *testing.T) {
	f := newFixture(t)
	files, err := listRunFiles(filepath.Join(f.runs, "live-failed"))
	mustDo(t, err)
	for _, want := range []string{"sub/notes.md", "escape-dir", "escape.md"} {
		if !slices.Contains(files, want) {
			t.Fatalf("%s missing from %v", want, files)
		}
	}
	for _, p := range files {
		if strings.HasPrefix(p, "escape-dir/") {
			t.Fatalf("symlinked dir descended: %v", files)
		}
	}
}

func TestListRunFilesCaps(t *testing.T) {
	dir := t.TempDir()
	for i := range maxFiles + 50 {
		mustDo(t, os.WriteFile(filepath.Join(dir, "f"+strings.Repeat("0", 5-len(itoaT(i)))+itoaT(i)), nil, 0o644))
	}
	deep := filepath.Join(dir, "a", "b", "c", "d", "e", "f", "g", "h", "i")
	mustDo(t, os.MkdirAll(deep, 0o755))
	files, err := listRunFiles(dir)
	mustDo(t, err)
	if len(files) != maxFiles {
		t.Fatalf("%d files listed, want the %d cap", len(files), maxFiles)
	}
}

func itoaT(i int) string { return strconv.Itoa(i) }

func TestReadRunFileOutside(t *testing.T) {
	f := newFixture(t)
	in, err := readRunFile(f.runs, "live-failed", "04-validate.md")
	mustDo(t, err)
	if in.Kind != "text" || !strings.HasPrefix(in.Text, "PASS") {
		t.Fatalf("inside %+v", in)
	}
	for _, rel := range []string{"escape.md", "escape-dir", "escape-dir/inner.md", "../stale/00-context.md", "sub/../../stale/00-context.md", "/etc/hosts"} {
		r, err := readRunFile(f.runs, "live-failed", rel)
		mustDo(t, err)
		if r.Kind != "outside" || r.Text != outsideText {
			t.Fatalf("%s read as %+v", rel, r)
		}
	}
	if r, _ := readRunFile(f.runs, "..", "outside/secret.md"); r.Kind != "outside" {
		t.Fatal(".. id read")
	}
	if r, _ := readRunFile(f.runs, "live-failed", "nope.md"); r.Kind != "missing" {
		t.Fatal("missing file")
	}
}

func TestReadCappedBinaryAndTruncation(t *testing.T) {
	dir := t.TempDir()
	big := filepath.Join(dir, "big.md")
	mustDo(t, os.WriteFile(big, []byte(strings.Repeat("a", maxBytes+4096)), 0o644))
	r, err := readCapped(big)
	mustDo(t, err)
	if r.Text != strings.Repeat("a", maxBytes)+"\n\n… tronqué : 516 Ko, 512 Ko affichés\n" {
		t.Fatalf("truncation tail %q", r.Text[maxBytes:])
	}
	bin := filepath.Join(dir, "bin.md")
	mustDo(t, os.WriteFile(bin, []byte("a\x00b"), 0o644))
	if r, _ := readCapped(bin); r.Kind != "binary" {
		t.Fatalf("binary read as %s", r.Kind)
	}
	if r, _ := readCapped(dir); r.Kind != "error" {
		t.Fatalf("dir read as %s", r.Kind)
	}
}

func TestReaderIncremental(t *testing.T) {
	f := newFixture(t)
	r := &Reader{RunsDir: f.runs, BudgetDir: f.budget}
	first, _, err := r.Read()
	mustDo(t, err)
	second, _, err := r.Read()
	mustDo(t, err)
	a, b := byID(first)["live-failed"], byID(second)["live-failed"]
	if a.parsed == nil || a.parsed != b.parsed {
		t.Fatal("unchanged run parsed again")
	}
	p := filepath.Join(f.runs, "live-failed", "00-context.md")
	mustDo(t, os.WriteFile(p, []byte(strings.Replace(liveCtx, "failed", "complete", 1)), 0o644))
	third, _, err := r.Read()
	mustDo(t, err)
	c := byID(third)["live-failed"]
	if c.parsed == b.parsed || deriveRun(c, f.now).Column == "human" {
		t.Fatal("changed 00-context.md not read again")
	}
	if byID(third)["stale"].parsed != byID(second)["stale"].parsed {
		t.Fatal("another run parsed again")
	}
}

// ---- board ---------------------------------------------------------------------

func TestRenderBoard180x50(t *testing.T) {
	f := newFixture(t)
	m := f.model(t, 180, 50)
	frame := m.View().Content
	lines := strings.Split(frame, "\n")
	if len(lines) != 50 {
		t.Fatalf("%d lines", len(lines))
	}
	for y, l := range lines {
		if w := visibleWidth(l); w != 180 {
			t.Fatalf("line %d width %d", y, w)
		}
		if w := lipgloss.Width(l); w != 180 {
			t.Fatalf("line %d lipgloss width %d", y, w)
		}
	}
	text := plain(frame)
	var head string
	for _, l := range text {
		if strings.Contains(l, "Init") && strings.Contains(l, "Validate") {
			head = l
			break
		}
	}
	last := -1
	for _, c := range Columns {
		at := strings.Index(head, c.Label)
		if at <= last {
			t.Fatalf("labels out of order in %q", head)
		}
		last = at
	}
	all := strings.Join(text, "\n")
	for _, want := range []string{"live-failed", "done-pr", "stale", "À TOI", "INACTIF", "étape 04-validate", "APEX board · fixture", "/apex -x <tâche>", "╭", "╯"} {
		if !strings.Contains(all, want) {
			t.Fatalf("%q not drawn", want)
		}
	}
	if !strings.Contains(frame, "38;2;255;121;198") {
		t.Fatal("no human truecolor")
	}
}

func TestRenderNarrow(t *testing.T) {
	f := newFixture(t)
	for _, wh := range [][2]int{{60, 30}, {23, 12}, {10, 5}, {1, 1}} {
		m := f.model(t, wh[0], wh[1])
		lines := strings.Split(m.View().Content, "\n")
		if len(lines) != wh[1] {
			t.Fatalf("%v: %d lines", wh, len(lines))
		}
		for y, l := range lines {
			if visibleWidth(l) != wh[0] {
				t.Fatalf("%v line %d width %d", wh, y, visibleWidth(l))
			}
		}
	}
}

func TestDoneCap(t *testing.T) {
	now := float64(time.Now().UnixMilli())
	var runs []*RunInput
	for k := range 35 {
		ms := now - float64(8+k)*hourMs
		id := "run-" + string(rune('0'+k/10)) + string(rune('0'+k%10))
		runs = append(runs, &RunInput{ID: id, Context: strp(doneCtx), MtimeMs: &ms, Files: []string{"00-context.md", "pr.md"}})
	}
	m := newModel("", "", "", 180, 400)
	m.setRuns(runs, now)
	text := strings.Join(plain(m.View().Content), "\n")
	for k := range 35 {
		id := "run-" + string(rune('0'+k/10)) + string(rune('0'+k%10))
		if strings.Contains(text, id) != (k < 30) {
			t.Fatalf("%s shown=%v", id, k < 30)
		}
	}
	if !regexp.MustCompile(`\+5\b`).MatchString(text) {
		t.Fatal("no +5")
	}
}

func TestTickPulsesLiveDot(t *testing.T) {
	f := newFixture(t)
	m := f.model(t, 180, 50)
	on := m.View().Content
	send(m, tickMsg{})
	off := m.View().Content
	lit, dim := "38;2;139;233;253", "38;2;91;96;117"
	if on == off || !strings.Contains(on, lit) {
		t.Fatal("the tick did not change the live dot")
	}
	// live-failed's dot, on the card bg (#20222c), right before its id.
	before := func(frame string) string {
		at := strings.Index(frame, "mlive-failed")
		return frame[max(0, at-140):at]
	}
	dot := func(c string) string { return c + ";48;2;32;34;44m●" }
	if b, a := before(on), before(off); !strings.Contains(b, dot(lit)) || !strings.Contains(a, dot(dim)) || strings.Contains(a, dot(lit)) {
		t.Fatalf("dot colors per tick: lit %q, dim %q", b, a)
	}
}

func TestDoneCardHasNoLiveDot(t *testing.T) {
	hasDot := func(c *Card) bool {
		for _, row := range cardRows(c, 40, false).rows {
			for _, cl := range row {
				if cl.ch == "●" {
					return true
				}
			}
		}
		return false
	}
	if !hasDot(&Card{ID: "w", Title: "w", Live: true, Column: "execute"}) {
		t.Fatal("a live card at work lost its dot")
	}
	if hasDot(&Card{ID: "d", Title: "d", Live: true, Column: "done"}) {
		t.Fatal("a live Terminé card carries the pulsing dot")
	}
	if (&Card{Live: true, Column: "done"}).pulses() {
		t.Fatal("a live Terminé card pulses")
	}
}

// ---- keys and mouse ---------------------------------------------------------------

func key(code rune) tea.KeyPressMsg { return tea.KeyPressMsg{Code: code} }
func char(c rune) tea.KeyPressMsg   { return tea.KeyPressMsg{Code: c, Text: string(c)} }

func send(m *Model, msg tea.Msg) tea.Cmd {
	_, cmd := m.Update(msg)
	m.View()
	return cmd
}

func selected(m *Model) (int, string) {
	m.View()
	s := m.selection()
	if s.idx < 0 {
		return s.col, ""
	}
	return s.col, m.columnCards(s.col)[s.idx].ID
}

func wantSel(t *testing.T, m *Model, col int, id string) {
	t.Helper()
	if c, i := selected(m); c != col || i != id {
		t.Fatalf("selected (%d, %q), want (%d, %q)", c, i, col, id)
	}
}

func TestKeys(t *testing.T) {
	f := newFixture(t)
	m := f.model(t, 180, 50)
	// Newest first: stale (7 h) above done-pr (8 h) in Terminé, the first non-empty column.
	wantSel(t, m, 4, "stale")
	send(m, key(tea.KeyDown))
	wantSel(t, m, 4, "done-pr")
	send(m, key(tea.KeyDown))
	wantSel(t, m, 4, "done-pr")
	send(m, key(tea.KeyUp))
	wantSel(t, m, 4, "stale")
	send(m, char('j'))
	send(m, key(tea.KeyRight))
	wantSel(t, m, 5, "live-failed")
	send(m, char('l'))
	wantSel(t, m, 5, "live-failed")
	send(m, key(tea.KeyLeft))
	wantSel(t, m, 4, "stale")
	send(m, char('h'))
	wantSel(t, m, 3, "")
	if send(m, key(tea.KeyEnter)); m.drawer != nil {
		t.Fatal("enter in an empty column opened a drawer")
	}
	send(m, key(tea.KeyRight))
	send(m, key(tea.KeyEnd))
	wantSel(t, m, 4, "done-pr")
	send(m, key(tea.KeyHome))
	wantSel(t, m, 4, "stale")
	send(m, key(tea.KeyPgDown))
	wantSel(t, m, 4, "done-pr")
	send(m, key(tea.KeyPgUp))
	wantSel(t, m, 4, "stale")
	send(m, char('j'))
	if cmd := send(m, key(tea.KeyEnter)); cmd == nil || m.drawer == nil || m.drawer.id != "done-pr" {
		t.Fatal("enter did not open done-pr with a read")
	}
	send(m, key(tea.KeyEscape))
	if m.drawer != nil {
		t.Fatal("esc did not close")
	}
	if cmd := send(m, char('q')); cmd == nil || !m.quit {
		t.Fatal("q did not quit")
	}
	m.quit = false
	if cmd := send(m, tea.KeyPressMsg{Code: 'c', Mod: tea.ModCtrl}); cmd == nil || !m.quit {
		t.Fatal("ctrl+c did not quit")
	}
}

func TestKeyNames(t *testing.T) {
	cases := map[string]tea.KeyPressMsg{
		"up": key(tea.KeyUp), "down": key(tea.KeyDown), "left": key(tea.KeyLeft), "right": key(tea.KeyRight),
		"enter": key(tea.KeyEnter), "esc": key(tea.KeyEscape), "tab": key(tea.KeyTab), "pgup": key(tea.KeyPgUp),
		"pgdn": key(tea.KeyPgDown), "home": key(tea.KeyHome), "end": key(tea.KeyEnd), "space": {Code: tea.KeySpace, Text: " "},
		"q": char('q'), "G": {Code: 'g', Text: "G", Mod: tea.ModShift}, "ctrl-c": {Code: 'c', Mod: tea.ModCtrl},
	}
	for want, k := range cases {
		if got := keyName(k); got != want {
			t.Fatalf("%v → %q, want %q", k, got, want)
		}
	}
	if got := keyName(tea.KeyPressMsg{Code: tea.KeyTab, Mod: tea.ModShift}); got != "tab" {
		t.Fatalf("shift+tab → %q", got)
	}
}

// run a read command and feed its message back, as the Bubble Tea loop would.
func runCmd(t *testing.T, m *Model, cmd tea.Cmd) {
	t.Helper()
	if cmd == nil {
		t.Fatal("no command")
	}
	send(m, cmd())
}

func findHit(m *Model, kind hitKind, id string) *hit {
	for i := range m.hits {
		if h := &m.hits[i]; h.kind == kind && (id == "" || h.id == id) {
			return h
		}
	}
	return nil
}

func TestMouseDrawer(t *testing.T) {
	f := newFixture(t)
	m := f.model(t, 180, 50)
	m.View()
	h := findHit(m, hitCard, "live-failed")
	if h == nil {
		t.Fatal("no hit rect for live-failed")
	}
	cmd := send(m, tea.MouseClickMsg{X: h.x + 2, Y: h.y + 1, Button: tea.MouseLeft})
	if m.drawer == nil || m.drawer.id != "live-failed" {
		t.Fatal("click did not open live-failed")
	}
	runCmd(t, m, cmd)
	d := m.drawer
	if d.path != "00-context.md" || !slices.Contains(d.files, "sub/notes.md") || d.tones["04-validate.md"] != "good" {
		t.Fatalf("drawer %+v", d)
	}
	drawn := strings.Join(plain(m.View().Content), "\n")
	if !strings.Contains(drawn, "live-failed · À toi · 05-examine · actif") || !strings.Contains(drawn, "SUB") {
		t.Fatal("drawer head / subdir group")
	}
	runCmd(t, m, send(m, key(tea.KeyDown)))
	if d.path != "04-validate.md" {
		t.Fatalf("down → %s", d.path)
	}
	if !strings.Contains(strings.Join(plain(m.View().Content), "\n"), "All green.") {
		t.Fatal("markdown doc")
	}
	m.View()
	h = nil
	for i := range m.hits {
		if m.hits[i].kind == hitFile && m.hits[i].path == "escape.md" {
			h = &m.hits[i]
		}
	}
	runCmd(t, m, send(m, tea.MouseClickMsg{X: h.x + 1, Y: h.y, Button: tea.MouseLeft}))
	esc := strings.Join(plain(m.View().Content), "\n")
	if !strings.Contains(esc, outsideText) || strings.Contains(esc, "TOP SECRET") {
		t.Fatal("escaping link read or not shown as outside")
	}
	c := findHit(m, hitClose, "")
	send(m, tea.MouseClickMsg{X: c.x + 1, Y: c.y + 1, Button: tea.MouseLeft})
	if m.drawer != nil {
		t.Fatal("× did not close")
	}
}

func TestStaleDrawerReadDropped(t *testing.T) {
	f := newFixture(t)
	m := f.model(t, 180, 50)
	m.View()
	cmd := m.openDrawer(5, 0, "live-failed")
	msg := cmd()
	send(m, key(tea.KeyEscape))
	send(m, msg)
	if m.drawer != nil {
		t.Fatal("a read that came after the close reopened the drawer")
	}
}

// ---- wheel ---------------------------------------------------------------------

// manyRuns: n live runs at the Execute step, newest first by index.
func manyRuns(n int, now float64) []*RunInput {
	runs := make([]*RunInput, n)
	for i := range runs {
		ms := now - float64(i)*1000
		id := "run-" + itoaT(1000+i)
		runs[i] = &RunInput{ID: id, Context: strp(ctxText(id, [][2]string{{"00-init", "complete"}, {"03-execute", "in progress"}})), MtimeMs: &ms, Files: []string{"00-context.md"}}
	}
	return runs
}

func TestWheelScrollsColumnKeepsSelection(t *testing.T) {
	now := float64(time.Now().UnixMilli())
	m := newModel("", "", "", 180, 40)
	m.setRuns(manyRuns(20, now), now)
	m.View()
	wantSel(t, m, 2, "run-1000")
	h := findHit(m, hitCard, "run-1000")
	frame := m.frame
	m.Update(tea.MouseWheelMsg{X: h.x + 1, Y: h.y + 1, Button: tea.MouseWheelDown})
	if m.frame != frame || !m.dirty {
		t.Fatal("the wheel drew to hit-test")
	}
	if m.scroll[2] != wheelLines {
		t.Fatalf("scroll %d after one notch", m.scroll[2])
	}
	m.View()
	if m.scroll[2] != wheelLines {
		t.Fatalf("the frame moved the scroll back to %d", m.scroll[2])
	}
	wantSel(t, m, 2, "run-1000")
	// Down until the first card left the viewport: the selection goes to a card in view.
	for range 4 {
		send(m, tea.MouseWheelMsg{X: h.x + 1, Y: 20, Button: tea.MouseWheelDown})
	}
	s := m.scroll[2]
	if s != 5*wheelLines {
		t.Fatalf("scroll %d after 5 notches", s)
	}
	_, id := selected(m)
	sel := m.selection()
	lay := m.view.cols[2]
	if top := lay.tops[sel.idx]; id == "run-1000" || top+lay.heights[sel.idx] <= s || top >= s+m.view.areaH {
		t.Fatalf("selection %s not in view (scroll %d)", id, s)
	}
	// Up: back to 0, selection stays while visible.
	for range 5 {
		send(m, tea.MouseWheelMsg{X: h.x + 1, Y: 20, Button: tea.MouseWheelUp})
	}
	if m.scroll[2] != 0 {
		t.Fatalf("scroll %d after going back up", m.scroll[2])
	}
	// A key brings the selection back in charge of the scroll.
	send(m, key(tea.KeyDown))
	if !m.follow {
		t.Fatal("a key did not restore follow")
	}
}

func TestWheelOtherColumnAndDrawer(t *testing.T) {
	now := float64(time.Now().UnixMilli())
	m := newModel("", "", "", 180, 40)
	runs := manyRuns(20, now)
	stale := now - 7*hourMs
	runs = append(runs, &RunInput{ID: "old", Context: strp(doneCtx), MtimeMs: &stale, Files: []string{"00-context.md", "pr.md"}})
	m.setRuns(runs, now)
	m.sel = &selState{col: 4, idx: 0, id: "old"}
	m.View()
	col := findHit(m, hitCol, "")
	for i := range m.hits {
		if m.hits[i].kind == hitCol && m.hits[i].col == 2 {
			col = &m.hits[i]
		}
	}
	send(m, tea.MouseWheelMsg{X: col.x + 1, Y: col.y + 5, Button: tea.MouseWheelDown})
	if m.scroll[2] != wheelLines {
		t.Fatalf("column under the pointer scrolled to %d", m.scroll[2])
	}
	wantSel(t, m, 4, "old")

	m.drawer = &drawerState{id: "old", files: []string{"a.md"}, path: "a.md", hasPath: true, focus: "files", tones: map[string]string{}}
	m.drawer.doc = &FileRead{Kind: "text", Text: strings.Repeat("line\n\n", 80)}
	m.dirty = true
	m.View()
	doc := findHit(m, hitDoc, "")
	send(m, tea.MouseWheelMsg{X: doc.x + 2, Y: doc.y + 2, Button: tea.MouseWheelDown})
	if m.drawer.docScroll != wheelLines {
		t.Fatalf("doc scroll %d", m.drawer.docScroll)
	}
}

// ---- poll ----------------------------------------------------------------------

func TestPollOffLoop(t *testing.T) {
	f := newFixture(t)
	m := newModel(f.runs, f.budget, "fixture", 120, 40)
	_, cmd := m.Update(pollTickMsg{})
	if cmd == nil || !m.polling {
		t.Fatal("poll tick started no read")
	}
	if _, again := m.Update(pollTickMsg{}); again != nil {
		t.Fatal("a second poll started while one runs")
	}
	msg := cmd()
	pm, ok := msg.(pollMsg)
	if !ok || pm.err != nil || len(pm.cards) != 3 {
		t.Fatalf("poll result %+v", msg)
	}
	_, next := m.Update(msg)
	if m.polling || next == nil || m.status == nil || !m.status.ok || m.status.count != 3 || len(m.groups["human"].Cards) != 1 {
		t.Fatal("poll result not applied")
	}
}

func TestPollUnreadableRunsDir(t *testing.T) {
	m := newModel(filepath.Join(t.TempDir(), "gone"), "", "", 120, 40)
	_, cmd := m.Update(pollTickMsg{})
	m.Update(cmd())
	if m.status == nil || m.status.ok || m.status.err == "" {
		t.Fatal("unreadable runs dir not shown")
	}
	if !strings.Contains(strings.Join(plain(m.View().Content), "\n"), "●") {
		t.Fatal("status dot missing")
	}
}

// ---- markdown ------------------------------------------------------------------

func TestRenderMarkdown(t *testing.T) {
	md := "PASS — all good\n\n# Title\n\nSome **bold** and `code` and [a link](https://x.y).\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n- [x] done\n- [ ] todo\n1. one\n\n> quoted\n\n```\ncode line\n```\n"
	lines := renderMarkdown(md, 40)
	text := make([]string, len(lines))
	for i, l := range lines {
		text[i] = stripAnsi(l)
		if visibleWidth(l) > 40 {
			t.Fatalf("wider than 40: %q", text[i])
		}
	}
	if !strings.Contains(text[0], "PASS — all good") || !strings.Contains(lines[0], "38;2;80;250;123") {
		t.Fatal("verdict badge")
	}
	i := slices.Index(text, "Title")
	if i < 0 || !strings.Contains(lines[i], ";1m") {
		t.Fatal("heading not bold")
	}
	has := func(pred func(string) bool) bool { return slices.ContainsFunc(text, pred) }
	if !has(func(l string) bool { return strings.HasPrefix(l, "┌") }) || !has(func(l string) bool { return strings.HasPrefix(l, "└") }) {
		t.Fatal("table box")
	}
	// `1. one` continues the `-` list, so it takes its bullet (as tui.js and the page do).
	for _, want := range []string{"☑ done", "☐ todo", "code line", "• one", "a link"} {
		if !has(func(l string) bool { return strings.Contains(l, want) }) {
			t.Fatalf("%q missing", want)
		}
	}
	if !has(func(l string) bool { return strings.HasPrefix(l, "│ quoted") }) {
		t.Fatal("quote")
	}
	if !has(func(l string) bool { return strings.Contains(l, "Some bold and code and a link.") }) {
		t.Fatalf("inline styles: %q", text)
	}
	for _, l := range renderMarkdown(strings.Repeat("word ", 30)+strings.Repeat("x", 50)+"\n| "+strings.Repeat("c | ", 20)+"\n", 10) {
		if visibleWidth(l) > 10 {
			t.Fatalf("wider than 10: %q", stripAnsi(l))
		}
	}
}

func TestMarkdownControlChars(t *testing.T) {
	out := strings.Join(renderMarkdown("a\x1b[31mb\x07c\x1b]0;title\x07", 40), "")
	raw := strings.ReplaceAll(out, "\x1b[0", "")
	if strings.Contains(raw, "\x1b[31m") || strings.Contains(raw, "\x07") || strings.Contains(raw, "\x1b]") {
		t.Fatalf("control chars reached the terminal: %q", out)
	}
	if !strings.Contains(stripAnsi(out), "a?[31mb?c?]0;title?") {
		t.Fatalf("control chars not drawn ?: %q", stripAnsi(out))
	}
}

// ---- no terminal ---------------------------------------------------------------

func TestNoTerminal(t *testing.T) {
	r, w, err := os.Pipe()
	mustDo(t, err)
	er, ew, err := os.Pipe()
	mustDo(t, err)
	stdin, stderr := os.Stdin, os.Stderr
	os.Stdin, os.Stderr = r, ew
	code := run([]string{t.TempDir()})
	os.Stdin, os.Stderr = stdin, stderr
	mustDo(t, ew.Close())
	buf := make([]byte, 512)
	n, _ := er.Read(buf)
	mustDo(t, w.Close())
	if code != 1 || !strings.Contains(string(buf[:n]), "needs a terminal") {
		t.Fatalf("rc %d, stderr %q", code, buf[:n])
	}
	if run(nil) != 2 {
		t.Fatal("no runs dir is not a usage error")
	}
}
