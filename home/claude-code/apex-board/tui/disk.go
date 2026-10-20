package main

// Disk side (port of tui.js readRuns / readRun / listRunFiles / readRunFile / loadDrawer).
// Read-only: it lists and reads, never writes. A path whose realpath leaves the runs dir is never
// read (« hors du run »); a symlinked dir is listed, never descended; control chars are drawn `?`
// by toCells; a file is read up to maxBytes; a listing stops at maxFiles entries.

import (
	"bytes"
	"errors"
	"io"
	"io/fs"
	"math"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
)

const (
	maxBytes = 512 * 1024
	maxFiles = 2000
	maxDepth = 8
	// What a file whose realpath leaves the runs dir shows instead of its content.
	outsideText = "« hors du run »"
)

// FileRead is a run file: Kind text | outside | missing | binary | error | empty.
type FileRead struct {
	Kind    string
	Text    string
	MtimeMs float64
}

func isGone(err error) bool {
	return errors.Is(err, fs.ErrNotExist) || errors.Is(err, syscall.ENOTDIR)
}

func realRoot(root string) (string, error) {
	abs, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	return filepath.EvalSymlinks(abs)
}

// realInside: the realpath of p and 1 when it stays under base, -1 when it leaves it, 0 when
// it is gone (a dangling link included: nothing to read, which is not an error).
func realInside(base, p string) (string, int, error) {
	// Absolute first: EvalSymlinks keeps a relative path relative, realpath does not.
	abs, err := filepath.Abs(p)
	if err != nil {
		return "", 0, err
	}
	real, err := filepath.EvalSymlinks(abs)
	if err != nil {
		if isGone(err) {
			return "", 0, nil
		}
		return "", 0, err
	}
	if real == base || strings.HasPrefix(real, base+string(filepath.Separator)) {
		return real, 1, nil
	}
	return "", -1, nil
}

// mtimeMs as node's stat computes it: sec * 1e3 + nsec / 1e6.
func mtimeMs(fi fs.FileInfo) float64 {
	t := fi.ModTime()
	return float64(t.Unix()*1000) + float64(t.Nanosecond())/1e6
}

// readCapped: a regular file's text up to maxBytes (the rest announced); binary and
// non-files are not read.
func readCapped(file string) (FileRead, error) {
	fi, err := os.Stat(file)
	if err != nil {
		return FileRead{}, err
	}
	if !fi.Mode().IsRegular() {
		return FileRead{Kind: "error", Text: "pas un fichier ordinaire : non lu"}, nil
	}
	n := min(fi.Size(), maxBytes)
	f, err := os.Open(file)
	if err != nil {
		return FileRead{}, err
	}
	defer f.Close()
	buf := make([]byte, n)
	got, err := io.ReadFull(f, buf)
	if err != nil && !errors.Is(err, io.ErrUnexpectedEOF) && !errors.Is(err, io.EOF) {
		return FileRead{}, err
	}
	data := buf[:got]
	if bytes.IndexByte(data, 0) >= 0 {
		return FileRead{Kind: "binary", MtimeMs: mtimeMs(fi)}, nil
	}
	text := decodeUTF8(data)
	if fi.Size() > maxBytes {
		ko := math.Floor(float64(fi.Size())/1024 + 0.5)
		text += "\n\n… tronqué : " + strconv.FormatFloat(ko, 'f', -1, 64) + " Ko, " + strconv.Itoa(maxBytes/1024) + " Ko affichés\n"
	}
	return FileRead{Kind: "text", Text: text, MtimeMs: mtimeMs(fi)}, nil
}

func safeID(id string) bool {
	return id != "" && id != "." && id != ".." && !strings.Contains(id, "/") && !strings.ContainsRune(id, filepath.Separator)
}

// readRunFile: `rel` is `/`-separated as listRunFiles gives it; any path whose realpath leaves
// runsDir is `outside` and never opened.
func readRunFile(runsDir, id, rel string) (FileRead, error) {
	parts := strings.Split(rel, "/")
	if !safeID(id) || strings.HasPrefix(rel, "/") || slices.ContainsFunc(parts, func(p string) bool { return p == "" || p == "." || p == ".." }) {
		return FileRead{Kind: "outside", Text: outsideText}, nil
	}
	base, err := realRoot(runsDir)
	if err != nil {
		return FileRead{}, err
	}
	real, where, err := realInside(base, filepath.Join(append([]string{runsDir, id}, parts...)...))
	switch {
	case err != nil:
		return FileRead{}, err
	case where == 0:
		return FileRead{Kind: "missing"}, nil
	case where < 0:
		return FileRead{Kind: "outside", Text: outsideText}, nil
	}
	return readCapped(real)
}

