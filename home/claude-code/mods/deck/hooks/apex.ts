// Pure reading of an APEX run: its 00-context.md (header and Progress table, every drifted
// spelling tolerated), its liveness rule, the live steps its tool calls stand for, the external
// verdict file, and what the block and the log show of it. No `$`, no clock, no I/O.

import type {
  DeckApexLiveStep,
  DeckApexRun,
  DeckApexSessionRun,
  DeckApexStep,
  DeckApexStepKind,
  DeckApexStepName,
  DeckApexSteps,
} from '../types'
import { fmtTimer, shorten } from './core'

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

// ---------------------------------------------------------------- live steps

/** The steps in the order the row shows them; edit, gate and ship always, the rest once seen. */
export const STEP_ORDER: readonly DeckApexStepName[] = ['plan', 'edit', 'implement', 'tests', 'gate', 'Codex', 'review', 'ship']
const ALWAYS: ReadonlySet<DeckApexStepName> = new Set<DeckApexStepName>(['edit', 'gate', 'ship'])

const EDITING = new Set(['Edit', 'Write', 'NotebookEdit'])
const PLAN_PATH = /(^|\/)\.claude\/output\/apex\//
const CODEX = /apex-verify-external/
const SHIP = /\bgit\s+(commit|push)\b|\bgh\s+pr\s+(create|merge)\b/
const GATE = /nix flake check|pnpm (verify|test|typecheck|lint)|claude plugin (test|validate)|\btsc\b|cargo (check|test)/

/**
 * The step a tool call stands for, or null. Edits count from every loop; Bash (gate, Codex, ship)
 * from the main loop only: a reviewer's probes are no gate.
 */
export function classifyCall(
  tool: string,
  input: { file_path?: string; notebook_path?: string; command?: string },
  inSubagent: boolean,
): DeckApexStepName | null {
  if (EDITING.has(tool)) {
    const path = input.file_path ?? input.notebook_path ?? ''
    return PLAN_PATH.test(path) ? 'plan' : 'edit'
  }
  if (tool !== 'Bash' || inSubagent) return null
  const command = input.command ?? ''
  if (CODEX.test(command)) return 'Codex'
  if (SHIP.test(command)) return 'ship'
  if (GATE.test(command)) return 'gate'
  return null
}

const IMPLEMENTERS = new Set(['frontend-expert', 'backend-expert', 'nix-expert', 'debugger', 'quick-fix'])
const REVIEWERS = new Set(['code-reviewer', 'security-auditor'])

/** The step a spawned agent stands for (its type's last `:` segment), or null. */
export function classifyAgent(subagentType: string): 'implement' | 'tests' | 'review' | null {
  const type = subagentType.split(':').pop() ?? subagentType
  if (IMPLEMENTERS.has(type)) return 'implement'
  if (type === 'test-runner') return 'tests'
  if (REVIEWERS.has(type)) return 'review'
  return null
}

/** The external verification's verdict line in a Bash output, or null. */
export function parseCodex(output: string): { verdict: string; findings: number } | null {
  const match = /EXTERNAL-VERIFY (PASS|FAIL|BLOCKED)\b(?:.*?findings=(\d+))?/.exec(output)
  const verdict = match?.[1]
  if (verdict === undefined) return null
  return { verdict, findings: Number(match?.[2] ?? 0) }
}

