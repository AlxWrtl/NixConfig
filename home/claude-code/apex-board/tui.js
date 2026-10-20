'use strict'
// APEX board in the terminal: the page of index.html (same columns, cards, chips, drawer and
// markdown) drawn with ANSI truecolor, read straight from disk. Every column / flag / chip rule
// comes from board.js; this file only reads files and draws.
//
//   node tui.js <runs-dir> [budget-dir] [repo-name]
//
// Read-only: it lists and reads, never writes a file. A path whose realpath leaves <runs-dir> is
// never read (shown as « hors du run »); a symlinked dir is listed, never descended.
// Two layers: pure functions (exported when required, driven by tui-test.js) and the IO shell
// (alt screen, raw stdin, SGR mouse, 2 s poll) that runs only as main and always restores the
// terminal: q, Ctrl-C, SIGTERM, SIGHUP, an uncaught error.

const fs = require('fs')
const path = require('path')
const B = require('./board.js')

/** Disk poll period, as the page's POLL_MS. */
const POLL_MS = 2000
/** Pulse period of a live card's dot. */
const TICK_MS = 1000
/** A file is read up to this many bytes; the rest is announced, not shown. */
const MAX_BYTES = 512 * 1024
/** Drawer listing bounds: entries and subdir depth. */
const MAX_FILES = 2000
const MAX_DEPTH = 8
/** The page's drawer is min(920px, 100vw): about 100 columns. */
const DRAWER_W = 100
/** Board geometry: side margin, gap between columns, narrowest column before scrolling sideways. */
const MARGIN = 2
const GAP = 3
const MIN_COL = 20
/** Cards a PgUp / PgDn moves on the board. */
const PAGE_CARDS = 5
/** What a file whose realpath leaves the runs dir shows instead of its content. */
const OUTSIDE = '« hors du run »'

// Alt screen, hidden cursor, no autowrap, mouse clicks + SGR coordinates; LEAVE undoes all of it.
const ENTER = '\x1b[?1049h\x1b[?25l\x1b[?7l\x1b[?1000h\x1b[?1006h\x1b[2J'
const LEAVE = '\x1b[0m\x1b[?1006l\x1b[?1000l\x1b[?7h\x1b[?25h\x1b[?1049l'
const SYNC_ON = '\x1b[?2026h'
const SYNC_OFF = '\x1b[?2026l'

// ---- palette (index.html :root) -------------------------------------------

const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)]
const P = {
  bg: hex('#14151b'),
  panel: hex('#1a1c24'),
  card: hex('#20222c'),
  cardHover: hex('#252835'),
  line: hex('#2b2e3b'),
  text: hex('#e4e5ea'),
  muted: hex('#868ba0'),
  faint: hex('#5b6075'),
  active: hex('#8be9fd'),
  pass: hex('#50fa7b'),
  changes: hex('#ffb86c'),
  human: hex('#ff79c6'),
  merged: hex('#bd93f9'),
}
/** The page's scrim, rgba(5, 6, 10, .55). */
const SCRIM = [5, 6, 10]
/** color-mix(in srgb, a t, b). */
const mix = (a, b, t) => a.map((v, i) => Math.round(v * t + b[i] * (1 - t)))
const TONE = { good: P.pass, warn: P.changes, stop: P.human }
const LABEL = Object.fromEntries(B.COLUMNS.map((c) => [c.key, c.label]))
const FOOTER = ['/apex <tâche>', '/apex -x <tâche>', 'apex: +1 tour', '/deck']
const KEYS_BOARD = '←→↑↓ naviguer · ⏎ ouvrir · esc fermer · q quitter'

const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n))

// ---- cells: one per terminal column ---------------------------------------
// A cell is { ch, w, fg, bg, b, i, u }: w 2 for a wide char, whose right half is a w 0 cell.

const CTL = -1
const DROP = -2
const WIDE = [
  [0x1100, 0x115f], [0x231a, 0x231b], [0x2329, 0x232a], [0x23e9, 0x23ec], [0x23f0, 0x23f0], [0x23f3, 0x23f3],
  [0x25fd, 0x25fe], [0x2614, 0x2615], [0x2648, 0x2653], [0x267f, 0x267f], [0x2693, 0x2693], [0x26a1, 0x26a1],
  [0x26aa, 0x26ab], [0x26bd, 0x26be], [0x26c4, 0x26c5], [0x26ce, 0x26ce], [0x26d4, 0x26d4], [0x26ea, 0x26ea],
  [0x26f2, 0x26f3], [0x26f5, 0x26f5], [0x26fa, 0x26fa], [0x26fd, 0x26fd], [0x2705, 0x2705], [0x270a, 0x270b],
  [0x2728, 0x2728], [0x274c, 0x274c], [0x274e, 0x274e], [0x2753, 0x2755], [0x2757, 0x2757], [0x2795, 0x2797],
  [0x27b0, 0x27b0], [0x27bf, 0x27bf], [0x2b1b, 0x2b1c], [0x2b50, 0x2b50], [0x2b55, 0x2b55], [0x2e80, 0x303e],
  [0x3041, 0x33ff], [0x3400, 0x4dbf], [0x4e00, 0x9fff], [0xa000, 0xa4cf], [0xac00, 0xd7a3], [0xf900, 0xfaff],
  [0xfe30, 0xfe4f], [0xff00, 0xff60], [0xffe0, 0xffe6], [0x1f004, 0x1f004], [0x1f0cf, 0x1f0cf], [0x1f18e, 0x1f18e],
  [0x1f191, 0x1f19a], [0x1f200, 0x1f251], [0x1f300, 0x1f3fa], [0x1f400, 0x1f64f], [0x1f680, 0x1f6ff],
  [0x1f7e0, 0x1f7eb], [0x1f900, 0x1f9ff], [0x1fa70, 0x1faff], [0x20000, 0x3fffd],
]
const COMBINING = [[0x300, 0x36f], [0x483, 0x489], [0x591, 0x5bd], [0x610, 0x61a], [0x64b, 0x65f], [0x1ab0, 0x1aff], [0x1dc0, 0x1dff], [0x20d0, 0x20ff], [0xfe20, 0xfe2f]]
// Invisible or presentation-switching: dropped so the counted width is the drawn width.
const DROPPED = [[0xad, 0xad], [0x200b, 0x200f], [0x2028, 0x202e], [0x2060, 0x206f], [0xfe00, 0xfe0f], [0xfeff, 0xfeff], [0x1f3fb, 0x1f3ff], [0xe0000, 0xe007f]]
const inRanges = (cp, ranges) => ranges.some(([lo, hi]) => cp >= lo && cp <= hi)

/** Columns a code point takes: 1 or 2, 0 for a combining mark, CTL for a control, DROP for an invisible. */
function cpWidth(cp) {
  if (cp < 0x20 || (cp >= 0x7f && cp < 0xa0)) return CTL
  if (cp < 0x300) return cp === 0xad ? DROP : 1
  if (inRanges(cp, DROPPED)) return DROP
  if (inRanges(cp, COMBINING)) return 0
  return inRanges(cp, WIDE) ? 2 : 1
}

const cell = (ch, w, st) => ({ ch, w, fg: st.fg, bg: st.bg, b: !!st.b, i: !!st.i, u: !!st.u })

/** Text as cells. A control char (ESC included) becomes `?`: file text never drives the terminal. */
function toCells(str, st, out = []) {
  for (const ch of String(str)) {
    const cp = ch.codePointAt(0)
    if (cp === 9) {
      out.push(cell(' ', 1, st))
      continue
    }
    const w = cpWidth(cp)
    if (w === CTL) out.push(cell('?', 1, st))
    else if (w === DROP) continue
    else if (w === 0) {
      if (out.length > 0) out[out.length - 1] = { ...out[out.length - 1], ch: out[out.length - 1].ch + ch }
    } else out.push(cell(ch, w, st))
  }
  return out
}

