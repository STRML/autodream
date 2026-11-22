# runsh: a real changelog remote is cloned blob:none and sparse, with a non-cone pattern for one file

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_clone`)

## Context

`oh-my-pi` carries Cargo, bazel and a `node_modules` tree, and only one markdown file is wanted out of it. `git` ignores `--filter` on a local clone, so the suite's offline fixture must behave the same either way. Sparse cone mode refuses a file path outright; the old call failed and `|| true` hid it.

## Decision

`changelog_clone` adds `--filter=blob:none --sparse` only when the remote looks real (`*://*` or `*@*:*`). Blobs for the logged path are fetched on demand. After a sparse clone it runs `sparse-checkout set --no-cone "/$path"`, with the pattern anchored by a leading slash, stdout discarded, stderr appended to the run log and the status ignored (`|| true`). A local fixture gets a plain clone and no sparse step.

## Consequences

Because the clone is blobless, any later git call may need the network; that is why all calls on an owned cache go through `changelog_git` and why the `log -p` status is read, see `changelog-owned-cache-ignores-user-git-config` and `changelog-patch-read-through-file`.
