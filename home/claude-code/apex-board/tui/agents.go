package main

// Agents tab: the dispatched Claude Code sessions (claude-dispatch, one abduco session each), every
// project, as a kanban (Attend ta réponse · Travaille · Figé · Terminé). Two sources merged at each
// poll: ~/.claude/session-state/<name>.json, written by hooks/session-state.js on each hook event
// (state idle / working / waiting / needs-you / done, intent, notice), and abduco's session list,
// which says whether the session still runs: one killed without SessionEnd keeps its last state in
// the file. The engine's jobs dir is no longer written since #299: it is not read. The masking and
// projectOf are deck's (home/claude-code/mods/deck/hooks/), so the deck panel and this tab agree;
// the board-only rules (liveness, stale working) say so where they sit.
//
// Read-only, as disk.go: only `<name>.json` directly under the dir's realpath, name per
// claude-dispatch's rule (validName: the writer's dotted temp files fail it); opened O_NOFOLLOW |
// O_NONBLOCK and must be a regular file (a link is refused, never read); read up to 64 KB, the
// writer's MAX_STATE (larger is reported, not parsed); control chars are drawn `?` by toCells. The
// reads and the abduco call run in the poll's Cmd, off the UI goroutine; a file that did not change
// (size, mtime, inode) keeps its parsed state.
//
// Three actions, argv only (no shell), the board stays open. Enter, `o` or a click on a card runs
// `agent-pane pick <name>`: the agent screen's top pane switches to that session. `x` on the
// selected card or a click on its × (drawn only on a session abduco lists) arms it, the footer
// asks; a second `x` or × on that card runs `agent-pane stop <name>`, which TERMs its abduco server
// (the in-flight turn is lost, the transcript stays): any other key or click disarms. `n` or a
// click on « + nouvel agent » runs `claude-dispatch --blank agent-HHMMSS` in the board's repo (a
// session with no prompt, in its own worktree as a dispatched one), then picks it: the user types
// the first prompt in the top pane, and the card takes it as its title. After any pick that
// succeeded, `agent-pane alive`: when no pane runs, osascript opens one, a Ghostty split above the
// board (ensurePane); a failure only says so in the footer.

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"

	tea "charm.land/bubbletea/v2"
)

const (
	// The writer's MAX_STATE (hooks/session-state.js): a larger file is none it wrote.
	maxStateBytes = 64 * 1024
	// Board-only: a working session silent this long is drawn Figé.
	staleMs = 15 * 60 * 1000
	// deck's BG_KEEP_MS: a finished session older than this leaves the tab.
	keepMs         = 24 * 60 * 60 * 1000
	dispatchPrefix = "[claude-dispatch]"
	// abduco answers a list at once; one that hangs must not hold the poll.
	abducoTimeout = 2 * time.Second
	pickTimeout   = 5 * time.Second
	// abduco -n returns once its server is up; claude starts behind it.
	launchTimeout = 10 * time.Second
)

const (
	tabRuns = iota
	tabAgents
)

// Liveness, from abduco's list (board-only: deck does not call abduco).
const (
	liveUnknown = iota // abduco did not answer: nothing is drawn ended
	liveRunning
	liveEnded  // mark `+`: the command exited, the session is not attachable
	liveAbsent // not listed: the session is gone
)

// nameRe: claude-dispatch's session name rule, the one session-state.js and agent-pane check.
var nameRe = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,47}$`)

// validName: only such a name is a session. It becomes the argv word of `agent-pane pick <name>`,
// so `-x` or `--help` must never get there.
func validName(s string) bool { return nameRe.MatchString(s) }

// ---- kinds ---------------------------------------------------------------------

// sessionKind: the writer's state word as the tab's kind; a word it does not write is `other`.
func sessionKind(state string) string {
	switch state {
	case "needs-you", "waiting", "idle", "working", "done":
		return state
	}
	return "other"
}

// bgOrder: what waits on you first, what ended last (deck's order of the same kinds).
var bgOrder = []string{"needs-you", "waiting", "idle", "working", "other", "done"}

type agentColumn struct{ Key, Label, Who string }

// AgentColumns: the kinds folded into four columns, in bgOrder (see agentColumnOf).
var AgentColumns = []agentColumn{
	{Key: "ask", Label: "Attend ta réponse", Who: "toi"},
	{Key: "work", Label: "Travaille", Who: "agent"},
	{Key: "stuck", Label: "Figé", Who: "à regarder"},
	{Key: "done", Label: "Terminé", Who: "24 h"},
}

// deck's core.ts SECRETS, in order: credentials masked before a line is drawn.
var secretRules = []struct {
	re *regexp.Regexp
	to string
}{
	{regexp.MustCompile(`(?i)(authorization\s*[:=]\s*)(bearer\s+|basic\s+)?\S+`), "${1}${2}•••"},
	{regexp.MustCompile(`(?i)\b(bearer)\s+[A-Za-z0-9._~+/-]{8,}=*`), "${1} •••"},
	{regexp.MustCompile(`\b(sk|pk|rk|ghp|gho|ghs|github_pat|xox[abprs])[-_][A-Za-z0-9_-]{8,}`), "•••"},
	{regexp.MustCompile(`(?i)((?:api[_-]?key|access[_-]?token|token|secret|password|passwd|pwd)\s*[=:]\s*)("[^"]*"|'[^']*'|\S+)`), "${1}•••"},
	{regexp.MustCompile(`(?i)(--(?:token|password|api-key|secret)[= ])\S+`), "${1}•••"},
	{regexp.MustCompile(`(\b[A-Z][A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD)=)\S+`), "${1}•••"},
	{regexp.MustCompile(`(?i)(\b[a-z][a-z0-9+.-]*://[^\s/:@]+:)[^\s@]+@`), "${1}•••@"},
}

func redact(s string) string {
	for _, r := range secretRules {
		s = r.re.ReplaceAllString(s, r.to)
	}
	return s
}

func oneLine(s string) string { return strings.Join(strings.Fields(s), " ") }

var worktreeRe = regexp.MustCompile(`^(.*)/\.claude/worktrees/[^/]+$`)

// projectOf is deck's: a cwd's last folder, a `<repo>/.claude/worktrees/<x>` read as `<repo>`.
func projectOf(cwd string) string {
	p := strings.TrimRight(cwd, "/")
	if m := worktreeRe.FindStringSubmatch(p); m != nil {
		p = m[1]
	}
	if name := p[strings.LastIndexByte(p, '/')+1:]; name != "" {
		return name
	}
	return cwd
}

// ---- parse ---------------------------------------------------------------------

