'use strict'
// APEX board, pure part: read a run's 00-context.md (every drifted spelling tolerated, as the deck
// does in mods/deck/hooks/apex.ts), its directory listing, its correction budget and its external
// verdict, and derive the column its card sits in. No DOM, no fetch, no clock: `now` comes in.
// Loaded by index.html (global `ApexBoard`) and by test.js (module.exports).

;(function () {
  /** A run is live only while its 00-context.md moved in the last 6 hours. */
  const STALE_MS = 6 * 60 * 60 * 1000
  /** Correction rounds a run gets before the user must grant more (correction-budget.js). */
  const MAX_ROUNDS = 2
  /** Cards the Terminé column shows before `+N`. */
  const DONE_CAP = 30

  // The 6 columns, in board order; `cls` is the reference's column style.
  const COLUMNS = [
    { key: 'init', label: 'Init', who: 'coordinateur' },
    { key: 'plan', label: 'Plan', who: '01-analyze · 02-plan' },
    { key: 'execute', label: 'Execute', who: 'implémenteur' },
    { key: 'validate', label: 'Validate', who: '04 → 08' },
    { key: 'done', label: 'Terminé', who: '09 · PR · inactif', cls: 'merged-col' },
    { key: 'human', label: 'À toi', who: 'décision', cls: 'human' },
  ]

  const HINT_GRANT = 'apex: +1 tour'
  const HINT_SESSION = 'répondre dans la session · /deck'
  const HINT_EXT = 'relire external-verify.json · corriger dans la session'

  // ---- 00-context.md ------------------------------------------------------

  const clean = (value) => String(value).replace(/\*\*/g, '').replace(/`/g, '').trim()

  function statusKind(status) {
    const s = clean(status).toLowerCase()
    if (/^(complete|done|✅)/.test(s)) return 'done'
    if (/^pending/.test(s)) return 'pending'
    if (/^(in[ _]progress|en cours|running)/.test(s)) return 'running'
    if (/^(skipped|supprimé|n\/a)/.test(s)) return 'skipped'
    if (/^(red|failed|échoué)(?![a-z])/.test(s)) return 'failed'
    if (/^(blocked|bloqué)(?![a-z])/.test(s)) return 'blocked'
    return 'other'
  }

  // "Key: value", "**Key:** value", "**Key**: value", "- Key: value".
  const FIELD = /^\s*(?:[-*]\s+)?\**\s*([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ ]*?)\s*\**\s*:\s*(.*)$/

  /** A header value's head: `High-stakes (sandbox keys) — files…` → `High-stakes`. */
  function headOf(value) {
    return value.split(/\s+—\s+|\s+→\s+|\s*\(|;|\.\s/)[0].trim()
  }

  function readSteps(lines) {
    const start = lines.findIndex((l) => /^##\s+progress\b/i.test(l))
    if (start < 0) return null
    const steps = []
    for (const line of lines.slice(start + 1)) {
      if (/^##\s/.test(line)) break
      if (!line.trim().startsWith('|')) continue
      if (/^[\s|:-]+$/.test(line)) continue
      const cells = line.split('|').slice(1, -1).map(clean)
      const step = cells[0] || ''
      const status = cells[1] || ''
      if (step === '' || /^step$/i.test(step)) continue
      steps.push({ step, status, kind: statusKind(status) })
    }
    return steps
  }

  // A line that stops the run for the user: `BLOCKED…`, `Status: BLOCKED…`, outside tables and
  // code fences. `SANDBOX-BLOCKED` or `Codex is BLOCKED` in prose is no such line.
  const BLOCKED_LINE = /^(?:[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ ]{0,30}:\s*)?BLOCKED\b/

  function blockedLine(lines) {
    let fence = false
    for (const line of lines) {
      if (line.startsWith('```')) fence = !fence
      if (fence || line.trim().startsWith('|')) continue
      const bare = clean(line).replace(/^#+\s*/, '').replace(/^(?:[-*+]|\d+\.)\s+/, '')
      if (BLOCKED_LINE.test(bare)) return bare
    }
    return null
  }

  /** Title, tier, branch, Progress steps (null when the file has no table) and a BLOCKED line. */
  function parseContext(text, dirName) {
    const lines = String(text).replace(/\r\n?/g, '\n').split('\n')
    const headerEnd = lines.findIndex((l) => /^##\s/.test(l))
    const header = headerEnd < 0 ? lines : lines.slice(0, headerEnd)

    const heading = header.find((l) => /^#\s+\S/.test(l))
    const headingText = heading === undefined ? '' : clean(heading.replace(/^#\s+/, ''))
    const apex = headingText.match(/^APEX\s*[:—–-]\s*(.+)$/i)
    const title = clean(apex ? apex[1] : headingText) || dirName

    const fields = new Map()
    for (const line of header) {
      const m = FIELD.exec(line)
      if (!m) continue
      const key = m[1].trim().toLowerCase()
      if (!fields.has(key)) fields.set(key, clean(m[2]))
    }
    const tierField = fields.get('tier')
    const modeField = fields.get('mode')
    const flags = fields.get('flags') || fields.get('flags résolus')
    const flagMode = flags ? flags.match(/\bmode\s*:?\s+([^\s,;)]+)/i) : null
    const tier = tierField ? headOf(tierField) : modeField ? headOf(modeField) : flagMode ? flagMode[1] : null
    const branchField = fields.get('branch') || fields.get('branche')
    const branch = branchField ? branchField.split(/\s+/)[0] : null

    return { title, tier: tier || null, branch: branch || null, steps: readSteps(lines), blocked: blockedLine(lines) }
  }

  // ---- column of a step, of a file ---------------------------------------

  /** The column a step name stands for: its NN prefix, else a word in it; null when unknown. */
  function stepColumn(step) {
    const nn = /^(\d\d)/.exec(step)
    if (nn) {
      const n = Number(nn[1])
      if (n === 0) return 'init'
      if (n <= 2) return 'plan'
      if (n === 3) return 'execute'
      if (n <= 8) return 'validate'
      return 'done'
    }
    const s = step.toLowerCase()
    if (/init/.test(s)) return 'init'
    if (/analy|plan|challenge|obsidian/.test(s)) return 'plan'
    if (/execut|implement/.test(s)) return 'execute'
    if (/valid|examin|resolv|test|verif|review/.test(s)) return 'validate'
    if (/finish|ship/.test(s)) return 'done'
    return null
  }

  const STEP_FILE = /^(\d\d)[a-z]?-.*\.md$/

  /** The column of the highest NN-*.md among `files`, or null when none is one. */
  function fileColumn(files) {
    const nns = files.map((f) => STEP_FILE.exec(f)).filter(Boolean).map((m) => m[1]).sort()
    return nns.length === 0 ? null : stepColumn(nns[nns.length - 1])
  }

  /** A run that shipped: its pr.md or commit.txt is there. */
  const shipped = (files) => files.includes('pr.md') || files.includes('commit.txt')

  /** A run that delivered: it shipped, or its Progress table has a 09-finish step done. */
  const delivered = (ctx, files) => shipped(files) || ((ctx && ctx.steps) || []).some((s) => s.step.startsWith('09-finish') && s.kind === 'done')

  // ---- directory index, budget, verdict -----------------------------------

  const ENTITIES = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#x27;': "'", '&#39;': "'" }

  /** The entries of a python http.server directory index: `{ name, dir }`, in page order. */
  function parseIndex(html) {
    const out = []
    const re = /<a\s+href="([^"]*)"/gi
    let m
    while ((m = re.exec(html)) !== null) {
      const href = m[1].replace(/&(?:amp|lt|gt|quot|#x27|#39);/g, (e) => ENTITIES[e])
      if (href === '' || href.startsWith('?') || href.startsWith('/') || /^[a-z]+:/i.test(href)) continue
      let name
      try {
        name = decodeURIComponent(href)
      } catch {
        // A malformed escape is no entry this page could have produced.
        continue
      }
      const dir = name.endsWith('/')
      if (dir) name = name.slice(0, -1)
      if (name === '' || name === '.' || name === '..' || name.includes('/')) continue
      out.push({ name, dir })
    }
    return out
  }

  /** Rounds used and grants per run id, from the budget dir's file names `<id>.round<n>` / `<id>.grant<n>`. */
  function parseBudget(names) {
    const budget = new Map()
    for (const name of names) {
      const m = /^(.+)\.(round|grant)(\d+)$/.exec(name)
      if (!m) continue
      const b = budget.get(m[1]) || { rounds: 0, grants: 0 }
      if (m[2] === 'round') b.rounds++
      else b.grants++
      budget.set(m[1], b)
    }
    return budget
  }

  const VERDICTS = new Set(['PASS', 'FAIL', 'BLOCKED', 'ERROR'])

  /** The verdict and findings count of an external-verify.json text, or null when it is not one. */
  function parseVerdict(text) {
    let data
    try {
      data = JSON.parse(text)
    } catch {
      // Half-written or not JSON: no verdict to show.
      return null
    }
    if (typeof data !== 'object' || data === null || !VERDICTS.has(data.verdict)) return null
    return { verdict: data.verdict, findings: Array.isArray(data.findings) ? data.findings.length : 0 }
  }

  const VERDICT_FILE = /^(\d\d[a-z]?-)?external-verify(.*)\.json$/

  /**
   * The run's latest external verdict file among its files, or null. Rounds come from the digits
   * of the suffix after `external-verify` (none = 0, `-r1`/`1`/`-1` = 1, `-2` = 2, `3` = 3 …);
   * equal rounds fall back on the NN prefix, an unprefixed name winning over `NN-` (it was the
   * preferred name before rounds existed).
   */
  function verdictFile(files) {
    let best = null
    for (const f of files) {
      const m = VERDICT_FILE.exec(f)
      if (!m) continue
      const digits = m[2].match(/\d+/)
      const key = { name: f, round: digits ? Number(digits[0]) : 0, prefix: m[1] === undefined ? '~' : m[1] }
      if (best === null || key.round > best.round || (key.round === best.round && key.prefix > best.prefix)) best = key
    }
    return best === null ? null : best.name
  }

  // ---- stage ---------------------------------------------------------------

  const isLive = (mtimeMs, now) => typeof mtimeMs === 'number' && !Number.isNaN(mtimeMs) && now - mtimeMs < STALE_MS

  /** A spent correction budget and a verdict not PASS, each with its hint; empty when neither. */
  function reserveReasons(budget, verdict) {
    const reasons = []
    const cap = MAX_ROUNDS + budget.grants
    if (budget.rounds >= cap) reasons.push({ text: `budget de correction épuisé (${budget.rounds}/${cap})`, hint: HINT_GRANT })
    if (verdict && verdict.verdict !== 'PASS') {
      const findings = verdict.findings > 0 ? ` · ${verdict.findings} findings` : ''
      reasons.push({ text: `vérif externe ${verdict.verdict}${findings}`, hint: HINT_EXT })
    }
    return reasons
  }

  /**
   * Why a live run waits for the user, each with its hint; empty when it does not. A delivered
   * run's reserves (budget, verdict) are no such reason: they go to its `reserve` chip.
   */
  function humanReasons(ctx, budget, verdict, isDelivered) {
    const reasons = []
    for (const s of (ctx && ctx.steps) || []) {
      if (s.kind === 'failed') reasons.push({ text: `étape ${s.step} en échec`, hint: HINT_SESSION })
      if (s.kind === 'blocked') reasons.push({ text: `étape ${s.step} bloquée`, hint: HINT_SESSION })
    }
    if (ctx && ctx.blocked) reasons.push({ text: ctx.blocked.slice(0, 120), hint: HINT_SESSION })
    if (!isDelivered) reasons.push(...reserveReasons(budget, verdict))
    return reasons
  }

  /**
   * The column of a run that does not wait for the user, and whether it finished: pr.md or
   * commit.txt, else the Progress table's current step (running, else first pending; all done is
   * finished), else the highest NN-*.md file.
   */
  function workColumn(ctx, files) {
    if (shipped(files)) return { column: 'done', finished: true, current: null }
    const steps = ctx ? ctx.steps : null
    if (steps && steps.length > 0) {
      const open = [...steps.filter((s) => s.kind === 'running'), ...steps.filter((s) => s.kind === 'pending')]
      if (open.length === 0) return { column: 'done', finished: true, current: null }
      const known = open.find((s) => stepColumn(s.step) !== null)
      if (known) {
        const column = stepColumn(known.step)
        return { column, finished: column === 'done', current: known.step }
      }
    }
    const column = fileColumn(files) || 'init'
    return { column, finished: column === 'done', current: null }
  }

  /** The chips row: tier · ext · corr1 · corr2 (· one more per grant) (· reserve, delivered with reserves). */
  function chipsOf(ctx, budget, verdict, isDelivered) {
    const chips = [{ key: 'tier', label: (ctx && ctx.tier) || 'tier', state: ctx && ctx.tier ? 'info' : 'unset', title: `tier : ${(ctx && ctx.tier) || 'inconnu'}` }]
    if (verdict === null) chips.push({ key: 'ext', label: 'ext', state: 'unset', title: 'vérif externe : aucune' })
    else {
      const findings = verdict.findings > 0 ? ` · ${verdict.findings} findings` : ''
      chips.push({ key: 'ext', label: 'ext', state: verdict.verdict === 'PASS' ? 'pass' : 'fail', title: `vérif externe : ${verdict.verdict}${findings}` })
    }
    const total = MAX_ROUNDS + budget.grants
    for (let n = 1; n <= total; n++) {
      const used = budget.rounds >= n
      chips.push({ key: `corr${n}`, label: `corr${n}`, state: used ? 'used' : 'unset', title: `tour de correction ${n} : ${used ? 'utilisé' : 'libre'}${n > MAX_ROUNDS ? ' (accordé)' : ''}` })
    }
    const reserves = isDelivered ? reserveReasons(budget, verdict) : []
    if (reserves.length > 0) chips.push({ key: 'reserve', label: 'livré avec réserve', state: 'info', title: `livré avec réserve : ${reserves.map((r) => r.text).join(' · ')}` })
    return chips
  }

  /**
   * A run's card: `input` = { id, context (text or null), mtimeMs (Last-Modified of 00-context.md,
   * or null), files (top-level names), budget ({ rounds, grants } or undefined), verdict (text of
   * the external verify file, or null) }.
   * 1. live = mtime < 6 h; 2. live and failed / BLOCKED / budget spent / ext not PASS → À toi,
   * except budget spent / ext not PASS on a delivered run (pr.md, commit.txt or 09-finish done):
   * Terminé with a « livré avec réserve » chip; 3. not live → Terminé (flag `inactif` unless
   * finished); 4-5. workColumn.
   */
  function deriveRun(input, now) {
    const ctx = typeof input.context === 'string' ? parseContext(input.context, input.id) : null
    const files = input.files || []
    const budget = input.budget || { rounds: 0, grants: 0 }
    const verdict = typeof input.verdict === 'string' ? parseVerdict(input.verdict) : null
    const live = isLive(input.mtimeMs, now)
    const work = workColumn(ctx, files)
    const isDelivered = delivered(ctx, files)
    const reasons = live ? humanReasons(ctx, budget, verdict, isDelivered) : []
    const hints = [...new Set(reasons.map((r) => r.hint))].sort((a, b) => (b === HINT_GRANT) - (a === HINT_GRANT))
    const column = reasons.length > 0 ? 'human' : live ? work.column : 'done'
    const flag = column === 'human' ? 'à toi' : !live && !work.finished ? 'inactif' : null
    return {
      id: input.id,
      title: ctx ? ctx.title : input.id,
      tier: ctx ? ctx.tier : null,
      branch: ctx ? ctx.branch : null,
      mtimeMs: typeof input.mtimeMs === 'number' ? input.mtimeMs : null,
      live,
      column,
      current: work.current,
      finished: work.finished,
      flag,
      reasons: reasons.map((r) => r.text),
      hints,
      chips: chipsOf(ctx, budget, verdict, isDelivered),
    }
  }

  /** Cards per column, newest first; Terminé capped at DONE_CAP with the rest counted in `more`. */
  function groupRuns(cards) {
    const out = {}
    for (const c of COLUMNS) out[c.key] = { cards: [], more: 0 }
    const sorted = [...cards].sort((a, b) => (b.mtimeMs || 0) - (a.mtimeMs || 0) || (a.id < b.id ? 1 : a.id > b.id ? -1 : 0))
    for (const card of sorted) out[card.column].cards.push(card)
    const done = out.done
    done.more = Math.max(0, done.cards.length - DONE_CAP)
    done.cards = done.cards.slice(0, DONE_CAP)
    return out
  }

  // ---- drawer --------------------------------------------------------------

  /** A report line's tone: good, warn, stop or null; a verdict word heading the line. */
  function lineTone(line) {
    const bare = clean(line).replace(/^#+\s*/, '').replace(/^verdict\s*:\s*/i, '')
    if (/^(PASS|APPROVED?|READY)\b/.test(bare)) return 'good'
    if (/^(NEEDS_FIXES|CHANGES|FAIL)\b/.test(bare)) return 'warn'
    if (/^(BLOCKED|ESCALATE|ERROR)\b/.test(bare)) return 'stop'
    return null
  }

  /** A run file's verdict dot: a JSON verdict, else the first non-empty line of the text. */
  function fileTone(name, text) {
    if (/\.json$/.test(name)) {
      const v = parseVerdict(text)
      return v === null ? null : v.verdict === 'PASS' ? 'good' : 'stop'
    }
    const first = String(text).split('\n').find((l) => l.trim() !== '')
    return first === undefined ? null : lineTone(first)
  }

  /** Drawer order: 00-context.md, step files by name, then the rest; files of a subdir after. */
  function sortFiles(paths) {
    const rank = (p) => (p.includes('/') ? 3 : p === '00-context.md' ? 0 : /^\d\d/.test(p) ? 1 : 2)
    return [...paths].sort((a, b) => rank(a) - rank(b) || (a < b ? -1 : a > b ? 1 : 0))
  }

  const api = {
    STALE_MS,
    MAX_ROUNDS,
    DONE_CAP,
    COLUMNS,
    statusKind,
    parseContext,
    stepColumn,
    fileColumn,
    parseIndex,
    parseBudget,
    parseVerdict,
    verdictFile,
    isLive,
    deriveRun,
    groupRuns,
    lineTone,
    fileTone,
    sortFiles,
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = api
  else globalThis.ApexBoard = api
})()
