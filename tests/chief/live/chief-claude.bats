# Chief on Claude Code: identity, then a researcher dispatched through the
# dispatch skill, woken by the Stop hook when it finishes.

# bats file_tags=live,claude

setup_file() {
  load ../lib/live
  load ../lib/common
  live_gate CHIEF_TEST_CHIEF_CLAUDE "Chief on a real claude"
  live_require herdr claude jq ss
  live_isolate
  live_login_claude || skip "no claude login: set ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN, or log in"
  live_chief_workspace
  jq --arg p "$LIVE/ws" '. + {projects: {($p): {hasTrustDialogAccepted: true}}}' "$CLAUDE_CONFIG_DIR/.claude.json" \
    > "$CLAUDE_CONFIG_DIR/.claude.json.new" && mv "$CLAUDE_CONFIG_DIR/.claude.json.new" "$CLAUDE_CONFIG_DIR/.claude.json"
  pane=$(live_pane chief "$LIVE/ws" claude --plugin-dir "$REPO_ROOT/plugins/chief" --dangerously-skip-permissions --model haiku)
  echo "$pane" > "$LIVE/pane"
  live_wait 60 live_screen_has "$pane" 'bypass permissions on'
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
  PANE=$(cat "$LIVE/pane")
}

@test "identity: the session answers as Chief" {
  live_chief_identity "$PANE"
  live_screen_has "$PANE" 'NAME=Chief'
}

@test "dispatch: Chief spawns a researcher and is woken when it finishes" {
  live_dispatch_and_wake "$PANE" res-cl-1 'Stop hook feedback|chief watcher'
}
