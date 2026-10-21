package main

// The Agents tab's `n` / « + nouvel agent »: runLaunch, runPick and abducoList are stubbed, so no
// process is ever started (TestRunLaunchNoBinary only names a binary that is not there).

import (
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
)

type launchCall struct {
	dir  string
	argv []string
}

// stubLaunch records each runLaunch call; dispatchBin is a fake store path for the test's length.
func stubLaunch(t testing.TB, err error) *[]launchCall {
	t.Helper()
	var calls []launchCall
	prevRun, prevBin := runLaunch, dispatchBin
	runLaunch = func(dir string, argv []string) error {
		calls = append(calls, launchCall{dir, slices.Clone(argv)})
		return err
	}
	dispatchBin = "/nix/store/x-claude-dispatch/bin/claude-dispatch"
	t.Cleanup(func() { runLaunch, dispatchBin = prevRun, prevBin })
	return &calls
}

// newAgentModel: the fixture's Agents tab, its runs dir under a temp repo (as apex-board.sh passes
// it); the repo returned.
func newAgentModel(t *testing.T) (*Model, string) {
	t.Helper()
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	repo := filepath.Join(t.TempDir(), "repo")
	m.runsDir = filepath.Join(repo, ".claude", "output", "apex")
	return m, repo
}

var blankName = regexp.MustCompile(`^agent-[0-2][0-9][0-5][0-9][0-5][0-9]$`)

// `n` runs exactly [dispatchBin, --blank, agent-HHMMSS] in the repo off the UI goroutine, then
// [agentPaneBin, pick, name]; the footer says it and the new card is selected.
func TestNewAgentKey(t *testing.T) {
	m, repo := newAgentModel(t)
	launches := stubLaunch(t, nil)
	picks := stubPick(t, nil)
	cmd := send(m, char('n'))
	if cmd == nil || m.quit || len(*launches) != 0 || len(*picks) != 0 {
		t.Fatalf("n: Cmd %v, launched on the UI goroutine %d", cmd != nil, len(*launches))
	}
	if m.ag.note != "nouvel agent : lancement…" || !m.ag.launching {
		t.Fatalf("note %q", m.ag.note)
	}
	// A second n while the first runs launches nothing.
	if again := send(m, char('n')); again != nil || m.ag.note != "nouvel agent : un lancement est en cours" {
		t.Fatalf("second n: Cmd %v note %q", again != nil, m.ag.note)
	}
	msg := cmd()
	if len(*launches) != 1 {
		t.Fatalf("launches %v", *launches)
	}
	l := (*launches)[0]
	name := l.argv[len(l.argv)-1]
	if l.dir != repo || len(l.argv) != 3 || l.argv[0] != dispatchBin || l.argv[1] != "--blank" || !blankName.MatchString(name) || !validName(name) {
		t.Fatalf("launch %+v", l)
	}
	if len(*picks) != 1 || !slices.Equal((*picks)[0], []string{agentPaneBin, "pick", name}) {
		t.Fatalf("picks %q", *picks)
	}
	send(m, msg)
	if m.ag.note != "nouvel agent : "+name || m.ag.launching || m.ag.sel == nil || m.ag.sel.id != name {
		t.Fatalf("after: note %q launching %v sel %+v", m.ag.note, m.ag.launching, m.ag.sel)
	}
	if !strings.Contains(strings.Join(plain(m.View().Content), "\n"), "nouvel agent : "+name) {
		t.Fatal("note not drawn")
	}
}

// The footer's « + nouvel agent » is drawn under its hit, and a click on it launches as `n`.
func TestNewAgentClick(t *testing.T) {
	m, repo := newAgentModel(t)
	launches := stubLaunch(t, nil)
	picks := stubPick(t, nil)
	m.View()
	h := findHit(m, hitNew, "")
	if h == nil {
		t.Fatal("no « + nouvel agent » hit")
	}
	row := []rune(plain(m.View().Content)[h.y])
	if got := string(row[h.x : h.x+h.w]); got != newAgentLabel || h.y != 49 {
		t.Fatalf("hit over %q at row %d", got, h.y)
	}
	cmd := send(m, tea.MouseClickMsg{X: h.x + 2, Y: h.y, Button: tea.MouseLeft})
	if cmd == nil || len(*launches) != 0 {
		t.Fatal("click: no launch Cmd, or launched on the UI goroutine")
	}
	send(m, cmd())
	if len(*launches) != 1 || (*launches)[0].dir != repo || (*launches)[0].argv[1] != "--blank" || len(*picks) != 1 {
		t.Fatalf("click: launches %v picks %q", *launches, *picks)
	}
	// A click on the keys beside the button launches nothing.
	*launches = nil
	m.ag.launching = false
	if cmd := send(m, tea.MouseClickMsg{X: h.x + h.w + 4, Y: h.y, Button: tea.MouseLeft}); cmd != nil || len(*launches) != 0 {
		t.Fatal("a click beside the button launched")
	}
}