// sessionInput: one state file as the tab reads it, and abduco's word on it. The parsed part is
// cached by the reader and never mutated: each poll sets Live on a copy (withLiveness).
type sessionInput struct {
	Name, Cwd, State, Event string
	Intent, Notice          string // one line, redacted
	UpdatedAt               float64
	Live                    int  // liveUnknown | liveRunning | liveEnded | liveAbsent
	noState                 bool // listed by abduco as running, no state file
}

func strOf(v map[string]any, k string) string {
	s, _ := v[k].(string)
	return s
}

func isoMs(s string) float64 {
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return 0
	}
	return float64(t.UnixMilli())
}

// parseSessionState: nil when it is no JSON object, lacks a string `state` or `cwd`, or its
// `name` is not the file's stem (a file copied under another name is not that session).
func parseSessionState(name string, data []byte) *sessionInput {
	var v map[string]any
	if json.Unmarshal(data, &v) != nil || v == nil {
		return nil
	}
	state, ok1 := v["state"].(string)
	cwd, ok2 := v["cwd"].(string)
	if !ok1 || !ok2 || strOf(v, "name") != name {
		return nil
	}
	intent := oneLine(redact(strOf(v, "intent")))
	if rest, ok := strings.CutPrefix(intent, dispatchPrefix); ok {
		intent = strings.TrimSpace(rest)
	}
	return &sessionInput{
		Name: name, Cwd: cwd, State: state, Event: oneLine(strOf(v, "event")),
		Intent: intent, Notice: oneLine(redact(strOf(v, "notice"))), UpdatedAt: isoMs(strOf(v, "updatedAt")),
	}
}

// abducoSession: one line of `abduco`'s list.
type abducoSession struct {
	Mark      byte // ' ', '*' (a client attached), '+' (command ended)
	Pid, Name string
}

// parseAbduco reads `abduco`'s list as agent-pane's list_sessions does: `<mark> <day>\t <date>
// <time>\t<pid>\t<name>` (its strftime holds a TAB), split on runs of TABs; a line of fewer than 3
// fields (the header) or whose name fails validName is skipped. name = last field, pid = the one
// before, mark = the first char.
func parseAbduco(out []byte) []abducoSession {
	var list []abducoSession
	for line := range strings.SplitSeq(string(out), "\n") {
		f := strings.FieldsFunc(line, func(r rune) bool { return r == '\t' })
		if len(f) < 3 || !validName(f[len(f)-1]) {
			continue
		}
		list = append(list, abducoSession{Mark: f[0][0], Pid: f[len(f)-2], Name: f[len(f)-1]})
	}
	return list
}

// abducoList runs `abduco` with no argument (the list), stdin /dev/null, env inherited (its socket
// dir); a variable so the tests never run it.
var abducoList = func() ([]byte, error) {
	if abducoBin == "" {
		return nil, errors.New("binaire absent")
	}
	ctx, cancel := context.WithTimeout(context.Background(), abducoTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, abducoBin)
	cmd.WaitDelay = time.Second
	out, err := cmd.Output()
	if ctx.Err() != nil {
		return nil, errors.New("pas de réponse en " + strconv.Itoa(int(abducoTimeout/time.Second)) + " s")
	}
	return out, err
}

// readAbduco: each listed session's liveness by name; an error when abduco did not answer.
func readAbduco() (map[string]int, error) {
	out, err := abducoList()
	if err != nil {
		return nil, err
	}
	live := map[string]int{}
	for _, s := range parseAbduco(out) {
		live[s.Name] = liveRunning
		if s.Mark == '+' {
			live[s.Name] = liveEnded
		}
	}
	return live, nil
}

// withLiveness: the sessions as this poll sees them, copies with Live set, then (sorted by name)
// those abduco lists as running without a state file. live nil (abduco failed): Live stays
// unknown, nothing is drawn ended (fail-open).
func withLiveness(sessions []*sessionInput, live map[string]int) []*sessionInput {
	out := make([]*sessionInput, 0, len(sessions)+len(live))
	seen := map[string]bool{}
	for _, s := range sessions {
		c := *s
		seen[c.Name] = true
		if live != nil {
			c.Live = liveAbsent
			if l, ok := live[c.Name]; ok {
				c.Live = l
			}
		}
		out = append(out, &c)
	}
	var extra []string
	for n, l := range live {
		if l == liveRunning && !seen[n] {
			extra = append(extra, n)
		}
	}
	slices.Sort(extra)
	for _, n := range extra {
		out = append(out, &sessionInput{Name: n, Live: liveRunning, noState: true})
	}
	return out
}

// ---- disk ----------------------------------------------------------------------

var (
	errNotRegular = errors.New("pas un fichier ordinaire : non lu")
	errLink       = errors.New("lien : non lu")
	errTooBig     = errors.New("plus de " + strconv.Itoa(maxStateBytes/1024) + " Ko : non lu")
)

// openNoFollow: a regular file, read-only, a final link refused and a FIFO not waited on.
func openNoFollow(p string) (*os.File, fs.FileInfo, error) {
	f, err := os.OpenFile(p, os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		if errors.Is(err, syscall.ELOOP) {
			return nil, nil, errLink
		}
		return nil, nil, err
	}
	fi, err := f.Stat()
	if err == nil && !fi.Mode().IsRegular() {
		err = errNotRegular
	}
	if err != nil {
		f.Close()
		return nil, nil, err
	}
	return f, fi, nil
}

func readState(p string) ([]byte, error) {
	f, fi, err := openNoFollow(p)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	if fi.Size() > maxStateBytes {
		return nil, errTooBig
	}
	data, err := io.ReadAll(io.LimitReader(f, maxStateBytes+1))
	if err != nil {
		return nil, err
	}
	if len(data) > maxStateBytes {
		return nil, errTooBig
	}
	return data, nil
}

func fileSig(fi fs.FileInfo) string {
	s := strconv.FormatInt(fi.Size(), 10) + ":" + strconv.FormatInt(fi.ModTime().UnixNano(), 10) + ":" + fi.Mode().String()
	if st, ok := fi.Sys().(*syscall.Stat_t); ok {
		s += ":" + strconv.FormatUint(st.Ino, 10) + ":" + strconv.FormatInt(int64(st.Dev), 10)
	}
	return s
}

// SessionsReader reads the session-state dir, incrementally. Used from one goroutine at a time
// (the poll).
type SessionsReader struct {
	Dir string

	base  string
	cache map[string]cachedSession
}

type cachedSession struct {
	sig  string
	sess *sessionInput // nil: not a session (parseSessionState), skipped until the file changes
}

type sessionsRead struct {
	sessions []*sessionInput
	problems []string
}

