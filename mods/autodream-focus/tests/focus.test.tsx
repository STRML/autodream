import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const NOW = new Date(2026, 9, 4, 20, 15, 0).getTime()
const FILE = '/Users/x/.claude/autodream/tags.jsonl'
const SCRIPT = '/Users/x/.claude/autodream/autodream-focus.sh'

type Machine = {
  /** what is in tags.jsonl when the session starts; absent means no file */
  file?: string
  /** the file is there but reading it fails with this (not a missing file) */
  readError?: string
  /** the writer script is not installed */
  noScript?: boolean
  /** the writer exits 1 with this on stderr */
  writerFails?: string
  /** extra environment the mod can see */
  env?: Record<string, string>
}

type Run = { argv: string[]; env: Record<string, string> | undefined }

/**
 * The writer is autodream-focus.sh. The stand-in below does what it does to the file the mod reads (toggle a line by id), so the
 * buttons can be checked against what a press leaves on disk. The mod itself never writes: any fs.write is refused.
 */
const world = (on: On, { file, readError, noScript = false, writerFails, env = {} }: Machine = {}) => {
  mock.clock(on, { now: NOW })
  mock.env(on, { HOME: '/Users/x', ...env })

  const runs: Run[] = []
  const toasts: string[] = []
  const writes: string[] = []
  let disk = file

  on('session.start', () => ({ cwd: '/x' }))
  on('session.id', () => ({ value: 's1' }))
  on('session.cwd', () => ({ value: '/Users/x/proj' }))
  on('fs.exists', (_$, e) => ({ value: e.path.endsWith('autodream-focus.sh') ? !noScript : e.path === FILE && (disk !== undefined || readError !== undefined) }))
  on('fs.read', (_$, e) => {
    if (readError !== undefined) return { deny: readError }

    return e.path === FILE && disk !== undefined ? { value: disk } : { deny: `ENOENT ${e.path}` }
  })
  on('fs.write', (_$, e) => {
    writes.push(e.path)

    return { deny: 'the mod must not write tags.jsonl; the shared writer does' }
  })
  on('process.run', (_$, e) => {
    runs.push({ argv: e.argv, env: e.init?.env })

    if (writerFails !== undefined) return { value: { exitCode: 1, stdout: '', stderr: writerFails, isStdoutTruncated: false, isStderrTruncated: false } }

    const arg = (flag: string) => e.argv[e.argv.indexOf(flag) + 1] ?? ''
    const id = `${arg('--session')}:${arg('--uuid')}`
    const lines = (disk ?? '').split('\n').filter(Boolean)
    const isTagged = lines.some(line => JSON.parse(line).id === id)

    disk = isTagged
      ? `${lines.filter(line => JSON.parse(line).id !== id).join('\n')}\n`
      : `${[...lines, JSON.stringify({ id, session: arg('--session'), uuid: arg('--uuid'), role: arg('--role'), text: arg('--text'), cwd: arg('--cwd'), taggedAt: new Date(NOW).toISOString(), harness: arg('--harness') })].join('\n')}\n`

    return { value: { exitCode: 0, stdout: `${isTagged ? 'untagged' : 'tagged'} ${id}\n`, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.toast', (_$, e) => {
    toasts.push(e.text)

    return { value: undefined }
  })
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine row</Text>
  })

  return { runs, toasts, writes, disk: () => disk }
}

const start = ($: any) => $.session.start({ cwd: '/x', surface: 'terminal', isInteractive: true })

const user = ($: any, requestId: string, props: Record<string, unknown> = {}) =>
  $.ui.mount({
    plugin: 'autodream-focus',
    surface: 'terminal',
    component: 'UserMessage',
    requestId,
    props: { text: 'why is the build red?', origin: { kind: 'composer' }, isExpanded: false, ...props },
  })

const reply = ($: any, requestId: string, text = 'The lockfile is stale.') =>
  $.ui.mount({
    plugin: 'autodream-focus',
    surface: 'terminal',
    component: 'AssistantMessage',
    requestId,
    props: { text, isFirstOfReply: true },
  })

/** The button's own Box: hidden until hovered, or shown for good once tagged. */
const shown = async (ui: any) => {
  const tree = JSON.stringify(await ui.drawn())

  return tree.includes('"display":"none"') ? 'hover' : 'always'
}

test('a prompt gets a focus button that waits for the pointer, and the engine row stays', async ($, on) => {
  world(on)
  await start($)

  const ui = await user($, 'r1')

  expect(await ui.find({ key: 'focus-press:r1' })).toBeDefined()
  expect(JSON.stringify(await ui.drawn())).toContain('engine row')
  expect(await shown(ui)).toBe('hover')
})

test('a reply gets one too', async ($, on) => {
  world(on)
  await start($)

  expect(await (await reply($, 'r2')).find({ key: 'focus-press:r2' })).toBeDefined()
})

test('pressing the button hands the turn to the shared writer, and the button stays shown', async ($, on) => {
  const { runs, toasts } = world(on)
  await start($)

  const ui = await user($, 'r1')

  await ui.press({ key: 'focus-press:r1' })

  expect(runs).toHaveLength(1)
  expect(runs[0]?.argv).toEqual([SCRIPT, 'tag', '--harness', 'claude', '--session', 's1', '--uuid', 'r1', '--role', 'user', '--cwd', '/Users/x/proj', '--text', 'why is the build red?'])
  expect(toasts.join(' ')).toContain('Tagged')
  expect(await shown(ui)).toBe('always')
})

