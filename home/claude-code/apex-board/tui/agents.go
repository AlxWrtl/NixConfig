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
// Three actions, argv only (no shell), the board stays open. Enter, `o` or a click on a card shows
// that session in a Ghostty pane: the live pane already showing it gets the focus, else a click on
// a pane of the board's tab puts it there (one pane per terminal, several agents at once; see
// « placement » below); outside Ghostty, `agent-pane pick <name>` on the board's own pane. `x` on
// the selected card or a click on its × (drawn only on a session abduco lists) arms it, the footer
// asks; a second `x` or × on that card runs `agent-pane stop <name>`, which TERMs its abduco server
// (the in-flight turn is lost, the transcript stays): any other key or click disarms. `n` or a
// click on « + nouvel agent » runs `claude-dispatch --blank agent-HHMMSS` in the board's repo (a
// session with no prompt, in its own worktree as a dispatched one), then shows it as a card click
// does (placement mode for the new name): the user types the first prompt in its pane, and the
// card takes it as its title. `N` starts a generic one, in no repo: `abduco -n <name> claude
// --name <name>` in a new `~/agents/<name>` (launchGeneric). `c` on a closed agent (its claude
// exited, abduco no longer lists it) brings its conversation back: `abduco -n <name> claude
// --continue --name <name>` in its worktree or generic dir, then the same show (resumeAgent).
//
// Ghostty not answering, the fallback pick (pickTop) keeps one pane per board: pick and alive pass
// `--slot <tty>` (paneSlot, the board's tty name); when no pane runs, osascript opens one, a split
// above the board running `agent-pane --slot <tty>` (ensurePane); a failure only says so in the
// footer; no tty, no slot: the one global pane.
//
// With the board's repo known (tabRepo), the cards are grouped by project as an accordion: the
// expanded group fills the kanban, the others one header line each; `p` / `P` or a click on a
// header expands another (agentGroups).

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
	Resumable                     bool // abduco answered without it, cwd its worktree or generic dir: `c` continues it
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
		// Absent only: an ended (`+`) session still holds its name (abduco -n would refuse it).
		Resumable: !s.noState && s.Live == liveAbsent && (isWorktreeOf(s.Cwd, s.Name) || isGenericOf(s.Cwd, s.Name)),
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

// ---- groups --------------------------------------------------------------------

const (
	groupProject = iota // a repo (a worktree read as its repo) or a cwd
	groupGeneric        // genericRoot/<name>
	groupNone           // no cwd known (a session without state file)
)

// The keys of the two groups that are no path; a path key never starts with NUL.
const (
	genericKey = "\x00generic"
	noneKey    = "\x00none"
)

// agentGroup: one fold of the accordion, its cards by column in the board's order.
type agentGroup struct {
	key, label string
	kind       int
	cols       [4][]*Agent
	n          int
}

func (g *agentGroup) has(id string) bool {
	for _, col := range g.cols {
		if slices.ContainsFunc(col, func(a *Agent) bool { return a.ID == id }) {
			return true
		}
	}
	return false
}

// tabRepo: the board's project, repoOf(runsDir) with a worktree read as its repo (apex-board.sh
// passes the toplevel of the worktree it runs in); "" without one: no groups, one kanban of all.
func tabRepo(runsDir string) string {
	repo := repoOf(runsDir)
	if m := worktreeRe.FindStringSubmatch(repo); m != nil && m[1] != "" {
		return m[1]
	}
	return repo
}

// groupKeyOf: an agent's group, its worktree's repo (the absolute path, not the basename, so two
// repos of one name stay apart), else Génériques for genericRoot/<name>, else its cwd; no cwd:
// « sans dossier ».
func groupKeyOf(a *Agent) (string, int) {
	switch {
	case a.Cwd == "":
		return noneKey, groupNone
	case isGenericOf(a.Cwd, a.Name):
		return genericKey, groupGeneric
	}
	p := a.Cwd
	if filepath.IsAbs(p) {
		p = filepath.Clean(p)
	}
	if m := worktreeRe.FindStringSubmatch(p); m != nil && m[1] != "" {
		p = m[1]
	}
	return p, groupProject
}

// labelGroups: each project's last folder; two of one name get their parent's too, and the full
// path if that is not enough.
func labelGroups(gs []*agentGroup) {
	counts := func() map[string]int {
		n := map[string]int{}
		for _, g := range gs {
			n[g.label]++
		}
		return n
	}
	for _, g := range gs {
		g.label = filepath.Base(g.key)
	}
	n := counts()
	for _, g := range gs {
		if n[g.label] > 1 {
			g.label = filepath.Base(filepath.Dir(g.key)) + "/" + g.label
		}
	}
	n = counts()
	for _, g := range gs {
		if n[g.label] > 1 {
			g.label = g.key
		}
	}
}

// groupAgents: the board's cards by group, in the accordion's order: the tab's project first
// (always, even empty), the other projects by label, Génériques, then « sans dossier » (each only
// when it holds a card).
func groupAgents(b *agentsBoard, tab string) []*agentGroup {
	tg := &agentGroup{key: tab, kind: groupProject}
	projects := []*agentGroup{tg}
	byKey := map[string]*agentGroup{tab: tg}
	generic := &agentGroup{key: genericKey, label: "Génériques", kind: groupGeneric}
	none := &agentGroup{key: noneKey, label: "sans dossier", kind: groupNone}
	for c := range b.cols {
		for _, a := range b.cols[c] {
			key, kind := groupKeyOf(a)
			g := byKey[key]
			switch {
			case kind == groupGeneric:
				g = generic
			case kind == groupNone:
				g = none
			case g == nil:
				g = &agentGroup{key: key, kind: groupProject}
				byKey[key] = g
				projects = append(projects, g)
			}
			g.cols[c] = append(g.cols[c], a)
			g.n++
		}
	}
	labelGroups(projects)
	rest := projects[1:]
	slices.SortFunc(rest, func(x, y *agentGroup) int {
		if d := strings.Compare(strings.ToLower(x.label), strings.ToLower(y.label)); d != 0 {
			return d
		}
		if d := strings.Compare(x.label, y.label); d != 0 {
			return d
		}
		return strings.Compare(x.key, y.key)
	})
	out := projects
	for _, g := range []*agentGroup{generic, none} {
		if g.n > 0 {
			out = append(out, g)
		}
	}
	return out
}

