package main

// Cells, one per terminal column, and the grid the board is drawn on (port of tui.js's cell
// layer). Drawing on a grid of exact widths, rather than composing styled strings, keeps every
// line exactly `width` columns and lets the drawer fade what is under it.

import (
	"strconv"
	"strings"
	"unicode/utf8"

	"charm.land/lipgloss/v2"
)

type rgb struct{ r, g, b uint8 }

// hexColor goes through Lip Gloss so the palette is the one its parser reads.
func hexColor(h string) rgb {
	r, g, b, _ := lipgloss.Color(h).RGBA()
	return rgb{uint8(r >> 8), uint8(g >> 8), uint8(b >> 8)}
}

// Palette: index.html :root.
var P = struct {
	bg, panel, card, cardHover, line, text, muted, faint, active, pass, changes, human, merged, err rgb
}{
	bg:        hexColor("#14151b"),
	panel:     hexColor("#1a1c24"),
	card:      hexColor("#20222c"),
	cardHover: hexColor("#252835"),
	line:      hexColor("#2b2e3b"),
	text:      hexColor("#e4e5ea"),
	muted:     hexColor("#868ba0"),
	faint:     hexColor("#5b6075"),
	active:    hexColor("#8be9fd"),
	pass:      hexColor("#50fa7b"),
	changes:   hexColor("#ffb86c"),
	human:     hexColor("#ff79c6"),
	merged:    hexColor("#bd93f9"),
	err:       hexColor("#ff5555"), // failures and refusals; human stays the decision pink
}

// scrim is the page's rgba(5, 6, 10, .55).
var scrim = rgb{5, 6, 10}

// mix is color-mix(in srgb, a t, b).
func mix(a, b rgb, t float64) rgb {
	m := func(x, y uint8) uint8 { return uint8(jsRound(float64(x)*t + float64(y)*(1-t))) }
	return rgb{m(a.r, b.r), m(a.g, b.g), m(a.b, b.b)}
}

func jsRound(x float64) float64 {
	f := float64(int64(x))
	if x-f >= 0.5 {
		return f + 1
	}
	return f
}

var tones = map[string]rgb{"good": P.pass, "warn": P.changes, "stop": P.err}

// toneGlyphs: a file verdict readable without colour; "·" when the file has none.
var toneGlyphs = map[string]string{"good": "✓", "warn": "~", "stop": "✗"}

// style: fg / bg unset take the color under them when drawn.
type style struct {
	fg, bg       rgb
	hasFg, hasBg bool
	b, i, u      bool
}

func fg(c rgb) style        { return style{fg: c, hasFg: true} }
func fgbg(f, b rgb) style   { return style{fg: f, bg: b, hasFg: true, hasBg: true} }
func bgOnly(b rgb) style    { return style{bg: b, hasBg: true} }
func (s style) bold() style { s.b = true; return s }
func (s style) withBg(b rgb) style {
	s.bg, s.hasBg = b, true
	return s
}

// cell: w 2 for a wide char, whose right half is a w 0 cell.
type cell struct {
	ch string
	w  int8
	st style
}

const (
	wCtl  = -1
	wDrop = -2
)

type span struct{ lo, hi rune }

var wideRanges = []span{
	{0x1100, 0x115f}, {0x231a, 0x231b}, {0x2329, 0x232a}, {0x23e9, 0x23ec}, {0x23f0, 0x23f0}, {0x23f3, 0x23f3},
	{0x25fd, 0x25fe}, {0x2614, 0x2615}, {0x2648, 0x2653}, {0x267f, 0x267f}, {0x2693, 0x2693}, {0x26a1, 0x26a1},
	{0x26aa, 0x26ab}, {0x26bd, 0x26be}, {0x26c4, 0x26c5}, {0x26ce, 0x26ce}, {0x26d4, 0x26d4}, {0x26ea, 0x26ea},
	{0x26f2, 0x26f3}, {0x26f5, 0x26f5}, {0x26fa, 0x26fa}, {0x26fd, 0x26fd}, {0x2705, 0x2705}, {0x270a, 0x270b},
	{0x2728, 0x2728}, {0x274c, 0x274c}, {0x274e, 0x274e}, {0x2753, 0x2755}, {0x2757, 0x2757}, {0x2795, 0x2797},
	{0x27b0, 0x27b0}, {0x27bf, 0x27bf}, {0x2b1b, 0x2b1c}, {0x2b50, 0x2b50}, {0x2b55, 0x2b55}, {0x2e80, 0x303e},
	{0x3041, 0x33ff}, {0x3400, 0x4dbf}, {0x4e00, 0x9fff}, {0xa000, 0xa4cf}, {0xac00, 0xd7a3}, {0xf900, 0xfaff},
	{0xfe30, 0xfe4f}, {0xff00, 0xff60}, {0xffe0, 0xffe6}, {0x1f004, 0x1f004}, {0x1f0cf, 0x1f0cf}, {0x1f18e, 0x1f18e},
	{0x1f191, 0x1f19a}, {0x1f200, 0x1f251}, {0x1f300, 0x1f3fa}, {0x1f400, 0x1f64f}, {0x1f680, 0x1f6ff},
	{0x1f7e0, 0x1f7eb}, {0x1f900, 0x1f9ff}, {0x1fa70, 0x1faff}, {0x20000, 0x3fffd},
}

