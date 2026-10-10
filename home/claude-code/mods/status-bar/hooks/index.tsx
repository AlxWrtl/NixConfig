// status-bar: the session's status under the prompt, in place of the
// command status line: model, folder, git branch, the last response's
// tokens in/out, the context bar (against the auto-compact window) and the 5h / 7d quota bars with their
// reset countdowns. Drawn on the PromptHint line, one row when it fits the
// width, else two; the engine's own hint line (`? for shortcuts`, `esc to
// interrupt`, its pills) stays drawn beneath, live.
// Observes only: turn.step, turn.complete and session.measure hooks return
// next(e)'s result unchanged. Read-only: the branch is read from .git/HEAD.

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, TextProps, Timer } from 'claude-code'

import type { StatusBarLimit, StatusBarStep, StatusBarUsage } from '../types'
import { contextFill, layout, parentDir, parseHead, pickModel, resolveGitdir } from './format.ts'
import type { Seg } from './format.ts'

// Reset countdowns move by the minute.
const TICK_MS = 60_000
// Folders walked up from the working directory to find `.git`.
const MAX_DEPTH = 64

const NO_USAGE: StatusBarUsage = { contextPercent: null, contextTokens: null, limits: [] }

const usage = atom({ plugin: 'status-bar', key: 'usage' } as const, NO_USAGE)
const step = atom({ plugin: 'status-bar', key: 'step' } as const, null)
const model = atom({ plugin: 'status-bar', key: 'model' } as const, '')
const cwd = atom({ plugin: 'status-bar', key: 'cwd' } as const, '')
const branch = atom({ plugin: 'status-bar', key: 'branch' } as const, null)
const now = atom({ plugin: 'status-bar', key: 'now' } as const, 0)

// Module-level: a hot reload drops the environment and its timers with it.
let timer: Timer | undefined

// The engine's usage figures as the state keeps them (JSON values only:
// no absent field, null instead).
function toUsage(
  context: { percent?: number; tokens?: number; window: number },
  rateLimits: readonly { kind: string; percentUsed: number; resetsAt?: string }[],
  raw: string | undefined,
): StatusBarUsage {
  const limits: StatusBarLimit[] = rateLimits.map(l => ({
    kind: l.kind,
    percentUsed: l.percentUsed,
    resetsAt: l.resetsAt ?? null,
  }))
  return { contextPercent: contextFill(context, raw).pct, contextTokens: context.tokens ?? null, limits }
}

// Writes only on change, so readers redraw only when a figure moved (the
// state library reads and writes named atoms only: one helper per atom).
async function putUsage($: EngineInterface, value: StatusBarUsage): Promise<void> {
  if (JSON.stringify(await read($, usage)) === JSON.stringify(value)) return
  await update($, usage, () => value)
}

async function putStep($: EngineInterface, value: StatusBarStep | null): Promise<void> {
  if (JSON.stringify(await read($, step)) === JSON.stringify(value)) return
  await update($, step, () => value)
}

async function putModel($: EngineInterface, value: string): Promise<void> {
  if ((await read($, model)) === value) return
  await update($, model, () => value)
}

async function putCwd($: EngineInterface, value: string): Promise<void> {
  if ((await read($, cwd)) === value) return
  await update($, cwd, () => value)
}

async function putBranch($: EngineInterface, value: string | null): Promise<void> {
  if ((await read($, branch)) === value) return
  await update($, branch, () => value)
}

async function putNow($: EngineInterface, value: number): Promise<void> {
  if ((await read($, now)) === value) return
  await update($, now, () => value)
}

// The branch HEAD names at `path`; null when unreadable or detached.
async function readHead($: EngineInterface, path: string): Promise<string | null> {
  try {
    return parseHead(await $.fs.read(path)) ?? null
  } catch {
    // No HEAD there (a broken worktree link): no branch shown.
    return null
  }
}

// The checked-out branch of the repository holding `dir`: the nearest
// `.git` above it, a folder, or a worktree's file naming its git folder.
async function findBranch($: EngineInterface, dir: string): Promise<string | null> {
  let at = dir
  for (let depth = 0; depth < MAX_DEPTH; depth += 1) {
    const dotGit = `${at === '/' ? '' : at}/.git`
    let kind: string | undefined
    try {
      kind = (await $.fs.stat(dotGit)).kind
    } catch {
      // No .git here: look one folder up.
      kind = undefined
    }
    if (kind === 'dir') return readHead($, `${dotGit}/HEAD`)
    if (kind === 'file') {
      let text: string
      try {
        text = await $.fs.read(dotGit)
      } catch {
        // Unreadable .git file: branch unknown.
        return null
      }
      const gitdir = resolveGitdir(text, at)
      return gitdir === undefined ? null : readHead($, `${gitdir}/HEAD`)
    }
    const up = parentDir(at)
    if (up === at) return null
    at = up
  }
  return null
}

