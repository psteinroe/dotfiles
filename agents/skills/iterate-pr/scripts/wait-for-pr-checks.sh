#!/usr/bin/env bash
set -u

pr_selector="${1:-}"
repo_selector="${2:-}"
if [[ $# -gt 2 ]] \
  || [[ ! "$pr_selector" =~ ^[0-9]+$ && ! "$pr_selector" =~ ^https://[^/]+/[^/]+/[^/]+/pull/[0-9]+$ ]] \
  || [[ -n "$repo_selector" && ! "$repo_selector" =~ ^[^/]+/[^/]+$ ]]; then
  printf 'usage: %s <PR number or URL> [owner/repo]\n' "${0##*/}" >&2
  exit 64
fi

checks_args=(pr checks "$pr_selector")
view_args=(pr view "$pr_selector")
if [[ -n "$repo_selector" ]]; then
  checks_args+=(--repo "$repo_selector")
  view_args+=(--repo "$repo_selector")
fi
checks_args+=(--json name,state,bucket,link,workflow)
view_args+=(--json mergeable,mergeStateStatus,headRefOid,url)

interval="${CI_WAIT_INTERVAL_SECONDS:-30}"
timeout="${CI_WAIT_TIMEOUT_SECONDS:-3600}"
max_errors="${CI_WAIT_MAX_ERRORS:-3}"
stable_polls_required="${CI_WAIT_STABLE_POLLS:-3}"
deadline=$((SECONDS + timeout))
consecutive_errors=0
stable_polls=0
stable_fingerprint=""
expected_head=""
head_changed() {
  jq -cn --arg head "$1" --arg expected "$expected_head" \
    '{status:"head_changed", expectedHead:$expected, head:$head}'
  exit 4
}
gh_error_file="$(mktemp "${TMPDIR:-/tmp}/wait-for-pr-checks.XXXXXX")"
trap 'rm -f "$gh_error_file"' EXIT

while ((SECONDS < deadline)); do
  : >"$gh_error_file"
  pr_state="$(gh "${view_args[@]}" 2>"$gh_error_file")"
  command_status=$?
  command_error="$(<"$gh_error_file")"
  if [[ $command_status -ne 0 ]] || ! jq -e 'type == "object" and (.headRefOid | type == "string" and length > 0)' <<<"$pr_state" >/dev/null 2>&1; then
    consecutive_errors=$((consecutive_errors + 1))
    stable_polls=0
    stable_fingerprint=""
    if ((consecutive_errors >= max_errors)); then
      message="${command_error:-gh pr view returned invalid output}"
      jq -cn \
        --arg message "$message" \
        --argjson command_status "$command_status" \
        '{status:"error", commandStatus:$command_status, message:$message}'
      exit 2
    fi
    sleep "$interval"
    continue
  fi

  head="$(jq -r '.headRefOid' <<<"$pr_state")"
  if [[ -z "$expected_head" ]]; then expected_head="$head"; fi
  if [[ "$head" != "$expected_head" ]]; then head_changed "$head"; fi

  if jq -e '.mergeable == "CONFLICTING" or .mergeStateStatus == "DIRTY"' <<<"$pr_state" >/dev/null; then
    jq -c '{
      status: "conflict",
      mergeable,
      mergeStateStatus,
      headRefOid,
      url
    }' <<<"$pr_state"
    exit 3
  fi

  : >"$gh_error_file"
  checks="$(gh "${checks_args[@]}" 2>"$gh_error_file")"
  command_status=$?
  command_error="$(<"$gh_error_file")"
  valid_json=false
  if jq -e 'type == "array"' <<<"$checks" >/dev/null 2>&1; then
    valid_json=true
  fi

  if [[ $command_status -ne 0 && $command_status -ne 1 && $command_status -ne 8 ]] || [[ $valid_json == false ]]; then
    consecutive_errors=$((consecutive_errors + 1))
    stable_polls=0
    stable_fingerprint=""
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
  # Checks and PR view are separate requests. Revalidate the head after checks
  # so a push during the poll cannot turn the previous commit's checks green.
  : >"$gh_error_file"
  current_pr="$(gh "${view_args[@]}" 2>"$gh_error_file")"
  command_status=$?
  if [[ $command_status -ne 0 ]] || ! jq -e 'type == "object" and (.headRefOid | type == "string" and length > 0)' <<<"$current_pr" >/dev/null 2>&1; then
    consecutive_errors=$((consecutive_errors + 1))
    stable_polls=0
    stable_fingerprint=""
    if ((consecutive_errors >= max_errors)); then
      message="$(<"$gh_error_file")"
      jq -cn --arg message "${message:-Unable to revalidate PR head}" --argjson command_status "$command_status" \
        '{status:"error", commandStatus:$command_status, message:$message}'
      exit 2
    fi
    sleep "$interval"
    continue
  fi
  current_head="$(jq -r '.headRefOid' <<<"$current_pr")"
  if [[ "$current_head" != "$expected_head" ]]; then head_changed "$current_head"; fi
  if jq -e '.mergeable == "CONFLICTING" or .mergeStateStatus == "DIRTY"' <<<"$current_pr" >/dev/null; then
    jq -c '{status:"conflict", mergeable, mergeStateStatus, headRefOid, url}' <<<"$current_pr"
    exit 3
  fi
  consecutive_errors=0

  if ! jq -e 'length > 0' <<<"$checks" >/dev/null 2>&1; then
    stable_polls=0
    stable_fingerprint=""
    sleep "$interval"
    continue
  fi

  failed="$(jq '[.[] | select(.bucket == "fail" or .bucket == "cancel")] | length' <<<"$checks")"
  if [[ "$failed" -gt 0 ]]; then
    jq -c '{
      status: "failed",
      passed: [.[] | select(.bucket == "pass")] | length,
      failed: [.[] | select(.bucket == "fail" or .bucket == "cancel") | {name, workflow, state, link}],
      pending: [.[] | select(.bucket == "pending") | {name, workflow, state, link}]
    }' <<<"$checks"
    exit 1
  fi

  pending="$(jq '[.[] | select(.bucket == "pending")] | length' <<<"$checks")"
  if [[ "$pending" -gt 0 ]]; then
    stable_polls=0
    stable_fingerprint=""
    sleep "$interval"
    continue
  fi

  # GitHub registers workflow jobs asynchronously after a push. A nonempty,
  # terminal check list can therefore be incomplete. Require the same terminal
  # set across multiple polls before declaring the checks passed.
  fingerprint="$(jq -c 'sort_by(.name, .workflow, .link) | map({name, workflow, bucket, state, link})' <<<"$checks")"
  if [[ "$fingerprint" == "$stable_fingerprint" ]]; then
    stable_polls=$((stable_polls + 1))
  else
    stable_fingerprint="$fingerprint"
    stable_polls=1
  fi
  if ((stable_polls < stable_polls_required)); then
    sleep "$interval"
    continue
  fi

  jq -c --arg expected "$expected_head" '{
    status: "passed",
    expectedHead: $expected,
    passed: [.[] | select(.bucket == "pass")] | length,
    skipped: [.[] | select(.bucket == "skipping")] | length
  }' <<<"$checks"
  exit 0
done

jq -cn --argjson timeout "$timeout" '{status:"timeout", timeoutSeconds:$timeout}'
exit 124
