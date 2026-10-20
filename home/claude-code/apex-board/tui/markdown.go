package main

// Markdown as cell lines (port of tui.js mdLines, itself a port of index.html markdown()):
// verdict badge, headings, code, quotes, box-drawn tables, lists and tasks, inline styles.

import (
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"

	"charm.land/lipgloss/v2"
)

// mdLine: fill is a bg the whole line takes (code).
type mdLine struct {
	cells   []cell
	fill    rgb
	hasFill bool
}

var (
	reLinkURL = regexp.MustCompile(`^(?:https?://|\.{0,2}/|#)[^)` + jsSpaceClass + `]*\)`)
	tableBox  = lipgloss.NormalBorder()
)

// inlineAt is INLINE (`code`, **bold**, *em* not after `*`, [link](url)) tried at pos: which
// alternative, its group bounds and the match end; kind 0 when none matches there.
func inlineAt(s string, pos int) (kind, g0, g1, end int) {
	switch s[pos] {
	case '`':
		if j := strings.IndexByte(s[pos+1:], '`'); j > 0 {
			return 1, pos + 1, pos + 1 + j, pos + 2 + j
		}
	case '*':
		if pos+1 < len(s) && s[pos+1] == '*' {
			if j := strings.IndexByte(s[pos+2:], '*'); j > 0 && pos+2+j+1 < len(s) && s[pos+2+j+1] == '*' {
				return 2, pos + 2, pos + 2 + j, pos + 2 + j + 2
			}
		}
		if pos > 0 && s[pos-1] == '*' {
			return 0, 0, 0, 0
		}
		if pos+1 < len(s) && s[pos+1] != '*' {
			if r, _ := utf8.DecodeRuneInString(s[pos+1:]); !isJSSpace(r) {
				if j := strings.IndexByte(s[pos+1:], '*'); j > 0 {
					return 3, pos + 1, pos + 1 + j, pos + 2 + j
				}
			}
		}
	case '[':
		j := strings.IndexByte(s[pos+1:], ']')
		if j <= 0 {
			return 0, 0, 0, 0
		}
		close := pos + 1 + j
		if close+1 < len(s) && s[close+1] == '(' {
			if loc := reLinkURL.FindStringIndex(s[close+2:]); loc != nil {
				return 4, pos + 1, close, close + 2 + loc[1]
			}
		}
	}
	return 0, 0, 0, 0
}

// inlineCells: **bold**, *em*, `code`, [link](url) as styled cells.
func inlineCells(s string, base style, out []cell) []cell {
	last, pos := 0, 0
	for pos < len(s) {
		k := strings.IndexAny(s[pos:], "`*[")
		if k < 0 {
			break
		}
		pos += k
		kind, g0, g1, end := inlineAt(s, pos)
		if kind == 0 {
			pos++
			continue
		}
		out = toCells(s[last:pos], base, out)
		inner := s[g0:g1]
		switch kind {
		case 1:
			out = toCells(inner, base.withBg(P.card), out)
		case 2:
			b := base
			b.b = true
			out = inlineCells(inner, b, out)
		case 3:
			b := base
			b.i = true
			out = inlineCells(inner, b, out)
		default:
			b := base
			b.fg, b.hasFg, b.u = P.active, true, true
			out = inlineCells(inner, b, out)
		}
		last, pos = end, end
	}
	return toCells(s[last:], base, out)
}

// expandTabs: tab stops every 4 UTF-16 units, as tui.js counted them.
func expandTabs(s string) string {
	if !strings.Contains(s, "\t") {
		return s
	}
	var sb strings.Builder
	n := 0
	for _, r := range s {
		if r == '\t' {
			k := 4 - n%4
			sb.WriteString(strings.Repeat(" ", k))
			n += k
			continue
		}
		sb.WriteRune(r)
		if r >= 0x10000 {
			n += 2
		} else {
			n++
		}
	}
	return sb.String()
}

// codeLines: a <pre>, one padding line above and below, lines cut at the width.
func codeLines(lines []string, w int) []mdLine {
	st := fgbg(P.text, P.bg)
	out := []mdLine{{fill: P.bg, hasFill: true}}
	for _, raw := range lines {
		for _, chunk := range hardWrap(cellsOf(expandTabs(raw), st), max(1, w-2)) {
			out = append(out, mdLine{cells: append([]cell{{ch: " ", w: 1, st: st}}, chunk...), fill: P.bg, hasFill: true})
		}
	}
	return append(out, mdLine{fill: P.bg, hasFill: true})
}

