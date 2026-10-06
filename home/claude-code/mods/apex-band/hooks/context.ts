// Pure parsing of an APEX run's 00-context.md and its liveness rule.
// The header format drifted over time (Branch/Branche, Flags/Flags résolus,
// bold or wrapped Mode, no Mode, Baseline skipped, no Progress table, many
// status spellings): every reader here tolerates all of them.

import type { ApexBandRun, ApexBandStep, ApexBandStepKind } from '../types'

export type Run = ApexBandRun
export type Step = ApexBandStep
export type StepKind = ApexBandStepKind

// A run is live only while its context file moved in the last 6 hours.
export const STALE_MS = 6 * 60 * 60 * 1000

const clean = (value: string): string => value.replace(/\*\*/g, '').replace(/`/g, '').trim()

export function statusKind(status: string): StepKind {
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

function cutMode(value: string): string {
  const head = value.split(/\s+—\s+|\s+→\s+|\s*\(|;|\.\s/)[0] ?? value
  return head.trim()
}

function readSteps(lines: readonly string[]): Step[] {
  const start = lines.findIndex(l => /^##\s+progress\b/i.test(l))
  if (start < 0) return []
  const steps: Step[] = []
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

export function parseContext(text: string, dirName: string): Run {
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

  const flags = fields.get('flags') ?? fields.get('flags résolus')
  const modeField = fields.get('mode')
  const modeFromFlags = flags?.match(/\bmode\s+([^\s,;)]+)/i)?.[1]
  const mode = modeField !== undefined && modeField !== '' ? cutMode(modeField) : modeFromFlags

  const branchField = fields.get('branch') ?? fields.get('branche')
  const branch = branchField?.split(/\s+/)[0]

  const baselineField = fields.get('baseline')
  const skipped = fields.get('baseline skipped')
  const baseline =
    baselineField !== undefined && baselineField !== ''
      ? baselineField
      : skipped === undefined
        ? undefined
        : `skipped${skipped === '' ? '' : ` — ${skipped}`}`

  const run: Run = { title, steps: readSteps(lines) }
  if (mode !== undefined && mode !== '') run.mode = mode
  if (branch !== undefined && branch !== '') run.branch = branch
  if (baseline !== undefined) run.baseline = baseline
  const current = currentStep(run.steps)
  if (current !== undefined) run.currentStep = current
  return run
}

export function currentStep(steps: readonly Step[]): string | undefined {
  return (steps.find(s => s.kind === 'running') ?? steps.find(s => s.kind === 'pending'))?.step
}

// Live: modified in the last STALE_MS, its 09-finish row neither done nor
// skipped, and, when it has a Progress table, a pending or running row left.
export function isLive(run: Run, mtimeMs: number, now: number): boolean {
  if (now - mtimeMs >= STALE_MS) return false
  const finish = run.steps.find(s => /finish/i.test(s.step))
  if (finish !== undefined && (finish.kind === 'done' || finish.kind === 'skipped')) return false
  if (run.steps.length === 0) return true
  return run.steps.some(s => s.kind === 'pending' || s.kind === 'running')
}

// The branch named by a .git/HEAD file ("ref: refs/heads/<name>"), or
// undefined for a detached HEAD (a bare sha) or anything unrecognised.
export function headBranch(text: string): string | undefined {
  const name = /^ref:\s*refs\/heads\/(\S+)\s*$/.exec(text.trim())?.[1]
  return name === undefined || name === '' ? undefined : name
}

// Off-branch only when both the run's branch and HEAD's are known and
// differ: a run without Branch, or a detached/unreadable HEAD, stays shown.
export function onBranch(run: Run, head: string | undefined): boolean {
  return run.branch === undefined || head === undefined || run.branch === head
}
