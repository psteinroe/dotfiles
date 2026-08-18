#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wait_script="$script_dir/wait-for-pr-checks.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_ARGS_LOG"
if [[ "${GH_MOCK_MODE:-error}" == "completed" ]]; then
  printf '%s\n' '[{"bucket":"pass","link":"pass-url","name":"Lint","state":"SUCCESS","workflow":"CI"},{"bucket":"fail","link":"fail-url","name":"Test","state":"FAILURE","workflow":"CI"}]'
  exit 1
fi
printf 'mock authentication failure\n' >&2
exit 4
MOCK
chmod +x "$tmp_dir/bin/gh"

export PATH="$tmp_dir/bin:$PATH"
export GH_ARGS_LOG="$tmp_dir/gh-args.log"

set +e
CI_WAIT_INTERVAL_SECONDS=0.05 CI_WAIT_TIMEOUT_SECONDS=1 \
  "$wait_script" >"$tmp_dir/missing.out" 2>"$tmp_dir/missing.err"
missing_status=$?
set -e
if [[ $missing_status -ne 64 ]]; then
  printf 'expected a missing PR selector to exit 64 immediately, got %s\n' "$missing_status" >&2
  exit 1
fi

set +e
GH_MOCK_MODE=completed "$wait_script" 123 >"$tmp_dir/number.out"
number_status=$?
set -e
if [[ $number_status -ne 1 ]]; then
  printf 'expected a PR number to use the current repository and exit 1, got %s\n' "$number_status" >&2
  exit 1
fi
if ! grep -Fxq "pr checks 123 --json name,state,bucket,link,workflow" "$GH_ARGS_LOG"; then
  printf 'numeric selector did not default to the current repository: %s\n' "$(cat "$GH_ARGS_LOG")" >&2
  exit 1
fi

set +e
GH_MOCK_MODE=completed "$wait_script" 123 example/project >"$tmp_dir/number-repo.out"
number_repo_status=$?
set -e
if [[ $number_repo_status -ne 1 ]]; then
  printf 'expected a PR number with an explicit repository to exit 1, got %s\n' "$number_repo_status" >&2
  exit 1
fi
if ! grep -Fxq "pr checks 123 --repo example/project --json name,state,bucket,link,workflow" "$GH_ARGS_LOG"; then
  printf 'explicit repository was not forwarded to gh: %s\n' "$(cat "$GH_ARGS_LOG")" >&2
  exit 1
fi

pr_url="https://github.com/example/project/pull/123"
set +e
CI_WAIT_INTERVAL_SECONDS=0.05 CI_WAIT_TIMEOUT_SECONDS=2 CI_WAIT_MAX_ERRORS=2 \
  "$wait_script" "$pr_url" >"$tmp_dir/error.out"
error_status=$?
set -e
if [[ $error_status -ne 2 ]]; then
  printf 'expected repeated gh errors to exit 2, got %s\n' "$error_status" >&2
  exit 1
fi
jq -e '.status == "error" and .commandStatus == 4 and (.message | contains("authentication"))' \
  "$tmp_dir/error.out" >/dev/null

set +e
GH_MOCK_MODE=completed "$wait_script" "$pr_url" >"$tmp_dir/completed.out"
completed_status=$?
set -e
if [[ $completed_status -ne 1 ]]; then
  printf 'expected completed failing checks to exit 1, got %s\n' "$completed_status" >&2
  exit 1
fi
jq -e '.status == "failed" and (.failed | length) == 1 and .failed[0].name == "Test"' \
  "$tmp_dir/completed.out" >/dev/null
if ! grep -Fq "pr checks $pr_url --json" "$GH_ARGS_LOG"; then
  printf 'PR selector was not forwarded to gh: %s\n' "$(cat "$GH_ARGS_LOG")" >&2
  exit 1
fi

printf 'wait-for-pr-checks tests passed\n'
