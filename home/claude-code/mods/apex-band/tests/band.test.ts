import { describe, expect, test } from 'claude-code/testing'

import { baselineWord, layoutBand } from '../hooks/band.ts'
import type { Run } from '../hooks/context.ts'

const RUN: Run = {
  title: 'mods task-board + apex-band',
  mode: 'Standard',
  branch: 'feat/claude-mods',
  baseline: 'nix flake check -> green',
  steps: [],
  currentStep: '03-execute',
}

describe('baselineWord', () => {
  test('green, red, skipped, raw', () => {
    expect(baselineWord('nix flake check --no-build -> green (13 ✅)')).toBe('vert')
    expect(baselineWord('red: 2 failed')).toBe('rouge')
    expect(baselineWord('skipped — tree dirty')).toBe('ignorée')
    expect(baselineWord('a very long baseline text that says nothing useful')).toBe('a very long baseline text tha…')
  })
})

describe('layoutBand', () => {
  test('one line when it fits', () => {
    expect(layoutBand(RUN, 200, 3)).toEqual([
      'APEX · mods task-board + apex-band · Standard · étape 03-execute · feat/claude-mods · baseline vert',
    ])
  })

  test('two lines when narrow, each within the width', () => {
    const lines = layoutBand(RUN, 40, 3)
    expect(lines.length).toBe(2)
    for (const line of lines) expect(line.length <= 40).toBe(true)
    expect(lines[0]?.startsWith('APEX · ')).toBe(true)
  })

  test('one truncated line when only one row is free', () => {
    const lines = layoutBand(RUN, 40, 1)
    expect(lines.length).toBe(1)
    expect(lines[0]?.length).toBe(40)
    expect(lines[0]?.endsWith('…')).toBe(true)
  })

  test('missing fields are left out', () => {
    expect(layoutBand({ title: 't', steps: [] }, 80, 2)).toEqual(['APEX · t'])
  })
})