// agentGroups: the groups and the expanded one's index; nil, -1 without a tab repo (one kanban).
// The selected card's group is the expanded one (a launch or a resume selects its card by name:
// its group opens once a poll draws it); else the last expanded key, else the tab's project. The
// key is kept, so a poll keeps the group.
func (m *Model) agentGroups() ([]*agentGroup, int) {
	a := &m.ag
	tab := tabRepo(m.runsDir)
	if tab == "" {
		return nil, -1
	}
	gs := groupAgents(&a.board, tab)
	open := max(0, slices.IndexFunc(gs, func(g *agentGroup) bool { return g.key == a.group }))
	if a.sel != nil && a.sel.id != "" {
		if i := slices.IndexFunc(gs, func(g *agentGroup) bool { return g.has(a.sel.id) }); i >= 0 {
			open = i
		}
	}
	a.group = gs[open].key
	return gs, open
}

// shownCols: the columns the kanban draws and the keys move in, the expanded group's (all cards
// without groups).
func (m *Model) shownCols() *[4][]*Agent {
	gs, open := m.agentGroups()
	if gs == nil {
		return &m.ag.board.cols
	}
	return &gs[open].cols
}

// openGroup expands key's group: no card selected in it yet, its columns from the top.
func (m *Model) openGroup(key string) {
	a := &m.ag
	a.group, a.sel, a.scroll, a.hscroll = key, nil, [4]int{}, 0
	a.follow, m.dirty = true, true
}

// stepGroup: `p` (+1) / `P` (-1), the next / previous group, wrapping.
func (m *Model) stepGroup(d int) {
	gs, open := m.agentGroups()
	if len(gs) < 2 {
		return
	}
	m.openGroup(gs[(open+d+len(gs))%len(gs)].key)
}

// groupLine: a group's header, `▸ <label> · <n>` (`▾` expanded), then each non-empty column's
// count.
func groupLine(g *agentGroup, open bool) []cell {
	arrow, st := "▸ ", fg(P.muted)
	if open {
		arrow, st = "▾ ", fg(P.text).bold()
	}
	out := toCells(g.label+" · "+strconv.Itoa(g.n), st, cellsOf(arrow, fg(P.active)))
	var counts []string
	for c, col := range g.cols {
		if len(col) > 0 {
			counts = append(counts, AgentColumns[c].Label+" "+strconv.Itoa(len(col)))
		}
	}
	if len(counts) > 0 {
		out = toCells("   "+strings.Join(counts, " · "), fg(P.faint), out)
	}
	return out
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
	noteErr  bool   // note reports a failure or a refusal (P.err), else a neutral line (P.muted)
	armed    string // the card a first `x` / × asked to stop; "" = none
	group    string // the expanded group's key; "" = the tab's project (agentGroups)
	// A launch runs: a second `n` waits for it, two launches in one second would pick one name.
	launching bool
	place     *placeState // placement mode (showCmd): nil = none
	placeGen  int         // the last placement's gen
}

type agentsPoll struct {
	board    agentsBoard
	problems []string
	now      float64
	clock    string
	err      error
}

// pickMsg: the outcome of `agent-pane pick <name>`; err "" when it succeeded, then paneErr:
// ensurePane's (tried only after a pick that succeeded); ghostty: why showCmd fell back to it.
type pickMsg struct{ name, err, paneErr, ghostty string }

// stopMsg: the outcome of `agent-pane stop <name>`; err "" when it succeeded.
type stopMsg struct{ name, err string }

// newAgentMsg: the outcome of `n` (or of `c`, resume set, or of `N`, generic set): the name
// launched ("" when none was picked), the launch's error, then show (the show path, after a launch
// that succeeded), or with Ghostty not answering (ghostty: why) the fallback pick's error, then
// ensurePane's.
type newAgentMsg struct {
	name, err, pickErr, paneErr, ghostty string
	resume, blank, generic               bool // blank: resumed with no conversation to continue
	show                                 *placeStartMsg
}

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

// safeCommand: the whole split command, the path and ` --slot <slot>`: words the shell only
// splits on spaces.
var safeCommand = regexp.MustCompile(`^[A-Za-z0-9._+/ -]+$`)

// paneSlot: the board's own pane, the basename of its stdin's tty (`ttys012`), set by run on the
// interactive path only (ttySlot). Stable for the terminal's life (a board started again in that
// tab finds its pane), nothing written. "" (no tty: the snapshot, the tests): no --slot, the one
// global pane as before.
var paneSlot string

// ttySlot: the name of f's char device under /dev (a `tty*` entry of the same Rdev) when it passes
// validName, else "". Stdlib only: no ttyname(3) without cgo.
func ttySlot(f *os.File) string {
	fi, err := f.Stat()
	if err != nil || fi.Mode()&fs.ModeCharDevice == 0 {
		return ""
	}
	st, ok := fi.Sys().(*syscall.Stat_t)
	if !ok {
		return ""
	}
	return devName("/dev", uint64(st.Rdev))
}

// devName: the `tty*` char device in dir whose Rdev is rdev, when its name passes validName.
func devName(dir string, rdev uint64) string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return ""
	}
	for _, e := range entries {
		n := e.Name()
		if !strings.HasPrefix(n, "tty") || !validName(n) {
			continue
		}
		fi, err := os.Lstat(filepath.Join(dir, n))
		if err != nil || fi.Mode()&fs.ModeCharDevice == 0 {
			continue
		}
		if st, ok := fi.Sys().(*syscall.Stat_t); ok && uint64(st.Rdev) == rdev {
			return n
		}
	}
	return ""
}

// paneArgv: [pane, --slot <paneSlot>, args…], the slot right after the binary, or [pane, args…]
// without one: pick and alive address the board's own pane. stop never takes it (sessions are
// global).
func paneArgv(pane string, args ...string) []string {
	argv := []string{pane}
	if paneSlot != "" {
		argv = append(argv, "--slot", paneSlot)
	}
	return append(argv, args...)
}

