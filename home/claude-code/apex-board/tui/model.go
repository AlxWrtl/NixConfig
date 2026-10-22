package main

// State and events (port of tui.js state / selection / reduce, driven by Bubble Tea). Disk work
// runs in tea.Cmds, off the UI goroutine: the 2 s poll (incremental Reader) and every drawer
// read. View draws only when something changed; the wheel scrolls from the last render's
// layout and hit map, without drawing to hit-test.

import (
	"math"
	"slices"
	"time"

	tea "charm.land/bubbletea/v2"
)

const (
	// Disk poll period, as the page's POLL_MS.
	pollEvery = 2 * time.Second
	// Pulse period of a live card's dot.
	tickEvery = time.Second
	// Lines one wheel notch scrolls.
	wheelLines = 3
)

type boardStatus struct {
	ok    bool
	count int
	time  string
	err   string
}

// selState: the selected card; id "" when the selection is a place in an empty column.
type selState struct {
	col, idx int
	id       string
}

type drawerState struct {
	id         string     // the card's key
	run        string     // its run id ("" reads as id)
	src        *runSource // its agent source, nil for the board's own runs
	files      []string   // nil while loading
	tones      map[string]string
	path       string
	hasPath    bool
	doc        *FileRead // nil while loading
	focus      string    // "files" | "doc"
	docScroll  int
	fileScroll int
}

// Model is the board; a pointer so View can keep what it drew (View and Update run on the
// same goroutine in Bubble Tea, see tea.go's event loop).
type Model struct {
	repo          string
	width, height int
	runs          []*RunInput
	now           float64
	cards         []*Card
	groups        map[string]*Group
	status        *boardStatus
	problems      []string
	sel           *selState
	scroll        [6]int
	hscroll       int
	drawer        *drawerState
	tick          bool
	follow        bool // keep the selected card in view (keys); off after the wheel
	quit          bool
	tab           int // tabRuns | tabAgents
	ag            agentsState

	runsDir, budgetDir string
	reader             *Reader
	polling            bool

	dirty   bool
	frame   string
	hits    []hit
	view    viewInfo
	g       grid
	docMemo docMemo
}

// newModel: a fresh board of width × height, as tui.js initialState.
func newModel(runsDir, budgetDir, repo string, width, height int) *Model {
	m := &Model{
		repo: repo, width: width, height: height, tick: true, follow: true, dirty: true,
		runsDir: runsDir, budgetDir: budgetDir, reader: &Reader{RunsDir: runsDir, BudgetDir: budgetDir, Agents: true},
	}
	m.setRuns(nil, 0)
	return m
}

// setRuns derives cards and columns from board rules only.
func (m *Model) setRuns(runs []*RunInput, now float64) {
	cards := make([]*Card, len(runs))
	for i, r := range runs {
		cards[i] = deriveRun(r, now)
	}
	m.applyCards(runs, now, cards, groupRuns(cards))
}

func (m *Model) applyCards(runs []*RunInput, now float64, cards []*Card, groups map[string]*Group) {
	m.runs, m.now, m.cards, m.groups = runs, now, cards, groups
	m.dirty = true
}

func (m *Model) columnCards(c int) []*Card { return m.groups[Columns[c].Key].Cards }

// selection: the selected column and index (-1 in an empty column), by card id first so it
// follows a moving card.
func (m *Model) selection() selection {
	if m.sel != nil {
		if m.sel.id != "" {
			for c := range Columns {
				if i := slices.IndexFunc(m.columnCards(c), func(x *Card) bool { return x.key() == m.sel.id }); i >= 0 {
					return selection{c, i}
				}
			}
		}
		col := clamp(m.sel.col, 0, len(Columns)-1)
		if n := len(m.columnCards(col)); n > 0 {
			return selection{col, clamp(m.sel.idx, 0, n-1)}
		}
		return selection{col, -1}
	}
	for c := range Columns {
		if len(m.columnCards(c)) > 0 {
			return selection{c, 0}
		}
	}
	return selection{0, -1}
}

// ---- messages and commands ----------------------------------------------------

type tickMsg struct{}
type pollTickMsg struct{}

type pollMsg struct {
	runs     []*RunInput
	cards    []*Card
	groups   map[string]*Group
	problems []string
	now      float64
	clock    string
	err      error
	agents   *agentsPoll // nil without a session-state dir
}

type drawerMsg struct {
	id, want string
	data     DrawerData
}

type docMsg struct {
	id, path string
	doc      FileRead
}

