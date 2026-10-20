# Runs the checked-in t3.json scripts flagged for a trigger, so T3 Code's machine-wide setup and
# settle actions follow whatever the worktree's repository declares
case "${1:-}" in
  setup) flag=runOnWorktreeCreate ;;
  settle) flag=runOnSettle ;;
  *)
    echo "Usage: t3-repo-action setup|settle" >&2
    exit 2
    ;;
esac

if [ ! -f t3.json ]; then
  echo "No t3.json in $PWD; nothing to run on $1."
  exit 0
fi

jq -r --arg flag "$flag" '.scripts[]? | select(.[$flag] == true) | .command' t3.json |
  while IFS= read -r command; do
    echo "t3.json: $command"
    bash -c "$command" </dev/null
  done