var (
	reTableSep  = regexp.MustCompile(`^\|[` + jsSpaceClass + `:|-]+\|$`)
	reRowEdges  = regexp.MustCompile(`^\||\|$`)
	reList      = regexp.MustCompile(`^` + reS + `*([-*+]|\d+\.)` + reS + `+`)
	reBlockHead = regexp.MustCompile("^(#{1,6}" + reS + "|```|" + reS + `*>|\|)`)
	reMdHeading = regexp.MustCompile(`^(#{1,6})` + reS + `+(` + reDot + `*)$`)
	reQuote     = regexp.MustCompile(`^` + reS + `*>`)
	reQuoteLead = regexp.MustCompile(`^` + reS + `*>` + reS + `?`)
	reOrdered   = regexp.MustCompile(`^` + reS + `*\d+\.`)
	reContinued = regexp.MustCompile(`^` + reS + `{2,}` + reNS)
	reIndent    = regexp.MustCompile(`^` + reS + `*`)
	reTask      = regexp.MustCompile(`^\[([ xX])\]` + reS + `+(` + reDot + `*)$`)
)

func rule(l, m, r string, w []int, ln style) []cell {
	var sb strings.Builder
	sb.WriteString(l)
	for j, x := range w {
		if j > 0 {
			sb.WriteString(m)
		}
		sb.WriteString(strings.Repeat(tableBox.Top, x+2))
	}
	sb.WriteString(r)
	return cellsOf(sb.String(), ln)
}

func tableLines(rows []string, W int) [][]cell {
	base := fg(P.text)
	ln := fg(P.line)
	var body []string
	for _, r := range rows {
		if !reTableSep.MatchString(r) {
			body = append(body, r)
		}
	}
	if len(body) == 0 {
		return nil
	}
	grid := make([][][]cell, len(body))
	n := 0
	for i, r := range body {
		st := base
		if i == 0 {
			st = base.bold()
		}
		for _, c := range strings.Split(reRowEdges.ReplaceAllString(r, ""), "|") {
			grid[i] = append(grid[i], inlineCells(jsTrim(c), st, nil))
		}
		n = max(n, len(grid[i]))
	}
	for i := range grid {
		for len(grid[i]) < n {
			grid[i] = append(grid[i], nil)
		}
	}
	avail := W - (3*n + 1)
	if avail < n {
		// Too narrow for a grid: one wrapped line per row, cells joined by the rule.
		var out [][]cell
		for _, r := range grid {
			var joined []cell
			for j, c := range r {
				if j > 0 {
					joined = toCells(" "+tableBox.Left+" ", ln, joined)
				}
				joined = append(joined, c...)
			}
			out = append(out, wrapCells(joined, W)...)
		}
		return out
	}
	w := make([]int, n)
	total := 0
	for j := range n {
		w[j] = 1
		for _, r := range grid {
			w[j] = max(w[j], cellsWidth(r[j]))
		}
		total += w[j]
	}
	for total > avail {
		j := 0
		for k := 1; k < n; k++ {
			if w[k] > w[j] {
				j = k
			}
		}
		w[j]--
		total--
	}
	b := tableBox
	out := [][]cell{rule(b.TopLeft, b.MiddleTop, b.TopRight, w, ln)}
	for ri, r := range grid {
		wrapped := make([][][]cell, n)
		h := 0
		for j, c := range r {
			wrapped[j] = wrapCells(c, w[j])
			h = max(h, len(wrapped[j]))
		}
		for k := range h {
			line := cellsOf(b.Left, ln)
			for j, x := range wrapped {
				var part []cell
				if k < len(x) {
					part = x[k]
				}
				line = append(line, cell{ch: " ", w: 1, st: base})
				part = clipCells(part, w[j])
				line = append(line, part...)
				line = append(line, spaces(w[j]-cellsWidth(part), style{})...)
				line = append(line, cell{ch: " ", w: 1, st: base})
				line = toCells(b.Left, ln, line)
			}
			out = append(out, line)
		}
		if ri == 0 && len(grid) > 1 {
			out = append(out, rule(b.MiddleLeft, b.Middle, b.MiddleRight, w, ln))
		}
	}
	return append(out, rule(b.BottomLeft, b.MiddleBottom, b.BottomRight, w, ln))
}

type listItem struct {
	indent int
	text   string
}