// Read is one poll: the sessions, what could not be read; the error of the dir itself (a missing
// one is no session).
func (r *SessionsReader) Read() (sessionsRead, error) {
	var out sessionsRead
	entries, err := sortedEntries(r.Dir)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			r.cache = nil
			return out, nil
		}
		return out, err
	}
	base, err := realRoot(r.Dir)
	if err != nil {
		return out, err
	}
	if base != r.base {
		r.base, r.cache = base, nil
	}
	next := map[string]cachedSession{}
	problem := func(name, msg string) { out.problems = append(out.problems, name+" : "+msg) }
	for _, e := range entries {
		// Only `<name>.json` with a valid name: anything else (a temp file, `-x.json`, pins) is
		// skipped, not counted, not reported, never read.
		name, ok := strings.CutSuffix(e.Name(), ".json")
		if !ok || !validName(name) {
			continue
		}
		// Under the dir's realpath: name holds no `/`, so the file is directly in it.
		p := filepath.Join(base, e.Name())
		fi, err := os.Lstat(p)
		switch {
		case err != nil && isGone(err):
			continue // renamed away since the listing
		case err != nil:
			problem(name, err.Error())
			continue
		case fi.Mode()&fs.ModeSymlink != 0:
			problem(name, errLink.Error())
			continue
		case !fi.Mode().IsRegular():
			problem(name, errNotRegular.Error())
			continue
		case fi.Size() > maxStateBytes:
			problem(name, strconv.FormatInt(fi.Size()/1024, 10)+" Ko, "+errTooBig.Error())
			continue
		}
		sig := fileSig(fi)
		c, hit := r.cache[name]
		if !hit || c.sig != sig {
			data, err := readState(p)
			if err != nil {
				if !isGone(err) {
					problem(name, err.Error())
				}
				continue
			}
			c = cachedSession{sig: sig, sess: parseSessionState(name, data)}
		}
		next[name] = c
		if c.sess != nil {
			out.sessions = append(out.sessions, c.sess)
		}
	}
	r.cache = next
	return out, nil
}

// ---- derive --------------------------------------------------------------------

// Agent: one card of the tab, derived from a sessionInput at a given now. ID is the session name.
// Title: the first prompt (Mission) once the session has one, its name before: a blank agent's
// name (agent-HHMMSS) says nothing of what it does.
type Agent struct {
	ID, Name, Project, Cwd, State string
	Kind, Column                  string
	Title, Mission, Current       string
	Asking, Stale                 bool
	Stoppable                     bool // abduco lists it: there is a session to stop
	UpdatedAt                     float64
	Age                           string
	Chips                         []Chip
	rows                          rowsMemo
}

type agentsBoard struct {
	cols  [4][]*Agent
	total int
	old   int
}

func colIndex(key string) int {
	return slices.IndexFunc(AgentColumns, func(c agentColumn) bool { return c.Key == key })
}

// ageText: since the last update, in words.
func ageText(now, at float64) string {
	if at <= 0 {
		return "date inconnue"
	}
	d := now - at
	if d < 60_000 {
		return "à l’instant"
	}
	mins := int(d / 60_000)
	if mins < 60 {
		return "il y a " + strconv.Itoa(mins) + " min"
	}
	if h := mins / 60; h < 24 {
		return "il y a " + strconv.Itoa(h) + " h"
	}
	return "il y a " + strconv.Itoa(mins/60/24) + " j"
}

func infoChip(key, label string) []Chip { return []Chip{{Key: key, Label: label, State: "info"}} }

// agentColumnOf: a session's kind and column. Liveness first (board-only): running in abduco
// without a state file → Figé « sans état »; ended (`+`) or gone from the list while its state is
// not done → Terminé with the reason (a done state needs none). Then the state: needs-you, waiting
// (« à toi ») and idle (« pas encore lancée ») → Attend ta réponse; working → Travaille, Figé once
// silent over staleMs (board-only); done → Terminé; a word the writer does not write → Figé, the
// word as chip.
func agentColumnOf(s *sessionInput, now float64) (kind, col string, stale bool, chips []Chip) {
	kind = sessionKind(s.State)
	switch {
	case s.noState:
		return "other", "stuck", false, infoChip("nostate", "sans état")
	case s.Live == liveEnded && kind != "done":
		return "done", "done", false, infoChip("ended", "commande terminée")
	case s.Live == liveAbsent && kind != "done":
		return "done", "done", false, infoChip("closed", "session fermée")
	}
	switch kind {
	case "needs-you":
		return kind, "ask", false, nil
	case "waiting":
		return kind, "ask", false, infoChip("waiting", "à toi")
	case "idle":
		return kind, "ask", false, infoChip("idle", "pas encore lancée")
	case "working":
		if s.UpdatedAt > 0 && now-s.UpdatedAt > staleMs {
			return kind, "stuck", true, infoChip("stale", "rien depuis "+strings.TrimPrefix(ageText(now, s.UpdatedAt), "il y a "))
		}
		return kind, "work", false, nil
	case "done":
		return kind, "done", false, nil
	}
	word := oneLine(s.State)
	if word == "" {
		word = "état vide"
	}
	return kind, "stuck", false, infoChip("other", word)
}

func deriveAgent(s *sessionInput, now float64) *Agent {
	kind, col, stale, chips := agentColumnOf(s, now)
	a := &Agent{
		ID: s.Name, Name: s.Name, Project: projectOf(s.Cwd), Cwd: s.Cwd, State: s.State,
		Kind: kind, Column: col, Mission: s.Intent, Stale: stale, UpdatedAt: s.UpdatedAt, Age: ageText(now, s.UpdatedAt), Chips: chips,
		// Not listed or abduco silent: nothing to stop, no × (fail-closed on the action).
		Stoppable: s.noState || s.Live == liveRunning || s.Live == liveEnded,
	}
	a.Title = a.Mission
	if a.Title == "" {
		a.Title = a.Name
	}
	if kind == "needs-you" {
		// The notice says what it waits on (a permission, an idle prompt).
		a.Asking, a.Current = true, s.Notice
	}
	if a.Current == a.Mission {
		a.Current = ""
	}
	return a
}

