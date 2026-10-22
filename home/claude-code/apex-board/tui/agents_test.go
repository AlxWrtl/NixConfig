package main

// The Agents tab: testdata/session-state (one file per state the writer writes, an unknown word,
// done over 24 h, a session ended under abduco and one closed without SessionEnd, plus files that
// are no session: bad JSON, an array, no cwd, name ≠ stem, `-x.json`, a dotted temp file, an
// uppercase name) copied to a temp dir, where the edges that cannot live in git are added: a link
// out of the dir, an oversized file, a FIFO. testdata/abduco/listing.txt is abduco's list in its
// real format (header, `*`, `+`, bad names); abducoList and runPick are stubbed in every test, so
// no process is ever started.

import (
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

var testNow = float64(time.Date(2026, 10, 20, 12, 0, 0, 0, time.UTC).UnixMilli())

// stubAbduco: abducoList answers out (or err) for the test's length.
func stubAbduco(t testing.TB, out []byte, err error) {
	t.Helper()
	prev := abducoList
	abducoList = func() ([]byte, error) { return out, err }
	t.Cleanup(func() { abducoList = prev })
}

func listing(t testing.TB) []byte {
	t.Helper()
	b, err := os.ReadFile("testdata/abduco/listing.txt")
	mustDo(t, err)
	return b
}

// stubPick records each runPick argv; agentPaneBin is a fake store path for the test's length.
// A pane runs (runAlive true) and opening one fails the test: stubPane changes both. Ghostty does
// not answer (runGhostty fails, so Enter falls back to the board's own pane) and agent-pane's state
// dir is an empty temp dir: stubGhostty changes them.
func stubPick(t testing.TB, err error) *[][]string {
	t.Helper()
	var calls [][]string
	prevRun, prevBin, prevAlive, prevOpen := runPick, agentPaneBin, runAlive, runOpenPane
	prevGhostty, prevState := runGhostty, paneStateDir
	runPick = func(argv []string) error {
		calls = append(calls, slices.Clone(argv))
		return err
	}
	runAlive = func([]string) (bool, error) { return true, nil }
	runOpenPane = func(argv []string) error {
		t.Errorf("a pane opened while one runs: %q", argv)
		return nil
	}
	runGhostty = func([]string) (string, error) { return "", errors.New(noGhostty) }
	state := filepath.Join(t.TempDir(), "agent-pane")
	paneStateDir = func() string { return state }
	agentPaneBin = "/nix/store/x-agent-pane/bin/agent-pane"
	t.Cleanup(func() {
		runPick, agentPaneBin, runAlive, runOpenPane = prevRun, prevBin, prevAlive, prevOpen
		runGhostty, paneStateDir = prevGhostty, prevState
	})
	return &calls
}

// noGhostty: stubPick's runGhostty error, the fallback note's tail.
const noGhostty = "pas de Ghostty (test)"

// paneCalls: what stubPane recorded, runAlive's argv and runOpenPane's.
type paneCalls struct{ alive, open [][]string }

// stubPane: runAlive answers alive (or aliveErr), runOpenPane openErr; both record their argv.
// After stubPick, which it overrides.
func stubPane(t testing.TB, alive bool, aliveErr, openErr error) *paneCalls {
	t.Helper()
	var c paneCalls
	prevAlive, prevOpen := runAlive, runOpenPane
	runAlive = func(argv []string) (bool, error) {
		c.alive = append(c.alive, slices.Clone(argv))
		return alive, aliveErr
	}
	runOpenPane = func(argv []string) error {
		c.open = append(c.open, slices.Clone(argv))
		return openErr
	}
	t.Cleanup(func() { runAlive, runOpenPane = prevAlive, prevOpen })
	return &c
}

type sessionsFixture struct{ dir, outside string }

func newSessionsFixture(t *testing.T) *sessionsFixture {
	t.Helper()
	root := t.TempDir()
	f := &sessionsFixture{dir: filepath.Join(root, "session-state"), outside: filepath.Join(root, "outside")}
	copyTree(t, "testdata/session-state", f.dir)
	mustDo(t, os.MkdirAll(f.outside, 0o755))
	secret := `{"name":"linked","state":"needs-you","cwd":"/x","intent":"SECRET-OUTSIDE","updatedAt":"2026-10-20T11:59:00.000Z"}`
	mustDo(t, os.WriteFile(filepath.Join(f.outside, "linked.json"), []byte(secret), 0o600))
	mustDo(t, os.Symlink(filepath.Join(f.outside, "linked.json"), filepath.Join(f.dir, "linked.json")))
	big := `{"name":"big","state":"working","cwd":"/x","pad":"` + strings.Repeat("x", maxStateBytes) + `"}`
	mustDo(t, os.WriteFile(filepath.Join(f.dir, "big.json"), []byte(big), 0o600))
	mustDo(t, syscall.Mkfifo(filepath.Join(f.dir, "fifo.json"), 0o600))
	return f
}

func (f *sessionsFixture) read(t *testing.T) (sessionsRead, agentsBoard) {
	t.Helper()
	read, err := (&SessionsReader{Dir: f.dir}).Read()
	mustDo(t, err)
	live, err := readAbduco()
	mustDo(t, err)
	return read, deriveAgents(withLiveness(read.sessions, live), testNow)
}

func agentsModel(t *testing.T, f *sessionsFixture, w, h int) *Model {
	t.Helper()
	stubAbduco(t, listing(t), nil)
	m := newModel("", "", "fixture", w, h)
	m.setSessionsDir(f.dir)
	m.tab = tabAgents
	p := pollAgents(m.ag.reader)
	mustDo(t, p.err)
	// Derived again at testNow: the ages and the 24 h keep do not move with the clock.
	read, err := m.ag.reader.Read()
	mustDo(t, err)
	live, _ := readAbduco()
	p.board, p.now, p.clock = deriveAgents(withLiveness(read.sessions, live), testNow), testNow, "12:00:00"
	m.applyAgents(p)
	return m
}

func colIDs(b agentsBoard, key string) []string {
	var ids []string
	for _, a := range b.cols[colIndex(key)] {
		ids = append(ids, a.ID)
	}
	return ids
}

func agentOf(t *testing.T, b agentsBoard, id string) *Agent {
	t.Helper()
	for _, col := range b.cols {
		for _, a := range col {
			if a.ID == id {
				return a
			}
		}
	}
	t.Fatalf("%s not on the board", id)
	return nil
}

func TestSessionKind(t *testing.T) {
	for state, want := range map[string]string{
		"needs-you": "needs-you", "waiting": "waiting", "idle": "idle", "working": "working", "done": "done",
		"Working": "other", "blocked": "other", "paused": "other", "": "other", " done": "other",
	} {
		if got := sessionKind(state); got != want {
			t.Errorf("sessionKind(%q) = %q, want %q", state, got, want)
		}
	}
	if projectOf("/a/Repo/.claude/worktrees/x") != "Repo" || projectOf("/a/b/") != "b" || projectOf("/") != "/" || projectOf("") != "" {
		t.Fatal("projectOf is not deck's")
	}
}

func TestValidName(t *testing.T) {
	for name, want := range map[string]bool{
		"a": true, "0": true, "ask-needs": true, "a-": true, strings.Repeat("a", 48): true,
		"": false, "-x": false, "--help": false, "Upper": false, "a_b": false, "a.b": false, "a/b": false,
		"../a": false, "a\n": false, "a b": false, "é": false, strings.Repeat("a", 49): false,
	} {
		if got := validName(name); got != want {
			t.Errorf("validName(%q) = %v", name, got)
		}
	}
}

func TestParseSessionState(t *testing.T) {
	ok := `{"name":"s1","state":"working","cwd":"/x","event":"UserPromptSubmit","updatedAt":"2026-10-20T11:59:00.000Z","intent":"[claude-dispatch]  fais\nça  avec token=abcdef123456","notice":"x\u0007y"}`
	s := parseSessionState("s1", []byte(ok))
	if s == nil || s.Intent != "fais ça avec token=•••" || s.State != "working" || s.Event != "UserPromptSubmit" || s.UpdatedAt != testNow-60_000 || s.Notice != "x\x07y" {
		t.Fatalf("parsed %+v", s)
	}
	for name, data := range map[string]string{
		"not json":      `{not json`,
		"array":         `[1]`,
		"null":          `null`,
		"string":        `"x"`,
		"no state":      `{"name":"s1","cwd":"/x"}`,
		"state number":  `{"name":"s1","state":1,"cwd":"/x"}`,
		"no cwd":        `{"name":"s1","state":"working"}`,
		"name mismatch": `{"name":"s2","state":"working","cwd":"/x"}`,
		"no name":       `{"state":"working","cwd":"/x"}`,
		"name number":   `{"name":1,"state":"working","cwd":"/x"}`,
	} {
		if parseSessionState("s1", []byte(data)) != nil {
			t.Errorf("%s: parsed", name)
		}
	}
}

func TestParseAbduco(t *testing.T) {
	got := parseAbduco(listing(t))
	var names, marks, pids []string
	for _, s := range got {
		names, marks, pids = append(names, s.Name), append(marks, string(s.Mark)), append(pids, s.Pid)
	}
	want := []string{"ask-needs", "ask-wait", "ask-idle", "work-live", "work-stale", "odd-state", "ended-cmd", "stateless", "gone-cmd"}
	if !slices.Equal(names, want) {
		t.Fatalf("names %q", names)
	}
	if !slices.Equal(marks, []string{"*", " ", " ", "*", " ", " ", "+", " ", "+"}) || pids[0] != "101" || pids[8] != "109" {
		t.Fatalf("marks %q pids %q", marks, pids)
	}
	if parseAbduco(nil) != nil || parseAbduco([]byte("Active sessions (on host x)\n")) != nil {
		t.Fatal("empty list")
	}
	live, err := func() (map[string]int, error) {
		stubAbduco(t, listing(t), nil)
		return readAbduco()
	}()
	mustDo(t, err)
	if live["ask-needs"] != liveRunning || live["ended-cmd"] != liveEnded || live["gone-cmd"] != liveEnded {
		t.Fatalf("liveness %v", live)
	}
	if _, listed := live["closed"]; listed {
		t.Fatal("closed listed")
	}
}

// Every row of the plan's state / liveness table.
func TestAgentColumnOf(t *testing.T) {
	recent := testNow - 60_000
	for _, c := range []struct {
		name            string
		in              sessionInput
		kind, col, chip string
		stale, asking   bool
		current         string
	}{
		{"needs-you", sessionInput{State: "needs-you", Notice: "permission Bash", Live: liveRunning}, "needs-you", "ask", "", false, true, "permission Bash"},
		{"waiting", sessionInput{State: "waiting", Notice: "old", Live: liveRunning}, "waiting", "ask", "à toi", false, false, ""},
		{"idle", sessionInput{State: "idle", Live: liveRunning}, "idle", "ask", "pas encore lancée", false, false, ""},
		{"working", sessionInput{State: "working", Live: liveRunning}, "working", "work", "", false, false, ""},
		{"working stale", sessionInput{State: "working", Live: liveRunning, UpdatedAt: testNow - 40*60_000}, "working", "stuck", "rien depuis 40 min", true, false, ""},
		{"done", sessionInput{State: "done", Live: liveAbsent}, "done", "done", "", false, false, ""},
		{"done ended", sessionInput{State: "done", Live: liveEnded}, "done", "done", "", false, false, ""},
		{"ended +", sessionInput{State: "working", Live: liveEnded}, "done", "done", "commande terminée", false, false, ""},
		{"absent", sessionInput{State: "needs-you", Notice: "x", Live: liveAbsent}, "done", "done", "session fermée", false, false, ""},
		{"no state file", sessionInput{Live: liveRunning, noState: true}, "other", "stuck", "sans état", false, false, ""},
		{"unknown word", sessionInput{State: "paused", Live: liveRunning}, "other", "stuck", "paused", false, false, ""},
		{"empty word", sessionInput{State: "", Live: liveRunning}, "other", "stuck", "état vide", false, false, ""},
		{"abduco failed: never ended", sessionInput{State: "waiting", Live: liveUnknown}, "waiting", "ask", "à toi", false, false, ""},
	} {
		in := c.in
		in.Name = "s"
		if in.UpdatedAt == 0 && !in.noState {
			in.UpdatedAt = recent
		}
		a := deriveAgent(&in, testNow)
		chip := ""
		if len(a.Chips) > 0 {
			chip = a.Chips[0].Label
		}
		if a.Kind != c.kind || a.Column != c.col || chip != c.chip || a.Stale != c.stale || a.Asking != c.asking || a.Current != c.current {
			t.Errorf("%s: kind %q col %q chip %q stale %v asking %v current %q", c.name, a.Kind, a.Column, chip, a.Stale, a.Asking, a.Current)
		}
	}
}

// staleMs and keepMs at their edges.
func TestStaleAndKeep(t *testing.T) {
	at := func(state string, ago float64) *sessionInput {
		return &sessionInput{Name: "s", State: state, Live: liveRunning, UpdatedAt: testNow - ago}
	}
	if a := deriveAgent(at("working", staleMs), testNow); a.Column != "work" {
		t.Fatal("stale at exactly staleMs")
	}
	if a := deriveAgent(at("working", staleMs+1), testNow); a.Column != "stuck" {
		t.Fatal("not stale past staleMs")
	}
	b := deriveAgents([]*sessionInput{at("done", keepMs), at("done", keepMs+1), at("waiting", 3*keepMs)}, testNow)
	if b.total != 2 || b.old != 1 || len(b.cols[colIndex("done")]) != 1 || len(b.cols[colIndex("ask")]) != 1 {
		t.Fatalf("keep: total %d old %d", b.total, b.old)
	}
	// Ended by abduco counts as done for the 24 h keep.
	gone := at("working", keepMs+1)
	gone.Live = liveAbsent
	if b := deriveAgents([]*sessionInput{gone}, testNow); b.old != 1 || b.total != 0 {
		t.Fatal("an old closed session kept")
	}
	if hiddenText(b) != "1 terminée depuis plus de 24 h masquée" || hiddenText(agentsBoard{}) != "" {
		t.Fatalf("hidden %q", hiddenText(b))
	}
}

func TestReadSessionsColumns(t *testing.T) {
	stubAbduco(t, listing(t), nil)
	f := newSessionsFixture(t)
	read, b := f.read(t)
	wantProblems := []string{"big : 64 Ko, plus de 64 Ko : non lu", "fifo : pas un fichier ordinaire : non lu", "linked : lien : non lu"}
	if !slices.Equal(read.problems, wantProblems) {
		t.Fatalf("problems %q", read.problems)
	}
	for key, want := range map[string][]string{
		"ask":   {"ask-needs", "ask-wait", "ask-idle"}, // bgOrder: needs-you, waiting, idle
		"work":  {"work-live"},
		"stuck": {"work-stale", "odd-state", "stateless"}, // working (stale) before other; newest first
		"done":  {"closed", "ended-cmd", "done-recent"},   // newest first
	} {
		if got := colIDs(b, key); !slices.Equal(got, want) {
			t.Errorf("%s: %v, want %v", key, got, want)
		}
	}
	if b.total != 10 || b.old != 1 {
		t.Fatalf("total %d, old %d", b.total, b.old)
	}
	if a := agentOf(t, b, "ask-needs"); !a.Asking || a.Current != "Claude needs your permission to use Bash (token=•••" || a.Mission != "corrige le login qui boucle" || a.Project != "Beta" || a.Age != "il y a 3 min" {
		t.Fatalf("needs-you: %+v", a)
	}
	if a := agentOf(t, b, "ask-wait"); a.Project != "Gamma" || strings.Contains(a.Mission, "ghp_abcdefghijklmnop") || a.Chips[0].Label != "à toi" {
		t.Fatalf("waiting: %+v", a)
	}
	if a := agentOf(t, b, "work-live"); a.Mission != "/card X1 — monter vite en 7.3" || a.Project != "Alpha" {
		t.Fatalf("working: %+v", a)
	}
	if a := agentOf(t, b, "ended-cmd"); a.Chips[0].Label != "commande terminée" {
		t.Fatalf("ended: %+v", a.Chips)
	}
	if a := agentOf(t, b, "closed"); a.Chips[0].Label != "session fermée" {
		t.Fatalf("closed: %+v", a.Chips)
	}
	if a := agentOf(t, b, "stateless"); a.Chips[0].Label != "sans état" || a.Age != "date inconnue" {
		t.Fatalf("stateless: %+v", a)
	}
	if a := agentOf(t, b, "done-recent"); len(a.Chips) != 0 {
		t.Fatalf("done needs no reason: %+v", a.Chips)
	}
	for _, col := range b.cols {
		for _, a := range col {
			for _, bad := range []string{"no-cwd", "someone-else", "wrong-name", "-x", "Upper", "array", "bad-json", "gone-cmd", "linked", "big", "fifo", "done-old"} {
				if a.ID == bad {
					t.Fatalf("%s shown", bad)
				}
			}
		}
	}
}

// Only `<name>.json` with a valid name is read: anything else never reaches pick's argv.
func TestSessionNamesValidated(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "session-state")
	mustDo(t, os.MkdirAll(dir, 0o755))
	for _, name := range []string{"--help", "-x", "ABC", "a.b", ".s1", "s1.json.1.2", "ok-1"} {
		body := `{"name":"` + name + `","state":"needs-you","cwd":"/x","updatedAt":"2026-10-20T11:59:00.000Z"}`
		mustDo(t, os.WriteFile(filepath.Join(dir, name+".json"), []byte(body), 0o600))
	}
	mustDo(t, os.WriteFile(filepath.Join(dir, ".ok-1.json.99.1.tmp"), []byte(`{"name":"ok-1","state":"done","cwd":"/x"}`), 0o600))
	mustDo(t, os.MkdirAll(filepath.Join(dir, "sub"), 0o755))
	read, err := (&SessionsReader{Dir: dir}).Read()
	mustDo(t, err)
	var names []string
	for _, s := range read.sessions {
		names = append(names, s.Name)
	}
	if !slices.Equal(names, []string{"ok-1"}) || len(read.problems) != 0 || read.sessions[0].State != "needs-you" {
		t.Fatalf("listed %v, problems %q", names, read.problems)
	}
}