// paneCommand: what the split runs, `<pane>` or `<pane> --slot <paneSlot>`; "" when the shell
// Ghostty hands it to could read more than those words in it.
func paneCommand(pane string) string {
	if !safePath.MatchString(pane) {
		return ""
	}
	cmd := pane
	if paneSlot != "" {
		if !validName(paneSlot) {
			return ""
		}
		cmd += " --slot " + paneSlot
	}
	if !safeCommand.MatchString(cmd) {
		return ""
	}
	return cmd
}

// openPaneArgv: osascript with paneScript as -e lines and command as the script's argv item: the
// command never becomes script text.
func openPaneArgv(command string) []string {
	argv := []string{"/usr/bin/osascript"}
	for _, line := range paneScript {
		argv = append(argv, "-e", line)
	}
	return append(argv, command)
}

// ensurePane runs after a pick that succeeded, in its Cmd: `agent-pane alive`, and when no pane
// runs a Ghostty split running agent-pane, which reads at start the target the pick just wrote.
// "" when a pane runs or one opened, else the footer's reason; the pick stands either way.
func ensurePane(pane string) string {
	alive, err := runAlive(paneArgv(pane, "alive"))
	switch {
	case err != nil:
		return "agent-pane alive : " + err.Error()
	case alive:
		return ""
	}
	cmd := paneCommand(pane)
	if cmd == "" {
		return "chemin d'agent-pane non sûr"
	}
	if err := runOpenPane(openPaneArgv(cmd)); err != nil {
		return "osascript : " + err.Error()
	}
	return ""
}

// paneNote: the footer's tail for ensurePane's reason, the command to type by hand.
func paneNote(reason string) string {
	hand := "agent-pane"
	if paneSlot != "" {
		hand += " --slot " + paneSlot
	}
	return " · pane : " + reason + " — lance " + hand + " à la main"
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
	return pickLaunched(pane, newAgentMsg{name: name})
}

// pickLaunched: after a launch that succeeded, the card's show path (showIn): the focus of a pane
// already showing it (a resume), else placement mode for the new name (msg.show); Ghostty not
// answering, the fallback pick's outcome (pickTop) into msg.
func pickLaunched(pane string, msg newAgentMsg) newAgentMsg {
	if pane == "" {
		msg.pickErr = "binaire absent"
		return msg
	}
	s := showIn(pane, msg.name)
	if s.top != nil {
		msg.pickErr, msg.paneErr, msg.ghostty = s.top.err, s.top.paneErr, s.top.ghostty
		return msg
	}
	msg.show = &s
	return msg
}

// genericRoot: where `N` puts a generic agent, one dir per name, $HOME/agents ("" when HOME is
// unknown: no generic agent). A variable so the tests point it at a temp dir.
var genericRoot = func() string {
	h, err := os.UserHomeDir()
	if err != nil || h == "" {
		return ""
	}
	return filepath.Join(h, "agents")
}

// isGenericOf: cwd is exactly `<genericRoot>/<name>`, clean and absolute, where launchGeneric
// started this agent: only there does `claude --continue` find its conversation.
func isGenericOf(cwd, name string) bool {
	root := genericRoot()
	return root != "" && filepath.IsAbs(root) && validName(name) && filepath.IsAbs(cwd) &&
		filepath.Clean(cwd) == cwd && cwd == filepath.Join(root, name)
}

// genericTaken: nameTaken's rule for `N`: a name abduco lists, with a state file, or whose
// `<root>/<name>` exists (an earlier generic's dir, even a link). A path that cannot be checked
// counts as taken.
func genericTaken(root, sessionsDir string, listed map[string]bool) func(string) bool {
	exists := func(p string) bool {
		_, err := os.Lstat(p)
		return !errors.Is(err, fs.ErrNotExist)
	}
	return func(n string) bool {
		return listed[n] || (sessionsDir != "" && exists(filepath.Join(sessionsDir, n+".json"))) ||
			exists(filepath.Join(root, n))
	}
}

// ensureGenericRoot: root as a real dir, made 0700 when missing; a link or anything else at root
// is refused, never followed.
func ensureGenericRoot(root string) error {
	fi, err := os.Lstat(root)
	switch {
	case errors.Is(err, fs.ErrNotExist):
		return os.Mkdir(root, 0o700)
	case err != nil:
		return err
	case fi.Mode()&fs.ModeSymlink != 0 || !fi.IsDir():
		return errors.New(root + " : lien ou pas un dossier, rien lancé")
	}
	return nil
}

// launchGeneric runs in genericCmd's Cmd: a free name, a new `<root>/<name>` (Mkdir: an existing
// one fails), `abduco -n <name> claude --name <name>` there, then pickLaunched. resumeAgent's
// launch minus --continue, CLAUDE_CODE_CHILD_SESSION dropped the same way; not through
// claude-dispatch for resumeAgent's reason. A refused launch removes the dir, still empty.
func launchGeneric(abduco, claude, pane, root, sessionsDir string, now time.Time) newAgentMsg {
	msg := newAgentMsg{generic: true}
	if !filepath.IsAbs(root) {
		msg.err = "dossier des génériques inconnu, rien lancé"
		return msg
	}
	if err := ensureGenericRoot(root); err != nil {
		msg.err = err.Error()
		return msg
	}
	var listed map[string]bool
	if out, err := abducoList(); err == nil {
		listed = map[string]bool{}
		for _, s := range parseAbduco(out) {
			listed[s.Name] = true
		}
	}
	name := agentName(now, genericTaken(root, sessionsDir, listed))
	if !validName(name) {
		msg.err = "aucun nom libre pour " + now.Format("150405")
		return msg
	}
	dir := filepath.Join(root, name)
	if err := os.Mkdir(dir, 0o700); err != nil {
		msg.err = err.Error()
		return msg
	}
	msg.name = name
	argv := []string{"/usr/bin/env", "-u", "CLAUDE_CODE_CHILD_SESSION", abduco, "-n", name, claude, "--name", name}
	if err := runLaunch(dir, argv); err != nil {
		_ = os.Remove(dir) // empty: claude never ran in it
		msg.err = err.Error()
		return msg
	}
	return pickLaunched(pane, msg)
}

