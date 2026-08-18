#!/usr/bin/env bash
set -u

pr_selector="${1:-}"
if [[ ! "$pr_selector" =~ ^https://[^/]+/[^/]+/[^/]+/pull/[0-9]+$ ]]; then
  printf 'usage: %s <full PR URL>\n' "${0##*/}" >&2
  exit 64
fi

interval="${CI_WAIT_INTERVAL_SECONDS:-30}"
timeout="${CI_WAIT_TIMEOUT_SECONDS:-3600}"
max_errors="${CI_WAIT_MAX_ERRORS:-3}"
deadline=$((SECONDS + timeout))
consecutive_errors=0
gh_error_file="$(mktemp "${TMPDIR:-/tmp}/wait-for-pr-checks.XXXXXX")"
trap 'rm -f "$gh_error_file"' EXIT

while ((SECONDS < deadline)); do
  args=(pr checks "$pr_selector" --json name,state,bucket,link,workflow)

  : >"$gh_error_file"
  checks="$(gh "${args[@]}" 2>"$gh_error_file")"
  command_status=$?
  command_error="$(<"$gh_error_file")"
  valid_json=false
  if jq -e 'type == "array"' <<<"$checks" >/dev/null 2>&1; then
    valid_json=true
  fi

  if [[ $command_status -ne 0 && $command_status -ne 1 && $command_status -ne 8 ]] || [[ $valid_json == false ]]; then
    consecutive_errors=$((consecutive_errors + 1))
    if ((consecutive_errors >= max_errors)); then
      message="${command_error:-gh pr checks returned invalid output}"
      jq -cn \
        --arg message "$message" \
        --argjson command_status "$command_status" \
        '{status:"error", commandStatus:$command_status, message:$message}'
      exit 2
    fi
    sleep "$interval"
    continue
  fi
  consecutive_errors=0

  if ! jq -e 'length > 0' <<<"$checks" >/dev/null 2>&1; then
    sleep "$interval"
    continue
  fi

  jq_filter='def human_gate:
    ([.name, .workflow, .state] | map(. // "") | join(" "))
    | test("approval|required review|review required|manual approval|merge queue"; "i");'

  failed="$(jq "$jq_filter [.[] | select(.bucket == \"fail\" or .bucket == \"cancel\")] | length" <<<"$checks")"
  if [[ "$failed" -gt 0 ]]; then
    jq -c "$jq_filter {
      status: \"failed\",
      passed: [.[] | select(.bucket == \"pass\")] | length,
      failed: [.[] | select(.bucket == \"fail\" or .bucket == \"cancel\") | {name, workflow, state, link}],
      pending: [.[] | select(.bucket == \"pending\") | {name, workflow, state, link}]
    }" <<<"$checks"
    exit 1
  fi

  actionable_pending="$(jq "$jq_filter [.[] | select(.bucket == \"pending\" and (human_gate | not))] | length" <<<"$checks")"
  if [[ "$actionable_pending" -gt 0 ]]; then
    sleep "$interval"
    continue
  fi

  human_pending="$(jq "$jq_filter [.[] | select(.bucket == \"pending\" and human_gate)] | length" <<<"$checks")"
  if [[ "$human_pending" -gt 0 ]]; then
    jq -c "$jq_filter {
      status: \"human_gate\",
      pending: [.[] | select(.bucket == \"pending\" and human_gate) | {name, workflow, state, link}]
    }" <<<"$checks"
    exit 3
  fi

  jq -c '{
    status: "passed",
    passed: [.[] | select(.bucket == "pass")] | length,
    skipped: [.[] | select(.bucket == "skipping")] | length
  }' <<<"$checks"
  exit 0
done

jq -cn --argjson timeout "$timeout" '{status:"timeout", timeoutSeconds:$timeout}'
exit 124
