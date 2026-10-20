package main

// Port of board.js; the parity check in checks/apex-board.nix keeps them equal (parity.js runs
// board.js on the same runs dir and its JSON must match `--derive-json` byte for byte).
// Regexes keep board.js's meaning under RE2: JS `\s` / `.` spelled out (jsutil.go), `/i` as
// explicit letter classes (RE2 case folding also matches ſ and the Kelvin sign), lookaheads as
// code. Comments name the board.js function each piece comes from.

import (
	"encoding/json"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"
)

// StaleMs: a run is live only while its 00-context.md moved in the last 6 hours.
const StaleMs = 6 * 60 * 60 * 1000

// MaxRounds: correction rounds a run gets before the user must grant more.
const MaxRounds = 2

// DoneCap: cards the Terminé column shows before `+N`.
const DoneCap = 30

// Column is one of the 6 board columns, in board order.
type Column struct{ Key, Label, Who, Cls string }

// Columns is board.js COLUMNS.
var Columns = []Column{
	{Key: "init", Label: "Init", Who: "coordinateur"},
	{Key: "plan", Label: "Plan", Who: "01-analyze · 02-plan"},
	{Key: "execute", Label: "Execute", Who: "implémenteur"},
	{Key: "validate", Label: "Validate", Who: "04 → 08"},
	{Key: "done", Label: "Terminé", Who: "09 · PR · inactif", Cls: "merged-col"},
	{Key: "human", Label: "À toi", Who: "décision", Cls: "human"},
}

const (
	hintGrant   = "apex: +1 tour"
	hintSession = "répondre dans la session · /deck"
	hintExt     = "relire external-verify.json · corriger dans la session"
)

// ---- 00-context.md ------------------------------------------------------

func clean(value string) string {
	return jsTrim(strings.ReplaceAll(strings.ReplaceAll(value, "**", ""), "`", ""))
}

// wordPrefix is /^(a|b)(?![a-z])/: a prefix not followed by an ASCII lowercase letter.
func wordPrefix(s string, words ...string) bool {
	for _, w := range words {
		if strings.HasPrefix(s, w) && (len(s) == len(w) || s[len(w)] < 'a' || s[len(w)] > 'z') {
			return true
		}
	}
	return false
}

func hasPrefix(s string, words ...string) bool {
	for _, w := range words {
		if strings.HasPrefix(s, w) {
			return true
		}
	}
	return false
}

func statusKind(status string) string {
	s := jsLower(clean(status))
	if hasPrefix(s, "complete", "done", "✅") {
		return "done"
	}
	if hasPrefix(s, "pending") {
		return "pending"
	}
	if hasPrefix(s, "in progress", "in_progress", "en cours", "running") {
		return "running"
	}
	if hasPrefix(s, "skipped", "supprimé", "n/a") {
		return "skipped"
	}
	if wordPrefix(s, "red", "failed", "échoué") {
		return "failed"
	}
	if wordPrefix(s, "blocked", "bloqué") {
		return "blocked"
	}
	return "other"
}

// ci spells an ASCII word case-insensitively the way JS /i does for it.
func ci(word string) string {
	var sb strings.Builder
	for _, r := range word {
		if r >= 'a' && r <= 'z' {
			sb.WriteString("[" + string(r-32) + string(r) + "]")
		} else {
			sb.WriteString(regexp.QuoteMeta(string(r)))
		}
	}
	return sb.String()
}

const latin = `A-Za-z\x{C0}-\x{FF}`

var (
	// "Key: value", "**Key:** value", "**Key**: value", "- Key: value".
	reField    = regexp.MustCompile(`^` + reS + `*(?:[-*]` + reS + `+)?\**` + reS + `*([` + latin + `][` + latin + ` ]*?)` + reS + `*\**` + reS + `*:` + reS + `*(` + reDot + `*)$`)
	reHeadSep  = regexp.MustCompile(reS + `+—` + reS + `+|` + reS + `+→` + reS + `+|` + reS + `*\(|;|\.` + reS)
	reProgress = regexp.MustCompile(`^##` + reS + `+` + ci("progress") + `\b`)
	reH2       = regexp.MustCompile(`^##` + reS)
	reRule     = regexp.MustCompile(`^[` + jsSpaceClass + `|:-]+$`)
	reStepHead = regexp.MustCompile(`^` + ci("step") + `$`)
	// A line that stops the run for the user: `BLOCKED…`, `Status: BLOCKED…`.
	reBlocked  = regexp.MustCompile(`^(?:[` + latin + `][` + latin + ` ]{0,30}:` + reS + `*)?BLOCKED\b`)
	reHashes   = regexp.MustCompile(`^#+` + reS + `*`)
	reBullet   = regexp.MustCompile(`^(?:[-*+]|\d+\.)` + reS + `+`)
	reHeading1 = regexp.MustCompile(`^#` + reS + `+` + reNS)
	reHashLead = regexp.MustCompile(`^#` + reS + `+`)
	reApex     = regexp.MustCompile(`^` + ci("apex") + reS + `*[:—–-]` + reS + `*(` + reDot + `+)$`)
	reFlagMode = regexp.MustCompile(`\b` + ci("mode") + reS + `*:?` + reS + `+([^` + jsSpaceClass + `,;)]+)`)
)

