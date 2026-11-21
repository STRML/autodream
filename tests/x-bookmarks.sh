#!/bin/bash
# Tests for bin/x-bookmarks.sh — the fetch, the read state, and every way it degrades.
#
# No network. `curl` is shimmed by a fake earlier on PATH (same trick tests/review-skip.sh
# uses for `claude`), and the queryId cache is pre-seeded so the bundle-scraping walk is
# skipped — that walk is against a live third party and cannot be meaningfully faked.
#
# What is actually worth pinning here is everything downstream of the HTTP call, because
# that is where the two bugs found during development lived: emit ordering came out
# oldest-first, and mark-read silently no-opped on every line. Both were invisible to a
# smoke test and both would have quietly wasted the feature.
#
# Usage:  tests/x-bookmarks.sh
# Exit:   0 if every assertion passes, 1 otherwise.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
# shellcheck source=/dev/null
. "$HERE/lib-tmp.sh"; suite_tmp xbmt
BIN="$REPO/bin/x-bookmarks.sh"

pass=0; fail=0
ok(){ printf '  ok   - %s\n' "$1"; pass=$((pass + 1)); }
no(){ printf '  FAIL - %s\n' "$1"; fail=$((fail + 1)); }
assert_file(){     [ -f "$1" ] && ok "$2" || no "$2 (missing: $1)"; }
assert_grep(){     grep -q "$2" "$1" 2>/dev/null && ok "$3" || no "$3 (no /$2/ in $1)"; }
assert_nogrep(){   grep -q "$2" "$1" 2>/dev/null && no "$3 (/$2/ unexpectedly in $1)" || ok "$3"; }
assert_eq(){       [ "$1" = "$2" ] && ok "$3" || no "$3 (got [$1] want [$2])"; }

# A two-bookmark page in the real response shape: bookmark_timeline_v2 -> instructions ->
# entries -> content.itemContent.tweet_results.result, author under core.user_results.
# The ids are deliberately NOT in ascending file order, so an emit that trusts file
# position instead of sorting by id fails this fixture.
fixture_page(){ cat <<'JSON'
{"data":{"bookmark_timeline_v2":{"timeline":{"instructions":[{"type":"TimelineAddEntries","entries":[
{"entryId":"tweet-100","content":{"itemContent":{"tweet_results":{"result":{
  "rest_id":"100",
  "core":{"user_results":{"result":{"core":{"screen_name":"olderauthor","name":"Older"}}}},
  "legacy":{"full_text":"the older post","created_at":"Mon Jul 28 10:00:00 +0000 2026","entities":{"urls":[]}}}}}}},
{"entryId":"tweet-200","content":{"itemContent":{"tweet_results":{"result":{
  "rest_id":"200",
  "core":{"user_results":{"result":{"core":{"screen_name":"newerauthor","name":"Newer"}}}},
  "legacy":{"full_text":"the newer post","created_at":"Fri Aug 01 10:00:00 +0000 2026","entities":{"urls":[{"expanded_url":"https://example.com/article"}]}}}}}}},
{"entryId":"cursor-bottom-0","content":{"cursorType":"Bottom","value":"CURSOR_END"}}
]}]}}}}
JSON
}

# Fake curl. Honours -o <file> and -w '%{http_code}' the way the script uses them:
# writes MOCK_BODY (or the fixture) to the -o path and prints MOCK_CODE.
make_curl_shim(){ # $1=bindir
  mkdir -p "$1"
  cat > "$1/curl" <<'SH'
#!/bin/bash
out=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  prev="$a"
done
[ -n "$out" ] && { if [ -n "${MOCK_BODY:-}" ] && [ -f "${MOCK_BODY}" ]; then cat "$MOCK_BODY" > "$out"; else printf '{}' > "$out"; fi; }
printf '%s' "${MOCK_CODE:-200}"
exit 0
SH
  chmod +x "$1/curl"
  # Fake sleep: the script paces its pages with a real `sleep 2`, which made every collect in this
  # suite wait. Record the request instead (MOCK_SLEEP_LOG) so a test can still say what was asked.
  cat > "$1/sleep" <<'SH'
#!/bin/bash
[ -n "${MOCK_SLEEP_LOG:-}" ] && printf '%s\n' "$*" >> "$MOCK_SLEEP_LOG"
exit 0
SH
  chmod +x "$1/sleep"
}

# Fresh sandbox with credentials and a pre-seeded queryId so detection is skipped.
setup(){
  local root; root=$(mktemp -d "${TMPDIR:-/tmp}/xbmt.XXXXXX")
  mkdir -p "$root/state" "$root/findings" "$root/bin"
  printf 'X_AUTH_TOKEN=token\nX_CT0=csrf\n' > "$root/creds"; chmod 600 "$root/creds"
  printf 'CACHEDQUERYID' > "$root/state/query-id"
  make_curl_shim "$root/bin"
  fixture_page > "$root/page.json"
  printf '%s' "$root"
}
run_bm(){ # $1=root, rest = args ; MOCK_CODE/MOCK_BODY/X_CREDS_FILE inherited
  local root="$1"; shift
  # AUTODREAM_DIR and AUTODREAM_CONFIG are pinned into the sandbox because the script
  # sources its config: without this the suite would read the developer's real
  # ~/.claude/autodream/config and inherit whatever they set there.
  PATH="$root/bin:$PATH" \
  AUTODREAM_DIR="$root" AUTODREAM_CONFIG="$root/no-such-config" \
  X_CREDS_FILE="${X_CREDS_FILE:-$root/creds}" X_STATE_DIR="$root/state" \
  X_MAX_PAGES="${X_MAX_PAGES:-1}" MOCK_BODY="${MOCK_BODY:-$root/page.json}" MOCK_SLEEP_LOG="${MOCK_SLEEP_LOG:-}" \
  bash "$BIN" "$@" > "$root/out.txt" 2>&1
}