test('the mod never writes tags.jsonl itself, so there is one locked writer for every harness', async ($, on) => {
  const { writes, toasts } = world(on)
  await start($)

  await (await user($, 'r1')).press({ key: 'focus-press:r1' })

  expect(writes).toHaveLength(0)
  expect(toasts.join(' ')).not.toContain('Could not')
})

test('a reply is tagged with the assistant role', async ($, on) => {
  const { runs } = world(on)
  await start($)

  await (await reply($, 'r2')).press({ key: 'focus-press:r2' })

  expect(runs[0]?.argv[runs[0].argv.indexOf('--role') + 1]).toBe('assistant')
})

test('pressing a tagged button takes the tag back', async ($, on) => {
  const { toasts } = world(on)
  await start($)

  const ui = await user($, 'r1')

  await ui.press({ key: 'focus-press:r1' })
  await ui.press({ key: 'focus-press:r1' })

  expect(toasts.at(-1)).toContain('removed')
  expect(await shown(ui)).toBe('hover')
})

test('a tag on disk at session start is already lit', async ($, on) => {
  const mine = JSON.stringify({
    id: 's1:r1',
    session: 's1',
    uuid: 'r1',
    role: 'user',
    text: 'why is the build red?',
    cwd: '/x',
    day: '2026-10-03',
    taggedAt: '2026-10-03T10:00:00.000Z',
  })

  world(on, { file: `${mine}\n` })
  await start($)

  expect(await shown(await user($, 'r1'))).toBe('always')
  expect(await shown(await user($, 'r2'))).toBe('hover')
})

test('a tag that OMP or Codex wrote lights the button for its own turn', async ($, on) => {
  const other = JSON.stringify({ id: 's1:r1', session: 's1', uuid: 'r1', role: 'assistant', text: 'x', cwd: '/x', taggedAt: '2026-10-03T10:00:00.000Z', harness: 'omp', transcript: '/t/s1.jsonl' })

  world(on, { file: `${other}\n` })
  await start($)

  expect(await shown(await user($, 'r1'))).toBe('always')
})

test('a notification or a peer message is not the person\'s to tag', async ($, on) => {
  world(on)
  await start($)

  expect(await (await user($, 'n1', { origin: { kind: 'task-notification' } })).find({ key: 'focus-press:n1' })).toBeUndefined()
  expect(await (await user($, 'n2', { origin: { kind: 'peer' } })).find({ key: 'focus-press:n2' })).toBeUndefined()
})

test('a row with no text has nothing to tag', async ($, on) => {
  world(on)
  await start($)

  expect(await (await user($, 'e1', { text: '  ' })).find({ key: 'focus-press:e1' })).toBeUndefined()
})

test('a writer that refuses says why, and does not mark the turn', async ($, on) => {
  const { toasts } = world(on, { writerFails: 'autodream-focus: cannot read /Users/x/.claude/autodream/tags.jsonl; nothing was changed' })
  await start($)

  const ui = await user($, 'r1')

  await ui.press({ key: 'focus-press:r1' })

  expect(toasts.join(' ')).toContain('Could not save the tag')
  expect(toasts.join(' ')).toContain('nothing was changed')
  expect(await shown(ui)).toBe('hover')
})

test('a writer that is not installed is said, not worked around with a write of the mod\'s own', async ($, on) => {
  const { runs, writes, toasts } = world(on, { noScript: true })
  await start($)

  await (await user($, 'r1')).press({ key: 'focus-press:r1' })

  expect(runs).toHaveLength(0)
  expect(writes).toHaveLength(0)
  expect(toasts.at(-1)).toContain('was not found')
})

test('a file that is there but will not read shows no lit buttons, and says so', async ($, on) => {
  const { toasts } = world(on, { readError: 'EIO: i/o error' })
  await start($)

  expect(toasts.join(' ')).toContain('Could not read the tags file')
  expect(await shown(await user($, 'r1'))).toBe('hover')
})

test('the writer is run with the same AUTODREAM_DIR and AUTODREAM_TAGS_FILE the mod reads', async ($, on) => {
  const { runs } = world(on, { env: { AUTODREAM_DIR: '/opt/ad', AUTODREAM_TAGS_FILE: '/elsewhere/t.jsonl' } })
  await start($)

  await (await user($, 'r1')).press({ key: 'focus-press:r1' })

  expect(runs[0]?.argv[0]).toBe('/opt/ad/autodream-focus.sh')
  expect(runs[0]?.env).toEqual({ AUTODREAM_DIR: '/opt/ad', AUTODREAM_TAGS_FILE: '/elsewhere/t.jsonl' })
})

test('a long turn is handed over one character past the writer\'s cap, so it marks the cut', async ($, on) => {
  const { runs } = world(on)
  await start($)

  await (await reply($, 'r3', 'x'.repeat(5_000))).press({ key: 'focus-press:r3' })

  const argv = runs[0]?.argv ?? []

  expect(argv[argv.indexOf('--text') + 1]).toHaveLength(2_001)
})
