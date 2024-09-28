# Set a custom session root path. Default is `$HOME`.
# Must be called before `initialize_session`.
session_root "~/Developer/hellomateo"

# Create session with specified name if it does not already exist. If no
# argument is given, session name will be based on layout file name.
if initialize_session "hellomateo"; then
  new_window "hellomateo"
  split_h 25

  select_pane 0
  run_cmd "nvim ."

  select_pane 1
  run_cmd "cd supabase"
  run_cmd "clear"
fi

# Finalize session creation and switch/attach to it.
finalize_and_go_to_session