const cellsWidth = (cells) => cells.reduce((n, c) => n + c.w, 0)
const spaces = (n, st) => Array.from({ length: Math.max(0, n) }, () => cell(' ', 1, st))

/** The first `w` columns of `cells`; a wide char cut in half becomes a space. */
function clipCells(cells, w) {
  const out = []
  let n = 0
  for (const c of cells) {
    if (n + c.w > w) {
      if (n < w) out.push({ ...c, ch: ' ', w: 1 })
      break
    }
    out.push(c)
    n += c.w
  }
  return out
}

/** `cells` clipped then padded to exactly `w` columns with spaces on `bg`. */
const padTo = (cells, w, bg) => {
  const c = clipCells(cells, w)
  return [...c, ...spaces(w - cellsWidth(c), { bg })]
}

/** `cells` within `w` columns, an ellipsis replacing what does not fit. */
function fitCells(cells, w) {
  if (w <= 0) return []
  if (cellsWidth(cells) <= w) return cells
  const kept = clipCells(cells, w - 1)
  const st = cells[Math.min(kept.length, cells.length - 1)] || {}
  return [...kept, cell('…', 1, st)]
}

/** Word-wrap cells to `w` columns; a word longer than a line is cut. Always at least one line. */
function wrapCells(cells, width) {
  const w = Math.max(1, width)
  const lines = []
  let line = []
  let lineW = 0
  const flush = () => {
    while (line.length > 0 && line[line.length - 1].ch === ' ') {
      line.pop()
      lineW--
    }
    lines.push(line)
    line = []
    lineW = 0
  }
  let i = 0
  while (i < cells.length) {
    if (cells[i].ch === ' ') {
      if (lineW > 0 && lineW + 1 <= w) {
        line.push(cells[i])
        lineW++
      }
      i++
      continue
    }
    let j = i
    let ww = 0
    while (j < cells.length && cells[j].ch !== ' ') ww += cells[j++].w
    if (lineW > 0 && lineW + ww > w) flush()
    for (let k = i; k < j; k++) {
      if (lineW + cells[k].w > w) flush()
      line.push(cells[k])
      lineW += cells[k].w
    }
    i = j
  }
  if (line.length > 0 || lines.length === 0) flush()
  return lines
}

/** Cells cut every `w` columns, no word logic (code). */
function hardWrap(cells, width) {
  const w = Math.max(1, width)
  const out = []
  let line = []
  let n = 0
  for (const c of cells) {
    if (n + c.w > w) {
      out.push(line)
      line = []
      n = 0
    }
    line.push(c)
    n += c.w
  }
  out.push(line)
  return out
}

/** `str` wrapped to `w`, at most `max` lines, the last one ending in `…` when text was cut. */
function wrapText(str, w, max, st) {
  const lines = wrapCells(toCells(str, st), w)
  if (lines.length <= max) return lines
  const kept = lines.slice(0, max)
  kept[max - 1] = [...clipCells(kept[max - 1], Math.max(0, w - 1)), cell('…', 1, st)]
  return kept
}

// ---- ANSI ------------------------------------------------------------------

function sgr(c) {
  let s = '\x1b[0'
  if (c.fg) s += `;38;2;${c.fg[0]};${c.fg[1]};${c.fg[2]}`
  if (c.bg) s += `;48;2;${c.bg[0]};${c.bg[1]};${c.bg[2]}`
  if (c.b) s += ';1'
  if (c.i) s += ';3'
  if (c.u) s += ';4'
  return s + 'm'
}

/** One line of cells as an ANSI string, attributes reset at its end. */
function serialize(cells) {
  let out = ''
  let last = null
  for (const c of cells) {
    if (c.w === 0) continue
    const k = sgr(c)
    if (k !== last) {
      out += k
      last = k
    }
    out += c.ch
  }
  return out + '\x1b[0m'
}

/** `s` without its escape sequences (CSI, OSC, two-byte). */
function stripAnsi(s) {
  let out = ''
  let i = 0
  while (i < s.length) {
    if (s.charCodeAt(i) !== 27) {
      out += s[i++]
      continue
    }
    const next = s[i + 1]
    if (next === '[') {
      i += 2
      while (i < s.length && !(s.charCodeAt(i) >= 0x40 && s.charCodeAt(i) <= 0x7e)) i++
      i++
    } else if (next === ']') {
      i += 2
      while (i < s.length && s.charCodeAt(i) !== 7 && !(s.charCodeAt(i) === 27 && s[i + 1] === '\\')) i++
      i += s.charCodeAt(i) === 7 ? 1 : 2
    } else i += 2
  }
  return out
}

/** Columns an ANSI string takes on screen. */
const visibleWidth = (s) => cellsWidth(toCells(stripAnsi(s), {}))

// ---- grid ------------------------------------------------------------------

const blank = (bg) => ({ ch: ' ', w: 1, fg: P.text, bg, b: false, i: false, u: false })

function makeGrid(w, h, bg) {
  return Array.from({ length: h }, () => Array.from({ length: w }, () => blank(bg)))
}

/** Set one cell, keeping wide chars whole: an overwritten half blanks the other half. */
function setCell(row, x, c) {
  if (x < 0 || x >= row.length) return
  const old = row[x]
  if (old.w === 0 && x > 0) row[x - 1] = { ...row[x - 1], ch: ' ', w: 1 }
  if (old.w === 2 && x + 1 < row.length) row[x + 1] = { ...row[x + 1], ch: ' ', w: 1 }
  if (c.w !== 2) {
    row[x] = c
    return
  }
  if (x + 1 >= row.length) {
    row[x] = { ...c, ch: ' ', w: 1 }
    return
  }
  if (row[x + 1].w === 2 && x + 2 < row.length) row[x + 2] = { ...row[x + 2], ch: ' ', w: 1 }
  row[x] = c
  row[x + 1] = { ...c, ch: '', w: 0 }
}

/** Draw cells from x, stopping before maxX; a cell without bg takes the one under it. */
function putCells(row, x, cells, maxX) {
  for (const c of cells) {
    if (x >= maxX) break
    if (x < 0) {
      x += c.w
      continue
    }
    const full = { ...c, fg: c.fg || P.text, bg: c.bg || row[x].bg }
    if (x + c.w > maxX) {
      setCell(row, x, { ...full, ch: ' ', w: 1 })
      return maxX
    }
    setCell(row, x, full)
    x += c.w
  }
  return x
}

function put(g, x, y, cells, maxX) {
  if (y < 0 || y >= g.length) return x
  const row = g[y]
  return putCells(row, x, cells, maxX === undefined ? row.length : Math.min(maxX, row.length))
}

function fillRow(g, y, x0, x1, bg) {
  if (y < 0 || y >= g.length) return
  for (let x = Math.max(0, x0); x < Math.min(x1, g[y].length); x++) setCell(g[y], x, blank(bg))
}

/** A cell seen through a layer: opacity `t` over `toward`. */
const fadeCell = (c, toward, t) => ({ ...c, fg: mix(c.fg || P.text, toward, t), bg: mix(c.bg || P.bg, toward, t) })

// ---- disk ------------------------------------------------------------------

/** Realpath of `p` when it stays under `root`, false when it leaves it, null when it is gone. */
function realInside(root, p, fsImpl) {
  let real
  try {
    real = fsImpl.realpathSync(p)
  } catch (err) {
    // Gone, or a dangling link: there is nothing to read, which is not an error.
    if (err.code === 'ENOENT' || err.code === 'ENOTDIR') return null
    throw err
  }
  const base = fsImpl.realpathSync(root)
  return real === base || real.startsWith(base + path.sep) ? real : false
}