// headOf: `High-stakes (sandbox keys) — files…` → `High-stakes`.
func headOf(value string) string {
	if loc := reHeadSep.FindStringIndex(value); loc != nil {
		value = value[:loc[0]]
	}
	return jsTrim(value)
}

// Step is one row of the Progress table.
type Step struct{ Step, Status, Kind string }

func readSteps(lines []string) []Step {
	start := slices.IndexFunc(lines, reProgress.MatchString)
	if start < 0 {
		return nil
	}
	steps := []Step{}
	for _, line := range lines[start+1:] {
		if reH2.MatchString(line) {
			break
		}
		if !strings.HasPrefix(jsTrim(line), "|") {
			continue
		}
		if reRule.MatchString(line) {
			continue
		}
		parts := strings.Split(line, "|")
		var cells []string
		if len(parts) >= 2 {
			cells = parts[1 : len(parts)-1]
		}
		step, status := "", ""
		if len(cells) > 0 {
			step = clean(cells[0])
		}
		if len(cells) > 1 {
			status = clean(cells[1])
		}
		if step == "" || reStepHead.MatchString(step) {
			continue
		}
		steps = append(steps, Step{Step: step, Status: status, Kind: statusKind(status)})
	}
	return steps
}

// blockedLine: outside tables and code fences. `SANDBOX-BLOCKED` in prose is no such line.
func blockedLine(lines []string) (string, bool) {
	fence := false
	for _, line := range lines {
		if strings.HasPrefix(line, "```") {
			fence = !fence
		}
		if fence || strings.HasPrefix(jsTrim(line), "|") {
			continue
		}
		bare := reBullet.ReplaceAllString(reHashes.ReplaceAllString(clean(line), ""), "")
		if reBlocked.MatchString(bare) {
			return bare, true
		}
	}
	return "", false
}

// Context is parseContext's result; nil pointers are board.js's nulls.
type Context struct {
	Title   string
	Tier    *string
	Branch  *string
	Steps   []Step // nil: no Progress table
	Blocked *string
}

func strp(s string) *string { return &s }

func firstJSSpace(s string) int {
	return strings.IndexFunc(s, isJSSpace)
}

func parseContext(text, dirName string) *Context {
	text = strings.ReplaceAll(strings.ReplaceAll(text, "\r\n", "\n"), "\r", "\n")
	lines := strings.Split(text, "\n")
	headerEnd := slices.IndexFunc(lines, reH2.MatchString)
	header := lines
	if headerEnd >= 0 {
		header = lines[:headerEnd]
	}

	headingText := ""
	if i := slices.IndexFunc(header, reHeading1.MatchString); i >= 0 {
		headingText = clean(reHashLead.ReplaceAllString(header[i], ""))
	}
	title := headingText
	if m := reApex.FindStringSubmatch(headingText); m != nil {
		title = m[1]
	}
	title = clean(title)
	if title == "" {
		title = dirName
	}

	fields := map[string]string{}
	for _, line := range header {
		m := reField.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		key := jsLower(jsTrim(m[1]))
		if _, seen := fields[key]; !seen {
			fields[key] = clean(m[2])
		}
	}
	or := func(a, b string) string {
		if a != "" {
			return a
		}
		return b
	}
	tierField, modeField := fields["tier"], fields["mode"]
	flags := or(fields["flags"], fields["flags résolus"])
	tier := ""
	switch {
	case tierField != "":
		tier = headOf(tierField)
	case modeField != "":
		tier = headOf(modeField)
	case flags != "":
		if m := reFlagMode.FindStringSubmatch(flags); m != nil {
			tier = m[1]
		}
	}
	branch := or(fields["branch"], fields["branche"])
	if i := firstJSSpace(branch); i >= 0 {
		branch = branch[:i]
	}

	ctx := &Context{Title: title, Steps: readSteps(lines)}
	if tier != "" {
		ctx.Tier = strp(tier)
	}
	if branch != "" {
		ctx.Branch = strp(branch)
	}
	if b, ok := blockedLine(lines); ok {
		ctx.Blocked = strp(b)
	}
	return ctx
}