func TestSessionsReaderIncremental(t *testing.T) {
	f := newSessionsFixture(t)
	r := &SessionsReader{Dir: f.dir}
	first, err := r.Read()
	mustDo(t, err)
	again, err := r.Read()
	mustDo(t, err)
	find := func(rd sessionsRead, name string) *sessionInput {
		for _, s := range rd.sessions {
			if s.Name == name {
				return s
			}
		}
		return nil
	}
	if find(first, "ask-needs") == nil || find(first, "ask-needs") != find(again, "ask-needs") {
		t.Fatal("unchanged session parsed again")
	}
	if len(again.problems) != len(first.problems) {
		t.Fatalf("problems drift: %q", again.problems)
	}
	// As the writer does: a temp file renamed over the state file.
	tmp := filepath.Join(f.dir, ".ask-needs.json.1.2.tmp")
	mustDo(t, os.WriteFile(tmp, []byte(`{"name":"ask-needs","state":"done","cwd":"/x","updatedAt":"2026-10-20T11:59:00.000Z"}`), 0o600))
	mustDo(t, os.Rename(tmp, filepath.Join(f.dir, "ask-needs.json")))
	third, err := r.Read()
	mustDo(t, err)
	if s := find(third, "ask-needs"); s == nil || s.State != "done" {
		t.Fatal("changed session not read again")
	}
	// A cached parse is never mutated by a poll's liveness.
	withLiveness(third.sessions, map[string]int{})
	if find(third, "ask-needs").Live != liveUnknown {
		t.Fatal("cached session mutated")
	}
	if rd, err := (&SessionsReader{Dir: filepath.Join(t.TempDir(), "none")}).Read(); err != nil || len(rd.sessions) != 0 {
		t.Fatalf("missing dir: %v", err)
	}
}

