// deck: one live dashboard pane, opened on demand only (/deck, aliases /apex-pane and
// /task-board); it never opens by itself and draws no status line: nothing above the prompt
// unless you open it.
// From Flightdeck v0.3.2 (MIT, Stephen Casella): main model vitals, the on-call architect,
// subagent cards and swimlanes, a turn receipt and a session log. Ours: the APEX block on top,
// drawn only while an APEX run of the session's folder is live (header, phase dots, what asks
// the user to act, background shells), its phase changes written to the log as `apex`.
// Observes only: every hook but the commands and the pane returns next(e)'s result unchanged.
// Read-only: it never writes a file. The run folders are polled every 5 s only while the pane is
// open, and once per prompt and per finished main turn otherwise; a poll writes nothing that
// did not change.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type {
  DeckAgentCard,
  DeckApexAlert,
  DeckApexBudget,
  DeckApexRun,
  DeckApexSessionRun,
  DeckApexShell,
  DeckApexSteps,
  DeckApexVerdict,
  DeckArchitect,
  DeckLayout,
  DeckLogLine,
  DeckMain,
  DeckRoster,
  DeckTurn,
  DeckUsage,
  DeckView,
} from '../types'
import {
  DEFAULT_ARCHITECT,
  DEFAULT_MAIN,
  DEFAULT_ROSTER,
  DEFAULT_TURN,
  DEFAULT_USAGE,
  DEFAULT_VIEW,
  EDIT_TOOLS,
  afterCall,
  applyStep,
  cardTitle,
  titleLines,
  consultTimeline,
  describeInput,
  endConsult,
  fitLegend,
  fmtClock,
  fmtDuration,
  fmtTimer,
  fmtUsd,
  plural,
  gauge,
  isAdvising,
  kTokens,
  lanes,
  limitLabel,
  listOf,
  logRows,
  momentOf,
  normalize,
  normalizeCard,
  normalizeLog,
  noteTool,
  PALETTES,
  SVG_COLORS,
  parseConfig,
  prettyModel,
  promptLine,
  handbackOf,
  adviceLine,
  receiptOf,
  shorten,
  startConsult,
} from './core'
import type { Config, Panel } from './core'
import {
  NO_STEPS,
  PHASE_GLYPH,
  apexHeader,
  bareShown,
  callSwitch,
  classifyAgent,
  classifyCall,
  endAgent,
  headBranch,
  isLive,
  modelFamily,
  newestStep,
  onBranch,
  parseCodex,
  parseContext,
  parseReview,
  parseVerdict,
  phaseNote,
  runFromFiles,
  runSwitch,
  isSessionDir,
  seeStep,
  sessionKey,
  sessionRunOf,
  settleRun,
  startSteps,
  stepCells,
  stepDetail,
} from './apex'
import type { StepCell, StepMark } from './apex'
import {
  addShell,
  clearFinished,
  closeBySnapshot,
  shellsAfterTurn,
  finishByNotification,
  parseTaskNotifications,
  runningShells,
  stopShell,
} from './shells'
import type { Notification } from './shells'
import { alertsOf, budgetOf, pickVerdict } from './signals'

const PANE = 'deck'
const TITLE = 'Deck'
const PANE_COLUMNS = 66
const POLL_MS = 5000
// The two names the external verification is written under, in a run dir.
const VERIFY_NAMES = ['04-external-verify.json', 'external-verify.json']
// Finished shells shown under the running ones; the rest fold into « +N earlier ».
const DONE_SHELLS = 3

// ---------------------------------------------------------------- state

const main = atom({ plugin: 'deck', key: 'main' } as const, DEFAULT_MAIN)
const usage = atom({ plugin: 'deck', key: 'usage' } as const, DEFAULT_USAGE)
const architect = atom({ plugin: 'deck', key: 'architect' } as const, DEFAULT_ARCHITECT)
const agents = atom({ plugin: 'deck', key: 'agents' } as const, [])
const log = atom({ plugin: 'deck', key: 'log' } as const, [])
const turn = atom({ plugin: 'deck', key: 'turn' } as const, DEFAULT_TURN)
const receipt = atom({ plugin: 'deck', key: 'receipt' } as const, null)
const view = atom({ plugin: 'deck', key: 'view' } as const, DEFAULT_VIEW)
const roster = atom({ plugin: 'deck', key: 'roster' } as const, DEFAULT_ROSTER)
const run = atom({ plugin: 'deck', key: 'run' } as const, null)
const apexSteps = atom({ plugin: 'deck', key: 'apexSteps' } as const, NO_STEPS)
const verdict = atom({ plugin: 'deck', key: 'verdict' } as const, null)
const budget = atom({ plugin: 'deck', key: 'budget' } as const, null)
const shells = atom({ plugin: 'deck', key: 'shells' } as const, [])
const sessionRun = atom({ plugin: 'deck', key: 'sessionRun' } as const, null)

// Module-level: a hot reload drops the environment and its timer with it.
let timer: Timer | undefined
// The pane is open: the 5 s timer runs only then.
let isPaneOpen = false
// Polls in a row that missed the run shown (settleRun).
let misses = 0
// The last run dir a poll found this session (kept through a miss or an ended run), or null:
// a different one is a new run, which clears the finished cards and shells.
let lastRunDir: string | null = null
// The poll under way (its number), or null: a second one waits, unless the first is stuck for
// STUCK_TICKS ticks, when it is given up and polling goes on.
let pollCount = 0
let pollUnderWay: number | null = null
let skippedTicks = 0
const STUCK_TICKS = 6

type ServerBlock = { type: string; id?: string; name?: string; tool_use_id?: string }

// Every read goes through these, so a value saved under an older shape still reads.
async function getMain($: EngineInterface): Promise<DeckMain> {
  return normalize(DEFAULT_MAIN, await read($, main))
}
async function getUsage($: EngineInterface): Promise<DeckUsage> {
  return normalize(DEFAULT_USAGE, await read($, usage))
}
async function getArchitect($: EngineInterface): Promise<DeckArchitect> {
  const a = normalize(DEFAULT_ARCHITECT, await read($, architect))
  return { ...a, consults: listOf(a.consults), ids: listOf(a.ids), seen: listOf(a.seen) }
}
async function getCards($: EngineInterface): Promise<DeckAgentCard[]> {
  return listOf<unknown>(await read($, agents)).map(normalizeCard)
}
async function getLog($: EngineInterface): Promise<DeckLogLine[]> {
  return normalizeLog(await read($, log))
}
async function getTurn($: EngineInterface): Promise<DeckTurn> {
  return normalize(DEFAULT_TURN, await read($, turn))
}
async function getView($: EngineInterface): Promise<DeckView> {
  return normalize(DEFAULT_VIEW, await read($, view))
}
async function getRoster($: EngineInterface): Promise<DeckRoster> {
  const r = normalize(DEFAULT_ROSTER, await read($, roster))
  return { architectTypes: listOf(r.architectTypes) }
}
async function getShells($: EngineInterface): Promise<DeckApexShell[]> {
  return listOf<DeckApexShell>(await read($, shells))
}

async function say($: EngineInterface, who: string, text: string, kind: DeckLogLine['kind'] = 'info', agentId: string | null = null) {
  const line: DeckLogLine = { at: await $.clock.now(), who, text, kind, agentId }
  await update($, log, list => [...normalizeLog(list), line].slice(-60))
}

async function whoIs($: EngineInterface, agentId: string | undefined) {
  if (!agentId) return 'main'
  const card = (await getCards($)).find(c => c.id === agentId)
  return card ? shorten(cardTitle(card), 14) : 'agent'
}

async function consultStarted($: EngineInterface, cfg: Config, id: string, via: string) {
  const t = await getTurn($)
  const moment = momentOf(t)
  const at = await $.clock.now()
  await update($, architect, a => startConsult(normalize(DEFAULT_ARCHITECT, a), { id, at, moment, via }))
  if (moment === 'before done') await update($, turn, x => ({ ...normalize(DEFAULT_TURN, x), isReviewing: true }))
  await say($, cfg.architectLabel.toLowerCase(), cfg.moments ? `${moment} · ${via}` : `consulted · ${via}`, 'consult')
}

