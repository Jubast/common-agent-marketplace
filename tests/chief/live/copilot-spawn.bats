# The copilot adapter against the REAL Copilot CLI on herdr: its screen needles
# against real screens, then one real `chief-spawn.sh --agent copilot --mode
# researcher` through teardown.
#
# Spends one research turn (the spawned worker's brief); everything else is
# free local screen reading. Fails without retrying on a rate or quota message.
#   CHIEF_TEST_COPILOT=1 tests/chief/run-tests.sh --only-live tests/chief/live/copilot-spawn.bats
# Copilot has no folder-trust handling, so the spawn repo is trusted in the
# scratch config; the probe repo stays untrusted so its trust dialog shows.
# The tests run in order: the probe pane they share is opened by the first.

# bats file_tags=live,copilot

setup_file() {
  load ../lib/live
  load ../lib/common
  live_gate CHIEF_TEST_COPILOT "herdr with a real copilot"
  live_require herdr copilot jq ss
  live_isolate
  mkdir -p "$LIVE/repo" "$LIVE/probe-repo"
  for r in "$LIVE/repo" "$LIVE/probe-repo"; do
    git -C "$r" init -q -b main
    git -C "$r" commit -q --allow-empty -m init
  done
  live_login_copilot "$LIVE/repo" || skip "no copilot login at $LIVE_REAL_COPILOT_HOME/config.json"
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
  export CHIEF_HOME="$LIVE/chief" CHIEF_BACKEND=herdr
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
  . "$BIN/lib/backends/backend.sh"
  chief_agent_load copilot
}

screen() { herdr agent read "$1" --source recent-unwrapped --lines 40 2>/dev/null; }
shows_ready() { grep -Eq -- "$(agent_ready_text)"; }
shows_quota() { grep -qiE 'rate limit|quota|upgrade|usage limit|premium request'; }

# collect_until <agent> <regex> <timeout-s> <dir> - saves each distinct screen as
# <dir>/N.txt (N in $SHOTS) until one matches <regex> (collapsed whitespace)
collect_until() {
  local agent=$1 re=$2 limit=$(( $3 * 10 )) dir=$4 last="" s i
  SHOTS=0
  mkdir -p "$dir"
  for i in $(seq 1 "$limit"); do
    s=$(screen "$agent")
    if [ "$s" != "$last" ]; then SHOTS=$((SHOTS + 1)); printf '%s\n' "$s" > "$dir/$SHOTS.txt"; last=$s; fi
    printf '%s' "$s" | tr -s '[:space:]' ' ' | grep -Eq -- "$re" && return 0
    sleep 0.1
  done
  return 1
}
# ready_screens <dir> <last-n> - how many of screens 1..<last-n> show the ready text
ready_screens() {
  local n=0 i
  for i in $(seq 1 "$2"); do shows_ready < "$1/$i.txt" && n=$((n + 1)); done
  echo "$n"
}

@test "agent_trust_text: matches the real folder-trust dialog, ready text does not" {
  PANE=$(herdr worktree create --cwd "$LIVE/probe-repo" --branch probe --path "$LIVE/probe-wt" --label probe \
           --trust-repository --no-focus | jq -r '.result.root_pane.pane_id // empty')
  [ -n "$PANE" ]
  echo "$PANE" > "$LIVE/probe-pane"
  cmd=$(agent_command)
  herdr agent start probe --kind "$(agent_name)" --pane "$PANE" --timeout 30000 -- ${cmd#* } >/dev/null 2>&1 || true
  collect_until probe "$(agent_trust_text)" 30 "$LIVE/shots-trust"
  assert_equal "$(ready_screens "$LIVE/shots-trust" "$SHOTS")" 0
}

@test "agent_ready_text: matches the real idle footer and nothing before it" {
  herdr agent send-keys probe enter >/dev/null 2>&1
  collect_until probe "$(agent_ready_text)" 30 "$LIVE/shots-ready"
  assert_contains_all "$(cat "$LIVE/shots-ready/$SHOTS.txt")" "Allow All"
  assert_equal "$(ready_screens "$LIVE/shots-ready" $((SHOTS - 1)))" 0
  assert_contains_all "$(chief_agent_input_line < "$LIVE/shots-ready/$SHOTS.txt")" "❯"
}

# A bracketed paste of 20 lines of /help: copilot shows its paste placeholder; if
# it did not take the paste, /help is a local command, not a model turn.
@test "agent_paste_text: matches the real paste placeholder on the input line" {
  PANE=$(cat "$LIVE/probe-pane")
  LONG=$(for _ in $(seq 1 20); do echo "/help"; done)
  herdr pane send-text "$PANE" "$(printf '\033[200~%s\033[201~' "$LONG")" >/dev/null 2>&1
  sleep 2
  pasted=$(screen probe)
  printf '%s' "$pasted" | tr -s '[:space:]' ' ' | grep -Eq -- "$(agent_paste_text)"
  assert_contains_all "$(printf '%s\n' "$pasted" | chief_agent_input_line)" "[Paste #"
  herdr workspace close "${PANE%%:*}" >/dev/null 2>&1 || true
}

@test "chief-spawn: a copilot researcher reaches ready, gets its brief and reports done" {
  ID=t-copilot-1
  INTENT="Test run. Write the single word ok into the report file and report done. Do nothing else."
  run "$BIN/chief-spawn.sh" "$ID" "$LIVE/repo" --agent copilot --mode researcher \
    --branch "research/$ID" --intent "$INTENT"
  assert_success
  assert_output --partial "spawned: $ID"
  assert_equal "$(chief_meta_get "$ID" agent)" copilot

  STATUS=$(chief_task_path "$ID" status)
  finished=0
  for i in $(seq 1 120); do
    case $(tail -n1 "$STATUS" 2>/dev/null) in done:*|failed:*|blocked:*|needs-decision:*) finished=1; break ;; esac
    if [ $((i % 5)) = 0 ] && screen "$ID" | shows_quota; then
      echo "copilot shows a rate/quota message - stopped without retrying" >&2
      return 1
    fi
    sleep 2
  done
  assert_equal "$finished" 1
  assert_equal "$(tail -n1 "$STATUS" | cut -c1-5)" "done:"
  assert_file_not_empty "$(chief_task_path "$ID" report.md)"
}

@test "chief-teardown: discards the copilot task, its worktree and workspace" {
  ID=t-copilot-1
  run "$BIN/chief-teardown.sh" "$ID"
  assert_success
  assert_not_exist "$WORKTREES/$ID"
  assert_equal "$(herdr workspace list | jq -r --arg id "$ID" '[.result.workspaces[]? | select(.label | startswith($id))] | length')" 0
}
