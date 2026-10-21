package main

// The Agents tab's `n` / « + nouvel agent »: runLaunch, runPick, runAlive, runOpenPane and
// abducoList are stubbed, so no process is ever started (TestRunLaunchNoBinary only names a binary
// that is not there; TestRunAlive runs /bin/sh scripts of its temp dir).

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

// `n` with no pane running: pick, then [agentPaneBin, alive], then exactly one osascript call
// whose last argv item is the agent-pane path and whose script never holds it.
func TestNewAgentOpensPane(t *testing.T) {
	m, _ := newAgentModel(t)
	stubLaunch(t, nil)
	picks := stubPick(t, nil)
	pc := stubPane(t, false, nil, nil)
	var order []string
	pick, alive, open := runPick, runAlive, runOpenPane
	runPick = func(a []string) error { order = append(order, "pick"); return pick(a) }
	runAlive = func(a []string) (bool, error) { order = append(order, "alive"); return alive(a) }
	runOpenPane = func(a []string) error { order = append(order, "open"); return open(a) }
	msg := send(m, char('n'))()
	if !slices.Equal(order, []string{"pick", "alive", "open"}) || len(*picks) != 1 {
		t.Fatalf("order %q", order)
	}
	name := (*picks)[0][2]
	if len(pc.alive) != 1 || !slices.Equal(pc.alive[0], []string{agentPaneBin, "alive"}) || len(pc.open) != 1 {
		t.Fatalf("alive %q open %q", pc.alive, pc.open)
	}
	o := pc.open[0]
	if o[0] != "/usr/bin/osascript" || o[len(o)-1] != agentPaneBin || len(o) != 2*len(paneScript)+2 {
		t.Fatalf("osascript argv %q", o)
	}
	for i := 1; i < len(o)-1; i += 2 {
		if o[i] != "-e" || o[i+1] != paneScript[i/2] || strings.Contains(o[i+1], agentPaneBin) {
			t.Fatalf("argv %d: %q %q", i, o[i], o[i+1])
		}
	}
	script := strings.Join(paneScript, "\n")
	for _, want := range []string{"on run argv", `tell application "Ghostty"`, "set command of cfg to item 1 of argv", "split t direction up with configuration cfg"} {
		if !strings.Contains(script, want) {
			t.Fatalf("script lacks %q", want)
		}
	}
	send(m, msg)
	if m.ag.note != "nouvel agent : "+name || m.ag.sel == nil || m.ag.sel.id != name {
		t.Fatalf("note %q sel %+v", m.ag.note, m.ag.sel)
	}
}

// `n` with a pane running asks alive and opens nothing; a failed alive or split, or a path the
// shell would split, only says so in the footer: the agent stays launched, picked and selected.
func TestNewAgentPaneOutcomes(t *testing.T) {
	m, _ := newAgentModel(t)
	launches := stubLaunch(t, nil)
	stubPick(t, nil)
	pc := stubPane(t, true, nil, nil)
	send(m, send(m, char('n'))())
	if len(pc.alive) != 1 || len(pc.open) != 0 || !strings.HasPrefix(m.ag.note, "nouvel agent : agent-") || strings.Contains(m.ag.note, "pane") {
		t.Fatalf("pane runs: alive %q open %q note %q", pc.alive, pc.open, m.ag.note)
	}
	for _, c := range []struct {
		alive    bool
		aliveErr error
		openErr  error
		bin      string
		opens    int
		tail     string
	}{
		{false, nil, errors.New("execution error: Ghostty got an error: Can’t get window 1. (-1728)"), "", 1, " · pane : osascript : execution error: Ghostty got an error: Can’t get window 1. (-1728) — lance agent-pane à la main"},
		{false, errors.New("usage: agent-pane"), nil, "", 0, " · pane : agent-pane alive : usage: agent-pane — lance agent-pane à la main"},
		{false, nil, nil, "/nix/store/x y/bin/agent-pane", 0, " · pane : chemin d'agent-pane non sûr — lance agent-pane à la main"},
	} {
		pc := stubPane(t, c.alive, c.aliveErr, c.openErr)
		if c.bin != "" {
			agentPaneBin = c.bin
		}
		*launches = nil
		m.ag.sel = nil
		send(m, send(m, char('n'))())
		agentPaneBin = "/nix/store/x-agent-pane/bin/agent-pane"
		if len(*launches) != 1 || len(pc.open) != c.opens || !strings.HasPrefix(m.ag.note, "nouvel agent : agent-") || !strings.HasSuffix(m.ag.note, c.tail) {
			t.Fatalf("%+v: launches %d open %d note %q", c, len(*launches), len(pc.open), m.ag.note)
		}
		if m.ag.sel == nil || !strings.HasPrefix(m.ag.sel.id, "agent-") {
			t.Fatalf("%+v: launched agent not selected: %+v", c, m.ag.sel)
		}
	}
}

// runAlive on real processes (/bin/sh scripts): exit 0 = a pane, exit 1 = none, any other exit
// or no binary = an error carrying stderr's first line.
func TestRunAlive(t *testing.T) {
	dir := t.TempDir()
	script := func(name, body string) string {
		p := filepath.Join(dir, name)
		mustDo(t, os.WriteFile(p, []byte("#!/bin/sh\n"+body+"\n"), 0o700))
		return p
	}
	for _, c := range []struct {
		argv  []string
		alive bool
		err   string
	}{
		{[]string{script("zero", "exit 0"), "alive"}, true, ""},
		{[]string{script("one", "exit 1"), "alive"}, false, ""},
		{[]string{script("two", "echo 'usage: agent-pane' >&2; exit 2"), "alive"}, false, "usage: agent-pane"},
		{[]string{filepath.Join(dir, "none"), "alive"}, false, "no such file"},
	} {
		alive, err := runAlive(c.argv)
		switch {
		case alive != c.alive:
			t.Errorf("%s: alive %v", c.argv[0], alive)
		case c.err == "" && err != nil:
			t.Errorf("%s: error %v", c.argv[0], err)
		case c.err != "" && (err == nil || !strings.Contains(err.Error(), c.err)):
			t.Errorf("%s: error %v, want %q", c.argv[0], err, c.err)
		}
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
