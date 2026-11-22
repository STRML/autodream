# bin-a: the open-questions banner is posted through two senders, and the nightly run does not rely on a window opening

Status: accepted · Date: 2026-11-21 · Code: `bin/notify.sh` (the `$NOTIFIER` and `osascript` blocks)

## Context

The nightly run fires about 3am under launchd, when opening a GUI window silently fails to surface. `display notification` posts to Notification Center, which keeps the alert until it is dismissed, so it is waiting whenever the Mac is next used.

A banner's exit code does not prove it was shown (learned 2026-06). If the sender's notification permission is off, or a Focus or Do-Not-Disturb mode suppresses it, macOS drops the banner to Notification Center and the command still exits 0. The branded `cc-autodream.app` bundle is its own sender, so when the branding was introduced macOS treated it as a new app with notifications off by default. Every nightly banner vanished for a week while the log read "posted". That authorization state is TCC-protected and unreadable from a script, so the drop cannot be detected.

## Decision

- The banner is the reliable signal. The direct open of the inbox file stays as a best-effort extra on top (see `bin-a-notify-open-command-is-shell-snippet.md`).
- Both senders fire. `terminal-notifier` gives the clickable, branded banner (`-execute` opens the inbox file, `-group` collapses repeats). `osascript` posts through the system's already-trusted sender as a backup floor, so one blacked-out sender cannot black out the whole alert.
- The `osascript` backup is silent (no sound) so two landing banners do not chime twice. `AUTODREAM_NOTIFY_OSA_BACKUP=0` suppresses the backup. With no `terminal-notifier`, `osascript` is the primary sender and carries the sound.
- Posting is best-effort: a notification failure never breaks the run.

## Consequences

For click-to-open the cc-autodream sender's style must be "Alerts" (not "Banners", which auto-dismiss) in System Settings > Notifications, and it must be allowed through any Focus. Do not collapse the two senders into one on the grounds that a posted banner means a shown banner.
