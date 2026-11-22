import type { FocusTag } from '../types'

export const TEXT_CAP = 2_000

const ROLES: readonly string[] = ['user', 'assistant']

export const tagsFileFromEnv = (env: {
  HOME?: string | undefined
  AUTODREAM_DIR?: string | undefined
  AUTODREAM_TAGS_FILE?: string | undefined
}): string => env.AUTODREAM_TAGS_FILE || `${env.AUTODREAM_DIR || `${env.HOME ?? ''}/.claude/autodream`}/tags.jsonl`

export const focusScript = (env: {
  HOME?: string | undefined
  AUTODREAM_DIR?: string | undefined
  AUTODREAM_FOCUS_BIN?: string | undefined
}): string => env.AUTODREAM_FOCUS_BIN || `${env.AUTODREAM_DIR || `${env.HOME ?? ''}/.claude/autodream`}/autodream-focus.sh`

export const tagId = (session: string, uuid: string): string => `${session}:${uuid}`

export const forWriter = (text: string): string => {
  const chars = Array.from(text)

  return chars.length > TEXT_CAP + 1 ? chars.slice(0, TEXT_CAP + 1).join('') : text
}

const isString = (value: unknown): value is string => typeof value === 'string'

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

export const readTags = (text: string): FocusTag[] => {
  const tags: FocusTag[] = []

  for (const line of text.split('\n')) {
    if (line.trim() === '') continue

    const tag = parseTag(line)

    if (tag !== null) tags.push(tag)
  }

  return tags
}