// isWorktreeOf: cwd is exactly `<abs repo>/.claude/worktrees/<name>`, where `claude --worktree
// <name>` (claude-dispatch) puts the session: only there does `claude --continue` find this
// agent's conversation.
func isWorktreeOf(cwd, name string) bool {
	repo, ok := strings.CutSuffix(cwd, "/.claude/worktrees/"+name)
	return ok && validName(name) && repo != "" && filepath.IsAbs(cwd) && filepath.Clean(cwd) == cwd
}

// claudeProjects: claude's transcript root, ~/.claude/projects ("" when HOME is unknown). A
// variable so the tests point it at a temp dir.
var claudeProjects = func() string {
	h, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(h, ".claude", "projects")
}

// hasConversation: a `*.jsonl` transcript in cwd's project dir under projects, named as claude
// names it: cwd with every byte but [A-Za-z0-9] turned `-` (measured on this host's worktrees,
// 2026-10-21). An agent whose user never typed a prompt has none: `--continue` would find nothing.
// projects "" or a dir that cannot be read: true, --continue then says it itself.
func hasConversation(projects, cwd string) bool {
	if projects == "" {
		return true
	}
	enc := []byte(cwd)
	for i, c := range enc {
		if !('a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || '0' <= c && c <= '9') {
			enc[i] = '-'
		}
	}
	entries, err := os.ReadDir(filepath.Join(projects, string(enc)))
	if errors.Is(err, fs.ErrNotExist) {
		return false
	}
	if err != nil {
		return true
	}
	return slices.ContainsFunc(entries, func(e fs.DirEntry) bool {
		return e.Type().IsRegular() && strings.HasSuffix(e.Name(), ".jsonl")
	})
}

// resumeAgent runs in resumeCmd's Cmd: `abduco -n <name> claude --continue --name <name>` in the
// worktree (without --continue when hasConversation finds none: a blank session there, as `n`
// had started it), then pickLaunched. claude-dispatch's launch minus --worktree (the cwd is the worktree)
// and minus a prompt: --continue reopens the most recent conversation there, not the state file's
// sessionId, which another claude run in that dir (a hook's `claude -p`) can have overwritten
// (measured 2026-10-21). CLAUDE_CODE_CHILD_SESSION is dropped as claude-dispatch does. Not through
// claude-dispatch: it is the sandbox-excluded allow-list, a resume mode there would widen what a
// sandboxed session launches; the board runs in the user's terminal, outside the sandbox; a
// worktree that is gone, or a link, launches nothing.
func resumeAgent(abduco, claude, pane, name, cwd string) newAgentMsg {
	msg := newAgentMsg{name: name, resume: true}
	if fi, err := os.Lstat(cwd); err != nil || !fi.IsDir() {
		msg.err = "worktree absent ou lien : " + cwd
		return msg
	}
	argv := []string{"/usr/bin/env", "-u", "CLAUDE_CODE_CHILD_SESSION", abduco, "-n", name, claude}
	if hasConversation(claudeProjects(), cwd) {
		argv = append(argv, "--continue")
	} else {
		msg.blank = true
	}
	argv = append(argv, "--name", name)
	if err := runLaunch(cwd, argv); err != nil {
		msg.err = err.Error()
		return msg
	}
	return pickLaunched(pane, msg)
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
// is an argv word. Enter, `o` and a card click go through showCmd, which falls back to this pick
// when Ghostty cannot be asked.
func (m *Model) pickCmd(name string) tea.Cmd {
	if !validName(name) {
		return nil
	}
	if agentPaneBin == "" {
		m.ag.say("agent-pane : binaire absent, rien lancé", true)
		m.dirty = true
		return nil
	}
	pane := agentPaneBin
	return func() tea.Msg { return pickTop(pane, name) }
}

// pickTop: the board's own pane (paneArgv's slot) gets name, then ensurePane; in pickCmd's Cmd or
// showCmd's.
func pickTop(pane, name string) pickMsg {
	if err := runPick(paneArgv(pane, "pick", name)); err != nil {
		return pickMsg{name: name, err: err.Error()}
	}
	return pickMsg{name: name, paneErr: ensurePane(pane)}
}

func (m *Model) applyPick(msg pickMsg) {
	switch {
	case msg.err != "":
		m.ag.say("agent-pane pick "+msg.name+" : "+msg.err, true)
	case msg.paneErr != "":
		m.ag.say("affichée en haut : "+msg.name+paneNote(msg.paneErr), true)
	default:
		m.ag.say("affichée en haut : "+msg.name, false)
	}
	if msg.ghostty != "" {
		m.ag.note += " · Ghostty : " + msg.ghostty
		m.ag.noteErr = true
	}
	m.dirty = true
}

// ---- placement: one pane per Ghostty terminal ------------------------------------
//
// A pane's slot is its Ghostty terminal's id lowercased (termSlot: Ghostty's ids are uppercase
// UUIDs, the slot rule wants lowercase), so a terminal names its slot with no registry; `agent-pane
// --here` (the `ap` alias, and the command of every split the board opens) resolves its own the
// same way. Enter, `o` or a click on a card (showCmd): a live pane already showing the agent gets
// the focus (findShown); else the board enters placement mode (placeState): every placeEvery it
// asks Ghostty which terminal of its own tab has the focus, and the first one that is not the
// board gets the agent (placeInto): an agent pane switches (pick), any other terminal gets a split
// on its right running `agent-pane --here`, then the pick on the new terminal's slot. Enter splits
// the board itself, Échap or placeTimeout cancels. Nothing is ever typed into a terminal: a split
// carries its command in its surface configuration, and every script gets the ids and the command
// as argv items, never as script text. Ghostty that cannot be asked (another terminal, osascript
// refused) falls back to pickTop, the board's own pane as before.

const (
	placeEvery   = 300 * time.Millisecond
	placeTimeout = 30 * time.Second
	// The most a script prints: two ids and a newline.
	ghosttyOutMax = 4096
)

// uuidSlot: a slot that is a terminal's (Ghostty's id lowercased): only those can be focused; the
// others (a board's tty, a hand-typed `--slot`) are no terminal.
var uuidSlot = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

// termSlot: the slot of a terminal id Ghostty printed, lowercased, when it passes the name rule
// (agent-pane --here's); "" else. A passing id is also safe as an osascript argv item (no `-`
// first).
func termSlot(id string) string {
	s := strings.ToLower(strings.TrimSpace(id))
	if !validName(s) {
		return ""
	}
	return s
}

// boardScript: the board's tab id and terminal id, one per line: it runs in the focused terminal
// of the front window's selected tab (the key or the click that started it went there).
var boardScript = []string{
	"on run argv",
	`tell application "Ghostty"`,
	"set tb to selected tab of front window",
	"return (id of tb) & linefeed & (id of focused terminal of tb)",
	"end tell",
	"end run",
}

// focusedScript: the id of the focused terminal of the tab whose id is item 1, in any window; ""
// when no tab has it (closed).
var focusedScript = []string{
	"on run argv",
	`tell application "Ghostty"`,
	"repeat with w in windows",
	"repeat with tb in tabs of w",
	"if id of tb is item 1 of argv then return id of focused terminal of tb",
	"end repeat",
	"end repeat",
	"end tell",
	`return ""`,
	"end run",
}

// focusScript: focus the terminal whose id is item 1 (its window comes to the front).
var focusScript = []string{
	"on run argv",
	`tell application "Ghostty"`,
	"focus (terminal id (item 1 of argv))",
	"end tell",
	"end run",
}

// splitScript: a split on the right of the terminal whose id is item 1, running item 2; prints the
// new terminal's id, "" when split gives none back.
var splitScript = []string{
	"on run argv",
	`tell application "Ghostty"`,
	"set cfg to new surface configuration",
	"set command of cfg to item 2 of argv",
	"set n to split (terminal id (item 1 of argv)) direction right with configuration cfg",
	"try",
	"return id of n",
	"on error",
	`return ""`,
	"end try",
	"end tell",
	"end run",
}

// ghosttyArgv: osascript with script as -e lines and items as the script's argv.
func ghosttyArgv(script []string, items ...string) []string {
	argv := []string{"/usr/bin/osascript"}
	for _, line := range script {
		argv = append(argv, "-e", line)
	}
	return append(argv, items...)
}

// runGhostty runs argv (osascript, no shell) as runQuiet and returns stdout trimmed, at most
// ghosttyOutMax bytes. A variable so the tests never run it.
var runGhostty = func(argv []string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), pickTimeout)
	defer cancel()
	var stdout, stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	cmd.WaitDelay = time.Second
	err := cmd.Run()
	switch {
	case err == nil:
		if stdout.Len() > ghosttyOutMax {
			return "", errors.New("réponse de plus de " + strconv.Itoa(ghosttyOutMax) + " octets")
		}
		return strings.TrimSpace(stdout.String()), nil
	case ctx.Err() != nil:
		return "", errors.New("pas de réponse en " + strconv.Itoa(int(pickTimeout/time.Second)) + " s")
	}
	if line, _, _ := strings.Cut(strings.TrimSpace(stderr.String()), "\n"); line != "" {
		return "", errors.New(oneLine(line))
	}
	return "", err
}

