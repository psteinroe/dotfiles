# Set a custom session root path. Default is `$HOME`.
# Must be called before `initialize_session`.
session_root "~/Developer/postgres_lsp"

# Create session with specified name if it does not already exist. If no
# argument is given, session name will be based on layout file name.
if initialize_session "pg_lsp"; then
  new_window "pg_lsp"
  split_h 25

  select_pane 0
  run_cmd "nvim ."

  new_window "logs"
  select_window "logs"
  split_h 50
  select_pane 1
  run_cmd "latest_file=\$(ls -t /Users/psteinroe/Library/Caches/dev.supabase-community.pglsp/pglsp-logs | head -n 1)"
  run_cmd "[ -n \"\$latest_file\" ] && tail -f \"/Users/psteinroe/Library/Caches/dev.supabase-community.pglsp/pglsp-logs/\$latest_file\" || echo 'No log files found'"
  select_pane 0
  run_cmd "nvim ."

  select_window "pg_lsp"
fi

# Finalize session creation and switch/attach to it.
finalize_and_go_to_session
