def thread_display_status($as_of; $dropped_days):
  . as $thread |
  ([$thread.sessions[] | select(.date <= $as_of)] | sort_by([.date, .hash]) | last // {}) as $latest |
  (($as_of | strptime("%Y-%m-%d") | mktime) - ($dropped_days * 86400) | gmtime | strftime("%Y-%m-%d")) as $cutoff |
  ([$latest.date // "", ($thread.kept_open // "" | select(. <= $as_of))] | max) as $last_touch |
  if $thread.status != "open" then $thread.status
  elif $thread.kind == "idea" then "open"
  elif (["not_achieved", "partially_achieved", "unclear_from_transcript"] | index($latest.outcome // "")) != null and $last_touch < $cutoff then "dropped"
  else "open"
  end;

def annotate_threads($as_of; $dropped_days):
  map(.status = (. | thread_display_status($as_of; $dropped_days)));

def valid_thread:
  type == "object" and
  (.id | type == "string" and test("^t-[0-9a-f]{8}$")) and
  (.kind | type == "string" and (. == "work" or . == "idea")) and
  (.repo | type == "string") and
  (.title | type == "string") and
  (.goal | type == "string") and
  (.sessions | type == "array" and all(.[]; type == "object" and (.date | type == "string") and (.hash | type == "string"))) and
  (.status | type == "string" and (. == "open" or . == "done" or . == "closed_by_sam")) and
  (.done_by == null or (.done_by | type == "string")) and
  (.kept_open == null or (.kept_open | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))) and
  (.last_seen | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"));

def valid_state:
  all(.[]; valid_thread) and ([.[].id] | length == (unique | length));

if valid_state then
  if $mode == "list" then
    annotate_threads($as_of; $dropped_days)
    | map(select(($status_filter == "" or .status == $status_filter) and
                 ($kind_filter == "" or .kind == $kind_filter) and
                 ($repo_filter == "" or .repo == $repo_filter)))
    | if $json == "1" then . else .[] | "\(.id)\t\(.status)\t\(.kind)\t\(.repo)\t\(.title)" end
  elif $mode == "search" then
    annotate_threads($as_of; $dropped_days)
    | map(select([.id, .kind, .repo, .title, .goal, .status] | any(contains($query))))
    | if $json == "1" then . else .[] | "\(.id)\t\(.status)\t\(.kind)\t\(.repo)\t\(.title)" end
  elif $mode == "render" then
    map(.display_status = (. | thread_display_status($as_of; $dropped_days)))
  elif $mode == "report" then
    map(. as $thread |
      ($thread | thread_display_status($as_of; $dropped_days)) as $report_status |
      (if $previous_as_of == "" then null else $thread | thread_display_status($previous_as_of; $dropped_days) end) as $previous_status |
      ($thread.sessions | map(select(.date <= $as_of)) | length) as $report_session_count |
      $thread + {report_status: $report_status, previous_report_status: $previous_status, report_session_count: $report_session_count})
  else .
  end
else
  error("malformed state")
end
