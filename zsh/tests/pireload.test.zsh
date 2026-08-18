#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin"

cat > "$fixture/bin/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\t%s\n' "${HERDR_SESSION:-}" "$*" >> "$PIRELOAD_TRACE"
case "$1 $2" in
  "agent list")
    printf '%s\n' '{"result":{"agents":[
      {"agent":"pi","pane_id":"p1","agent_status":"idle"},
      {"agent":"pi","pane_id":"p2","agent_status":"working"},
      {"agent":"pi","pane_id":"p3","agent_status":"blocked"},
      {"agent":"pi","pane_id":"p4","agent_status":"done"},
      {"agent":"pi","pane_id":"p5","agent_status":"idle"},
      {"agent":"pi","pane_id":"p6","agent_status":"unknown"},
      {"agent":"other","pane_id":"p7","agent_status":"idle"}
    ]}}'
    ;;
  "pane process-info")
    pane=${4:?}
    if [[ "$pane" == p1 ]]; then pid=101; else pid=105; fi
    printf '{"result":{"process_info":{"foreground_processes":[{"name":"pi","argv0":"pi","pid":%s}]}}}\n' "$pid"
    ;;
  "agent get")
    [[ "$3" == p1 ]]
    printf '%s\n' '{"result":{"agent":{"agent":"pi","pane_id":"p1","agent_status":"idle"}}}'
    ;;
  "agent prompt")
    [[ "$3" == p1 && "$4" == /reload ]]
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$fixture/bin/herdr"

cat > "$fixture/bin/ps" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' '999 105'
EOF
chmod +x "$fixture/bin/ps"

: > "$fixture/trace"
export PIRELOAD_TRACE="$fixture/trace"
export PATH="$fixture/bin:$PATH"
fpath=("$repo_root/zsh/functions" $fpath)
autoload -Uz pireload

output=$(pireload --session fixture)

[[ "$output" == *"[fixture] p1: reloaded."* ]]
[[ "$output" == *"[fixture] p2: working; skipped."* ]]
[[ "$output" == *"[fixture] p3: blocked; skipped."* ]]
[[ "$output" == *"[fixture] p5: background child process active; skipped."* ]]
[[ "$output" == *"[fixture] p6: status unknown; skipped."* ]]
[[ "$output" == *"Pi reload: 1 reloaded, 4 skipped, 1 already done"* ]]
[[ $(grep -c $'^fixture\tagent prompt p1 /reload$' "$fixture/trace") == 1 ]]
[[ $(grep -c $'agent prompt' "$fixture/trace") == 1 ]]

print 'pireload safety test passed'