// abduco failing marks nothing ended (fail-open) and says so in the tab.
func TestAbducoFailureFailsOpen(t *testing.T) {
	f := newSessionsFixture(t)
	stubAbduco(t, nil, errors.New("exit status 1"))
	p := pollAgents(&SessionsReader{Dir: f.dir})
	if p.err != nil || !slices.Contains(p.problems, "abduco : exit status 1 : sessions non vérifiées") {
		t.Fatalf("problems %q", p.problems)
	}
	read, _ := (&SessionsReader{Dir: f.dir}).Read()
	b := deriveAgents(withLiveness(read.sessions, nil), testNow)
	if a := agentOf(t, b, "closed"); a.Column != "ask" {
		t.Fatalf("closed drawn %q with abduco unknown", a.Column)
	}
	if a := agentOf(t, b, "ended-cmd"); a.Column != "stuck" || !a.Stale { // working, 20 min silent
		t.Fatalf("ended-cmd drawn %q with abduco unknown", a.Column)
	}
	if slices.Contains(colIDs(b, "stuck"), "stateless") {
		t.Fatal("a stateless session invented")
	}
}

func TestAbducoListNoBinary(t *testing.T) {
	prev := abducoBin
	defer func() { abducoBin = prev }()
	abducoBin = ""
	if _, err := abducoList(); err == nil || err.Error() != "binaire absent" {
		t.Fatalf("no binary: %v", err)
	}
	abducoBin = filepath.Join(t.TempDir(), "abduco")
	if _, err := abducoList(); err == nil {
		t.Fatal("a missing binary answered")
	}
}

// Ghostty not answering (stubPick): Enter, o and a card click fall back to exactly [agentPaneBin,
// pick, name], the footer saying why; the board stays open.
func TestPick(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	calls := stubPick(t, nil)
	bin := agentPaneBin
	for i, k := range []tea.Msg{key(tea.KeyEnter), char('o')} {
		cmd := send(m, k)
		if cmd == nil || m.quit {
			t.Fatalf("%v: no pick Cmd, or quit", k)
		}
		if len(*calls) != i {
			t.Fatal("pick ran on the UI goroutine")
		}
		msg := cmd()
		if _, ok := msg.(tea.QuitMsg); ok {
			t.Fatal("pick quit")
		}
		send(m, msg)
	}
	want := []string{bin, "pick", "ask-needs"}
	if len(*calls) != 2 || !slices.Equal((*calls)[0], want) || !slices.Equal((*calls)[1], want) {
		t.Fatalf("calls %q", *calls)
	}
	if m.quit || m.ag.note != "affichée en haut : ask-needs · Ghostty : "+noGhostty || !strings.Contains(strings.Join(plain(m.View().Content), "\n"), "affichée en haut : ask-needs") {
		t.Fatalf("note %q", m.ag.note)
	}
	send(m, key(tea.KeyDown))
	if m.ag.note != "" {
		t.Fatal("note not cleared by the next key")
	}
	// A click on a card selects it and picks it.
	*calls = nil
	card := findHit(m, hitCard, "work-live")
	cmd := send(m, tea.MouseClickMsg{X: card.x + 1, Y: card.y, Button: tea.MouseLeft})
	if cmd == nil {
		t.Fatal("click: no pick")
	}
	send(m, cmd())
	if len(*calls) != 1 || !slices.Equal((*calls)[0], []string{bin, "pick", "work-live"}) || m.ag.sel.id != "work-live" {
		t.Fatalf("click calls %q", *calls)
	}
	// A refused pick says stderr's first line.
	runPick = func([]string) error { return errors.New("name must match ^[a-z0-9][a-z0-9-]{0,47}$") }
	send(m, send(m, key(tea.KeyEnter))())
	if m.ag.note != "agent-pane pick work-live : name must match ^[a-z0-9][a-z0-9-]{0,47}$ · Ghostty : "+noGhostty {
		t.Fatalf("error note %q", m.ag.note)
	}
	// An invalid name never reaches runPick, nor does any name without the binary.
	*calls = nil
	runPick = func(argv []string) error { *calls = append(*calls, argv); return nil }
	for _, bad := range []string{"--help", "-x", "", "A", "a b", "a\n"} {
		if m.pickCmd(bad) != nil || m.showCmd(bad) != nil {
			t.Fatalf("pickCmd or showCmd(%q) gave a Cmd", bad)
		}
	}
	agentPaneBin = ""
	for _, c := range []func(string) tea.Cmd{m.pickCmd, m.showCmd} {
		m.ag.note = ""
		if c("ask-needs") != nil || m.ag.note != "agent-pane : binaire absent, rien lancé" {
			t.Fatalf("no binary: note %q", m.ag.note)
		}
	}
	if len(*calls) != 0 {
		t.Fatalf("runPick called: %q", *calls)
	}
}