// Each figure on its own: one refused read leaves the others current.
async function refresh($: EngineInterface): Promise<void> {
  const jobs: Promise<void>[] = [
    $.clock.now().then(at => putNow($, at)),
    // A refused read measures against the model's window, as an unset variable does.
    Promise.all([$.session.usage(), $.env.get('CLAUDE_CODE_AUTO_COMPACT_WINDOW').catch(() => undefined)]).then(([u, raw]) =>
      putUsage($, toUsage(u.context, u.rateLimits, raw)),
    ),
    $.session.model().then(m => putModel($, m)),
    $.session.cwd().then(async dir => {
      await putCwd($, dir)
      await putBranch($, await findBranch($, dir))
    }),
  ]
  const results = await Promise.allSettled(jobs)
  const failed = results.find(r => r.status === 'rejected')
  if (failed !== undefined) throw failed.reason
}

function onTick($: EngineInterface): void {
  refresh($).catch(() => {
    // A refused read or write leaves that figure as drawn; the next tick
    // (TICK_MS later), turn or measurement refreshes it again.
  })
}

// Started from session.start and lazily from prompt.submit: session.start
// does not fire again after a hot reload.
function ensurePolling($: EngineInterface): void {
  if (timer !== undefined) return
  timer = $.clock.every(TICK_MS, () => onTick($))
  $.clock.after(0, () => onTick($))
}

// Runs `write`; a refused state write leaves the bar as it was (an observer
// never fails the event it watches).
async function record(write: () => Promise<void>): Promise<void> {
  try {
    await write()
  } catch {
    // Display only: the next step, turn or tick writes again.
  }
}

// A segment's Text props: only the styles it sets, never an undefined prop.
function segProps(seg: Seg): TextProps {
  return {
    ...(seg.color === undefined ? {} : { color: seg.color }),
    ...(seg.dim === true ? { dimColor: true } : {}),
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    ensurePolling($)
    return next(e)
  })

  on('prompt.submit', ($, e, next) => {
    ensurePolling($)
    return next(e)
  }).catch(($, e, next) => next(e))

  // Pushed when the context fill or a quota window moves.
  on('session.measure', async ($, e, next) => {
    await record(async () => {
      const raw = await $.env.get('CLAUDE_CODE_AUTO_COMPACT_WINDOW').catch(() => undefined)
      await putUsage($, toUsage(e.context, e.rateLimits, raw))
    })
    return next(e)
  }).catch(($, e, next) => next(e))

  // Each main-loop response: its tokens in/out (the status line's
  // total_input_tokens / total_output_tokens) and the model that answered.
  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    const used = result.usage
    if (e.agentId === undefined && used !== null) {
      const tokensIn = used.input_tokens + used.cache_creation_input_tokens + used.cache_read_input_tokens
      await record(() => putStep($, { tokensIn, tokensOut: used.output_tokens, model: used.model }))
    }
    return result
  }).catch(async function* ($, e, next) {
    return yield* next(e)
  })

  // A main-loop turn ended: the branch may have moved, the model changed.
  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId === undefined) await record(() => refresh($))
    return done
  }).catch(($, e, next) => next(e))

  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear') {
      // No session.start follows a /clear: the timer is kept, counts reset.
      await record(() => putStep($, null))
      await record(() => refresh($))
    } else {
      timer?.cancel()
      timer = undefined
    }
    return next(e)
  })

  // Our rows, then the engine's own hint line (what next(e) answers: its
  // drawing, pills live). Reads state only.
  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
    const { Box, Text } = $.ui.resolve(e)
    const last = await read($, step)
    const figures = await read($, usage)
    const lines = layout(
      {
        model: pickModel(await read($, model), last?.model),
        cwd: await read($, cwd),
        branch: await read($, branch),
        tokensIn: last?.tokensIn ?? figures.contextTokens ?? 0,
        tokensOut: last?.tokensOut ?? 0,
        contextPercent: figures.contextPercent ?? 0,
        limits: figures.limits,
        now: await read($, now),
      },
      e.viewport?.columns,
    )
    const theirs = await next(e)
    return (
      <Box flexDirection="column">
        {lines.map(line => (
          <Box flexDirection="row">
            {line.map(seg => (
              <Text {...segProps(seg)} wrap="truncate-end">
                {seg.text}
              </Text>
            ))}
          </Box>
        ))}
        {theirs}
      </Box>
    )
  })
}