// ---- column of a step, of a file ---------------------------------------

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

// stepColumn: its NN prefix, else a word in it; "" when unknown (board.js null).
func stepColumn(step string) string {
	if len(step) >= 2 && isDigit(step[0]) && isDigit(step[1]) {
		n := int(step[0]-'0')*10 + int(step[1]-'0')
		switch {
		case n == 0:
			return "init"
		case n <= 2:
			return "plan"
		case n == 3:
			return "execute"
		case n <= 8:
			return "validate"
		}
		return "done"
	}
	s := jsLower(step)
	has := func(words ...string) bool {
		for _, w := range words {
			if strings.Contains(s, w) {
				return true
			}
		}
		return false
	}
	switch {
	case has("init"):
		return "init"
	case has("analy", "plan", "challenge", "obsidian"):
		return "plan"
	case has("execut", "implement"):
		return "execute"
	case has("valid", "examin", "resolv", "test", "verif", "review"):
		return "validate"
	case has("finish", "ship"):
		return "done"
	}
	return ""
}

var reStepFile = regexp.MustCompile(`^(\d\d)[a-z]?-` + reDot + `*\.md$`)

// fileColumn: the column of the highest NN-*.md among files, "" when none is one.
func fileColumn(files []string) string {
	best := ""
	for _, f := range files {
		if m := reStepFile.FindStringSubmatch(f); m != nil && m[1] > best {
			best = m[1]
		}
	}
	if best == "" {
		return ""
	}
	return stepColumn(best)
}

func shipped(files []string) bool {
	return slices.Contains(files, "pr.md") || slices.Contains(files, "commit.txt")
}

// ---- directory index, budget, verdict -----------------------------------

var (
	reHref     = regexp.MustCompile(`<[Aa]` + reS + `+` + ci("href") + `="([^"]*)"`)
	reEntity   = regexp.MustCompile(`&(?:amp|lt|gt|quot|#x27|#39);`)
	reScheme   = regexp.MustCompile(`^[A-Za-z]+:`)
	entityText = map[string]string{"&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": `"`, "&#x27;": "'", "&#39;": "'"}
)

// IndexEntry is one link of a python http.server directory index.
type IndexEntry struct {
	Name string
	Dir  bool
}

// parseIndex is used by the page only; ported so the rules stay one set.
func parseIndex(html string) []IndexEntry {
	out := []IndexEntry{}
	for _, m := range reHref.FindAllStringSubmatch(html, -1) {
		href := reEntity.ReplaceAllStringFunc(m[1], func(e string) string { return entityText[e] })
		if href == "" || strings.HasPrefix(href, "?") || strings.HasPrefix(href, "/") || reScheme.MatchString(href) {
			continue
		}
		name, ok := decodeURIComponent(href)
		if !ok {
			// A malformed escape is no entry this page could have produced.
			continue
		}
		dir := strings.HasSuffix(name, "/")
		if dir {
			name = name[:len(name)-1]
		}
		if name == "" || name == "." || name == ".." || strings.Contains(name, "/") {
			continue
		}
		out = append(out, IndexEntry{Name: name, Dir: dir})
	}
	return out
}

func unhex(c byte) (byte, bool) {
	switch {
	case c >= '0' && c <= '9':
		return c - '0', true
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10, true
	case c >= 'A' && c <= 'F':
		return c - 'A' + 10, true
	}
	return 0, false
}

// decodeURIComponent: false where JS throws URIError (bad escape, invalid UTF-8).
func decodeURIComponent(s string) (string, bool) {
	if !strings.Contains(s, "%") {
		return s, true
	}
	b := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		if s[i] != '%' {
			b = append(b, s[i])
			continue
		}
		if i+2 >= len(s) {
			return "", false
		}
		h, ok1 := unhex(s[i+1])
		l, ok2 := unhex(s[i+2])
		if !ok1 || !ok2 {
			return "", false
		}
		b = append(b, h<<4|l)
		i += 2
	}
	if !utf8.Valid(b) {
		return "", false
	}
	return string(b), true
}

