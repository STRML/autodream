import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, RenderElement } from 'claude-code'

import type { FocusTag } from '../types'
import { focusScript, forWriter, readTags, tagId, tagsFile } from './focus-lib'

/**
 * Plain text, not an icon: a glyph's width is a guess the engine and the terminal make separately (the emoji eye with
 * its selector drew as an ellipsis, and a bare one was small), and words cannot be measured wrong. The check mark is
 * one cell in every terminal.
 */
const LABEL = 'autodream focus'
const OFF = `+ ${LABEL}`
const ON = `✓ ${LABEL}`
/** The label plus the padding a plain Button gives it, with room to spare: squeezed below that, it truncates to an ellipsis. */
const WIDTH = OFF.length + 5

const tagged = atom({ plugin: 'autodream-focus', key: 'tagged' } as const, [])

type Ui = ReturnType<EngineInterface['ui']['resolve']>
type Turn = { uuid: string; role: FocusTag['role']; text: string }

const where = async ($: EngineInterface): Promise<string> => {
  const [HOME, AUTODREAM_DIR, AUTODREAM_TAGS_FILE] = await Promise.all([
    $.env.get('HOME'),
    $.env.get('AUTODREAM_DIR'),
    $.env.get('AUTODREAM_TAGS_FILE'),
  ])

  return tagsFile({ HOME, AUTODREAM_DIR, AUTODREAM_TAGS_FILE })
}

const reason = (cause: unknown): string => (cause instanceof Error ? cause.message : String(cause))

/**
 * The tags on disk now, to light the buttons. This mod only reads the file: every write goes through bin/autodream-focus.sh,
 * which holds the lock the other two harnesses use, so a tag from the button and one from OMP or Codex cannot overwrite each other.
 *
 * Only a file that is not there is empty. One that is there and will not read (over the 4 MiB a read allows, no permission,
 * an I/O error) throws, so the buttons say so rather than show every turn as untagged.
 */
const load = async ($: EngineInterface): Promise<FocusTag[]> => {
  const file = await where($)

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

/** The script and the two settings that move the file it writes, as the writer reads them from its environment. */
const writer = async ($: EngineInterface): Promise<{ script: string; env: Record<string, string> }> => {
  const [HOME, AUTODREAM_DIR, AUTODREAM_TAGS_FILE, AUTODREAM_FOCUS_BIN] = await Promise.all([
    $.env.get('HOME'),
    $.env.get('AUTODREAM_DIR'),
    $.env.get('AUTODREAM_TAGS_FILE'),
    $.env.get('AUTODREAM_FOCUS_BIN'),
  ])

  return {
    script: focusScript({ HOME, AUTODREAM_DIR, AUTODREAM_FOCUS_BIN }),
    env: { ...(AUTODREAM_DIR ? { AUTODREAM_DIR } : {}), ...(AUTODREAM_TAGS_FILE ? { AUTODREAM_TAGS_FILE } : {}) },
  }
}

const press = async ($: EngineInterface, turn: Turn) => {
  try {
    const [session, cwd, { script, env }] = await Promise.all([$.session.id(), $.session.cwd(), writer($)])

    if (!(await $.fs.exists(script))) {
      $.ui.toast(`autodream-focus.sh was not found at ${script}, so nothing was changed. Run cc-autodream's install.sh.`)

      return
    }

    // The writer toggles: a second press on a tagged turn takes the tag back, and says which it did.
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

/**
 * The row as the engine draws it, with the focus button over its top-right corner. The button is absolutely positioned
 * so showing it moves nothing, and it sits on the right because the left edge of a split pane has no cells to spare.
 * Untagged it appears while the pointer is over the row; tagged it stays, so a glance down the transcript finds what
 * was marked.
 */
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
        width={WIDTH}
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

  // Only what the person typed (here or from the phone): a task notification or a peer's message is not theirs to tag.
  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    const beneath = await next(e)
    const kind = e.props.origin?.kind

    if (kind !== 'composer' && kind !== 'bridge') return beneath

    return withFocus($, $.ui.resolve(e), { uuid: e.requestId, role: 'user', text: e.props.text }, e.requestId, beneath)
  })

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const beneath = await next(e)

    return withFocus($, $.ui.resolve(e), { uuid: e.requestId, role: 'assistant', text: e.props.text }, e.requestId, beneath)
  })
}
