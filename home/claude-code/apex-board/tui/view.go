package main

// The screen (port of tui.js renderBoard / cardRows / drawHeader / drawDrawer): header, six
// columns of rounded cards with chips, footer, and the right drawer. render also keeps the hit
// map and each column's layout, so a mouse event is resolved without drawing again.

import (
	"strconv"
	"strings"

	"charm.land/lipgloss/v2"
)

const (
	// The page's drawer is min(920px, 100vw): about 100 columns.
	drawerW = 100
	// Board geometry: side margin, gap between columns, narrowest column before scrolling sideways.
	margin = 2
	gap    = 3
	minCol = 20
	// Cards a PgUp / PgDn moves on the board.
	pageCards = 5
)

var (
	footerText = strings.Join([]string{"/apex <tâche>", "/apex -x <tâche>", "apex: +1 tour", "/deck"}, "   ")
	keysBoard  = "←→↑↓ naviguer · ⏎ ouvrir · esc fermer · a agents · q quitter"
	cardBox    = lipgloss.RoundedBorder()
)

func labelOf(key string) string {
	for _, c := range Columns {
		if c.Key == key {
			return c.Label
		}
	}
	return key
}

func clamp(n, lo, hi int) int { return max(lo, min(hi, n)) }

type hitKind uint8

const (
	hitCard hitKind = iota + 1
	hitCol
	hitFile
	hitClose
	hitScrim
	hitDoc
	hitDrawer
	hitTab  // col: the tab index
	hitStop // an agent card's ×: col, idx, id as hitCard
)

type hit struct {
	x, y, w, h int
	kind       hitKind
	col, idx   int
	id, path   string
}

func hitAt(hits []hit, x, y int) *hit {
	for k := len(hits) - 1; k >= 0; k-- {
		h := &hits[k]
		if x >= h.x && x < h.x+h.w && y >= h.y && y < h.y+h.h {
			return h
		}
	}
	return nil
}

// colLayout: where each card of a drawn column sits, in rows of the column's content.
type colLayout struct {
	tops, heights []int
	ids           []string
	total         int
}

type selection struct{ col, idx int }

// viewInfo: what the last render drew, for the next event.
type viewInfo struct {
	first, nVis, areaH                     int
	sel                                    selection
	docLines, bodyH, docScroll, fileScroll int
	cols                                   [6]colLayout
}

// rowsMemo: a card's rows for one (width, selected), drawn with the dot lit; dotOff is the
// dot of the other tick, patched in at draw time so the 1 s pulse redraws no card.
// Cards are new after each poll.
type rowsMemo struct {
	cw     int
	sel    bool
	armed  bool // agent cards: the × lit (a stop asked)
	rows   [][]cell
	dotOff cell
}

// pulses: a live card still at work carries the pulsing dot; a Terminé card, live or not, none.
func (c *Card) pulses() bool { return c.Live && c.Column != "done" }

// chipLines: the chips row, flowed onto as many lines as the card needs.
func chipLines(chips []Chip, iw int, bg rgb) [][]cell {
	lines := [][]cell{nil}
	for _, c := range chips {
		l, r, f, edge, cbg := "[", "]", P.faint, P.faint, bg
		switch c.State {
		case "info":
			f, edge = P.muted, P.line
		case "pass":
			l, r, f, edge, cbg = " ", " ", P.pass, P.pass, mix(P.pass, bg, 0.14)
		case "fail":
			f, edge = P.human, P.human
		case "used":
			l, r, f, edge, cbg = " ", " ", P.changes, P.changes, mix(P.changes, bg, 0.16)
		}
		label := fitCells(cellsOf(c.Label, fgbg(f, cbg)), max(1, iw-2))
		chip := make([]cell, 0, len(label)+2)
		chip = append(chip, cell{ch: l, w: 1, st: fgbg(edge, cbg)})
		chip = append(chip, label...)
		chip = append(chip, cell{ch: r, w: 1, st: fgbg(edge, cbg)})
		line := lines[len(lines)-1]
		used := cellsWidth(line)
		if used > 0 && used+1+cellsWidth(chip) > iw {
			lines = append(lines, chip)
			continue
		}
		if used > 0 {
			line = append(line, cell{ch: " ", w: 1, st: bgOnly(bg)})
		}
		lines[len(lines)-1] = append(line, chip...)
	}
	return lines
}

