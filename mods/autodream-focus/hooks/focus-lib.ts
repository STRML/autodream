import type { FocusTag } from '../types'

/** A tagged turn is a pointer plus enough of its text for the nightly note to stand alone. bin/autodream-focus.sh cuts a turn at this length. */
export const TEXT_CAP = 2_000

const ROLES: readonly string[] = ['user', 'assistant']

/**
 * Where the tags are, resolved the way bin/vault-notes.sh resolves them: an exported AUTODREAM_TAGS_FILE wins, else AUTODREAM_DIR (an empty
 * one counts as unset) plus tags.jsonl. This is only the fallback: the mod asks the writer (`autodream-focus.sh path`), which also reads
 * `$AUTODREAM_DIR/config`, a file this mod cannot source.
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

/**
 * The text handed to the writer: one character past its cap, so the writer sees a long turn and marks the cut with an
 * ellipsis. Counted in code points, as the writer counts, not in UTF-16 units: a turn of emoji cut at 2,001 units would be
 * about 1,000 characters, under the writer's cap, so it would add no ellipsis and could keep half a surrogate pair.
 */
export const forWriter = (text: string): string => {
  const chars = Array.from(text)

  return chars.length > TEXT_CAP + 1 ? chars.slice(0, TEXT_CAP + 1).join('') : text
}

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