func tickCmd() tea.Cmd {
	return tea.Tick(tickEvery, func(time.Time) tea.Msg { return tickMsg{} })
}

func pollTickCmd() tea.Cmd {
	return tea.Tick(pollEvery, func(time.Time) tea.Msg { return pollTickMsg{} })
}

// pollCmd reads and derives in the Cmd goroutine, the runs and the agent sessions; one poll at a
// time owns the Readers.
func (m *Model) pollCmd() tea.Cmd {
	if m.polling {
		return nil
	}
	m.polling = true
	r, jr := m.reader, m.ag.reader
	return func() tea.Msg {
		agents := pollAgents(jr)
		runs, problems, err := r.Read()
		t := time.Now()
		if err != nil {
			return pollMsg{err: err, agents: agents}
		}
		now := float64(t.UnixMilli())
		cards := make([]*Card, len(runs))
		for i, in := range runs {
			cards[i] = deriveRun(in, now)
		}
		return pollMsg{runs: runs, cards: cards, groups: groupRuns(cards), problems: problems, now: now, clock: t.Format("15:04:05"), agents: agents}
	}
}

func (m *Model) drawerCmd() tea.Cmd {
	d := m.drawer
	if d == nil {
		return nil
	}
	runsDir, src, id, run, want := m.runsDir, d.src, d.id, d.runID(), ""
	if d.hasPath {
		want = d.path
	}
	return func() tea.Msg { return drawerMsg{id: id, want: want, data: loadDrawerFrom(runsDir, src, run, want)} }
}

// runID: the drawer's run dir name in its source.
func (d *drawerState) runID() string {
	if d.run == "" {
		return d.id
	}
	return d.run
}

func (m *Model) docCmd() tea.Cmd {
	runsDir, src, id, run, p := m.runsDir, m.drawer.src, m.drawer.id, m.drawer.runID(), m.drawer.path
	return func() tea.Msg { return docMsg{id: id, path: p, doc: loadDocFrom(runsDir, src, run, p)} }
}

// Init: first poll now, then every pollEvery after each result; the clock tick.
func (m *Model) Init() tea.Cmd { return tea.Batch(m.pollCmd(), tickCmd()) }

// View draws when the state changed since the last frame.
func (m *Model) View() tea.View {
	if m.dirty || m.frame == "" {
		m.render()
	}
	v := tea.NewView(m.frame)
	v.AltScreen = true
	v.MouseMode = tea.MouseModeCellMotion
	v.WindowTitle = "APEX board"
	return v
}

// ensureView: the layout of the current state, for keys that read it (page size, doc length).
func (m *Model) ensureView() viewInfo {
	if m.dirty || m.frame == "" {
		m.render()
	}
	return m.view
}

// Update: one message, the commands it needs.
func (m *Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height, m.dirty = msg.Width, msg.Height, true
	case tickMsg:
		m.tick, m.dirty = !m.tick, true
		return m, tickCmd()
	case pollTickMsg:
		return m, m.pollCmd()
	case pollMsg:
		return m, m.applyPoll(msg)
	case drawerMsg:
		m.applyDrawer(msg)
	case pickMsg:
		m.applyPick(msg)
	case placeStartMsg:
		return m, m.applyPlaceStart(msg)
	case placeTickMsg:
		return m, m.applyPlaceTick(msg)
	case placeFocusMsg:
		return m, m.applyPlaceFocus(msg)
	case placedMsg:
		m.applyPlaced(msg)
	case stopMsg:
		return m, m.applyStop(msg)
	case newAgentMsg:
		return m, m.applyNewAgent(msg)
	case docMsg:
		if d := m.drawer; d != nil && d.id == msg.id && d.hasPath && d.path == msg.path {
			doc := msg.doc
			d.doc, m.dirty = &doc, true
		}
	case tea.KeyPressMsg:
		return m, m.key(keyName(msg))
	case tea.MouseClickMsg:
		if msg.Button == tea.MouseLeft {
			return m, m.click(msg.X, msg.Y)
		}
	case tea.MouseWheelMsg:
		if m.tab == tabAgents {
			if h := hitAt(m.hits, msg.X, msg.Y); h != nil && (msg.Button == tea.MouseWheelUp || msg.Button == tea.MouseWheelDown) {
				dir := 1
				if msg.Button == tea.MouseWheelUp {
					dir = -1
				}
				m.wheelAgents(h, dir)
			}
			return m, nil
		}
		switch msg.Button {
		case tea.MouseWheelUp:
			m.wheel(msg.X, msg.Y, -1)
		case tea.MouseWheelDown:
			m.wheel(msg.X, msg.Y, 1)
		}
	}
	return m, nil
}

