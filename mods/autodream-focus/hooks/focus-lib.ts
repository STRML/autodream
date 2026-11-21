import type { FocusTag } from '../types'

/** A tagged turn is a pointer plus enough of its text for the nightly note to stand alone. bin/autodream-focus.sh cuts a turn at this length. */
export const TEXT_CAP = 2_000

const ROLES: readonly string[] = ['user', 'assistant']

/**
 * Where the tags are, resolved the way bin/vault-notes.sh resolves them: an exported AUTODREAM_TAGS_FILE wins, else AUTODREAM_DIR (an empty
 * one counts as unset) plus tags.jsonl. The writer (bin/autodream-focus.sh) also reads `$AUTODREAM_DIR/config`; this mod cannot see a value
 * that lives only there, so a tags file moved only in the config shows no lit buttons here. Export it to move the mod's reading too.
 */
export const tagsFile = (env: {
  HOME?: string | undefined
  AUTODREAM_DIR?: string | undefined
  AUTODREAM_TAGS_FILE?: string | undefined
}): string => env.AUTODREAM_TAGS_FILE || `${env.AUTODREAM_DIR || `${env.HOME ?? ''}/.claude/autodream`}/tags.jsonl`

/**
 * The shared writer: an explicit override, else the install directory autodream links its scripts into. Every tag is written
 * by this one script, under its lock, for all three harnesses; the mod only reads the file to light the buttons.
 */
export const focusScript = (env: {
  HOME?: string | undefined
  AUTODREAM_DIR?: string | undefined
  AUTODREAM_FOCUS_BIN?: string | undefined
}): string => env.AUTODREAM_FOCUS_BIN || `${env.AUTODREAM_DIR || `${env.HOME ?? ''}/.claude/autodream`}/autodream-focus.sh`

/** One turn, across sessions: the id Claude Code gives the row, under the session that holds it. */
export const tagId = (session: string, uuid: string): string => `${session}:${uuid}`

/** The text handed to the writer: one character past its cap, so the writer sees a long turn and marks the cut with an ellipsis. */
export const forWriter = (text: string): string => text.slice(0, TEXT_CAP + 1)

const isString = (value: unknown): value is string => typeof value === 'string'

/** One line of tags.jsonl as a tag, or null when it is not one this mod can read. */
const parseTag = (line: string): FocusTag | null => {
  let raw: unknown

  try {
    raw = JSON.parse(line)
  } catch {
    return null
  }

  if (typeof raw !== 'object' || raw === null) return null

  const { id, session, uuid, role, text, cwd, taggedAt } = raw as Record<string, unknown>

  if (!isString(id) || !isString(session) || !isString(uuid) || !isString(role) || !ROLES.includes(role)) return null
  if (!isString(text) || !isString(taggedAt)) return null

  return { ...raw, id, session, uuid, role: role as FocusTag['role'], text, cwd: isString(cwd) ? cwd : '', taggedAt }
}

/** The tags tags.jsonl holds. A line this mod cannot read (torn, hand-edited, from a later version) is skipped here and left alone on disk. */
export const readTags = (text: string): FocusTag[] => {
  const tags: FocusTag[] = []

  for (const line of text.split('\n')) {
    if (line.trim() === '') continue

    const tag = parseTag(line)

    if (tag !== null) tags.push(tag)
  }

  return tags
}