async function consultEnded($: EngineInterface, cfg: Config, advice: string | null, id?: string) {
  const at = await $.clock.now()
  const first = advice?.split('\n').find(l => l.trim()) ?? null
  const text = first ? shorten(first.replace(/^[#>*\s-]+/, ''), 160) : null
  await update($, architect, a => endConsult(normalize(DEFAULT_ARCHITECT, a), at, text, id))
  await update($, turn, t => ({ ...normalize(DEFAULT_TURN, t), isReviewing: false }))
  await say($, cfg.architectLabel.toLowerCase(), text ? `advice: ${shorten(text, 60)}` : 'advice returned', 'consult')
}

async function noteAdvice($: EngineInterface, cfg: Config, advice: string) {
  await update($, architect, x => ({ ...normalize(DEFAULT_ARCHITECT, x), lastAdvice: advice }))
  await say($, cfg.architectLabel.toLowerCase(), `advice: ${shorten(advice, 60)}`, 'consult')
}

async function isArchitectType($: EngineInterface, cfg: Config, type: string) {
  return cfg.architect.test(type) || (await getRoster($)).architectTypes.includes(type)
}

async function openPane($: EngineInterface) {
  // columns apply when docked beside the transcript, rows when seated inline above the prompt.
  const opened = await $.ui.open({ id: PANE, title: TITLE, columns: PANE_COLUMNS, rows: 8 })
  // Open, even when not placed yet (seated once a surface places it): polled from now on.
  isPaneOpen = true
  startPolling($)
  return opened
}

async function resetAll($: EngineInterface) {
  await update($, main, m => ({ ...DEFAULT_MAIN, model: normalize(DEFAULT_MAIN, m).model, mode: normalize(DEFAULT_MAIN, m).mode }))
  await update($, architect, () => DEFAULT_ARCHITECT)
  await update($, agents, () => [])
  await update($, log, () => [])
  await update($, turn, () => DEFAULT_TURN)
  await update($, receipt, () => null)
  await update($, view, () => DEFAULT_VIEW)
  // The context gauge waits for the next measurement rather than showing the pre-clear fill.
  await update($, usage, x => ({ ...normalize(DEFAULT_USAGE, x), pct: null, tokens: null }))
  // The run comes back on the next poll; its live steps start over.
  await update($, run, () => null)
  await update($, apexSteps, () => NO_STEPS)
  await update($, verdict, () => null)
  await update($, budget, () => null)
  await update($, shells, () => [])
  await update($, sessionRun, () => null)
}

/** The session's cost read fresh, not from the last measurement: the receipt subtracts two of these. */
async function costNow($: EngineInterface): Promise<number | null> {
  const u = await $.session.usage().catch(() => null)
  return u?.cost?.usd ?? null
}

async function noteMode($: EngineInterface, mode: string | undefined) {
  if (mode) await update($, main, m => (normalize(DEFAULT_MAIN, m).mode === mode ? normalize(DEFAULT_MAIN, m) : { ...normalize(DEFAULT_MAIN, m), mode }))
}

// ---------------------------------------------------------------- APEX run (polled)

// Reads a field of an engine record whose shape varies per tool; a value that is not a
// non-empty string reads as undefined.
function stringField(record: unknown, key: string): string | undefined {
  if (typeof record !== 'object' || record === null) return undefined
  const value: unknown = Reflect.get(record, key)
  return typeof value === 'string' && value !== '' ? value : undefined
}

function numberField(record: unknown, key: string): number | undefined {
  if (typeof record !== 'object' || record === null) return undefined
  const value: unknown = Reflect.get(record, key)
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined
}

// A row's text: a string as is, else its text blocks joined; another shape reads as empty.
function rowText(content: unknown): string {
  if (typeof content === 'string') return content
  if (!Array.isArray(content)) return ''
  const parts: string[] = []
  for (const block of content) {
    const text = stringField(block, 'type') === 'text' ? stringField(block, 'text') : undefined
    if (text !== undefined) parts.push(text)
  }
  return parts.join('\n')
}

// A run folder: its name, its newest time (with a context file: that file's or its newest .md
// file's; without: its newest step file's), its context file's mtime when it has one, its .md files.
type RunDir = { dir: string; mtimeMs: number; context?: number; files: { name: string; mtimeMs: number }[] }

// Folders listed per poll: the LISTED_DIRS ranked newest that are runs, plus the newest with a
// context file wherever it ranks. Cost before that: 1 stat per folder with a context file, 2 per
// folder without (the failed context stat, then the folder's own).
const LISTED_DIRS = 3

// The newest run folder, or undefined. Ranked by its context file's mtime, else by the folder's
// own (adding a file moves it; editing one does not), then listed in rank order and the newest
// time of each decides. A folder without a context file and without a step file is no run: it
// takes no slot and is never chosen.
async function newestRun($: EngineInterface, root: string): Promise<RunDir | undefined> {
  let entries
  try {
    entries = await $.fs.list(root)
  } catch {
    // No .claude/output/apex here (or unreadable): no run to show.
    return undefined
  }
  const ranked: { dir: string; key: number; context?: number }[] = []
  for (const entry of entries) {
    if (entry.kind !== 'dir') continue
    try {
      const stat = await $.fs.stat(`${root}/${entry.name}/00-context.md`)
      ranked.push({ dir: entry.name, key: stat.mtimeMs, context: stat.mtimeMs })
      continue
    } catch {
      // No context file: the folder ranks by its own mtime, read below.
    }
    try {
      ranked.push({ dir: entry.name, key: (await $.fs.stat(`${root}/${entry.name}`)).mtimeMs })
    } catch {
      // Vanished between list and stat: skipped.
    }
  }
  ranked.sort((a, b) => b.key - a.key)
  const newestContext = ranked.find(r => r.context !== undefined)
  let best: RunDir | undefined
  let slots = 0
  for (const candidate of ranked) {
    if (slots >= LISTED_DIRS && candidate !== newestContext) continue
    let files: { name: string; mtimeMs: number }[]
    try {
      files = (await $.fs.list(`${root}/${candidate.dir}`))
        .filter(e => e.kind === 'file' && e.name.endsWith('.md'))
        .map(e => ({ name: e.name, mtimeMs: e.mtimeMs }))
    } catch {
      // Unreadable folder: its context file's time alone, if any.
      files = []
    }
    const mtimeMs =
      candidate.context === undefined ? newestStep(files) : Math.max(candidate.context, ...files.map(f => f.mtimeMs))
    // Without a context file, a folder with no step file is not a run: no slot, never chosen.
    if (mtimeMs === -Infinity) continue
    slots += 1
    if (best !== undefined && mtimeMs <= best.mtimeMs) continue
    best = { dir: candidate.dir, mtimeMs, files, ...(candidate.context === undefined ? {} : { context: candidate.context }) }
  }
  return best
}

// HEAD's branch, or undefined: no repo here, or a worktree whose .git is a file.
async function readHead($: EngineInterface, cwd: string): Promise<string | undefined> {
  try {
    return headBranch(await $.fs.read(`${cwd}/.git/HEAD`))
  } catch {
    // Unreadable HEAD: branch unknown, shown.
    return undefined
  }
}

// The session's last main-loop Skill(apex) call, or null (an older shape reads as none).
async function getSessionRun($: EngineInterface): Promise<DeckApexSessionRun | null> {
  const value: unknown = await read($, sessionRun)
  const startedAt = numberField(value, 'startedAt')
  const lastAt = numberField(value, 'lastAt')
  if (startedAt === undefined || lastAt === undefined) return null
  return { startedAt, lastAt, args: stringField(value, 'args') ?? '' }
}

// The live run folder, else the session's Skill(apex) call (HEAD read only when there is one).
async function scan($: EngineInterface): Promise<DeckApexRun | null> {
  const cwd = await $.session.cwd()
  const folder = await scanFolder($, cwd)
  if (folder !== null) return folder
  const at = await getSessionRun($)
  if (at === null) return null
  return sessionRunOf(at, await readHead($, cwd), await $.clock.now())
}

async function scanFolder($: EngineInterface, cwd: string): Promise<DeckApexRun | null> {
  const root = `${cwd}/.claude/output/apex`
  const newest = await newestRun($, root)
  if (newest === undefined) return null
  let parsed: DeckApexRun
  let liveMs: number
  if (newest.context !== undefined) {
    let text: string
    try {
      text = await $.fs.read(`${root}/${newest.dir}/00-context.md`)
    } catch {
      // Vanished between stat and read, or over 4 MiB: nothing shown this round.
      return null
    }
    parsed = parseContext(text, newest.dir)
    liveMs = newest.context
  } else {
    parsed = runFromFiles(newest.dir, newest.files)
    // Only a finish step file: the run ended.
    if (parsed.currentStep === undefined) return null
    liveMs = newest.mtimeMs
  }
  const now = await $.clock.now()
  if (!isLive(parsed, liveMs, now)) return null
  const head = await readHead($, cwd)
  // Without a context file the header names the folder (no branch); hidden on the trunk, live 1 h.
  if (newest.context === undefined && !bareShown(parsed, liveMs, head, now)) return null
  return onBranch(parsed, head) ? { ...parsed, dir: newest.dir } : null
}

// The state library reads and writes named atoms only: one writer per atom, each writing
// only when the value changed.
async function putVerdict($: EngineInterface, value: DeckApexVerdict | null): Promise<void> {
  if (JSON.stringify(await read($, verdict)) === JSON.stringify(value)) return
  await update($, verdict, () => value)
}

async function putBudget($: EngineInterface, value: DeckApexBudget | null): Promise<void> {
  if (JSON.stringify(await read($, budget)) === JSON.stringify(value)) return
  await update($, budget, () => value)
}

// The live steps, or none (an older shape reads as none).
async function getSteps($: EngineInterface): Promise<DeckApexSteps> {
  const s = normalize(NO_STEPS, await read($, apexSteps))
  return { runKey: typeof s.runKey === 'string' ? s.runKey : null, steps: listOf(s.steps), current: s.current ?? null }
}

// One change to the live steps, written only when it changed something. Steps count only while
// a run is live: a Skill(apex) call set the key, else the shown run folder gives it.
async function changeSteps($: EngineInterface, fn: (value: DeckApexSteps, runKey: string) => DeckApexSteps): Promise<void> {
  await record(async () => {
    const current = await getSteps($)
    const runKey = current.runKey ?? (await read($, run))?.dir ?? null
    if (runKey === null) return
    const next = fn(current, runKey)
    if (next !== current) await update($, apexSteps, () => next)
  })
}

async function changeShells($: EngineInterface, fn: (value: DeckApexShell[]) => DeckApexShell[]): Promise<void> {
  const current = await getShells($)
  if (fn(current) === current) return
  await update($, shells, list => fn(listOf<DeckApexShell>(list)))
}

// The run's external verification, from whichever of its two names was written last;
// re-read only when that file's mtime moved.
async function refreshVerdict($: EngineInterface, found: DeckApexRun | null): Promise<void> {
  const dir = found?.dir
  // A session run has no folder: nothing to list.
  if (dir === undefined || isSessionDir(dir)) return putVerdict($, null)
  const runDir = `${await $.session.cwd()}/.claude/output/apex/${dir}`
  let newest: { name: string; mtimeMs: number } | null = null
  try {
    for (const entry of await $.fs.list(runDir)) {
      if (entry.kind !== 'file' || !VERIFY_NAMES.includes(entry.name)) continue
      newest = pickVerdict(newest, { name: entry.name, mtimeMs: entry.mtimeMs })
    }
  } catch {
    // The run directory vanished: no verification to show.
    newest = null
  }
  if (newest === null) return putVerdict($, null)
  const current = await read($, verdict)
  if (current !== null && current.dir === dir && current.mtimeMs === newest.mtimeMs) return
  let next: DeckApexVerdict | null = null
  try {
    const parsed = parseVerdict(await $.fs.read(`${runDir}/${newest.name}`))
    if (parsed !== null) next = { dir, mtimeMs: newest.mtimeMs, ...parsed }
  } catch {
    // Vanished between list and read, or over 4 MiB: shown as pending.
    next = null
  }
  await putVerdict($, next)
}

// The run's correction budget, from the names in ~/.claude/apex-correction-budget (one file
// per round used or granted).
async function refreshBudget($: EngineInterface, found: DeckApexRun | null): Promise<void> {
  const dir = found?.dir
  const home = await $.env.get('HOME')
  if (dir === undefined || isSessionDir(dir) || home === undefined || home === '') return putBudget($, null)
  let names: string[]
  try {
    names = (await $.fs.list(`${home}/.claude/apex-correction-budget`)).map(entry => entry.name)
  } catch {
    // No round was ever claimed on this machine: no budget to show.
    names = []
  }
  await putBudget($, budgetOf(names, dir))
}

// A subagent's still running shells close once it is killed, fails or leaves the agent list:
// their notification would only ever reach that loop. Read only while such a shell runs.
async function snapshotShells($: EngineInterface): Promise<void> {
  const list = await getShells($)
  if (!list.some(s => s.status === 'running' && s.ownerAgentId !== undefined)) return
  const listed = await $.agent.list()
  const owners = listed.map(a => ({ id: a.id, type: a.type, status: a.status }))
  const [cards, a] = await Promise.all([getCards($), getArchitect($)])
  const known = [...cards.map(c => c.id), ...a.ids]
  const at = await $.clock.now()
  await changeShells($, current => closeBySnapshot(current, owners, known, at))
}

// A new run: the finished cards and shells go, the running ones stay; receipt, log, main untouched.
async function clearForNewRun($: EngineInterface): Promise<void> {
  const cards = await getCards($)
  if (clearFinished(cards, []).cards !== cards) {
    await update($, agents, list => clearFinished(listOf<unknown>(list).map(normalizeCard), []).cards)
  }
  await changeShells($, current => clearFinished([], current).shells)
}

// One poll: run (its phase moves to the log), phases, verdict, budget, owned shells.
async function refresh($: EngineInterface): Promise<void> {
  const scanned = await scan($)
  const prev = await read($, run)
  const settled = settleRun(prev, scanned, misses)
  misses = settled.misses
  const found = settled.run
  if (JSON.stringify(prev) !== JSON.stringify(found)) await update($, run, () => found)
  const note = phaseNote(prev, found)
  if (note !== null) await say($, 'apex', note)
  const sw = runSwitch(lastRunDir, found?.dir ?? null)
  lastRunDir = sw.last
  if (sw.isNew) await clearForNewRun($)
  await refreshVerdict($, found)
  await refreshBudget($, found)
  await snapshotShells($)
}

function onTick($: EngineInterface): void {
  if (pollUnderWay !== null && skippedTicks < STUCK_TICKS) {
    skippedTicks += 1
    return
  }
  pollCount += 1
  const mine = pollCount
  pollUnderWay = mine
  skippedTicks = 0
  refresh($)
    .catch(() => {
      // A failed scan or a refused write leaves the figures as they were; the next tick tries again.
    })
    .finally(() => {
      // A poll given up as stuck no longer owns the slot when it settles at last.
      if (pollUnderWay === mine) pollUnderWay = null
    })
}

// One poll now, and the 5 s timer while the pane is open.
function startPolling($: EngineInterface): void {
  if (timer === undefined) timer = $.clock.every(POLL_MS, () => onTick($))
  pollOnce($)
}

function stopPolling(): void {
  timer?.cancel()
  timer = undefined
}

// A single poll (a prompt, a finished main turn): the log's apex lines fill with the pane closed.
function pollOnce($: EngineInterface): void {
  $.clock.after(0, () => onTick($))
}

// Runs `write`; a refused state write leaves the figures as they were (an observer never fails
// the event it watches).
async function record(write: () => Promise<void>): Promise<void> {
  try {
    await write()
  } catch {
    // Figures only: the next step, call or poll writes again.
  }
}

/**
 * The run's live step a tool call stands for: edits from every loop, gate / Codex / ship from the
 * main loop's Bash only. A refused call, or a failed edit, is no step. Called from the one
 * unmatched tool.call observer (the engine allows one per event).
 */
async function noteCallStep($: EngineInterface, e: unknown, ran: { result?: unknown; isError?: boolean }): Promise<void> {
  const isRefused = ran.result === undefined && ran.isError !== true
  const tool = stringField(e, 'tool') ?? ''
  const input = { file_path: stringField(e, 'file_path'), notebook_path: stringField(e, 'notebook_path'), command: stringField(e, 'command') }
  const name = isRefused ? null : classifyCall(tool, input, stringField(e, 'agentId') !== undefined)
  const isFailedEdit = (name === 'edit' || name === 'plan') && ran.isError === true
  if (name === null || isFailedEdit) return
  const codex = name === 'Codex' ? parseCodex(stringField(ran.result, 'stdout') ?? '') : null
  const at = await $.clock.now()
  await changeSteps($, (s, key) => seeStep(s, key, name, at, codex === null ? {} : codex))
}

/** An implementer, test-runner or reviewer started: its step, with what it does and on which model. */
async function noteAgentStep($: EngineInterface, subagentType: string, description: string, agentId: string, model: string): Promise<void> {
  const name = classifyAgent(subagentType)
  if (name === null) return
  const at = await $.clock.now()
  const detail = `${description} (${modelFamily(model)})`
  await changeSteps($, (s, key) => seeStep(s, key, name, at, { agentId, detail }))
}

/** A step's agent ended: a reviewer's verdict is the first one its final text names. */
async function endAgentStep($: EngineInterface, agentId: string, answer: string): Promise<void> {
  const at = await $.clock.now()
  const isReview = (await getSteps($)).steps.some(x => x.agentId === agentId && x.name === 'review')
  const verdict = isReview ? parseReview(answer) : null
  await changeSteps($, s => endAgent(s, agentId, at, verdict))
}

const alertText = (a: DeckApexAlert) =>
  a.kind === 'step'
    ? `✗ step ${a.step} failed`
    : a.kind === 'verify'
      ? `✗ external verify ${a.verdict} · ${plural(a.findings, 'finding')}`
      : `■ correction budget spent · ${a.rounds}/${a.cap} rounds`

/** /deck and its aliases: open (the default), close, reset, layout <auto|compact|wide|mini>. */
async function runCommand($: EngineInterface, args: string) {
  const [verb = 'open', arg = ''] = args.trim().split(/\s+/)
  if (verb === 'close') {
    await $.ui.close({ id: PANE })
    isPaneOpen = false
    stopPolling()
    return { text: 'Deck closed.' }
  }
  if (verb === 'reset') {
    await resetAll($)
    return { text: 'Deck reset.' }
  }
  if (verb === 'layout') {
    const layout: DeckLayout | null = arg === 'compact' || arg === 'wide' || arg === 'auto' || arg === 'mini' ? arg : null
    if (!layout) return { text: 'Usage: /deck layout auto|compact|wide|mini' }
    await update($, view, v => ({ ...normalize(DEFAULT_VIEW, v), layout }))
    const opened = await openPane($)
    return { text: opened.isPlaced ? `Deck layout: ${layout}.` : `Layout set to ${layout}; the pane is not shown yet: ${opened.reason}` }
  }
  const opened = await openPane($)
  if (!opened.isPlaced) return { text: `Deck is not shown yet: ${opened.reason}` }
  return { text: 'Deck opened. Focus it with ctrl+x tab; 1-6 expand cards.' }
}

// ---------------------------------------------------------------- hooks

export const register: Register = (on, options) => {
  const cfg = parseConfig(options)
  const C = PALETTES[cfg.palette]

  on('session.start', async ($, e, next) => {
    // Each command on its own: one refused leaves the others registered.
    try {
      await $.command.register({
        name: 'deck',
        description: 'Deck, the live agent and APEX dashboard: open, close, reset, or set the layout',
        argumentHint: '[open|close|reset|layout auto|compact|wide|mini]',
      })
    } catch {
      // Refused: no /deck this session; the aliases and the observers still run.
    }
    try {
      await $.command.register({ name: 'apex-pane', description: 'Opens the deck pane (alias of /deck)' })
    } catch {
      // Refused: no /apex-pane this session; /deck still opens the pane.
    }
    try {
      await $.command.register({ name: 'task-board', description: 'Opens the deck pane (alias of /deck)' })
    } catch {
      // Refused: no /task-board this session; /deck still opens the pane.
    }
    // A host without usage (headless, an SDK host, a session not yet bound) just starts without it.
    const u = await $.session.usage().catch(() => null)
    if (u) {
      await update($, usage, x => ({
        ...normalize(DEFAULT_USAGE, x),
        pct: u.context.percent ?? null,
        tokens: u.context.tokens ?? null,
        window: u.context.window,
        costUsd: u.cost?.usd ?? null,
        limits: u.rateLimits.map(r => ({ kind: r.kind, pct: r.percentUsed })),
      }))
    }
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    // The next session's first run is no new run.
    lastRunDir = null
    if (e.reason === 'clear') {
      // A /clear starts every figure over; the poll is kept for it.
      misses = 0
      await resetAll($)
    } else {
      isPaneOpen = false
      stopPolling()
    }
    return next(e)
  })

  // The pane closed (its close button, /deck close, another plugin): the 5 s poll stops.
  on('ui.close', async ($, e, next) => {
    const closed = await next(e)
    if (e.id === PANE) {
      isPaneOpen = false
      stopPolling()
    }
    return closed
  })

  on('command.run', { command: 'deck' }, async ($, e) => runCommand($, e.args))
  on('command.run', { command: 'apex-pane' }, async ($, e) => runCommand($, e.args))
  on('command.run', { command: 'task-board' }, async ($, e) => runCommand($, e.args))

  on('prompt.submit', ($, e, next) => {
    pollOnce($)
    return next(e)
  })

  on('classic.UserPromptSubmit', async ($, e, next) => {
    await noteMode($, e.permission_mode)
    return next(e)
  })

  on('agent.offer', async ($, e, next) => {
    const offered = await next(e)
    if (cfg.architect.test(e.agent) || (cfg.matchDescriptions && cfg.architect.test(e.description))) {
      await update($, roster, r => {
        const x = normalize(DEFAULT_ROSTER, r)
        return x.architectTypes.includes(e.agent) ? x : { architectTypes: [...listOf<string>(x.architectTypes), e.agent].slice(-20) }
      })
    }
    return offered
  })

  on('turn.start', async ($, e, next) => {
    const [now, cost] = await Promise.all([$.clock.now(), costNow($)])
    await update($, turn, () => ({ ...DEFAULT_TURN, startedAt: now, costAtStart: cost }))
    await update($, main, m => ({ ...normalize(DEFAULT_MAIN, m), isRunning: true }))
    // A background architect's report reaches the main loop as the text opening this turn. The
    // SubagentHandback tool call (in tool.call) normally carries it first; this is the fallback.
    const back = e.text ? handbackOf(e.text) : null
    const a = back ? await getArchitect($) : null
    if (back && a && a.ids.includes(back.from)) {
      const advice = adviceLine(back.body)
      if (advice && advice !== a.lastAdvice) await noteAdvice($, cfg, advice)
    } else if (e.text) {
      const p = promptLine(e.text)
      await say($, p.who, p.text)
    }
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    // The main loop's model is known when its request starts; a long first request shouldn't read "—".
    if (!e.agentId) {
      await update($, main, m => {
        const x = normalize(DEFAULT_MAIN, m)
        return { ...x, model: e.model, effort: String(e.effort ?? x.effort), steps: x.steps + 1 }
      })
    }
    const result = yield* next(e)
    const id = e.agentId
    if (!id) return result
    const cards = await getCards($)
    if (cards.some(c => c.id === id)) {
      const step = { model: e.model, usage: result.usage, stopReason: result.stopReason }
      await update($, agents, list => listOf<unknown>(list).map(normalizeCard).map(c => (c.id === id ? applyStep(c, step) : c)))
      if (result.stopReason === 'max_tokens') await say($, await whoIs($, id), 'hit max_tokens', 'error', id)
    }
    return result
  })

  on('session.measure', async ($, e, next) => {
    await update($, usage, x => ({
      ...normalize(DEFAULT_USAGE, x),
      pct: e.context.percent ?? null,
      tokens: e.context.tokens ?? null,
      window: e.context.window,
      costUsd: e.cost?.usd ?? null,
      limits: e.rateLimits.map(r => ({ kind: r.kind, pct: r.percentUsed })),
    }))
    return next(e)
  })

  on('session.compact', async ($, e, next) => {
    const done = await next(e)
    if (!e.agentId && e.trigger !== 'precompute') {
      const now = await $.clock.now()
      await update($, usage, x => {
        const u = normalize(DEFAULT_USAGE, x)
        return { ...u, compactions: u.compactions + 1, lastCompactAt: now }
      })
      await say($, 'main', `context compacted (${e.trigger})`)
    }
    return done
  })

  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    await noteCallStep($, e, ran)
    // A refused call carries neither a result nor an error. An inference, not the refusal's own
    // field: a tool that answers with an undefined result would read as refused too (log text only).
    const isRefused = ran.result === undefined && ran.isError !== true
    // A background agent hands its report back through this tool; an architect's report is its advice.
    if (String(e.tool) === 'SubagentHandback') {
      const message = (e as unknown as { message?: unknown }).message
      const a = e.agentId ? await getArchitect($) : null
      if (a && e.agentId && a.ids.includes(e.agentId) && typeof message === 'string') {
        const advice = adviceLine(message)
        if (advice && advice !== a.lastAdvice) await noteAdvice($, cfg, advice)
      }
      return ran
    }
    if (e.tool === 'Agent') return ran
    const hasFailed = !isRefused && ran.isError === true
    const isEdit = !hasFailed && !isRefused && EDIT_TOOLS.has(e.tool)
    const t0 = await getTurn($)
    if (isEdit || hasFailed || (!e.agentId && t0.errorStreak > 0)) {
      await update($, turn, t => afterCall(normalize(DEFAULT_TURN, t), { inSubagent: Boolean(e.agentId), hasFailed, isEdit }))
    }
    const text = shorten(describeInput(e.tool, e), 64)
    if (e.agentId) {
      const id = e.agentId
      await update($, agents, list =>
        listOf<unknown>(list)
          .map(normalizeCard)
          .map(c => (c.id === id ? noteTool(c, { tool: e.tool, text, isError: hasFailed || isRefused }) : c)),
      )
    }
    // The log keeps what is worth a glance: refusals, errors and edits; the rest is on the cards.
    if (isRefused) await say($, await whoIs($, e.agentId), `${text}  refused`, 'error', e.agentId ?? null)
    else if (hasFailed) await say($, await whoIs($, e.agentId), `${text}  ✗`, 'error', e.agentId ?? null)
    else if (isEdit) await say($, await whoIs($, e.agentId), text, 'info', e.agentId ?? null)
    return ran
  })

  // Background shell: run_in_background, or ctrl+B / auto-background, all answer a backgroundTaskId.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const ran = await next(e)
    const id = stringField(ran.result, 'backgroundTaskId')
    if (id !== undefined) {
      await record(async () => {
        const startedAt = await $.clock.now()
        const label = stringField(e, 'description') ?? stringField(e, 'command') ?? 'shell'
        const toolUseId = stringField(e, 'tool_use_id')
        // Set only inside a subagent loop: its shells close with it.
        const ownerAgentId = stringField(e, 'agentId')
        await changeShells($, current =>
          addShell(current, {
            id,
            label,
            startedAt,
            ...(toolUseId === undefined ? {} : { toolUseId }),
            ...(ownerAgentId === undefined ? {} : { ownerAgentId }),
          }),
        )
      })
    }
    return ran
  }).catch(($, e, next) => next(e))

  // A main-loop Skill(apex) call that ran: a run without a folder (yet), a new run once any run
  // was seen. A subagent's call, another skill, a failed or refused call: nothing.
  on('tool.call', { tool: 'Skill' }, async ($, e, next) => {
    const ran = await next(e)
    if (stringField(e, 'skill') === 'apex' && !e.agentId && ran.isError !== true && ran.result !== undefined) {
      await record(async () => {
        const now = await $.clock.now()
        const sw = callSwitch(lastRunDir, sessionKey(now))
        lastRunDir = sw.last
        if (sw.isNew) await clearForNewRun($)
        await update($, sessionRun, () => ({ startedAt: now, lastAt: now, args: shorten(stringField(e, 'args') ?? '', 40) }))
        // Each call starts the run's live steps over, keyed as the session run.
        await update($, apexSteps, () => startSteps(sessionKey(now)))
      })
      pollOnce($)
    }
    return ran
  }).catch(($, e, next) => next(e))

  // A shell stopped by TaskStop gets no notification row: closed as killed. TaskStop also stops
  // agents; stopShell leaves those alone.
  on('tool.call', { tool: 'TaskStop' }, async ($, e, next) => {
    const ran = await next(e)
    if (ran.isError !== true && ran.result !== undefined) {
      const id = stringField(ran.result, 'task_id') ?? stringField(e, 'task_id') ?? stringField(e, 'shell_id')
      if (id !== undefined) {
        await record(async () => {
          const at = await $.clock.now()
          await changeShells($, current => stopShell(current, id, at))
        })
      }
    }
    return ran
  }).catch(($, e, next) => next(e))

  // A background shell's notification row: the one completion signal a shell has. A render hook
  // never writes state, so the write is deferred to a timer; the row itself is drawn unchanged.
  on('ui.render', { component: 'UserMessage', props: { origin: { kind: 'task-notification' } } }, ($, e, next) => {
    const task: unknown = e.props.task
    const note: Notification = {}
    const id = stringField(task, 'id')
    const toolUseId = stringField(task, 'toolUseId')
    const status = stringField(task, 'status')
    const durationMs = numberField(task, 'durationMs')
    if (id !== undefined) note.id = id
    if (toolUseId !== undefined) note.toolUseId = toolUseId
    if (status !== undefined) note.status = status
    if (durationMs !== undefined) note.durationMs = durationMs
    if (note.status !== undefined) {
      $.clock.after(0, () => {
        $.clock
          .now()
          .then(at => changeShells($, current => finishByNotification(current, note, at)))
          .catch(() => {
            // State refused: the shell stays running until its owner's end or a later redraw.
          })
      })
    }
    return next(e)
  })

  // A server-side review tool never reaches tool.call: it shows only in the assistant's rows.
  // A subagent's shell notifies that subagent's loop only: its row never reaches the main
  // transcript, so it is read here. Read before next: the row is relayed unchanged.
  on('session.append', async ($, e, next) => {
    const agentId = e.agentId
    if (agentId !== undefined && agentId !== '' && e.origin.kind === 'task-notification') {
      const notes = parseTaskNotifications(rowText(e.message.content))
      if (notes.length > 0) {
        await record(async () => {
          const at = await $.clock.now()
          await changeShells($, current => notes.reduce((list, note) => finishByNotification(list, note, at), current))
        })
      }
    }
    if (!e.agentId && e.message.type === 'assistant') {
      const a = await getArchitect($)
      // Consults this row opened: their result may be in the same row, after the stale read above.
      const opened = new Set<string>()
      for (const block of e.message.content as unknown as readonly ServerBlock[]) {
        if (block.type === 'server_tool_use' && block.name && block.id && cfg.architect.test(block.name)) {
          if (a.seen.includes(block.id)) continue
          const id = block.id
          await update($, architect, x => {
            const y = normalize(DEFAULT_ARCHITECT, x)
            return { ...y, seen: [...listOf<string>(y.seen), id].slice(-60) }
          })
          opened.add(id)
          await consultStarted($, cfg, id, `${block.name} tool`)
        } else if (block.type.endsWith('_tool_result') && block.tool_use_id) {
          const id = block.tool_use_id
          const isOpen = opened.has(id) || (await getArchitect($)).consults.some(c => c.id === id && c.endAt === null)
          if (isOpen) await consultEnded($, cfg, null, id)
        }
      }
    }
    return next(e)
  })

  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
    if (!e.parentAgentId) await noteMode($, e.permissionMode)
    if (!started.agentId) return started
    const id = started.agentId
    await noteAgentStep($, e.subagentType, e.description, id, started.model)
    if (await isArchitectType($, cfg, e.subagentType)) {
      await update($, architect, a => {
        const x = normalize(DEFAULT_ARCHITECT, a)
        return { ...x, ids: [...listOf<string>(x.ids), id].slice(-40) }
      })
      await consultStarted($, cfg, id, e.subagentType.split(':').pop() ?? 'agent')
      return started
    }
    const card: DeckAgentCard = {
      ...normalizeCard({}),
      id,
      type: e.name ?? e.subagentType,
      model: started.model,
      description: e.description,
      spawnedAt: await $.clock.now(),
    }
    await update($, agents, list => [...listOf<unknown>(list).map(normalizeCard), card].slice(-24))
    await say($, shorten(cardTitle(card), 12), `spawned · ${card.type}`, 'info', id)
    return started
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    const id = e.agentId
    const now = await $.clock.now()
    if (!id) {
      const [t, cards, cost] = await Promise.all([getTurn($), getCards($), costNow($)])
      const r = receiptOf(t, {
        durationMs: e.durationMs,
        agentsSince: cards.filter(c => c.spawnedAt >= t.startedAt).length,
        costNow: cost,
        reason: e.reason,
      })
      await update($, receipt, () => r)
      await update($, main, m => ({ ...normalize(DEFAULT_MAIN, m), isRunning: false }))
      pollOnce($)
      return done
    }
    // Any subagent, the architect too: its still running shells could only ever notify it.
    await record(() => changeShells($, current => shellsAfterTurn(current, id, e.reason, now)))
    await endAgentStep($, id, e.answer)
    if ((await getArchitect($)).ids.includes(id)) {
      await consultEnded($, cfg, e.answer, id)
      return done
    }
    const cards = await getCards($)
    if (cards.some(c => c.id === id)) {
      const status = e.reason === 'answer' ? 'done' : e.reason === 'aborted' ? 'stopped' : 'failed'
      await update($, agents, list =>
        listOf<unknown>(list)
          .map(normalizeCard)
          .map(c => (c.id === id ? { ...c, status, endedAt: now, answer: shorten(e.answer, 400) } : c)),
      )
      const card = cards.find(c => c.id === id)
      const took = card ? fmtDuration(now - card.spawnedAt) : ''
      await say($, await whoIs($, id), status === 'done' ? `done · ${took}` : status, status === 'done' ? 'done' : 'error', id)
    }
    return done
  })

  // ---------------------------------------------------------------- drawing

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    // Drawn means open (a hot reload forgets the flag; the surface does not): polled while it is.
    if (!isPaneOpen) {
      isPaneOpen = true
      startPolling($)
    }
    const els = $.ui.resolve(e)
    const { Box, Text, Button } = els
    // Clients draw on terminal and desktop only; elsewhere the same frame as static text.
    const hasClient = 'Client' in els && (e.surface === 'terminal' || e.surface === 'desktop')
    const [m, u, a, cards, lines, t, r, v, apexRun, st, sr, vd, bg, sh, now] = await Promise.all([
      getMain($),
      getUsage($),
      getArchitect($),
      getCards($),
      getLog($),
      getTurn($),
      read($, receipt),
      getView($),
      read($, run),
      getSteps($),
      getSessionRun($),
      read($, verdict),
      read($, budget),
      getShells($),
      $.clock.now(),
    ])
    const W = Math.max(40, e.props.bodyColumns)
    const layout = v.layout ?? cfg.layout
    const isWide = layout === 'wide' || (layout === 'auto' && W >= 110)
    const colW = isWide ? Math.floor((W - 2) / 2) : W
    const modelName = prettyModel(m.model)
    const viewed = e.props.view?.agentId ?? null
    const advising = isAdvising(a)
    const running = cards.filter(c => c.status === 'running')
    const showArchitect = a.consults.length > 0 || a.ids.length > 0
    const motion = cfg.motion && hasClient
    // A panel with nothing to show yet takes no room: most sessions never spawn an agent.
    const isEmpty: Record<Panel, boolean> = {
      main: false,
      architect: !showArchitect,
      agents: cards.length === 0,
      receipt: !m.isRunning && !r,
      log: false,
    }
    const panels = cfg.panels.filter(p => !isEmpty[p])

    // A connector between panels: animated while its flow is live, a dim line otherwise.
    const rail = (key: string, active: boolean, color: string, width: number, marks: number[] = [], isMerge = false) =>
      motion ? (
        <els.Client
          key={key}
          module="./rail.tsx"
          width={width}
          height={1}
          props={{ active, width, color, dim: C.faint, marks, isMerge }}
        />
      ) : (
        <Text color={C.faint}>{'─'.repeat(Math.max(1, width))}</Text>
      )

    // A start time of 0 is unknown (state saved before it was recorded): no clock, not decades.
    const clock = (key: string, since: number, endAt: number | null, color: string) =>
      since <= 0 ? (
        <Text color={color}>—</Text>
      ) : hasClient ? (
        <els.Client key={key} module="./elapsed.tsx" props={{ since, now, endAt, color }} />
      ) : (
        <Text color={color}>{fmtTimer((endAt ?? now) - since)}</Text>
      )

    // ---- APEX: drawn only while a run is live, first and full width
    const alerts = alertsOf(apexRun, vd, bg)
    const shellsRunning = runningShells(sh)
    const doneShells = sh.filter(s => s.status !== 'running')
    const shownShells = [...sh.filter(s => s.status === 'running'), ...doneShells.slice(0, DONE_SHELLS)]
    const hiddenShells = sh.length - shownShells.length
    const markColor: Record<StepMark, string> = { done: C.apex, current: C.apex, pending: C.dim }
    const shellMark = (s: DeckApexShell) =>
      s.status === 'running'
        ? { glyph: '◐', color: C.agent }
        : s.status === 'completed'
          ? { glyph: '✓', color: C.ok }
          : s.status === 'failed'
            ? { glyph: '✗', color: C.warn }
            : { glyph: '■', color: C.dim }
    // A shell's row: mark, label, live duration (frozen once ended), status.
    const shellRow = (s: DeckApexShell, w: number) => {
      const sm = shellMark(s)
      return (
        <Box>
          <Text color={sm.color}>{`${sm.glyph} `}</Text>
          <Box width={Math.max(10, w - 24)}>
            <Text wrap="truncate">{s.label}</Text>
          </Box>
          <Text> </Text>
          <Box flexShrink={0}>{clock(`shell-clock-${s.id}`, s.startedAt, s.endedAt ?? null, C.dim)}</Box>
          <Text color={sm.color}>{` ${s.status}`}</Text>
        </Box>
      )
    }
    // The call clock and the task belong to the run the last Skill(apex) call started.
    const callRun = sr !== null && st.runKey === sessionKey(sr.startedAt) ? sr : null
    const cells = stepCells(st)
    const detail = stepDetail(st)
    const cellText = (c: StepCell) => (
      <Text color={c.isWarn ? C.warn : markColor[c.mark]} bold={c.mark === 'current'}>
        {`${PHASE_GLYPH[c.mark]} ${c.label}`}
      </Text>
    )
    // The live steps on one row (a separator Text between them, so each step reads on its own).
    const stepRow = () => cells.flatMap((c, i) => (i === 0 ? [cellText(c)] : [<Text>{'  '}</Text>, cellText(c)]))
    // `APEX · <branch> · <tier>`, then the time since the Skill(apex) call.
    const headerRow = (run: DeckApexRun) => (
      <Box>
        <Box flexShrink={1}>
          <Text color={C.apex} bold wrap="truncate">
            {apexHeader(run)}
          </Text>
        </Box>
        {callRun !== null ? <Text color={C.apex}>{' · '}</Text> : null}
        {callRun !== null ? <Box flexShrink={0}>{clock('apex-clock', callRun.startedAt, null, C.apex)}</Box> : null}
      </Box>
    )
    const taskRow =
      callRun !== null && callRun.args !== '' ? (
        <Text color={C.dim} wrap="truncate">
          {callRun.args}
        </Text>
      ) : null
    // The current step's agent (with its live clock) or verdict.
    const detailRow =
      detail === null ? null : (
        <Box>
          <Text color={markColor[detail.mark]} wrap="truncate">
            {`${PHASE_GLYPH[detail.mark]} ${detail.text}${detail.since !== undefined ? ' ' : ''}`}
          </Text>
          {detail.since !== undefined ? <Box flexShrink={0}>{clock('step-clock', detail.since, null, C.dim)}</Box> : null}
        </Box>
      )
    const apexBlock = (w: number) => {
      if (apexRun === null) return null
      return (
        <Box flexDirection="column" width={w}>
          <Box flexDirection="column" borderStyle="round" borderColor={C.apex} paddingX={1} width={w}>
            {headerRow(apexRun)}
            {taskRow}
            <Box flexWrap="wrap" columnGap={2}>
              {cells.map(cellText)}
            </Box>
            {detailRow}
            {alerts.map(al => (
              <Text color={C.warn} bold wrap="truncate">
                {alertText(al)}
              </Text>
            ))}
            {shownShells.map(s => shellRow(s, w))}
            {hiddenShells > 0 ? <Text color={C.faint}>{`+${hiddenShells} earlier shells`}</Text> : null}
          </Box>
          {rail('apex-link', m.isRunning || shellsRunning > 0, C.apex, w)}
        </Box>
      )
    }
    const apexRows =
      apexRun === null
        ? 0
        : 2 + 1 + (taskRow === null ? 0 : 1) + 1 + (detailRow === null ? 0 : 1) + alerts.length + shownShells.length + (hiddenShells > 0 ? 1 : 0) + 1

    // ---- main
    const effortN = { low: 1, medium: 2, high: 3, xhigh: 4, max: 4 }[m.effort] ?? 0
    const ctxGauge = u.pct !== null ? gauge(u.pct, 10) : null
    const mainPanel = (w: number) => (
      <Box flexDirection="column" borderStyle="round" borderColor={C.main} paddingX={1} width={w}>
        <Box justifyContent="space-between">
          <Text color={C.main} bold>
            {modelName} · main
          </Text>
          <Text color={m.isRunning ? C.main : C.dim}>{m.isRunning ? '● working' : '○ idle'}</Text>
        </Box>
        <Text wrap="truncate">
          <Text dimColor>effort </Text>
          <Text color={C.main}>{'▮'.repeat(effortN) + '▯'.repeat(4 - effortN)} </Text>
          <Text color={C.main} bold>
            {m.effort || '—'}
          </Text>
          {m.mode ? <Text dimColor>{`   mode ${m.mode}`}</Text> : null}
          <Text dimColor>{`   ${m.steps} req`}</Text>
        </Text>
        {ctxGauge ? (
          <Text wrap="truncate">
            <Text dimColor>ctx </Text>
            <Text color={u.pct !== null && u.pct >= 80 ? C.warn : C.main}>{ctxGauge.on}</Text>
            <Text color={C.faint}>{ctxGauge.off}</Text>
            <Text bold>{` ${Math.round(u.pct ?? 0)}%`}</Text>
            {u.tokens !== null ? <Text dimColor>{` ${kTokens(u.tokens)}/${kTokens(u.window)}`}</Text> : null}
            {u.compactions > 0 ? <Text color={C.amber}>{`  ⟲${u.compactions}`}</Text> : null}
          </Text>
        ) : null}
        {u.costUsd !== null || u.limits.length > 0 ? (
          <Text wrap="truncate">
            {u.costUsd !== null ? <Text color={C.text}>{`${fmtUsd(u.costUsd)}   `}</Text> : null}
            {u.limits.slice(0, 2).map(l => {
              const lg = gauge(l.pct, 5)
              return (
                <Text wrap="truncate">
                  <Text dimColor>{`${limitLabel(l.kind)} `}</Text>
                  <Text color={l.pct >= 80 ? C.warn : C.main}>{lg.on}</Text>
                  <Text color={C.faint}>{lg.off}</Text>
                  <Text dimColor>{` ${Math.round(l.pct)}%  `}</Text>
                </Text>
              )
            })}
          </Text>
        ) : null}
      </Box>
    )

    // ---- architect
    const lastConsult = a.consults[a.consults.length - 1]
    const architectPanel = (w: number) => {
      const tl = consultTimeline(a, now, Math.max(8, w - 4))
      return (
        <Box flexDirection="column" borderStyle="round" borderColor={C.arch} paddingX={1} width={w}>
          <Box justifyContent="space-between">
            <Text color={C.arch} bold>
              {cfg.architectLabel} · {advising ? 'advising' : 'on call'}
            </Text>
            <Text>
              <Text dimColor>consults </Text>
              <Text color={C.arch} bold>
                {a.consults.length}
              </Text>
            </Text>
          </Box>
          <Text color={C.arch}>{tl}</Text>
          {lastConsult ? (
            <Text dimColor wrap="truncate">
              {advising
                ? `consulting since ${fmtClock(lastConsult.at)}`
                : `last ${fmtDuration(now - (lastConsult.endAt ?? lastConsult.at))} ago · took ${fmtDuration((lastConsult.endAt ?? now) - lastConsult.at)}`}
            </Text>
          ) : (
            <Text dimColor>not consulted yet</Text>
          )}
          {cfg.moments ? (
            <Box flexWrap="wrap" columnGap={2}>
              {(['before a plan', 'error repeats', 'before done'] as const).map(mo => {
                const isOn = lastConsult?.moment === mo
                return (
                  <Text color={isOn ? C.arch : C.dim} bold={isOn}>
                    {isOn ? '◆' : '◇'} {mo}
                  </Text>
                )
              })}
              <Text color={C.faint}>(inferred)</Text>
            </Box>
          ) : null}
          {a.lastAdvice ? (
            <Text color={C.arch} wrap="truncate">
              » {a.lastAdvice}
            </Text>
          ) : null}
        </Box>
      )
    }

    // ---- agents: cards up to the limit, swimlanes beyond it
    const statusColor = (c: DeckAgentCard) => (c.status === 'failed' ? C.warn : c.status === 'done' ? C.ok : C.agent)
    const glyph = (c: DeckAgentCard) => (c.status === 'running' ? '◐' : c.status === 'done' ? '✓' : c.status === 'failed' ? '✗' : '■')
    const expandOnPress = (id: string) => () =>
      update($, view, x => ({ ...normalize(DEFAULT_VIEW, x), expanded: normalize(DEFAULT_VIEW, x).expanded === id ? null : id }))

    const agentsPanel = (w: number) => {
      // Cards need 20 columns each; when the pane can't hold the limit, lanes take over.
      const fit = Math.max(1, Math.min(cfg.maxCards, Math.floor((w + 1) / 21)))
      const useLanes = cards.length > fit
      const header = (
        <Box justifyContent="space-between" width={w}>
          <Text bold>{`agents · ${running.length} running · ${cards.length} total`}</Text>
          {cards.length > 0 ? <Text color={C.faint}>1-{Math.min(cards.length, useLanes ? 6 : fit)} expand</Text> : null}
        </Box>
      )
      if (cards.length === 0) {
        return (
          <Box flexDirection="column" width={w}>
            {header}
            <Text color={C.faint}>no subagents yet</Text>
          </Box>
        )
      }
      if (useLanes) {
        const shown = cards.slice(-6)
        const barW = Math.max(8, w - 28)
        const geo = lanes(shown, now, barW)
        return (
          <Box flexDirection="column" width={w}>
            {header}
            {cards.length > shown.length ? <Text color={C.faint}>{`+${cards.length - shown.length} earlier`}</Text> : null}
            {shown.map((c, i) => {
              const gm = geo[i]
              const isViewed = viewed === c.id
              return (
                <Box>
                  <Text color={statusColor(c)} bold={isViewed}>{`${isViewed ? '▶' : glyph(c)} `}</Text>
                  <Box width={17}>
                    <Button key={`card-${c.id}`} plain hotkey={String(i + 1)} label={shorten(cardTitle(c), 14)} onPress={expandOnPress(c.id)} />
                  </Box>
                  <Text color={C.faint}>{' ' + '·'.repeat(gm?.before ?? 0)}</Text>
                  <Text color={statusColor(c)}>{'━'.repeat(gm?.bar ?? 1)}</Text>
                  <Text color={C.faint}>{'·'.repeat(gm?.after ?? 0) + ' '}</Text>
                  {clock(`lane-clock-${c.id}`, c.spawnedAt, c.endedAt, C.dim)}
                </Box>
              )
            })}
          </Box>
        )
      }
      const shown = cards.slice(-fit)
      const cardW = Math.max(20, Math.floor((w - (shown.length - 1)) / shown.length))
      const centers = shown.map((_, i) => i * (cardW + 1) + Math.floor(cardW / 2))
      return (
        <Box flexDirection="column" width={w}>
          {header}
          {rail('fan-out', running.length > 0, C.agent, w, centers)}
          <Box columnGap={1}>
            {shown.map((c, i) => {
              const isViewed = viewed === c.id
              const sameModel = !c.model || prettyModel(c.model) === modelName
              return (
                <Box
                  flexDirection="column"
                  borderStyle={isViewed ? 'double' : 'round'}
                  borderColor={c.lastStop === 'max_tokens' ? C.warn : C.agent}
                  borderDimColor={c.status !== 'running' && !isViewed}
                  width={cardW}
                  paddingX={1}
                >
                  <Button key={`card-${c.id}`} plain hotkey={String(i + 1)} label={titleLines(cardTitle(c), cardW - 7, cardW - 4)[0]} onPress={expandOnPress(c.id)} />
                  <Text bold wrap="truncate">
                    {titleLines(cardTitle(c), cardW - 7, cardW - 4)[1]}
                  </Text>
                  <Text color={C.dim} wrap="truncate">
                    {sameModel ? c.type : `${c.type} · ${prettyModel(c.model)}`}
                  </Text>
                  <Text dimColor wrap="truncate">
                    {c.steps > 0 ? `ctx ${kTokens(c.ctx)} · out ${kTokens(c.out)} · ${c.steps} st` : 'starting…'}
                  </Text>
                  <Box>
                    <Text color={c.lastStop === 'max_tokens' ? C.warn : statusColor(c)}>
                      {cardW >= 26 ? `${glyph(c)} ${c.lastStop === 'max_tokens' ? 'max_tokens' : c.status} ` : `${glyph(c)} `}
                    </Text>
                    <Box flexShrink={0}>{clock(`card-clock-${c.id}`, c.spawnedAt, c.endedAt, C.dim)}</Box>
                  </Box>
                </Box>
              )
            })}
          </Box>
          {rail('merge', running.length > 0, C.agent, w, centers, true)}
        </Box>
      )
    }

    const expandedCard = cards.find(c => c.id === v.expanded)
    const expandedPanel = (w: number) =>
      expandedCard ? (
        <Box flexDirection="column" borderStyle="single" borderColor={C.agent} paddingX={1} width={w}>
          <Text bold wrap="wrap">
            {expandedCard.description || expandedCard.type}
          </Text>
          <Text dimColor wrap="truncate">{`${expandedCard.type} · ${prettyModel(expandedCard.model)} · ${expandedCard.status} · ${expandedCard.steps} steps`}</Text>
          {expandedCard.tools.length === 0 ? <Text color={C.faint}>no tool calls yet</Text> : null}
          {expandedCard.tools.map(n => (
            <Text color={n.isError ? C.warn : C.text} wrap="truncate">
              {`${n.isError ? '✗' : '·'} ${n.text}`}
            </Text>
          ))}
          {expandedCard.answer ? (
            <Text dimColor wrap="wrap">
              {`» ${shorten(expandedCard.answer, 240)}`}
            </Text>
          ) : null}
        </Box>
      ) : null

    // ---- receipt: the turn now, or the last one
    const receiptPanel = (w: number) => {
      const isReview = t.isReviewing
      return (
        <Box flexDirection="column" borderStyle="round" borderColor={C.main} borderDimColor={!m.isRunning && !isReview} paddingX={1} width={w}>
          {m.isRunning ? (
            <Box>
              <Text color={C.main} wrap="truncate">{`◐ back to ${modelName.toLowerCase()} · turn `}</Text>
              <Box flexShrink={0}>{clock('turn-clock', t.startedAt, null, C.main)}</Box>
              {w >= 60 ? <Text dimColor wrap="truncate">{` · ${plural(t.edits, 'edit')} · ${plural(t.errors, 'error')}`}</Text> : null}
            </Box>
          ) : r ? (
            <Text wrap="truncate">
              <Text color={r.reason === 'answer' ? C.ok : C.warn}>{r.reason === 'answer' ? '✓ ' : '✗ '}</Text>
              <Text>{`last turn ${fmtDuration(r.durationMs)} · ${plural(r.agents, 'agent')} · ${plural(r.edits, 'edit')} · ${plural(r.errors, 'error')}`}</Text>
              {r.costDelta !== null ? <Text color={C.main}>{` · +${fmtUsd(r.costDelta)}`}</Text> : null}
            </Text>
          ) : (
            <Text color={C.faint}>no turn finished yet</Text>
          )}
          {isReview ? <Text color={C.arch}>{`${cfg.architectLabel.toLowerCase()} reviewing before done (inferred)`}</Text> : null}
        </Box>
      )
    }

    // ---- log: whatever rows the other panels leave, 4 to 8
    const used = 2 + apexRows + 5 + (showArchitect ? 6 : 0) + (cards.length > cfg.maxCards ? 3 + Math.min(6, cards.length) : 8) + (expandedCard ? 8 : 0) + 3
    const bodyRows = e.props.scroll?.bodyRows ?? e.viewport?.rows ?? 40
    const nLog = logRows(bodyRows, used)
    const shownLines = (viewed ? lines.filter(l => l.agentId === viewed) : lines).slice(-nLog)
    const colorOf = (l: DeckLogLine) =>
      l.kind === 'error'
        ? C.warn
        : l.kind === 'consult'
          ? C.arch
          : l.who === 'apex'
            ? C.apex
            : l.who === 'main'
              ? C.main
              : l.who === 'you'
                ? C.text
                : C.agent
    const logPanel = (w: number) => (
      <Box flexDirection="column" borderStyle="round" borderColor={C.faint} paddingX={1} width={w}>
        <Text dimColor>{viewed ? 'session log · this agent' : 'session log'}</Text>
        {shownLines.length === 0 ? <Text color={C.faint}>nothing yet</Text> : null}
        {shownLines.map(l => (
          <Box>
            <Box width={9} flexShrink={0}>
              <Text color={C.faint}>{fmtClock(l.at)}</Text>
            </Box>
            <Box width={13} flexShrink={0}>
              <Text color={colorOf(l)} bold wrap="truncate">
                {l.who}
              </Text>
            </Box>
            <Text color={l.kind === 'error' ? C.warn : C.text} wrap="truncate">
              {l.text}
            </Text>
          </Box>
        ))}
      </Box>
    )

    const draw = (p: Panel, w: number) =>
      p === 'main' ? mainPanel(w) : p === 'architect' ? architectPanel(w) : p === 'agents' ? agentsPanel(w) : p === 'receipt' ? receiptPanel(w) : logPanel(w)

    // Panels with the flow between them; the agents panel draws its own rails.
    const column = (ps: Panel[], w: number) => (
      <Box flexDirection="column" width={w}>
        {ps.map((p, i) => {
          const prev = ps[i - 1]
          const link =
            i === 0 || p === 'agents' || prev === 'agents' || p === 'log'
              ? null
              : rail(`link-${p}`, p === 'architect' ? advising : m.isRunning, p === 'architect' ? C.arch : C.main, w)
          return (
            <Box flexDirection="column">
              {link}
              {draw(p, w)}
              {p === 'agents' ? expandedPanel(w) : null}
            </Box>
          )
        })}
      </Box>
    )

    // Desktop draws the agents' time axis as SVG under the panels.
    const svgLanes =
      e.surface !== 'terminal' && cards.length > 0
        ? (() => {
            const { Svg } = $.ui.resolve(e)
            const rowH = 18
            const pxW = 520
            const geo = lanes(cards.slice(-10), now, 100)
            const rects = cards
              .slice(-10)
              .map((c, i) => {
                const gm = geo[i]
                const x = 150 + ((gm?.before ?? 0) / 100) * (pxW - 160)
                const wpx = Math.max(3, ((gm?.bar ?? 1) / 100) * (pxW - 160))
                const fill = c.status === 'running' ? SVG_COLORS.running : c.status === 'done' ? SVG_COLORS.done : c.status === 'failed' ? SVG_COLORS.failed : SVG_COLORS.other
                const label = shorten(cardTitle(c), 22).replace(/[<&>]/g, '')
                return `<text x="4" y="${i * rowH + 13}" font-size="11" fill="${SVG_COLORS.label}">${label}</text><rect x="${x}" y="${i * rowH + 4}" width="${wpx}" height="10" rx="3" fill="${fill}"/>`
              })
              .join('')
            const svgH = Math.min(10, cards.length) * rowH + 4
            return (
              <Svg
                source={`<svg xmlns="http://www.w3.org/2000/svg" width="${pxW}" height="${svgH}" viewBox="0 0 ${pxW} ${svgH}">${rects}</svg>`}
                alt={`${cards.length} agents on a time axis`}
                width={pxW}
                height={svgH}
              />
            )
          })()
        : null

    // Inline above the prompt (the terminal's main screen), the pane is a summary of at most 8 rows.
    const isMini = layout === 'mini' || (layout === 'auto' && e.props.placement === 'inline')
    if (isMini) {
      const MINI_ROWS = 8
      const mg = u.pct !== null ? gauge(u.pct, 6) : null
      // While a run is live it takes its rows first: header, task, step row, its detail, each
      // alert, the running shells; the agents and the receipt get what is left of the 8.
      const apexMini =
        apexRun === null
          ? []
          : [
              headerRow(apexRun),
              ...(taskRow === null ? [] : [taskRow]),
              <Text wrap="truncate">{stepRow()}</Text>,
              ...(detailRow === null ? [] : [detailRow]),
              ...alerts.map(al => (
                <Text color={C.warn} bold wrap="truncate">
                  {alertText(al)}
                </Text>
              )),
              ...sh.filter(s => s.status === 'running').map(s => shellRow(s, W)),
            ].slice(0, MINI_ROWS - 1)
      const room = MINI_ROWS - 1 - apexMini.length
      const ordered = [...cards.filter(c => c.status === 'running'), ...cards.filter(c => c.status !== 'running').reverse()]
      let nLive = Math.min(3, cards.length, room)
      // Agents left out: their « +N more » row takes the last slot.
      if (cards.length > nLive && nLive > 0 && nLive === room) nLive -= 1
      const live = ordered.slice(0, nLive)
      const showMore = cards.length > live.length && room > live.length
      const showReceipt = !m.isRunning && r !== null && room - live.length - (showMore ? 1 : 0) > 0
      return (
        <Box flexDirection="column" width={W}>
          <Text wrap="truncate">
            <Text color={C.main} bold>
              {modelName}
            </Text>
            <Text color={m.isRunning ? C.main : C.dim}>{m.isRunning ? ' ● working' : ' ○ idle'}</Text>
            {mg ? <Text dimColor> · ctx </Text> : null}
            {mg ? <Text color={(u.pct ?? 0) >= 80 ? C.warn : C.main}>{mg.on}</Text> : null}
            {mg ? <Text color={C.faint}>{mg.off}</Text> : null}
            {mg ? <Text>{` ${Math.round(u.pct ?? 0)}%`}</Text> : null}
            {u.compactions > 0 ? <Text color={C.amber}>{` ⟲${u.compactions}`}</Text> : null}
            {u.costUsd !== null ? <Text dimColor>{` · ${fmtUsd(u.costUsd)}`}</Text> : null}
            {showArchitect ? <Text color={C.arch}>{` · ${cfg.architectLabel.toLowerCase()} ${advising ? 'advising' : a.consults.length}`}</Text> : null}
          </Text>
          {apexMini}
          {live.map(c => (
            <Box>
              <Text color={statusColor(c)}>{`${glyph(c)} `}</Text>
              <Box width={Math.max(10, W - 30)}>
                <Text wrap="truncate">{cardTitle(c)}</Text>
              </Box>
              <Text dimColor>{c.steps > 0 ? ` ctx ${kTokens(c.ctx)} ` : ' '}</Text>
              {clock(`mini-clock-${c.id}`, c.spawnedAt, c.endedAt, C.dim)}
            </Box>
          ))}
          {showMore ? (
            <Text color={C.faint} wrap="truncate">{`+${cards.length - live.length} more agents · /deck layout compact for all`}</Text>
          ) : null}
          {showReceipt && r ? (
            <Text dimColor wrap="truncate">
              {`last turn ${fmtDuration(r.durationMs)} · ${plural(r.agents, 'agent')} · ${plural(r.edits, 'edit')} · ${plural(r.errors, 'error')}${r.costDelta !== null ? ` · +${fmtUsd(r.costDelta)}` : ''}`}
            </Text>
          ) : null}
        </Box>
      )
    }

    const legend = fitLegend(
      [
        ...(apexRun !== null ? [{ label: 'apex', color: C.apex }] : []),
        { label: 'main', color: C.main },
        { label: 'agents', color: C.agent },
        ...(showArchitect ? [{ label: cfg.architectLabel.toLowerCase(), color: C.arch }] : []),
      ],
      W,
    )

    const body = isWide ? (
      <Box flexDirection="column">
        <Box columnGap={2}>
          {column(panels.filter(p => p === 'main' || p === 'architect'), colW)}
          {column(panels.filter(p => p === 'agents' || p === 'receipt'), colW)}
        </Box>
        {panels.includes('log') ? logPanel(W) : null}
      </Box>
    ) : (
      column(panels, W)
    )

    return (
      <Box flexDirection="column" width={W}>
        <Box justifyContent="center">
          <Text bold wrap="truncate">
            <Text>DECK</Text>
            <Text color={C.dim}> · </Text>
            <Text color={C.main}>{modelName.toUpperCase()}</Text>
            <Text>{m.isRunning ? ' WORKS' : ' IDLE'}</Text>
            {showArchitect ? <Text color={C.dim}> · </Text> : null}
            {showArchitect ? <Text color={C.arch}>{cfg.architectLabel}</Text> : null}
            {showArchitect ? <Text>{advising ? ' ADVISING' : ' ON CALL'}</Text> : null}
          </Text>
        </Box>
        <Box justifyContent="center" columnGap={2}>
          {legend.map(l => (
            <Text>
              <Text color={l.color}>■</Text>
              <Text dimColor>{` ${l.label}`}</Text>
            </Text>
          ))}
        </Box>
        {apexBlock(W)}
        {body}
        {svgLanes}
      </Box>
    )
  })
}