// paneStateDir: agent-pane's state dir, `${XDG_STATE_HOME:-$HOME/.local/state}/agent-pane` as the
// script computes it; "" without a home. A variable so the tests point it at a temp dir.
var paneStateDir = func() string {
	base := os.Getenv("XDG_STATE_HOME")
	if base == "" {
		h, err := os.UserHomeDir()
		if err != nil || h == "" {
			return ""
		}
		base = filepath.Join(h, ".local", "state")
	}
	return filepath.Join(base, "agent-pane")
}

// slotTarget: line 1 of a slot's target file (the name it shows), "" when it cannot be read (a
// link, not a regular file, absent). The file is two short lines: 256 bytes are plenty.
func slotTarget(p string) string {
	f, _, err := openNoFollow(p)
	if err != nil {
		return ""
	}
	defer f.Close()
	head, _ := io.ReadAll(io.LimitReader(f, 256))
	line, _, _ := strings.Cut(string(head), "\n")
	return line
}

// findShown: the slot of a terminal whose live pane shows name (its target's line 1, and `agent-pane
// --slot <slot> alive` exit 0), "" when none. Only terminal slots (uuidSlot): another cannot be
// focused.
func findShown(pane, name string) string {
	dir := paneStateDir()
	if dir == "" {
		return ""
	}
	root := filepath.Join(dir, "slots")
	entries, err := os.ReadDir(root)
	if err != nil {
		return ""
	}
	for _, e := range entries {
		slot := e.Name()
		if !e.IsDir() || !uuidSlot.MatchString(slot) || slotTarget(filepath.Join(root, slot, "target")) != name {
			continue
		}
		if alive, err := runAlive([]string{pane, "--slot", slot, "alive"}); err == nil && alive {
			return slot
		}
	}
	return ""
}

// hereCommand: what a split runs, `<pane> --here`; "" when the shell Ghostty hands it to could read
// more than those words in it (paneCommand's rule).
func hereCommand(pane string) string {
	if !safePath.MatchString(pane) {
		return ""
	}
	if cmd := pane + " --here"; safeCommand.MatchString(cmd) {
		return cmd
	}
	return ""
}

// placeState: placement mode, for one agent; the board's tab and terminal ids as Ghostty printed
// them (compared and passed back as is); gen tells this placement's ticks from an earlier one's.
type placeState struct {
	name, tab, board string
	until            time.Time
	gen              int
}

// placeStartMsg: showCmd's outcome: shown (a pane showed name and got the focus; err when the focus
// failed), else the board's ids (placement starts), else top (Ghostty not asked: the fallback pick
// ran).
type placeStartMsg struct {
	name, err, tab, board string
	shown                 bool
	top                   *pickMsg
}

// placeTickMsg: time to ask which terminal of the board's tab has the focus.
type placeTickMsg struct{ gen int }