// Budget is a run's correction rounds used and grants.
type Budget struct{ Rounds, Grants int }

var reBudget = regexp.MustCompile(`^(` + reDot + `+)\.(round|grant)(\d+)$`)

// parseBudget: per run id, from the budget dir's names `<id>.round<n>` / `<id>.grant<n>`.
func parseBudget(names []string) map[string]*Budget {
	budget := map[string]*Budget{}
	for _, name := range names {
		m := reBudget.FindStringSubmatch(name)
		if m == nil {
			continue
		}
		b := budget[m[1]]
		if b == nil {
			b = &Budget{}
			budget[m[1]] = b
		}
		if m[2] == "round" {
			b.Rounds++
		} else {
			b.Grants++
		}
	}
	return budget
}

// Verdict is an external-verify.json's verdict and findings count.
type Verdict struct {
	Verdict  string
	Findings int
}

// parseVerdict: nil when the text is not a verdict (half-written, not JSON, unknown word).
func parseVerdict(text string) *Verdict {
	// A map, not a struct: struct fields would also take "VERDICT" (case-insensitive keys).
	var data map[string]json.RawMessage
	if err := json.Unmarshal([]byte(text), &data); err != nil || data == nil {
		return nil
	}
	raw, ok := data["verdict"]
	if !ok {
		return nil
	}
	var v string
	if err := json.Unmarshal(raw, &v); err != nil {
		return nil
	}
	switch v {
	case "PASS", "FAIL", "BLOCKED", "ERROR":
	default:
		return nil
	}
	n := 0
	if f, ok := data["findings"]; ok && len(f) > 0 && f[0] == '[' {
		var arr []json.RawMessage
		if json.Unmarshal(f, &arr) == nil {
			n = len(arr)
		}
	}
	return &Verdict{Verdict: v, Findings: n}
}

var (
	reVerdictFile = regexp.MustCompile(`^(\d\d[a-z]?-)?external-verify(` + reDot + `*)\.json$`)
	reDigits      = regexp.MustCompile(`\d+`)
)

// verdictFile: the run's latest external verdict file, "" when none. Rounds from the digits
// after `external-verify`; equal rounds fall back on the NN prefix, unprefixed winning.
func verdictFile(files []string) string {
	type key struct {
		name, prefix string
		round        float64
	}
	var best *key
	for _, f := range files {
		m := reVerdictFile.FindStringSubmatchIndex(f)
		if m == nil {
			continue
		}
		k := key{name: f, prefix: "~"}
		if m[2] >= 0 {
			k.prefix = f[m[2]:m[3]]
		}
		if d := reDigits.FindString(f[m[4]:m[5]]); d != "" {
			// Number("…"): a huge digit run is Infinity, as ParseFloat's range error value.
			k.round, _ = strconv.ParseFloat(d, 64)
		}
		if best == nil || k.round > best.round || (k.round == best.round && k.prefix > best.prefix) {
			best = &k
		}
	}
	if best == nil {
		return ""
	}
	return best.name
}

// ---- stage ---------------------------------------------------------------

func isLive(mtimeMs *float64, now float64) bool {
	return mtimeMs != nil && *mtimeMs == *mtimeMs && now-*mtimeMs < StaleMs
}

type reason struct{ text, hint string }

func humanReasons(ctx *Context, budget Budget, verdict *Verdict) []reason {
	reasons := []reason{}
	if ctx != nil {
		for _, s := range ctx.Steps {
			if s.Kind == "failed" {
				reasons = append(reasons, reason{"étape " + s.Step + " en échec", hintSession})
			}
			if s.Kind == "blocked" {
				reasons = append(reasons, reason{"étape " + s.Step + " bloquée", hintSession})
			}
		}
		if ctx.Blocked != nil && *ctx.Blocked != "" {
			reasons = append(reasons, reason{utf16Slice(*ctx.Blocked, 120), hintSession})
		}
	}
	limit := MaxRounds + budget.Grants
	if budget.Rounds >= limit {
		reasons = append(reasons, reason{"budget de correction épuisé (" + strconv.Itoa(budget.Rounds) + "/" + strconv.Itoa(limit) + ")", hintGrant})
	}
	if verdict != nil && verdict.Verdict != "PASS" {
		reasons = append(reasons, reason{"vérif externe " + verdict.Verdict + findingsText(verdict), hintExt})
	}
	return reasons
}

