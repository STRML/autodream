# bin-b: the focus button is a text label, absolutely placed at the row's top right, hover-only until tagged

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-focus/hooks/register.tsx` (`LABEL`, `BUTTON_WIDTH`, `withFocus`)

## Context

CLAUDE.md "The focus mod" records the live findings: the engine measures an emoji with a selector wider than the terminal draws it and truncated it, a bare one drew too small, a plain `Button` pads its label so a narrower box shows an ellipsis, a `width` on a wrapper `Box` around `next(e)` is refused at runtime, and a left-hand column cost every row two cells in a narrow split.

## Decision

- The label is the words `autodream focus` with a `+` or a check mark prefix. Words cannot be measured wrong, and the check mark is one cell in every terminal.
- `BUTTON_WIDTH` is the untagged label's length plus 5: the padding a plain `Button` adds, with room to spare.
- The button's `Box` is `position="absolute"` at `top=0 right=0`, so showing it reflows nothing. Untagged it is `display: none` and `hover: { display: 'flex' }`; tagged it stays displayed, so a glance down the transcript finds what was marked.
- `beneath` (the engine's own row) is rendered unwrapped, with the button as a sibling in a column `Box`.

## Consequences

When the button is missing, search the session transcript for `ui.render (UserMessage) refused:` before guessing; the mod tests cannot catch these layout failures.
