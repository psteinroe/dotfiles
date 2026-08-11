#!/usr/bin/env bash
set -u

run_id="${1:?usage: wait-for-run.sh RUN_ID}"
interval="${CI_WAIT_INTERVAL_SECONDS:-30}"
timeout="${CI_WAIT_TIMEOUT_SECONDS:-3600}"
deadline=$((SECONDS + timeout))

while ((SECONDS < deadline)); do
  run="$(gh run view "$run_id" --json status,conclusion,url,workflowName 2>/dev/null)"
  if [[ $? -ne 0 ]]; then
    sleep "$interval"
    continue
  fi

  status="$(jq -r '.status' <<<"$run")"
  if [[ "$status" != "completed" ]]; then
    sleep "$interval"
    continue
  fi

  jq -c '{status, conclusion, workflowName, url}' <<<"$run"
  conclusion="$(jq -r '.conclusion' <<<"$run")"
  if [[ "$conclusion" == "success" || "$conclusion" == "neutral" || "$conclusion" == "skipped" ]]; then
    exit 0
  fi
  exit 1
done

jq -cn --arg runId "$run_id" --argjson timeout "$timeout" \
  '{status:"timeout", runId:$runId, timeoutSeconds:$timeout}'
exit 124
