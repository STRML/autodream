# 0014: Upstream changelog watch

Status: accepted · Governs: `bin/run.sh`

This record holds 12 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: Upstream changelog window](#background-upstream-changelog-window)
- [every changelog source failing in one run posts a warning banner, one failing posts nothing](#every-changelog-source-failing-in-one-run-posts-a-warning-banner-one-failing-posts-nothing)
- [a changelog cache is "owned" only when its path resolves physically inside the install's cache directory](#a-changelog-cache-is-owned-only-when-its-path-resolves-physically-inside-the-installs-cache-directory)
- [a real changelog remote is cloned blob:none and sparse, with a non-cone pattern for one file](#a-real-changelog-remote-is-cloned-blobnone-and-sparse-with-a-non-cone-pattern-for-one-file)
- [changelog lines are deduped by the line and the release header it sits under, with blank lines exempt](#changelog-lines-are-deduped-by-the-line-and-the-release-header-it-sits-under-with-blank-lines-exempt)
- [an owned changelog cache follows its remote with fetch and reset --hard, a foreign repo keeps pull --ff-only](#an-owned-changelog-cache-follows-its-remote-with-fetch-and-reset---hard-a-foreign-repo-keeps-pull---ff-only)
- [every git call on an owned changelog cache runs with no user or system git config](#every-git-call-on-an-owned-changelog-cache-runs-with-no-user-or-system-git-config)
- [the changelog patch is read through a file so git's own status is seen](#the-changelog-patch-is-read-through-a-file-so-gits-own-status-is-seen)
- [each changelog section is capped by line count, and a bad cap falls back to 400](#each-changelog-section-is-capped-by-line-count-and-a-bad-cap-falls-back-to-400)
- [changelog sections are appended to a named file, never emitted on stdout](#changelog-sections-are-appended-to-a-named-file-never-emitted-on-stdout)
- [the changelog window watches Claude Code, Codex and OMP, each with its own path, cache and failure line](#the-changelog-window-watches-claude-code-codex-and-omp-each-with-its-own-path-cache-and-failure-line)
- [the changelog source loop runs in the current shell and its first-error variable is a dynamically scoped local](#the-changelog-source-loop-runs-in-the-current-shell-and-its-first-error-variable-is-a-dynamically-scoped-local)

## Background: Upstream changelog window

This section was moved here from the former CLAUDE.md. Its original title: "Upstream changelog window".

`changelog_window()` runs `git log -p` on a changelog over `[TARGET_DATE, NEXT_DATE)` (real commit dates; the raw CHANGELOG has no dates, the git history does). The inserted lines go to `changelog-window.md`, which L2 reads for the "Upstream harness changes" report section. Any git failure writes a note and never aborts the run. There is no remote `git blame`; that is why we keep a persistent local clone.

Since 2026-09-11 it watches **three** harnesses rather than one, because the user works across all three: Claude Code, Codex, and OMP. `changelog_sources()` holds the list as `name|remote|path|cache-dir` records. Four things in that design are load-bearing:

- **The path is per-source.** OMP is a monorepo with no root CHANGELOG — the CLI's log is at `packages/coding-agent/CHANGELOG.md`. A hardcoded `CHANGELOG.md` silently yields an empty section for it.
- **Failures are per-source.** Each harness gets its own cache, its own clone/pull, and its own `## <Harness>` section in the one output file. A dead remote writes an explicit failure line into its own section; it never blanks the others, and it never produces an empty file that reads like a quiet night upstream.
- **`CHANGELOG_REMOTE` selects a single source and suppresses the defaults.** Back-compat for the old one-repo knob, and the reason the test suite stays offline: the changelog test points that variable at a local fixture, and a default list that still ran would have the suite cloning three real remotes. `AUTODREAM_CHANGELOG_SOURCES` overrides the whole set.
- **An owned cache ignores the user's git config.** Every git call on a cache under `$AUTODREAM_DIR/cache` (fetch, reset, clone, sparse-checkout, rev-parse, `log -p`) goes through `changelog_git`, which sets `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0`. This host's `~/.gitconfig` rewrites `https://github.com/` to `git@github.com:`, and on 2026-10-30 and 10-31 every source failed with `Permission denied (publickey)` while the anonymous https fetch worked. It is every call and not just the fetch, because the caches are blob:none partial clones and `log -p` fetches old blobs on demand through the same config; with only the fetch fixed, that lazy fetch fails into `2>/dev/null` and the section reads as a quiet night. `changelog_window` creates `$AUTODREAM_DIR/cache` first, since `cache_owns` resolves that root physically and a fresh install's first clone would otherwise run with the user's config. Below the root, a cache path's missing parents are skipped up to the nearest one that exists, and that one is resolved, so `cache/nested/source` is owned on its first clone (#174); only names that do not exist at all are skipped, so a symlink in the path (dangling or not) is still resolved and refused when it leads out. `test_changelog_nested_cache_path_is_owned_on_first_clone` pins both. A repo outside the cache (a `CLAUDE_CODE_REPO` checkout) keeps the user's config. The cost: a private remote whose token comes from a credential helper in `~/.gitconfig` cannot be read from an owned cache, so point such a source's cache path outside `$AUTODREAM_DIR/cache`. `test_changelog_owned_cache_ignores_global_insteadof` points `HOME` at a `.gitconfig` that rewrites `file://` to a bogus path, and its second run reads a commit whose blob no checkout fetched, so the lazy fetch is what it tests.
- **A failure quotes git, and a total failure posts a banner.** The section line reads `Git pull failed (<cause>); X changes not checked this run.`, and git's whole stderr still goes to the run log. The patch read (`git log -p`) goes through a file so its status is seen: a failure there is `Git log failed (<cause>)`, never "No changelog commits in this window". The cause is the FIRST stderr line that is not blank, `hint:` or `warning:` (any case: OpenSSH prints `Warning: Permanently added ...` first), not the last: git ends with two lines of advice ("Please make sure you have the correct access rights / and the repository exists."). The line is cut to 200 characters, and backticks, angle brackets and control characters are swapped out or removed. When every configured source fails in one run, `notify.sh --warning` posts a WARNING banner naming the first failure. `--warning` exists so this does not say FAILED or drop a `<date>-FAILED.txt` into the inbox for a run that still writes its report. One source failing posts nothing.
- **Sections are appended to a named file, never emitted on stdout.** `log()` writes to stdout, so an earlier draft that built the file inside a `{ … } > "$out"` block filed every "cloning …" progress line as an upstream release note. Caught in a live run against all three remotes; `test_changelog_multi_source` pins it.

Output is deduped and capped. A changelog edited across many commits in one window re-inserts the same lines repeatedly — OMP moved 119 commits over 2026-09-08..10 and emitted `## [18.1.16]` three times, each with its bullets. Non-blank lines are deduped order-preserving (blanks exempt, or the markdown collapses into one paragraph) and each section is capped at `AUTODREAM_CHANGELOG_MAX_LINES` (400) with an explicit truncation note, so one chatty monorepo cannot crowd the other harnesses out of L2's context.

## every changelog source failing in one run posts a warning banner, one failing posts nothing

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_warn_all_failed`)

### Context

Every source failing is a broken fetch path on this host (lost credentials, a rewritten URL, no network), not a quiet night upstream, and the per-source lines sit in a findings file nobody reads until the report. A single failing source is already in its own section. See docs/adr/0014-changelog-watch.md#background-upstream-changelog-window, "Upstream changelog window".

### Decision

When `failed` equals `sources` (and is above zero), `changelog_warn_all_failed` logs and runs `notify.sh --warning <date> "upstream changelog check failed for all N source(s); first: <first error>"`. A notify failure is logged and not fatal. It posts nothing when no source was configured or when `$AUTODREAM_DIR/notify.sh` is not executable (the failure is still logged). `--warning` is used so the banner does not say FAILED or drop a `<date>-FAILED.txt` into the inbox for a run that still writes its report.

### Consequences

Do not escalate a single failing source to a banner.

## a changelog cache is "owned" only when its path resolves physically inside the install's cache directory

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`cache_owns`, `changelog_clone`, `changelog_window`)

### Context

Ownership gates two things: `rm -rf` of a cache path before cloning, and running git without the user's config. `AUTODREAM_CHANGELOG_SOURCES` names the path, so a typo pointing at a real non-git directory must not be deleted to make room for a clone (debate review of e95e2f2). The path as written proves nothing: `$AUTODREAM_DIR/cache/../x` matches the prefix, and so does `$AUTODREAM_DIR/cache/link/x` where `link` points elsewhere, and `rm -rf` follows both (Codex review of 0129fc0). A nested source such as `cache/nested/source` must be owned on its first clone (#174).

### Decision

`cache_owns` refuses any path containing `..`, resolves `$AUTODREAM_DIR/cache` with `pwd -P`, then walks up from the path's parent past names that do not exist at all (neither a file nor a symlink, so a dangling symlink is still resolved or refused), resolves that nearest existing ancestor physically and tests that it sits under the cache. With no `..`, what `clone` creates below that ancestor stays below it. `changelog_clone` clears the repo directory only when owned; outside the cache nothing is deleted, a non-empty non-git directory is refused with a failure section, and `git clone` accepts a missing or empty target. `changelog_window` creates `$AUTODREAM_DIR/cache` first, because `cache_owns` resolves that directory as the root every owned path must sit under, so on a fresh install the first clone would otherwise count as foreign and run with the user's git config.

### Consequences

`test_changelog_refuses_foreign_cache_dir` pins that a non-git directory, a path that climbs out with `..` and a path through a symlink inside the cache are never deleted. `test_changelog_nested_cache_path_is_owned_on_first_clone` pins the nested case and a symlink out of the cache with a missing remainder behind it. Do not replace the physical resolve with a prefix test.

## a real changelog remote is cloned blob:none and sparse, with a non-cone pattern for one file

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_clone`)

### Context

`oh-my-pi` carries Cargo, bazel and a `node_modules` tree, and only one markdown file is wanted out of it. `git` ignores `--filter` on a local clone, so the suite's offline fixture must behave the same either way. Sparse cone mode refuses a file path outright; the old call failed and `|| true` hid it.

### Decision

`changelog_clone` adds `--filter=blob:none --sparse` only when the remote looks real (`*://*` or `*@*:*`). Blobs for the logged path are fetched on demand. After a sparse clone it runs `sparse-checkout set --no-cone "/$path"`, with the pattern anchored by a leading slash, stdout discarded, stderr appended to the run log and the status ignored (`|| true`). A local fixture gets a plain clone and no sparse step.

### Consequences

Because the clone is blobless, any later git call may need the network; that is why all calls on an owned cache go through `changelog_git` and why the `log -p` status is read, see `changelog-owned-cache-ignores-user-git-config` and `changelog-patch-read-through-file`.

## changelog lines are deduped by the line and the release header it sits under, with blank lines exempt

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_one`, the `awk` that builds `added`)

### Context

A changelog edited across many commits in one window re-inserts the same lines repeatedly. OMP's log moved 119 commits for 2026-09-08 through 09-10 and emitted `## [18.1.16]` three times with its bullets under each. Blank lines are exempt or the markdown collapses into one paragraph. A window-wide key dropped `### Fixed` and `- Fixed a crash`, which repeat across releases, from the second release, leaving its bullets under no heading or under the first release's (review of https://github.com/STRML/cc-autodream/pull/83).

### Decision

The inserted `+` lines of the patch (minus the `+++` file header) go through `awk '!NF { print; next } /^## \[/ { hdr = $0 } !seen[hdr SUBSEP $0]++'`: every blank line is kept, and any other line is kept once per `## [` release header.

### Consequences

Do not widen the key to the whole window, and do not dedupe blank lines. Output is also capped, see `changelog-per-source-line-cap`.

## an owned changelog cache follows its remote with fetch and reset --hard, a foreign repo keeps pull --ff-only

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_sync`)

### Context

`git pull --ff-only` failed forever once a fork was rebased and force-pushed. The OMP fork is rebased on every upstream sync, so the section read "pull failed" every night. A cache this install owns is disposable. A repo outside the cache (a `CLAUDE_CODE_REPO` checkout) may hold someone's work.

### Decision

For an owned cache `changelog_sync` runs `fetch --quiet origin` then `reset --hard --quiet FETCH_HEAD` (both through `changelog_git yes`). For a foreign repo it runs the conservative `git pull --ff-only --quiet`, because resetting it would discard someone's work.

### Consequences

Do not use `reset --hard` on anything `cache_owns` has not approved (see `changelog-cache-ownership-resolved-physically`). A fork that is rebased makes `pull --ff-only` the wrong tool for any cache we own. `test_changelog_survives_a_force_pushed_remote` pins it.

## every git call on an owned changelog cache runs with no user or system git config

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_git`)

### Context

An owned cache reads a public remote. This host's `~/.gitconfig` rewrites `https://github.com/` to `git@github.com:` (`url.git@github.com:.insteadOf`), and with no key loaded all three sources failed on 2026-10-30 and 10-31 while anonymous https worked. Fixing only the fetch is not enough: the caches are `blob:none` partial clones, so reset and `git log -p` fetch missing blobs from the same remote on demand through the same config, and a failure there reads as a quiet night. See docs/adr/0014-changelog-watch.md#background-upstream-changelog-window, "Upstream changelog window".

### Decision

`changelog_git yes <args>` runs `git` with `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0`. Every call on an owned cache (fetch, reset, clone, sparse-checkout, rev-parse, `log -p`) goes through it, not just fetch and clone. A repo outside the cache is someone's checkout and keeps their config (`changelog_git no`).

### Consequences

A private remote whose token comes from a credential helper in `~/.gitconfig` cannot be read from an owned cache; point such a source's cache path outside `$AUTODREAM_DIR/cache`. `test_changelog_owned_cache_ignores_global_insteadof` pins it, and its second run reads a commit whose blob no checkout fetched, so the lazy fetch is what it tests. A new git call on a source's repo must use `changelog_git`.

## the changelog patch is read through a file so git's own status is seen

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_one`, `changelog_patch`, `changelog_step`)

### Context

In a `blob:none` cache `git log -p` fetches old blobs from the remote, and a failure there piped straight into the filters read as "No changelog commits in this window" (panel review of PR #173).

### Decision

`changelog_one` makes a `mktemp` file under `${TMPDIR:-/tmp}` and runs `changelog_patch`, which writes `git log -p --reverse --since --until -- <path>` to it, through `changelog_step`, so git's stderr goes to the run log and a failure writes `Git log failed (<cause>)` into the source's section, removes the scratch file and fails the source. Only then do the `grep`/`awk` filters read the file. Failing to make the scratch file is its own failure section (`No scratch file for the changelog diff`).

### Consequences

Do not pipe `git log -p` straight into the filters. A failed log must never read as a quiet night; `test_changelog_log_failure_is_not_a_quiet_night` pins it with a git shim that fails only `log -p`. See docs/adr/0014-changelog-watch.md#background-upstream-changelog-window, "Upstream changelog window".

## each changelog section is capped by line count, and a bad cap falls back to 400

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_one`, `AUTODREAM_CHANGELOG_MAX_LINES`)

### Context

One chatty monorepo must not crowd the other harnesses out of L2's context, so the cap is per section: a quiet source is never truncated for a loud one. A non-numeric cap made the `-gt` test error out as false under `set -u` without `-e`, so the section went out uncapped (debate review of e95e2f2). A pattern test is not enough: `00` is all digits and still zero, and `head -n 00` then fails and drops the section's content.

### Decision

`cap` is `AUTODREAM_CHANGELOG_MAX_LINES` (default 400). It is validated by a pattern check that it is digits and then numerically that it is greater than 0; otherwise a log line says it is not a positive integer and 400 is used. When the deduped section exceeds the cap it is cut with `head -n` and an explicit `[...truncated: N lines in window, showing first CAP. Raise AUTODREAM_CHANGELOG_MAX_LINES to see the rest.]` line is appended.

### Consequences

Truncation must stay explicit, never silent. Keep the cap per section. Do not validate the cap by pattern alone. `test_changelog_refuses_foreign_cache_dir` pins that `abc` and `00` fall back to 400.

## changelog sections are appended to a named file, never emitted on stdout

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_window`, `changelog_one`)

### Context

`log()` writes to stdout. A version that built the changelog inside a `{ ... } > "$out"` block silently interleaved every "cloning ..." progress line into the file L2 then reads as release notes. Caught in a live run against all three remotes; `test_changelog_multi_source` pins it. See docs/adr/0014-changelog-watch.md#background-upstream-changelog-window, "Upstream changelog window".

### Decision

`changelog_window` truncates `$FINDINGS_DIR/changelog-window.md` once with its header line, then every `changelog_one` appends its own section to `$out` with `>>`. Nothing in `changelog_window` may wrap the loop in a `> "$out"` block.

### Consequences

Any new progress line is safe only because it goes through `log()` outside the file. Do not turn the section writers into stdout emitters.

## the changelog window watches Claude Code, Codex and OMP, each with its own path, cache and failure line

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_sources`, `changelog_window`, `changelog_one`)

### Context

See docs/adr/0014-changelog-watch.md#background-upstream-changelog-window, "Upstream changelog window". There is no remote `git blame` or `log`, so a persistent local cache is kept (not a tmpdir) and nightly cost is one delta fetch (the original comment said `git pull`; an owned cache now fetches and resets, see `changelog-owned-cache-follows-remote-by-reset`). git is the only dependency. The user works across three harnesses, and a release note only earns its place in the report when it lands in a tool in use. OMP is a monorepo with no root CHANGELOG; the CLI's log is at `packages/coding-agent/CHANGELOG.md`. The window matches the session scan exactly, so each release is reported once.

### Decision

`changelog_sources` prints `name|remote|path|cache-dir` records: Claude Code, Codex and OMP. The path is per source, never assumed. Each source has its own cache, its own clone/pull and its own `## <name>` section, so a dead remote writes an explicit failure line into its own section and never an empty file that reads like a quiet night upstream. An explicit `CHANGELOG_REMOTE` selects a SINGLE source and suppresses the defaults: back-compat for the old one-repo knob and load-bearing for the test suite, whose changelog test points it at a local fixture; a default list that still ran would have the suite cloning three real remotes, breaking the promise that it never touches the network. `AUTODREAM_CHANGELOG_SOURCES` (`;`-separated) overrides the whole set. The OMP default is `STRML/oh-my-pi`, the fork this host runs, which is rebased onto upstream on every sync, so it carries the build in use; to watch upstream itself set `AUTODREAM_CHANGELOG_SOURCES`. The Claude Code cache defaults to `$AUTODREAM_DIR/cache/claude-code` (`CLAUDE_CODE_REPO` overrides it). `AUTODREAM_CHANGELOG=0` disables the whole check, and a missing `git` skips it. Any failure is recorded in the output, never aborts the pipeline.

### Consequences

Do not hardcode `CHANGELOG.md` for a new source. Keep the `CHANGELOG_REMOTE` suppression, or the suite goes to the network. A new source needs its own cache directory under `$AUTODREAM_DIR/cache` to be treated as owned, see `changelog-cache-ownership-resolved-physically`.

## the changelog source loop runs in the current shell and its first-error variable is a dynamically scoped local

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_window`, `changelog_fail`, `changelog_warn_all_failed`)

### Context

The loop sets counters (`sources`, `failed`), and `changelog_fail` sets `CHANGELOG_FIRST_ERR`, all of which are read after the loop. A piped `while read` runs in a subshell and loses them.

### Decision

The loop reads from a here-string (`<<< "$srcs"`), not a pipe. `CHANGELOG_FIRST_ERR` is declared `local` in `changelog_window` and is seen by `changelog_fail` and `changelog_warn_all_failed` through bash's dynamic scoping, so it never outlives the run's one changelog pass.

### Consequences

Do not pipe into this loop, and do not make `CHANGELOG_FIRST_ERR` global. A function that sets it must be called from inside `changelog_window`.