// cardRows: rows of exactly cw cells: rounded box, top row, title, branch, chips, À-toi reasons.
func cardRows(card *Card, cw int, selected bool) *rowsMemo {
	if m := &card.rows; m.rows != nil && m.cw == cw && m.sel == selected {
		return m
	}
	human := card.Column == "human"
	bg := P.card
	if selected {
		bg = P.cardHover
	}
	border := P.line
	switch {
	case selected:
		border = P.active
	case human:
		border = P.human
	case card.Live:
		border = mix(P.active, P.line, 0.35)
	}
	iw := max(1, cw-4)
	st := func(f rgb) style { return fgbg(f, bg) }
	var body [][]cell

	var top []cell
	if card.pulses() {
		top = toCells("● ", st(P.active), top)
	}
	dotOff := cell{ch: "●", w: 1, st: st(P.faint)}
	var flag []cell
	if card.Flag != nil {
		f := P.muted
		if human {
			f = P.human
		}
		flag = cellsOf(strings.ToUpper(*card.Flag), st(f).bold())
	}
	flagW := cellsWidth(flag)
	room := iw - cellsWidth(top)
	if flagW > 0 {
		room -= flagW + 1
	}
	top = append(top, fitCells(cellsOf(card.ID, st(P.muted)), room)...)
	if flagW > 0 {
		top = append(top, spaces(iw-cellsWidth(top)-flagW, bgOnly(bg))...)
		top = append(top, flag...)
	}
	body = append(body, top)
	body = append(body, wrapText(card.Title, iw, 3, st(P.text))...)
	if card.Branch != nil {
		body = append(body, fitCells(cellsOf(*card.Branch, st(P.faint)), iw))
	}
	body = append(body, chipLines(card.Chips, iw, bg)...)
	if human {
		body = append(body, cellsOf(strings.Repeat(cardBox.Top, iw), st(P.line)))
		for _, r := range card.Reasons {
			body = append(body, wrapText(r, iw, 3, st(P.human))...)
		}
		for _, h := range card.Hints {
			body = append(body, wrapText(h, iw, 3, st(P.muted))...)
		}
	}

	rows := boxRows(body, cw, iw, border, bg)
	// Terminé is the page's `.card.merged { opacity: .72 }`.
	if card.Column == "done" {
		for _, r := range rows {
			for i := range r {
				r[i] = fadeCell(r[i], P.bg, 0.72)
			}
		}
		dotOff = fadeCell(dotOff, P.bg, 0.72)
	}
	card.rows = rowsMemo{cw: cw, sel: selected, rows: rows, dotOff: dotOff}
	return &card.rows
}

// boxRows: body lines (iw wide) in a rounded box of exactly cw cells.
func boxRows(body [][]cell, cw, iw int, border, bg rgb) [][]cell {
	edge := fgbg(border, P.bg)
	rule := strings.Repeat(cardBox.Top, max(0, cw-2))
	rows := make([][]cell, 0, len(body)+2)
	rows = append(rows, padTo(cellsOf(cardBox.TopLeft+rule+cardBox.TopRight, edge), cw, P.bg))
	for _, line := range body {
		r := make([]cell, 0, cw)
		r = append(r, cell{ch: cardBox.Left, w: 1, st: edge}, cell{ch: " ", w: 1, st: bgOnly(bg)})
		r = append(r, padTo(line, iw, bg)...)
		r = append(r, cell{ch: " ", w: 1, st: bgOnly(bg)}, cell{ch: cardBox.Right, w: 1, st: edge})
		rows = append(rows, padTo(r, cw, P.bg))
	}
	return append(rows, padTo(cellsOf(cardBox.BottomLeft+rule+cardBox.BottomRight, edge), cw, P.bg))
}