# ---------------------------------------------------------------------------

test_pages_are_paced_and_the_last_one_is_not_waited_on(){
  echo "# pacing: two seconds between pages, and no wait after the last page the run will fetch"
  local root; root=$(setup)
  : > "$root/sleeps"
  X_MAX_PAGES=1 MOCK_SLEEP_LOG="$root/sleeps" run_bm "$root" collect "$root/findings"
  assert_eq "$(wc -l < "$root/sleeps" | tr -d ' ')" "0" "a one-page run never sleeps: nothing follows the page"
  rm -rf "$root"
  root=$(setup)
  : > "$root/sleeps"
  X_MAX_PAGES=2 MOCK_SLEEP_LOG="$root/sleeps" run_bm "$root" collect "$root/findings"
  assert_eq "$(cat "$root/sleeps")" "2" "a two-page run waits once, two seconds, between the pages"
  rm -rf "$root"
}

test_not_configured(){
  echo "# no credentials -> a not-configured stub, an empty manifest, exit 0"
  local root; root=$(setup)
  X_CREDS_FILE="$root/does-not-exist" run_bm "$root" collect "$root/findings"
  assert_eq "$?" "0" "exits 0 with no credentials"
  assert_file "$root/findings/x-bookmarks.md" "the output file is written anyway"
  assert_grep "$root/findings/x-bookmarks.md" "not configured" "it says the feature is not configured"
  assert_nogrep "$root/findings/x-bookmarks.md" "fetch failed" "an absent config is not reported as a failure"
  assert_eq "$(wc -c < "$root/findings/x-bookmarks-manifest.txt" | tr -d ' ')" "0" "the manifest is empty"
  rm -rf "$root"
}

test_auth_failure(){
  echo "# HTTP 401 -> the fetch-failed header names the re-paste remediation, exit 0"
  local root; root=$(setup)
  MOCK_CODE=401 run_bm "$root" collect "$root/findings"
  assert_eq "$?" "0" "exits 0 so the nightly run continues"
  assert_grep "$root/findings/x-bookmarks.md" "^# x-bookmarks: fetch failed" "the first line is the failure header"
  assert_grep "$root/findings/x-bookmarks.md" "auth_token" "the remediation names the cookies to re-paste"
  rm -rf "$root"
}

test_stale_queryid_clears_cache(){
  echo "# HTTP 400 -> the cached queryId is dropped so the next run re-scrapes it"
  local root; root=$(setup)
  MOCK_CODE=400 run_bm "$root" collect "$root/findings"
  [ ! -f "$root/state/query-id" ] && ok "the stale queryId cache was cleared" || no "the stale queryId cache survived"
  assert_grep "$root/findings/x-bookmarks.md" "400" "the report names the status code"
  rm -rf "$root"
}

test_queryid_source_is_recorded(){
  echo "# every collect records where the queryId came from, including when it never looked"
  local root; root=$(setup)
  # The seeded cache means the bundle walk is not exercised — which is the state #38
  # exists to make visible, since the fetch works either way.
  run_bm "$root" collect "$root/findings"
  assert_grep "$root/findings/x-bookmarks-queryid.txt" "^cache$" "a reused id is recorded as cache, not as a working walk"
  rm -f "$root/state/query-id"
  run_bm "$root" collect "$root/findings2"
  assert_grep "$root/findings2/x-bookmarks-queryid.txt" "^failed$" "a walk that found nothing is recorded as failed"
  X_CREDS_FILE="$root/does-not-exist" run_bm "$root" collect "$root/findings3"
  assert_grep "$root/findings3/x-bookmarks-queryid.txt" "^not_attempted$" "and an unconfigured run says the walk never ran"
  rm -rf "$root"
}

test_parse_and_emit(){
  echo "# a real-shaped response parses into markdown, a manifest, and state"
  local root; root=$(setup)
  run_bm "$root" collect "$root/findings"
  local md="$root/findings/x-bookmarks.md"
  assert_grep "$md" "@newerauthor"       "the author handle is read from user core"
  assert_grep "$md" "the newer post"     "the post text is present"
  assert_grep "$md" "x.com/newerauthor/status/200" "the permalink is built from handle and id"
  assert_grep "$md" "example.com/article" "the expanded link is included"
  assert_eq "$(wc -l < "$root/findings/x-bookmarks-manifest.txt" | tr -d ' ')" "2" "both bookmarks are in the manifest"
  assert_eq "$(wc -l < "$root/state/seen.jsonl" | tr -d ' ')" "2" "both bookmarks are recorded in state"
  rm -rf "$root"
}

test_newest_first(){
  echo "# emit order is by tweet id descending, not by position in the state file"
  local root; root=$(setup)
  run_bm "$root" collect "$root/findings"
  assert_eq "$(head -1 "$root/findings/x-bookmarks-manifest.txt")" "200" "the newer bookmark is listed first"
  rm -rf "$root"
}

