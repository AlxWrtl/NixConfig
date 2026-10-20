package main

// Agents tab: the user's Claude Code background sessions, every project, as a kanban
// (Attend ta réponse · Travaille · Figé · Terminé). Source: ~/.claude/jobs/<id>/state.json and
// its timeline.jsonl, a format the engine does not document, parsed defensively as the deck mod
// does (home/claude-code/mods/deck/hooks/background.ts): bgKind, BG_ORDER, the 24 h keep of
// finished sessions, the timeline folding and the secret masking are ported from there so the
// deck panel and this tab agree; the board-only rules (hidden empty sessions, stale working)
// say so where they sit.
//
// Read-only, as disk.go: only under the jobs dir's realpath; a job dir that is a link is not
// listed; state.json and timeline.jsonl are opened O_NOFOLLOW | O_NONBLOCK and must be regular
// files (a link is refused, never read); state.json is read up to 256 KB (larger is reported,
// not parsed), the timeline's last 512 KB; control chars are drawn `?` by toCells. The reads run
// in the poll's Cmd, off the UI goroutine; a session whose files did not change (size, mtime,
// inode) keeps its parsed state.

import (
	"bytes"
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
	maxStateBytes    = 256 * 1024
	maxTimelineBytes = 512 * 1024
	// Board-only: a working session silent this long is drawn Figé (deck keeps it `working`).
	staleMs = 15 * 60 * 1000
	// deck's BG_KEEP_MS: a finished session older than this leaves the tab.
	keepMs = 24 * 60 * 60 * 1000
	// Timeline steps the drawer shows, newest first.
	timelineMax    = 50
	dispatchPrefix = "[claude-dispatch]"
)

const (
	tabRuns = iota
	tabAgents
)

// ---- deck's mapping ------------------------------------------------------------

// bgKind is deck's bgKind word for word: a `tempo` of `active` (exact case) is `working`
// whatever the state (the session runs a turn now); a `working` state whose `tempo` is `blocked`
// (exact case) is `needs-you` when it asks (a non-empty `needs` or `block.questions`), else
// `stalled`; the other words are compared lowercased; a word it does not know is `other`.
func bgKind(state, tempo string, asks bool) string {
	if tempo == "active" {
		return "working"
	}
	if state == "working" && tempo == "blocked" {
		if asks {
			return "needs-you"
		}
		return "stalled"
	}
	switch strings.ToLower(state) {
	case "working":
		return "working"
	case "blocked":
		return "needs-you"
	case "done", "completed":
		return "done"
	case "failed", "error":
		return "failed"
	case "stopped", "killed":
		return "stopped"
	}
	return "other"
}

// bgOrder is deck's BG_ORDER: what waits on you first, what ended last.
var bgOrder = []string{"needs-you", "stalled", "failed", "working", "other", "stopped", "done"}

type agentColumn struct{ Key, Label, Who string }

// AgentColumns: deck's kinds folded into four columns, in BG_ORDER (see agentColumnOf).
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

