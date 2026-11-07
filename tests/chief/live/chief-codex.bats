# Chief on Codex: the hook trust flow, identity, a researcher dispatched through
# the dispatch skill and woken by `codex queue`, and no wake once the TUI is closed.

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
  live_wait 60 live_visible_has "$PANE" 'Hooks need review'
}
codex_idle() { live_wait 90 live_visible_gone "$PANE" 'esc to interrupt'; }
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
  live_wait 30 live_visible_gone "$PANE" 'Hooks need review'
  live_chief_identity "$PANE"
  run ! live_screen_has "$PANE" 'NAME=Chief'
  codex_quit
}

@test "trust: trusting the hooks in /hooks turns the identity on" {
  codex_start
  herdr pane send-keys "$PANE" Enter > /dev/null  # "Review hooks"
  live_wait 30 live_visible_has "$PANE" 'trust all'
  herdr pane send-keys "$PANE" t > /dev/null
  live_wait 10 live_visible_gone "$PANE" 'need review'
  herdr pane send-keys "$PANE" Escape > /dev/null
  live_wait 30 live_visible_gone "$PANE" 'trust all'
  live_chief_identity "$PANE"
  live_screen_has "$PANE" 'NAME=Chief'
}

@test "dispatch: Chief spawns a researcher and is woken by a chief watcher turn" {
  codex_idle
  live_dispatch_and_wake "$PANE" res-cx-1 'chief watcher: res-cx-1'
}

@test "wake: nothing is queued once the TUI is closed" {
  codex_idle
  live_say "$PANE" "$(live_dispatch_prompt res-cx-2 "$LIVE/go")"
  live_wait 120 live_screen_has "$PANE" 'spawned: res-cx-2'
  armed() { pgrep -f "$LIVE/.*/hooks/stop-watch-codex\.sh" > /dev/null; }
  eventually 30 armed  # the turn ended and the async Stop hook is watching
  codex_quit
  rollout=$(newest_rollout)
  lines=$(wc -l < "$rollout")
  touch "$LIVE/go"  # the researcher was held until the TUI was gone
  eventually 300 live_task_status_is res-cx-2 'done:'
  sleep 15  # five watcher polls (CHIEF_POLL=3)
  assert_equal "$(wc -l < "$rollout")" "$lines"
  run ! grep -q 'chief watcher: res-cx-2' "$rollout"
}
