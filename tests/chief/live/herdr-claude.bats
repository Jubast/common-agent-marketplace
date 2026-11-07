# backends/herdr.sh against a REAL claude: the three things real Claude Code
# rendering does that the stand-in agent of ../backends/herdr.bats can only
# imitate - the folder-trust dialog, the dim placeholder hint in a
# never-prompted input box, and our own text in the input line while a prompt
# is in flight. Everything else is covered there for free.
#
# Spends three trivial claude turns ("reply with exactly: ok").
#   CHIEF_TEST_HERDR=1 tests/chief/run-tests.sh --only-live tests/chief/live/herdr-claude.bats
# The tests run in order: the first two start the agents the later ones use.

# bats file_tags=live,claude

setup_file() {
  load ../lib/live
  load ../lib/common
  live_gate CHIEF_TEST_HERDR "herdr with a real claude"
  live_require herdr claude jq ss
  live_isolate
  live_login_claude || skip "no claude login: set ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN, or log in"
}
teardown_file() {
  load ../lib/live
  load ../lib/common
  live_stop
}

setup() {
  load ../lib/live
  load ../lib/common
  live_env
  WORK="$LIVE/work"
  mkdir -p "$WORK/project"
  [ -d "$WORK/project/.git" ] || { git -C "$WORK/project" init -q -b main; git -C "$WORK/project" commit -q --allow-empty -m init; }
  export CHIEF_HOME="$WORK/.chief"
  . "$BIN/lib/paths.sh"
  chief_ensure_dirs
  . "$BIN/lib/meta.sh"
  . "$BIN/lib/agents/agent.sh"
  . "$BIN/lib/backends/herdr.sh"
}

capture() { herdr agent read "$1" --source recent-unwrapped --lines 200 2>/dev/null; }
# backend_spawn only waits for the first turn to START: poll backend_busy
# before asserting on the reply.
idle() { ! backend_busy "$1"; }
# spawn_task <id> - backend_spawn as chief-spawn.sh calls it, one trivial brief
spawn_task() {
  local id=$1 out
  printf 'Reply with exactly the single word: ok\n' > "$WORK/brief-$id.md"
  chief_meta_set "$id" mode builder
  chief_meta_set "$id" project "$WORK/project"
  chief_meta_set "$id" agent claude
  out=$(backend_spawn "$id" "$WORK/project" "$WORK/brief-$id.md" "chief/$id")
  chief_meta_set "$id" worktree "$(sed -n 1p <<< "$out")"
  chief_meta_set "$id" endpoint "$(sed -n 2p <<< "$out")"
}

@test "backend_spawn: runs real claude in a pre-trusted worktree" {
  spawn_task t-real-1
  eventually 30 idle t-real-1
  assert_contains_all "$(capture t-real-1)" "ok" "bypass permissions"
}

@test "backend_spawn: accepts the folder-trust dialog of real claude" {
  CHIEF_NO_PRETRUST=1 spawn_task t-real-2
  eventually 30 idle t-real-2
  assert_contains_all "$(capture t-real-2)" "ok"
}

# Claude Code fills a never-yet-prompted box with a dim placeholder hint, which a
# bare-emptiness check would misread as pending text; the needle match must not,
# and must catch our own text in flight.
box_has() {  # <id> <text>
  herdr agent read "$1" --source detection --lines 40 2>/dev/null | chief_agent_input_line \
    | chief_agent_has_text "$(printf '%s' "$2" | tr -s '[:space:]' ' ' | cut -c1-24)"
}

@test "input line: misses text that was never sent" {
  chief_agent_use t-real-1
  run ! box_has t-real-2 "never sent to this pane xyz123"
}

@test "input line: catches our own text while the prompt is in flight" {
  chief_agent_use t-real-1
  PROMPT="Reply with exactly the single word: done"
  ( herdr agent prompt t-real-1 "$PROMPT" --wait --until working --until blocked --timeout 30000 \
      > "$WORK/prompt.json" 2>&1 ) &
  prompt_pid=$!
  caught=0
  for _ in $(seq 1 60); do
    box_has t-real-1 "$PROMPT" && { caught=1; break; }
    sleep 0.05
  done
  wait "$prompt_pid"
  assert_equal "$caught" 1
  eventually 30 idle t-real-1
  assert_contains_all "$(capture t-real-1)" "done"
}