// A report line without its markdown: `**`, heading `#`s, list bullets' leading spaces.
const bare = (line: string): string => line.replace(/\*\*/g, '').replace(/^\s*#+\s*/, '').trim()
const LABELLED = /^\s*verdict\s*:\s*(APPROVED|NEEDS_FIXES|BLOCKED)\b/i
const LEADING = /^(APPROVED|NEEDS_FIXES|BLOCKED)\b/

const nonEmpty = (text: string): string[] => text.replace(/\r\n?/g, '\n').split('\n').filter(l => l.trim() !== '')

// The verdict and the index (among the non-empty lines) of the line that carries it.
function reviewVerdict(lines: readonly string[]): { verdict: string; at: number } | null {
  // A labelled `Verdict: X` line wins: a first line may open with the word as prose ("BLOCKED by X").
  for (const [at, line] of lines.entries()) {
    const word = LABELLED.exec(bare(line))?.[1]
    if (word !== undefined) return { verdict: word.toUpperCase(), at }
  }
  const first = lines[0]
  const word = first === undefined ? undefined : LEADING.exec(bare(first))?.[1]
  return word === undefined ? null : { verdict: word, at: 0 }
}

/**
 * A reviewer's verdict, anchored: a `Verdict: X` line, else a first non-empty line that is (or
 * starts with) APPROVED, NEEDS_FIXES or BLOCKED; else null. The word in later prose is ignored.
 */
export function parseReview(answer: string): string | null {
  return reviewVerdict(nonEmpty(answer))?.verdict ?? null
}

/** The first 3 non-empty lines of a review after its verdict line (from the top without one), shortened. */
export function reviewLines(answer: string): string[] {
  const lines = nonEmpty(answer)
  const v = reviewVerdict(lines)
  return lines.slice(v === null ? 0 : v.at + 1, (v === null ? 0 : v.at + 1) + 3).map(l => shorten(l, 100))
}

/** The first 2 non-empty lines of an agent's final answer, shortened. */
export function answerLines(answer: string): string[] {
  return nonEmpty(answer)
    .slice(0, 2)
    .map(l => shorten(l, 100))
}

/** A path's last two segments: `hooks/apex.ts`. */
export function pathTail(path: string): string {
  return path.split('/').filter(p => p !== '').slice(-2).join('/')
}

type BashOutput = { stdout?: string; stderr?: string; returnCodeInterpretation?: string }

const lastLineOf = (text: string): string | undefined => {
  const last = nonEmpty(text).pop()
  return last === undefined ? undefined : shorten(last, 100)
}

/** A gate call's evidence: its command, the exit code its output names, its error flag, its last output line. */
export function gateEvidence(
  command: string,
  out: BashOutput,
  isError: boolean,
): Pick<DeckApexLiveStep, 'command' | 'exitCode' | 'isError' | 'lastLine'> {
  const all = [out.stdout ?? '', out.stderr ?? '', out.returnCodeInterpretation ?? ''].join('\n')
  const code = /\bexit(?:ed with)?(?: code| status)?[\s:]+(\d+)\b/i.exec(all)?.[1]
  const last = lastLineOf(`${out.stdout ?? ''}\n${out.stderr ?? ''}`)
  return {
    command: shorten(command, 80),
    ...(code === undefined ? {} : { exitCode: Number(code) }),
    isError,
    ...(last === undefined ? {} : { lastLine: last }),
  }
}

/** A ship call's evidence: its command, the commit subject `-m` gives (a heredoc's first line too), a PR URL. */
export function shipEvidence(command: string, stdout: string): Pick<DeckApexLiveStep, 'command' | 'subject' | 'url'> {
  const heredoc = /\bgit\s+commit\b[\s\S]*?-m\s+["']?\$\(cat\s+<<-?\s*['"]?\w+['"]?\s*\n\s*([^\n]+)/.exec(command)?.[1]
  const quoted = /\bgit\s+commit\b[^\n]*?\s-m\s*(?:"([^"\n]*)"|'([^'\n]*)'|([^\s"'$][^\s]*))/.exec(command)
  const subject = heredoc ?? quoted?.[1] ?? quoted?.[2] ?? quoted?.[3]
  const url = /https:\/\/github\.com\/[^\s/]+\/[^\s/]+\/pull\/\d+/.exec(stdout)?.[0]
  return {
    command: shorten(command.split('\n')[0] ?? command, 80),
    ...(subject === undefined || subject.trim() === '' ? {} : { subject: shorten(subject, 80) }),
    ...(url === undefined ? {} : { url }),
  }
}

/** A `gh pr merge` call: the run is at rest once its turn completes. */
export const isMergeCall = (command: string): boolean => /\bgh\s+pr\s+merge\b/.test(command)

/**
 * When the run came to rest, or null while it is busy: the main turn completed (`turnEndAt`) and
 * no agent card or shell of the run (started since `startedAt`) still runs, or a merge was seen.
 * The rest time is the latest of the turn end, an agent end, a shell end.
 */
export function runEndedAt(
  run: { startedAt: number; turnEndAt?: number | null; merged?: boolean },
  cards: readonly { spawnedAt: number; endedAt: number | null; status: string }[],
  shells: readonly { startedAt: number; endedAt?: number; status: string }[],
): number | null {
  const turnEnd = run.turnEndAt
  if (turnEnd === undefined || turnEnd === null) return null
  const ownCards = cards.filter(c => c.spawnedAt >= run.startedAt)
  const ownShells = shells.filter(x => x.startedAt >= run.startedAt)
  const isBusy = ownCards.some(c => c.status === 'running') || ownShells.some(x => x.status === 'running')
  if (isBusy && run.merged !== true) return null
  const ends = [...ownCards.map(c => c.endedAt), ...ownShells.map(x => x.endedAt)].filter((t): t is number => typeof t === 'number')
  return Math.max(turnEnd, ...ends)
}

/** A model id's family (`Opus`), else the id itself. */
export function modelFamily(id: string): string {
  const family = /(opus|sonnet|haiku|fable)/i.exec(id)?.[1]
  return family === undefined ? id : family.charAt(0).toUpperCase() + family.slice(1).toLowerCase()
}

export const NO_STEPS: DeckApexSteps = { runKey: null, steps: [], current: null }

/** A run's steps, none seen yet. */
export const startSteps = (runKey: string): DeckApexSteps => ({ runKey, steps: [], current: null })

/** Step `name` seen at `at` in run `runKey` (another run's steps start over); it becomes current. */
export function seeStep(
  s: DeckApexSteps,
  runKey: string,
  name: DeckApexStepName,
  at: number,
  extra: Omit<DeckApexLiveStep, 'name' | 'status' | 'at'> = {},
): DeckApexSteps {
  const base = s.runKey === runKey ? s : startSteps(runKey)
  const prev = base.steps.find(x => x.name === name)
  // Files add up (distinct, bounded); a ship's subject and PR URL survive its later calls.
  const files = [...new Set([...(prev?.files ?? []), ...(extra.files ?? [])])].slice(0, MAX_FILES)
  const subject = extra.subject ?? prev?.subject
  const url = extra.url ?? prev?.url
  const step: DeckApexLiveStep = {
    name,
    status: 'seen',
    at,
    ...extra,
    ...(files.length === 0 ? {} : { files }),
    ...(subject === undefined ? {} : { subject }),
    ...(url === undefined ? {} : { url }),
  }
  return { runKey, steps: [...base.steps.filter(x => x.name !== name), step], current: name }
}

// Distinct files a step keeps: enough to count « +N more » past the 6 shown.
const MAX_FILES = 40
const SHOWN_FILES = 6

/**
 * Agent `agentId`'s step ended at `at`, with its verdict if any and what its answer said; the same
 * reference when no step is its.
 */
export function endAgent(
  s: DeckApexSteps,
  agentId: string,
  at: number,
  verdict: string | null,
  end: Pick<DeckApexLiveStep, 'lines' | 'isFailed'> = {},
): DeckApexSteps {
  if (!s.steps.some(x => x.agentId === agentId && x.endedAt === undefined)) return s
  return {
    ...s,
    steps: s.steps.map(x =>
      x.agentId === agentId && x.endedAt === undefined ? { ...x, endedAt: at, ...(verdict === null ? {} : { verdict }), ...end } : x,
    ),
  }
}

const WARN_VERDICTS = new Set(['FAIL', 'BLOCKED', 'ERROR', 'NEEDS_FIXES'])

export type StepMark = 'done' | 'current' | 'pending'

export type StepCell = { name: DeckApexStepName; label: string; mark: StepMark; isWarn: boolean }

const isRunning = (x: DeckApexLiveStep): boolean => x.agentId !== undefined && x.endedAt === undefined

// A step with a verdict is done; the current one, or one whose agent still runs, is ◐.
const markOf = (s: DeckApexSteps, x: DeckApexLiveStep): StepMark =>
  x.verdict !== undefined ? 'done' : x.name === s.current || isRunning(x) ? 'current' : 'done'

/** The step row: label (with its verdict and findings), mark, warn colour. */
export function stepCells(s: DeckApexSteps): StepCell[] {
  const cells: StepCell[] = []
  for (const name of STEP_ORDER) {
    const x = s.steps.find(y => y.name === name)
    if (x === undefined) {
      if (ALWAYS.has(name)) cells.push({ name, label: name, mark: 'pending', isWarn: false })
      continue
    }
    const findings = x.findings !== undefined && x.findings > 0 ? ` ${x.findings}` : ''
    const label = x.verdict === undefined ? name : `${name} ${x.verdict}${findings}`
    cells.push({ name, label, mark: markOf(s, x), isWarn: x.verdict !== undefined && WARN_VERDICTS.has(x.verdict) })
  }
  return cells
}

export type StepDetail = { name: DeckApexStepName; mark: StepMark; text: string; since?: number }

const detailOf = (s: DeckApexSteps, x: DeckApexLiveStep): StepDetail | null => {
  if (isRunning(x) && x.detail !== undefined) return { name: x.name, mark: markOf(s, x), text: `${x.name} : ${x.detail}`, since: x.at }
  if (x.verdict === undefined) return null
  const findings = x.findings !== undefined && x.findings > 0 ? ` · ${x.findings} findings` : ''
  return { name: x.name, mark: markOf(s, x), text: `${x.name} : ${x.verdict}${findings}` }
}

/** The line under the row: the current step's agent (running) or verdict, else a still running agent's. */
export function stepDetail(s: DeckApexSteps): StepDetail | null {
  const current = s.steps.find(x => x.name === s.current)
  const own = current === undefined ? null : detailOf(s, current)
  if (own !== null) return own
  const running = [...s.steps].reverse().find(x => isRunning(x) && x.detail !== undefined)
  return running === undefined ? null : detailOf(s, running)
}

/** A step's explanation box: its lines, and when a still running agent started (its live clock). */
export type StepExplain = { lines: string[]; since?: number }

// An agent step's head line: description (model), status, duration once ended.
const agentLine = (x: DeckApexLiveStep): string => {
  const what = x.detail ?? x.name
  if (x.endedAt === undefined) return `${what} · running`
  return `${what} · ${x.isFailed === true ? 'failed' : 'done'} · ${fmtTimer(x.endedAt - x.at)}`
}

/** What a step did, as its explanation box shows it; a step never seen is not reached yet. */
export function explainStep(s: DeckApexSteps, name: DeckApexStepName): StepExplain {
  const x = s.steps.find(y => y.name === name)
  if (x === undefined) return { lines: ['not reached yet'] }
  const running = x.agentId !== undefined && x.endedAt === undefined ? { since: x.at } : {}
  switch (name) {
    case 'plan':
    case 'edit': {
      const files = x.files ?? []
      if (files.length === 0) return { lines: [name === 'plan' ? 'run files written' : 'files edited'] }
      const more = files.length > SHOWN_FILES ? ` +${files.length - SHOWN_FILES} more` : ''
      return { lines: [`${files.slice(0, SHOWN_FILES).join(', ')}${more}`] }
    }
    case 'implement':
    case 'tests':
      return { lines: [agentLine(x), ...(x.lines ?? []).slice(0, 2)], ...running }
    case 'review': {
      const head = x.endedAt === undefined ? agentLine(x) : `${x.verdict ?? 'no verdict'} · ${agentLine(x)}`
      return { lines: [head, ...(x.lines ?? []).slice(0, 3)], ...running }
    }
    case 'gate': {
      const status = x.exitCode !== undefined ? `exit ${x.exitCode}` : x.isError === true ? 'failed' : 'ok'
      const tail = x.lastLine === undefined ? '' : ` · ${x.lastLine}`
      return { lines: [`$ ${x.command ?? 'gate'}`, `${status}${tail}`] }
    }
    case 'Codex': {
      if (x.verdict === undefined) return { lines: ['no verdict (ran in background)'] }
      return { lines: [`${x.verdict} · ${x.findings ?? 0} findings`] }
    }
    case 'ship': {
      const head = x.subject !== undefined ? `commit: ${x.subject}` : `$ ${x.command ?? 'ship'}`
      return { lines: [head, ...(x.url === undefined ? [] : [`PR: ${x.url}`])] }
    }
  }
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
