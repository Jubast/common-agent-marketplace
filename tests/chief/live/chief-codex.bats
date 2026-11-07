# Chief's own session on Codex CLI: the hooks need the operator's trust, then
# Chief gets the identity, spawns a trivial researcher through the dispatch skill
# and is woken by `codex queue` (the async Stop hook) when it is done - and only
# while the TUI runs. Workers run claude:haiku. The plugin is installed from a
# local marketplace into the scratch CODEX_HOME.
#
# Spends a few codex and claude turns:
#   CHIEF_TEST_CHIEF_CODEX=1 tests/chief/run-tests.sh --only-live tests/chief/live/chief-codex.bats
# The tests run in order; a restart of the TUI keeps the scratch CODEX_HOME.

# bats file_tags=live,codex

setup_file() {
  load ../lib/live
  load ../lib/common
  live_gate CHIEF_TEST_CHIEF_CODEX "Chief on a real codex"
  live_require herdr codex claude jq ss
  live_isolate
  live_login_claude || skip "no claude login for the workers"
  live_chief_workspace
  live_login_codex "$LIVE/ws" "$LIVE/ws/proj" || skip "no codex login at $LIVE_REAL_CODEX_HOME/auth.json"
  mkdir -p "$LIVE/mkt/.agents/plugins" "$LIVE/mkt/plugins"
  ln -s "$REPO_ROOT/plugins/chief" "$LIVE/mkt/plugins/chief"
  cat > "$LIVE/mkt/.agents/plugins/marketplace.json" <<'JSON'
{"name":"chieftest","interface":{"displayName":"chieftest"},"plugins":[{"name":"chief","source":{"source":"local","path":"./plugins/chief"},"policy":{"installation":"AVAILABLE","authentication":"ON_INSTALL"},"category":"Productivity"}]}
JSON
  codex plugin marketplace add "$LIVE/mkt" > /dev/null 2>&1
  codex plugin add chief@chieftest > /dev/null 2>&1
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
  PANE=$(cat "$LIVE/pane" 2>/dev/null || true)
}

# codex_start - a fresh TUI in the Chief workspace; waits for its first screen
codex_start() {
  PANE=$(live_pane chief "$LIVE/ws" codex --dangerously-bypass-approvals-and-sandbox)
  echo "$PANE" > "$LIVE/pane"
  live_wait_visible "$PANE" 'Hooks need review' 60
}
codex_idle() { live_wait_visible_gone "$PANE" 'esc to interrupt' 90; }
codex_quit() { live_quit_tui "$PANE" 'codex resume'; }
newest_rollout() { ls -t "$CODEX_HOME"/sessions/*/*/*/rollout-*.jsonl | head -1; }

@test "trust: codex asks to review Chief's new hooks at startup" {
  codex_start
  live_visible_has "$PANE" 'Review hooks'
}

@test "trust: without it the session gets no identity" {
  herdr pane send-keys "$PANE" Down > /dev/null
  herdr pane send-keys "$PANE" Down > /dev/null
  herdr pane send-keys "$PANE" Enter > /dev/null  # "Continue without trusting"
  live_wait_visible_gone "$PANE" 'Hooks need review' 30
  live_chief_identity "$PANE"
  ! live_screen_has "$PANE" 'NAME=Chief'
  codex_quit
}

@test "trust: trusting the hooks in /hooks turns the identity on" {
  codex_start
  herdr pane send-keys "$PANE" Enter > /dev/null  # "Review hooks"
  live_wait_visible "$PANE" 'trust all' 30
  herdr pane send-keys "$PANE" t > /dev/null
  sleep 1
  herdr pane send-keys "$PANE" Escape > /dev/null
  live_wait_visible_gone "$PANE" 'trust all' 30
  live_chief_identity "$PANE"
  live_screen_has "$PANE" 'NAME=Chief'
}

@test "dispatch: Chief spawns a researcher and is woken by a chief watcher turn" {
  codex_idle
  live_dispatch_and_wake "$PANE" res-cx-1 'chief watcher: res-cx-1'
}

@test "wake: nothing is queued once the TUI is closed" {
  codex_idle
  live_say "$PANE" "$(live_dispatch_prompt res-cx-2)"
  live_wait_screen "$PANE" 'spawned: res-cx-2' 120
  armed() { pgrep -f "$LIVE/.*/hooks/stop-watch-codex\.sh" > /dev/null; }
  eventually 30 armed  # the turn ended and the async Stop hook is watching
  codex_quit
  sleep 3
  ! live_task_status_is res-cx-2 'done:'  # the researcher outlived the TUI
  rollout=$(newest_rollout)
  lines=$(wc -l < "$rollout")
  live_wait_task res-cx-2 'done:' 300
  sleep 15  # five watcher polls (CHIEF_POLL=3)
  assert_equal "$(wc -l < "$rollout")" "$lines"
  ! grep -q 'chief watcher: res-cx-2' "$rollout"
}