// placeFocusMsg: the answer: the focused terminal's id ("" = the tab is gone), or err.
type placeFocusMsg struct {
	gen       int
	term, err string
}

// placedMsg: placeInto's outcome: err "" when name is shown; split when a new split shows it.
type placedMsg struct {
	name, err string
	split     bool
}

// showCmd: Enter, `o` or a card click on name: findShown then the focus, else the board's ids,
// in a Cmd off the UI goroutine; Ghostty failing to answer falls back to pickTop.
func (m *Model) showCmd(name string) tea.Cmd {
	if !validName(name) {
		return nil
	}
	if agentPaneBin == "" {
		m.ag.say("agent-pane : binaire absent, rien lancé", true)
		m.dirty = true
		return nil
	}
	pane := agentPaneBin
	return func() tea.Msg { return showIn(pane, name) }
}

// showIn: showCmd's work, in its Cmd or after a launch that succeeded (pickLaunched).
func showIn(pane, name string) placeStartMsg {
	if slot := findShown(pane, name); slot != "" {
		if _, err := runGhostty(ghosttyArgv(focusScript, strings.ToUpper(slot))); err != nil {
			return placeStartMsg{name: name, shown: true, err: err.Error()}
		}
		return placeStartMsg{name: name, shown: true}
	}
	out, err := runGhostty(ghosttyArgv(boardScript))
	why := ""
	tab, board, _ := strings.Cut(out, "\n")
	switch {
	case err != nil:
		why = err.Error()
	case termSlot(tab) == "" || termSlot(board) == "":
		why = "ids illisibles"
	default:
		return placeStartMsg{name: name, tab: strings.TrimSpace(tab), board: strings.TrimSpace(board)}
	}
	top := pickTop(pane, name)
	top.ghostty = why
	return placeStartMsg{name: name, top: &top}
}

// placeTick: the next placeTickMsg of this placement, placeEvery from now.
func placeTick(gen int) tea.Cmd {
	return tea.Tick(placeEvery, func(time.Time) tea.Msg { return placeTickMsg{gen: gen} })
}

func (m *Model) applyPlaceStart(msg placeStartMsg) tea.Cmd {
	a := &m.ag
	m.dirty = true
	switch {
	case msg.top != nil:
		m.applyPick(*msg.top)
		return nil
	case msg.shown && msg.err != "":
		a.say("focus "+msg.name+" : osascript : "+msg.err, true)
		return nil
	case msg.shown:
		a.say("affichée : "+msg.name, false)
		return nil
	}
	a.placeGen++
	a.place = &placeState{name: msg.name, tab: msg.tab, board: msg.board, until: time.Now().Add(placeTimeout), gen: a.placeGen}
	a.say("clique le pane où afficher "+msg.name+" · Entrée = nouveau split · Échap = annuler", false)
	return placeTick(a.placeGen)
}

// placing: the current placement when gen is its own, else nil (cancelled, done, or replaced).
func (m *Model) placing(gen int) *placeState {
	if p := m.ag.place; p != nil && p.gen == gen {
		return p
	}
	return nil
}

// endPlace leaves placement mode, the footer saying note (failed: as a failure).
func (m *Model) endPlace(note string, failed bool) {
	m.ag.place, m.dirty = nil, true
	m.ag.say(note, failed)
}

// say sets the footer note; failed: it reports a failure or a refusal, drawn in P.err.
func (a *agentsState) say(note string, failed bool) { a.note, a.noteErr = note, failed }

// applyPlaceTick: past placeTimeout the placement ends; else one osascript in a Cmd asks the
// board's tab for its focused terminal (the next tick waits for its answer).
func (m *Model) applyPlaceTick(msg placeTickMsg) tea.Cmd {
	p := m.placing(msg.gen)
	if p == nil {
		return nil
	}
	if !time.Now().Before(p.until) {
		m.endPlace("placement de "+p.name+" annulé ("+strconv.Itoa(int(placeTimeout/time.Second))+" s)", true)
		return nil
	}
	gen, argv := p.gen, ghosttyArgv(focusedScript, p.tab)
	return func() tea.Msg {
		out, err := runGhostty(argv)
		if err != nil {
			return placeFocusMsg{gen: gen, err: err.Error()}
		}
		return placeFocusMsg{gen: gen, term: out}
	}
}

// applyPlaceFocus: the board still focused, another tick; another terminal gets the agent.
func (m *Model) applyPlaceFocus(msg placeFocusMsg) tea.Cmd {
	p := m.placing(msg.gen)
	switch {
	case p == nil:
		return nil
	case msg.err != "":
		m.endPlace("placement annulé : osascript : "+msg.err, true)
		return nil
	case msg.term == "":
		m.endPlace("onglet du board introuvable : placement annulé", true)
		return nil
	case msg.term == p.board:
		return placeTick(p.gen)
	}
	return m.placeCmd(p, msg.term, false)
}

// placeCmd ends placement mode and runs placeInto on term in a Cmd (split: a new split of term,
// whatever runs there: Enter on the board).
func (m *Model) placeCmd(p *placeState, term string, split bool) tea.Cmd {
	name, pane := p.name, agentPaneBin
	m.endPlace("placement de "+name+"…", false)
	return func() tea.Msg { return placeInto(pane, name, term, split) }
}

// placeInto: term's own pane gets name when one runs there (and split is false), else a split on
// term's right running `agent-pane --here`, then the pick on the new terminal's slot. The new pane
// polls its target, so a pick before or after its start shows the same agent.
func placeInto(pane, name, term string, split bool) placedMsg {
	slot := termSlot(term)
	if slot == "" {
		return placedMsg{name: name, err: "id de terminal illisible"}
	}
	if !split {
		alive, err := runAlive([]string{pane, "--slot", slot, "alive"})
		if err != nil {
			return placedMsg{name: name, err: "agent-pane alive : " + err.Error()}
		}
		if alive {
			return pickInto(pane, name, slot, false)
		}
	}
	cmd := hereCommand(pane)
	if cmd == "" {
		return placedMsg{name: name, err: "chemin d'agent-pane non sûr"}
	}
	out, err := runGhostty(ghosttyArgv(splitScript, term, cmd))
	if err != nil {
		return placedMsg{name: name, err: "split : osascript : " + err.Error()}
	}
	nslot := termSlot(out)
	if nslot == "" {
		return placedMsg{name: name, err: "split ouvert sans id : rien choisi dedans", split: true}
	}
	return pickInto(pane, name, nslot, true)
}