// mdLines: markdown as lines, none wider than width.
func mdLines(src string, width int) []mdLine {
	W := max(1, width)
	base := fg(P.text)
	lines := strings.Split(strings.ReplaceAll(src, "\r", ""), "\n")
	var out []mdLine
	afterHeading := false
	push := func(cells []cell) { out = append(out, mdLine{cells: cells}) }
	gap := func() {
		if len(out) > 0 && !afterHeading && len(out[len(out)-1].cells) > 0 {
			push(nil)
		}
		afterHeading = false
	}
	i := 0
	first := jsTrim(lines[0])
	if tone := lineTone(first); tone != "" {
		c := tones[tone]
		push(fitCells(cellsOf(" "+first+" ", fgbg(c, mix(c, P.panel, 0.15)).bold()), W))
		i = 1
	}
	isList := reList.MatchString
	isBlockStart := func(l string) bool { return reBlockHead.MatchString(l) || isList(l) }

	for i < len(lines) {
		line := lines[i]
		if jsTrim(line) == "" {
			i++
			continue
		}
		if strings.HasPrefix(line, "```") {
			var body []string
			i++
			for i < len(lines) && !strings.HasPrefix(lines[i], "```") {
				body = append(body, lines[i])
				i++
			}
			i++
			gap()
			out = append(out, codeLines(body, W)...)
			continue
		}
		if h := reMdHeading.FindStringSubmatch(line); h != nil {
			n := min(len(h[1]), 4)
			gap()
			c := P.text
			if n == 3 {
				c = P.muted
			}
			for _, l := range wrapCells(inlineCells(h[2], fg(c).bold(), nil), W) {
				push(l)
			}
			afterHeading = true
			i++
			continue
		}
		if reQuote.MatchString(line) {
			var body []string
			for i < len(lines) && reQuote.MatchString(lines[i]) {
				body = append(body, reQuoteLead.ReplaceAllString(lines[i], ""))
				i++
			}
			gap()
			for _, l := range wrapCells(inlineCells(strings.Join(body, " "), fg(P.muted), nil), W-2) {
				push(append(cellsOf("│ ", fg(P.line)), l...))
			}
			continue
		}
		if strings.HasPrefix(line, "|") {
			var rows []string
			for i < len(lines) && strings.HasPrefix(lines[i], "|") {
				rows = append(rows, lines[i])
				i++
			}
			gap()
			for _, l := range tableLines(rows, W) {
				push(l)
			}
			continue
		}
		if isList(line) {
			ordered := reOrdered.MatchString(line)
			var items []listItem
			for i < len(lines) && (isList(lines[i]) || (reContinued.MatchString(lines[i]) && len(items) > 0)) {
				l := lines[i]
				i++
				if isList(l) {
					items = append(items, listItem{indent: utf16Len(reIndent.FindString(l)), text: l[len(reList.FindString(l)):]})
				} else {
					items[len(items)-1].text += " " + jsTrim(l)
				}
			}
			gap()
			for n, it := range items {
				task := reTask.FindStringSubmatch(it.text)
				head := cellsOf(strings.Repeat(" ", min(it.indent/2, W/3)), base)
				switch {
				case task != nil && task[1] == " ":
					head = toCells("☐ ", fg(P.faint), head)
				case task != nil:
					head = toCells("☑ ", fg(P.pass), head)
				case ordered:
					head = toCells(strconv.Itoa(n+1)+". ", fg(P.muted), head)
				default:
					head = toCells("• ", fg(P.muted), head)
				}
				text := it.text
				if task != nil {
					text = task[2]
				}
				hw := cellsWidth(head)
				for k, l := range wrapCells(inlineCells(text, base, nil), W-hw) {
					if k == 0 {
						push(append(head[:len(head):len(head)], l...))
					} else {
						push(append(spaces(hw, style{}), l...))
					}
				}
			}
			continue
		}
		var para []string
		for i < len(lines) && jsTrim(lines[i]) != "" && !isBlockStart(lines[i]) {
			para = append(para, lines[i])
			i++
		}
		// A line no block takes (a heading the `$` of its regex refuses) still moves on.
		if len(para) == 0 {
			para = append(para, lines[i])
			i++
		}
		gap()
		for _, l := range wrapCells(inlineCells(strings.Join(para, " "), base, nil), W) {
			push(l)
		}
	}
	for len(out) > 0 && len(out[len(out)-1].cells) == 0 && !out[len(out)-1].hasFill {
		out = out[:len(out)-1]
	}
	for k := range out {
		out[k].cells = clipCells(out[k].cells, W)
	}
	return out
}

// renderMarkdown: markdown as ANSI lines, none wider than width.
func renderMarkdown(text string, width int) []string {
	w := max(1, width)
	lines := mdLines(text, w)
	out := make([]string, len(lines))
	for i, l := range lines {
		if l.hasFill {
			out[i] = serializeLine(padTo(l.cells, w, l.fill))
		} else {
			out[i] = serializeLine(l.cells)
		}
	}
	return out
}