func (m *Model) applyPoll(msg pollMsg) tea.Cmd {
	m.polling = false
	next := pollTickCmd()
	m.applyAgents(msg.agents)
	if msg.err != nil {
		// The runs dir itself is unreadable: keep the last board and say why.
		m.status, m.dirty = &boardStatus{err: msg.err.Error()}, true
		return next
	}
	m.applyCards(msg.runs, msg.now, msg.cards, msg.groups)
	m.problems = msg.problems
	m.status = &boardStatus{ok: true, count: len(msg.runs), time: msg.clock}
	if m.drawer != nil {
		if c := m.cardByID(m.drawer.id); c != nil && c.Live {
			return tea.Batch(next, m.drawerCmd())
		}
	}
	return next
}

func (m *Model) applyDrawer(msg drawerMsg) {
	d := m.drawer
	want := ""
	if d != nil && d.hasPath {
		want = d.path
	}
	if d == nil || d.id != msg.id || want != msg.want {
		return // closed, or another file asked since
	}
	data := msg.data
	if data.Path != want {
		d.docScroll = 0
	}
	d.files, d.tones = data.Files, data.Tones
	d.path, d.hasPath = data.Path, data.Path != ""
	doc := data.Doc
	d.doc = &doc
	m.dirty = true
}

// keyName: the event names of tui.js parseInput.
func keyName(k tea.KeyPressMsg) string {
	switch s := k.String(); s {
	case "pgdown":
		return "pgdn"
	case "shift+tab":
		return "tab"
	case "shift+n": // a press reported without its text (kitty keyboard)
		return "N"
	case "shift+p":
		return "P"
	case "ctrl+c":
		return "ctrl-c"
	default:
		return s
	}
}

func (m *Model) key(ev string) tea.Cmd {
	if ev == "ctrl-c" {
		m.quit = true
		return tea.Quit
	}
	if m.tab == tabAgents {
		return m.keyAgents(ev)
	}
	if m.drawer != nil {
		return m.keyDrawer(ev)
	}
	return m.keyBoard(ev)
}

func (m *Model) pick(c, i int) {
	list := m.columnCards(c)
	idx := -1
	if len(list) > 0 {
		idx = clamp(i, 0, len(list)-1)
	}
	m.sel = &selState{col: c, idx: max(idx, 0)}
	if idx >= 0 {
		m.sel.id = list[idx].key()
	}
	m.follow, m.dirty = true, true
}

func (m *Model) openDrawer(col, idx int, id string) tea.Cmd {
	m.sel = &selState{col: col, idx: idx, id: id}
	m.drawer = &drawerState{id: id, tones: map[string]string{}, focus: "files"}
	if c := m.cardByID(id); c != nil {
		m.drawer.run, m.drawer.src = c.ID, c.source
	}
	m.follow, m.dirty = true, true
	return m.drawerCmd()
}

const far = math.MaxInt32

func (m *Model) keyBoard(ev string) tea.Cmd {
	sel := m.selection()
	row := max(sel.idx, 0)
	switch ev {
	case "q":
		m.quit = true
		return tea.Quit
	case "a", "tab":
		m.setTab(tabAgents)
	case "left", "h":
		m.pick(max(0, sel.col-1), row)
	case "right", "l":
		m.pick(min(len(Columns)-1, sel.col+1), row)
	case "up", "k":
		m.pick(sel.col, sel.idx-1)
	case "down", "j":
		m.pick(sel.col, sel.idx+1)
	case "home", "g":
		m.pick(sel.col, 0)
	case "end", "G":
		m.pick(sel.col, far)
	case "pgup":
		m.pick(sel.col, sel.idx-pageCards)
	case "pgdn", "space":
		m.pick(sel.col, sel.idx+pageCards)
	case "enter":
		if sel.idx >= 0 {
			return m.openDrawer(sel.col, sel.idx, m.columnCards(sel.col)[sel.idx].key())
		}
	case "r":
		return m.pollCmd()
	}
	return nil
}

func (m *Model) fileAt(i int) tea.Cmd {
	d := m.drawer
	if len(d.files) == 0 {
		return nil
	}
	p := d.files[clamp(i, 0, len(d.files)-1)]
	m.dirty = true
	if d.hasPath && p == d.path {
		d.focus = "files"
		return nil
	}
	d.path, d.hasPath, d.doc, d.docScroll, d.focus = p, true, nil, 0, "files"
	return m.docCmd()
}