var combiningRanges = []span{{0x300, 0x36f}, {0x483, 0x489}, {0x591, 0x5bd}, {0x610, 0x61a}, {0x64b, 0x65f}, {0x1ab0, 0x1aff}, {0x1dc0, 0x1dff}, {0x20d0, 0x20ff}, {0xfe20, 0xfe2f}}

// Invisible or presentation-switching: dropped so the counted width is the drawn width.
var droppedRanges = []span{{0xad, 0xad}, {0x200b, 0x200f}, {0x2028, 0x202e}, {0x2060, 0x206f}, {0xfe00, 0xfe0f}, {0xfeff, 0xfeff}, {0x1f3fb, 0x1f3ff}, {0xe0000, 0xe007f}}

func inRanges(cp rune, rs []span) bool {
	for _, r := range rs {
		if cp >= r.lo && cp <= r.hi {
			return true
		}
	}
	return false
}

// cpWidth: 1 or 2, 0 for a combining mark, wCtl for a control, wDrop for an invisible.
func cpWidth(cp rune) int {
	if cp < 0x20 || (cp >= 0x7f && cp < 0xa0) {
		return wCtl
	}
	if cp < 0x300 {
		if cp == 0xad {
			return wDrop
		}
		return 1
	}
	if inRanges(cp, droppedRanges) {
		return wDrop
	}
	if inRanges(cp, combiningRanges) {
		return 0
	}
	if inRanges(cp, wideRanges) {
		return 2
	}
	return 1
}

// toCells appends str as cells. A control char (ESC included) becomes `?`: file text never
// drives the terminal. Bytes that are not UTF-8 are drawn U+FFFD.
func toCells(str string, st style, out []cell) []cell {
	for i := 0; i < len(str); {
		c := str[i]
		if c >= 0x20 && c < 0x7f {
			out = append(out, cell{ch: str[i : i+1], w: 1, st: st})
			i++
			continue
		}
		r, n := utf8.DecodeRuneInString(str[i:])
		ch := str[i : i+n]
		i += n
		if r == utf8.RuneError && n == 1 {
			out = append(out, cell{ch: "�", w: 1, st: st})
			continue
		}
		if r == '\t' {
			out = append(out, cell{ch: " ", w: 1, st: st})
			continue
		}
		switch w := cpWidth(r); w {
		case wCtl:
			out = append(out, cell{ch: "?", w: 1, st: st})
		case wDrop:
		case 0:
			if len(out) > 0 {
				out[len(out)-1].ch += ch
			}
		default:
			out = append(out, cell{ch: ch, w: int8(w), st: st})
		}
	}
	return out
}

func cellsOf(str string, st style) []cell { return toCells(str, st, nil) }

func cellsWidth(cells []cell) int {
	n := 0
	for _, c := range cells {
		n += int(c.w)
	}
	return n
}

func spaces(n int, st style) []cell {
	if n <= 0 {
		return nil
	}
	out := make([]cell, n)
	for i := range out {
		out[i] = cell{ch: " ", w: 1, st: st}
	}
	return out
}

// clipCells: the first w columns; a wide char cut in half becomes a space.
func clipCells(cells []cell, w int) []cell {
	n := 0
	for i, c := range cells {
		if n+int(c.w) > w {
			out := cells[:i:i]
			if n < w {
				c.ch, c.w = " ", 1
				out = append(out, c)
			}
			return out
		}
		n += int(c.w)
	}
	return cells
}