test_mark_read_then_not_relisted(){
  echo "# once marked read, a bookmark is not offered again"
  local root; root=$(setup)
  run_bm "$root" collect "$root/findings"
  run_bm "$root" mark-read "$root/findings"
  assert_eq "$(grep -c '"read_on":null' "$root/state/seen.jsonl")" "0" "no bookmark is left unread"
  assert_eq "$(wc -l < "$root/state/seen.jsonl" | tr -d ' ')" "2" "marking read does not drop state rows"

  mkdir -p "$root/findings2"
  run_bm "$root" collect "$root/findings2"
  assert_nogrep "$root/findings2/x-bookmarks.md" "the newer post" "an already-read bookmark is not re-listed"
  assert_eq "$(wc -c < "$root/findings2/x-bookmarks-manifest.txt" | tr -d ' ')" "0" "the second manifest is empty"
  rm -rf "$root"
}

test_mark_read_idempotent(){
  echo "# mark-read runs twice without corrupting state"
  local root; root=$(setup)
  run_bm "$root" collect "$root/findings"
  run_bm "$root" mark-read "$root/findings"
  local before; before=$(cat "$root/state/seen.jsonl")
  run_bm "$root" mark-read "$root/findings"
  assert_eq "$(cat "$root/state/seen.jsonl")" "$before" "a second mark-read changes nothing"
  rm -rf "$root"
}

test_mark_read_no_manifest(){
  echo "# mark-read with no manifest is a no-op, not an error"
  local root; root=$(setup)
  run_bm "$root" collect "$root/findings"
  mkdir -p "$root/empty"
  run_bm "$root" mark-read "$root/empty"
  assert_eq "$?" "0" "exits 0 with no manifest"
  assert_eq "$(grep -c '"read_on":null' "$root/state/seen.jsonl")" "2" "state is untouched"
  rm -rf "$root"
}

test_unread_survive_a_failed_fetch(){
  echo "# a fetch failure still serves bookmarks captured earlier, with a banner"
  local root; root=$(setup)
  run_bm "$root" collect "$root/findings"          # populate state, leave unread
  mkdir -p "$root/findings2"
  MOCK_CODE=401 run_bm "$root" collect "$root/findings2"
  local md="$root/findings2/x-bookmarks.md"
  assert_grep "$md" "the newer post" "previously-captured unread bookmarks are still offered"
  assert_grep "$md" "could not reach X" "the staleness is disclosed"
  assert_eq "$(wc -l < "$root/findings2/x-bookmarks-manifest.txt" | tr -d ' ')" "2" "they are still manifested for mark-read"
  rm -rf "$root"
}

test_state_not_duplicated(){
  echo "# collecting the same page twice does not duplicate state rows"
  local root; root=$(setup)
  run_bm "$root" collect "$root/findings"
  mkdir -p "$root/findings2"
  run_bm "$root" collect "$root/findings2"
  assert_eq "$(wc -l < "$root/state/seen.jsonl" | tr -d ' ')" "2" "state still holds exactly two rows"
  rm -rf "$root"
}

test_text_is_capped(){
  echo "# an overlong post is truncated so a thread cannot blow the token budget"
  local root; root=$(setup)
  local long; long=$(printf 'x%.0s' $(seq 1 3000))
  jq --arg t "$long" '.data.bookmark_timeline_v2.timeline.instructions[0].entries[0].content.itemContent.tweet_results.result.legacy.full_text = $t' \
    "$root/page.json" > "$root/page-long.json"
  MOCK_BODY="$root/page-long.json" X_MAX_TEXT=100 run_bm "$root" collect "$root/findings"
  assert_grep "$root/findings/x-bookmarks.md" '\[…\]' "the truncation marker is present"
  [ "$(wc -c < "$root/findings/x-bookmarks.md")" -lt 2000 ] \
    && ok "the emitted file stayed small" || no "the emitted file was not truncated"
  rm -rf "$root"
}

# ---- Regressions from the PR #37 review -------------------------------------------

test_duplicate_ids_within_one_fetch(){
  echo "# regression: the same id twice in one fetch produces one state row, not two"
  local root; root=$(setup)
  # X's cursor pagination genuinely returns a post twice when the timeline shifts between
  # requests. Dedupe used to consult only the pre-existing state file, so neither copy
  # looked known and both were written.
  jq -c '.data.bookmark_timeline_v2.timeline.instructions[0].entries =
          [ .data.bookmark_timeline_v2.timeline.instructions[0].entries[0],
            .data.bookmark_timeline_v2.timeline.instructions[0].entries[0],
            .data.bookmark_timeline_v2.timeline.instructions[0].entries[1] ]' \
    "$root/page.json" > "$root/page-dup.json"
  MOCK_BODY="$root/page-dup.json" run_bm "$root" collect "$root/findings"
  assert_eq "$(wc -l < "$root/state/seen.jsonl" | tr -d ' ')" "2" "the duplicate produced one row, not two"
  assert_eq "$(wc -l < "$root/findings/x-bookmarks-manifest.txt" | tr -d ' ')" "2" "and is listed once in the manifest"
  rm -rf "$root"
}

test_auth_failure_reason_is_not_empty(){
  echo "# regression: the credential-expiry reason survives the subshell that produced it"
  local root; root=$(setup)
  # fail() used to set a shell variable from inside nested command substitutions, so the
  # reason died with the subshell and the report said a fetch failed for no stated reason.
  MOCK_CODE=401 run_bm "$root" collect "$root/findings"
  local first; first=$(head -1 "$root/findings/x-bookmarks.md")
  # Everything after the em dash must be non-empty.
  case "$first" in
    *"— "?*) ok "the failure header carries an actual reason" ;;
    *) no "the failure header has an empty reason (got: $first)" ;;
  esac
  assert_grep "$root/findings/x-bookmarks.md" "auth_token" "and the reason names the fix"
  rm -rf "$root"
}