/** A regular file's text, up to MAX_BYTES (the rest announced); binary and non-files are not read. */
function readCapped(file, fsImpl) {
  const st = fsImpl.statSync(file)
  if (!st.isFile()) return { kind: 'error', text: 'pas un fichier ordinaire : non lu' }
  const len = Math.min(st.size, MAX_BYTES)
  const buf = Buffer.alloc(len)
  const fd = fsImpl.openSync(file, 'r')
  let off = 0
  try {
    while (off < len) {
      const n = fsImpl.readSync(fd, buf, off, len - off, off)
      if (n === 0) break
      off += n
    }
  } finally {
    fsImpl.closeSync(fd)
  }
  const data = buf.subarray(0, off)
  if (data.includes(0)) return { kind: 'binary', mtimeMs: st.mtimeMs }
  let text = data.toString('utf8')
  if (st.size > MAX_BYTES) text += `\n\n… tronqué : ${Math.round(st.size / 1024)} Ko, ${MAX_BYTES / 1024} Ko affichés\n`
  return { kind: 'text', text, mtimeMs: st.mtimeMs }
}

const safeId = (id) => typeof id === 'string' && id !== '' && id !== '.' && id !== '..' && !id.includes('/') && !id.includes(path.sep)

/**
 * A run file: { kind: 'text', text, mtimeMs } | { kind: 'outside', text: OUTSIDE } | { kind:
 * 'missing' } | { kind: 'binary' } | { kind: 'error', text }. `rel` is `/`-separated, as
 * listRunFiles gives it; any path whose realpath leaves `runsDir` is `outside` and never opened.
 */
function readRunFile(runsDir, id, rel, fsImpl = fs) {
  const parts = String(rel).split('/')
  if (!safeId(id) || path.isAbsolute(rel) || parts.some((p) => p === '' || p === '.' || p === '..')) return { kind: 'outside', text: OUTSIDE }
  const real = realInside(runsDir, path.join(runsDir, id, ...parts), fsImpl)
  if (real === null) return { kind: 'missing' }
  if (real === false) return { kind: 'outside', text: OUTSIDE }
  return readCapped(real, fsImpl)
}

/** A run's files, recursive, `/`-separated; a symlink is listed as a file and never descended. */
function listRunFiles(runDir, fsImpl = fs) {
  const out = []
  const walk = (dir, prefix, depth) => {
    const entries = fsImpl.readdirSync(dir, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))
    for (const e of entries) {
      if (out.length >= MAX_FILES) return
      if (e.isDirectory()) {
        if (depth < MAX_DEPTH) walk(path.join(dir, e.name), `${prefix}${e.name}/`, depth + 1)
      } else out.push(prefix + e.name)
    }
  }
  walk(runDir, '', 0)
  return out
}

/**
 * The deriveRun inputs of every run dir under `runsDir` (real dirs only, by name): context and
 * its mtimeMs, top-level file names, budget, external verdict text. A missing budget dir is no
 * round used; other read errors land in `problems` (as the page's banner) and the board goes on.
 */
function readRuns(runsDir, budgetDir, fsImpl = fs, problems = []) {
  const ids = fsImpl.readdirSync(runsDir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name).sort()
  let budget = new Map()
  if (budgetDir) {
    try {
      budget = B.parseBudget(fsImpl.readdirSync(budgetDir))
    } catch (err) {
      // No budget dir yet means no correction round was ever used; anything else is shown.
      if (err.code !== 'ENOENT') problems.push(`budget/ illisible, tours de correction inconnus : ${err.message}`)
    }
  }
  const runs = []
  for (const id of ids) {
    try {
      runs.push(readRun(runsDir, id, budget.get(id), fsImpl))
    } catch (err) {
      // A run removed between the listing and its read is simply gone; anything else is shown.
      if (err.code !== 'ENOENT') problems.push(`${id} : ${err.message}`)
    }
  }
  return runs
}

function readRun(runsDir, id, budget, fsImpl) {
  const dir = path.join(runsDir, id)
  const files = fsImpl.readdirSync(dir, { withFileTypes: true }).filter((e) => !e.isDirectory()).map((e) => e.name).sort()
  const text = (name) => {
    const real = realInside(runsDir, path.join(dir, name), fsImpl)
    if (typeof real !== 'string') return null
    const r = readCapped(real, fsImpl)
    return r.kind === 'text' ? r : null
  }
  const ctx = files.includes('00-context.md') ? text('00-context.md') : null
  const vf = B.verdictFile(files)
  const verdict = vf ? text(vf) : null
  return { id, context: ctx ? ctx.text : null, mtimeMs: ctx ? ctx.mtimeMs : null, files, budget, verdict: verdict ? verdict.text : null }
}

/** The open run's file list, verdict dots and selected file, read again. */
function loadDrawer(state, runsDir, fsImpl = fs) {
  const d = state.drawer
  if (!d) return { ...state, need: null }
  let files
  try {
    files = B.sortFiles(listRunFiles(path.join(runsDir, d.id), fsImpl))
  } catch (err) {
    // The run dir went away or is unreadable: say so in the doc pane, as the page's note does.
    return { ...state, need: null, drawer: { ...d, files: [], tones: {}, path: null, doc: { kind: 'error', text: err.message } } }
  }
  const tones = {}
  for (const f of files) {
    if (!/\.(md|json)$/.test(f)) continue
    const r = readRunFile(runsDir, d.id, f, fsImpl)
    if (r.kind === 'text') tones[f] = B.fileTone(f, r.text)
  }
  const p = d.path && files.includes(d.path) ? d.path : files[0] || null
  let doc
  if (p === null) doc = { kind: 'empty' }
  else {
    try {
      doc = readRunFile(runsDir, d.id, p, fsImpl)
    } catch (err) {
      // Unreadable (permissions, I/O): the reason replaces the content.
      doc = { kind: 'error', text: err.message }
    }
  }
  return { ...state, need: null, drawer: { ...d, files, tones, path: p, doc, docScroll: p === d.path ? d.docScroll : 0 } }
}

// ---- markdown (port of index.html markdown()) ------------------------------