// A refused launch says stderr's first line and picks nothing; a refused pick after a launch says
// both; no binary or no repo: a note, nothing run.
func TestNewAgentFailures(t *testing.T) {
	m, _ := newAgentModel(t)
	launches := stubLaunch(t, errors.New("create-session: Address already in use"))
	picks := stubPick(t, nil)
	msg := send(m, char('n'))()
	name := (*launches)[0].argv[2]
	send(m, msg)
	if len(*picks) != 0 || m.ag.note != "claude-dispatch --blank "+name+" : create-session: Address already in use" || m.ag.launching {
		t.Fatalf("launch error: picks %q note %q", *picks, m.ag.note)
	}
	if m.ag.sel != nil && m.ag.sel.id == name {
		t.Fatal("a failed launch selected its name")
	}

	runLaunch = func(string, []string) error { return nil }
	runPick = func([]string) error { return errors.New("cannot write target") }
	send(m, send(m, char('n'))())
	if !strings.HasPrefix(m.ag.note, "nouvel agent : agent-") || !strings.HasSuffix(m.ag.note, " · agent-pane pick : cannot write target") {
		t.Fatalf("pick error note %q", m.ag.note)
	}
	agentPaneBin = ""
	send(m, send(m, char('n'))())
	if !strings.HasSuffix(m.ag.note, " · agent-pane pick : binaire absent") {
		t.Fatalf("no agent-pane note %q", m.ag.note)
	}

	*launches = nil
	runLaunch = func(dir string, argv []string) error {
		*launches = append(*launches, launchCall{dir, argv})
		return nil
	}
	dispatchBin = ""
	if cmd := send(m, char('n')); cmd != nil || m.ag.note != "claude-dispatch : binaire absent, rien lancé" || m.ag.launching {
		t.Fatalf("no binary: note %q", m.ag.note)
	}
	dispatchBin = "/nix/store/x-claude-dispatch/bin/claude-dispatch"
	for _, runs := range []string{"", "relative/.claude/output/apex", "/x/runs", "/.claude/output/apex/../apex2"} {
		m.runsDir = runs
		if cmd := send(m, char('n')); cmd != nil || m.ag.note != "nouvel agent : dépôt inconnu, rien lancé" {
			t.Fatalf("runs dir %q: note %q", runs, m.ag.note)
		}
	}
	if len(*launches) != 0 {
		t.Fatalf("launched: %v", *launches)
	}
}

func TestAgentName(t *testing.T) {
	at := time.Date(2026, 10, 21, 9, 5, 7, 0, time.Local)
	none := func(string) bool { return false }
	if got := agentName(at, none); got != "agent-090507" {
		t.Fatalf("free: %q", got)
	}
	taken := map[string]bool{"agent-090507": true, "agent-090507-2": true}
	if got := agentName(at, func(n string) bool { return taken[n] }); got != "agent-090507-3" {
		t.Fatalf("collision: %q", got)
	}
	all := func(string) bool { return true }
	if got := agentName(at, all); got != "" {
		t.Fatalf("all taken: %q", got)
	}
	last := agentName(at, func(n string) bool { return n != "agent-090507-99" })
	if last != "agent-090507-99" || !validName(last) {
		t.Fatalf("last suffix %q", last)
	}
	for h := range 24 {
		if n := agentName(time.Date(2026, 1, 1, h, 59, 59, 0, time.Local), none); !validName(n) || !blankName.MatchString(n) {
			t.Fatalf("hour %d: %q", h, n)
		}
	}
	// Taken: listed by abduco, a state file, a worktree; free otherwise.
	repo, sessions := t.TempDir(), t.TempDir()
	mustDo(t, os.WriteFile(filepath.Join(sessions, "agent-000002.json"), []byte("{}"), 0o600))
	mustDo(t, os.MkdirAll(filepath.Join(repo, ".claude", "worktrees", "agent-000003"), 0o755))
	is := nameTaken(repo, sessions, map[string]bool{"agent-000001": true})
	for n, want := range map[string]bool{"agent-000001": true, "agent-000002": true, "agent-000003": true, "agent-000004": false} {
		if is(n) != want {
			t.Errorf("nameTaken(%q) = %v", n, !want)
		}
	}
	if nameTaken(repo, "", nil)("agent-000002") {
		t.Fatal("no sessions dir: a state file read")
	}
}