func (m *Model) scrollDoc(n int) {
	v := m.ensureView()
	d := m.drawer
	d.docScroll = clamp(v.docScroll+n, 0, max(0, v.docLines-v.bodyH))
	m.dirty = true
}

func (m *Model) keyDrawer(ev string) tea.Cmd {
	d := m.drawer
	at := -1
	if d.hasPath {
		at = slices.Index(d.files, d.path)
	}
	page := func() int { return max(1, m.ensureView().bodyH-2) }
	switch ev {
	case "esc", "q":
		m.drawer, m.dirty = nil, true
	case "tab":
		if d.focus == "files" {
			d.focus = "doc"
		} else {
			d.focus = "files"
		}
		m.dirty = true
	case "left", "h":
		d.focus, m.dirty = "files", true
	case "right", "l", "enter":
		d.focus, m.dirty = "doc", true
	case "up", "k":
		if d.focus == "doc" {
			m.scrollDoc(-1)
		} else {
			return m.fileAt(at - 1)
		}
	case "down", "j":
		if d.focus == "doc" {
			m.scrollDoc(1)
		} else {
			return m.fileAt(at + 1)
		}
	case "pgup":
		m.scrollDoc(-page())
	case "pgdn", "space":
		m.scrollDoc(page())
	case "home", "g":
		if d.focus == "doc" {
			m.scrollDoc(-far)
		} else {
			return m.fileAt(0)
		}
	case "end", "G":
		if d.focus == "doc" {
			m.scrollDoc(far)
		} else {
			return m.fileAt(len(d.files) - 1)
		}
	case "r":
		return m.pollCmd()
	}
	return nil
}

func (m *Model) click(x, y int) tea.Cmd {
	h := hitAt(m.hits, x, y)
	if m.tab == tabAgents {
		return m.clickAgents(h) // a click on nothing still disarms a stop
	}
	if h == nil {
		return nil
	}
	if m.drawer == nil {
		if h.kind == hitTab {
			m.setTab(h.col)
		}
		if h.kind == hitCard {
			return m.openDrawer(h.col, h.idx, h.id)
		}
		if h.kind == hitRefresh {
			return m.pollCmd()
		}
		return nil
	}
	switch h.kind {
	case hitClose, hitScrim:
		m.drawer, m.dirty = nil, true
	case hitFile:
		return m.fileAt(slices.Index(m.drawer.files, h.path))
	}
	return nil
}

// wheel scrolls what is under the pointer by wheelLines per notch, from the last render's
// layout. On the board the selection stays while any row of it is visible; once it has left
// the viewport it moves to the nearest card still in view, so the next frame does not jump back.
func (m *Model) wheel(x, y, dir int) {
	h := hitAt(m.hits, x, y)
	if h == nil {
		return
	}
	if m.drawer != nil {
		if h.kind == hitScrim {
			return
		}
		d := m.drawer
		ds := clamp(m.view.docScroll+dir*wheelLines, 0, max(0, m.view.docLines-m.view.bodyH))
		if ds != d.docScroll {
			d.docScroll, m.view.docScroll, m.dirty = ds, ds, true
		}
		return
	}
	if h.kind != hitCard && h.kind != hitCol {
		return
	}
	c := h.col
	lay, areaH := m.view.cols[c], m.view.areaH
	s := clamp(m.scroll[c]+dir*wheelLines, 0, max(0, lay.total-areaH))
	if s == m.scroll[c] {
		return
	}
	m.scroll[c], m.follow, m.dirty = s, false, true
	sel := m.view.sel
	if sel.col != c || sel.idx < 0 || sel.idx >= len(lay.tops) {
		return
	}
	shown := func(i int) bool { return lay.tops[i] < s+areaH && lay.tops[i]+lay.heights[i] > s }
	if shown(sel.idx) {
		return
	}
	pick := -1
	if dir > 0 {
		for i := range lay.tops {
			if shown(i) {
				pick = i
				break
			}
		}
	} else {
		for i := len(lay.tops) - 1; i >= 0; i-- {
			if shown(i) {
				pick = i
				break
			}
		}
	}
	if pick >= 0 {
		m.sel = &selState{col: c, idx: pick, id: lay.ids[pick]}
		m.view.sel = selection{c, pick}
	}
}