// pickInto: `agent-pane --slot <slot> pick <name>`.
func pickInto(pane, name, slot string, split bool) placedMsg {
	if err := runPick([]string{pane, "--slot", slot, "pick", name}); err != nil {
		return placedMsg{name: name, err: "agent-pane pick : " + err.Error(), split: split}
	}
	return placedMsg{name: name, split: split}
}

func (m *Model) applyPlaced(msg placedMsg) {
	switch {
	case msg.err != "":
		m.ag.say(msg.name+" : "+msg.err, true)
	case msg.split:
		m.ag.say("affichée : "+msg.name+" (nouveau split)", false)
	default:
		m.ag.say("affichée : "+msg.name, false)
	}
	m.dirty = true
}

// keyPlace: a key in placement mode: Enter splits the board, Échap cancels, any other is ignored
// (the footer stays).
func (m *Model) keyPlace(ev string) tea.Cmd {
	p := m.ag.place
	switch ev {
	case "enter":
		return m.placeCmd(p, p.board, true)
	case "esc":
		m.endPlace("placement annulé", false)
	}
	return nil
}

// stopCmd: `agent-pane stop <name>` in a Cmd, as pickCmd; the footer says the outcome (stopMsg).
func (m *Model) stopCmd(name string) tea.Cmd {
	if !validName(name) {
		return nil
	}
	if agentPaneBin == "" {
		m.ag.say("agent-pane : binaire absent, rien éteint", true)
		m.dirty = true
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
		m.ag.say("agent-pane stop "+msg.name+" : "+msg.err, true)
	} else {
		m.ag.say("éteinte : "+msg.name, false)
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
		a.say("nouvel agent : un lancement est en cours", true)
		return nil
	}
	if dispatchBin == "" {
		a.say("claude-dispatch : binaire absent, rien lancé", true)
		return nil
	}
	repo := tabRepo(m.runsDir)
	if repo == "" {
		a.say("nouvel agent : dépôt inconnu, rien lancé", true)
		return nil
	}
	sessionsDir := ""
	if a.reader != nil {
		sessionsDir = a.reader.Dir
	}
	bin, pane := dispatchBin, agentPaneBin
	a.launching = true
	a.say("nouvel agent : lancement…", false)
	return func() tea.Msg { return launchAgent(bin, pane, repo, sessionsDir, time.Now()) }
}

// resumeCmd: `c` on the selected card: resumeAgent in a Cmd, off the UI goroutine, when the card
// is Resumable; else the footer says why. One launch at a time, `n`'s guard.
func (m *Model) resumeCmd(ag *Agent) tea.Cmd {
	a := &m.ag
	m.dirty = true
	switch {
	case !ag.Resumable:
		a.say(ag.Name+" : rien à reprendre (session encore listée, abduco muet ou hors worktree)", true)
		return nil
	case a.launching:
		a.say("reprise : un lancement est en cours", true)
		return nil
	case abducoBin == "" || claudeBin == "":
		a.say("reprise : binaire absent, rien lancé", true)
		return nil
	}
	abduco, claude, pane, name, cwd := abducoBin, claudeBin, agentPaneBin, ag.Name, ag.Cwd
	a.launching = true
	a.say("reprise de "+name+"…", false)
	return func() tea.Msg { return resumeAgent(abduco, claude, pane, name, cwd) }
}

// genericCmd: `N`: launchGeneric in a Cmd, off the UI goroutine, in genericRoot; the footer says
// the outcome (newAgentMsg). No repo needed. One launch at a time, `n`'s guard.
func (m *Model) genericCmd() tea.Cmd {
	a := &m.ag
	m.dirty = true
	switch {
	case a.launching:
		a.say("générique : un lancement est en cours", true)
		return nil
	case abducoBin == "" || claudeBin == "":
		a.say("générique : binaire absent, rien lancé", true)
		return nil
	}
	root := genericRoot()
	if root == "" || !filepath.IsAbs(root) {
		a.say("générique : dossier inconnu, rien lancé", true)
		return nil
	}
	sessionsDir := ""
	if a.reader != nil {
		sessionsDir = a.reader.Dir
	}
	abduco, claude, pane := abducoBin, claudeBin, agentPaneBin
	a.launching = true
	a.say("générique : lancement…", false)
	return func() tea.Msg { return launchGeneric(abduco, claude, pane, root, sessionsDir, time.Now()) }
}

// applyNewAgent: the footer says it, the new card is selected, and a poll at once draws it.
func (m *Model) applyNewAgent(msg newAgentMsg) tea.Cmd {
	a := &m.ag
	a.launching, m.dirty = false, true
	label, launch := "nouvel agent : ", "claude-dispatch --blank "
	switch {
	case msg.resume:
		label, launch = "reprise : ", "reprise de "
	case msg.generic:
		label, launch = "générique : ", "abduco -n "
	}
	switch {
	case msg.name == "":
		a.say(label+msg.err, true)
	case msg.err != "":
		a.say(launch+msg.name+" : "+msg.err, true)
	case msg.pickErr != "":
		a.say(label+msg.name+" · agent-pane pick : "+msg.pickErr, true)
	case msg.paneErr != "":
		a.say(label+msg.name+paneNote(msg.paneErr), true)
	default:
		a.say(label+msg.name, false)
	}
	if msg.blank && msg.err == "" {
		a.note += " (aucune conversation : session vierge)"
	}
	if msg.ghostty != "" {
		a.note += " · Ghostty : " + msg.ghostty
		a.noteErr = true
	}
	if msg.name != "" && msg.err == "" {
		a.sel, a.follow = &selState{id: msg.name}, true
	}
	if msg.show != nil && msg.err == "" {
		// The launch's line, then the show path's (the placement prompt, or the focus).
		head, headErr := a.note, a.noteErr
		tick := m.applyPlaceStart(*msg.show)
		a.say(head+" · "+a.note, headErr || a.noteErr)
		return tea.Batch(m.pollCmd(), tick)
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
		a.say(ag.Name+" : pas de session à éteindre", true)
		return nil
	case armed != ag.ID:
		a.armed = ag.ID
		a.say("éteindre "+ag.Name+" ? × ou x encore pour confirmer · Échap annule", true)
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
	cols := m.shownCols()
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
	list := m.shownCols()[c]
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
	if a.place != nil {
		return m.keyPlace(ev)
	}
	if a.note != "" {
		a.note, m.dirty = "", true
	}
	armed := m.disarm()
	sel := m.agentSelection()
	cols := m.shownCols()
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
			return m.showCmd(cols[sel.col][sel.idx].ID)
		}
	case "x":
		if sel.idx >= 0 {
			return m.stopAgent(cols[sel.col][sel.idx], armed)
		}
	case "n":
		return m.newAgentCmd()
	case "N":
		return m.genericCmd()
	case "p":
		m.stepGroup(1)
	case "P":
		m.stepGroup(-1)
	case "c":
		if sel.idx >= 0 {
			return m.resumeCmd(cols[sel.col][sel.idx])
		}
	case "r":
		return m.refreshCmd()
	}
	return nil
}

