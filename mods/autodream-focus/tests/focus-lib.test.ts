import { expect, test } from 'claude-code/testing'

import type { FocusTag } from '../types'
import { focusScript, forWriter, readTags, tagId, tagsFile, TEXT_CAP } from '../hooks/focus-lib'

const TAG: FocusTag = {
  id: 's1:r1',
  session: 's1',
  uuid: 'r1',
  role: 'assistant',
  text: 'first line\nsecond line with "quotes"',
  cwd: '/Users/x/proj',
  taggedAt: '2026-10-04T18:00:00.000Z',
}

test('a tag with a multi-line text is read back from one line', () => {
  expect(readTags(`${JSON.stringify(TAG)}\n`)).toEqual([TAG])
})

test('an empty file holds no tags', () => {
  expect(readTags('')).toEqual([])
})

test('torn, foreign and incomplete lines are not tags', () => {
  const torn = '{"id":"s1:r1","session":"s1"'
  const foreign = '{"note":"written by hand"}'
  const badRole = JSON.stringify({ ...TAG, id: 's1:bad-role', role: 'system' })
  const text = [torn, 'not json at all', '[1,2,3]', 'null', foreign, badRole, JSON.stringify(TAG), ''].join('\n')

  expect(readTags(text)).toEqual([TAG])
})

test('a tag written by OMP or Codex is read like any other, with the fields this version does not know', () => {
  const line = JSON.stringify({ ...TAG, harness: 'omp', transcript: '/Users/x/.omp/agent/sessions/b/s1.jsonl' })

  expect(readTags(line)[0]).toEqual({ ...TAG, harness: 'omp', transcript: '/Users/x/.omp/agent/sessions/b/s1.jsonl' })
})

test('a tag without a cwd is read with an empty one', () => {
  const { cwd: _cwd, ...rest } = TAG

  expect(readTags(JSON.stringify(rest))[0]?.cwd).toBe('')
})

test('the same row id in two sessions is two tags', () => {
  expect(tagId('s1', 'r1')).not.toBe(tagId('s2', 'r1'))
})

test('a turn is handed to the writer one character past its cap, so the writer marks the cut', () => {
  expect(forWriter('short')).toBe('short')
  expect(forWriter('x'.repeat(TEXT_CAP))).toHaveLength(TEXT_CAP)
  expect(forWriter('x'.repeat(5_000))).toHaveLength(TEXT_CAP + 1)
})

test('characters are counted as the writer counts them, in code points, so emoji are not cut early or in half', () => {
  const fifteenHundred = '😀'.repeat(1_500)
  const many = '😀'.repeat(3_000)

  expect(forWriter(fifteenHundred)).toBe(fifteenHundred)
  expect(Array.from(forWriter(many))).toHaveLength(TEXT_CAP + 1)
  expect(forWriter(many)).not.toContain('�')
  expect(forWriter(many).endsWith('😀')).toBe(true)
})

test('the tags file is next to the rest of autodream, and AUTODREAM_DIR moves it', () => {
  expect(tagsFile({ HOME: '/Users/x' })).toBe('/Users/x/.claude/autodream/tags.jsonl')
  expect(tagsFile({ HOME: '/Users/x', AUTODREAM_DIR: '/opt/ad' })).toBe('/opt/ad/tags.jsonl')
  expect(tagsFile({ HOME: '/Users/x', AUTODREAM_DIR: '' })).toBe('/Users/x/.claude/autodream/tags.jsonl')
})

test('AUTODREAM_TAGS_FILE moves the tags file, as it moves the one bin/vault-notes.sh reads', () => {
  expect(tagsFile({ HOME: '/Users/x', AUTODREAM_DIR: '/opt/ad', AUTODREAM_TAGS_FILE: '/elsewhere/t.jsonl' })).toBe('/elsewhere/t.jsonl')
  expect(tagsFile({ HOME: '/Users/x', AUTODREAM_TAGS_FILE: '' })).toBe('/Users/x/.claude/autodream/tags.jsonl')
})

test('the writer is the install directory script, AUTODREAM_DIR moves it, and AUTODREAM_FOCUS_BIN overrides it', () => {
  expect(focusScript({ HOME: '/Users/x' })).toBe('/Users/x/.claude/autodream/autodream-focus.sh')
  expect(focusScript({ HOME: '/Users/x', AUTODREAM_DIR: '/opt/ad' })).toBe('/opt/ad/autodream-focus.sh')
  expect(focusScript({ HOME: '/Users/x', AUTODREAM_DIR: '' })).toBe('/Users/x/.claude/autodream/autodream-focus.sh')
  expect(focusScript({ HOME: '/Users/x', AUTODREAM_FOCUS_BIN: '/opt/bin/focus' })).toBe('/opt/bin/focus')
})