test_no_jq_still_writes_the_file(){
  echo "# regression: a missing jq reports itself instead of silently writing nothing"
  local root; root=$(setup)
  # PATH holding only what the script needs, minus jq. A bare exit here used to skip the
  # dispatch entirely, so no output file was written, run.sh's `|| log` never fired
  # (status 0), and PROMPT.md read the absent file as "feature not enabled".
  mkdir -p "$root/nojq"
  local b
  for b in date mktemp rm cat mkdir grep sed sort head tail wc stat sleep find basename cut tr awk; do
    [ -x "/usr/bin/$b" ] && ln -sf "/usr/bin/$b" "$root/nojq/$b"
    [ -x "/bin/$b" ]     && ln -sf "/bin/$b"     "$root/nojq/$b"
  done
  cp "$root/bin/curl" "$root/nojq/curl"
  env -i HOME="$HOME" PATH="$root/nojq" \
      AUTODREAM_DIR="$root" AUTODREAM_CONFIG="$root/no-such-config" \
      X_CREDS_FILE="$root/creds" X_STATE_DIR="$root/state" \
      /bin/bash "$BIN" collect "$root/findings" >/dev/null 2>&1
  assert_eq "$?" "0" "exits 0 with jq missing"
  assert_file "$root/findings/x-bookmarks.md" "the output file is still written"
  assert_grep "$root/findings/x-bookmarks.md" "^# x-bookmarks: fetch failed" "it reports a failure"
  assert_grep "$root/findings/x-bookmarks.md" "jq" "and names jq as the cause"
  rm -rf "$root"
}

# chmod 555 stops writes for everyone but root. Returns 1 (and the test skips) when the
# directory still takes a write, so the test cannot fail for the wrong reason.
deny_writes(){
  chmod 555 "$1"
  ( : > "$1/.probe" ) 2>/dev/null || return 0
  rm -f "$1/.probe"; chmod 755 "$1"; return 1
}

test_state_write_failure_is_not_no_unread(){
  echo "# regression: a seen.jsonl that cannot be written is reported, not read as an empty inbox (#108)"
  local root; root=$(setup)
  # No prior state and a state dir that cannot take the staged file: the fetch succeeds,
  # merge_state fails, and the report used to be told there were no unread bookmarks.
  deny_writes "$root/state" || { ok "skipped: this user can write to a read-only directory"; rm -rf "$root"; return; }
  run_bm "$root" collect "$root/findings"
  local rc=$?
  chmod 755 "$root/state"
  assert_eq "$rc" "0" "exits 0 so the nightly run continues"
  assert_nogrep "$root/findings/x-bookmarks.md" "no unread bookmarks" "the report does not claim an empty inbox"
  assert_grep "$root/findings/x-bookmarks.md" "^# x-bookmarks: fetch failed" "it uses the failure header L2 already handles"
  assert_grep "$root/findings/x-bookmarks.md" "seen.jsonl" "and names the state file it could not write"
  rm -rf "$root"
}

test_state_write_failure_after_failed_fetch(){
  echo "# regression: the fetch-failed branch also checks the state write (#108)"
  local root; root=$(setup)
  deny_writes "$root/state" || { ok "skipped: this user can write to a read-only directory"; rm -rf "$root"; return; }
  MOCK_CODE=500 run_bm "$root" collect "$root/findings"
  chmod 755 "$root/state"
  assert_grep "$root/findings/x-bookmarks.md" "seen.jsonl" "the state-write failure is named even when the fetch failed too"
  rm -rf "$root"
}

test_state_write_failure_keeps_earlier_unread(){
  echo "# regression: with unread bookmarks already on disk, a failed state write still shows them and names the failure (#108)"
  local fetch_code
  for fetch_code in 200 500; do
    local root; root=$(setup)
    printf '{"id":"50","author":"earlier","url":"https://x.com/earlier/status/50","text":"earlier post","links":[],"read_on":null}\n' > "$root/state/seen.jsonl"
    deny_writes "$root/state" || { ok "skipped: this user can write to a read-only directory"; rm -rf "$root"; return; }
    MOCK_CODE=$fetch_code run_bm "$root" collect "$root/findings"
    chmod 755 "$root/state"
    assert_grep "$root/findings/x-bookmarks.md" "earlier post" "fetch $fetch_code: the unread bookmark already on disk is still shown"
    assert_grep "$root/findings/x-bookmarks.md" "could not update .*seen.jsonl" "fetch $fetch_code: the banner names the state-write failure"
    rm -rf "$root"
  done
}

# A curl shim that serves the bookmarks page, logs every URL it is asked for, and returns
# a Bookmarks chunk only for MOCK_CHUNK_URL. Every other URL is a miss (a 404 body).
make_walk_shim(){ # $1=bindir
  mkdir -p "$1"
  cat > "$1/curl" <<'SH'
#!/bin/bash
out=""; prev=""; url=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  case "$a" in https://*) url="$a" ;; esac
  prev="$a"
done
printf '%s\n' "$url" >> "$MOCK_LOG"
case "$url" in
  https://x.com/i/bookmarks) cat "$MOCK_HTML" > "$out"; printf '200' ;;
  "$MOCK_CHUNK_URL") printf 'a:1,queryId:"WALKEDQID",operationName:"Bookmarks",b:2' > "$out"; printf '200' ;;
  *) printf 'not found' > "$out"; printf '404' ;;
esac
exit 0
SH
  chmod +x "$1/curl"
}

