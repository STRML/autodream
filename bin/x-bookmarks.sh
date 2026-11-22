#!/usr/bin/env bash
usage() {
  cat <<'EOF'
x-bookmarks.sh: pull recent X bookmarks so the aggregator can turn them into ideas.

Usage:
  x-bookmarks.sh collect <findings-dir>    write x-bookmarks.md + manifest
  x-bookmarks.sh mark-read <findings-dir>  stamp the manifest's ids as read
  x-bookmarks.sh status                    check the setup by hand
  x-bookmarks.sh browser-login             log in to the browser profile, once, by hand

Config (env; run.sh sources ~/.claude/autodream/config with `set -a` first):
  AUTODREAM_DIR       default $HOME/.claude/autodream
  X_CREDS_FILE        default $AUTODREAM_DIR/x-credentials, sourced as bash, keys:
                        X_AUTH_TOKEN=...   (the auth_token cookie)
                        X_CT0=...          (the ct0 cookie)
  X_STATE_DIR         default $AUTODREAM_DIR/x-bookmarks
  X_MAX_PAGES         pagination cap, ~20 bookmarks per page         default 3
  X_MAX_UNREAD        most unread bookmarks to show one report       default 40
  X_MAX_TEXT          per-post character cap in the report input     default 800
  X_QUERYID_TTL       seconds to reuse a scraped queryId             default 86400
  AUTODREAM_X_FETCH   graphql or browser                             default graphql
  X_BROWSER_PROFILE   agent-browser profile directory                default $AUTODREAM_DIR/x-browser-profile
  X_BROWSER_BIN       agent-browser binary                           default agent-browser (on PATH)
  X_BROWSER_SESSION   agent-browser session name                     default autodream-x
  X_BROWSER_TIMEOUT   seconds each browser command may run           default 60
  X_BROWSER_LOCK_WAIT seconds to wait for another run's browser      default 120
EOF
}

set -uo pipefail

_pp="$(dirname "${BASH_SOURCE[0]}")/portable.sh"
[ -r "$_pp" ] || _pp="$(dirname "$(readlink "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/portable.sh"
# shellcheck source=/dev/null
. "$_pp"

AUTODREAM_DIR="${AUTODREAM_DIR:-$HOME/.claude/autodream}"

AUTODREAM_CONFIG="${AUTODREAM_CONFIG:-$AUTODREAM_DIR/config}"
if [ -f "$AUTODREAM_CONFIG" ]; then
  _env_snapshot=$(export -p)
  set +u
  set -a
  # shellcheck disable=SC1090
  . "$AUTODREAM_CONFIG" 2>/dev/null || true
  set +a
  set -u
  eval "$_env_snapshot"
  unset _env_snapshot
fi

CREDS_FILE="${X_CREDS_FILE:-$AUTODREAM_DIR/x-credentials}"
STATE_DIR="${X_STATE_DIR:-$AUTODREAM_DIR/x-bookmarks}"
MAX_PAGES="${X_MAX_PAGES:-3}"
case "$MAX_PAGES" in
  ''|*[!0-9]*) MAX_PAGES=0 ;;
  *) MAX_PAGES=$((10#$MAX_PAGES)) ;;
esac
if [ "$MAX_PAGES" -lt 1 ]; then
  echo "x-bookmarks: X_MAX_PAGES=${X_MAX_PAGES:-} is not a positive number; using 3" >&2
  MAX_PAGES=3
fi
MAX_UNREAD="${X_MAX_UNREAD:-40}"
MAX_TEXT="${X_MAX_TEXT:-800}"
QUERYID_TTL="${X_QUERYID_TTL:-86400}"

X_FETCH_MODE="${AUTODREAM_X_FETCH:-graphql}"
case "$X_FETCH_MODE" in
  graphql|browser) : ;;
  *) echo "x-bookmarks: AUTODREAM_X_FETCH=$X_FETCH_MODE is not graphql or browser; using graphql" >&2
     X_FETCH_MODE=graphql ;;
esac
BROWSER_PROFILE="${X_BROWSER_PROFILE:-$AUTODREAM_DIR/x-browser-profile}"
BROWSER_BIN="${X_BROWSER_BIN:-agent-browser}"
BROWSER_SESSION="${X_BROWSER_SESSION:-autodream-x}"
BROWSER_TIMEOUT="${X_BROWSER_TIMEOUT:-60}"
case "$BROWSER_TIMEOUT" in ''|*[!0-9]*|0) BROWSER_TIMEOUT=60 ;; esac
BROWSER_LOCK_WAIT="${X_BROWSER_LOCK_WAIT:-120}"
case "$BROWSER_LOCK_WAIT" in ''|*[!0-9]*) BROWSER_LOCK_WAIT=120 ;; esac
BROWSER_LOCK="$AUTODREAM_DIR/locks/x-browser.lock"

SEEN="$STATE_DIR/seen.jsonl"
QID_CACHE="$STATE_DIR/query-id"
TODAY="$(date +%F)"

BEARER="${X_BEARER:-AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA}"
UA="${X_USER_AGENT:-Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36}"
GRAPHQL_BASE="https://x.com/i/api/graphql"

