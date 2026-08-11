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

  pending="$(jq '[.[] | select(.bucket == "pending")] | length' <<<"$checks")"
  if [[ "$pending" -gt 0 ]]; then
    sleep "$interval"
    continue
  fi

  jq -c '{
    passed: [.[] | select(.bucket == "pass")] | length,
    failed: [.[] | select(.bucket == "fail" or .bucket == "cancel") | {name, workflow, state, link}],
    skipped: [.[] | select(.bucket == "skipping")] | length
  }' <<<"$checks"

  failed="$(jq '[.[] | select(.bucket == "fail" or .bucket == "cancel")] | length' <<<"$checks")"
  if [[ "$failed" -eq 0 ]]; then
    exit 0
  fi
  exit 1
done

jq -cn --argjson timeout "$timeout" '{status:"timeout", timeoutSeconds:$timeout}'
exit 124