test_walk_reaches_every_suffix_variant(){
  echo "# regression: a page full of main.*.js URLs does not starve the suffix variants (#107)"
  local root; root=$(setup)
  rm -f "$root/state/query-id"
  make_walk_shim "$root/bin"
  local hash=0123456789abcdef i
  {
    for i in $(seq 1 30); do printf '"https://abs.twimg.com/responsive-web/client-web/main.page%s.js"\n' "$i"; done
    printf '{7:"bundle.Bookmarks"}{7:"%s"}\n' "$hash"
  } > "$root/page.html"
  # The last variant the walk enumerates: with the old global cap of 24 requests it sat
  # behind 30 page URLs and was never requested.
  MOCK_HTML="$root/page.html" MOCK_LOG="$root/requests.log" \
  MOCK_CHUNK_URL="https://abs.twimg.com/responsive-web/client-web/bundle.Bookmarks.${hash}9.js" \
    run_bm "$root" collect "$root/findings"
  assert_eq "$(cat "$root/state/query-id" 2>/dev/null)" "WALKEDQID" "the queryId behind the last suffix variant is found"
  assert_eq "$(cat "$root/findings/x-bookmarks-queryid.txt")" "fresh" "and recorded as a fresh scrape"
  rm -rf "$root"
}

# ---- The browser path (#166) ---------------------------------------------------------
#
# `agent-browser` is shimmed the way curl is. The shim logs every call (AB_LOG), strips the
# global --session/--profile/--headed flags, serves MOCK_HAR on `network har stop <path>`,
# and answers `get url` with AB_URL. AB_FAIL=<open|har-start|har-stop|get-url|wait|scroll>
# makes that one command exit 1, and AB_HANG=<same> makes it block (exec, so the watchdog's
# kill reaches the sleep). Nothing here touches x.com: the real browser path cannot be
# exercised without a logged-in profile, which is what the PR's verify command is for.

make_ab_shim(){ # $1=bindir
  mkdir -p "$1"
  cat > "$1/agent-browser" <<'SH'
#!/bin/bash
printf 'session=%s profile=%s :: %s\n' "${AGENT_BROWSER_SESSION:-}" "${AGENT_BROWSER_PROFILE:-}" "$*" >> "${AB_LOG:-/dev/null}"
while [ $# -gt 0 ]; do
  case "$1" in
    --session|--profile) shift 2 ;;
    --headed|--json) shift ;;
    *) break ;;
  esac
done
name="$1"
case "$1 ${2:-}" in
  "network har") name="har-$3" ;;
  "get url") name="get-url" ;;
esac
[ "${AB_HANG:-}" = "$name" ] && exec /bin/sleep 30
if [ "${AB_FAIL:-}" = "$name" ]; then echo "agent-browser: simulated $name failure" >&2; exit 1; fi
case "$name" in
  har-stop) cp "${MOCK_HAR:-/dev/null}" "$4" ;;
  get-url) printf '%s\n' "${AB_URL:-https://x.com/i/bookmarks}" ;;
esac
exit 0
SH
  chmod +x "$1/agent-browser"
}

# curl that records the call and fails: proves the browser path never reached for it.
make_curl_trap(){ # $1=bindir
  cat > "$1/curl" <<'SH'
#!/bin/bash
printf 'called\n' >> "${CURL_LOG:-/dev/null}"
exit 7
SH
  chmod +x "$1/curl"
}

# make_har <out> <status:bodyfile>...  — a HAR with one Bookmarks entry per pair, in order,
# between a BookmarkFolders call and an unrelated asset that must both be ignored.
make_har(){
  local out="$1"; shift
  local entries='[{"request":{"method":"GET","url":"https://x.com/i/api/graphql/ZZZ/BookmarkFolders?variables=%7B%7D"},"response":{"status":200,"content":{"text":"{\"folders\":true}"}}},{"request":{"method":"GET","url":"https://abs.twimg.com/main.js"},"response":{"status":200,"content":{"text":"x"}}}]'
  local pair status file
  for pair in "$@"; do
    status="${pair%%:*}"; file="${pair#*:}"
    entries=$(jq -c --argjson s "$status" --rawfile b "$file" \
      '. + [{request:{method:"GET",url:"https://x.com/i/api/graphql/RANDOMQID/Bookmarks?variables=%7B%22count%22%3A20%7D"},response:{status:$s,content:{mimeType:"application/json",text:$b}}}]' <<<"$entries")
  done
  jq -n --argjson e "$entries" '{log:{version:"1.2",entries:$e}}' > "$out"
}

# A sandbox for the browser path: shims, a profile dir, a trapped curl, no queryId cache and
# a HAR holding the fixture page. Credentials exist unless the test removes them.
bsetup(){
  local root; root=$(setup)
  make_ab_shim "$root/bin"
  make_curl_trap "$root/bin"
  mkdir -p "$root/profile"
  make_har "$root/har.json" "200:$root/page.json"
  printf '%s' "$root"
}
run_br(){ # $1=root, rest = args
  local root="$1"; shift
  AUTODREAM_X_FETCH=browser X_BROWSER_PROFILE="${X_BROWSER_PROFILE:-$root/profile}" \
  X_BROWSER_TIMEOUT="${X_BROWSER_TIMEOUT:-20}" AB_LOG="$root/ab.log" CURL_LOG="$root/curl.log" \
  MOCK_HAR="${MOCK_HAR:-$root/har.json}" MOCK_BODY="${MOCK_BODY:-$root/page.json}" \
    run_bm "$root" "$@"
}
fetch_path(){ head -1 "$1/x-bookmarks-fetch.txt" 2>/dev/null; }

