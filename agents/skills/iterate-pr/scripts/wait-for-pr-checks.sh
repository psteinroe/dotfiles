#!/usr/bin/env bash
set -u

pr_selector="${1:-}"
interval="${CI_WAIT_INTERVAL_SECONDS:-30}"
timeout="${CI_WAIT_TIMEOUT_SECONDS:-3600}"
deadline=$((SECONDS + timeout))

while ((SECONDS < deadline)); do
  args=(pr checks)
  if [[ -n "$pr_selector" ]]; then
    args+=("$pr_selector")
  fi
  args+=(--json name,state,bucket,link,workflow)

  checks="$(gh "${args[@]}" 2>/dev/null)"
  command_status=$?
  if [[ $command_status -ne 0 && $command_status -ne 1 && $command_status -ne 8 ]]; then
    sleep "$interval"
    continue
  fi

  if ! jq -e 'type == "array" and length > 0' <<<"$checks" >/dev/null 2>&1; then
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