// Enter with no pane running, Ghostty not answering: after the fallback pick, [agentPaneBin,
// alive] then one osascript split; a failed split only says so; a refused pick asks nothing.
func TestPickOpensPane(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	picks := stubPick(t, nil)
	pc := stubPane(t, false, nil, nil)
	send(m, send(m, key(tea.KeyEnter))())
	if len(*picks) != 1 || len(pc.alive) != 1 || !slices.Equal(pc.alive[0], []string{agentPaneBin, "alive"}) {
		t.Fatalf("picks %q alive %q", *picks, pc.alive)
	}
	if len(pc.open) != 1 || !slices.Equal(pc.open[0], openPaneArgv(agentPaneBin)) || m.ag.note != "affichée en haut : ask-needs · Ghostty : "+noGhostty {
		t.Fatalf("open %q note %q", pc.open, m.ag.note)
	}
	pc.open = nil
	runOpenPane = func(argv []string) error {
		pc.open = append(pc.open, argv)
		return errors.New("Ghostty got an error: Can’t get front window. (-1728)")
	}
	send(m, send(m, key(tea.KeyEnter))())
	if len(pc.open) != 1 || m.ag.note != "affichée en haut : ask-needs · pane : osascript : Ghostty got an error: Can’t get front window. (-1728) — lance agent-pane à la main · Ghostty : "+noGhostty {
		t.Fatalf("open error: open %d note %q", len(pc.open), m.ag.note)
	}
	pc.alive, pc.open = nil, nil
	runPick = func([]string) error { return errors.New("cannot write target") }
	send(m, send(m, key(tea.KeyEnter))())
	if len(pc.alive) != 0 || len(pc.open) != 0 || m.ag.note != "agent-pane pick ask-needs : cannot write target · Ghostty : "+noGhostty {
		t.Fatalf("refused pick: alive %q open %q note %q", pc.alive, pc.open, m.ag.note)
	}
}

// ---- placement (Ghostty), runGhostty stubbed -------------------------------------

// Ghostty's ids in the tests: uppercase UUIDs, as Ghostty prints them.
const (
	boardTab  = "6B1E0C4A-0000-4000-8000-00000000000A"
	boardTerm = "6B1E0C4A-0000-4000-8000-0000000000B0"
	otherTerm = "6B1E0C4A-0000-4000-8000-0000000000C0"
	newTerm   = "6B1E0C4A-0000-4000-8000-0000000000D0"
)

// ghosttyCall: one runGhostty call, its -e lines and its argv items.
type ghosttyCall struct{ script, items []string }

// ghosttyFake: what each script answers.
type ghosttyFake struct {
	board, focused, split string
	focusErr, splitErr    error
}

// stubGhostty: runGhostty answers from fake per script, each call recorded; after stubPick. An
// argv that is not /usr/bin/osascript, -e pairs, then items, or an unknown script, fails the test.
func stubGhostty(t *testing.T, fake *ghosttyFake) *[]ghosttyCall {
	t.Helper()
	var calls []ghosttyCall
	prev := runGhostty
	runGhostty = func(argv []string) (string, error) {
		if len(argv) == 0 || argv[0] != "/usr/bin/osascript" {
			t.Errorf("not osascript: %q", argv)
			return "", errors.New("bad argv")
		}
		var c ghosttyCall
		i := 1
		for i+1 < len(argv) && argv[i] == "-e" {
			c.script = append(c.script, argv[i+1])
			i += 2
		}
		c.items = slices.Clone(argv[i:])
		calls = append(calls, c)
		switch {
		case slices.Equal(c.script, boardScript):
			return fake.board, nil
		case slices.Equal(c.script, focusedScript):
			return fake.focused, fake.focusErr
		case slices.Equal(c.script, splitScript):
			return fake.split, fake.splitErr
		case slices.Equal(c.script, focusScript):
			return "", fake.focusErr
		}
		t.Errorf("unknown script %q", c.script)
		return "", errors.New("unknown script")
	}
	t.Cleanup(func() { runGhostty = prev })
	return &calls
}

// startPlace: Enter on the selected card (ask-needs) must start placement mode, its first tick
// armed.
func startPlace(t *testing.T, m *Model) *placeState {
	t.Helper()
	cmd := send(m, key(tea.KeyEnter))
	if cmd == nil {
		t.Fatal("Enter: no Cmd")
	}
	msg, ok := cmd().(placeStartMsg)
	if !ok {
		t.Fatalf("Enter gave %T, want placeStartMsg", msg)
	}
	if send(m, msg) == nil || m.ag.place == nil {
		t.Fatalf("no placement: note %q", m.ag.note)
	}
	return m.ag.place
}

// tickOnce: one tick of the current placement and Ghostty's answer; when that ends the placement
// (a terminal was chosen), its Cmd runs and its outcome is applied. The next tick's Cmd is never
// run (it sleeps placeEvery).
func tickOnce(t *testing.T, m *Model) {
	t.Helper()
	p := m.ag.place
	cmd := send(m, placeTickMsg{gen: p.gen})
	if cmd == nil {
		return
	}
	next := send(m, cmd())
	if m.ag.place == nil && next != nil {
		send(m, next())
	}
}