FEATURES='{"graphql_timeline_v2_bookmark_timeline":true,"rweb_tipjar_consumption_enabled":true,"responsive_web_graphql_exclude_directive_enabled":true,"verified_phone_label_enabled":false,"creator_subscriptions_tweet_preview_api_enabled":true,"responsive_web_graphql_timeline_navigation_enabled":true,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":false,"communities_web_enable_tweet_community_results_fetch":true,"c9s_tweet_anatomy_moderator_badge_enabled":true,"articles_preview_enabled":true,"responsive_web_edit_tweet_api_enabled":true,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":true,"view_counts_everywhere_api_enabled":true,"longform_notetweets_consumption_enabled":true,"responsive_web_twitter_article_tweet_consumption_enabled":true,"tweet_awards_web_tipping_enabled":false,"creator_subscriptions_quote_tweet_preview_enabled":false,"freedom_of_speech_not_reach_fetch_enabled":true,"standardized_nudges_misinfo":true,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":true,"rweb_video_timestamps_enabled":true,"longform_notetweets_rich_text_read_enabled":true,"longform_notetweets_inline_media_enabled":true,"responsive_web_enhance_cards_enabled":false}'
FIELD_TOGGLES='{"withArticlePlainText":false,"withArticleRichContentState":false,"withGrokAnalyze":false,"withDisallowedReplyControls":false}'

TMP="$(mktemp -d "${TMPDIR:-/tmp}/xbm.XXXXXX")"
BROWSER_OPEN=0
BROWSER_LOCK_HELD=0
cleanup() {
  local j
  for j in $(jobs -p); do kill "$j" 2>/dev/null; done
  [ "$BROWSER_OPEN" = 1 ] && browser_close
  browser_unlock
  rm -rf "$TMP"
}
trap cleanup EXIT

FAIL_FILE="$TMP/fail-reason"
: > "$FAIL_FILE"
REAUTH_HINT="Open x.com logged in, DevTools > Application > Cookies > https://x.com, copy auth_token and ct0, and rewrite $CREDS_FILE."

fail() { printf '%s' "$1" > "$FAIL_FILE"; return 1; }
fail_reason() { cat "$FAIL_FILE" 2>/dev/null; }

QID_SOURCE_FILE="$TMP/queryid-source"
printf 'not_attempted' > "$QID_SOURCE_FILE"
qid_source() { cat "$QID_SOURCE_FILE" 2>/dev/null; }

load_creds() {
  [ -f "$CREDS_FILE" ] || return 2
  set +u
  # shellcheck disable=SC1090
  . "$CREDS_FILE" 2>/dev/null || { set -u; fail "credentials file at $CREDS_FILE could not be parsed as shell"; return 1; }
  set -u
  [ -n "${X_AUTH_TOKEN:-}" ] && [ -n "${X_CT0:-}" ] || { fail "credentials file is missing X_AUTH_TOKEN or X_CT0. $REAUTH_HINT"; return 1; }
  return 0
}

warn_perms() {
  local mode; mode=$(pstat_mode "$CREDS_FILE") || return 0
  case "$mode" in
    600|400) : ;;
    *) echo "  WARNING: $CREDS_FILE is mode $mode; these cookies are a full account session. chmod 600 it." >&2 ;;
  esac
}

curl_x() { curl -sS --max-time 30 -A "$UA" "$@"; }

COOKIE_CFG="$TMP/curl-cookie.cfg"
API_CFG="$TMP/curl-api.cfg"

cfg_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

write_curl_configs() {
  local tok csrf bearer
  tok="$(cfg_escape "$X_AUTH_TOKEN")"
  csrf="$(cfg_escape "$X_CT0")"
  bearer="$(cfg_escape "$BEARER")"
  ( umask 077
    printf 'header = "cookie: auth_token=%s; ct0=%s"\n' "$tok" "$csrf" > "$COOKIE_CFG"
    {
      printf 'header = "cookie: auth_token=%s; ct0=%s"\n' "$tok" "$csrf"
      printf 'header = "x-csrf-token: %s"\n' "$csrf"
      printf 'header = "authorization: Bearer %s"\n' "$bearer"
      printf 'header = "x-twitter-active-user: yes"\n'
      printf 'header = "x-twitter-auth-type: OAuth2Session"\n'
      printf 'header = "x-twitter-client-language: en"\n'
      printf 'header = "content-type: application/json"\n'
      printf 'header = "referer: https://x.com/i/bookmarks"\n'
    } > "$API_CFG"
  )
}

extract_qid() { grep -oE 'queryId:"[^"]+",operationName:"Bookmarks"' "$1" 2>/dev/null | head -1 | sed 's/queryId:"//; s/",operationName.*//'; }

