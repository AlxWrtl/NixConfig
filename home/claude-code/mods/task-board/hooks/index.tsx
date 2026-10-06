// task-board: a pane opened by /task-board listing the session's background
// shells and subagents with their duration and state (en cours / fini /
// échoué). Observes only: every tool.call hook returns next(e)'s result
// unchanged. Silent: no sound, no pop-up notification.

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import {
  addAgent,
  addShell,
  applyAgentSnapshot,
  clear,
  finishAgentTurn,
  finishByNotification,
  parseTaskNotifications,
  runningCount,
  stopShell,
} from './board.ts'
import type { Notification, Task } from './board.ts'
import { layoutRow } from './format.ts'

const PANE = 'task-board'
const TITLE = 'Tâches'
const TICK_MS = 1000

const tasks = atom({ plugin: 'task-board', key: 'tasks' } as const, [])
const now = atom({ plugin: 'task-board', key: 'now' } as const, 0)
const isOpen = atom({ plugin: 'task-board', key: 'isOpen' } as const, false)

// Reads a field of an engine record whose shape varies per tool; anything
// that is not a non-empty string reads as undefined.
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

// A row's text: a string as is, else its text blocks joined (any other
// block skipped); anything else reads as empty.
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

// Applies a pure change to the task list, writing only when it changed.
async function change($: EngineInterface, fn: (list: Task[]) => Task[]): Promise<void> {
  const current = await read($, tasks)
  if (fn(current) === current) return
  await update($, tasks, fn)
}

// Module-level: a hot reload drops the environment and its timers with it.
let timer: Timer | undefined

async function tick($: EngineInterface): Promise<void> {
  const at = await $.clock.now()
  const list = await $.agent.list()
  const snapshot = list.map(a => ({ id: a.id, description: a.description, type: a.type, status: a.status }))
  await change($, current => applyAgentSnapshot(current, snapshot, at))
  // Per-second refresh only while the pane is open and something runs.
  if ((await read($, isOpen)) && runningCount(await read($, tasks)) > 0) {
    await update($, now, () => at)
  }
}

