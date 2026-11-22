import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderElement } from 'claude-code'

import type { FocusTag } from '../types'
import { focusScript, forWriter, readTags, tagId, tagsFileFromEnv } from './focus-lib'

const LABEL = 'autodream focus'
const OFF = `+ ${LABEL}`
const ON = `✓ ${LABEL}`
const BUTTON_WIDTH = OFF.length + 5

const isTypedByPerson = (kind: string | undefined): boolean => kind === 'composer' || kind === 'bridge'

const tagged = atom({ plugin: 'autodream-focus', key: 'tagged' } as const, [])

type Ui = ReturnType<EngineInterface['ui']['resolve']>
type Turn = { uuid: string; role: FocusTag['role']; text: string }

const writer = async ($: EngineInterface): Promise<{ script: string; env: Record<string, string>; fallback: string }> => {
  const [HOME, AUTODREAM_DIR, AUTODREAM_TAGS_FILE, AUTODREAM_FOCUS_BIN] = await Promise.all([
    $.env.get('HOME'),
    $.env.get('AUTODREAM_DIR'),
    $.env.get('AUTODREAM_TAGS_FILE'),
    $.env.get('AUTODREAM_FOCUS_BIN'),
  ])

  return {
    script: focusScript({ HOME, AUTODREAM_DIR, AUTODREAM_FOCUS_BIN }),
    env: { ...(AUTODREAM_DIR ? { AUTODREAM_DIR } : {}), ...(AUTODREAM_TAGS_FILE ? { AUTODREAM_TAGS_FILE } : {}) },
    fallback: tagsFileFromEnv({ HOME, AUTODREAM_DIR, AUTODREAM_TAGS_FILE }),
  }
}

const tagsFilePath = async ($: EngineInterface): Promise<string> => {
  const { script, env, fallback } = await writer($)

  try {
    if (await $.fs.exists(script)) {
      const { exitCode, stdout } = await $.process.run([script, 'path'], { env, timeoutMs: 5_000 })

      if (exitCode === 0 && stdout.trim() !== '') return stdout.trim()
    }
  } catch {
  }

  return fallback
}

const reason = (cause: unknown): string => (cause instanceof Error ? cause.message : String(cause))

const load = async ($: EngineInterface): Promise<FocusTag[]> => {
  const file = await tagsFilePath($)

  if (!(await $.fs.exists(file))) return []

  const text = await $.fs.read(file)

  if (typeof text !== 'string') throw new Error(`${file} did not read as text`)

  return readTags(text)
}

const refresh = async ($: EngineInterface) => {
  try {
    const tags = await load($)

    await update($, tagged, () => tags.map(tag => tag.id))
  } catch (cause) {
    $.ui.toast(`Could not read the tags file, so no turn shows as tagged: ${reason(cause)}`)
  }
}

const press = async ($: EngineInterface, turn: Turn) => {
  try {
    const [session, cwd, { script, env }] = await Promise.all([$.session.id(), $.session.cwd(), writer($)])

    if (!(await $.fs.exists(script))) {
      $.ui.toast(`autodream-focus.sh was not found at ${script}, so nothing was changed. Run cc-autodream's install.sh.`)

      return
    }

    const { exitCode, stdout, stderr } = await $.process.run(
      [script, 'tag', '--harness', 'claude', '--session', session, '--uuid', turn.uuid, '--role', turn.role, '--cwd', cwd, '--text', forWriter(turn.text)],
      { env, timeoutMs: 15_000 },
    )

    if (exitCode !== 0) {
      $.ui.toast(`Could not save the tag: ${(stderr || stdout).trim().slice(0, 300)}`)

      return
    }

    await refresh($)
    $.ui.toast(stdout.trim().startsWith('untagged') ? 'Tag removed.' : "Tagged: tonight's autodream takes a close look at this.")
  } catch (cause) {
    $.ui.toast(`Could not save the tag: ${reason(cause)}`)
  }
}

const withFocus = async ($: EngineInterface, ui: Ui, turn: Turn, requestId: string, beneath: RenderElement) => {
  if (typeof turn.text !== 'string' || turn.text.trim() === '') return beneath

  const [session, ids] = await Promise.all([$.session.id(), read($, tagged)])
  const isTagged = ids.includes(tagId(session, turn.uuid))
  const { Box, Button } = ui

  return (
    <Box key={`focus:${requestId}`} flexDirection="column">
      {beneath}
      <Box
        position="absolute"
        top={0}
        right={0}
        width={BUTTON_WIDTH}
        justifyContent="flex-end"
        display={isTagged ? 'flex' : 'none'}
        hover={isTagged ? undefined : { display: 'flex' }}
      >
        <Button key={`focus-press:${requestId}`} plain dimColor={!isTagged} label={isTagged ? ON : OFF} onPress={() => press($, turn)} />
      </Box>
    </Box>
  )
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await refresh($)

    return next(e)
  })

  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    const beneath = await next(e)

    if (!isTypedByPerson(e.props.origin?.kind)) return beneath

    return withFocus($, $.ui.resolve(e), { uuid: e.requestId, role: 'user', text: e.props.text }, e.requestId, beneath)
  })

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const beneath = await next(e)

    return withFocus($, $.ui.resolve(e), { uuid: e.requestId, role: 'assistant', text: e.props.text }, e.requestId, beneath)
  })
}