const INLINE = /`([^`]+)`|\*\*([^*]+)\*\*|(?<!\*)\*([^*\s][^*]*)\*|\[([^\]]+)\]\(((?:https?:\/\/|\.{0,2}\/|#)[^)\s]*)\)/g

/** **bold**, *em*, `code`, [link](url) as styled cells. */
function inlineCells(s, base) {
  const out = []
  let last = 0
  for (const m of String(s).matchAll(INLINE)) {
    toCells(s.slice(last, m.index), base, out)
    if (m[1] !== undefined) toCells(m[1], { ...base, bg: P.card }, out)
    else if (m[2] !== undefined) out.push(...inlineCells(m[2], { ...base, b: true }))
    else if (m[3] !== undefined) out.push(...inlineCells(m[3], { ...base, i: true }))
    else out.push(...inlineCells(m[4], { ...base, fg: P.active, u: true }))
    last = m.index + m[0].length
  }
  toCells(String(s).slice(last), base, out)
  return out
}

function expandTabs(s) {
  let out = ''
  for (const ch of s) out += ch === '\t' ? ' '.repeat(4 - (out.length % 4)) : ch
  return out
}

/** A <pre>: one padding line above and below, lines cut at the width, filled with the board bg. */
function codeLines(lines, w) {
  const st = { fg: P.text, bg: P.bg }
  const out = [{ cells: [], fill: P.bg }]
  for (const raw of lines) {
    for (const chunk of hardWrap(toCells(expandTabs(raw), st), Math.max(1, w - 2))) out.push({ cells: [cell(' ', 1, st), ...chunk], fill: P.bg })
  }
  out.push({ cells: [], fill: P.bg })
  return out
}

function tableLines(rows, W) {
  const base = { fg: P.text }
  const ln = { fg: P.line }
  const body = rows.filter((r) => !/^\|[\s:|-]+\|$/.test(r))
  if (body.length === 0) return []
  const grid = body.map((r, n) => r.replace(/^\||\|$/g, '').split('|').map((c) => inlineCells(c.trim(), n === 0 ? { ...base, b: true } : base)))
  const n = Math.max(...grid.map((r) => r.length))
  for (const r of grid) while (r.length < n) r.push([])
  const avail = W - (3 * n + 1)
  if (avail < n) {
    // Too narrow for a grid: one wrapped line per row, cells joined by the rule.
    const out = []
    for (const r of grid) {
      const joined = []
      r.forEach((c, j) => {
        if (j > 0) toCells(' │ ', ln, joined)
        joined.push(...c)
      })
      out.push(...wrapCells(joined, W))
    }
    return out
  }
  const w = []
  for (let j = 0; j < n; j++) w.push(Math.max(1, ...grid.map((r) => cellsWidth(r[j]))))
  let total = w.reduce((a, b) => a + b, 0)
  while (total > avail) {
    let j = 0
    for (let k = 1; k < n; k++) if (w[k] > w[j]) j = k
    w[j]--
    total--
  }
  const rule = (l, m, r) => toCells(l + w.map((x) => '─'.repeat(x + 2)).join(m) + r, ln)
  const out = [rule('┌', '┬', '┐')]
  grid.forEach((r, ri) => {
    const wrapped = r.map((c, j) => wrapCells(c, w[j]))
    const h = Math.max(...wrapped.map((x) => x.length))
    for (let k = 0; k < h; k++) {
      const line = toCells('│', ln)
      wrapped.forEach((x, j) => {
        line.push(cell(' ', 1, base), ...padTo(x[k] || [], w[j]), cell(' ', 1, base))
        toCells('│', ln, line)
      })
      out.push(line)
    }
    if (ri === 0 && grid.length > 1) out.push(rule('├', '┼', '┤'))
  })
  out.push(rule('└', '┴', '┘'))
  return out
}

/** Markdown as lines `{ cells, fill }` (fill: a bg the whole line takes, for code). */
function mdLines(src, width) {
  const W = Math.max(1, width)
  const base = { fg: P.text }
  const lines = String(src).replace(/\r/g, '').split('\n')
  const out = []
  let afterHeading = false
  const push = (cells, fill = null) => out.push({ cells, fill })
  const gap = () => {
    if (out.length > 0 && !afterHeading && out[out.length - 1].cells.length > 0) push([])
    afterHeading = false
  }
  let i = 0
  const first = (lines[0] || '').trim()
  const tone = B.lineTone(first)
  if (tone) {
    push(fitCells(toCells(` ${first} `, { fg: TONE[tone], bg: mix(TONE[tone], P.panel, 0.15), b: true }), W))
    i = 1
  }
  const isList = (l) => /^\s*([-*+]|\d+\.)\s+/.test(l)
  const isBlockStart = (l) => /^(#{1,6}\s|```|\s*>|\|)/.test(l) || isList(l)

  while (i < lines.length) {
    const line = lines[i]
    if (!line.trim()) {
      i++
      continue
    }
    if (line.startsWith('```')) {
      const body = []
      i++
      while (i < lines.length && !lines[i].startsWith('```')) body.push(lines[i++])
      i++
      gap()
      for (const l of codeLines(body, W)) out.push(l)
      continue
    }
    const h = line.match(/^(#{1,6})\s+(.*)$/)
    if (h) {
      const n = Math.min(h[1].length, 4)
      gap()
      for (const l of wrapCells(inlineCells(h[2], { fg: n === 3 ? P.muted : P.text, b: true }), W)) push(l)
      afterHeading = true
      i++
      continue
    }
    if (/^\s*>/.test(line)) {
      const body = []
      while (i < lines.length && /^\s*>/.test(lines[i])) body.push(lines[i++].replace(/^\s*>\s?/, ''))
      gap()
      for (const l of wrapCells(inlineCells(body.join(' '), { fg: P.muted }), W - 2)) push([...toCells('│ ', { fg: P.line }), ...l])
      continue
    }
    if (line.startsWith('|')) {
      const rows = []
      while (i < lines.length && lines[i].startsWith('|')) rows.push(lines[i++])
      gap()
      for (const l of tableLines(rows, W)) push(l)
      continue
    }
    if (isList(line)) {
      const ordered = /^\s*\d+\./.test(line)
      const items = []
      while (i < lines.length && (isList(lines[i]) || (/^\s{2,}\S/.test(lines[i]) && items.length))) {
        const l = lines[i++]
        if (isList(l)) items.push({ indent: l.match(/^\s*/)[0].length, text: l.replace(/^\s*([-*+]|\d+\.)\s+/, '') })
        else items[items.length - 1].text += ' ' + l.trim()
      }
      gap()
      items.forEach(({ indent, text }, n) => {
        const task = text.match(/^\[([ xX])\]\s+(.*)$/)
        const lead = toCells(' '.repeat(Math.min(Math.floor(indent / 2), Math.floor(W / 3))), base)
        const marker = task
          ? toCells(task[1] === ' ' ? '☐ ' : '☑ ', { fg: task[1] === ' ' ? P.faint : P.pass })
          : toCells(ordered ? `${n + 1}. ` : '• ', { fg: P.muted })
        const head = [...lead, ...marker]
        const hw = cellsWidth(head)
        wrapCells(inlineCells(task ? task[2] : text, base), W - hw).forEach((l, k) => push(k === 0 ? [...head, ...l] : [...spaces(hw, {}), ...l]))
      })
      continue
    }
    const para = []
    while (i < lines.length && lines[i].trim() && !isBlockStart(lines[i])) para.push(lines[i++])
    // A line no block takes (a heading the `$` of its regex refuses) still moves on.
    if (para.length === 0) para.push(lines[i++])
    gap()
    for (const l of wrapCells(inlineCells(para.join(' '), base), W)) push(l)
  }
  while (out.length > 0 && out[out.length - 1].cells.length === 0 && !out[out.length - 1].fill) out.pop()
  return out.map((l) => ({ cells: clipCells(l.cells, W), fill: l.fill }))
}

/** Markdown as ANSI lines, none wider than `width`: verdict badge, headings, code, quotes, tables, lists. */
function renderMarkdown(text, width) {
  const w = Math.max(1, Math.floor(width) || 1)
  return mdLines(text, w).map((l) => serialize(l.fill ? padTo(l.cells, w, l.fill) : l.cells))
}

// ---- state -----------------------------------------------------------------

/** A fresh board state; `need` asks the IO shell for a read ('poll', 'drawer', 'file'). */
function initialState(o = {}) {
  return {
    repo: o.repo || '',
    width: o.width || 80,
    height: o.height || 24,
    runs: [],
    now: 0,
    status: null,
    problems: [],
    sel: null,
    scroll: [0, 0, 0, 0, 0, 0],
    hscroll: 0,
    drawer: null,
    tick: true,
    quit: false,
    need: null,
  }
}

let memo = { runs: null, now: null, cards: [], groups: null }
/** Cards and columns of the state's runs, from board.js only. */
function derive(state) {
  if (memo.runs !== state.runs || memo.now !== state.now) {
    const cards = state.runs.map((r) => B.deriveRun(r, state.now))
    memo = { runs: state.runs, now: state.now, cards, groups: B.groupRuns(cards) }
  }
  return memo
}

const columnCards = (groups, c) => groups[B.COLUMNS[c].key].cards

/** The selected { col, idx } (idx -1 in an empty column): by card id first, so it follows a moving card. */
function selection(state, groups) {
  if (state.sel) {
    if (state.sel.id) {
      for (let c = 0; c < B.COLUMNS.length; c++) {
        const i = columnCards(groups, c).findIndex((x) => x.id === state.sel.id)
        if (i >= 0) return { col: c, idx: i }
      }
    }
    const col = clamp(state.sel.col, 0, B.COLUMNS.length - 1)
    const n = columnCards(groups, col).length
    return { col, idx: n > 0 ? clamp(state.sel.idx, 0, n - 1) : -1 }
  }
  const col = Math.max(0, B.COLUMNS.findIndex((_, c) => columnCards(groups, c).length > 0))
  return { col, idx: columnCards(groups, col).length > 0 ? 0 : -1 }
}

// ---- board -----------------------------------------------------------------

/** The chips row, flowed onto as many lines as the card needs; a chip wider than the card is cut. */
function chipLines(chips, iw, bg) {
  const look = (state) => {
    if (state === 'info') return { l: '[', r: ']', fg: P.muted, edge: P.line, bg }
    if (state === 'pass') return { l: ' ', r: ' ', fg: P.pass, edge: P.pass, bg: mix(P.pass, bg, 0.14) }
    if (state === 'fail') return { l: '[', r: ']', fg: P.human, edge: P.human, bg }
    if (state === 'used') return { l: ' ', r: ' ', fg: P.changes, edge: P.changes, bg: mix(P.changes, bg, 0.16) }
    return { l: '[', r: ']', fg: P.faint, edge: P.faint, bg }
  }
  const lines = [[]]
  for (const c of chips) {
    const s = look(c.state)
    const label = fitCells(toCells(c.label, { fg: s.fg, bg: s.bg }), Math.max(1, iw - 2))
    const chip = [cell(s.l, 1, { fg: s.edge, bg: s.bg }), ...label, cell(s.r, 1, { fg: s.edge, bg: s.bg })]
    const line = lines[lines.length - 1]
    const used = cellsWidth(line)
    if (used > 0 && used + 1 + cellsWidth(chip) > iw) lines.push(chip)
    else line.push(...(used > 0 ? [cell(' ', 1, { bg })] : []), ...chip)
  }
  return lines
}

/** A card as rows of exactly `cw` cells: rounded box, top row, title, branch, chips, À-toi reasons. */
function cardRows(card, cw, selected, tick) {
  const human = card.column === 'human'
  const bg = selected ? P.cardHover : P.card
  const border = selected ? P.active : human ? P.human : card.live ? mix(P.active, P.line, 0.35) : P.line
  const iw = Math.max(1, cw - 4)
  const st = (fg, more) => ({ fg, bg, ...more })
  const body = []

  const top = []
  if (card.live) toCells('● ', st(tick ? P.active : P.faint), top)
  const flag = card.flag ? toCells(card.flag.toUpperCase(), st(human ? P.human : P.muted, { b: true })) : []
  const flagW = cellsWidth(flag)
  top.push(...fitCells(toCells(card.id, st(P.muted)), iw - cellsWidth(top) - (flagW > 0 ? flagW + 1 : 0)))
  body.push(flagW > 0 ? [...top, ...spaces(iw - cellsWidth(top) - flagW, { bg }), ...flag] : top)
  body.push(...wrapText(card.title, iw, 3, st(P.text)))
  if (card.branch) body.push(fitCells(toCells(card.branch, st(P.faint)), iw))
  body.push(...chipLines(card.chips, iw, bg))
  if (human) {
    body.push(toCells('─'.repeat(iw), st(P.line)))
    for (const r of card.reasons) body.push(...wrapText(r, iw, 3, st(P.human)))
    for (const h of card.hints) body.push(...wrapText(h, iw, 3, st(P.muted)))
  }

  const edge = { fg: border, bg: P.bg }
  const rows = [padTo(toCells(`╭${'─'.repeat(Math.max(0, cw - 2))}╮`, edge), cw, P.bg)]
  for (const line of body) rows.push(padTo([cell('│', 1, edge), cell(' ', 1, { bg }), ...padTo(line, iw, bg), cell(' ', 1, { bg }), cell('│', 1, edge)], cw, P.bg))
  rows.push(padTo(toCells(`╰${'─'.repeat(Math.max(0, cw - 2))}╯`, edge), cw, P.bg))
  // Terminé is the page's `.card.merged { opacity: .72 }`.
  return card.column === 'done' ? rows.map((r) => r.map((c) => fadeCell(c, P.bg, 0.72))) : rows
}

function drawHeader(g, state, W, y) {
  const title = toCells(`APEX board${state.repo ? ` · ${state.repo}` : ''}`, { fg: P.text, b: true })
  const st = state.status
  const status = st === null || st === undefined
    ? toCells('lecture…', { fg: P.muted })
    : st.ok
      ? [...toCells('● ', { fg: P.pass }), ...toCells(`runs/ · ${st.count} · ${st.time}`, { fg: P.muted })]
      : [...toCells('● ', { fg: P.human }), ...toCells(st.error, { fg: P.human })]
  const room = W - 2 * MARGIN
  const sw = Math.min(cellsWidth(status), Math.max(0, room - Math.min(cellsWidth(title), 12) - 2))
  put(g, MARGIN, y, fitCells(title, room - (sw > 0 ? sw + 2 : 0)))
  if (sw > 0) {
    const sc = fitCells(status, sw)
    put(g, W - MARGIN - cellsWidth(sc), y, sc)
  }
}

/**
 * The whole screen for `state` at width × height: { lines (exactly `height` ANSI strings of
 * `width` columns), hits (rects → { type: 'card' | 'col' | 'file' | 'close' | 'scrim' | 'doc' |
 * 'drawer' }, last drawn on top), view (scrolls as drawn, doc length) }.
 */
function renderBoard(state, width, height) {
  const W = Math.max(1, Math.floor(Number(width)) || 1)
  const H = Math.max(1, Math.floor(Number(height)) || 1)
  const g = makeGrid(W, H, P.bg)
  const hits = []
  const { cards, groups } = derive(state)
  const sel = selection(state, groups)
  const view = { scroll: (state.scroll || [0, 0, 0, 0, 0, 0]).slice(), first: 0, sel, docLines: 0, bodyH: 0, docScroll: 0, fileScroll: 0 }

  const tall = H >= 16
  let y = tall ? 1 : 0
  drawHeader(g, state, W, y)
  y++
  const problems = state.problems || []
  const banner = problems.slice(0, 3).concat(problems.length > 3 ? [`+${problems.length - 3}`] : [])
  for (const p of banner) put(g, MARGIN, y++, fitCells(toCells(p, { fg: P.human }), W - 2 * MARGIN))
  y++
  const headY = y
  const cardsTop = headY + 2
  const footerTop = tall ? H - 2 : H - 1
  const areaH = Math.max(0, footerTop - (tall ? 1 : 0) - cardsTop)

  const n = B.COLUMNS.length
  const inner = Math.max(1, W - 2 * MARGIN)
  const nVis = clamp(Math.floor((inner + GAP) / (MIN_COL + GAP)), 1, n)
  // Equal columns; the columns left over go one each to the first ones, so the board fills the width.
  const span = inner - GAP * (nVis - 1)
  const base = Math.max(1, Math.floor(span / nVis))
  const extra = Math.max(0, span - base * nVis)
  const first = clamp(clamp(state.hscroll || 0, sel.col - nVis + 1, sel.col), 0, n - nVis)
  view.first = first

  for (let v = 0; v < nVis; v++) {
    const c = first + v
    const col = B.COLUMNS[c]
    const cw = base + (v < extra ? 1 : 0)
    const x = MARGIN + v * (base + GAP) + Math.min(v, extra)
    const grp = groups[col.key]
    const items = []
    let top = 0
    grp.cards.forEach((card, i) => {
      const rows = cardRows(card, cw, c === sel.col && i === sel.idx, state.tick !== false)
      items.push({ card, rows, top, i })
      top += rows.length
    })
    const total = top + (grp.more > 0 || grp.cards.length === 0 ? 1 : 0)
    let s = view.scroll[c] || 0
    const picked = c === sel.col && sel.idx >= 0 ? items[sel.idx] : undefined
    if (picked) {
      if (picked.top + picked.rows.length > s + areaH) s = picked.top + picked.rows.length - areaH
      if (picked.top < s) s = picked.top
    }
    s = clamp(s, 0, Math.max(0, total - areaH))
    view.scroll[c] = s

    // Column head: label, who, count; the line under it; `›` between work columns.
    const count = grp.cards.length + grp.more
    const countCells = count > 0 ? toCells(String(count), { fg: P.muted }) : []
    const hx = put(g, x, headY, toCells(col.label, { fg: col.key === 'human' ? P.human : col.key === 'done' ? P.merged : P.text, b: true }), x + cw)
    const whoMax = x + cw - (countCells.length > 0 ? cellsWidth(countCells) + 1 : 0) - (hx + 1)
    if (whoMax > 0) put(g, hx + 1, headY, fitCells(toCells(col.who, { fg: P.faint }), whoMax))
    if (count > 0) put(g, x + cw - cellsWidth(countCells), headY, countCells, x + cw)
    put(g, x, headY + 1, toCells('─'.repeat(cw), { fg: col.key === 'human' ? mix(P.human, P.bg, 0.55) : P.line }))
    if (s > 0 && cw >= 2) put(g, x + cw - 2, headY + 1, toCells('↑', { fg: P.muted }))
    if (s + areaH < total) put(g, x + cw - 1, headY + 1, toCells('↓', { fg: P.muted }))
    if (c < 4 && v < nVis - 1) put(g, x + cw + 1, headY, toCells('›', { fg: P.faint }))
    hits.push({ x, y: headY, w: cw, h: Math.max(1, cardsTop + areaH - headY), hit: { type: 'col', col: c } })

    for (const it of items) {
      let firstRow = -1
      let shown = 0
      it.rows.forEach((row, r) => {
        const at = it.top + r - s
        if (at < 0 || at >= areaH) return
        put(g, x, cardsTop + at, row, x + cw)
        if (firstRow < 0) firstRow = cardsTop + at
        shown++
      })
      if (shown > 0) hits.push({ x, y: firstRow, w: cw, h: shown, hit: { type: 'card', id: it.card.id, col: c, idx: it.i } })
    }
    const tail = grp.cards.length === 0 ? '—' : grp.more > 0 ? `+${grp.more}` : null
    const tailAt = top - s
    if (tail !== null && tailAt >= 0 && tailAt < areaH) put(g, x + 1, cardsTop + tailAt, toCells(tail, { fg: P.faint }), x + cw)
  }
  if (first > 0) put(g, 0, headY, toCells('‹', { fg: P.muted }))
  if (first + nVis < n) put(g, W - 1, headY, toCells('›', { fg: P.muted }))

  if (tall) put(g, MARGIN, H - 2, fitCells(toCells(FOOTER.join('   '), { fg: P.muted }), W - 2 * MARGIN))
  const keys = toCells(KEYS_BOARD, { fg: P.faint })
  const where = nVis < n ? toCells(`colonnes ${first + 1}-${first + nVis}/${n}`, { fg: P.faint }) : []
  const kw = W - 2 * MARGIN - (where.length > 0 ? cellsWidth(where) + 2 : 0)
  put(g, MARGIN, H - 1, fitCells(keys, kw > 8 ? kw : W - 2 * MARGIN))
  if (where.length > 0 && kw > 8) put(g, W - MARGIN - cellsWidth(where), H - 1, where)

  if (state.drawer) drawDrawer(g, hits, state, cards, W, H, view)
  return { lines: g.map(serialize), hits, view }
}

// ---- drawer ----------------------------------------------------------------

function fileItems(d) {
  const items = []
  let group = null
  for (const f of d.files || []) {
    const name = f.includes('/') ? f.split('/').slice(0, -1).join('/') : 'Run'
    if (name !== group) {
      items.push({ group: name })
      group = name
    }
    items.push({ path: f })
  }
  return items
}

const note = (text, w, fg = P.faint) => wrapCells(toCells(text, { fg }), w).map((cells) => ({ cells, fill: null }))

let docMemo = null
/** The doc pane's lines: markdown for .md, code style otherwise, a note while nothing is readable. */
function docLines(d, w) {
  const doc = d.doc
  if (d.files === null || doc === null || doc === undefined) return note('chargement…', w)
  if (doc.kind === 'empty') return note('Ce run n’a encore rien écrit.', w)
  if (doc.kind === 'outside') return [...note(OUTSIDE, w, P.human), ...note(`${d.path} pointe hors de .claude/output/apex : non lu.`, w)]
  if (doc.kind === 'missing') return note('Fichier disparu depuis la liste.', w)
  if (doc.kind === 'binary') return note('Fichier binaire : non affiché.', w)
  if (doc.kind !== 'text') return note(doc.text || 'illisible', w, P.human)
  if (docMemo && docMemo.text === doc.text && docMemo.path === d.path && docMemo.w === w) return docMemo.lines
  const lines = /\.md$/.test(d.path) ? mdLines(doc.text, w) : codeLines(doc.text.replace(/\n$/, '').split('\n'), w)
  docMemo = { text: doc.text, path: d.path, w, lines }
  return lines
}

function drawDrawer(g, hits, state, cards, W, H, view) {
  const d = state.drawer
  const dw = Math.min(DRAWER_W, W)
  const x0 = W - dw
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < x0; x++) g[y][x] = fadeCell(g[y][x], SCRIM, 0.45)
    fillRow(g, y, x0, W, P.panel)
  }
  if (x0 > 0) hits.push({ x: 0, y: 0, w: x0, h: H, hit: { type: 'scrim' } })
  hits.push({ x: x0, y: 0, w: dw, h: H, hit: { type: 'drawer' } })
  let cx = x0
  if (x0 > 0) {
    for (let y = 0; y < H; y++) put(g, x0, y, toCells('│', { fg: P.line }))
    cx = x0 + 1
  }
  const pad = dw >= 40 ? 2 : 1
  const left = cx + pad
  const right = W - pad
  const card = cards.find((c) => c.id === d.id) || null

  // Head: id · column · step · actif, title, branch, À-toi reasons and hints, × to close.
  let y = H >= 16 ? 1 : 0
  const closeX = right - 1
  put(g, closeX, y, toCells('×', { fg: P.muted, b: true }))
  hits.push({ x: closeX - 1, y: Math.max(0, y - 1), w: 3, h: 3, hit: { type: 'close' } })
  const headW = Math.max(1, closeX - 2 - left)
  const num = card ? [card.id, LABEL[card.column], card.current, card.live ? 'actif' : 'inactif'].filter(Boolean).join(' · ') : d.id
  put(g, left, y++, fitCells(toCells(num, { fg: P.muted }), headW))
  if (card) {
    for (const l of wrapText(card.title, headW, 2, { fg: P.text, b: true })) put(g, left, y++, l)
    if (card.branch) put(g, left, y++, fitCells(toCells(card.branch, { fg: P.faint }), headW))
    if (card.column === 'human') {
      for (const r of card.reasons) for (const l of wrapText(r, headW, 2, { fg: P.human })) put(g, left, y++, l)
      for (const h of card.hints) for (const l of wrapText(h, headW, 2, { fg: P.muted })) put(g, left, y++, l)
    }
  }
  y++
  put(g, cx, y, toCells('─'.repeat(Math.max(0, W - cx)), { fg: P.line }))
  const bodyTop = y + 1
  const keysY = H - 1
  const bodyH = Math.max(0, keysY - bodyTop)

  // Files: grouped Run / subdir, verdict dot, the selected one highlighted.
  const fw = clamp(Math.floor(dw * 0.3), Math.min(12, dw), 26)
  const fx = cx
  const items = fileItems(d)
  const selRow = items.findIndex((it) => it.path === d.path)
  let fsc = d.fileScroll || 0
  if (selRow >= 0) {
    if (selRow >= fsc + bodyH) fsc = selRow - bodyH + 1
    if (selRow < fsc) fsc = selRow
  }
  fsc = clamp(fsc, 0, Math.max(0, items.length - bodyH))
  view.fileScroll = fsc
  for (let r = 0; r < bodyH; r++) {
    const it = items[fsc + r]
    const yy = bodyTop + r
    if (!it) break
    if (it.group !== undefined) {
      put(g, fx + 1, yy, fitCells(toCells(it.group.toUpperCase(), { fg: P.faint }), fw - 2))
      continue
    }
    const on = it.path === d.path
    const bg = on ? (d.focus === 'files' ? P.cardHover : P.card) : undefined
    if (on) fillRow(g, yy, fx, fx + fw, bg)
    put(g, fx + 1, yy, toCells('●', { fg: TONE[(d.tones || {})[it.path]] || P.faint, bg }))
    put(g, fx + 3, yy, fitCells(toCells(it.path.split('/').pop(), { fg: on ? P.text : P.muted, bg }), fw - 4), fx + fw)
    hits.push({ x: fx, y: yy, w: fw, h: 1, hit: { type: 'file', path: it.path } })
  }
  if (d.files && d.files.length === 0 && bodyH > 0) put(g, fx + 1, bodyTop, fitCells(toCells('Aucun fichier.', { fg: P.faint }), fw - 2))
  for (let r = 0; r < bodyH; r++) put(g, fx + fw, bodyTop + r, toCells('│', { fg: P.line }))

  // Document.
  const dx = fx + fw + 1 + pad
  const docW = right - dx
  let tail = []
  if (docW >= 1 && bodyH > 0) {
    const lines = docLines(d, docW)
    const ds = clamp(d.docScroll || 0, 0, Math.max(0, lines.length - bodyH))
    view.docLines = lines.length
    view.bodyH = bodyH
    view.docScroll = ds
    for (let r = 0; r < bodyH; r++) {
      const l = lines[ds + r]
      if (!l) break
      if (l.fill) fillRow(g, bodyTop + r, dx, right, l.fill)
      put(g, dx, bodyTop + r, l.cells, right)
    }
    hits.push({ x: fx + fw + 1, y: bodyTop, w: W - (fx + fw + 1), h: bodyH, hit: { type: 'doc' } })
    if (lines.length > bodyH) tail = toCells(`${ds + 1}-${Math.min(ds + bodyH, lines.length)}/${lines.length}`, { fg: P.faint })
  }
  const keys = toCells(`${d.focus === 'doc' ? '↑↓ défiler · ⇥ fichiers' : '↑↓ fichier · ⇥ document'} · pgup/pgdn page · esc fermer`, { fg: P.faint })
  const kw = right - left - (tail.length > 0 ? cellsWidth(tail) + 2 : 0)
  put(g, left, keysY, fitCells(keys, kw))
  if (tail.length > 0 && kw > 0) put(g, right - cellsWidth(tail), keysY, tail)
}

