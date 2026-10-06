// Pure layout of the band: at most two lines, each fitting `cols` cells.

import type { ApexBandRun } from '../types'

const SEP = ' · '

export function truncate(text: string, width: number): string {
  if (width <= 0) return ''
  if (text.length <= width) return text
  return width === 1 ? '…' : `${text.slice(0, width - 1)}…`
}

// skipped → ignorée, a red word → rouge, a green word → vert, else the raw
// text cut to 30 characters.
export function baselineWord(baseline: string): string {
  const s = baseline.toLowerCase()
  if (/skip|ignor/.test(s)) return 'ignorée'
  if (/\bred\b|rouge|fail|échec|✘|❌/.test(s)) return 'rouge'
  if (/green|vert|✅|\bpass/.test(s)) return 'vert'
  return truncate(baseline, 30)
}

export function layoutBand(run: ApexBandRun, cols: number, maxRows: number): string[] {
  const width = Math.max(1, cols)
  const rest = [
    run.mode,
    run.currentStep === undefined ? undefined : `étape ${run.currentStep}`,
    run.branch,
    run.baseline === undefined ? undefined : `baseline ${baselineWord(run.baseline)}`,
  ].filter((part): part is string => part !== undefined && part !== '')
  const head = `APEX${SEP}${run.title}`
  const one = [head, ...rest].join(SEP)
  if (one.length <= width || maxRows < 2 || rest.length === 0) return [truncate(one, width)]
  return [truncate(head, width), truncate(rest.join(SEP), width)]
}