// clickAgents: h nil = a click on nothing, which only disarms. In placement mode a click on the
// board is ignored, as a key (the footer stays).
func (m *Model) clickAgents(h *hit) tea.Cmd {
	a := &m.ag
	if a.place != nil {
		return nil
	}
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
		return m.showCmd(h.id)
	case hitStop:
		cols := m.shownCols()
		if h.col < 0 || h.col >= len(cols) || h.idx < 0 || h.idx >= len(cols[h.col]) || cols[h.col][h.idx].ID != h.id {
			return nil // the board moved since the frame
		}
		a.sel = &selState{col: h.col, idx: h.idx, id: h.id}
		a.follow, m.dirty = true, true
		return m.stopAgent(cols[h.col][h.idx], armed)
	case hitGroup:
		a.note = ""
		m.openGroup(h.id)
	case hitNew:
		return m.newAgentCmd()
	case hitRefresh:
		return m.refreshCmd()
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

var keysAgents = "←→↑↓ naviguer · ⏎/o afficher · x éteindre · c reprendre · N générique · p projet · a runs · q quitter"

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
	case armed:
		border = P.err
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
			xc = P.err
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

// minGroupCards: the card rows the folded headers leave to the open group, when short of rows.
const minGroupCards = 4

// drawGroup: group i's header row at y, under a hitGroup.
func (m *Model) drawGroup(gr *agentGroup, i int, open bool, y, W int) {
	if y < 0 || y >= len(m.g) {
		return
	}
	w := max(0, W-2*margin)
	m.g.put(margin, y, fitCells(groupLine(gr, open), w))
	if w > 0 {
		m.hits = append(m.hits, hit{x: margin, y: y, w: w, h: 1, kind: hitGroup, idx: i, id: gr.key})
	}
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
	footerTop := H - 1
	if tall {
		footerTop = H - 2
	}
	bottom := footerTop // the cards end above it (a blank row before the footer when tall)
	if tall {
		bottom--
	}
	// The accordion: the folded groups before the open one, its header, its kanban, the folded
	// ones after. Short of rows, the folded headers nearest the open one are kept, and the cards
	// keep minGroupCards rows first.
	gs, open := m.agentGroups()
	cols := &a.board.cols
	var after []*agentGroup
	if gs != nil {
		cols = &gs[open].cols
		room := max(0, bottom-y-3-minGroupCards)
		nb := min(open, room)
		na := min(len(gs)-open-1, room-nb)
		for i := open - nb; i <= open; i++ {
			m.drawGroup(gs[i], i, i == open, y, W)
			y++
		}
		after = gs[open+1 : open+1+na]
		bottom -= na
	}
	headY := y
	cardsTop := headY + 2
	areaH := max(0, bottom-cardsTop)
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
		list := cols[c]
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
	for k, gr := range after {
		m.drawGroup(gr, open+1+k, false, cardsTop+areaH+k, W)
	}

	// Footer: the note or what is hidden, then the keys (and the hidden count when short).
	info := cellsOf(hiddenText(a.board), fg(P.muted))
	if a.note != "" {
		nc := P.muted
		if a.noteErr {
			nc = P.err
		}
		info = cellsOf(a.note, fg(nc))
	}
	if tall {
		g.put(margin, H-2, fitCells(info, W-2*margin))
		info = nil
	}
	// Short: a note wins over the columns indicator, the ‹ › arrows still say more columns.
	if nVis < n && (tall || a.note == "") {
		info = cellsOf("colonnes "+strconv.Itoa(first+1)+"-"+strconv.Itoa(first+nVis)+"/"+strconv.Itoa(n), fg(P.faint))
	}
	btn := cellsOf(newAgentLabel, fg(P.active).bold())
	ref := cellsOf(refreshLabel, fg(P.active).bold())
	keys := append(toCells(" · ", fg(P.faint), slices.Clone(btn)), ref...)
	if paneSlot != "" {
		// The slot to type for `ap --slot <slot>` by hand.
		keys = toCells(" · panneau "+paneSlot, fg(P.muted), keys)
	}
	keys = toCells(" · "+keysAgents, fg(P.muted), keys)
	kw := W - 2*margin
	if len(info) > 0 {
		kw -= min(cellsWidth(info), kw/2) + 2
	}
	shownKeys := fitCells(keys, max(0, kw))
	g.put(margin, H-1, shownKeys)
	if w := min(cellsWidth(btn), cellsWidth(shownKeys)); w > 0 {
		m.hits = append(m.hits, hit{x: margin, y: H - 1, w: w, h: 1, kind: hitNew})
	}
	rx := cellsWidth(btn) + 3
	if w := min(cellsWidth(ref), cellsWidth(shownKeys)-rx); w > 0 {
		m.hits = append(m.hits, hit{x: margin + rx, y: H - 1, w: w, h: 1, kind: hitRefresh})
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