func sortedEntries(dir string) ([]fs.DirEntry, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	slices.SortFunc(entries, func(a, b fs.DirEntry) int { return jsCompare(a.Name(), b.Name()) })
	return entries, nil
}

// listRunFiles: recursive, `/`-separated; a symlink is listed as a file and never descended.
func listRunFiles(runDir string) ([]string, error) {
	out := []string{}
	var walk func(dir, prefix string, depth int) error
	walk = func(dir, prefix string, depth int) error {
		entries, err := sortedEntries(dir)
		if err != nil {
			return err
		}
		for _, e := range entries {
			if len(out) >= maxFiles {
				return nil
			}
			if e.IsDir() {
				if depth < maxDepth {
					if err := walk(filepath.Join(dir, e.Name()), prefix+e.Name()+"/", depth+1); err != nil {
						return err
					}
				}
			} else {
				out = append(out, prefix+e.Name())
			}
		}
		return nil
	}
	if err := walk(runDir, "", 0); err != nil {
		return nil, err
	}
	return out, nil
}

func readBudget(budgetDir string) (map[string]*Budget, string) {
	if budgetDir == "" {
		return map[string]*Budget{}, ""
	}
	entries, err := os.ReadDir(budgetDir)
	if err != nil {
		// No budget dir yet means no correction round was ever used; anything else is shown.
		if errors.Is(err, fs.ErrNotExist) {
			return map[string]*Budget{}, ""
		}
		return map[string]*Budget{}, "budget/ illisible, tours de correction inconnus : " + err.Error()
	}
	names := make([]string, len(entries))
	for i, e := range entries {
		names[i] = e.Name()
	}
	return parseBudget(names), ""
}

func runIDs(runsDir string) ([]string, error) {
	entries, err := sortedEntries(runsDir)
	if err != nil {
		return nil, err
	}
	var ids []string
	for _, e := range entries {
		if e.IsDir() {
			ids = append(ids, e.Name())
		}
	}
	return ids, nil
}

// readRuns: the deriveRun inputs of every run dir (real dirs only, by name). A missing budget
// dir is no round used; other read errors land in problems and the board goes on.
func readRuns(runsDir, budgetDir string) ([]*RunInput, []string, error) {
	r := &Reader{RunsDir: runsDir, BudgetDir: budgetDir}
	return r.read(false)
}

func runFiles(dir string) ([]string, error) {
	entries, err := sortedEntries(dir)
	if err != nil {
		return nil, err
	}
	files := []string{}
	for _, e := range entries {
		if !e.IsDir() {
			files = append(files, e.Name())
		}
	}
	return files, nil
}

func readRun(base, runsDir, id string, files []string) (*RunInput, error) {
	dir := filepath.Join(runsDir, id)
	text := func(name string) (*FileRead, error) {
		real, where, err := realInside(base, filepath.Join(dir, name))
		if err != nil || where <= 0 {
			return nil, err
		}
		r, err := readCapped(real)
		if err != nil || r.Kind != "text" {
			return nil, err
		}
		return &r, nil
	}
	in := &RunInput{ID: id, Files: files}
	if slices.Contains(files, "00-context.md") {
		ctx, err := text("00-context.md")
		if err != nil {
			return nil, err
		}
		if ctx != nil {
			in.Context, in.MtimeMs = strp(ctx.Text), &ctx.MtimeMs
		}
	}
	if vf := verdictFile(files); vf != "" {
		v, err := text(vf)
		if err != nil {
			return nil, err
		}
		if v != nil {
			in.Verdict = strp(v.Text)
		}
	}
	return in, nil
}

// Reader is readRuns made incremental: a run whose listing and read files (00-context.md,
// verdict) did not change keeps its parsed input. Used from one goroutine at a time (the poll).
type Reader struct {
	RunsDir, BudgetDir string

	base  string
	cache map[string]cachedRun
}

type cachedRun struct {
	sig   string
	input RunInput
}