// A live terminal pane whose target is the card: exactly one focus, its id uppercased as an argv
// item, no pick. Panes that are dead, show another agent, sit in a non-terminal slot (a hand one) or
// have a linked target are passed over; only the candidates are asked alive.
func TestShowFocusesShownPane(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	picks := stubPick(t, nil)
	calls := stubGhostty(t, &ghosttyFake{board: boardTab + "\n" + boardTerm})
	slots := filepath.Join(paneStateDir(), "slots")
	dead, live, other := "6b1e0c4a-0000-4000-8000-0000000000a0", strings.ToLower(otherTerm), "6b1e0c4a-0000-4000-8000-0000000000f0"
	linked := "6b1e0c4a-0000-4000-8000-0000000000e0"
	// "0hand" (a hand-typed --slot, live) sorts first: a terminal check dropped would focus it.
	for slot, name := range map[string]string{dead: "ask-needs", live: "ask-needs", other: "work-live", "0hand": "ask-needs"} {
		mustDo(t, os.MkdirAll(filepath.Join(slots, slot), 0o700))
		mustDo(t, os.WriteFile(filepath.Join(slots, slot, "target"), []byte(name+"\n1-1\n"), 0o600))
	}
	mustDo(t, os.MkdirAll(filepath.Join(slots, linked), 0o700))
	mustDo(t, os.Symlink(filepath.Join(slots, live, "target"), filepath.Join(slots, linked, "target")))
	var alive [][]string
	runAlive = func(argv []string) (bool, error) {
		alive = append(alive, slices.Clone(argv))
		return argv[2] != dead, nil
	}
	send(m, send(m, key(tea.KeyEnter))())
	bin := agentPaneBin
	if !slices.EqualFunc(alive, [][]string{{bin, "--slot", dead, "alive"}, {bin, "--slot", live, "alive"}}, slices.Equal) {
		t.Fatalf("alive %q", alive)
	}
	if len(*calls) != 1 || !slices.Equal((*calls)[0].script, focusScript) || !slices.Equal((*calls)[0].items, []string{otherTerm}) {
		t.Fatalf("ghostty %q", *calls)
	}
	if len(*picks) != 0 || m.ag.place != nil || m.ag.note != "affichée : ask-needs" {
		t.Fatalf("picks %q place %+v note %q", *picks, m.ag.place, m.ag.note)
	}
	// A focus that fails says so, and places nothing.
	stubGhostty(t, &ghosttyFake{focusErr: errors.New("Can’t get terminal id")})
	send(m, send(m, key(tea.KeyEnter))())
	if m.ag.place != nil || m.ag.note != "focus ask-needs : osascript : Can’t get terminal id" || len(*picks) != 0 {
		t.Fatalf("focus error: note %q", m.ag.note)
	}
}

// Placement: the board still focused → another tick, nothing run; any key but Enter / Échap and
// any click ignored; a terminal whose pane runs → exactly [pane, --slot, lower(T), pick, name];
// one where none runs → one split on its right running `<pane> --here`, then the pick on the new
// terminal's slot; a split with no id back picks nothing.
func TestPlacement(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	picks := stubPick(t, nil)
	fake := &ghosttyFake{board: boardTab + "\n" + boardTerm, focused: boardTerm, split: newTerm}
	calls := stubGhostty(t, fake)
	pc := stubPane(t, true, nil, nil)
	bin, slot := agentPaneBin, strings.ToLower(otherTerm)
	p := startPlace(t, m)
	if len(*calls) != 1 || !slices.Equal((*calls)[0].script, boardScript) || len((*calls)[0].items) != 0 {
		t.Fatalf("board query %q", *calls)
	}
	if p.name != "ask-needs" || p.tab != boardTab || p.board != boardTerm || !strings.HasPrefix(m.ag.note, "clique le pane où afficher ask-needs") {
		t.Fatalf("place %+v note %q", p, m.ag.note)
	}
	note := m.ag.note
	for _, k := range []tea.Msg{char('x'), char('q'), char('o'), char('n'), char('a'), key(tea.KeyDown)} {
		if cmd := send(m, k); cmd != nil || m.quit || m.ag.place != p || m.ag.note != note || m.tab != tabAgents {
			t.Fatalf("%v not ignored: place %+v note %q", k, m.ag.place, m.ag.note)
		}
	}
	card := findHit(m, hitCard, "work-live")
	if cmd := send(m, tea.MouseClickMsg{X: card.x + 1, Y: card.y, Button: tea.MouseLeft}); cmd != nil || m.ag.place != p {
		t.Fatal("a click in placement was not ignored")
	}
	tickOnce(t, m)
	if m.ag.place != p || len(*calls) != 2 || !slices.Equal((*calls)[1].script, focusedScript) || !slices.Equal((*calls)[1].items, []string{boardTab}) {
		t.Fatalf("board focused: place %+v calls %q", m.ag.place, *calls)
	}
	if len(*picks) != 0 || len(pc.alive) != 0 {
		t.Fatalf("board focused ran: picks %q alive %q", *picks, pc.alive)
	}
	if send(m, placeTickMsg{gen: p.gen - 1}) != nil {
		t.Fatal("a stale tick asked Ghostty")
	}
	// Another terminal, its pane alive: the pane switches.
	fake.focused = otherTerm
	tickOnce(t, m)
	if m.ag.place != nil || !slices.EqualFunc(pc.alive, [][]string{{bin, "--slot", slot, "alive"}}, slices.Equal) {
		t.Fatalf("alive %q place %+v", pc.alive, m.ag.place)
	}
	if !slices.EqualFunc(*picks, [][]string{{bin, "--slot", slot, "pick", "ask-needs"}}, slices.Equal) || len(*calls) != 3 || m.ag.note != "affichée : ask-needs" {
		t.Fatalf("picks %q calls %d note %q", *picks, len(*calls), m.ag.note)
	}
	// No pane there: a split on its right, then the pick on the new terminal's slot.
	*picks, *calls = nil, nil
	pc = stubPane(t, false, nil, nil)
	startPlace(t, m)
	tickOnce(t, m)
	if len(*calls) != 3 || !slices.Equal((*calls)[2].script, splitScript) || !slices.Equal((*calls)[2].items, []string{otherTerm, bin + " --here"}) {
		t.Fatalf("split %q", *calls)
	}
	if !slices.EqualFunc(*picks, [][]string{{bin, "--slot", strings.ToLower(newTerm), "pick", "ask-needs"}}, slices.Equal) || m.ag.note != "affichée : ask-needs (nouveau split)" {
		t.Fatalf("picks %q note %q", *picks, m.ag.note)
	}
	if len(pc.open) != 0 {
		t.Fatalf("the old split above ran: %q", pc.open)
	}
	// The split gives no id back: nothing picked, the footer says it.
	*picks, fake.split = nil, ""
	startPlace(t, m)
	tickOnce(t, m)
	if len(*picks) != 0 || m.ag.note != "ask-needs : split ouvert sans id : rien choisi dedans" {
		t.Fatalf("no id: picks %q note %q", *picks, m.ag.note)
	}
	// No script ever holds the name, the pane's path or an id: argv items only.
	for _, c := range *calls {
		for _, l := range c.script {
			if strings.Contains(l, "ask-needs") || strings.Contains(l, bin) || strings.Contains(l, "--here") || strings.Contains(strings.ToUpper(l), "6B1E0C4A") {
				t.Fatalf("script line %q holds a value", l)
			}
		}
	}
}

// Enter in placement: a split on the right of the board's own terminal (no alive asked), the
// pick on the new one.
func TestPlacementEnter(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	picks := stubPick(t, nil)
	calls := stubGhostty(t, &ghosttyFake{board: boardTab + "\n" + boardTerm, focused: boardTerm, split: newTerm})
	pc := stubPane(t, true, nil, nil)
	startPlace(t, m)
	cmd := send(m, key(tea.KeyEnter))
	if cmd == nil || m.ag.place != nil {
		t.Fatal("Enter in placement: no split Cmd")
	}
	send(m, cmd())
	if len(*calls) != 2 || !slices.Equal((*calls)[1].script, splitScript) || !slices.Equal((*calls)[1].items, []string{boardTerm, agentPaneBin + " --here"}) {
		t.Fatalf("split %q", *calls)
	}
	if script := strings.Join(splitScript, "\n"); !strings.Contains(script, "direction right") || strings.Contains(script, "direction up") {
		t.Fatal("the split is not on the right")
	}
	if len(pc.alive) != 0 || !slices.EqualFunc(*picks, [][]string{{agentPaneBin, "--slot", strings.ToLower(newTerm), "pick", "ask-needs"}}, slices.Equal) {
		t.Fatalf("alive %q picks %q", pc.alive, *picks)
	}
}