test_default_mode_never_touches_the_browser(){
  echo "# AUTODREAM_X_FETCH unset -> the GraphQL path, and agent-browser is never called"
  local root; root=$(bsetup)
  make_curl_shim "$root/bin"
  AB_LOG="$root/ab.log" run_bm "$root" collect "$root/findings"
  assert_eq "$(fetch_path "$root/findings")" "graphql" "x-bookmarks-fetch.txt names the graphql path"
  [ ! -s "$root/ab.log" ] && ok "agent-browser was not invoked" || no "agent-browser was invoked in the default mode"
  assert_grep "$root/findings/x-bookmarks.md" "the newer post" "the bookmarks came from the GraphQL fetch"
  assert_eq "$(sed -n 2p "$root/findings/x-bookmarks-fetch.txt")" "" "no browser cause is recorded"
  rm -rf "$root"
}

test_unknown_mode_is_graphql_with_a_warning(){
  echo "# an unknown AUTODREAM_X_FETCH value is read as graphql, loudly"
  local root; root=$(bsetup)
  make_curl_shim "$root/bin"
  AUTODREAM_X_FETCH=headless AB_LOG="$root/ab.log" run_bm "$root" collect "$root/findings"
  assert_eq "$(fetch_path "$root/findings")" "graphql" "an unknown mode runs the default path"
  assert_grep "$root/out.txt" "AUTODREAM_X_FETCH" "the output names the variable it did not understand"
  [ ! -s "$root/ab.log" ] && ok "and the browser stays untouched" || no "the browser ran for an unknown mode"
  rm -rf "$root"
}

test_browser_mode_reads_the_response_from_the_har(){
  echo "# browser mode: the Bookmarks response in the HAR becomes the bookmarks, with no curl and no credentials"
  local root; root=$(bsetup)
  X_CREDS_FILE="$root/does-not-exist" run_br "$root" collect "$root/findings"
  assert_eq "$?" "0" "exits 0"
  assert_eq "$(fetch_path "$root/findings")" "browser" "the path is recorded as browser"
  assert_grep "$root/findings/x-bookmarks.md" "@newerauthor" "the author is parsed from the browser's response"
  assert_grep "$root/findings/x-bookmarks.md" "the older post" "every bookmark in the response is present"
  assert_eq "$(wc -l < "$root/findings/x-bookmarks-manifest.txt" | tr -d ' ')" "2" "both are in the manifest"
  assert_eq "$(wc -l < "$root/state/seen.jsonl" | tr -d ' ')" "2" "and recorded in state"
  [ ! -s "$root/curl.log" ] && ok "curl was never called" || no "the browser path called curl"
  assert_eq "$(cat "$root/findings/x-bookmarks-queryid.txt")" "not_attempted" "the queryId walk is recorded as not run"
  assert_grep "$root/ab.log" "har start" "the HAR recording starts before the page opens"
  assert_grep "$root/ab.log" "x.com/i/bookmarks" "the bookmarks page is opened"
  assert_eq "$(grep -vc "^session=autodream-x profile=$root/profile :: " "$root/ab.log")" "0" "every call runs in the dedicated session and profile"
  rm -rf "$root"
}

test_browser_mode_orders_the_har_before_the_page(){
  echo "# the HAR must start recording before open, or the first Bookmarks call is missed"
  local root; root=$(bsetup)
  run_br "$root" collect "$root/findings"
  local start open
  start=$(grep -n "har start" "$root/ab.log" | head -1 | cut -d: -f1)
  open=$(grep -n " open " "$root/ab.log" | head -1 | cut -d: -f1)
  { [ -n "$start" ] && [ -n "$open" ] && [ "$start" -lt "$open" ]; } && ok "har start precedes open" || no "har start ($start) does not precede open ($open)"
  rm -rf "$root"
}

test_browser_mode_scrolls_for_more_pages(){
  echo "# X_MAX_PAGES > 1: the browser scrolls, and every Bookmarks response in the HAR is read"
  local root; root=$(bsetup)
  # Page two holds one more bookmark, id 50.
  jq -c '.data.bookmark_timeline_v2.timeline.instructions[0].entries =
          [{"entryId":"tweet-50","content":{"itemContent":{"tweet_results":{"result":{"rest_id":"50","core":{"user_results":{"result":{"core":{"screen_name":"pagetwo"}}}},"legacy":{"full_text":"page two post","entities":{"urls":[]}}}}}}}]' \
    "$root/page.json" > "$root/page2.json"
  make_har "$root/har.json" "200:$root/page.json" "200:$root/page2.json"
  X_MAX_PAGES=2 run_br "$root" collect "$root/findings"
  assert_grep "$root/findings/x-bookmarks.md" "page two post" "the second response is read"
  assert_eq "$(grep -c ' scroll ' "$root/ab.log")" "1" "one scroll for the second page"
  rm -rf "$root"
  root=$(bsetup)
  X_MAX_PAGES=1 run_br "$root" collect "$root/findings"
  assert_eq "$(grep -c ' scroll ' "$root/ab.log")" "0" "a one-page run never scrolls"
  rm -rf "$root"
}

