#!/usr/bin/env bash
set -uo pipefail

run_id="${1:?usage: failed-run-summary.sh RUN_ID}"
log_dir="${TMPDIR:-/tmp}/pi-ci-logs"
log_file="$log_dir/run-$run_id-failed.log"
mkdir -p "$log_dir"

gh run view "$run_id" --log-failed >"$log_file" 2>&1
status=$?
if [[ "$status" -ne 0 ]]; then
  printf 'Failed to fetch logs for run %s; captured output: %s\n' "$run_id" "$log_file" >&2
  tail -n 80 "$log_file"
  exit "$status"
fi

pattern='error|failed|failure|panic|exception|assert|not ok|timed out|timeout|TS[0-9]{4}|ELIFECYCLE'
excerpt="$(rg -n -i -C 3 -m 60 "$pattern" "$log_file" || true)"
if [[ -n "$excerpt" ]]; then
  printf '%s\n' "$excerpt" | head -n 300
else
  tail -n 160 "$log_file"
fi
printf '\nFull failed log: %s\n' "$log_file"
