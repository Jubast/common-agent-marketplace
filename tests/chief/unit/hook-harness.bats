# The harness adapters around watch-reason.sh and session-start.sh: what each
# CLI (Claude Code, Codex, Copilot) gets injected and how it is woken. Fake
# codex/copilot CLIs and a stub Copilot SDK; nothing paid, no backend.

setup() {
  load ../lib/common
  W="$BATS_TEST_TMPDIR"
  PLUGIN="$REPO_ROOT/plugins/chief"
  SS="$PLUGIN/hooks/session-start.sh"
  ARM="$PLUGIN/hooks/stop-watch-claude.sh"
  CODEX_STOP="$PLUGIN/hooks/stop-watch-codex.sh"
  WATCH_REASON="$PLUGIN/hooks/watch-reason.sh"
  export CHIEF_POLL=1
  unset PLUGIN_ROOT COPILOT_CLI COPILOT_PROJECT_DIR
}

teardown() {
  [ -z "${TUI_PID:-}" ] || kill "$TUI_PID" 2>/dev/null || true
  [ -z "${EXT_PID:-}" ] || kill "$EXT_PID" 2>/dev/null || true
}

# project - $W/p, a git repo with Chief configured, as cwd and CHIEF_HOME
project() {
  mkdir -p "$W/p" && cd "$W/p" && git init -q -b main && git commit --allow-empty -q -m init
  export CHIEF_HOME="$W/p/.chief"
  "$BIN/chief-setup.sh" --backend herdr >/dev/null
}
# done_task <id> - a finished researcher the watcher has not reported yet
done_task() {
  mkdir -p "$CHIEF_HOME/tasks/$1"
  printf 'status=working\nmode=researcher\n' > "$CHIEF_HOME/tasks/$1/meta"
  echo "done: finished" > "$CHIEF_HOME/tasks/$1/status"
}
context() { jq -r '.hookSpecificOutput.additionalContext // .additionalContext'; }

# fake_codex - a codex on PATH that logs its arguments to $W/codex.log
fake_codex() {
  mkdir -p "$W/bin"
  printf '#!/bin/sh\necho "$@" >> "%s/codex.log"\n' "$W" > "$W/bin/codex"
  chmod +x "$W/bin/codex"
  PATH="$W/bin:$PATH"
}
# tui <dir> - a process named codex running in <dir>, standing in for the TUI
tui() {
  mkdir -p "$W/tui" && cp "$(command -v sleep)" "$W/tui/codex"
  ( cd "$1" && exec "$W/tui/codex" 60 ) &
  TUI_PID=$!
}

@test "session-start: claude gets the nested form and the chief root" {
  project
  run "$SS"
  assert_success
  assert_equal "$(jq -r '.hookSpecificOutput.hookEventName' <<< "$output")" SessionStart
  ctx=$(context <<< "$output")
  assert_contains_all "$ctx" "You are Chief" "chief root: $PLUGIN "
}

@test "session-start: copilot gets a top-level additionalContext" {
  project
  COPILOT_CLI=1 PLUGIN_ROOT="$PLUGIN" run "$SS"
  assert_success
  assert_equal "$(jq -r '.hookSpecificOutput // "none"' <<< "$output")" none
  assert_contains_all "$(context <<< "$output")" "You are Chief" "chief root: $PLUGIN "
}

@test "session-start: codex gets the nested form when only PLUGIN_ROOT is set" {
  project
  PLUGIN_ROOT="$PLUGIN" run "$SS"
  assert_success
  assert_equal "$(jq -r '.hookSpecificOutput.hookEventName' <<< "$output")" SessionStart
}

@test "session-start: copilot reads the session's dir from COPILOT_PROJECT_DIR" {
  project
  unset CHIEF_HOME
  cd "$PLUGIN"
  COPILOT_CLI=1 COPILOT_PROJECT_DIR="$W/p" run "$SS"
  assert_success
  ctx=$(context <<< "$output")
  assert_contains_all "$ctx" "backend: herdr"
  refute_contains_any "$ctx" "NOT CONFIGURED YET"
}

@test "stop-watch-claude: stands down when PLUGIN_ROOT marks codex or copilot" {
  project
  done_task t-1
  PLUGIN_ROOT="$PLUGIN" run "$ARM"
  assert_success
  assert_output ""
  run "$ARM"
  assert_failure 2
  assert_output --partial "chief watcher: t-1"
}

@test "watch-reason: prints the reason a task needs attention" {
  project
  done_task t-1
  run "$WATCH_REASON" .
  assert_success
  assert_output --partial "t-1: state: done"
}

@test "watch-reason: prints nothing when nothing is in flight" {
  project
  run "$WATCH_REASON" .
  assert_success
  assert_output ""
}

@test "watch-reason: exits 3 inside a linked worktree" {
  project
  done_task t-1
  git worktree add -q -b wt "$W/wt"
  run "$WATCH_REASON" "$W/wt"
  assert_failure 3
  assert_output ""
}

@test "stop-watch-codex: queues the reason on the session while a TUI runs" {
  project
  fake_codex
  done_task t-1
  tui "$W/p"
  run "$CODEX_STOP" <<< '{"session_id":"sess-1"}'
  assert_success
  assert_equal "$(grep -c '^queue --thread sess-1 --message chief watcher: t-1: state: done' "$W/codex.log")" 1
}

@test "stop-watch-codex: queues nothing when no TUI runs in the session's dir" {
  project
  fake_codex
  done_task t-1
  mkdir "$W/elsewhere"
  tui "$W/elsewhere"
  run "$CODEX_STOP" <<< '{"session_id":"sess-1"}'
  assert_success
  assert_file_not_exists "$W/codex.log"
}

@test "stop-watch-codex: queues nothing without a session id" {
  project
  fake_codex
  done_task t-1
  tui "$W/p"
  run "$CODEX_STOP" <<< '{}'
  assert_success
  assert_file_not_exists "$W/codex.log"
}

# ext_plugin - a copy of the plugin whose Copilot SDK is a stub logging each
# session.send prompt to $W/send.log
ext_plugin() {
  cp -r "$PLUGIN" "$W/pc"
  mkdir -p "$W/pc/node_modules/@github/copilot-sdk"
  echo '{"name":"@github/copilot-sdk","type":"module","exports":{"./extension":"./extension.mjs"}}' \
    > "$W/pc/node_modules/@github/copilot-sdk/package.json"
  cat > "$W/pc/node_modules/@github/copilot-sdk/extension.mjs" <<STUB
import { appendFileSync } from "node:fs";
export const joinSession = async () => ({ send: async (m) => appendFileSync("$W/send.log", m.prompt + "\n") });
STUB
}
watcher_gone() { ! pgrep -f "$W/pc/bin/chief-watch.sh"; }
sent() { grep -q 'chief watcher: t-1: state: done' "$W/send.log"; }

@test "extension: stands down inside a linked worktree" {
  project
  ext_plugin
  done_task t-1
  git worktree add -q -b wt "$W/wt"
  cd "$W/wt"
  run timeout 10 node "$W/pc/extensions/chief-watch/extension.mjs"
  assert_success
  assert_file_not_exists "$W/send.log"
}

@test "extension: sends the reason, and ends its watcher when terminated" {
  project
  ext_plugin
  done_task t-1
  node "$W/pc/extensions/chief-watch/extension.mjs" & EXT_PID=$!
  eventually 10 sent
  eventually 5 pgrep -f "$W/pc/bin/chief-watch.sh"
  kill "$EXT_PID"
  wait "$EXT_PID" || true
  eventually 5 watcher_gone
}