// padTo: clipped then padded to exactly w columns with spaces on bg.
func padTo(cells []cell, w int, bg rgb) []cell {
	c := clipCells(cells, w)
	rest := w - cellsWidth(c)
	if rest <= 0 {
		return c
	}
	out := make([]cell, len(c), len(c)+rest)
	copy(out, c)
	return append(out, spaces(rest, bgOnly(bg))...)
}

// fitCells: within w columns, an ellipsis replacing what does not fit.
func fitCells(cells []cell, w int) []cell {
	if w <= 0 {
		return nil
	}
	if cellsWidth(cells) <= w {
		return cells
	}
	kept := clipCells(cells, w-1)
	st := style{}
	if len(cells) > 0 {
		st = cells[min(len(kept), len(cells)-1)].st
	}
	out := make([]cell, len(kept), len(kept)+1)
	copy(out, kept)
	return append(out, cell{ch: "…", w: 1, st: st})
}

// wrapCells: word-wrap to w columns; a word longer than a line is cut. At least one line.
func wrapCells(cells []cell, width int) [][]cell {
	w := max(1, width)
	var lines [][]cell
	var line []cell
	lineW := 0
	flush := func() {
		for len(line) > 0 && line[len(line)-1].ch == " " {
			line = line[:len(line)-1]
			lineW--
		}
		lines = append(lines, line)
		line, lineW = nil, 0
	}
	i := 0
	for i < len(cells) {
		if cells[i].ch == " " {
			if lineW > 0 && lineW+1 <= w {
				line = append(line, cells[i])
				lineW++
			}
			i++
			continue
		}
		j, ww := i, 0
		for j < len(cells) && cells[j].ch != " " {
			ww += int(cells[j].w)
			j++
		}
		if lineW > 0 && lineW+ww > w {
			flush()
		}
		for k := i; k < j; k++ {
			if lineW+int(cells[k].w) > w {
				flush()
			}
			line = append(line, cells[k])
			lineW += int(cells[k].w)
		}
		i = j
	}
	if len(line) > 0 || len(lines) == 0 {
		flush()
	}
	return lines
}

// hardWrap: cut every w columns, no word logic (code).
func hardWrap(cells []cell, width int) [][]cell {
	w := max(1, width)
	var out [][]cell
	var line []cell
	n := 0
	for _, c := range cells {
		if n+int(c.w) > w {
			out = append(out, line)
			line, n = nil, 0
		}
		line = append(line, c)
		n += int(c.w)
	}
	return append(out, line)
}

// wrapText: wrapped to w, at most max lines, the last one ending in `…` when text was cut.
func wrapText(str string, w, maxLines int, st style) [][]cell {
	lines := wrapCells(cellsOf(str, st), w)
	if len(lines) <= maxLines {
		return lines
	}
	kept := lines[:maxLines]
	last := clipCells(kept[maxLines-1], max(0, w-1))
	kept[maxLines-1] = append(last[:len(last):len(last)], cell{ch: "…", w: 1, st: st})
	return kept
}

// ---- ANSI ------------------------------------------------------------------

func writeSGR(sb *strings.Builder, st style) {
	var buf [64]byte
	b := append(buf[:0], "\x1b[0"...)
	if st.hasFg {
		b = append(b, ";38;2;"...)
		b = strconv.AppendUint(b, uint64(st.fg.r), 10)
		b = append(b, ';')
		b = strconv.AppendUint(b, uint64(st.fg.g), 10)
		b = append(b, ';')
		b = strconv.AppendUint(b, uint64(st.fg.b), 10)
	}
	if st.hasBg {
		b = append(b, ";48;2;"...)
		b = strconv.AppendUint(b, uint64(st.bg.r), 10)
		b = append(b, ';')
		b = strconv.AppendUint(b, uint64(st.bg.g), 10)
		b = append(b, ';')
		b = strconv.AppendUint(b, uint64(st.bg.b), 10)
	}
	if st.b {
		b = append(b, ";1"...)
	}
	if st.i {
		b = append(b, ";3"...)
	}
	if st.u {
		b = append(b, ";4"...)
	}
	b = append(b, 'm')
	sb.Write(b)
}

// serialize writes one line of cells as ANSI, attributes reset at its end.
func serialize(sb *strings.Builder, cells []cell) {
	var last style
	have := false
	for _, c := range cells {
		if c.w == 0 {
			continue
		}
		if !have || c.st != last {
			writeSGR(sb, c.st)
			last, have = c.st, true
		}
		sb.WriteString(c.ch)
	}
	sb.WriteString("\x1b[0m")
}