func findingsText(v *Verdict) string {
	if v.Findings > 0 {
		return " · " + strconv.Itoa(v.Findings) + " findings"
	}
	return ""
}

type work struct {
	column   string
	finished bool
	current  *string
}

// workColumn: pr.md / commit.txt, else the Progress table's current step (running, else first
// pending; all done is finished), else the highest NN-*.md file.
func workColumn(ctx *Context, files []string) work {
	if shipped(files) {
		return work{column: "done", finished: true}
	}
	if ctx != nil && len(ctx.Steps) > 0 {
		var open []Step
		for _, s := range ctx.Steps {
			if s.Kind == "running" {
				open = append(open, s)
			}
		}
		for _, s := range ctx.Steps {
			if s.Kind == "pending" {
				open = append(open, s)
			}
		}
		if len(open) == 0 {
			return work{column: "done", finished: true}
		}
		for _, s := range open {
			if col := stepColumn(s.Step); col != "" {
				return work{column: col, finished: col == "done", current: strp(s.Step)}
			}
		}
	}
	col := fileColumn(files)
	if col == "" {
		col = "init"
	}
	return work{column: col, finished: col == "done"}
}

// Chip is one chip of a card's row: tier · ext · corr1 · corr2 (· one more per grant).
type Chip struct{ Key, Label, State, Title string }

func chipsOf(ctx *Context, budget Budget, verdict *Verdict) []Chip {
	tier := ""
	if ctx != nil && ctx.Tier != nil {
		tier = *ctx.Tier
	}
	label, state, known := "tier", "unset", "inconnu"
	if tier != "" {
		label, state, known = tier, "info", tier
	}
	chips := []Chip{{Key: "tier", Label: label, State: state, Title: "tier : " + known}}
	if verdict == nil {
		chips = append(chips, Chip{Key: "ext", Label: "ext", State: "unset", Title: "vérif externe : aucune"})
	} else {
		st := "fail"
		if verdict.Verdict == "PASS" {
			st = "pass"
		}
		chips = append(chips, Chip{Key: "ext", Label: "ext", State: st, Title: "vérif externe : " + verdict.Verdict + findingsText(verdict)})
	}
	total := MaxRounds + budget.Grants
	for n := 1; n <= total; n++ {
		used := budget.Rounds >= n
		st, word, granted := "unset", "libre", ""
		if used {
			st, word = "used", "utilisé"
		}
		if n > MaxRounds {
			granted = " (accordé)"
		}
		k := "corr" + strconv.Itoa(n)
		chips = append(chips, Chip{Key: k, Label: k, State: st, Title: "tour de correction " + strconv.Itoa(n) + " : " + word + granted})
	}
	return chips
}

// RunInput is what deriveRun takes: Context / Verdict nil when not read, MtimeMs nil when
// 00-context.md is absent, Budget nil when the run never used one.
type RunInput struct {
	ID      string
	Context *string
	MtimeMs *float64
	Files   []string
	Budget  *Budget
	Verdict *string

	parsed *Context // parseContext of Context, kept across polls while the run is unchanged
}

func (r *RunInput) context() *Context {
	if r.Context == nil {
		return nil
	}
	if r.parsed == nil {
		r.parsed = parseContext(*r.Context, r.ID)
	}
	return r.parsed
}

// Card is deriveRun's result, field for field.
type Card struct {
	ID       string
	Title    string
	Tier     *string
	Branch   *string
	MtimeMs  *float64
	Live     bool
	Column   string
	Current  *string
	Finished bool
	Flag     *string
	Reasons  []string
	Hints    []string
	Chips    []Chip

	rows rowsMemo // drawn rows, see cardRows
}