// tabCells: ` Runs ` and ` Agents `, the shown one lit, each with what waits on you (À toi /
// Attend ta réponse); spans are each tab's [start, width] in the cells.
func (m *Model) tabCells() ([]cell, [2][2]int) {
	var out []cell
	var spans [2][2]int
	waits := [2]int{0, len(m.ag.board.cols[0])}
	if g := m.groups["human"]; g != nil {
		waits[tabRuns] = len(g.Cards)
	}
	for i, name := range []string{"Runs", "Agents"} {
		if i > 0 {
			out = append(out, cell{ch: " ", w: 1})
		}
		// The shown tab is lit and bracketed, so it reads without color too.
		st, l, r := fg(P.muted), " ", " "
		if m.tab == i {
			st, l, r = fgbg(P.text, P.cardHover).bold(), "[", "]"
		}
		start := cellsWidth(out)
		out = toCells(l+name+" ", st, out)
		if waits[i] > 0 {
			hs := st
			hs.fg = P.human
			out = toCells("● "+strconv.Itoa(waits[i])+" ", hs, out)
		}
		out[len(out)-1] = cell{ch: r, w: 1, st: st}
		spans[i] = [2]int{start, cellsWidth(out) - start}
	}
	return out, spans
}

func (m *Model) drawHeader(g grid, W, y int) {
	t := "APEX board"
	if m.repo != "" {
		t += " · " + m.repo
	}
	title := cellsOf(t, fg(P.text).bold())
	var status []cell
	st, what := m.status, "runs/"
	if m.tab == tabAgents {
		st, what = m.ag.status, "session-state/"
	}
	switch {
	case st == nil:
		status = cellsOf("lecture…", fg(P.muted))
	case st.ok:
		status = toCells(what+" · "+strconv.Itoa(st.count)+" · "+st.time, fg(P.muted), cellsOf("● ", fg(P.pass)))
	default:
		status = toCells(st.err, fg(P.human), cellsOf("● ", fg(P.human)))
	}
	tabs, spans := m.tabCells()
	tabsW := cellsWidth(tabs)
	room := W - 2*margin
	sw := min(cellsWidth(status), max(0, room-min(cellsWidth(title), 12)-3-tabsW-2))
	tw := room
	if sw > 0 {
		tw -= sw + 2
	}
	// Title, then the tabs; too narrow for both, the tabs alone: they say which view is shown.
	x := margin
	if titleRoom := tw - tabsW - 3; titleRoom >= 4 {
		x = g.put(margin, y, fitCells(title, titleRoom)) + 3
	}
	shown := fitCells(tabs, margin+tw-x)
	g.put(x, y, shown)
	for i, sp := range spans {
		if w := min(sp[1], cellsWidth(shown)-sp[0]); w > 0 {
			m.hits = append(m.hits, hit{x: x + sp[0], y: y, w: w, h: 1, kind: hitTab, col: i})
		}
	}
	if sw > 0 {
		sc := fitCells(status, sw)
		g.put(W-margin-cellsWidth(sc), y, sc)
	}
}