// launchAgent: a name abduco lists gets the suffix.
func TestLaunchAgentSkipsListed(t *testing.T) {
	now := time.Now()
	base := "agent-" + now.Format("150405")
	stubAbduco(t, []byte("Active sessions (on host x)\n  Tue\t 2026-10-21 09:05:07\t101\t"+base+"\n"), nil)
	launches := stubLaunch(t, nil)
	stubPick(t, nil)
	repo := t.TempDir()
	if msg := launchAgent(dispatchBin, agentPaneBin, repo, "", now); msg.name != base+"-2" || msg.err != "" || msg.pickErr != "" {
		t.Fatalf("msg %+v", msg)
	}
	if !slices.Equal((*launches)[0].argv, []string{dispatchBin, "--blank", base + "-2"}) {
		t.Fatalf("argv %q", (*launches)[0].argv)
	}
}

func TestRepoOf(t *testing.T) {
	for runs, want := range map[string]string{
		"/u/repo/.claude/output/apex":  "/u/repo",
		"/u/repo/.claude/output/apex/": "/u/repo",
		"/.claude/output/apex":         "",
		"repo/.claude/output/apex":     "",
		"/u/repo/runs":                 "",
		"":                             "",
	} {
		if got := repoOf(runs); got != want {
			t.Errorf("repoOf(%q) = %q, want %q", runs, got, want)
		}
	}
}

func TestRunLaunchNoBinary(t *testing.T) {
	if err := runLaunch(t.TempDir(), []string{filepath.Join(t.TempDir(), "claude-dispatch"), "--blank", "agent-000000"}); err == nil {
		t.Fatal("a missing binary launched")
	}
}

// The card's title: the name until the first prompt, then the prompt, the name leading the row
// below; the [claude-dispatch] marker never shown.
func TestCardTitle(t *testing.T) {
	blank := &sessionInput{Name: "agent-090507", Cwd: "/u/Repo/.claude/worktrees/agent-090507", State: "idle", Live: liveRunning, UpdatedAt: testNow - 60_000}
	if a := deriveAgent(blank, testNow); a.Title != "agent-090507" {
		t.Fatalf("blank title %q", a.Title)
	}
	typed := *blank
	typed.State, typed.Intent = "working", "ajoute un bouton nouvel agent"
	if a := deriveAgent(&typed, testNow); a.Title != "ajoute un bouton nouvel agent" || a.Name != "agent-090507" {
		t.Fatalf("typed title %q", a.Title)
	}
	marked := parseSessionState("s1", []byte(`{"name":"s1","state":"working","cwd":"/x","intent":"[claude-dispatch] corrige la faute"}`))
	if a := deriveAgent(marked, testNow); a.Title != "corrige la faute" {
		t.Fatalf("dispatched title %q", a.Title)
	}

	m := newModel("", "", "fixture", 180, 50)
	m.tab = tabAgents
	m.applyAgents(&agentsPoll{board: deriveAgents([]*sessionInput{blank}, testNow), now: testNow, clock: "12:00:00"})
	if r := nameRow(t, m, "agent-090507"); !strings.Contains(r, "agent-090507") || !strings.HasSuffix(strings.TrimRight(r, " │"), "×") {
		t.Fatalf("blank title row %q", r)
	}
	if r := cardRow(t, m, "agent-090507", 2); !strings.Contains(r, "Repo") || strings.Contains(r, "agent-090507") {
		t.Fatalf("blank project row %q", r)
	}
	m.applyAgents(&agentsPoll{board: deriveAgents([]*sessionInput{&typed}, testNow), now: testNow, clock: "12:00:01"})
	if r := nameRow(t, m, "agent-090507"); !strings.Contains(r, "ajoute un bouton nouvel agent") || strings.Contains(r, "agent-090507") || !strings.HasSuffix(strings.TrimRight(r, " │"), "×") {
		t.Fatalf("typed title row %q", r)
	}
	if r := cardRow(t, m, "agent-090507", 2); !strings.Contains(r, "agent-090507 · Repo") {
		t.Fatalf("typed name row %q", r)
	}
	if n := strings.Count(strings.Join(plain(m.View().Content), "\n"), "ajoute un bouton nouvel agent"); n != 1 {
		t.Fatalf("prompt drawn %d times", n)
	}
}