// deriveRun: 1. live = mtime < 6 h; 2. live and failed / BLOCKED / budget spent / ext not
// PASS → À toi; 3. not live → Terminé (flag `inactif` unless finished); 4-5. workColumn.
func deriveRun(input *RunInput, now float64) *Card {
	ctx := input.context()
	files := input.Files
	budget := Budget{}
	if input.Budget != nil {
		budget = *input.Budget
	}
	var verdict *Verdict
	if input.Verdict != nil {
		verdict = parseVerdict(*input.Verdict)
	}
	live := isLive(input.MtimeMs, now)
	w := workColumn(ctx, files)
	var reasons []reason
	if live {
		reasons = humanReasons(ctx, budget, verdict)
	}
	hints := []string{}
	for _, r := range reasons {
		if !slices.Contains(hints, r.hint) {
			hints = append(hints, r.hint)
		}
	}
	slices.SortStableFunc(hints, func(a, b string) int {
		ga, gb := 0, 0
		if a == hintGrant {
			ga = 1
		}
		if b == hintGrant {
			gb = 1
		}
		return gb - ga
	})
	column := "done"
	switch {
	case len(reasons) > 0:
		column = "human"
	case live:
		column = w.column
	}
	var flag *string
	if column == "human" {
		flag = strp("à toi")
	} else if !live && !w.finished {
		flag = strp("inactif")
	}
	card := &Card{ID: input.ID, Title: input.ID, MtimeMs: input.MtimeMs, Live: live, Column: column, Current: w.current, Finished: w.finished, Flag: flag, Hints: hints, Chips: chipsOf(ctx, budget, verdict)}
	if ctx != nil {
		card.Title, card.Tier, card.Branch = ctx.Title, ctx.Tier, ctx.Branch
	}
	card.Reasons = make([]string, len(reasons))
	for i, r := range reasons {
		card.Reasons[i] = r.text
	}
	return card
}

// Group is one column's cards; More counts Terminé cards past DoneCap.
type Group struct {
	Cards []*Card
	More  int
}

// groupRuns: cards per column, newest first; Terminé capped at DoneCap.
func groupRuns(cards []*Card) map[string]*Group {
	out := map[string]*Group{}
	for _, c := range Columns {
		out[c.Key] = &Group{Cards: []*Card{}}
	}
	sorted := slices.Clone(cards)
	ms := func(c *Card) float64 {
		if c.MtimeMs == nil || *c.MtimeMs != *c.MtimeMs {
			return 0
		}
		return *c.MtimeMs
	}
	slices.SortStableFunc(sorted, func(a, b *Card) int {
		if d := ms(b) - ms(a); d != 0 && d == d {
			if d < 0 {
				return -1
			}
			return 1
		}
		return -jsCompare(a.ID, b.ID)
	})
	for _, c := range sorted {
		g := out[c.Column]
		g.Cards = append(g.Cards, c)
	}
	done := out["done"]
	done.More = max(0, len(done.Cards)-DoneCap)
	if len(done.Cards) > DoneCap {
		done.Cards = done.Cards[:DoneCap]
	}
	return out
}

// ---- drawer --------------------------------------------------------------

var (
	reVerdictLead = regexp.MustCompile(`^` + ci("verdict") + reS + `*:` + reS + `*`)
	reToneGood    = regexp.MustCompile(`^(PASS|APPROVED?|READY)\b`)
	reToneWarn    = regexp.MustCompile(`^(NEEDS_FIXES|CHANGES|FAIL)\b`)
	reToneStop    = regexp.MustCompile(`^(BLOCKED|ESCALATE|ERROR)\b`)
)

// lineTone: good, warn, stop or "" (null); a verdict word heading the line.
func lineTone(line string) string {
	bare := reVerdictLead.ReplaceAllString(reHashes.ReplaceAllString(clean(line), ""), "")
	switch {
	case reToneGood.MatchString(bare):
		return "good"
	case reToneWarn.MatchString(bare):
		return "warn"
	case reToneStop.MatchString(bare):
		return "stop"
	}
	return ""
}

// fileTone: a JSON verdict, else the first non-empty line of the text.
func fileTone(name, text string) string {
	if strings.HasSuffix(name, ".json") {
		v := parseVerdict(text)
		switch {
		case v == nil:
			return ""
		case v.Verdict == "PASS":
			return "good"
		}
		return "stop"
	}
	for line := range strings.SplitSeq(text, "\n") {
		if jsTrim(line) != "" {
			return lineTone(line)
		}
	}
	return ""
}

// sortFiles: 00-context.md, step files by name, then the rest; files of a subdir after.
func sortFiles(paths []string) []string {
	rank := func(p string) int {
		switch {
		case strings.Contains(p, "/"):
			return 3
		case p == "00-context.md":
			return 0
		case len(p) >= 2 && isDigit(p[0]) && isDigit(p[1]):
			return 1
		}
		return 2
	}
	out := slices.Clone(paths)
	slices.SortStableFunc(out, func(a, b string) int {
		if d := rank(a) - rank(b); d != 0 {
			return d
		}
		return jsCompare(a, b)
	})
	return out
}
