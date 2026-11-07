# Chief on Copilot (--experimental): identity, then a researcher dispatched
# through the dispatch skill, woken by the extension; no watcher left on exit.

# bats file_tags=live,copilot

setup_file() {
  load ../lib/live
  load ../lib/common
  live_gate CHIEF_TEST_CHIEF_COPILOT "Chief on a real copilot"
  live_require herdr copilot claude jq ss
  live_isolate
  live_login_claude || skip "no claude login for the workers"
  live_chief_workspace
  live_login_copilot "$LIVE/ws" || skip "no copilot login at $LIVE_REAL_COPILOT_HOME/config.json"
  pane=$(live_pane chief "$LIVE/ws" copilot --experimental --allow-all --plugin-dir "$REPO_ROOT/plugins/chief")
  echo "$pane" > "$LIVE/pane"
  live_wait 60 live_screen_has "$pane" 'Allow All'
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

@test "dispatch: the extension wakes the idle session when the researcher finishes" {
  live_dispatch_and_wake "$PANE" res-cp-1 'chief watcher: res-cp-1'
}

@test "extension: leaves no watcher behind once copilot exits" {
  live_quit_tui "$PANE" 'copilot --resume'
  gone() { ! pgrep -f "$REPO_ROOT/plugins/chief/(hooks/watch-reason|bin/chief-watch)\.sh" > /dev/null; }
  eventually 15 gone
}
