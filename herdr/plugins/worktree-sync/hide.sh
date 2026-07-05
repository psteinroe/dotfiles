source "${0:A:h}/lib/project-context.zsh" || exit 1

workspace_id="${HERDR_WORKSPACE_ID:-}"
if [[ -z "$workspace_id" ]]; then
  echo "No current Herdr workspace id; cannot hide workspace." >&2
  exit 1
fi

herdr workspace close "$workspace_id" >/dev/null