// Started from session.start and lazily from command.run / prompt.submit:
// session.start does not fire again after a hot reload.
function ensurePolling($: EngineInterface): void {
  if (timer !== undefined) return
  timer = $.clock.every(TICK_MS, () => {
    tick($).catch(() => {
      // A failed tick (agent list or state refused) is retried by the next
      // one a second later; nothing else depends on it.
    })
  })
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'task-board',
      description: 'Ouvre le tableau des tâches en arrière-plan (shells et sous-agents)',
      immediate: true,
    })
    ensurePolling($)
    return next(e)
  })

  on('prompt.submit', ($, e, next) => {
    ensurePolling($)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'task-board' }, async $ => {
    ensurePolling($)
    const at = await $.clock.now()
    await update($, now, () => at)
    await update($, isOpen, () => true)
    await $.ui.open({ id: PANE, title: TITLE })
    return { text: 'Tableau des tâches ouvert.' }
  })

  on('ui.close', async ($, e, next) => {
    if (e.id === PANE) await update($, isOpen, () => false)
    return next(e)
  }).catch(($, e, next) => next(e))

  // Background shell: run_in_background, or ctrl+B / auto-background, all
  // answer a backgroundTaskId.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const ran = await next(e)
    const id = stringField(ran.result, 'backgroundTaskId')
    if (id !== undefined) {
      const startedAt = await $.clock.now()
      const label = stringField(e, 'description') ?? stringField(e, 'command') ?? 'shell'
      const toolUseId = stringField(e, 'tool_use_id')
      // Set only inside a subagent loop: its shells close with it (board.ts).
      const ownerAgentId = stringField(e, 'agentId')
      await change($, current =>
        addShell(current, {
          id,
          label,
          startedAt,
          ...(toolUseId === undefined ? {} : { toolUseId }),
          ...(ownerAgentId === undefined ? {} : { ownerAgentId }),
        }),
      )
    }
    return ran
  }).catch(($, e, next) => next(e))

  // Background subagent: the Agent call answers async_launched + agentId.
  on('tool.call', { tool: 'Agent' }, async ($, e, next) => {
    const ran = await next(e)
    const id = stringField(ran.result, 'agentId')
    if (stringField(ran.result, 'status') === 'async_launched' && id !== undefined) {
      const startedAt = await $.clock.now()
      const label = stringField(ran.result, 'description') ?? stringField(e, 'description') ?? 'agent'
      const agentType = stringField(e, 'subagent_type')
      const toolUseId = stringField(e, 'tool_use_id')
      await change($, current =>
        addAgent(current, {
          id,
          label,
          startedAt,
          ...(agentType === undefined ? {} : { agentType }),
          ...(toolUseId === undefined ? {} : { toolUseId }),
        }),
      )
    }
    return ran
  }).catch(($, e, next) => next(e))

  // A background task's notification row: the one completion signal a shell
  // has. A render hook never writes state, so the write is deferred to a
  // timer; the row itself is drawn unchanged.
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
          .then(at => change($, current => finishByNotification(current, note, at)))
          .catch(() => {
            // State refused: the row stays "en cours" until the agent
            // snapshot (subagents) or a later redraw of the row retries it.
          })
      })
    }
    return next(e)
  })

  // A subagent's shell notifies that subagent's loop only: its row never
  // reaches the main transcript (nor the ui.render path above). Main-loop
  // rows stay on that path. Read before next: the row is relayed unchanged.
  on('session.append', async ($, e, next) => {
    const agentId = e.agentId
    if (agentId !== undefined && agentId !== '' && e.origin.kind === 'task-notification') {
      const notes = parseTaskNotifications(rowText(e.message.content))
      if (notes.length > 0) {
        const at = await $.clock.now()
        await change($, current => notes.reduce((list, note) => finishByNotification(list, note, at), current))
      }
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  // A shell stopped by TaskStop gets no notification row: close it as
  // killed. TaskStop also stops agents; stopShell leaves agent rows to the
  // agent snapshot.
  on('tool.call', { tool: 'TaskStop' }, async ($, e, next) => {
    const ran = await next(e)
    if (ran.isError !== true && ran.result !== undefined) {
      const id = stringField(ran.result, 'task_id') ?? stringField(e, 'task_id') ?? stringField(e, 'shell_id')
      if (id !== undefined) {
        const at = await $.clock.now()
        await change($, current => stopShell(current, id, at))
      }
    }
    return ran
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    const agentId = e.agentId
    if (agentId !== undefined) {
      const at = await $.clock.now()
      await change($, current => finishAgentTurn(current, agentId, e.reason, at))
    }
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear') {
      // No session.start follows a /clear: keep the timer, empty the list.
      await change($, clear)
    } else {
      timer?.cancel()
      timer = undefined
    }
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const list = await read($, tasks)
    const at = await read($, now)
    const cols = Math.max(20, e.props.bodyColumns)

    if (list.length === 0) {
      return (
        <Box flexDirection="column">
          <Text dimColor>Aucune tâche en arrière-plan.</Text>
        </Box>
      )
    }

    return (
      <Box flexDirection="column">
        {list.map(task => {
          const row = layoutRow(task, Math.max(at, task.startedAt), cols)
          const isDone = task.status === 'completed'
          const isFailed = task.status === 'failed' || task.status === 'killed'
          return (
            <Box flexDirection="row">
              <Text color={isFailed ? 'error' : isDone ? 'inactive' : 'warning'} dimColor={isDone}>
                {row.state}
              </Text>
              <Text dimColor={isDone} wrap="truncate-end">
                {' '}
                {row.text}{' '}
              </Text>
              <Text dimColor>{row.dur}</Text>
            </Box>
          )
        })}
      </Box>
    )
  })
}