// deriveAgents: the shown cards by column, in bgOrder then newest update first (deck's sortBg),
// without the finished ones older than keepMs (deck's recentBg).
func deriveAgents(sessions []*sessionInput, now float64) agentsBoard {
	var b agentsBoard
	for _, s := range sessions {
		a := deriveAgent(s, now)
		if a.Kind == "done" && now-a.UpdatedAt > keepMs {
			b.old++
			continue
		}
		c := colIndex(a.Column)
		b.cols[c] = append(b.cols[c], a)
		b.total++
	}
	for c := range b.cols {
		slices.SortStableFunc(b.cols[c], func(x, y *Agent) int {
			if d := slices.Index(bgOrder, x.Kind) - slices.Index(bgOrder, y.Kind); d != 0 {
				return d
			}
			switch {
			case x.UpdatedAt > y.UpdatedAt:
				return -1
			case x.UpdatedAt < y.UpdatedAt:
				return 1
			}
			return strings.Compare(x.ID, y.ID)
		})
	}
	return b
}

func plural(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return strconv.Itoa(n) + " " + many
}

// hiddenText: what the footer says the tab leaves out.
func hiddenText(b agentsBoard) string {
	if b.old == 0 {
		return ""
	}
	return plural(b.old, "terminée depuis plus de 24 h masquée", "terminées depuis plus de 24 h masquées")
}

// ---- state and events ----------------------------------------------------------

type agentsView struct {
	first, nVis, areaH int
	sel                selection
	cols               [4]colLayout
}

type agentsState struct {
	reader   *SessionsReader
	board    agentsBoard
	status   *boardStatus
	problems []string
	now      float64
	sel      *selState
	scroll   [4]int
	hscroll  int
	follow   bool
	view     agentsView
	note     string // a one-off footer message: the outcome of a pick, a stop or a launch
	armed    string // the card a first `x` / × asked to stop; "" = none
	// A launch runs: a second `n` waits for it, two launches in one second would pick one name.
	launching bool
}

type agentsPoll struct {
	board    agentsBoard
	problems []string
	now      float64
	clock    string
	err      error
}

// pickMsg: the outcome of `agent-pane pick <name>`; err "" when it succeeded, then paneErr:
// ensurePane's (tried only after a pick that succeeded).
type pickMsg struct{ name, err, paneErr string }

// stopMsg: the outcome of `agent-pane stop <name>`; err "" when it succeeded.
type stopMsg struct{ name, err string }

// newAgentMsg: the outcome of `n`: the name launched ("" when none was picked), the launch's
// error, then the pick's (tried only after a launch that succeeded), then ensurePane's.
type newAgentMsg struct{ name, err, pickErr, paneErr string }

// runPick runs argv (agent-pane pick or stop, no shell): runQuiet. A variable so the tests never
// run it.
var runPick = runQuiet

// runAlive runs argv (`agent-pane alive`) as runQuiet: true on exit 0, false on exit 1 (no pane
// runs), an error otherwise. A variable so the tests never run it.
var runAlive = func(argv []string) (bool, error) {
	err := runQuiet(argv)
	var exit *exec.ExitError
	switch {
	case err == nil:
		return true, nil
	case errors.As(err, &exit) && exit.ExitCode() == 1:
		return false, nil
	}
	return false, err
}

// runOpenPane runs openPaneArgv's argv (osascript) as runQuiet. A variable so the tests never run
// it.
var runOpenPane = runQuiet

// paneScript: Ghostty's AppleScript (Ghostty.app/Contents/Resources/Ghostty.sdef, 1.3): a split
// above the focused terminal of the front window, its command item 1 of argv. The board runs in
// that terminal, so the split opens above it.
var paneScript = []string{
	"on run argv",
	`tell application "Ghostty"`,
	"set t to focused terminal of selected tab of front window",
	"set cfg to new surface configuration",
	"set command of cfg to item 1 of argv",
	"split t direction up with configuration cfg",
	"end tell",
	"end run",
}

// safePath: Ghostty hands a command to the shell, so the agent-pane path it gets is only ever a
// store path's characters.
var safePath = regexp.MustCompile(`^/[A-Za-z0-9._+/-]+$`)

// openPaneArgv: osascript with paneScript as -e lines and pane as the script's argv item: the
// path never becomes script text.
func openPaneArgv(pane string) []string {
	argv := []string{"/usr/bin/osascript"}
	for _, line := range paneScript {
		argv = append(argv, "-e", line)
	}
	return append(argv, pane)
}

// ensurePane runs after a pick that succeeded, in its Cmd: `agent-pane alive`, and when no pane
// runs a Ghostty split running agent-pane, which reads at start the target the pick just wrote.
// "" when a pane runs or one opened, else the footer's reason; the pick stands either way.
func ensurePane(pane string) string {
	alive, err := runAlive([]string{pane, "alive"})
	switch {
	case err != nil:
		return "agent-pane alive : " + err.Error()
	case alive:
		return ""
	case !safePath.MatchString(pane):
		return "chemin d'agent-pane non sûr"
	}
	if err := runOpenPane(openPaneArgv(pane)); err != nil {
		return "osascript : " + err.Error()
	}
	return ""
}

// paneNote: the footer's tail for ensurePane's reason.
func paneNote(reason string) string {
	return " · pane : " + reason + " — lance agent-pane à la main"
}

// runQuiet runs argv (no shell), stdin and stdout /dev/null, env inherited, under pickTimeout;
// the error carries stderr's first line.
func runQuiet(argv []string) error {
	ctx, cancel := context.WithTimeout(context.Background(), pickTimeout)
	defer cancel()
	var stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Stderr = &stderr
	cmd.WaitDelay = time.Second
	err := cmd.Run()
	switch {
	case err == nil:
		return nil
	case ctx.Err() != nil:
		return errors.New("pas de réponse en " + strconv.Itoa(int(pickTimeout/time.Second)) + " s")
	}
	if line, _, _ := strings.Cut(strings.TrimSpace(stderr.String()), "\n"); line != "" {
		return errors.New(oneLine(line))
	}
	return err
}