detect_query_id() {
  local html="$TMP/bookmarks.html"
  curl_x --config "$COOKIE_CFG" \
         -o "$html" -w '%{http_code}' "https://x.com/i/bookmarks" > "$TMP/code" 2>/dev/null
  local code; code=$(cat "$TMP/code" 2>/dev/null)
  [ -s "$html" ] || { fail "could not load x.com/i/bookmarks (HTTP ${code:-none})"; return 1; }
  if grep -q -e 'LoginForm' -e '/i/flow/login' "$html" 2>/dev/null; then
    fail "X returned its login page — the auth_token/ct0 cookies are expired or invalid. $REAUTH_HINT"
    return 1
  fi

  local PAGE_URL_CAP=8
  local cands="$TMP/cands"; : > "$cands"
  grep -oE 'https://abs\.twimg\.com/responsive-web/client-web/[A-Za-z0-9._~-]+\.js' "$html" 2>/dev/null \
    | grep -E 'main\.|bundle\.Bookmarks' | awk '!seen[$0]++' | head -n "$PAGE_URL_CAP" >> "$cands"

  local chunk_id name hash
  chunk_id=$(grep -oE '[0-9]+:"(shared~bundle\.BookmarkFolders~bundle\.Bookmarks|bundle\.Bookmarks)"' "$html" 2>/dev/null | head -1 | cut -d: -f1)
  if [ -n "$chunk_id" ]; then
    name=$(grep -oE "${chunk_id}:\"[^\"]+\"" "$html" 2>/dev/null | head -1 | sed 's/^[0-9]*:"//; s/"$//')
    hash=$(grep -oE "${chunk_id}:\"[a-f0-9]{7,64}\"" "$html" 2>/dev/null | tail -1 | sed 's/^[0-9]*:"//; s/"$//')
    if [ -n "$name" ] && [ -n "$hash" ]; then
      local sfx
      for sfx in "${hash}a" "$hash" "${hash}b" "${hash}c" "${hash}d" "${hash}e" "${hash}f" \
                 "${hash}0" "${hash}1" "${hash}2" "${hash}3" "${hash}4" \
                 "${hash}5" "${hash}6" "${hash}7" "${hash}8" "${hash}9"; do
        printf 'https://abs.twimg.com/responsive-web/client-web/%s.%s.js\n' "$name" "$sfx" >> "$cands"
      done
    fi
  fi

  local url qid
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    curl_x -H 'referer: https://x.com/' -o "$TMP/chunk.js" "$url" >/dev/null 2>&1 || continue
    qid=$(extract_qid "$TMP/chunk.js")
    if [ -n "$qid" ]; then printf '%s' "$qid"; return 0; fi
  done < <(awk '!seen[$0]++' "$cands")

  fail "could not find the Bookmarks queryId in any X JS bundle (X changed its bundle layout; see the grounding note in this script)"
  return 1
}

get_query_id() {
  if [ -s "$QID_CACHE" ]; then
    local age; age=$(( $(date +%s) - $(pstat_mtime "$QID_CACHE" || echo 0) ))
    if [ "$age" -lt "$QUERYID_TTL" ]; then
      printf 'cache' > "$QID_SOURCE_FILE"
      cat "$QID_CACHE"; return 0
    fi
  fi
  local qid
  if ! qid=$(detect_query_id); then printf 'failed' > "$QID_SOURCE_FILE"; return 1; fi
  printf 'fresh' > "$QID_SOURCE_FILE"
  mkdir -p "$STATE_DIR" && printf '%s' "$qid" > "$QID_CACHE"
  printf '%s' "$qid"
}

fetch_page() {
  local qid="$1" cursor="${2:-}" vars
  if [ -n "$cursor" ]; then
    vars=$(jq -nc --arg c "$cursor" '{count:20,includePromotedContent:false,cursor:$c}')
  else
    vars='{"count":20,"includePromotedContent":false}'
  fi
  local code
  code=$(curl_x --get "$GRAPHQL_BASE/$qid/Bookmarks" \
    --data-urlencode "variables=$vars" \
    --data-urlencode "features=$FEATURES" \
    --data-urlencode "fieldToggles=$FIELD_TOGGLES" \
    --config "$API_CFG" \
    -o "$TMP/page.json" -w '%{http_code}' 2>/dev/null)

  case "$code" in
    200) : ;;
    401|403) fail "X rejected the credentials (HTTP $code) — the cookies are expired. $REAUTH_HINT"; return 1 ;;
    429)     fail "X rate-limited the request (HTTP 429); it will be retried tomorrow"; return 1 ;;
    400)     rm -f "$QID_CACHE"
             fail "X returned HTTP 400: $(head -c 300 "$TMP/page.json" 2>/dev/null | tr '\n' ' ')"; return 1 ;;
    *)       fail "X returned HTTP ${code:-none}"; return 1 ;;
  esac
  jq -e . "$TMP/page.json" >/dev/null 2>&1 || { fail "X returned a response that is not JSON"; return 1; }
  return 0
}

