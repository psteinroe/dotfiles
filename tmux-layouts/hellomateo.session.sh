# Set a custom session root path. Default is `$HOME`.
# Must be called before `initialize_session`.
session_root "~/Developer/hellomateo.git"

# Create session with specified name if it does not already exist. If no
# argument is given, session name will be based on layout file name.
if initialize_session "hellomateo"; then
  new_window "nvim"

  new_window "terminal"

  new_window "long running 1"

  new_window "long running 2"

  select_window "nvim"
  run_cmd "nvim ."
fi

# Finalize session creation and switch/attach to it.
finalize_and_go_to_session
