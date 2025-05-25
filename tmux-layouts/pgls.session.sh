# Set a custom session root path. Default is `$HOME`.
# Must be called before `initialize_session`.
session_root "~/Developer/postgres_lsp"

# Create session with specified name if it does not already exist. If no
# argument is given, session name will be based on layout file name.
if initialize_session "pgls"; then
  new_window "nvim"

  new_window "terminal"

  new_window "logs"

  new_window "biome"

  select_window "logs"
  run_cmd "just show-logs"

  select_window "biome"
  run_cmd "cd ~/Developer/biome"

  select_window "nvim"
  run_cmd "nvim ."
fi

# Finalize session creation and switch/attach to it.
finalize_and_go_to_session