// Échap, the 30 s timeout, a closed tab or a failed query: placement ends, nothing run.
func TestPlacementCancel(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	picks := stubPick(t, nil)
	fake := &ghosttyFake{board: boardTab + "\n" + boardTerm, focused: otherTerm, split: newTerm}
	calls := stubGhostty(t, fake)
	pc := stubPane(t, false, nil, nil)
	p := startPlace(t, m)
	if cmd := send(m, key(tea.KeyEscape)); cmd != nil || m.ag.place != nil || m.ag.note != "placement annulé" {
		t.Fatalf("Échap: place %+v note %q", m.ag.place, m.ag.note)
	}
	if send(m, placeTickMsg{gen: p.gen}) != nil || send(m, placeFocusMsg{gen: p.gen, term: otherTerm}) != nil {
		t.Fatal("a cancelled placement still runs")
	}
	startPlace(t, m)
	m.ag.place.until = time.Now().Add(-time.Millisecond)
	if cmd := send(m, placeTickMsg{gen: m.ag.place.gen}); cmd != nil || m.ag.place != nil || m.ag.note != "placement de ask-needs annulé (30 s)" {
		t.Fatalf("timeout: place %+v note %q", m.ag.place, m.ag.note)
	}
	fake.focused = ""
	startPlace(t, m)
	tickOnce(t, m)
	if m.ag.place != nil || m.ag.note != "onglet du board introuvable : placement annulé" {
		t.Fatalf("tab gone: note %q", m.ag.note)
	}
	fake.focusErr = errors.New("Ghostty got an error")
	startPlace(t, m)
	tickOnce(t, m)
	if m.ag.place != nil || m.ag.note != "placement annulé : osascript : Ghostty got an error" {
		t.Fatalf("query error: note %q", m.ag.note)
	}
	for _, c := range *calls {
		if slices.Equal(c.script, splitScript) {
			t.Fatalf("a cancelled placement split: %q", c.items)
		}
	}
	if len(*picks) != 0 || len(pc.alive) != 0 || len(pc.open) != 0 {
		t.Fatalf("picks %q alive %q open %q", *picks, pc.alive, pc.open)
	}
}

// Ids Ghostty prints that are no slot fall back to the board's own pane; termSlot lowercases and
// keeps the name rule; hereCommand refuses a path the shell would split, and placeInto then splits
// nothing.
func TestPlacementGuards(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	picks := stubPick(t, nil)
	calls := stubGhostty(t, &ghosttyFake{board: "only-one-line"})
	send(m, send(m, key(tea.KeyEnter))())
	if m.ag.place != nil || !slices.EqualFunc(*picks, [][]string{{agentPaneBin, "pick", "ask-needs"}}, slices.Equal) || m.ag.note != "affichée en haut : ask-needs · Ghostty : ids illisibles" {
		t.Fatalf("bad ids: picks %q note %q", *picks, m.ag.note)
	}
	if termSlot(otherTerm) != strings.ToLower(otherTerm) || termSlot(" "+otherTerm+"\n") != strings.ToLower(otherTerm) {
		t.Fatal("termSlot does not lowercase")
	}
	for _, bad := range []string{"", "-x", "../x", "a b", "A;B", strings.Repeat("a", 49)} {
		if termSlot(bad) != "" {
			t.Fatalf("termSlot(%q) = %q", bad, termSlot(bad))
		}
	}
	if hereCommand(agentPaneBin) != agentPaneBin+" --here" || hereCommand("/nix/store/x y/bin/agent-pane") != "" || hereCommand("bin/agent-pane") != "" {
		t.Fatal("hereCommand")
	}
	*calls = nil
	stubPane(t, false, nil, nil)
	if got := placeInto("/nix/store/x;y/bin/agent-pane", "ask-needs", otherTerm, false); got.err != "chemin d'agent-pane non sûr" || len(*calls) != 0 {
		t.Fatalf("unsafe path: %+v calls %q", got, *calls)
	}
	if got := placeInto(agentPaneBin, "ask-needs", "-x", true); got.err == "" || len(*calls) != 0 {
		t.Fatalf("bad term: %+v calls %q", got, *calls)
	}
}

// nameRow: the text of id's title row (the card's second row, the ×'s), within its card.
func nameRow(t *testing.T, m *Model, id string) string {
	t.Helper()
	return cardRow(t, m, id, 1)
}

// cardRow: the text of id's row r (0 = its top border), within its card.
func cardRow(t *testing.T, m *Model, id string, r int) string {
	t.Helper()
	m.View()
	card := findHit(m, hitCard, id)
	if card == nil {
		t.Fatalf("%s not drawn", id)
	}
	line := []rune(plain(m.View().Content)[card.y+r])
	return string(line[card.x : card.x+card.w])
}

// `x` arms the selected card, a second `x` runs exactly [agentPaneBin, stop, name]; any other key
// in between disarms.
func TestStopConfirm(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	calls := stubPick(t, nil)
	bin := agentPaneBin
	if cmd := send(m, char('x')); cmd != nil || len(*calls) != 0 {
		t.Fatalf("a first x stopped: calls %q", *calls)
	}
	ask := "éteindre ask-needs ? × ou x encore pour confirmer · Échap annule"
	if m.ag.armed != "ask-needs" || m.ag.note != ask || !strings.Contains(strings.Join(plain(m.View().Content), "\n"), ask) {
		t.Fatalf("armed %q note %q", m.ag.armed, m.ag.note)
	}
	if a := agentOf(t, m.ag.board, "ask-needs"); !a.rows.armed {
		t.Fatal("the armed card was not redrawn")
	}
	cmd := send(m, char('x'))
	if cmd == nil || len(*calls) != 0 {
		t.Fatal("no stop Cmd, or stop ran on the UI goroutine")
	}
	msg := cmd()
	if len(*calls) != 1 || !slices.Equal((*calls)[0], []string{bin, "stop", "ask-needs"}) {
		t.Fatalf("calls %q", *calls)
	}
	if next := send(m, msg); next == nil || m.ag.note != "éteinte : ask-needs" || m.ag.armed != "" {
		t.Fatalf("after stop: poll %v, note %q, armed %q", next != nil, m.ag.note, m.ag.armed)
	}
	// x, then another key, then x: the second x arms again, never stops.
	m.polling = false
	*calls = nil
	for _, between := range []tea.Msg{char('j'), key(tea.KeyEscape), char('r')} {
		m.ag.sel = &selState{id: "ask-needs"}
		send(m, char('x'))
		send(m, between)
		if m.ag.armed != "" {
			t.Fatalf("%v did not disarm", between)
		}
		m.ag.sel = &selState{id: "ask-needs"}
		if cmd := send(m, char('x')); cmd != nil || m.ag.armed != "ask-needs" {
			t.Fatalf("x after %v: a Cmd, or not armed", between)
		}
		send(m, key(tea.KeyEscape))
		m.polling = false
	}
	// Armed on one card, x on another arms that one.
	m.ag.sel = &selState{id: "ask-needs"}
	send(m, char('x'))
	send(m, char('j'))
	if cmd := send(m, char('x')); cmd != nil || m.ag.armed != "ask-wait" {
		t.Fatalf("x on another card: armed %q", m.ag.armed)
	}
	if len(*calls) != 0 {
		t.Fatalf("stopped without a confirm: %q", *calls)
	}
	// A refused stop says stderr's first line.
	runPick = func([]string) error { return errors.New("ask-wait: no such session") }
	send(m, send(m, char('x'))())
	if m.ag.note != "agent-pane stop ask-wait : ask-wait: no such session" {
		t.Fatalf("error note %q", m.ag.note)
	}
	// An invalid name never reaches runPick, nor does any name without the binary.
	*calls = nil
	runPick = func(argv []string) error { *calls = append(*calls, argv); return nil }
	for _, bad := range []string{"--help", "-x", "", "A", "a b", "a\n"} {
		if m.stopCmd(bad) != nil {
			t.Fatalf("stopCmd(%q) gave a Cmd", bad)
		}
	}
	agentPaneBin = ""
	if m.stopCmd("ask-needs") != nil || m.ag.note != "agent-pane : binaire absent, rien éteint" {
		t.Fatalf("no binary: note %q", m.ag.note)
	}
	if len(*calls) != 0 {
		t.Fatalf("runPick called: %q", *calls)
	}
}