test_browser_mode_stops_at_a_known_bookmark(){
  echo "# a response page is not read past the first already-seen bookmark, as on the GraphQL path"
  local root; root=$(bsetup)
  jq -c '.data.bookmark_timeline_v2.timeline.instructions[0].entries =
          [{"entryId":"tweet-50","content":{"itemContent":{"tweet_results":{"result":{"rest_id":"50","core":{"user_results":{"result":{"core":{"screen_name":"pagetwo"}}}},"legacy":{"full_text":"page two post","entities":{"urls":[]}}}}}}}]' \
    "$root/page.json" > "$root/page2.json"
  make_har "$root/har.json" "200:$root/page.json" "200:$root/page2.json"
  printf '{"id":"200","author":"newerauthor","url":"https://x.com/newerauthor/status/200","text":"the newer post","links":[],"read_on":"2026-08-01"}\n' > "$root/state/seen.jsonl"
  X_MAX_PAGES=2 run_br "$root" collect "$root/findings"
  assert_nogrep "$root/findings/x-bookmarks.md" "page two post" "nothing past the known bookmark is read"
  rm -rf "$root"
}

test_browser_mode_decodes_a_base64_body(){
  echo "# a HAR body stored as base64 is decoded before parsing"
  local root; root=$(bsetup)
  jq -n --rawfile b "$root/page.json" \
    '{log:{entries:[{request:{method:"GET",url:"https://x.com/i/api/graphql/Q/Bookmarks?v=1"},response:{status:200,content:{encoding:"base64",text:($b|@base64)}}}]}}' > "$root/har.json"
  run_br "$root" collect "$root/findings"
  assert_eq "$(fetch_path "$root/findings")" "browser" "a base64 response still counts as the browser path"
  assert_grep "$root/findings/x-bookmarks.md" "the newer post" "and parses"
  rm -rf "$root"
}

# One fallback case: break the browser path in the named way, collect, and check the GraphQL
# fallback served the bookmarks with the browser cause recorded.
fallback_case(){ # $1=case name
  local name="$1" root cause_re timeout=20
  root=$(bsetup)
  make_curl_shim "$root/bin"
  local bin_override="" url="" ab_fail="" hang=""
  case "$name" in
    missing_bin)          bin_override="$root/no-such-agent-browser"; cause_re="not found" ;;
    open)                 ab_fail=open; cause_re="open" ;;
    har_stop)             ab_fail=har-stop; cause_re="HAR" ;;
    no_bookmarks_request) printf '{"log":{"entries":[]}}' > "$root/har.json"; cause_re="no Bookmarks request" ;;
    har_unparseable)      printf 'not json' > "$root/har.json"; cause_re="HAR" ;;
    login_redirect)       url="https://x.com/i/flow/login"; cause_re="logged out" ;;
    http_401)             make_har "$root/har.json" "401:$root/page.json"; cause_re="401" ;;
    hung)                 hang=open; timeout=2; cause_re="timed out" ;;
    no_profile)           rm -rf "$root/profile"; cause_re="no browser profile" ;;
  esac
  local t0=$SECONDS
  X_BROWSER_BIN="$bin_override" AB_URL="$url" AB_FAIL="$ab_fail" AB_HANG="$hang" X_BROWSER_TIMEOUT="$timeout" \
    run_br "$root" collect "$root/findings"
  local elapsed=$((SECONDS - t0))
  assert_eq "$(fetch_path "$root/findings")" "fallback_graphql" "$name: the GraphQL fallback served the bookmarks"
  assert_grep "$root/findings/x-bookmarks-fetch.txt" "$cause_re" "$name: the browser cause is recorded"
  assert_grep "$root/findings/x-bookmarks.md" "the newer post" "$name: the report still has the bookmarks"
  if [ "$name" = hung ]; then
    [ "$elapsed" -lt 15 ] && ok "hung: the watchdog cut a blocked browser call short" || no "hung: took ${elapsed}s"
  fi
  rm -rf "$root"
}

test_browser_failure_falls_back_to_graphql(){
  echo "# every browser failure falls back to the GraphQL path when credentials exist, and the cause is kept"
  local c
  for c in missing_bin open har_stop no_bookmarks_request har_unparseable login_redirect http_401 hung no_profile; do
    fallback_case "$c"
  done
}

test_browser_failure_without_credentials_reports_the_browser_cause(){
  echo "# browser fails and there is no GraphQL fallback -> a fetch-failed header naming the browser, exit 0"
  local root; root=$(bsetup)
  AB_FAIL=open X_CREDS_FILE="$root/does-not-exist" run_br "$root" collect "$root/findings"
  assert_eq "$?" "0" "exits 0"
  assert_grep "$root/findings/x-bookmarks.md" "^# x-bookmarks: fetch failed" "the failure header is written"
  assert_grep "$root/findings/x-bookmarks.md" "browser" "and it names the browser path"
  assert_eq "$(fetch_path "$root/findings")" "failed" "the path is failed"
  assert_file "$root/findings/x-bookmarks-manifest.txt" "the manifest exists"
  rm -rf "$root"
}

test_both_paths_failing_names_both(){
  echo "# browser failure then GraphQL failure -> one header carrying both reasons, earlier unread bookmarks still served"
  local root; root=$(bsetup)
  make_curl_shim "$root/bin"
  printf '{"id":"50","author":"earlier","url":"https://x.com/earlier/status/50","text":"earlier post","links":[],"read_on":null}\n' > "$root/state/seen.jsonl"
  AB_FAIL=open MOCK_CODE=401 run_br "$root" collect "$root/findings"
  assert_eq "$?" "0" "exits 0"
  assert_eq "$(fetch_path "$root/findings")" "failed" "the path is failed"
  assert_grep "$root/findings/x-bookmarks.md" "earlier post" "unread bookmarks captured earlier are still offered"
  assert_grep "$root/findings/x-bookmarks.md" "browser" "the banner names the browser failure"
  assert_grep "$root/findings/x-bookmarks.md" "credentials" "and the GraphQL one"
  rm -rf "$root"
}