// ---- input -----------------------------------------------------------------

const SEQ = {
  '[A': 'up', '[B': 'down', '[C': 'right', '[D': 'left', OA: 'up', OB: 'down', OC: 'right', OD: 'left',
  '[H': 'home', '[F': 'end', OH: 'home', OF: 'end', '[1~': 'home', '[4~': 'end', '[7~': 'home', '[8~': 'end',
  '[5~': 'pgup', '[6~': 'pgdn', '[Z': 'tab',
}

/** Raw stdin text as events: key names, printable chars, mouse { type, x, y, button, wheel } (0-based). */
function parseInput(s) {
  const out = []
  let i = 0
  while (i < s.length) {
    const code = s.charCodeAt(i)
    if (code === 27) {
      const rest = s.slice(i + 1)
      const mouse = /^\[<(\d+);(\d+);(\d+)([Mm])/.exec(rest)
      if (mouse) {
        const b = Number(mouse[1])
        const press = mouse[4] === 'M' && (b & 32) === 0
        const wheel = b & 64 ? (b & 1 ? 1 : -1) : 0
        const button = !(b & 64) && (b & 3) === 0 ? 'left' : null
        if (press && (wheel !== 0 || button !== null)) out.push({ type: 'mouse', x: Number(mouse[2]) - 1, y: Number(mouse[3]) - 1, button, wheel })
        i += 1 + mouse[0].length
        continue
      }
      const seq = /^(\[[0-9;]*[A-Za-z~]|O[A-Za-z])/.exec(rest)
      if (seq) {
        if (SEQ[seq[1]]) out.push(SEQ[seq[1]])
        i += 1 + seq[0].length
        continue
      }
      out.push('esc')
      i++
      continue
    }
    if (code === 13 || code === 10) out.push('enter')
    else if (code === 9) out.push('tab')
    else if (code === 3) out.push('ctrl-c')
    else if (code === 32) out.push('space')
    else if (code > 32 && code !== 127) out.push(s[i])
    i++
  }
  return out
}

// ---- reduce ----------------------------------------------------------------

const hitAt = (hits, x, y) => {
  for (let k = hits.length - 1; k >= 0; k--) {
    const h = hits[k]
    if (x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h) return h.hit
  }
  return null
}

/** The state with its scrolls as the screen would draw them, so they persist. */
function settle(state) {
  const { view } = renderBoard(state, state.width, state.height)
  const next = { ...state, scroll: view.scroll, hscroll: view.first }
  if (state.drawer) next.drawer = { ...state.drawer, fileScroll: view.fileScroll }
  return next
}

function openDrawer(state, sel, id) {
  return settle({
    ...state,
    sel: { col: sel.col, idx: sel.idx, id },
    drawer: { id, files: null, tones: {}, path: null, doc: null, focus: 'files', docScroll: 0, fileScroll: 0 },
    need: 'drawer',
  })
}

function reduceBoard(state, ev) {
  const { groups } = derive(state)
  const sel = selection(state, groups)
  const pick = (c, i) => {
    const list = columnCards(groups, c)
    const idx = list.length > 0 ? clamp(i, 0, list.length - 1) : -1
    return settle({ ...state, sel: { col: c, idx: Math.max(idx, 0), id: idx >= 0 ? list[idx].id : null } })
  }
  const row = Math.max(sel.idx, 0)
  if (typeof ev === 'object' && ev !== null) {
    const h = hitAt(renderBoard(state, state.width, state.height).hits, ev.x, ev.y)
    if (!h) return state
    if (ev.button === 'left' && h.type === 'card') return openDrawer(state, { col: h.col, idx: h.idx }, h.id)
    if (ev.wheel !== 0 && (h.type === 'card' || h.type === 'col')) {
      return pick(h.col, h.col === sel.col ? sel.idx + ev.wheel : h.type === 'card' ? h.idx : 0)
    }
    return state
  }
  switch (ev) {
    case 'q':
      return { ...state, quit: true }
    case 'left':
    case 'h':
      return pick(Math.max(0, sel.col - 1), row)
    case 'right':
    case 'l':
      return pick(Math.min(B.COLUMNS.length - 1, sel.col + 1), row)
    case 'up':
    case 'k':
      return pick(sel.col, sel.idx - 1)
    case 'down':
    case 'j':
      return pick(sel.col, sel.idx + 1)
    case 'home':
    case 'g':
      return pick(sel.col, 0)
    case 'end':
    case 'G':
      return pick(sel.col, Infinity)
    case 'pgup':
      return pick(sel.col, sel.idx - PAGE_CARDS)
    case 'pgdn':
    case 'space':
      return pick(sel.col, sel.idx + PAGE_CARDS)
    case 'enter':
      return sel.idx >= 0 ? openDrawer(state, sel, columnCards(groups, sel.col)[sel.idx].id) : state
    case 'r':
      return { ...state, need: 'poll' }
    default:
      return state
  }
}

function reduceDrawer(state, ev) {
  const d = state.drawer
  const files = d.files || []
  const at = files.indexOf(d.path)
  const close = () => ({ ...state, drawer: null })
  const focus = (f) => ({ ...state, drawer: { ...d, focus: f } })
  const fileAt = (i) => {
    if (files.length === 0) return state
    const p = files[clamp(i, 0, files.length - 1)]
    if (p === d.path) return focus('files')
    return settle({ ...state, drawer: { ...d, path: p, doc: null, docScroll: 0, focus: 'files' }, need: 'file' })
  }
  const view = () => renderBoard(state, state.width, state.height).view
  const scrollBy = (n) => {
    const v = view()
    return { ...state, drawer: { ...d, docScroll: clamp(v.docScroll + n, 0, Math.max(0, v.docLines - v.bodyH)) } }
  }
  const page = () => Math.max(1, view().bodyH - 2)
  if (typeof ev === 'object' && ev !== null) {
    const h = hitAt(renderBoard(state, state.width, state.height).hits, ev.x, ev.y)
    if (!h) return state
    if (ev.button === 'left') {
      if (h.type === 'close' || h.type === 'scrim') return close()
      if (h.type === 'file') return fileAt(files.indexOf(h.path))
      return state
    }
    return ev.wheel !== 0 && h.type !== 'scrim' ? scrollBy(ev.wheel * 3) : state
  }
  switch (ev) {
    case 'esc':
    case 'q':
      return close()
    case 'tab':
      return focus(d.focus === 'files' ? 'doc' : 'files')
    case 'left':
    case 'h':
      return focus('files')
    case 'right':
    case 'l':
    case 'enter':
      return focus('doc')
    case 'up':
    case 'k':
      return d.focus === 'doc' ? scrollBy(-1) : fileAt(at - 1)
    case 'down':
    case 'j':
      return d.focus === 'doc' ? scrollBy(1) : fileAt(at + 1)
    case 'pgup':
      return scrollBy(-page())
    case 'pgdn':
    case 'space':
      return scrollBy(page())
    case 'home':
    case 'g':
      return d.focus === 'doc' ? scrollBy(-Infinity) : fileAt(0)
    case 'end':
    case 'G':
      return d.focus === 'doc' ? scrollBy(Infinity) : fileAt(files.length - 1)
    case 'r':
      return { ...state, need: 'poll' }
    default:
      return state
  }
}

/** The next state for one event; IO it needs is asked through `need`, never done here. */
function reduce(state, ev) {
  if (ev === 'ctrl-c') return { ...state, quit: true }
  return state.drawer ? reduceDrawer(state, ev) : reduceBoard(state, ev)
}

// ---- IO shell --------------------------------------------------------------

/** An idempotent terminal restore: raw mode off, then LEAVE. */
function makeRestore(write, setRaw) {
  let done = false
  return () => {
    if (done) return
    done = true
    try {
      setRaw(false)
    } catch {
      // stdin is already gone (terminal closed): no mode left to reset there; LEAVE still goes out.
    }
    write(LEAVE)
  }
}

const clock = (t) => [t.getHours(), t.getMinutes(), t.getSeconds()].map((v) => String(v).padStart(2, '0')).join(':')

function main(args) {
  const [runsDir, budgetDir = '', repo = ''] = args
  if (!runsDir) {
    process.stderr.write('usage: tui.js <runs-dir> [budget-dir] [repo-name]\n')
    process.exitCode = 2
    return
  }
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    process.stderr.write('apex-board --tui: needs a terminal on stdin and stdout\n')
    process.exitCode = 1
    return
  }
  const out = process.stdout
  const restore = makeRestore((s) => fs.writeSync(out.fd, s), (on) => process.stdin.setRawMode(on))
  const quit = (code) => {
    restore()
    process.exit(code)
  }
  const crash = (err) => {
    restore()
    process.stderr.write(`apex-board --tui: ${err && err.stack ? err.stack : String(err)}\n`)
    process.exit(1)
  }
  process.on('exit', restore)
  process.on('SIGINT', () => quit(130))
  process.on('SIGTERM', () => quit(143))
  process.on('SIGHUP', () => quit(129))
  process.on('uncaughtException', crash)
  process.on('unhandledRejection', crash)

  let state = initialState({ repo, width: out.columns, height: out.rows })
  let last = ''
  const draw = () => {
    const { lines } = renderBoard(state, state.width, state.height)
    let frame = SYNC_ON
    lines.forEach((l, y) => {
      frame += `\x1b[${y + 1};1H${l}`
    })
    frame += SYNC_OFF
    if (frame === last) return
    last = frame
    out.write(frame)
  }
  const poll = (s) => {
    const problems = []
    let runs
    try {
      runs = readRuns(runsDir, budgetDir, fs, problems)
    } catch (err) {
      // The runs dir itself is unreadable: keep the last board and say why, as the page's status does.
      return { ...s, status: { ok: false, error: err.message } }
    }
    let next = { ...s, runs, now: Date.now(), problems, status: { ok: true, count: runs.length, time: clock(new Date()) } }
    if (next.drawer) {
      const open = derive(next).cards.find((c) => c.id === next.drawer.id)
      if (open && open.live) next = loadDrawer(next, runsDir)
    }
    return next
  }
  const effects = (s) => (s.need === 'poll' ? poll({ ...s, need: null }) : s.need ? loadDrawer(s, runsDir) : s)

  out.write(ENTER)
  process.stdin.setRawMode(true)
  process.stdin.setEncoding('utf8')
  process.stdin.on('data', (chunk) => {
    for (const ev of parseInput(chunk)) {
      state = reduce(state, ev)
      if (state.quit) return quit(0)
      state = effects(state)
    }
    draw()
  })
  process.stdin.resume()
  out.on('resize', () => {
    state = settle({ ...state, width: out.columns, height: out.rows })
    last = ''
    out.write('\x1b[2J')
    draw()
  })
  state = poll(state)
  draw()
  setInterval(() => {
    state = poll(state)
    draw()
  }, POLL_MS)
  setInterval(() => {
    state = { ...state, tick: !state.tick }
    draw()
  }, TICK_MS)
}

if (require.main === module) main(process.argv.slice(2))
else {
  module.exports = {
    POLL_MS,
    OUTSIDE,
    ENTER,
    LEAVE,
    PALETTE: P,
    board: B,
    readRuns,
    listRunFiles,
    readRunFile,
    loadDrawer,
    renderBoard,
    renderMarkdown,
    reduce,
    parseInput,
    initialState,
    makeRestore,
    stripAnsi,
    visibleWidth,
  }
}