// A session abduco does not list (closed), or abduco silent: no ×, x stops nothing.
func TestStopNotStoppable(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	calls := stubPick(t, nil)
	m.View()
	for id, want := range map[string]bool{"ask-needs": true, "work-live": true, "ended-cmd": true, "stateless": true, "closed": false, "done-recent": false} {
		if a := agentOf(t, m.ag.board, id); a.Stoppable != want || (findHit(m, hitStop, id) != nil) != want || strings.Contains(nameRow(t, m, id), "×") != want {
			t.Errorf("%s: stoppable %v, × hit %v, row %q", id, a.Stoppable, findHit(m, hitStop, id) != nil, nameRow(t, m, id))
		}
	}
	for range 2 {
		m.ag.sel = &selState{id: "closed"}
		if cmd := send(m, char('x')); cmd != nil || m.ag.armed != "" || m.ag.note != "closed : pas de session à éteindre" {
			t.Fatalf("x on closed: armed %q note %q", m.ag.armed, m.ag.note)
		}
	}
	// abduco failed: every card is liveUnknown, none stoppable (fail-closed on the action).
	read, err := m.ag.reader.Read()
	mustDo(t, err)
	m.applyAgents(&agentsPoll{board: deriveAgents(withLiveness(read.sessions, nil), testNow), now: testNow, clock: "12:00:00"})
	m.ag.sel = nil
	m.View()
	if h := findHit(m, hitStop, ""); h != nil {
		t.Fatalf("× on %s with abduco silent", h.id)
	}
	sel := m.agentSelection()
	id := m.ag.board.cols[sel.col][sel.idx].ID
	for range 2 {
		if cmd := send(m, char('x')); cmd != nil || m.ag.armed != "" || m.ag.note != id+" : pas de session à éteindre" {
			t.Fatalf("x with abduco silent: note %q", m.ag.note)
		}
	}
	if len(*calls) != 0 {
		t.Fatalf("runPick called: %q", *calls)
	}
}

// A click on × arms, a second stops; a click on the card's body picks; a click anywhere else
// disarms.
func TestStopMouse(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	calls := stubPick(t, nil)
	bin := agentPaneBin
	m.View()
	x := findHit(m, hitStop, "work-live")
	card := findHit(m, hitCard, "work-live")
	if x == nil || card == nil || x.y != card.y+1 || []rune(plain(m.View().Content)[x.y])[x.x+1] != '×' {
		t.Fatalf("× hit %+v not on the drawn ×", x)
	}
	if h := hitAt(m.hits, x.x+1, x.y); h == nil || h.kind != hitStop {
		t.Fatal("the card's hit wins over its ×")
	}
	click := func(cx, cy int) tea.Cmd { return send(m, tea.MouseClickMsg{X: cx, Y: cy, Button: tea.MouseLeft}) }
	if cmd := click(x.x+1, x.y); cmd != nil || m.ag.armed != "work-live" || m.ag.sel.id != "work-live" || len(*calls) != 0 {
		t.Fatalf("first click: armed %q calls %q", m.ag.armed, *calls)
	}
	cmd := click(x.x, x.y)
	if cmd == nil {
		t.Fatal("second click: no stop")
	}
	send(m, cmd())
	if len(*calls) != 1 || !slices.Equal((*calls)[0], []string{bin, "stop", "work-live"}) {
		t.Fatalf("click calls %q", *calls)
	}
	// Armed, then a click on the body: disarmed and picked, not stopped.
	m.polling = false
	*calls = nil
	click(x.x+1, x.y)
	cmd = click(card.x+1, card.y+2)
	if cmd == nil || m.ag.armed != "" {
		t.Fatalf("body click: armed %q", m.ag.armed)
	}
	cmd()
	if len(*calls) != 1 || !slices.Equal((*calls)[0], []string{bin, "pick", "work-live"}) {
		t.Fatalf("body click calls %q", *calls)
	}
	// Armed, then a click on nothing: disarmed, the question gone.
	click(x.x+1, x.y)
	if hitAt(m.hits, 0, 49) != nil {
		t.Fatal("the test's empty cell holds a hit")
	}
	if cmd := click(0, 49); cmd != nil || m.ag.armed != "" || m.ag.note != "" {
		t.Fatalf("click on nothing: armed %q note %q", m.ag.armed, m.ag.note)
	}
	if cmd := click(x.x+1, x.y); cmd != nil || m.ag.armed != "work-live" {
		t.Fatal("after a disarm, a click on × stopped")
	}
}

func TestAgentsReadOnly(t *testing.T) {
	f := newSessionsFixture(t)
	before := append(snapshotTree(t, f.dir), snapshotTree(t, f.outside)...)
	m := agentsModel(t, f, 160, 48)
	m.View()
	all := strings.Join(plain(m.View().Content), "\n")
	if strings.Contains(all, "SECRET") {
		t.Fatal("a file outside the dir was drawn")
	}
	if after := append(snapshotTree(t, f.dir), snapshotTree(t, f.outside)...); !slices.Equal(before, after) {
		t.Fatal("the session-state dir changed")
	}
}

// snapshotTree: every path under root with its size, mode and mtime.
func snapshotTree(t testing.TB, root string) []string {
	var out []string
	mustDo(t, filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		fi, err := os.Lstat(p)
		if err != nil {
			return err
		}
		out = append(out, p+" "+fi.Mode().String()+" "+itoaT(int(fi.Size()))+" "+fi.ModTime().String())
		return nil
	}))
	return out
}

func TestRenderAgents(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
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
	all := strings.Join(text, "\n")
	head := ""
	for _, l := range text {
		if strings.Contains(l, "Attend ta réponse") && strings.Contains(l, "Terminé") {
			head = l
		}
	}
	last := -1
	for _, c := range AgentColumns {
		at := strings.Index(head, c.Label)
		if at <= last {
			t.Fatalf("columns out of order in %q", head)
		}
		last = at
	}
	for _, want := range []string{
		"[Agents ● 3]", " Runs ", "session-state/ · 10 · 12:00:00",
		"ask-needs", "Beta", "il y a 3 min", "corrige le login qui boucle", "Claude needs your permission",
		"lit ?[31mrouge? le cache", "à toi", "pas encore lancée", "/card X1 — monter vite en 7.3", "Alpha",
		"rien depuis 40 min", "paused", "sans état", "commande terminée", "session fermée",
		"1 terminée depuis plus de 24 h masquée", "linked : lien : non lu", "⏎/o afficher", "x éteindre",
	} {
		if !strings.Contains(all, want) {
			t.Fatalf("%q not drawn:\n%s", want, all)
		}
	}
	for _, not := range []string{"[claude-dispatch]", "abcdef123456", "ghp_abcdefghijklmnop", "SECRET", "ancien travail", "NOCWD", "WRONGNAME", "DASHNAME", "TMPFILE", "UPPERNAME", "gone-cmd", "attach"} {
		if strings.Contains(all, not) {
			t.Fatalf("%q drawn", not)
		}
	}
	if !strings.Contains(frame, "\x1b[0;38;2;255;121;198") {
		t.Fatal("no human truecolor")
	}
	// The × on a listed session's title row, beside the whole title (its first prompt), the name
	// leading the row below; none on a closed one.
	if r := nameRow(t, m, "ask-needs"); !strings.Contains(r, "corrige le login qui boucle") || !strings.HasSuffix(strings.TrimRight(r, " │"), "×") {
		t.Fatalf("listed title row %q", r)
	}
	if r := cardRow(t, m, "ask-needs", 2); !strings.Contains(r, "ask-needs · Beta") {
		t.Fatalf("listed name row %q", r)
	}
	if r := nameRow(t, m, "closed"); strings.Contains(r, "×") {
		t.Fatalf("closed name row %q", r)
	}
	if strings.Contains(strings.ReplaceAll(frame, "\x1b[", ""), "\x1b") || strings.Contains(frame, "\x07") {
		t.Fatal("a control char reached the terminal")
	}
}