func serializeLine(cells []cell) string {
	var sb strings.Builder
	serialize(&sb, cells)
	return sb.String()
}

// stripAnsi: s without its escape sequences (CSI, OSC, two-byte).
func stripAnsi(s string) string {
	var sb strings.Builder
	i := 0
	for i < len(s) {
		if s[i] != 27 {
			sb.WriteByte(s[i])
			i++
			continue
		}
		if i+1 < len(s) && s[i+1] == '[' {
			i += 2
			for i < len(s) && (s[i] < 0x40 || s[i] > 0x7e) {
				i++
			}
			i++
		} else if i+1 < len(s) && s[i+1] == ']' {
			i += 2
			for i < len(s) && s[i] != 7 && (s[i] != 27 || i+1 >= len(s) || s[i+1] != '\\') {
				i++
			}
			if i < len(s) && s[i] == 7 {
				i++
			} else {
				i += 2
			}
		} else {
			i += 2
		}
	}
	return sb.String()
}

// visibleWidth: columns an ANSI string takes on screen.
func visibleWidth(s string) int { return cellsWidth(cellsOf(stripAnsi(s), style{})) }

// ---- grid ------------------------------------------------------------------

func blank(bg rgb) cell { return cell{ch: " ", w: 1, st: fgbg(P.text, bg)} }

type grid [][]cell

func (g *grid) reset(w, h int, bg rgb) {
	if len(*g) != h || (h > 0 && len((*g)[0]) != w) {
		rows := make([][]cell, h)
		flat := make([]cell, w*h)
		for y := range rows {
			rows[y] = flat[y*w : (y+1)*w : (y+1)*w]
		}
		*g = rows
	}
	b := blank(bg)
	for _, row := range *g {
		for x := range row {
			row[x] = b
		}
	}
}

// setCell keeps wide chars whole: an overwritten half blanks the other half.
func setCell(row []cell, x int, c cell) {
	if x < 0 || x >= len(row) {
		return
	}
	old := row[x]
	if old.w == 0 && x > 0 {
		row[x-1].ch, row[x-1].w = " ", 1
	}
	if old.w == 2 && x+1 < len(row) {
		row[x+1].ch, row[x+1].w = " ", 1
	}
	if c.w != 2 {
		row[x] = c
		return
	}
	if x+1 >= len(row) {
		c.ch, c.w = " ", 1
		row[x] = c
		return
	}
	if row[x+1].w == 2 && x+2 < len(row) {
		row[x+2].ch, row[x+2].w = " ", 1
	}
	row[x] = c
	half := c
	half.ch, half.w = "", 0
	row[x+1] = half
}

// putCells draws from x, stopping before maxX; a cell without fg / bg takes text / the bg under it.
func putCells(row []cell, x int, cells []cell, maxX int) int {
	for _, c := range cells {
		if x >= maxX {
			break
		}
		if x < 0 {
			x += int(c.w)
			continue
		}
		if !c.st.hasFg {
			c.st.fg, c.st.hasFg = P.text, true
		}
		if !c.st.hasBg {
			c.st.bg, c.st.hasBg = row[x].st.bg, true
		}
		if x+int(c.w) > maxX {
			c.ch, c.w = " ", 1
			setCell(row, x, c)
			return maxX
		}
		setCell(row, x, c)
		x += int(c.w)
	}
	return x
}

func (g grid) put(x, y int, cells []cell) int { return g.putMax(x, y, cells, -1) }

func (g grid) putMax(x, y int, cells []cell, maxX int) int {
	if y < 0 || y >= len(g) {
		return x
	}
	row := g[y]
	if maxX < 0 || maxX > len(row) {
		maxX = len(row)
	}
	return putCells(row, x, cells, maxX)
}

func (g grid) fillRow(y, x0, x1 int, bg rgb) {
	if y < 0 || y >= len(g) {
		return
	}
	for x := max(0, x0); x < min(x1, len(g[y])); x++ {
		setCell(g[y], x, blank(bg))
	}
}

// fadeCell: a cell seen through a layer, opacity t over toward.
func fadeCell(c cell, toward rgb, t float64) cell {
	f, b := P.text, P.bg
	if c.st.hasFg {
		f = c.st.fg
	}
	if c.st.hasBg {
		b = c.st.bg
	}
	c.st.fg, c.st.bg, c.st.hasFg, c.st.hasBg = mix(f, toward, t), mix(b, toward, t), true, true
	return c
}