// jobInput: one state.json as the tab reads it (immutable once parsed: the reader caches it).
type jobInput struct {
	ID, Name, Cwd, Branch, State, Tempo string
	Needs, Question, Intent, Detail     string
	LastText                            string // the waiting text: the last reply's last paragraph, else detail unless it echoes a prompt
	UpdatedAt                           float64
	HasTimeline                         bool
	asks                                bool
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

// firstQuestion: the first readable text of block.questions (a string, or an object's
// question / text / header).
func firstQuestion(qs []any) string {
	for _, q := range qs {
		switch q := q.(type) {
		case string:
			if s := oneLine(redact(q)); s != "" {
				return s
			}
		case map[string]any:
			for _, k := range []string{"question", "text", "header"} {
				if s := oneLine(redact(strOf(q, k))); s != "" {
					return s
				}
			}
		}
	}
	return ""
}

// parseJobState: as deck's parseJobState, nil when it is no JSON object or lacks a string
// `state` or `cwd`.
func parseJobState(id string, data []byte) *jobInput {
	var v map[string]any
	if json.Unmarshal(data, &v) != nil || v == nil {
		return nil
	}
	state, ok1 := v["state"].(string)
	cwd, ok2 := v["cwd"].(string)
	if !ok1 || !ok2 {
		return nil
	}
	intent := oneLine(redact(strOf(v, "intent")))
	if rest, ok := strings.CutPrefix(intent, dispatchPrefix); ok {
		intent = strings.TrimSpace(rest)
	}
	j := &jobInput{
		ID: id, Name: oneLine(strOf(v, "name")), Cwd: cwd, Branch: oneLine(strOf(v, "worktreeBranch")),
		State: state, Tempo: strOf(v, "tempo"), Needs: oneLine(redact(strOf(v, "needs"))),
		Intent: intent, Detail: oneLine(redact(strOf(v, "detail"))), UpdatedAt: isoMs(strOf(v, "updatedAt")),
	}
	j.asks = strOf(v, "needs") != ""
	if b, ok := v["block"].(map[string]any); ok {
		if qs, ok := b["questions"].([]any); ok && len(qs) > 0 {
			j.asks, j.Question = true, firstQuestion(qs)
		}
	}
	return j
}

func (j *jobInput) kind() string { return bgKind(j.State, j.Tempo, j.asks) }

// neverStarted (board-only): a session that never got a prompt (no name and needs « send a
// prompt to start », or no mission and no timeline). deck lists it as needs-you; the tab hides it
// and counts it in the footer: these are the empty sessions the native view is full of.
func (j *jobInput) neverStarted() bool {
	if j.Name == "" && strings.Contains(strings.ToLower(j.Needs), "prompt to start") {
		return true
	}
	return j.Intent == "" && !j.HasTimeline
}

type timelineEvent struct {
	At                  float64
	State, Detail, Text string
}

// parseTimeline: deck's parseTimeline, oldest first: a line that does not read, has no ISO
// `at` or no non-empty `detail` is skipped; a detail repeated on the next line folds into its
// first. Board-only: the folded line's reply `text` (deck draws none) replaces the first's.
func parseTimeline(data []byte, limit int) []timelineEvent {
	if limit <= 0 {
		return nil
	}
	var out []timelineEvent
	for line := range bytes.SplitSeq(data, []byte{'\n'}) {
		if len(bytes.TrimSpace(line)) == 0 {
			continue
		}
		var v map[string]any
		if json.Unmarshal(line, &v) != nil || v == nil {
			continue
		}
		at := isoMs(strOf(v, "at"))
		detail := oneLine(redact(strOf(v, "detail")))
		if at == 0 || detail == "" {
			continue
		}
		text := strings.TrimSpace(redact(strOf(v, "text")))
		if n := len(out); n > 0 && out[n-1].Detail == detail {
			if text != "" {
				out[n-1].Text = text
			}
			continue
		}
		out = append(out, timelineEvent{At: at, State: oneLine(strOf(v, "state")), Detail: detail, Text: text})
	}
	if len(out) > limit {
		out = out[len(out)-limit:]
	}
	return out
}

// paragraphBreak: a blank line, as deck's waitingText splits a reply.
var paragraphBreak = regexp.MustCompile(`\n[ \t]*\n`)

// waitingText is deck's waitingText: what a needs-you session waits on, the last paragraph of the
// timeline's last non-empty reply `text`, one line and redacted. Without a reply, `detail`
// (already one line and redacted), unless it equals the `detail` of a line without `text` (a
// user prompt): a prompt echo gives "". A line that does not read is skipped.
func waitingText(data []byte, detail string) string {
	reply := ""
	prompts := map[string]bool{}
	for line := range bytes.SplitSeq(data, []byte{'\n'}) {
		var v map[string]any
		if json.Unmarshal(line, &v) != nil || v == nil {
			continue
		}
		if t := strings.TrimSpace(strOf(v, "text")); t != "" {
			reply = t
			continue
		}
		if d, ok := v["detail"].(string); ok {
			prompts[oneLine(redact(d))] = true
		}
	}
	parts := slices.DeleteFunc(paragraphBreak.Split(reply, -1), func(p string) bool { return strings.TrimSpace(p) == "" })
	if len(parts) > 0 {
		if last := oneLine(redact(parts[len(parts)-1])); last != "" {
			return last
		}
	}
	if prompts[detail] {
		return ""
	}
	return detail
}

// ---- disk ----------------------------------------------------------------------

// jobIDChars: the claude-bg wrapper's id alphabet (`^[0123456789abcdef]{8}$`), spelled out
// rather than a range.
const jobIDChars = "0123456789abcdef"

// validJobID: exactly 8 chars of jobIDChars. Only such a dir is a session: its name becomes the
// argv word of `claude attach <id>`, so a name like `--help` must never get there.
func validJobID(id string) bool {
	if len(id) != 8 {
		return false
	}
	for i := 0; i < len(id); i++ {
		if strings.IndexByte(jobIDChars, id[i]) < 0 {
			return false
		}
	}
	return true
}

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

// readTail: a file's last limit bytes, from its first whole line.
func readTail(p string, limit int64) ([]byte, error) {
	f, fi, err := openNoFollow(p)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	off := max(0, fi.Size()-limit)
	buf := make([]byte, fi.Size()-off)
	n, err := f.ReadAt(buf, off)
	if err != nil && !errors.Is(err, io.EOF) {
		return nil, err
	}
	data := buf[:n]
	if off > 0 {
		i := bytes.IndexByte(data, '\n')
		if i < 0 {
			return nil, nil
		}
		data = data[i+1:]
	}
	return data, nil
}

func fileSig(fi fs.FileInfo) string {
	if fi == nil {
		return "-"
	}
	s := strconv.FormatInt(fi.Size(), 10) + ":" + strconv.FormatInt(fi.ModTime().UnixNano(), 10) + ":" + fi.Mode().String()
	if st, ok := fi.Sys().(*syscall.Stat_t); ok {
		s += ":" + strconv.FormatUint(st.Ino, 10) + ":" + strconv.FormatInt(int64(st.Dev), 10)
	}
	return s
}

// JobsReader reads the jobs dir, incrementally. Used from one goroutine at a time (the poll).
type JobsReader struct {
	Dir string

	base  string
	cache map[string]cachedJob
}

type cachedJob struct {
	sig   string
	job   *jobInput
	empty bool
}

type jobsRead struct {
	jobs     []*jobInput
	empty    int // never started, or a dir without state.json
	problems []string
}

// Read is one poll: the sessions, how many are empty, what could not be read; the error of the
// jobs dir itself (a missing one is no session).
func (r *JobsReader) Read() (jobsRead, error) {
	var out jobsRead
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
	next := map[string]cachedJob{}
	add := func(c cachedJob) {
		if c.empty {
			out.empty++
		} else {
			out.jobs = append(out.jobs, c.job)
		}
	}
	for _, e := range entries {
		id := e.Name()
		// A link (to a dir or not) is never listed; files (pins.json) are not sessions; a dir whose
		// name is no job id (validJobID) is skipped: not counted, not reported, never read.
		if !e.IsDir() || !validJobID(id) {
			continue
		}
		dir, where, err := realInside(base, filepath.Join(r.Dir, id))
		if err != nil {
			out.problems = append(out.problems, id+" : "+err.Error())
			continue
		}
		if where != 1 {
			continue
		}
		statePath, tlPath := filepath.Join(dir, "state.json"), filepath.Join(dir, "timeline.jsonl")
		sfi, err := os.Lstat(statePath)
		switch {
		case err != nil && isGone(err):
			out.empty++ // only tmp/: a session that never wrote its state
			continue
		case err != nil:
			out.problems = append(out.problems, id+" : "+err.Error())
			continue
		case sfi.Mode()&fs.ModeSymlink != 0:
			out.problems = append(out.problems, id+" : state.json est un lien : non lu")
			continue
		case !sfi.Mode().IsRegular():
			out.problems = append(out.problems, id+" : state.json "+errNotRegular.Error())
			continue
		case sfi.Size() > maxStateBytes:
			out.problems = append(out.problems, id+" : state.json de "+strconv.FormatInt(sfi.Size()/1024, 10)+" Ko, "+errTooBig.Error())
			continue
		}
		tfi, terr := os.Lstat(tlPath)
		if terr != nil {
			tfi = nil
		}
		hasTL := tfi != nil && tfi.Mode().IsRegular() && tfi.Size() > 0
		sig := fileSig(sfi) + "|" + fileSig(tfi)
		if c, ok := r.cache[id]; ok && c.sig == sig {
			next[id] = c
			add(c)
			continue
		}
		data, err := readState(statePath)
		if err != nil {
			if !isGone(err) {
				out.problems = append(out.problems, id+" : state.json "+err.Error())
			}
			continue
		}
		j := parseJobState(id, data)
		if j == nil {
			continue // half-written or not a session: skipped this poll, as deck does
		}
		j.HasTimeline = hasTL
		if hasTL && j.kind() == "needs-you" && j.Needs == "" && j.Question == "" {
			if tail, err := readTail(tlPath, maxTimelineBytes); err == nil {
				j.LastText = waitingText(tail, j.Detail)
			}
		}
		c := cachedJob{sig: sig, job: j, empty: j.neverStarted()}
		next[id] = c
		add(c)
	}
	r.cache = next
	return out, nil
}

// loadAgentTimeline: the drawer's steps, newest first; a reason when it cannot be read.
func loadAgentTimeline(jobsDir, id string) ([]timelineEvent, string) {
	if !validJobID(id) {
		return nil, "hors de jobs/ : non lu"
	}
	base, err := realRoot(jobsDir)
	if err != nil {
		return nil, err.Error()
	}
	p := filepath.Join(jobsDir, id)
	if fi, err := os.Lstat(p); err != nil || !fi.IsDir() {
		return nil, "session disparue"
	}
	real, where, err := realInside(base, p)
	if err != nil || where != 1 {
		return nil, "hors de jobs/ : non lu"
	}
	data, err := readTail(filepath.Join(real, "timeline.jsonl"), maxTimelineBytes)
	if err != nil {
		if isGone(err) {
			return []timelineEvent{}, ""
		}
		return nil, "timeline.jsonl : " + err.Error()
	}
	ev := parseTimeline(data, timelineMax)
	slices.Reverse(ev)
	if ev == nil {
		ev = []timelineEvent{}
	}
	return ev, ""
}

// ---- derive --------------------------------------------------------------------

// Agent: one card of the tab, derived from a jobInput at a given now.
type Agent struct {
	ID, Name, Project, Branch, Cwd, State, Tempo string
	Kind, Column                                 string
	Mission, Current                             string
	Asking, Stale                                bool
	UpdatedAt                                    float64
	Age                                          string
	Chips                                        []Chip
	rows                                         rowsMemo
}

type agentsBoard struct {
	cols       [4][]*Agent
	total      int
	empty, old int
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

// agentColumnOf: deck's kind to a column. needs-you → Attend ta réponse; working → Travaille,
// Figé once silent over staleMs (board-only); stalled, failed and other (a state word deck does
// not know: nothing says it moves) → Figé, failed with a red chip; stopped and done → Terminé,
// stopped with a chip. The columns keep BG_ORDER: needs-you · stalled, failed · working · other
// · stopped, done, with working moved before stalled so the active work sits next to the ask.
func agentColumnOf(j *jobInput, kind string, now float64) (col string, stale bool, chips []Chip) {
	switch kind {
	case "needs-you":
		return "ask", false, nil
	case "working":
		if j.UpdatedAt > 0 && now-j.UpdatedAt > staleMs {
			return "stuck", true, []Chip{{Key: "stale", Label: "rien depuis " + strings.TrimPrefix(ageText(now, j.UpdatedAt), "il y a "), State: "info"}}
		}
		return "work", false, nil
	case "stalled":
		return "stuck", false, []Chip{{Key: "stalled", Label: "bloquée sans question", State: "info"}}
	case "failed":
		return "stuck", false, []Chip{{Key: "failed", Label: "échec", State: "fail"}}
	case "stopped":
		return "done", false, []Chip{{Key: "stopped", Label: "arrêtée", State: "info"}}
	case "done":
		return "done", false, nil
	}
	return "stuck", false, []Chip{{Key: "other", Label: j.State, State: "info"}}
}

func deriveAgent(j *jobInput, now float64) *Agent {
	kind := j.kind()
	col, stale, chips := agentColumnOf(j, kind, now)
	a := &Agent{
		ID: j.ID, Name: j.Name, Project: projectOf(j.Cwd), Branch: j.Branch, Cwd: j.Cwd, State: j.State, Tempo: j.Tempo,
		Kind: kind, Column: col, Mission: j.Intent, Stale: stale, UpdatedAt: j.UpdatedAt, Age: ageText(now, j.UpdatedAt), Chips: chips,
	}
	a.Current = j.Detail
	if col == "ask" {
		a.Asking = true
		// With a timeline, its waiting text rather than a detail that may echo the last prompt (a
		// timeline that does not read: no text).
		said := j.Detail
		if j.HasTimeline {
			said = j.LastText
		}
		a.Current = ""
		for _, s := range []string{j.Needs, j.Question, said} {
			if s != "" {
				a.Current = s
				break
			}
		}
	}
	if a.Current == a.Mission {
		a.Current = ""
	}
	return a
}

// deriveAgents: the shown cards by column, in BG_ORDER then newest update first (deck's sortBg),
// without the finished ones older than keepMs (deck's recentBg).
func deriveAgents(jobs []*jobInput, empty int, now float64) agentsBoard {
	b := agentsBoard{empty: empty}
	for _, j := range jobs {
		a := deriveAgent(j, now)
		if (a.Kind == "done" || a.Kind == "stopped") && now-a.UpdatedAt > keepMs {
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
	var parts []string
	if b.empty > 0 {
		parts = append(parts, plural(b.empty, "session vide masquée", "sessions vides masquées"))
	}
	if b.old > 0 {
		parts = append(parts, plural(b.old, "terminée depuis plus de 24 h masquée", "terminées depuis plus de 24 h masquées"))
	}
	return strings.Join(parts, " · ")
}

// ---- state and events ----------------------------------------------------------

type agentDrawer struct {
	id       string
	events   []timelineEvent // newest first; nil while loading
	err      string
	loadedAt float64 // the session's UpdatedAt the events were read for
	scroll   int
}

type agentsView struct {
	first, nVis, areaH         int
	sel                        selection
	docLines, bodyH, docScroll int
	cols                       [4]colLayout
}

type agentsState struct {
	reader   *JobsReader
	board    agentsBoard
	status   *boardStatus
	problems []string
	now      float64
	sel      *selState
	scroll   [4]int
	hscroll  int
	follow   bool
	drawer   *agentDrawer
	view     agentsView
	note     string // a one-off footer message (claude not on PATH)
}

type agentsPoll struct {
	board    agentsBoard
	problems []string
	now      float64
	clock    string
	err      error
}

type agentDrawerMsg struct {
	id     string
	at     float64
	events []timelineEvent
	err    string
}

// lookPath finds the claude binary `o` execs; a variable so the tests can stub it.
var lookPath = exec.LookPath

// setJobsDir turns the Agents tab on, reading dir at each poll.
func (m *Model) setJobsDir(dir string) {
	if dir == "" {
		m.ag.reader = nil
		return
	}
	m.ag.reader = &JobsReader{Dir: dir}
}

// pollAgents runs in the poll's Cmd goroutine.
func pollAgents(r *JobsReader) *agentsPoll {
	if r == nil {
		return nil
	}
	read, err := r.Read()
	t := time.Now()
	if err != nil {
		return &agentsPoll{err: err}
	}
	now := float64(t.UnixMilli())
	return &agentsPoll{board: deriveAgents(read.jobs, read.empty, now), problems: read.problems, now: now, clock: t.Format("15:04:05")}
}

func (m *Model) applyAgents(p *agentsPoll) tea.Cmd {
	if p == nil {
		return nil
	}
	a := &m.ag
	m.dirty = true
	if p.err != nil {
		a.status = &boardStatus{err: "jobs/ illisible : " + p.err.Error()}
		return nil
	}
	a.board, a.problems, a.now = p.board, p.problems, p.now
	a.status = &boardStatus{ok: true, count: p.board.total, time: p.clock}
	if d := a.drawer; d != nil {
		if ag := m.agentByID(d.id); ag != nil && ag.UpdatedAt != d.loadedAt {
			return m.agentDrawerCmd()
		}
	}
	return nil
}

func (m *Model) agentByID(id string) *Agent {
	for _, col := range m.ag.board.cols {
		for _, a := range col {
			if a.ID == id {
				return a
			}
		}
	}
	return nil
}

func (m *Model) agentDrawerCmd() tea.Cmd {
	d, r := m.ag.drawer, m.ag.reader
	if d == nil || r == nil {
		return nil
	}
	dir, id, at := r.Dir, d.id, 0.0
	if ag := m.agentByID(id); ag != nil {
		at = ag.UpdatedAt
	}
	return func() tea.Msg {
		ev, err := loadAgentTimeline(dir, id)
		return agentDrawerMsg{id: id, at: at, events: ev, err: err}
	}
}

func (m *Model) applyAgentDrawer(msg agentDrawerMsg) {
	d := m.ag.drawer
	if d == nil || d.id != msg.id {
		return // closed, or another session opened since
	}
	d.events, d.err, d.loadedAt = msg.events, msg.err, msg.at
	m.dirty = true
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

func (m *Model) openAgentDrawer(col, idx int, id string) tea.Cmd {
	a := &m.ag
	a.sel = &selState{col: col, idx: idx, id: id}
	a.drawer = &agentDrawer{id: id}
	a.follow, m.dirty = true, true
	return m.agentDrawerCmd()
}

// attachTo: quit and let main exec `claude attach <id>`; without claude on PATH, say the command.
// The id (the jobs dir name) and not the name: a part of a name also matches, an id is one session.
func (m *Model) attachTo(id string) tea.Cmd {
	if !validJobID(id) {
		return nil
	}
	if _, err := lookPath("claude"); err != nil {
		m.ag.note, m.dirty = "claude introuvable dans le PATH : lance  claude attach "+id, true
		return nil
	}
	m.attach, m.quit = id, true
	return tea.Quit
}

func (m *Model) keyAgents(ev string) tea.Cmd {
	a := &m.ag
	if a.note != "" {
		a.note, m.dirty = "", true
	}
	if a.drawer != nil {
		return m.keyAgentDrawer(ev)
	}
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
	case "enter":
		if sel.idx >= 0 {
			return m.openAgentDrawer(sel.col, sel.idx, a.board.cols[sel.col][sel.idx].ID)
		}
	case "o":
		if sel.idx >= 0 {
			return m.attachTo(a.board.cols[sel.col][sel.idx].ID)
		}
	case "r":
		return m.pollCmd()
	}
	return nil
}

func (m *Model) scrollAgentDrawer(n int) {
	if m.dirty || m.frame == "" {
		m.render()
	}
	v := m.ag.view
	m.ag.drawer.scroll = clamp(v.docScroll+n, 0, max(0, v.docLines-v.bodyH))
	m.dirty = true
}

func (m *Model) keyAgentDrawer(ev string) tea.Cmd {
	d := m.ag.drawer
	page := func() int {
		if m.dirty || m.frame == "" {
			m.render()
		}
		return max(1, m.ag.view.bodyH-2)
	}
	switch ev {
	case "esc", "q":
		m.ag.drawer, m.dirty = nil, true
	case "up", "k":
		m.scrollAgentDrawer(-1)
	case "down", "j":
		m.scrollAgentDrawer(1)
	case "pgup":
		m.scrollAgentDrawer(-page())
	case "pgdn", "space":
		m.scrollAgentDrawer(page())
	case "home", "g":
		m.scrollAgentDrawer(-far)
	case "end", "G":
		m.scrollAgentDrawer(far)
	case "o":
		return m.attachTo(d.id)
	case "r":
		return m.pollCmd()
	}
	return nil
}

func (m *Model) clickAgents(h *hit) tea.Cmd {
	a := &m.ag
	if a.drawer == nil {
		switch h.kind {
		case hitTab:
			m.setTab(h.col)
		case hitCard:
			return m.openAgentDrawer(h.col, h.idx, h.id)
		}
		return nil
	}
	if h.kind == hitClose || h.kind == hitScrim {
		a.drawer, m.dirty = nil, true
	}
	return nil
}

// wheelAgents: as wheel on the runs board, for the agents columns and drawer.
func (m *Model) wheelAgents(h *hit, dir int) {
	a := &m.ag
	if a.drawer != nil {
		if h.kind == hitScrim {
			return
		}
		ds := clamp(a.view.docScroll+dir*wheelLines, 0, max(0, a.view.docLines-a.view.bodyH))
		if ds != a.drawer.scroll {
			a.drawer.scroll, a.view.docScroll, m.dirty = ds, ds, true
		}
		return
	}
	if (h.kind != hitCard && h.kind != hitCol) || h.col < 0 || h.col >= len(AgentColumns) {
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

var keysAgents = "←→↑↓ naviguer · ⏎ ouvrir · o reprendre · a runs · q quitter"

// agentRows: rows of exactly cw cells: rounded box, name, project · branch and age, mission,
// the question (or the current step), chips.
func agentRows(a *Agent, cw int, selected bool) *rowsMemo {
	if m := &a.rows; m.rows != nil && m.cw == cw && m.sel == selected {
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
	name, nameSt := a.Name, st(P.text).bold()
	if name == "" {
		name, nameSt = "sans nom · "+a.ID, st(P.muted)
	}
	top = append(top, fitCells(cellsOf(name, nameSt), iw-cellsWidth(top))...)
	body = append(body, top)

	where := a.Project
	if a.Branch != "" {
		where += " · " + a.Branch
	}
	age := cellsOf(a.Age, st(P.muted))
	if room := iw - cellsWidth(age) - 1; room >= 4 {
		line := fitCells(cellsOf(where, st(P.faint)), room)
		line = append(line, spaces(iw-cellsWidth(line)-cellsWidth(age), bgOnly(bg))...)
		body = append(body, append(line, age...))
	} else {
		body = append(body, fitCells(cellsOf(where, st(P.faint)), iw), fitCells(age, iw))
	}
	if a.Mission != "" {
		body = append(body, wrapText(a.Mission, iw, 2, st(P.text))...)
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
	a.rows = rowsMemo{cw: cw, sel: selected, rows: rows, dotOff: dotOff}
	return &a.rows
}

// renderAgents is render for the Agents tab: same header, columns, footer and drawer layout.
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
			rows := agentRows(ag, cw, c == sel.col && i == sel.idx)
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
			firstRow, shown := -1, 0
			for r, row := range rows.rows {
				at := lay.tops[i] + r - s
				if at < 0 || at >= areaH {
					continue
				}
				g.putMax(x, cardsTop+at, row, x+cw)
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
	keys := cellsOf(keysAgents, fg(P.faint))
	kw := W - 2*margin
	if len(info) > 0 {
		kw -= min(cellsWidth(info), kw/2) + 2
	}
	g.put(margin, H-1, fitCells(keys, max(0, kw)))
	if len(info) > 0 && kw > 8 {
		iw := W - 2*margin - kw - 2
		ic := fitCells(info, iw)
		g.put(W-margin-cellsWidth(ic), H-1, ic)
	}

	if a.drawer != nil {
		m.drawAgentDrawer(g, W, H, &view)
	}
	a.view = view
	m.frame = frameOf(g)
	m.dirty = false
}

// stateWord: a timeline step's state in the tab's words.
func stateWord(s string) (string, rgb) {
	switch strings.ToLower(s) {
	case "blocked":
		return "attend", P.human
	case "working":
		return "travaille", P.active
	case "done", "completed":
		return "terminé", P.merged
	case "failed", "error":
		return "échec", P.human
	case "stopped", "killed":
		return "arrêtée", P.muted
	}
	return s, P.muted
}

// timelineLines: each step as `date state detail`, its reply text under it (3 lines at most).
func timelineLines(evs []timelineEvent, w int) []mdLine {
	const wordW = 10
	var out []mdLine
	for _, e := range evs {
		stamp := time.UnixMilli(int64(e.At)).Format("02/01 15:04")
		word, wc := stateWord(e.State)
		prefix := cellsOf(stamp+" ", fg(P.faint))
		prefix = append(prefix, padTo(cellsOf(word, fg(wc)), wordW, P.panel)...)
		pw := cellsWidth(prefix)
		indent := spaces(pw, bgOnly(P.panel))
		rest := max(1, w-pw)
		for i, l := range wrapCells(cellsOf(e.Detail, fg(P.text)), rest) {
			lead := indent
			if i == 0 {
				lead = prefix
			}
			out = append(out, mdLine{cells: append(slices.Clone(lead), l...)})
		}
		if t := oneLine(e.Text); t != "" && t != e.Detail {
			for _, l := range wrapText(t, rest, 3, fg(P.muted)) {
				out = append(out, mdLine{cells: append(slices.Clone(indent), l...)})
			}
		}
	}
	return out
}

func (m *Model) drawAgentDrawer(g grid, W, H int, view *agentsView) {
	d := m.ag.drawer
	dw := min(drawerW, W)
	x0 := W - dw
	for y := range H {
		for x := 0; x < x0; x++ {
			g[y][x] = fadeCell(g[y][x], scrim, 0.45)
		}
		g.fillRow(y, x0, W, P.panel)
	}
	if x0 > 0 {
		m.hits = append(m.hits, hit{x: 0, y: 0, w: x0, h: H, kind: hitScrim})
	}
	m.hits = append(m.hits, hit{x: x0, y: 0, w: dw, h: H, kind: hitDrawer})
	cx := x0
	if x0 > 0 {
		for y := range H {
			g.put(x0, y, cellsOf(cardBox.Left, fg(P.line)))
		}
		cx = x0 + 1
	}
	pad := 1
	if dw >= 40 {
		pad = 2
	}
	left, right := cx+pad, W-pad
	ag := m.agentByID(d.id)

	y := 0
	if H >= 16 {
		y = 1
	}
	closeX := right - 1
	g.put(closeX, y, cellsOf("×", fg(P.muted).bold()))
	m.hits = append(m.hits, hit{x: closeX - 1, y: max(0, y-1), w: 3, h: 3, kind: hitClose})
	headW := max(1, closeX-2-left)
	line := func(cells []cell) {
		g.put(left, y, fitCells(cells, headW))
		y++
	}
	wrapped := func(text string, n int, st style) {
		for _, l := range wrapText(text, headW, n, st) {
			g.put(left, y, l)
			y++
		}
	}
	if ag == nil {
		line(cellsOf(d.id+" · session disparue", fg(P.muted)))
	} else {
		state := ag.State
		if ag.Tempo != "" {
			state += "/" + ag.Tempo
		}
		line(cellsOf(strings.Join([]string{ag.ID, AgentColumns[colIndex(ag.Column)].Label, state, ag.Age}, " · "), fg(P.muted)))
		if ag.Name != "" {
			wrapped(ag.Name, 2, fg(P.text).bold())
		} else {
			line(cellsOf("sans nom", fg(P.muted).bold()))
		}
		where := ag.Project
		if ag.Branch != "" {
			where += " · " + ag.Branch
		}
		line(cellsOf(where+" — "+ag.Cwd, fg(P.faint)))
		if ag.Mission != "" {
			wrapped("Mission : "+ag.Mission, 3, fg(P.text))
		}
		if ag.Current != "" {
			if ag.Asking {
				wrapped(ag.Current, 4, fg(P.human))
			} else {
				wrapped(ag.Current, 2, fg(P.muted))
			}
		}
		line(toCells("claude attach "+ag.ID, fg(P.active).bold(), cellsOf("Reprendre : ", fg(P.muted))))
	}
	y++
	g.put(cx, y, cellsOf(strings.Repeat(cardBox.Top, max(0, W-cx)), fg(P.line)))
	bodyTop := y + 1
	keysY := H - 1
	bodyH := max(0, keysY-bodyTop)

	bw := right - left
	var tail []cell
	if bw >= 1 && bodyH > 0 {
		var lines []mdLine
		switch {
		case d.err != "":
			lines = note(d.err, bw, P.human)
		case d.events == nil:
			lines = note("chargement…", bw, P.faint)
		case len(d.events) == 0:
			lines = note("Aucune étape dans la timeline.", bw, P.faint)
		default:
			lines = timelineLines(d.events, bw)
		}
		ds := clamp(d.scroll, 0, max(0, len(lines)-bodyH))
		view.docLines, view.bodyH, view.docScroll = len(lines), bodyH, ds
		for r := 0; r < bodyH && ds+r < len(lines); r++ {
			g.putMax(left, bodyTop+r, lines[ds+r].cells, right)
		}
		m.hits = append(m.hits, hit{x: cx, y: bodyTop, w: W - cx, h: bodyH, kind: hitDoc})
		if len(lines) > bodyH {
			tail = cellsOf(strconv.Itoa(ds+1)+"-"+strconv.Itoa(min(ds+bodyH, len(lines)))+"/"+strconv.Itoa(len(lines)), fg(P.faint))
		}
	}
	keys := cellsOf("↑↓ défiler · pgup/pgdn page · o reprendre ici · esc fermer", fg(P.faint))
	if m.ag.note != "" {
		keys = cellsOf(m.ag.note, fg(P.human))
	}
	kw := right - left
	if len(tail) > 0 {
		kw -= cellsWidth(tail) + 2
	}
	g.put(left, keysY, fitCells(keys, kw))
	if len(tail) > 0 && kw > 0 {
		g.put(right-cellsWidth(tail), keysY, tail)
	}
}

// agentsSnapshot: one frame of the Agents tab read from jobsDir, ANSI stripped, no terminal
// (for the coordinator and the check): --agents-snapshot <width> <height> [open].
func agentsSnapshot(args []string, jobsDir string, out io.Writer) int {
	if len(args) < 2 || len(args) > 3 || (len(args) == 3 && args[2] != "open") {
		return -1
	}
	w, err1 := strconv.Atoi(args[0])
	h, err2 := strconv.Atoi(args[1])
	if err1 != nil || err2 != nil || w < 1 || h < 1 {
		return -1
	}
	m := newModel("", "", "", w, h)
	m.setJobsDir(jobsDir)
	m.tab = tabAgents
	m.applyAgents(pollAgents(m.ag.reader))
	if len(args) == 3 {
		if sel := m.agentSelection(); sel.idx >= 0 {
			id := m.ag.board.cols[sel.col][sel.idx].ID
			m.openAgentDrawer(sel.col, sel.idx, id)
			ev, err := loadAgentTimeline(jobsDir, id)
			m.applyAgentDrawer(agentDrawerMsg{id: id, at: m.agentByID(id).UpdatedAt, events: ev, err: err})
		}
	}
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