// render draws the whole screen into m.frame (exactly height lines of width columns) and keeps
// the hits and layout; the scrolls it settles on persist, as tui.js settle() did.
func (m *Model) render() {
	if m.tab == tabAgents {
		m.renderAgents()
		return
	}
	W, H := max(1, m.width), max(1, m.height)
	m.g.reset(W, H, P.bg)
	g := m.g
	m.hits = m.hits[:0]
	sel := m.selection()
	view := viewInfo{sel: sel}

	tall := H >= 16
	y := 0
	if tall {
		y = 1
	}
	m.drawHeader(g, W, y)
	y++
	banner := m.problems
	if len(banner) > 3 {
		banner = append(banner[:3:3], "+"+strconv.Itoa(len(m.problems)-3))
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

	n := len(Columns)
	inner := max(1, W-2*margin)
	nVis := clamp((inner+gap)/(minCol+gap), 1, n)
	// Equal columns; the columns left over go one each to the first ones.
	span := inner - gap*(nVis-1)
	base := max(1, span/nVis)
	extra := max(0, span-base*nVis)
	first := clamp(clamp(m.hscroll, sel.col-nVis+1, sel.col), 0, n-nVis)
	view.first, view.nVis = first, nVis
	m.hscroll = first

	for v := range nVis {
		c := first + v
		col := Columns[c]
		cw := base
		if v < extra {
			cw++
		}
		x := margin + v*(base+gap) + min(v, extra)
		grp := m.groups[col.Key]
		lay := colLayout{}
		items := make([]*rowsMemo, len(grp.Cards))
		top := 0
		for i, card := range grp.Cards {
			rows := cardRows(card, cw, c == sel.col && i == sel.idx)
			items[i] = rows
			lay.tops = append(lay.tops, top)
			lay.heights = append(lay.heights, len(rows.rows))
			lay.ids = append(lay.ids, card.ID)
			top += len(rows.rows)
		}
		total := top
		if grp.More > 0 || len(grp.Cards) == 0 {
			total++
		}
		lay.total = total
		view.cols[c] = lay
		s := m.scroll[c]
		if m.follow && c == sel.col && sel.idx >= 0 && sel.idx < len(items) {
			pt, ph := lay.tops[sel.idx], lay.heights[sel.idx]
			if pt+ph > s+areaH {
				s = pt + ph - areaH
			}
			if pt < s {
				s = pt
			}
		}
		s = clamp(s, 0, max(0, total-areaH))
		m.scroll[c] = s

		// Column head: label, who, count; the line under it; `›` between work columns.
		count := len(grp.Cards) + grp.More
		var countCells []cell
		if count > 0 {
			countCells = cellsOf(strconv.Itoa(count), fg(P.muted))
		}
		lc := P.text
		switch col.Key {
		case "human":
			lc = P.human
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
		if count > 0 {
			g.putMax(x+cw-cellsWidth(countCells), headY, countCells, x+cw)
		}
		ruleC := P.line
		if col.Key == "human" {
			ruleC = mix(P.human, P.bg, 0.55)
		}
		g.put(x, headY+1, cellsOf(strings.Repeat(cardBox.Top, cw), fg(ruleC)))
		if s > 0 && cw >= 2 {
			g.put(x+cw-2, headY+1, cellsOf("↑", fg(P.muted)))
		}
		if s+areaH < total {
			g.put(x+cw-1, headY+1, cellsOf("↓", fg(P.muted)))
		}
		if c < 4 && v < nVis-1 {
			g.put(x+cw+1, headY, cellsOf("›", fg(P.faint)))
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
				if r == 1 && !m.tick && grp.Cards[i].pulses() {
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
		tail := ""
		if len(grp.Cards) == 0 {
			tail = "—"
		} else if grp.More > 0 {
			tail = "+" + strconv.Itoa(grp.More)
		}
		if at := top - s; tail != "" && at >= 0 && at < areaH {
			g.putMax(x+1, cardsTop+at, cellsOf(tail, fg(P.faint)), x+cw)
		}
	}
	if first > 0 {
		g.put(0, headY, cellsOf("‹", fg(P.muted)))
	}
	if first+nVis < n {
		g.put(W-1, headY, cellsOf("›", fg(P.muted)))
	}

	if tall {
		g.put(margin, H-2, fitCells(cellsOf(footerText, fg(P.muted)), W-2*margin))
	}
	keys := cellsOf(keysBoard, fg(P.faint))
	var where []cell
	if nVis < n {
		where = cellsOf("colonnes "+strconv.Itoa(first+1)+"-"+strconv.Itoa(first+nVis)+"/"+strconv.Itoa(n), fg(P.faint))
	}
	kw := W - 2*margin
	if len(where) > 0 {
		kw -= cellsWidth(where) + 2
	}
	if kw > 8 {
		g.put(margin, H-1, fitCells(keys, kw))
		if len(where) > 0 {
			g.put(W-margin-cellsWidth(where), H-1, where)
		}
	} else {
		g.put(margin, H-1, fitCells(keys, W-2*margin))
	}

	if m.drawer != nil {
		m.drawDrawer(g, W, H, &view)
	}
	m.view = view
	m.frame = frameOf(g)
	m.dirty = false
}

// frameOf: the grid as the frame's ANSI lines.
func frameOf(g grid) string {
	var sb strings.Builder
	if len(g) > 0 {
		sb.Grow(len(g) * len(g[0]) * 4)
	}
	for y, row := range g {
		if y > 0 {
			sb.WriteByte('\n')
		}
		serialize(&sb, row)
	}
	return sb.String()
}

// ---- drawer ----------------------------------------------------------------

type fileItem struct {
	group string
	path  string
}

func fileItems(d *drawerState) []fileItem {
	var items []fileItem
	group, have := "", false
	for _, f := range d.files {
		name := "Run"
		if i := strings.LastIndexByte(f, '/'); i >= 0 {
			name = f[:i]
		}
		if !have || name != group {
			items = append(items, fileItem{group: name})
			group, have = name, true
		}
		items = append(items, fileItem{path: f})
	}
	return items
}

func note(text string, w int, f rgb) []mdLine {
	var out []mdLine
	for _, c := range wrapCells(cellsOf(text, fg(f)), w) {
		out = append(out, mdLine{cells: c})
	}
	return out
}

type docMemo struct {
	doc   *FileRead
	path  string
	w     int
	lines []mdLine
}

// docLines: markdown for .md, code style otherwise, a note while nothing is readable.
func (m *Model) docLines(d *drawerState, w int) []mdLine {
	doc := d.doc
	switch {
	case d.files == nil || doc == nil:
		return note("chargement…", w, P.faint)
	case doc.Kind == "empty":
		return note("Ce run n’a encore rien écrit.", w, P.faint)
	case doc.Kind == "outside":
		return append(note(outsideText, w, P.human), note(d.path+" pointe hors de .claude/output/apex : non lu.", w, P.faint)...)
	case doc.Kind == "missing":
		return note("Fichier disparu depuis la liste.", w, P.faint)
	case doc.Kind == "binary":
		return note("Fichier binaire : non affiché.", w, P.faint)
	case doc.Kind != "text":
		t := doc.Text
		if t == "" {
			t = "illisible"
		}
		return note(t, w, P.human)
	}
	if mm := m.docMemo; mm.doc == doc && mm.path == d.path && mm.w == w {
		return mm.lines
	}
	var lines []mdLine
	if strings.HasSuffix(d.path, ".md") {
		lines = mdLines(doc.Text, w)
	} else {
		lines = codeLines(strings.Split(strings.TrimSuffix(doc.Text, "\n"), "\n"), w)
	}
	m.docMemo = docMemo{doc: doc, path: d.path, w: w, lines: lines}
	return lines
}

func (m *Model) cardByID(id string) *Card {
	for _, c := range m.cards {
		if c.ID == id {
			return c
		}
	}
	return nil
}

func (m *Model) drawDrawer(g grid, W, H int, view *viewInfo) {
	d := m.drawer
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
	card := m.cardByID(d.id)

	// Head: id · column · step · actif, title, branch, À-toi reasons and hints, × to close.
	y := 0
	if H >= 16 {
		y = 1
	}
	closeX := right - 1
	g.put(closeX, y, cellsOf("×", fg(P.muted).bold()))
	m.hits = append(m.hits, hit{x: closeX - 1, y: max(0, y-1), w: 3, h: 3, kind: hitClose})
	headW := max(1, closeX-2-left)
	num := d.id
	if card != nil {
		parts := []string{card.ID, labelOf(card.Column)}
		if card.Current != nil && *card.Current != "" {
			parts = append(parts, *card.Current)
		}
		if card.Live {
			parts = append(parts, "actif")
		} else {
			parts = append(parts, "inactif")
		}
		num = strings.Join(parts, " · ")
	}
	g.put(left, y, fitCells(cellsOf(num, fg(P.muted)), headW))
	y++
	if card != nil {
		for _, l := range wrapText(card.Title, headW, 2, fg(P.text).bold()) {
			g.put(left, y, l)
			y++
		}
		if card.Branch != nil {
			g.put(left, y, fitCells(cellsOf(*card.Branch, fg(P.faint)), headW))
			y++
		}
		if card.Column == "human" {
			for _, r := range card.Reasons {
				for _, l := range wrapText(r, headW, 2, fg(P.human)) {
					g.put(left, y, l)
					y++
				}
			}
			for _, h := range card.Hints {
				for _, l := range wrapText(h, headW, 2, fg(P.muted)) {
					g.put(left, y, l)
					y++
				}
			}
		}
	}
	y++
	g.put(cx, y, cellsOf(strings.Repeat(cardBox.Top, max(0, W-cx)), fg(P.line)))
	bodyTop := y + 1
	keysY := H - 1
	bodyH := max(0, keysY-bodyTop)

	// Files: grouped Run / subdir, verdict dot, the selected one highlighted.
	fw := clamp(dw*3/10, min(12, dw), 26)
	fx := cx
	items := fileItems(d)
	selRow := -1
	if d.hasPath {
		for i, it := range items {
			if it.group == "" && it.path == d.path {
				selRow = i
				break
			}
		}
	}
	fsc := d.fileScroll
	if selRow >= 0 {
		if selRow >= fsc+bodyH {
			fsc = selRow - bodyH + 1
		}
		if selRow < fsc {
			fsc = selRow
		}
	}
	fsc = clamp(fsc, 0, max(0, len(items)-bodyH))
	view.fileScroll = fsc
	d.fileScroll = fsc
	for r := 0; r < bodyH && fsc+r < len(items); r++ {
		it := items[fsc+r]
		yy := bodyTop + r
		if it.path == "" {
			g.put(fx+1, yy, fitCells(cellsOf(strings.ToUpper(it.group), fg(P.faint)), fw-2))
			continue
		}
		on := d.hasPath && it.path == d.path
		st := func(f rgb) style { return fg(f) }
		if on {
			bg := P.card
			if d.focus == "files" {
				bg = P.cardHover
			}
			g.fillRow(yy, fx, fx+fw, bg)
			st = func(f rgb) style { return fgbg(f, bg) }
		}
		dot := P.faint
		if t, ok := tones[d.tones[it.path]]; ok {
			dot = t
		}
		g.put(fx+1, yy, cellsOf("●", st(dot)))
		name := it.path[strings.LastIndexByte(it.path, '/')+1:]
		nc := P.muted
		if on {
			nc = P.text
		}
		g.putMax(fx+3, yy, fitCells(cellsOf(name, st(nc)), fw-4), fx+fw)
		m.hits = append(m.hits, hit{x: fx, y: yy, w: fw, h: 1, kind: hitFile, path: it.path})
	}
	if d.files != nil && len(d.files) == 0 && bodyH > 0 {
		g.put(fx+1, bodyTop, fitCells(cellsOf("Aucun fichier.", fg(P.faint)), fw-2))
	}
	for r := range bodyH {
		g.put(fx+fw, bodyTop+r, cellsOf(cardBox.Left, fg(P.line)))
	}

	// Document.
	dx := fx + fw + 1 + pad
	docW := right - dx
	var tail []cell
	if docW >= 1 && bodyH > 0 {
		lines := m.docLines(d, docW)
		ds := clamp(d.docScroll, 0, max(0, len(lines)-bodyH))
		view.docLines, view.bodyH, view.docScroll = len(lines), bodyH, ds
		for r := 0; r < bodyH && ds+r < len(lines); r++ {
			l := lines[ds+r]
			if l.hasFill {
				g.fillRow(bodyTop+r, dx, right, l.fill)
			}
			g.putMax(dx, bodyTop+r, l.cells, right)
		}
		m.hits = append(m.hits, hit{x: fx + fw + 1, y: bodyTop, w: W - (fx + fw + 1), h: bodyH, kind: hitDoc})
		if len(lines) > bodyH {
			tail = cellsOf(strconv.Itoa(ds+1)+"-"+strconv.Itoa(min(ds+bodyH, len(lines)))+"/"+strconv.Itoa(len(lines)), fg(P.faint))
		}
	}
	k := "↑↓ fichier · ⇥ document"
	if d.focus == "doc" {
		k = "↑↓ défiler · ⇥ fichiers"
	}
	keys := cellsOf(k+" · pgup/pgdn page · esc fermer", fg(P.faint))
	kw := right - left
	if len(tail) > 0 {
		kw -= cellsWidth(tail) + 2
	}
	g.put(left, keysY, fitCells(keys, kw))
	if len(tail) > 0 && kw > 0 {
		g.put(right-cellsWidth(tail), keysY, tail)
	}
}