// runLaunch runs argv in dir (claude-dispatch --blank <name>, no shell), stdin and stdout
// /dev/null, env inherited; the error carries stderr's first line. stderr is an os.Pipe handed to
// the child as is, not runPick's buffer: abduco's server outlives the call and keeps the fd unless
// built with NDEBUG, and Wait would sit on a copied pipe until WaitDelay. Read only after a
// failure, under a deadline. A variable so the tests never run it.
var runLaunch = func(dir string, argv []string) error {
	r, w, err := os.Pipe()
	if err != nil {
		return err
	}
	defer r.Close()
	ctx, cancel := context.WithTimeout(context.Background(), launchTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Dir, cmd.Stderr = dir, w
	cmd.WaitDelay = time.Second
	err = cmd.Start()
	w.Close()
	if err == nil {
		err = cmd.Wait()
	}
	switch {
	case err == nil:
		return nil
	case ctx.Err() != nil:
		return errors.New("pas de réponse en " + strconv.Itoa(int(launchTimeout/time.Second)) + " s")
	}
	_ = r.SetReadDeadline(time.Now().Add(200 * time.Millisecond))
	head, _ := io.ReadAll(io.LimitReader(r, 4096))
	if line, _, _ := strings.Cut(strings.TrimSpace(string(head)), "\n"); line != "" {
		return errors.New(oneLine(line))
	}
	return err
}

// repoOf: the repo apex-board.sh passed, read back from its runs dir `<repo>/.claude/output/apex`
// (absolute, pwd -P); "" for any other dir: no repo, no launch.
func repoOf(runsDir string) string {
	if !filepath.IsAbs(runsDir) {
		return ""
	}
	repo, ok := strings.CutSuffix(filepath.Clean(runsDir), "/.claude/output/apex")
	if !ok {
		return ""
	}
	return repo
}

// agentName: `agent-HHMMSS` at t, else the first of `-2` … `-99` after it that taken refuses;
// "" when all are taken. Always validName's: 15 characters at most.
func agentName(t time.Time, taken func(string) bool) string {
	base := "agent-" + t.Format("150405")
	for i := 1; i < 100; i++ {
		name := base
		if i > 1 {
			name += "-" + strconv.Itoa(i)
		}
		if !taken(name) {
			return name
		}
	}
	return ""
}

// nameTaken: a name abduco lists, or with a state file or a worktree left by an earlier session
// (`claude --worktree <name>` would reuse it): another session's, not this one's. A path that
// cannot be checked counts as taken.
func nameTaken(repo, sessionsDir string, listed map[string]bool) func(string) bool {
	exists := func(p string) bool {
		_, err := os.Lstat(p)
		return !errors.Is(err, fs.ErrNotExist)
	}
	return func(n string) bool {
		return listed[n] || (sessionsDir != "" && exists(filepath.Join(sessionsDir, n+".json"))) ||
			exists(filepath.Join(repo, ".claude", "worktrees", n))
	}
}

// launchAgent runs in newAgentCmd's Cmd: a free name, `claude-dispatch --blank <name>` in repo,
// then `agent-pane pick <name>`, then ensurePane. abduco silent: its list is not checked,
// `abduco -n` refuses a live session of that name itself (create-session: EADDRINUSE).
func launchAgent(bin, pane, repo, sessionsDir string, now time.Time) newAgentMsg {
	var listed map[string]bool
	if out, err := abducoList(); err == nil {
		listed = map[string]bool{}
		for _, s := range parseAbduco(out) {
			listed[s.Name] = true
		}
	}
	name := agentName(now, nameTaken(repo, sessionsDir, listed))
	if !validName(name) {
		return newAgentMsg{err: "aucun nom libre pour " + now.Format("150405")}
	}
	if err := runLaunch(repo, []string{bin, "--blank", name}); err != nil {
		return newAgentMsg{name: name, err: err.Error()}
	}
	if pane == "" {
		return newAgentMsg{name: name, pickErr: "binaire absent"}
	}
	if err := runPick([]string{pane, "pick", name}); err != nil {
		return newAgentMsg{name: name, pickErr: err.Error()}
	}
	return newAgentMsg{name: name, paneErr: ensurePane(pane)}
}

// setSessionsDir turns the Agents tab on, reading dir at each poll.
func (m *Model) setSessionsDir(dir string) {
	if dir == "" {
		m.ag.reader = nil
		return
	}
	m.ag.reader = &SessionsReader{Dir: dir}
}

// pollAgents runs in the poll's Cmd goroutine: the state files, then abduco's list.
func pollAgents(r *SessionsReader) *agentsPoll {
	if r == nil {
		return nil
	}
	read, err := r.Read()
	t := time.Now()
	if err != nil {
		return &agentsPoll{err: err}
	}
	problems := read.problems
	live, aerr := readAbduco()
	if aerr != nil {
		problems = append(slices.Clip(problems), "abduco : "+oneLine(aerr.Error())+" : sessions non vérifiées")
	}
	now := float64(t.UnixMilli())
	return &agentsPoll{board: deriveAgents(withLiveness(read.sessions, live), now), problems: problems, now: now, clock: t.Format("15:04:05")}
}

func (m *Model) applyAgents(p *agentsPoll) {
	if p == nil {
		return
	}
	a := &m.ag
	m.dirty = true
	if p.err != nil {
		a.status = &boardStatus{err: "session-state/ illisible : " + p.err.Error()}
		return
	}
	a.board, a.problems, a.now = p.board, p.problems, p.now
	a.status = &boardStatus{ok: true, count: p.board.total, time: p.clock}
}

// pickCmd: `agent-pane pick <name>` then ensurePane in a Cmd, off the UI goroutine; the footer
// says the outcome (pickMsg). The name is checked again here (the readers already skip others): it
// is an argv word.
func (m *Model) pickCmd(name string) tea.Cmd {
	if !validName(name) {
		return nil
	}
	if agentPaneBin == "" {
		m.ag.note, m.dirty = "agent-pane : binaire absent, rien lancé", true
		return nil
	}
	pane := agentPaneBin
	argv := []string{pane, "pick", name}
	return func() tea.Msg {
		if err := runPick(argv); err != nil {
			return pickMsg{name: name, err: err.Error()}
		}
		return pickMsg{name: name, paneErr: ensurePane(pane)}
	}
}

func (m *Model) applyPick(msg pickMsg) {
	switch {
	case msg.err != "":
		m.ag.note = "agent-pane pick " + msg.name + " : " + msg.err
	case msg.paneErr != "":
		m.ag.note = "affichée en haut : " + msg.name + paneNote(msg.paneErr)
	default:
		m.ag.note = "affichée en haut : " + msg.name
	}
	m.dirty = true
}

// stopCmd: `agent-pane stop <name>` in a Cmd, as pickCmd; the footer says the outcome (stopMsg).
func (m *Model) stopCmd(name string) tea.Cmd {
	if !validName(name) {
		return nil
	}
	if agentPaneBin == "" {
		m.ag.note, m.dirty = "agent-pane : binaire absent, rien éteint", true
		return nil
	}
	argv := []string{agentPaneBin, "stop", name}
	return func() tea.Msg {
		if err := runPick(argv); err != nil {
			return stopMsg{name: name, err: err.Error()}
		}
		return stopMsg{name: name}
	}
}

// applyStop: the footer says it, and a poll at once moves the card (session fermée).
func (m *Model) applyStop(msg stopMsg) tea.Cmd {
	if msg.err != "" {
		m.ag.note = "agent-pane stop " + msg.name + " : " + msg.err
	} else {
		m.ag.note = "éteinte : " + msg.name
	}
	m.dirty = true
	return m.pollCmd()
}

// newAgentCmd: `n` or « + nouvel agent »: launchAgent in a Cmd, off the UI goroutine; the footer
// says the outcome (newAgentMsg). Nothing runs without the binary, without a repo, or while a
// launch runs.
func (m *Model) newAgentCmd() tea.Cmd {
	a := &m.ag
	m.dirty = true
	if a.launching {
		a.note = "nouvel agent : un lancement est en cours"
		return nil
	}
	if dispatchBin == "" {
		a.note = "claude-dispatch : binaire absent, rien lancé"
		return nil
	}
	repo := repoOf(m.runsDir)
	if repo == "" {
		a.note = "nouvel agent : dépôt inconnu, rien lancé"
		return nil
	}
	sessionsDir := ""
	if a.reader != nil {
		sessionsDir = a.reader.Dir
	}
	bin, pane := dispatchBin, agentPaneBin
	a.launching, a.note = true, "nouvel agent : lancement…"
	return func() tea.Msg { return launchAgent(bin, pane, repo, sessionsDir, time.Now()) }
}

// applyNewAgent: the footer says it, the new card is selected, and a poll at once draws it.
func (m *Model) applyNewAgent(msg newAgentMsg) tea.Cmd {
	a := &m.ag
	a.launching, m.dirty = false, true
	switch {
	case msg.name == "":
		a.note = "nouvel agent : " + msg.err
	case msg.err != "":
		a.note = "claude-dispatch --blank " + msg.name + " : " + msg.err
	case msg.pickErr != "":
		a.note = "nouvel agent : " + msg.name + " · agent-pane pick : " + msg.pickErr
	case msg.paneErr != "":
		a.note = "nouvel agent : " + msg.name + paneNote(msg.paneErr)
	default:
		a.note = "nouvel agent : " + msg.name
	}
	if msg.name != "" && msg.err == "" {
		a.sel, a.follow = &selState{id: msg.name}, true
	}
	return m.pollCmd()
}

// stopAgent: the first `x` / × on a card arms it, the second on the same card (armed: the one
// armed before this event) stops it.
func (m *Model) stopAgent(ag *Agent, armed string) tea.Cmd {
	a := &m.ag
	m.dirty = true
	switch {
	case !ag.Stoppable:
		a.note = ag.Name + " : pas de session à éteindre"
		return nil
	case armed != ag.ID:
		a.armed, a.note = ag.ID, "éteindre "+ag.Name+" ? × ou x encore pour confirmer · Échap annule"
		return nil
	}
	return m.stopCmd(ag.ID)
}

// disarm: every event but the confirming one drops the arm; the armed name, for that one.
func (m *Model) disarm() string {
	armed := m.ag.armed
	if armed != "" {
		m.ag.armed, m.dirty = "", true
	}
	return armed
}

func (m *Model) setTab(t int) {
	m.tab, m.ag.note, m.hits, m.dirty = t, "", nil, true
}

func (m *Model) agentSelection() selection {
	a := &m.ag
	cols := &a.board.cols
	if a.sel != nil {
		if a.sel.id != "" {
			for c := range cols {
				if i := slices.IndexFunc(cols[c], func(x *Agent) bool { return x.ID == a.sel.id }); i >= 0 {
					return selection{c, i}
				}
			}
		}
		col := clamp(a.sel.col, 0, len(cols)-1)
		if n := len(cols[col]); n > 0 {
			return selection{col, clamp(a.sel.idx, 0, n-1)}
		}
		return selection{col, -1}
	}
	for c := range cols {
		if len(cols[c]) > 0 {
			return selection{c, 0}
		}
	}
	return selection{0, -1}
}

func (m *Model) pickAgent(c, i int) {
	a := &m.ag
	list := a.board.cols[c]
	idx := -1
	if len(list) > 0 {
		idx = clamp(i, 0, len(list)-1)
	}
	a.sel = &selState{col: c, idx: max(idx, 0)}
	if idx >= 0 {
		a.sel.id = list[idx].ID
	}
	a.follow, m.dirty = true, true
}

func (m *Model) keyAgents(ev string) tea.Cmd {
	a := &m.ag
	if a.note != "" {
		a.note, m.dirty = "", true
	}
	armed := m.disarm()
	sel := m.agentSelection()
	row := max(sel.idx, 0)
	n := len(AgentColumns)
	switch ev {
	case "q":
		m.quit = true
		return tea.Quit
	case "a", "tab":
		m.setTab(tabRuns)
	case "left", "h":
		m.pickAgent(max(0, sel.col-1), row)
	case "right", "l":
		m.pickAgent(min(n-1, sel.col+1), row)
	case "up", "k":
		m.pickAgent(sel.col, sel.idx-1)
	case "down", "j":
		m.pickAgent(sel.col, sel.idx+1)
	case "home", "g":
		m.pickAgent(sel.col, 0)
	case "end", "G":
		m.pickAgent(sel.col, far)
	case "pgup":
		m.pickAgent(sel.col, sel.idx-pageCards)
	case "pgdn", "space":
		m.pickAgent(sel.col, sel.idx+pageCards)
	case "enter", "o":
		if sel.idx >= 0 {
			return m.pickCmd(a.board.cols[sel.col][sel.idx].ID)
		}
	case "x":
		if sel.idx >= 0 {
			return m.stopAgent(a.board.cols[sel.col][sel.idx], armed)
		}
	case "n":
		return m.newAgentCmd()
	case "r":
		return m.pollCmd()
	}
	return nil
}

// clickAgents: h nil = a click on nothing, which only disarms.
func (m *Model) clickAgents(h *hit) tea.Cmd {
	a := &m.ag
	armed := m.disarm()
	if armed != "" {
		a.note = "" // the confirm question
	}
	if h == nil {
		return nil
	}
	switch h.kind {
	case hitTab:
		m.setTab(h.col)
	case hitCard:
		a.sel = &selState{col: h.col, idx: h.idx, id: h.id}
		a.note, a.follow, m.dirty = "", true, true
		return m.pickCmd(h.id)
	case hitStop:
		if h.col < 0 || h.col >= len(a.board.cols) || h.idx < 0 || h.idx >= len(a.board.cols[h.col]) || a.board.cols[h.col][h.idx].ID != h.id {
			return nil // the board moved since the frame
		}
		a.sel = &selState{col: h.col, idx: h.idx, id: h.id}
		a.follow, m.dirty = true, true
		return m.stopAgent(a.board.cols[h.col][h.idx], armed)
	case hitNew:
		return m.newAgentCmd()
	}
	return nil
}

// wheelAgents: as wheel on the runs board, for the agents columns.
func (m *Model) wheelAgents(h *hit, dir int) {
	a := &m.ag
	if (h.kind != hitCard && h.kind != hitCol && h.kind != hitStop) || h.col < 0 || h.col >= len(AgentColumns) {
		return
	}
	c := h.col
	lay, areaH := a.view.cols[c], a.view.areaH
	s := clamp(a.scroll[c]+dir*wheelLines, 0, max(0, lay.total-areaH))
	if s == a.scroll[c] {
		return
	}
	a.scroll[c], a.follow, m.dirty = s, false, true
	sel := a.view.sel
	if sel.col != c || sel.idx < 0 || sel.idx >= len(lay.tops) {
		return
	}
	shown := func(i int) bool { return lay.tops[i] < s+areaH && lay.tops[i]+lay.heights[i] > s }
	if shown(sel.idx) {
		return
	}
	pick := -1
	for k := range lay.tops {
		i := k
		if dir < 0 {
			i = len(lay.tops) - 1 - k
		}
		if shown(i) {
			pick = i
			break
		}
	}
	if pick >= 0 {
		a.sel = &selState{col: c, idx: pick, id: lay.ids[pick]}
		a.view.sel = selection{c, pick}
	}
}

// ---- view ----------------------------------------------------------------------

var keysAgents = "←→↑↓ naviguer · ⏎/o afficher en haut · x éteindre · r relire · a runs · q quitter"

// newAgentLabel: the footer's button, first on the keys row, under a hitNew.
const newAgentLabel = "+ nouvel agent (n)"

// stopShown: the card draws its × (a listed session, room for the title besides it). The × sits
// on the title's first row, at the last inner cell: x+cw-3 on screen, under a hitStop.
func (a *Agent) stopShown(cw int) bool { return a.Stoppable && cw-4 >= 6 }

// agentRows: rows of exactly cw cells: rounded box, title (and ×; the first prompt on up to two
// rows, else the name), the name once the title is the prompt, project and age, the notice (or
// what it does), chips. armed lights the ×.
func agentRows(a *Agent, cw int, selected, armed bool) *rowsMemo {
	if m := &a.rows; m.rows != nil && m.cw == cw && m.sel == selected && m.armed == armed {
		return m
	}
	bg := P.card
	if selected {
		bg = P.cardHover
	}
	border := P.line
	switch {
	case selected:
		border = P.active
	case a.Column == "ask":
		border = P.human
	case a.Column == "work":
		border = mix(P.active, P.line, 0.35)
	case a.Column == "stuck":
		border = mix(P.changes, P.line, 0.45)
	}
	iw := max(1, cw-4)
	st := func(f rgb) style { return fgbg(f, bg) }
	var body [][]cell

	var top []cell
	if a.Column == "work" {
		top = toCells("● ", st(P.active), top)
	}
	dotOff := cell{ch: "●", w: 1, st: st(P.faint)}
	// The title's rows: room for the × on the first; the name never wraps, the prompt on two rows.
	tw := iw - cellsWidth(top)
	if a.stopShown(cw) {
		tw -= 2
	}
	title := [][]cell{fitCells(cellsOf(a.Title, st(P.text).bold()), tw)}
	if a.Title != a.Name && tw > 0 {
		title = wrapText(a.Title, tw, 2, st(P.text).bold())
	}
	top = append(top, title[0]...)
	if a.stopShown(cw) {
		top = append(top, spaces(iw-cellsWidth(top)-1, bgOnly(bg))...)
		xc := P.muted
		if armed {
			xc = P.human
		}
		top = toCells("×", st(xc).bold(), top)
	}
	body = append(body, top)
	body = append(body, title[1:]...)

	// The project row; once the prompt is the title, the name leads it (the session's handle).
	where := a.Project
	if a.Title != a.Name {
		where = a.Name
		if a.Project != "" {
			where += " · " + a.Project
		}
	}
	age := cellsOf(a.Age, st(P.muted))
	if room := iw - cellsWidth(age) - 1; room >= 4 {
		line := fitCells(cellsOf(where, st(P.faint)), room)
		line = append(line, spaces(iw-cellsWidth(line)-cellsWidth(age), bgOnly(bg))...)
		body = append(body, append(line, age...))
	} else {
		body = append(body, fitCells(cellsOf(where, st(P.faint)), iw), fitCells(age, iw))
	}
	if a.Current != "" {
		if a.Asking {
			body = append(body, cellsOf(strings.Repeat(cardBox.Top, iw), st(P.line)))
			body = append(body, wrapText(a.Current, iw, 3, st(P.human))...)
		} else {
			body = append(body, wrapText(a.Current, iw, 2, st(P.muted))...)
		}
	}
	if len(a.Chips) > 0 {
		body = append(body, chipLines(a.Chips, iw, bg)...)
	}
	rows := boxRows(body, cw, iw, border, bg)
	if a.Column == "done" {
		for _, r := range rows {
			for i := range r {
				r[i] = fadeCell(r[i], P.bg, 0.72)
			}
		}
	}
	a.rows = rowsMemo{cw: cw, sel: selected, armed: armed, rows: rows, dotOff: dotOff}
	return &a.rows
}

// renderAgents is render for the Agents tab: same header, columns and footer layout.
func (m *Model) renderAgents() {
	W, H := max(1, m.width), max(1, m.height)
	m.g.reset(W, H, P.bg)
	g := m.g
	m.hits = m.hits[:0]
	a := &m.ag
	sel := m.agentSelection()
	view := agentsView{sel: sel}

	tall := H >= 16
	y := 0
	if tall {
		y = 1
	}
	m.drawHeader(g, W, y)
	y++
	banner := a.problems
	if len(banner) > 3 {
		banner = append(banner[:3:3], "+"+strconv.Itoa(len(a.problems)-3))
	}
	for _, p := range banner {
		g.put(margin, y, fitCells(cellsOf(p, fg(P.human)), W-2*margin))
		y++
	}
	y++
	headY := y
	cardsTop := headY + 2
	footerTop := H - 1
	if tall {
		footerTop = H - 2
	}
	areaH := footerTop - cardsTop
	if tall {
		areaH--
	}
	areaH = max(0, areaH)
	view.areaH = areaH

	n := len(AgentColumns)
	inner := max(1, W-2*margin)
	nVis := clamp((inner+gap)/(minCol+gap), 1, n)
	span := inner - gap*(nVis-1)
	base := max(1, span/nVis)
	extra := max(0, span-base*nVis)
	first := clamp(clamp(a.hscroll, sel.col-nVis+1, sel.col), 0, n-nVis)
	view.first, view.nVis = first, nVis
	a.hscroll = first

	for v := range nVis {
		c := first + v
		col := AgentColumns[c]
		cw := base
		if v < extra {
			cw++
		}
		x := margin + v*(base+gap) + min(v, extra)
		list := a.board.cols[c]
		lay := colLayout{}
		items := make([]*rowsMemo, len(list))
		top := 0
		for i, ag := range list {
			rows := agentRows(ag, cw, c == sel.col && i == sel.idx, ag.ID == a.armed)
			items[i] = rows
			lay.tops = append(lay.tops, top)
			lay.heights = append(lay.heights, len(rows.rows))
			lay.ids = append(lay.ids, ag.ID)
			top += len(rows.rows)
		}
		total := top
		if len(list) == 0 {
			total++
		}
		lay.total = total
		view.cols[c] = lay
		s := a.scroll[c]
		if a.follow && c == sel.col && sel.idx >= 0 && sel.idx < len(items) {
			pt, ph := lay.tops[sel.idx], lay.heights[sel.idx]
			if pt+ph > s+areaH {
				s = pt + ph - areaH
			}
			if pt < s {
				s = pt
			}
		}
		s = clamp(s, 0, max(0, total-areaH))
		a.scroll[c] = s

		var countCells []cell
		if len(list) > 0 {
			countCells = cellsOf(strconv.Itoa(len(list)), fg(P.muted))
		}
		lc, ruleC := P.text, P.line
		switch col.Key {
		case "ask":
			lc, ruleC = P.human, mix(P.human, P.bg, 0.55)
		case "stuck":
			lc = P.changes
		case "done":
			lc = P.merged
		}
		hx := g.putMax(x, headY, cellsOf(col.Label, fg(lc).bold()), x+cw)
		whoMax := x + cw - (hx + 1)
		if len(countCells) > 0 {
			whoMax -= cellsWidth(countCells) + 1
		}
		if whoMax > 0 {
			g.put(hx+1, headY, fitCells(cellsOf(col.Who, fg(P.faint)), whoMax))
		}
		if len(countCells) > 0 {
			g.putMax(x+cw-cellsWidth(countCells), headY, countCells, x+cw)
		}
		g.put(x, headY+1, cellsOf(strings.Repeat(cardBox.Top, cw), fg(ruleC)))
		if s > 0 && cw >= 2 {
			g.put(x+cw-2, headY+1, cellsOf("↑", fg(P.muted)))
		}
		if s+areaH < total {
			g.put(x+cw-1, headY+1, cellsOf("↓", fg(P.muted)))
		}
		m.hits = append(m.hits, hit{x: x, y: headY, w: cw, h: max(1, cardsTop+areaH-headY), kind: hitCol, col: c})

		for i, rows := range items {
			firstRow, shown, stopY := -1, 0, -1
			for r, row := range rows.rows {
				at := lay.tops[i] + r - s
				if at < 0 || at >= areaH {
					continue
				}
				g.putMax(x, cardsTop+at, row, x+cw)
				if r == 1 && list[i].stopShown(cw) {
					stopY = cardsTop + at
				}
				if r == 1 && !m.tick && list[i].Column == "work" {
					g.putMax(x+2, cardsTop+at, []cell{rows.dotOff}, x+cw)
				}
				if firstRow < 0 {
					firstRow = cardsTop + at
				}
				shown++
			}
			if shown > 0 {
				m.hits = append(m.hits, hit{x: x, y: firstRow, w: cw, h: shown, kind: hitCard, id: lay.ids[i], col: c, idx: i})
			}
			if stopY >= 0 {
				// After the card's hit, so it wins there (hitAt: last first); the cells around the × too.
				m.hits = append(m.hits, hit{x: x + cw - 4, y: stopY, w: 3, h: 1, kind: hitStop, id: lay.ids[i], col: c, idx: i})
			}
		}
		if at := top - s; len(list) == 0 && at >= 0 && at < areaH {
			g.putMax(x+1, cardsTop+at, cellsOf("—", fg(P.faint)), x+cw)
		}
	}
	if first > 0 {
		g.put(0, headY, cellsOf("‹", fg(P.muted)))
	}
	if first+nVis < n {
		g.put(W-1, headY, cellsOf("›", fg(P.muted)))
	}

	// Footer: the note or what is hidden, then the keys (and the hidden count when short).
	info := cellsOf(hiddenText(a.board), fg(P.muted))
	if a.note != "" {
		info = cellsOf(a.note, fg(P.human))
	}
	if tall {
		g.put(margin, H-2, fitCells(info, W-2*margin))
		info = nil
	}
	if nVis < n {
		info = cellsOf("colonnes "+strconv.Itoa(first+1)+"-"+strconv.Itoa(first+nVis)+"/"+strconv.Itoa(n), fg(P.faint))
	}
	btn := cellsOf(newAgentLabel, fg(P.active).bold())
	keys := toCells(" · "+keysAgents, fg(P.faint), slices.Clone(btn))
	kw := W - 2*margin
	if len(info) > 0 {
		kw -= min(cellsWidth(info), kw/2) + 2
	}
	shownKeys := fitCells(keys, max(0, kw))
	g.put(margin, H-1, shownKeys)
	if w := min(cellsWidth(btn), cellsWidth(shownKeys)); w > 0 {
		m.hits = append(m.hits, hit{x: margin, y: H - 1, w: w, h: 1, kind: hitNew})
	}
	if len(info) > 0 && kw > 8 {
		iw := W - 2*margin - kw - 2
		ic := fitCells(info, iw)
		g.put(W-margin-cellsWidth(ic), H-1, ic)
	}

	a.view = view
	m.frame = frameOf(g)
	m.dirty = false
}

// agentsSnapshot: one frame of the Agents tab read from sessionsDir (and abduco), ANSI stripped,
// no terminal (for the coordinator and the check): --agents-snapshot <width> <height>.
func agentsSnapshot(args []string, sessionsDir string, out io.Writer) int {
	if len(args) != 2 {
		return -1
	}
	w, err1 := strconv.Atoi(args[0])
	h, err2 := strconv.Atoi(args[1])
	if err1 != nil || err2 != nil || w < 1 || h < 1 {
		return -1
	}
	m := newModel("", "", "", w, h)
	m.setSessionsDir(sessionsDir)
	m.tab = tabAgents
	m.applyAgents(pollAgents(m.ag.reader))
	var sb strings.Builder
	for l := range strings.SplitSeq(m.View().Content, "\n") {
		sb.WriteString(strings.TrimRight(stripAnsi(l), " "))
		sb.WriteByte('\n')
	}
	if _, err := io.WriteString(out, sb.String()); err != nil {
		return 1
	}
	return 0
}
