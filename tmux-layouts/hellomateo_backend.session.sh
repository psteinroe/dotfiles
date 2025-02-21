# Set a custom session root path. Default is `$HOME`.
# Must be called before `initialize_session`.
session_root "~/Developer/hellomateo"

# Create session with specified name if it does not already exist. If no
# argument is given, session name will be based on layout file name.
if initialize_session "hellomateo_backend"; then
  new_window "code"
  split_h 25

  select_pane 0
  run_cmd "nvim ."

  new_window "supabase"
  select_window "supabase"
  run_cmd "cd supabase"

  new_window "web-app"
  select_window "web-app"
  run_cmd "cd apps/web-app"

  select_window "code"
fi

# Finalize session creation and switch/attach to it.
finalize_and_go_to_session