func TestRenderAgentsNarrow(t *testing.T) {
	f := newSessionsFixture(t)
	for _, wh := range [][2]int{{60, 30}, {23, 12}, {10, 5}, {1, 1}} {
		m := agentsModel(t, f, wh[0], wh[1])
		for pass := range 2 {
			lines := strings.Split(m.View().Content, "\n")
			if len(lines) != wh[1] {
				t.Fatalf("%v: %d lines", wh, len(lines))
			}
			for y, l := range lines {
				if visibleWidth(l) != wh[0] {
					t.Fatalf("%v pass %d line %d width %d", wh, pass, y, visibleWidth(l))
				}
			}
			m.ag.note, m.dirty = "affichée en haut : ask-needs", true
		}
	}
}

func TestAgentsTabKeys(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 50)
	stubPick(t, nil)
	m.tab = tabRuns
	m.dirty = true
	if !strings.Contains(plain(m.View().Content)[1], "[Runs]") {
		t.Fatalf("runs tab not shown active: %q", plain(m.View().Content)[1])
	}
	send(m, char('a'))
	if m.tab != tabAgents || !strings.Contains(plain(m.View().Content)[1], "[Agents ● 3]") {
		t.Fatal("a did not switch to Agents")
	}
	send(m, key(tea.KeyTab))
	if m.tab != tabRuns {
		t.Fatal("tab did not switch back")
	}
	send(m, char('a'))
	sel := func() string {
		s := m.agentSelection()
		if s.idx < 0 {
			return ""
		}
		return m.ag.board.cols[s.col][s.idx].ID
	}
	if sel() != "ask-needs" {
		t.Fatalf("first selection %q", sel())
	}
	send(m, key(tea.KeyDown))
	send(m, char('j'))
	if sel() != "ask-idle" {
		t.Fatalf("down: %q", sel())
	}
	send(m, key(tea.KeyRight))
	if sel() != "work-live" {
		t.Fatalf("right keeps the row, clamped: %q", sel())
	}
	send(m, char('l'))
	send(m, char('G'))
	if sel() != "stateless" {
		t.Fatalf("end: %q", sel())
	}
	send(m, char('l'))
	send(m, char('g'))
	if sel() != "closed" {
		t.Fatalf("home: %q", sel())
	}
	if cmd := send(m, char('r')); cmd == nil {
		t.Fatal("r did not poll")
	}
	if cmd := send(m, char('q')); cmd == nil || !m.quit {
		t.Fatal("q did not quit")
	}
}

func TestAgentsMouse(t *testing.T) {
	f := newSessionsFixture(t)
	m := agentsModel(t, f, 180, 18) // short: Attend ta réponse overflows
	stubPick(t, nil)
	m.View()
	tabs := findHit(m, hitTab, "")
	if tabs == nil || tabs.col != tabRuns {
		t.Fatal("no Runs tab hit")
	}
	send(m, tea.MouseClickMsg{X: tabs.x, Y: tabs.y, Button: tea.MouseLeft})
	if m.tab != tabRuns {
		t.Fatal("tab click")
	}
	var agentsTab *hit
	for i := range m.hits {
		if m.hits[i].kind == hitTab && m.hits[i].col == tabAgents {
			agentsTab = &m.hits[i]
		}
	}
	send(m, tea.MouseClickMsg{X: agentsTab.x, Y: agentsTab.y, Button: tea.MouseLeft})
	if m.tab != tabAgents {
		t.Fatal("agents tab click")
	}
	col := findHit(m, hitCol, "")
	before := m.ag.scroll[0]
	send(m, tea.MouseWheelMsg{X: col.x + 1, Y: col.y + 4, Button: tea.MouseWheelDown})
	if m.ag.scroll[0] <= before {
		t.Fatal("wheel did not scroll the column")
	}
}

func TestAgentsPollOffLoop(t *testing.T) {
	f := newFixture(t)
	sf := newSessionsFixture(t)
	called := 0
	prev := abducoList
	abducoList = func() ([]byte, error) { called++; return []byte("Active sessions (on host x)\n"), nil }
	defer func() { abducoList = prev }()
	m := newModel(f.runs, f.budget, "fixture", 120, 40)
	m.setSessionsDir(sf.dir)
	_, cmd := m.Update(pollTickMsg{})
	if cmd == nil || m.ag.status != nil || called != 0 {
		t.Fatal("sessions read on the UI goroutine")
	}
	msg := cmd()
	pm, ok := msg.(pollMsg)
	if !ok || pm.agents == nil || pm.agents.err != nil || len(pm.cards) != 3 || called != 1 {
		t.Fatalf("poll result %+v", msg)
	}
	_, next := m.Update(msg)
	if next == nil || m.ag.status == nil || !m.ag.status.ok || m.status == nil || !m.status.ok {
		t.Fatal("agents poll not applied")
	}
	// An empty abduco list: every session with a state file is gone, none is stateless.
	if len(m.ag.board.cols[colIndex("ask")]) != 0 || len(m.ag.board.cols[colIndex("work")]) != 0 {
		t.Fatalf("sessions absent from abduco still live: %v", colIDs(m.ag.board, "ask"))
	}
}

func TestAgentsSnapshotFlag(t *testing.T) {
	f := newSessionsFixture(t)
	stubAbduco(t, listing(t), nil)
	r, w, err := os.Pipe()
	mustDo(t, err)
	stdout := os.Stdout
	os.Stdout = w
	rc := run([]string{"--sessions", f.dir, "--agents-snapshot", "120", "30"})
	os.Stdout = stdout
	mustDo(t, w.Close())
	out, err := io.ReadAll(r)
	mustDo(t, err)
	if rc != 0 || !strings.Contains(string(out), "Attend ta réponse") || !strings.Contains(string(out), "ask-needs") || strings.Contains(string(out), "\x1b") {
		t.Fatalf("rc %d:\n%s", rc, out)
	}
	er, ew, err := os.Pipe()
	mustDo(t, err)
	stderr := os.Stderr
	os.Stderr = ew
	bad := run([]string{"--agents-snapshot", "x", "3"})
	open := run([]string{"--agents-snapshot", "80", "24", "open"})
	noDir := run([]string{"--sessions"})
	os.Stderr = stderr
	mustDo(t, ew.Close())
	msg, _ := io.ReadAll(er)
	if bad != 2 || open != 2 || noDir != 2 || !strings.Contains(string(msg), "usage") {
		t.Fatalf("usage rc %d %d %d: %s", bad, open, noDir, msg)
	}
}

func BenchmarkAgentsView(b *testing.B) {
	sessions := make([]*sessionInput, 80)
	states := []string{"needs-you", "waiting", "working", "done", "idle"}
	for i := range sessions {
		sessions[i] = &sessionInput{
			Name: "session-" + itoaT(i), Cwd: "/Users/u/projects/P" + itoaT(i%7), State: states[i%len(states)], Live: liveRunning,
			Intent: "mission " + strings.Repeat("longue ", 8), Notice: "étape en cours " + itoaT(i), UpdatedAt: testNow - float64(i)*120_000,
		}
	}
	m := newModel("", "", "bench", 200, 60)
	m.tab = tabAgents
	m.applyAgents(&agentsPoll{board: deriveAgents(sessions, testNow), now: testNow, clock: "12:00:00"})
	m.View()
	b.ReportAllocs()
	for i := 0; b.Loop(); i++ {
		m.tick = i%2 == 0
		m.dirty = true
		m.View()
	}
}