// signature: the run's top-level names and the identity of the files readRun reads (stat
// follows links, so a link pointed elsewhere changes it too).
func signature(dir string, files []string) string {
	var sb strings.Builder
	for _, f := range files {
		sb.WriteString(f)
		sb.WriteByte(0)
	}
	for _, name := range []string{"00-context.md", verdictFile(files)} {
		if name == "" || !slices.Contains(files, name) {
			continue
		}
		fi, err := os.Stat(filepath.Join(dir, name))
		if err != nil {
			sb.WriteString("?")
			continue
		}
		sb.WriteString(strconv.FormatInt(fi.Size(), 10) + ":" + strconv.FormatInt(fi.ModTime().UnixNano(), 10) + ":" + fi.Mode().String())
		if st, ok := fi.Sys().(*syscall.Stat_t); ok {
			sb.WriteString(":" + strconv.FormatUint(uint64(st.Ino), 10) + ":" + strconv.FormatInt(int64(st.Dev), 10))
		}
		sb.WriteByte(0)
	}
	return sb.String()
}

// Read is one poll: runs, problems, or the error of the runs dir itself.
func (r *Reader) Read() ([]*RunInput, []string, error) { return r.read(true) }

func (r *Reader) read(incremental bool) ([]*RunInput, []string, error) {
	ids, err := runIDs(r.RunsDir)
	if err != nil {
		return nil, nil, err
	}
	var problems []string
	budget, problem := readBudget(r.BudgetDir)
	if problem != "" {
		problems = append(problems, problem)
	}
	base, err := realRoot(r.RunsDir)
	if err != nil {
		return nil, nil, err
	}
	if base != r.base {
		r.base, r.cache = base, nil
	}
	next := map[string]cachedRun{}
	runs := []*RunInput{}
	for _, id := range ids {
		dir := filepath.Join(r.RunsDir, id)
		files, err := runFiles(dir)
		var in *RunInput
		if err == nil {
			sig := ""
			if incremental {
				sig = signature(dir, files)
				if c, ok := r.cache[id]; ok && c.sig == sig {
					cp := c.input
					in = &cp
				}
			}
			if in == nil {
				in, err = readRun(base, r.RunsDir, id, files)
			}
			if err == nil && incremental {
				in.context() // parsed here, off the UI goroutine
				next[id] = cachedRun{sig: sig, input: *in}
			}
		}
		if err != nil {
			// A run removed between the listing and its read is simply gone; anything else is shown.
			if !isGone(err) {
				problems = append(problems, id+" : "+err.Error())
			}
			continue
		}
		in.Budget = budget[id]
		runs = append(runs, in)
	}
	if incremental {
		r.cache = next
	}
	return runs, problems, nil
}

// DrawerData is loadDrawer's read of the open run: files, verdict dots, the shown file.
type DrawerData struct {
	Files   []string
	Tones   map[string]string
	Path    string // "" when the run has no file
	Doc     FileRead
	ListErr bool
}

// loadDrawer: the open run's file list, verdict dots and file `want` (else the first), read again.
func loadDrawer(runsDir, id, want string) DrawerData {
	files, err := listRunFiles(filepath.Join(runsDir, id))
	if err != nil {
		// The run dir went away or is unreadable: say so in the doc pane, as the page's note does.
		return DrawerData{Files: []string{}, Tones: map[string]string{}, Doc: FileRead{Kind: "error", Text: err.Error()}, ListErr: true}
	}
	files = sortFiles(files)
	tones := map[string]string{}
	for _, f := range files {
		if !strings.HasSuffix(f, ".md") && !strings.HasSuffix(f, ".json") {
			continue
		}
		// An unreadable file only loses its dot (tui.js let the throw end the program).
		if r, err := readRunFile(runsDir, id, f); err == nil && r.Kind == "text" {
			tones[f] = fileTone(f, r.Text)
		}
	}
	p := ""
	if want != "" && slices.Contains(files, want) {
		p = want
	} else if len(files) > 0 {
		p = files[0]
	}
	d := DrawerData{Files: files, Tones: tones, Path: p}
	if p == "" {
		d.Doc = FileRead{Kind: "empty"}
	} else {
		d.Doc = loadDoc(runsDir, id, p)
	}
	return d
}

// loadDoc: one file for the doc pane; an unreadable one shows its reason.
func loadDoc(runsDir, id, p string) FileRead {
	r, err := readRunFile(runsDir, id, p)
	if err != nil {
		return FileRead{Kind: "error", Text: err.Error()}
	}
	return r
}
