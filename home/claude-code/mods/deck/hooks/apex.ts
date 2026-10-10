// Pure reading of an APEX run: its 00-context.md (header and Progress table, every drifted
// spelling tolerated), its liveness rule, the per-phase token buckets, the external verdict
// file, and what the block and the log show of it. No `$`, no clock, no I/O.

import type { DeckApexPhases, DeckApexRun, DeckApexSessionRun, DeckApexStep, DeckApexStepKind, DeckApexTally } from '../types'

// ---------------------------------------------------------------- context file

/** A run is live only while its context file moved in the last 6 hours. */
export const STALE_MS = 6 * 60 * 60 * 1000

const clean = (value: string): string => value.replace(/\*\*/g, '').replace(/`/g, '').trim()

export function statusKind(status: string): DeckApexStepKind {
  const s = clean(status).toLowerCase()
  if (/^(complete|done|✅)/.test(s)) return 'done'
  if (/^pending/.test(s)) return 'pending'
  if (/^(in[ _]progress|en cours|running)/.test(s)) return 'running'
  if (/^(skipped|supprimé|n\/a)/.test(s)) return 'skipped'
  if (/^(red|failed|échoué)(?![a-z])/.test(s)) return 'failed'
  return 'other'
}

// "Key: value", "**Key:** value", "**Key**: value", "- Key: value".
const FIELD = /^\s*(?:[-*]\s+)?\**\s*([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ ]*?)\s*\**\s*:\s*(.*)$/

/** A header value's head: `Standard (mods UI) — files…` → `Standard`. */
function headOf(value: string): string {
  const head = value.split(/\s+—\s+|\s+→\s+|\s*\(|;|\.\s/)[0] ?? value
  return head.trim()
}

function readSteps(lines: readonly string[]): DeckApexStep[] {
  const start = lines.findIndex(l => /^##\s+progress\b/i.test(l))
  if (start < 0) return []
  const steps: DeckApexStep[] = []
  for (const line of lines.slice(start + 1)) {
    if (/^##\s/.test(line)) break
    if (!line.trim().startsWith('|')) continue
    if (/^[\s|:-]+$/.test(line)) continue
    const cells = line.split('|').slice(1, -1).map(clean)
    const step = cells[0] ?? ''
    const status = cells[1] ?? ''
    if (step === '' || /^step$/i.test(step)) continue
    steps.push({ step, status, kind: statusKind(status) })
  }
  return steps
}

export function currentStep(steps: readonly DeckApexStep[]): string | undefined {
  return (steps.find(s => s.kind === 'running') ?? steps.find(s => s.kind === 'pending'))?.step
}

export function parseContext(text: string, dirName: string): DeckApexRun {
  const lines = text.replace(/\r\n?/g, '\n').split('\n')
  const headerEnd = lines.findIndex(l => /^##\s/.test(l))
  const header = headerEnd < 0 ? lines : lines.slice(0, headerEnd)

  const heading = header.find(l => /^#\s+\S/.test(l))
  const headingText = heading === undefined ? undefined : clean(heading.replace(/^#\s+/, ''))
  const apexTitle = headingText?.match(/^APEX\s*[:—–-]\s*(.+)$/i)?.[1]
  const title = clean(apexTitle ?? headingText ?? '') || dirName

  const fields = new Map<string, string>()
  for (const line of header) {
    const match = FIELD.exec(line)
    const key = match?.[1]?.trim().toLowerCase()
    const value = match?.[2]
    if (key === undefined || value === undefined || fields.has(key)) continue
    fields.set(key, clean(value))
  }

  const tierField = fields.get('tier')
  const modeField = fields.get('mode')
  const flags = fields.get('flags') ?? fields.get('flags résolus')
  const tier =
    tierField !== undefined && tierField !== ''
      ? headOf(tierField)
      : modeField !== undefined && modeField !== ''
        ? headOf(modeField)
        : flags?.match(/\bmode\s+([^\s,;)]+)/i)?.[1]

  const branch = (fields.get('branch') ?? fields.get('branche'))?.split(/\s+/)[0]

  const run: DeckApexRun = { title, steps: readSteps(lines) }
  if (tier !== undefined && tier !== '') run.tier = tier
  if (branch !== undefined && branch !== '') run.branch = branch
  const current = currentStep(run.steps)
  if (current !== undefined) run.currentStep = current
  return run
}

/**
 * Live: modified in the last `staleMs` (STALE_MS by default), its 09-finish row neither done nor
 * skipped, and, when it has a Progress table, a pending or running row left.
 */
export function isLive(run: DeckApexRun, mtimeMs: number, now: number, staleMs: number = STALE_MS): boolean {
  if (now - mtimeMs >= staleMs) return false
  const finish = run.steps.find(s => /finish/i.test(s.step))
  if (finish !== undefined && (finish.kind === 'done' || finish.kind === 'skipped')) return false
  if (run.steps.length === 0) return true
  return run.steps.some(s => s.kind === 'pending' || s.kind === 'running')
}

/** APEX's main steps in order: the pending dots of a run read from its files. */
export const KNOWN_STEPS: readonly string[] = [
  '00-init',
  '01-analyze',
  '02-plan',
  '03-execute',
  '04-validate',
  '05-examine',
  '06-resolve',
  '07-tests',
  '08-run-tests',
  '09-finish',
]

// A step file: `NN-name.md` or `NNx-name.md`; 00-context.md is the run's header, not a step.
const STEP_FILE = /^(?!00-context\.md$)(\d\d[a-z]?-.+)\.md$/
const FINISH = /^\d\d[a-z]?-finish$/

/** A run folder without 00-context.md is live only while one of its step files moved in the last hour. */
export const BARE_STALE_MS = 60 * 60 * 1000

/** The newest step file's mtime among `files`, or -Infinity when none is a step file. */
export function newestStep(files: readonly { name: string; mtimeMs: number }[]): number {
  return Math.max(-Infinity, ...files.filter(f => STEP_FILE.test(f.name)).map(f => f.mtimeMs))
}

/**
 * A run folder without 00-context.md is shown only off the trunk (HEAD neither master nor main)
 * and while its newest step file is under BARE_STALE_MS old; the rest is isLive's rule.
 */
export function bareShown(run: DeckApexRun, stepMs: number, head: string | undefined, now: number): boolean {
  if (head === 'master' || head === 'main') return false
  return isLive(run, stepMs, now, BARE_STALE_MS)
}

/**
 * The run dir a poll found against the last one seen this session: new only when a previous run
 * was seen and the dir differs. `last` survives a poll with no run (a miss, an ended run), so the
 * same run coming back is not new. From a session key the poll never finds a new run: the call
 * that set it already counted (callSwitch), and the folder it then writes is that same run.
 */
export function runSwitch(last: string | null, dir: string | null): { isNew: boolean; last: string | null } {
  if (dir === null) return { isNew: false, last }
  return { isNew: last !== null && last !== dir && !isSessionDir(last), last: dir }
}

// ---------------------------------------------------------------- session run

// A session run's key, in the run dir's place: never a folder name (a folder holds no colon here).
const SESSION_PREFIX = 'session:'

/** The run key of the main-loop Skill(apex) call started at `startedAt`. */
export const sessionKey = (startedAt: number): string => `${SESSION_PREFIX}${startedAt}`

/** A run key set by a Skill(apex) call rather than by a folder under .claude/output/apex. */
export const isSessionDir = (dir: string): boolean => dir.startsWith(SESSION_PREFIX)

/** A main-loop Skill(apex) call: a new run once any run was seen this session. */
export function callSwitch(last: string | null, key: string): { isNew: boolean; last: string } {
  return { isNew: last !== null, last: key }
}

/**
 * The run a main-loop Skill(apex) call stands for while no run folder is live: shown off the
 * trunk (HEAD neither master nor main) and under BARE_STALE_MS after the last call; HEAD as
 * header, no tier, one current `apex` row.
 */
export function sessionRunOf(at: DeckApexSessionRun | null, head: string | undefined, now: number): DeckApexRun | null {
  if (at === null || head === 'master' || head === 'main' || now - at.lastAt >= BARE_STALE_MS) return null
  const run: DeckApexRun = {
    title: 'apex',
    steps: [{ step: 'apex', status: 'in progress', kind: 'running' }],
    currentStep: 'apex',
    dir: sessionKey(at.startedAt),
  }
  if (head !== undefined) run.branch = head
  return run
}

/**
 * A run folder without 00-context.md, read from its step files: title the folder, no tier, each
 * present step done, the most recently modified one current (a finish file never: the run ended),
 * the known steps after it pending.
 */
export function runFromFiles(dirName: string, files: readonly { name: string; mtimeMs: number }[]): DeckApexRun {
  const present = new Map<string, number>()
  for (const file of files) {
    const step = STEP_FILE.exec(file.name)?.[1]
    if (step !== undefined) present.set(step, Math.max(present.get(step) ?? 0, file.mtimeMs))
  }
  let current: string | undefined
  let newest = -Infinity
  for (const [step, mtimeMs] of present) {
    // A finish file ends the run: done, never current.
    if (FINISH.test(step)) continue
    if (mtimeMs > newest || (mtimeMs === newest && current !== undefined && step > current)) {
      current = step
      newest = mtimeMs
    }
  }
  const names = new Set(present.keys())
  if (current !== undefined) for (const step of KNOWN_STEPS) if (step > current) names.add(step)
  const steps: DeckApexStep[] = [...names].sort().map(step =>
    step === current
      ? { step, status: 'in progress', kind: 'running' }
      : present.has(step)
        ? { step, status: 'complete', kind: 'done' }
        : { step, status: 'pending', kind: 'pending' },
  )
  const run: DeckApexRun = { title: dirName, steps }
  if (current !== undefined) run.currentStep = current
  return run
}

/** The branch a .git/HEAD file names, or undefined (detached HEAD, anything unrecognised). */
export function headBranch(text: string): string | undefined {
  const name = /^ref:\s*refs\/heads\/(\S+)\s*$/.exec(text.trim())?.[1]
  return name === undefined || name === '' ? undefined : name
}

/** Off-branch only when both the run's branch and HEAD's are known and differ. */
export function onBranch(run: DeckApexRun, head: string | undefined): boolean {
  return run.branch === undefined || head === undefined || run.branch === head
}

// ---------------------------------------------------------------- phases

/** What a step's usage carries: ModelUsage's four counts. */
export type Usage = {
  input_tokens: number
  output_tokens: number
  cache_read_input_tokens: number
  cache_creation_input_tokens: number
}

export const ZERO: DeckApexTally = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }

// A finite non-negative count, else 0 (usage comes from the API).
const count = (n: number): number => (Number.isFinite(n) && n > 0 ? n : 0)

export function addUsage(tally: DeckApexTally, usage: Usage): DeckApexTally {
  return {
    input: tally.input + count(usage.input_tokens),
    output: tally.output + count(usage.output_tokens),
    cacheRead: tally.cacheRead + count(usage.cache_read_input_tokens),
    cacheWrite: tally.cacheWrite + count(usage.cache_creation_input_tokens),
  }
}

/** A phase's work as the block shows it: input, output and cache writes (cache reads left out). */
export const countedTotal = (t: DeckApexTally): number => t.input + t.output + t.cacheWrite

/** The buckets kept for run `dir` (null: no live run), started over when the run changed; same reference when equal. */
export function syncPhases(phases: DeckApexPhases, dir: string | null): DeckApexPhases {
  return phases.dir === dir ? phases : { dir, byStep: {} }
}

/** One response's usage added to `step`'s bucket of run `dir`; the buckets start over when the run changed. */
export function addPhase(phases: DeckApexPhases, dir: string, step: string | undefined, usage: Usage | null): DeckApexPhases {
  const base = phases.dir === dir ? phases : { dir, byStep: {} }
  if (step === undefined || usage === null) return base
  return { dir, byStep: { ...base.byStep, [step]: addUsage(base.byStep[step] ?? ZERO, usage) } }
}

// ---------------------------------------------------------------- verdict

const VERDICTS = new Set(['PASS', 'FAIL', 'BLOCKED', 'ERROR'])

/** The verdict word and findings count of an external-verify.json text, or null when it is not one. */
export function parseVerdict(text: string): { verdict: string; findings: number } | null {
  let data: unknown
  try {
    data = JSON.parse(text)
  } catch {
    // Not JSON (half-written, or another file): no verdict to show.
    return null
  }
  if (typeof data !== 'object' || data === null) return null
  const word: unknown = Reflect.get(data, 'verdict')
  const findings: unknown = Reflect.get(data, 'findings')
  if (typeof word !== 'string' || !VERDICTS.has(word)) return null
  return { verdict: word, findings: Array.isArray(findings) ? findings.length : 0 }
}

// ---------------------------------------------------------------- what the block and the log show

export type PhaseMark = 'done' | 'current' | 'pending' | 'failed' | 'skipped'

/** A step's dot: ● done, ◐ current, ○ pending; a failed step ✗, a skipped one ·. */
export function phaseMark(step: DeckApexStep, current: string | undefined): PhaseMark {
  if (step.kind === 'failed') return 'failed'
  if (step.step === current || step.kind === 'running') return 'current'
  if (step.kind === 'done') return 'done'
  if (step.kind === 'skipped') return 'skipped'
  return 'pending'
}

export const PHASE_GLYPH: Record<PhaseMark, string> = { done: '●', current: '◐', pending: '○', failed: '✗', skipped: '·' }

/** The block's header: `APEX · <branch, else title> · <tier>`. */
export function apexHeader(run: DeckApexRun): string {
  return ['APEX', run.branch ?? run.title, run.tier].filter((p): p is string => p !== undefined && p !== '').join(' · ')
}

/**
 * The log line a poll owes: a run found (its current step), a step that moved, a run gone; null
 * when nothing moved. Only the current step and the run's directory count.
 */
export function phaseNote(prev: DeckApexRun | null, next: DeckApexRun | null): string | null {
  if (next === null) return prev === null ? null : 'run ended'
  if (prev === null || prev.dir !== next.dir) return `${next.branch ?? next.title} · ${next.currentStep ?? 'started'}`
  if (prev.currentStep === next.currentStep) return null
  return `${prev.currentStep ?? '—'} → ${next.currentStep ?? 'done'}`
}

/** Polls in a row that must miss a live run before it counts as ended: one failed read is not an end. */
export const END_MISSES = 2

/**
 * The run a poll keeps: what it found, or, while a run shown before is missed fewer than
 * END_MISSES times in a row, that run still; `misses` is the count carried to the next poll.
 */
export function settleRun(prev: DeckApexRun | null, found: DeckApexRun | null, misses: number): { run: DeckApexRun | null; misses: number } {
  if (found !== null || prev === null) return { run: found, misses: 0 }
  const missed = misses + 1
  return missed >= END_MISSES ? { run: null, misses: 0 } : { run: prev, misses: missed }
}