test_browser_mode_is_not_configured_without_profile_or_credentials(){
  echo "# browser mode with neither a profile nor credentials is 'not configured', not a failure"
  local root; root=$(bsetup)
  rm -rf "$root/profile"
  X_CREDS_FILE="$root/does-not-exist" run_br "$root" collect "$root/findings"
  assert_eq "$?" "0" "exits 0"
  assert_grep "$root/findings/x-bookmarks.md" "not configured" "the stub says not configured"
  assert_nogrep "$root/findings/x-bookmarks.md" "fetch failed" "and not failed"
  assert_eq "$(fetch_path "$root/findings")" "not_attempted" "the path is not_attempted"
  [ ! -s "$root/ab.log" ] && ok "no browser was launched against a profile that does not exist" || no "the browser launched without a profile"
  rm -rf "$root"
}

test_browser_is_closed_on_every_outcome(){
  echo "# the dedicated browser session is closed after success and after failure"
  local root; root=$(bsetup)
  run_br "$root" collect "$root/findings"
  assert_eq "$(grep -c ' close$' "$root/ab.log")" "1" "closed exactly once after a good run (the EXIT trap does not close it again)"
  rm -rf "$root"
  root=$(bsetup)
  AB_FAIL=har-stop X_CREDS_FILE="$root/does-not-exist" run_br "$root" collect "$root/findings"
  assert_eq "$(grep -c ' close$' "$root/ab.log")" "1" "closed exactly once after a failed run"
  rm -rf "$root"
  root=$(bsetup)
  AB_FAIL=open run_br "$root" collect "$root/findings"
  assert_eq "$(grep -c ' close$' "$root/ab.log")" "1" "closed exactly once when open failed before the page loaded"
  rm -rf "$root"
  root=$(bsetup)
  AB_FAIL=close run_br "$root" collect "$root/findings"
  assert_eq "$(grep -c ' close$' "$root/ab.log")" "1" "a close that itself fails is not retried by the EXIT trap"
  assert_eq "$(fetch_path "$root/findings")" "browser" "and a failed close does not change the path that served the night"
  rm -rf "$root"
}

test_no_credential_reaches_the_browser_argv(){
  echo "# credentials never go in argv: the browser path does not carry the cookie values anywhere"
  local root; root=$(bsetup)
  printf 'X_AUTH_TOKEN=SECRETAUTHTOKEN\nX_CT0=SECRETCT0VALUE\n' > "$root/creds"; chmod 600 "$root/creds"
  make_curl_shim "$root/bin"
  AB_FAIL=open run_br "$root" collect "$root/findings"
  assert_nogrep "$root/ab.log" "SECRET" "no cookie value in any agent-browser call, fallback included"
  assert_nogrep "$root/findings/x-bookmarks-fetch.txt" "SECRET" "none in the recorded cause"
  rm -rf "$root"
}

test_browser_login_opens_a_headed_profile(){
  echo "# browser-login opens the dedicated profile headed, on the login page, and touches no credentials"
  local root; root=$(bsetup)
  rm -rf "$root/profile"
  AB_LOG="$root/ab.log" X_BROWSER_PROFILE="$root/profile" run_bm "$root" browser-login
  assert_eq "$?" "0" "exits 0"
  assert_grep "$root/ab.log" "[-][-]headed" "the window is shown"
  assert_grep "$root/ab.log" "[-][-]profile $root/profile" "the dedicated profile is used"
  assert_grep "$root/ab.log" "x.com" "it opens x.com"
  assert_grep "$root/out.txt" "close" "the output says how to finish"
  rm -rf "$root"
}

test_status_names_the_fetch_mode(){
  echo "# status says which fetch mode and browser profile are configured"
  local root; root=$(bsetup)
  run_br "$root" status
  assert_grep "$root/out.txt" "fetch mode" "the mode is printed"
  assert_grep "$root/out.txt" "browser" "browser mode is named"
  assert_grep "$root/out.txt" "$root/profile" "the profile path is shown"
  rm -rf "$root"
}

echo "x-bookmarks.sh tests"
test_pages_are_paced_and_the_last_one_is_not_waited_on
test_not_configured
test_auth_failure
test_stale_queryid_clears_cache
test_queryid_source_is_recorded
test_parse_and_emit
test_newest_first
test_mark_read_then_not_relisted
test_mark_read_idempotent
test_mark_read_no_manifest
test_unread_survive_a_failed_fetch
test_state_not_duplicated
test_text_is_capped
test_duplicate_ids_within_one_fetch
test_auth_failure_reason_is_not_empty
test_no_jq_still_writes_the_file
test_state_write_failure_is_not_no_unread
test_state_write_failure_after_failed_fetch
test_state_write_failure_keeps_earlier_unread
test_walk_reaches_every_suffix_variant
test_default_mode_never_touches_the_browser
test_unknown_mode_is_graphql_with_a_warning
test_browser_mode_reads_the_response_from_the_har
test_browser_mode_orders_the_har_before_the_page
test_browser_mode_scrolls_for_more_pages
test_browser_mode_stops_at_a_known_bookmark
test_browser_mode_decodes_a_base64_body
test_browser_failure_falls_back_to_graphql
test_browser_failure_without_credentials_reports_the_browser_cause
test_both_paths_failing_names_both
test_browser_mode_is_not_configured_without_profile_or_credentials
test_browser_is_closed_on_every_outcome
test_no_credential_reaches_the_browser_argv
test_browser_login_opens_a_headed_profile
test_status_names_the_fetch_mode

echo
echo "----------------------------------------"
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
