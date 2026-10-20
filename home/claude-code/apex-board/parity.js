'use strict'
// apex-board parity: what board.js derives from a runs dir, as the JSON the Go TUI writes with
// `--derive-json`. The check compares both byte for byte, so the Go port of board.js
// (tui/rules.go) cannot drift from the page's rules. Not shipped; the disk reading below is
// tui.js's (realpath under the runs dir, links never followed out, 512 KB cap, 2000 files).
//
//   node parity.js <runs-dir> <budget-dir> <now-ms>

const fs = require('fs')
const path = require('path')
const B = require('./board.js')

const MAX_BYTES = 512 * 1024
const MAX_FILES = 2000
const MAX_DEPTH = 8
const OUTSIDE = '« hors du run »'

function realInside(root, p) {
  let real
  try {
    real = fs.realpathSync(p)
  } catch (err) {
    // Gone, or a dangling link: nothing to read, which is not an error.
    if (err.code === 'ENOENT' || err.code === 'ENOTDIR') return null
    throw err
  }
  const base = fs.realpathSync(root)
  return real === base || real.startsWith(base + path.sep) ? real : false
}

function readCapped(file) {
  const st = fs.statSync(file)
  if (!st.isFile()) return { kind: 'error', text: 'pas un fichier ordinaire : non lu' }
  const len = Math.min(st.size, MAX_BYTES)
  const buf = Buffer.alloc(len)
  const fd = fs.openSync(file, 'r')
  let off = 0
  try {
    while (off < len) {
      const n = fs.readSync(fd, buf, off, len - off, off)
      if (n === 0) break
      off += n
    }
  } finally {
    fs.closeSync(fd)
  }
  const data = buf.subarray(0, off)
  if (data.includes(0)) return { kind: 'binary', mtimeMs: st.mtimeMs }
  let text = data.toString('utf8')
  if (st.size > MAX_BYTES) text += `\n\n… tronqué : ${Math.round(st.size / 1024)} Ko, ${MAX_BYTES / 1024} Ko affichés\n`
  return { kind: 'text', text, mtimeMs: st.mtimeMs }
}

const safeId = (id) => typeof id === 'string' && id !== '' && id !== '.' && id !== '..' && !id.includes('/') && !id.includes(path.sep)

function readRunFile(runsDir, id, rel) {
  const parts = String(rel).split('/')
  if (!safeId(id) || path.isAbsolute(rel) || parts.some((p) => p === '' || p === '.' || p === '..')) return { kind: 'outside', text: OUTSIDE }
  const real = realInside(runsDir, path.join(runsDir, id, ...parts))
  if (real === null) return { kind: 'missing' }
  if (real === false) return { kind: 'outside', text: OUTSIDE }
  return readCapped(real)
}

const byName = (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)

function listRunFiles(runDir) {
  const out = []
  const walk = (dir, prefix, depth) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true }).sort(byName)) {
      if (out.length >= MAX_FILES) return
      if (e.isDirectory()) {
        if (depth < MAX_DEPTH) walk(path.join(dir, e.name), `${prefix}${e.name}/`, depth + 1)
      } else out.push(prefix + e.name)
    }
  }
  walk(runDir, '', 0)
  return out
}

function readRun(runsDir, id, budget) {
  const dir = path.join(runsDir, id)
  const files = fs.readdirSync(dir, { withFileTypes: true }).filter((e) => !e.isDirectory()).map((e) => e.name).sort()
  const text = (name) => {
    const real = realInside(runsDir, path.join(dir, name))
    if (typeof real !== 'string') return null
    const r = readCapped(real)
    return r.kind === 'text' ? r : null
  }
  const ctx = files.includes('00-context.md') ? text('00-context.md') : null
  const vf = B.verdictFile(files)
  const verdict = vf ? text(vf) : null
  return { id, context: ctx ? ctx.text : null, mtimeMs: ctx ? ctx.mtimeMs : null, files, budget, verdict: verdict ? verdict.text : null }
}

function readRuns(runsDir, budgetDir, problems) {
  const ids = fs.readdirSync(runsDir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name).sort()
  let budget = new Map()
  if (budgetDir) {
    try {
      budget = B.parseBudget(fs.readdirSync(budgetDir))
    } catch (err) {
      // No budget dir yet means no round used; anything else is a problem.
      if (err.code !== 'ENOENT') problems.push(`budget/ illisible : ${err.message}`)
    }
  }
  const runs = []
  for (const id of ids) {
    try {
      runs.push(readRun(runsDir, id, budget.get(id)))
    } catch (err) {
      // A run removed between the listing and its read is gone; anything else is a problem.
      if (err.code !== 'ENOENT' && err.code !== 'ENOTDIR') problems.push(`${id} : ${err.message}`)
    }
  }
  return runs
}

const card = (c) => ({
  id: c.id,
  title: c.title,
  tier: c.tier,
  branch: c.branch,
  mtimeMs: c.mtimeMs,
  live: c.live,
  column: c.column,
  current: c.current,
  finished: c.finished,
  flag: c.flag,
  reasons: c.reasons,
  hints: c.hints,
  chips: c.chips.map((x) => ({ key: x.key, label: x.label, state: x.state, title: x.title })),
})

const lineTones = (text) =>
  text
    .split('\n')
    .map((l, i) => [i, B.lineTone(l)])
    .filter(([, t]) => t !== null)
    .map(([i, t]) => `${i}:${t}`)
    .join(';')

function runFiles(runsDir, id) {
  let files
  try {
    files = listRunFiles(path.join(runsDir, id))
  } catch {
    // Unlistable run: the Go side reports it the same way.
    return { id, listed: false, files: [] }
  }
  return {
    id,
    listed: true,
    files: B.sortFiles(files).map((f) => {
      let r
      try {
        r = readRunFile(runsDir, id, f)
      } catch {
        // Unreadable (permissions, I/O): kind error, no tone.
        return { name: f, kind: 'error', tone: null, lines: '' }
      }
      const text = r.kind === 'text'
      return { name: f, kind: r.kind, tone: text && /\.(md|json)$/.test(f) ? B.fileTone(f, r.text) : null, lines: text ? lineTones(r.text) : '' }
    }),
  }
}

function main(args) {
  if (args.length !== 3) {
    process.stderr.write('usage: node parity.js <runs-dir> <budget-dir> <now-ms>\n')
    return 2
  }
  const [runsDir, budgetDir, nowArg] = args
  const now = Number(nowArg)
  const problems = []
  const runs = readRuns(runsDir, budgetDir, problems)
  const groups = B.groupRuns(runs.map((r) => B.deriveRun(r, now)))
  const root = {
    now,
    problems: problems.length,
    columns: B.COLUMNS.map((c) => ({ key: c.key, label: c.label, more: groups[c.key].more, cards: groups[c.key].cards.map(card) })),
    runs: runs.map((r) => runFiles(runsDir, r.id)),
  }
  process.stdout.write(JSON.stringify(root, null, 1) + '\n')
  return 0
}

process.exitCode = main(process.argv.slice(2))