parse_page() {
  jq -c --arg today "$TODAY" '
    [ (.data.bookmark_timeline_v2.timeline.instructions // [])[] | (.entries // [])[] ]
    | map(select(.content.itemContent.tweet_results.result != null))
    | map(.content.itemContent.tweet_results.result)
    | map(if .tweet then .tweet else . end)
    | map(select(.legacy != null))
    | map({
        id: (.rest_id // ""),
        author: ((.core.user_results.result.core.screen_name
                  // .core.user_results.result.legacy.screen_name) // "unknown"),
        text: (.legacy.full_text // ""),
        links: [ (.legacy.entities.urls // [])[] | .expanded_url ],
        created_at: (.legacy.created_at // ""),
        first_seen: $today,
        read_on: null
      })
    | map(select(.id != ""))
    | map(. + {url: ("https://x.com/" + .author + "/status/" + .id)})
    | .[]
  ' "$TMP/page.json" 2>/dev/null
}

next_cursor() {
  jq -r '
    [ (.data.bookmark_timeline_v2.timeline.instructions // [])[] | (.entries // [])[]
      | select((.content.cursorType == "Bottom") or (((.entryId // "") | tostring) | startswith("cursor-bottom")))
      | .content.value ] | (.[0] // "")
  ' "$TMP/page.json" 2>/dev/null
}

known_ids() { [ -s "$SEEN" ] && jq -r '.id' "$SEEN" 2>/dev/null || true; }

ingest_init() {
  known_ids | sort > "$TMP/known"
  : > "$TMP/new.jsonl"
}

ingest_page() {
  if ! parse_page > "$TMP/page.jsonl"; then
    fail "could not parse a Bookmarks response (its timeline has an unexpected shape; X may have changed it)"
    return 3
  fi
  [ -s "$TMP/page.jsonl" ] || return 1
  local line id
  while IFS= read -r line; do
    id=$(printf '%s' "$line" | jq -r '.id' 2>/dev/null)
    if grep -qxF "$id" "$TMP/known" 2>/dev/null; then return 2; fi
    printf '%s\n' "$line" >> "$TMP/new.jsonl"
  done < "$TMP/page.jsonl"
  return 0
}

fetch_new() {
  local qid; qid=$(get_query_id) || return 1
  ingest_init
  local cursor="" page=1 rc

  while [ "$page" -le "$MAX_PAGES" ]; do
    fetch_page "$qid" "$cursor" || return 1
    ingest_page; rc=$?
    [ "$rc" -ne 3 ] || return 1
    [ "$rc" -eq 0 ] || break

    cursor=$(next_cursor) || { fail "could not read the next-page cursor of a Bookmarks response (its timeline has an unexpected shape)"; return 1; }
    [ -n "$cursor" ] || break
    page=$(( page + 1 ))
    if [ "$page" -le "$MAX_PAGES" ]; then sleep 2; fi
  done
  return 0
}

BROWSER_LOGIN_HINT="Log the profile in once with: x-bookmarks.sh browser-login"

run_bounded() {
  local secs="$1"; shift
  local flag="$TMP/timed-out"; rm -f "$flag"
  "$@" > "$TMP/ab.out" 2> "$TMP/ab.err" &
  local pid=$!
  ( i=0
    while [ "$i" -lt "$secs" ]; do
      command -p sleep 1
      kill -0 "$pid" 2>/dev/null || exit 0
      i=$(( i + 1 ))
    done
    : > "$flag"; kill -TERM "$pid"; command -p sleep 2; kill -KILL "$pid"
  ) >/dev/null 2>&1 &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  local rc=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  [ -e "$flag" ] && return 124
  return "$rc"
}

ab() {
  BROWSER_OPEN=1
  AGENT_BROWSER_SESSION="$BROWSER_SESSION" AGENT_BROWSER_PROFILE="$BROWSER_PROFILE" \
    run_bounded "$BROWSER_TIMEOUT" "$BROWSER_BIN" "$@"
}

browser_close() {
  ab close >/dev/null 2>&1
  local rc=$?
  BROWSER_OPEN=0
  return "$rc"
}

ab_err_line() { grep -v '^[[:space:]]*$' "$TMP/ab.err" 2>/dev/null | head -1 | tr '\t\r' '  ' | cut -c1-200; }

ab_must() {
  local what="$1"; shift
  ab "$@"
  local rc=$?
  [ "$rc" -ne 124 ] || { fail "$what: agent-browser timed out after ${BROWSER_TIMEOUT}s"; return 1; }
  [ "$rc" -eq 0 ] || { fail "$what: $(ab_err_line)"; return 1; }
  return 0
}

browser_ready() {
  command -v "$BROWSER_BIN" >/dev/null 2>&1 \
    || { fail "$BROWSER_BIN not found (put agent-browser on PATH or set X_BROWSER_BIN; it is a node script, so node has to be on the job's PATH too)"; return 1; }
  [ -d "$BROWSER_PROFILE" ] \
    || { fail "no browser profile at $BROWSER_PROFILE. $BROWSER_LOGIN_HINT"; return 1; }
  return 0
}

browser_logged_out_url() {
  case "$1" in
    *"/i/flow/login"*|*"x.com/login"*|*"twitter.com/login"*) return 0 ;;
  esac
  return 1
}

browser_capture() {
  local har="$1" i
  BROWSER_URL=""
  ab_must "could not start the HAR capture" network har start || return 1
  ab_must "agent-browser open failed" open "https://x.com/i/bookmarks" || return 1
  ab wait --load networkidle >/dev/null 2>&1 || true
  ab wait 2000 >/dev/null 2>&1 || true
  if ab get url; then BROWSER_URL=$(head -1 "$TMP/ab.out" 2>/dev/null); fi
  i=2
  while [ "$i" -le "$MAX_PAGES" ]; do
    ab scroll down 5000 >/dev/null 2>&1 || true
    ab wait 2500 >/dev/null 2>&1 || true
    i=$(( i + 1 ))
  done
  ab_must "could not export the HAR" network har stop "$har" || return 1
  return 0
}

browser_row_problem() {
  local line="$1" status
  status=$(printf '%s' "$line" | jq -r '.status' 2>/dev/null)
  case "$status" in
    200) : ;;
    401|403) printf 'X rejected the browser session (HTTP %s): the profile is logged out. %s' "$status" "$BROWSER_LOGIN_HINT"; return 0 ;;
    429)     printf 'X rate-limited the browser page (HTTP 429); it will be retried tomorrow'; return 0 ;;
    *)       printf 'X answered a Bookmarks request of the browser page with HTTP %s' "$status"; return 0 ;;
  esac
  printf '%s' "$line" | jq -r '.text' > "$TMP/har-body" 2>/dev/null
  jq -e . "$TMP/har-body" >/dev/null 2>&1 \
    && jq -e '(.data.bookmark_timeline_v2.timeline.instructions | type) == "array"' "$TMP/har-body" >/dev/null 2>&1 \
    && return 1
  if jq -e . "$TMP/har-body" >/dev/null 2>&1; then
    printf 'a Bookmarks response of the browser page is not in the expected shape (no bookmark_timeline_v2 timeline; X may have changed it)'
  else
    printf 'a Bookmarks response of the browser page is not valid JSON (truncated or cut off)'
  fi
  return 0
}

browser_pick_row() {
  local rows="$1" cursor="$2" cands="$TMP/har-cands.jsonl" line cause first=""
  if [ -z "$cursor" ]; then
    jq -c 'select(.cursor == "")' "$rows" > "$cands" 2>/dev/null
  else
    jq -c --arg c "$cursor" --arg e "$(printf '%s' "$cursor" | jq -sRr @uri)" \
      'select(.cursor != "" and (.cursor == $e or .cursor == $c))' "$rows" > "$cands" 2>/dev/null
  fi
  while IFS= read -r line; do
    if cause=$(browser_row_problem "$line"); then
      [ -n "$first" ] || first="$cause"
    else
      printf '%s' "$line"; return 0
    fi
  done < "$cands"
  if [ -n "$first" ]; then fail "$first"
  elif [ -z "$cursor" ]; then fail "the bookmarks page made no Bookmarks request that the HAR caught (X changed its page, or it did not finish loading within ${BROWSER_TIMEOUT}s)"
  else fail "the HAR holds no response to the Bookmarks request after cursor ${cursor:0:24}... (the scroll or the wait that should have loaded the next page did not)"
  fi
  return 1
}

browser_read_pages() {
  local har="$1" rows="$TMP/har-rows.jsonl" row rc page=1 cursor=""
  jq -e '.log.entries | type == "array"' "$har" >/dev/null 2>&1 \
    || { fail "the HAR export could not be read (not a HAR file)"; return 1; }
  jq -c 'def cursor_of: (.request.url | capture("[?&]variables=(?<v>[^&]*)")? // {v: ""}).v
           | ((capture("%22cursor%22%3A%22(?<c>(?:[^%]|%(?!22))*)%22")?
               // capture("\"cursor\":\"(?<c>[^\"]*)\"")? // {c: ""}).c);
         .log.entries[]
         | select((.request.method // "GET") == "GET")
         | select(((.request.url // "") | type) == "string")
         | select(.request.url | test("/graphql/[^/]+/Bookmarks(\\?|$)"))
         | {url: .request.url, cursor: cursor_of, status: (.response.status // 0),
            text: (if (.response.content.encoding // "") == "base64"
                   then ((.response.content.text // "") | (try @base64d catch ""))
                   else (.response.content.text // "") end)}' "$har" > "$rows" 2>/dev/null \
    || { fail "the HAR export could not be read (its entries are not in the HAR shape)"; return 1; }
  ingest_init
  while :; do
    row=$(browser_pick_row "$rows" "$cursor") || return 1
    printf '%s' "$row" | jq -r '.text' > "$TMP/page.json"
    ingest_page; rc=$?
    [ "$rc" -ne 3 ] || return 1
    [ "$rc" -eq 0 ] || return 0
    [ "$page" -lt "$MAX_PAGES" ] || return 0
    cursor=$(next_cursor) || { fail "could not read the next-page cursor of a Bookmarks response (its timeline has an unexpected shape)"; return 1; }
    [ -n "$cursor" ] || return 0
    page=$(( page + 1 ))
  done
}

browser_lock() {
  mkdir -p "$AUTODREAM_DIR/locks" 2>/dev/null || { fail "could not create $AUTODREAM_DIR/locks for the browser lock"; return 1; }
  local waited=0 holder age
  while ! mkdir "$BROWSER_LOCK" 2>/dev/null; do
    holder=$(cat "$BROWSER_LOCK/pid" 2>/dev/null)
    if [ -n "$holder" ]; then
      kill -0 "$holder" 2>/dev/null || { browser_lock_reap "$holder"; continue; }
    else
      age=$(( $(date +%s) - $(pstat_mtime "$BROWSER_LOCK" || echo 0) ))
      if [ "$age" -gt 300 ]; then browser_lock_reap ""; continue; fi
    fi
    [ "$waited" -lt "$BROWSER_LOCK_WAIT" ] \
      || { fail "another x-bookmarks run holds the browser profile (pid ${holder:-unknown}); waited ${waited}s"; return 1; }
    command -p sleep 1
    waited=$(( waited + 1 ))
  done
  printf '%s\n' "$$" > "$BROWSER_LOCK/pid"
  BROWSER_LOCK_HELD=1
  return 0
}
browser_lock_reap() {
  local grave="$BROWSER_LOCK.reap.$$"
  mv "$BROWSER_LOCK" "$grave" 2>/dev/null || return 0
  if [ "$(cat "$grave/pid" 2>/dev/null)" = "$1" ]; then rm -rf "$grave"; return 0; fi
  mv "$grave" "$BROWSER_LOCK" 2>/dev/null || rm -rf "$grave"
  return 0
}
browser_unlock() {
  if [ "$BROWSER_LOCK_HELD" = 1 ] && [ "$(cat "$BROWSER_LOCK/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$BROWSER_LOCK"
  fi
  BROWSER_LOCK_HELD=0
  return 0
}

fetch_new_browser() {
  browser_ready || return 1
  browser_lock || return 1
  local har="$TMP/x.har" rc=0
  browser_capture "$har" || rc=1
  browser_close || BROWSER_CAUSE="the browser did not close cleanly (exit $?): $(ab_err_line)"
  if [ "$rc" -eq 0 ] && browser_logged_out_url "$BROWSER_URL"; then
    fail "X sent the browser to its login page ($BROWSER_URL): the profile is logged out. $BROWSER_LOGIN_HINT"
    rc=1
  fi
  [ "$rc" -ne 0 ] || browser_read_pages "$har" || rc=1
  browser_unlock
  [ "$rc" -eq 0 ] && return 0
  : > "$TMP/new.jsonl"
  return 1
}

browser_login() {
  command -v "$BROWSER_BIN" >/dev/null 2>&1 || { echo "x-bookmarks: $BROWSER_BIN not found; put agent-browser on PATH or set X_BROWSER_BIN" >&2; return 1; }
  ( umask 077; mkdir -p "$BROWSER_PROFILE" ) || { echo "x-bookmarks: could not create $BROWSER_PROFILE" >&2; return 1; }
  echo "x-bookmarks: opening x.com in a window on the dedicated profile ($BROWSER_PROFILE)."
  echo "Log in there. The nightly run cannot use the profile while this window is open, so when you are done run:"
  echo "  $BROWSER_BIN --session $BROWSER_SESSION-login close"
  BROWSER_OPEN=0
  run_bounded "$BROWSER_TIMEOUT" "$BROWSER_BIN" --session "$BROWSER_SESSION-login" --profile "$BROWSER_PROFILE" --headed open "https://x.com/i/bookmarks"
  local rc=$?
  [ "$rc" -eq 0 ] || { echo "x-bookmarks: could not open the browser: $(ab_err_line)" >&2; return 1; }
  return 0
}

merge_state() {
  mkdir -p "$STATE_DIR"
  [ -f "$SEEN" ] || : > "$SEEN"
  local tmp="$STATE_DIR/.seen.jsonl.new.$$"
  if ! cat "$SEEN" > "$tmp"; then
    rm -f "$tmp"
    echo "x-bookmarks: could not stage a state update; leaving seen.jsonl untouched" >&2
    return 1
  fi
  local accepted="$TMP/accepted-ids"; : > "$accepted"
  if [ -s "$TMP/new.jsonl" ]; then
    local line id
    while IFS= read -r line; do
      id=$(printf '%s' "$line" | jq -r '.id' 2>/dev/null)
      [ -n "$id" ] || continue
      grep -qxF "$id" "$accepted" 2>/dev/null && continue
      printf '%s\n' "$id" >> "$accepted"
      jq -e --arg id "$id" 'select(.id == $id)' "$SEEN" >/dev/null 2>&1 && continue
      printf '%s\n' "$line" >> "$tmp"
    done < "$TMP/new.jsonl"
  fi
  mv "$tmp" "$SEEN" || { rm -f "$tmp"; echo "x-bookmarks: state update failed; seen.jsonl unchanged" >&2; return 1; }
}

require_findings_dir() { [ -n "$2" ] || { echo "usage: x-bookmarks.sh $1 <findings-dir>" >&2; exit 2; }; }

collect() {
  local findings="$1"
  mkdir -p "$findings"
  collect_bookmarks "$findings"
  local rc=$?
  printf '%s\n' "$(qid_source)" > "$findings/x-bookmarks-queryid.txt"
  write_fetch_record "$findings/x-bookmarks-fetch.txt"
  return $rc
}

FETCH_PATH=not_attempted
BROWSER_CAUSE=""
write_fetch_record() {
  {
    printf '%s\n' "$FETCH_PATH"
    [ -z "$BROWSER_CAUSE" ] || printf '%s\n' "$BROWSER_CAUSE" | tr '\n\t\r' '   ' | cut -c1-300
  } > "$1"
}

run_fetch() {
  if [ "$X_FETCH_MODE" = browser ]; then
    if fetch_new_browser; then FETCH_PATH=browser; return 0; fi
    BROWSER_CAUSE=$(fail_reason)
    local creds_rc creds_reason
    load_creds; creds_rc=$?; creds_reason=$(fail_reason)
    if [ "$creds_rc" -ne 0 ]; then
      FETCH_PATH=failed
      case "$creds_rc" in
        2) fail "the browser path failed ($BROWSER_CAUSE) and there are no GraphQL credentials at $CREDS_FILE to fall back on" ;;
        *) fail "the browser path failed ($BROWSER_CAUSE) and the GraphQL fallback cannot run: $creds_reason" ;;
      esac
      return 1
    fi
    warn_perms
    write_curl_configs
  fi
  if fetch_new; then
    if [ -n "$BROWSER_CAUSE" ]; then FETCH_PATH=fallback_graphql; else FETCH_PATH=graphql; fi
    return 0
  fi
  : > "$TMP/new.jsonl"
  FETCH_PATH=failed
  [ -z "$BROWSER_CAUSE" ] || fail "the browser path failed ($BROWSER_CAUSE) and so did the GraphQL fallback: $(fail_reason)"
  return 1
}

state_write_failed() {
  printf '# x-bookmarks: fetch failed — could not update %s, so this run'"'"'s bookmarks were not recorded (check that the state directory is writable)\n' "$SEEN" > "$1"
}

collect_bookmarks() {
  local findings="$1"
  local out="$findings/x-bookmarks.md" manifest="$findings/x-bookmarks-manifest.txt"
  : > "$manifest"

  if [ "$X_FETCH_MODE" = browser ]; then
    if [ ! -f "$CREDS_FILE" ] && [ ! -d "$BROWSER_PROFILE" ]; then
      printf '# x-bookmarks: not configured (no credentials at %s and no browser profile at %s)\n' "$CREDS_FILE" "$BROWSER_PROFILE" > "$out"
      echo "x-bookmarks: not configured; skipping"
      return 0
    fi
  else
    load_creds
    local creds_rc=$? creds_reason; creds_reason=$(fail_reason)
    case $creds_rc in
      2) printf '# x-bookmarks: not configured (no credentials at %s)\n' "$CREDS_FILE" > "$out"
         echo "x-bookmarks: not configured; skipping"
         return 0 ;;
      1) printf '# x-bookmarks: fetch failed — %s\n' "$creds_reason" > "$out"
         echo "x-bookmarks: $creds_reason"
         FETCH_PATH=failed
         return 0 ;;
    esac
    warn_perms
    write_curl_configs
  fi

  if ! run_fetch; then
    local note reason; reason=$(fail_reason)
    note="this run could not reach X ($reason). The bookmarks below were captured earlier and are still unread."
    local state_ok=0; merge_state || state_ok=1
    [ "$state_ok" -eq 0 ] || note="$note It also could not update $SEEN."
    if ! emit_unread "$out" "$manifest" "$note"; then
      if [ "$state_ok" -ne 0 ]; then state_write_failed "$out"
      else printf '# x-bookmarks: fetch failed — %s\n' "$(fail_reason)" > "$out"; fi
    fi
    echo "x-bookmarks: $(fail_reason)"
    return 0
  fi

  local note=""
  merge_state || note="this run could not update $SEEN, so the bookmarks it fetched were not recorded (check that the state directory is writable). The bookmarks below were captured earlier and are still unread."
  if ! emit_unread "$out" "$manifest" "$note"; then
    if [ -n "$note" ]; then state_write_failed "$out"; else printf '# x-bookmarks: no unread bookmarks\n' > "$out"; fi
  fi
  echo "x-bookmarks: $(wc -l < "$manifest" | tr -d ' ') unread -> $out"
  return 0
}

emit_unread() {
  local out="$1" manifest="$2" warn="${3:-}"
  [ -s "$SEEN" ] || return 1
  local unread="$TMP/unread.jsonl"
  jq -sc 'map(select(.read_on == null)) | sort_by([(.id | length), .id]) | reverse | .[]' \
    "$SEEN" 2>/dev/null | head -n "$MAX_UNREAD" > "$unread"
  [ -s "$unread" ] || return 1

  local total; total=$(jq -c 'select(.read_on == null)' "$SEEN" 2>/dev/null | wc -l | tr -d ' ')
  {
    printf '# Unread X bookmarks\n'
    [ -n "$warn" ] && printf '\n> Note: %s\n' "$warn"
    printf '\n%s unread bookmark(s)' "$total"
    [ "$total" -gt "$MAX_UNREAD" ] && printf '; showing the %s most recent' "$MAX_UNREAD"
    printf '.\n\n'
    jq -r --argjson cap "$MAX_TEXT" '
      "## @" + .author + "\n" +
      .url + "\n\n" +
      (if (.text | length) > $cap then (.text[0:$cap] + " […]") else .text end) + "\n" +
      (if (.links | length) > 0 then "\nLinks: " + (.links | join(", ")) + "\n" else "" end)
    ' "$unread"
  } > "$out"
  jq -r '.id' "$unread" > "$manifest"
  return 0
}

mark_read() {
  local findings="$1"
  require_findings_dir mark-read "$findings"
  local manifest="$findings/x-bookmarks-manifest.txt"
  [ -s "$manifest" ] || { echo "x-bookmarks: nothing to mark read"; return 0; }
  [ -s "$SEEN" ] || return 0

  local tmp="$STATE_DIR/.seen.jsonl.read.$$" ids
  ids=$(jq -Rsc 'split("\n") | map(select(length > 0))' "$manifest" 2>/dev/null) || ids='[]'
  if jq -c --argjson ids "$ids" --arg today "$TODAY" '
        .id as $i
        | if (.read_on == null) and (($ids | index($i)) != null)
          then .read_on = $today else . end
      ' "$SEEN" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$SEEN" || { rm -f "$tmp"; echo "x-bookmarks: read-state update failed; they stay unread" >&2; return 0; }
    echo "x-bookmarks: marked $(wc -l < "$manifest" | tr -d ' ') bookmark(s) read"
  else
    rm -f "$tmp"
    echo "x-bookmarks: could not update read state (leaving them unread)" >&2
  fi
  return 0
}

status() {
  printf 'fetch mode:  %s\n' "$X_FETCH_MODE"
  if [ "$X_FETCH_MODE" = browser ]; then
    local bin_state=found profile_state=present
    command -v "$BROWSER_BIN" >/dev/null 2>&1 || bin_state="NOT FOUND"
    [ -d "$BROWSER_PROFILE" ] || profile_state="ABSENT ($BROWSER_LOGIN_HINT)"
    printf 'browser:     %s %s, session %s, profile %s %s\n' "$BROWSER_BIN" "$bin_state" "$BROWSER_SESSION" "$BROWSER_PROFILE" "$profile_state"
  fi
  if [ ! -f "$CREDS_FILE" ]; then
    if [ "$X_FETCH_MODE" = browser ] && [ -d "$BROWSER_PROFILE" ]; then
      printf 'credentials: absent (%s) — the GraphQL fallback is unavailable\n' "$CREDS_FILE"
    else
      printf 'credentials: absent (%s) — feature is off\n' "$CREDS_FILE"
    fi
    return 0
  fi
  printf 'credentials: %s (mode %s)\n' "$CREDS_FILE" "$(pstat_mode "$CREDS_FILE" || echo '?')"
  warn_perms
  if load_creds; then
    printf 'keys:        X_AUTH_TOKEN and X_CT0 both set\n'
  else
    printf 'keys:        INCOMPLETE — %s\n' "$(fail_reason)"
    return 0
  fi
  if [ -s "$SEEN" ]; then
    printf 'state:       %s known, %s unread (%s)\n' \
      "$(wc -l < "$SEEN" | tr -d ' ')" \
      "$(jq -c 'select(.read_on == null)' "$SEEN" 2>/dev/null | wc -l | tr -d ' ')" "$SEEN"
  else
    printf 'state:       empty (%s)\n' "$SEEN"
  fi
  if [ -s "$QID_CACHE" ]; then
    printf 'queryId:     cached, %ss old (ttl %ss)\n' \
      "$(( $(date +%s) - $(pstat_mtime "$QID_CACHE" || echo 0) ))" "$QUERYID_TTL"
  else
    printf 'queryId:     not yet scraped\n'
  fi
}

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

case "${1:-}" in
  collect)
    shift
    findings="${1:-}"
    require_findings_dir collect "$findings"
    if [ "$HAVE_JQ" = "0" ]; then
      mkdir -p "$findings"
      : > "$findings/x-bookmarks-manifest.txt"
      printf '# x-bookmarks: fetch failed — jq is not installed or not on PATH, so bookmarks cannot be parsed\n' \
        > "$findings/x-bookmarks.md"
      FETCH_PATH=failed
      write_fetch_record "$findings/x-bookmarks-fetch.txt"
      echo "x-bookmarks: jq not found; wrote a failure stub" >&2
      exit 0
    fi
    collect "$findings" ;;
  browser-login)
    browser_login ;;
  mark-read)
    shift
    [ "$HAVE_JQ" = "1" ] || { echo "x-bookmarks: jq not found; cannot update read state (they stay unread)" >&2; exit 0; }
    mark_read "${1:-}" ;;
  status)
    [ "$HAVE_JQ" = "1" ] || printf 'jq:          NOT FOUND — the feature cannot run without it\n'
    status ;;
  -h|--help|help) usage ;;
  *) echo "usage: x-bookmarks.sh {collect <findings-dir>|mark-read <findings-dir>|status|browser-login}" >&2; exit 2 ;;
esac
