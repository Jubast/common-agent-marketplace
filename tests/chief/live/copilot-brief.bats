# #90 on real Copilot: a brief-sized prompt arrives exactly once, and at least
# one attempt hits herdr's `agent_prompt_stalled` (else the recovery is untested).

# bats file_tags=live,copilot

setup_file() {
  load ../lib/live
  load ../lib/common
  live_gate CHIEF_TEST_COPILOT_BRIEF "herdr with a real copilot"
  live_require herdr copilot jq ss
  REAL_HERDR=$(command -v herdr)
  live_isolate
  mkdir -p "$LIVE/repo"
  git -C "$LIVE/repo" init -q -b main
  git -C "$LIVE/repo" commit -q --allow-empty -m init
  live_login_copilot "$LIVE/repo" || skip "no copilot login at $LIVE_REAL_COPILOT_HOME/config.json"

  # herdr shim: logs one "<id> <bytes> <stalled 0|1>" line per `agent prompt`, then defers to the real herdr
  : > "$LIVE/prompts.log"
  mkdir -p "$LIVE/shim"
  cat > "$LIVE/shim/herdr" <<SHIM
#!/usr/bin/env bash
[ "\$1 \$2" = "agent prompt" ] || exec "$REAL_HERDR" "\$@"
out=\$("$REAL_HERDR" "\$@" 2>&1); rc=\$?
case \$out in *agent_prompt_stalled*) s=1;; *) s=0;; esac
echo "\$3 \${#4} \$s" >> "$LIVE/prompts.log"
printf '%s\n' "\$out"; exit \$rc
SHIM
  chmod +x "$LIVE/shim/herdr"
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
  PATH="$LIVE/shim:$PATH"
  export CHIEF_HOME="$LIVE/chief" CHIEF_BACKEND=herdr
  . "$BIN/lib/paths.sh"
  . "$BIN/lib/meta.sh"
}

# user_messages <id> - user.message events in the copilot session that got <id>'s brief
# (<id> as a whole word: t-brief-1 is not t-brief-10)
user_messages() {
  local f msgs
  for f in "$COPILOT_HOME"/session-state/*/events.jsonl; do
    [ -f "$f" ] || continue
    msgs=$(jq -c 'select(.type == "user.message")' "$f" 2>/dev/null)
    printf '%s\n' "$msgs" | jq -e --arg id "$1" 'tostring | test("(^|[^A-Za-z0-9_-])" + $id + "($|[^A-Za-z0-9_-])")' >/dev/null 2>&1 || continue
    printf '%s\n' "$msgs" | wc -l
    return
  done
  echo 0
}

# attempt <n> - one spawn of a brief-sized prompt, and what arrived
attempt() {
  local n=$1 id=t-brief-$1 status bytes calls
  run "$BIN/chief-spawn.sh" "$id" "$LIVE/repo" --agent copilot --mode researcher \
    --branch "research/$id" --intent "Test run. Write the single word ok into the report file and report done. Do nothing else."
  assert_success
  status=$(chief_task_path "$id" status)
  for _ in $(seq 1 120); do
    case $(tail -n1 "$status" 2>/dev/null) in done:*|failed:*|blocked:*|needs-decision:*) break ;; esac
    sleep 2
  done
  sleep 3  # a late second user.message would land here

  calls=$(grep -c -- "^$id " "$LIVE/prompts.log" || true)
  bytes=$(grep -- "^$id " "$LIVE/prompts.log" | head -1 | cut -d' ' -f2)
  [ "${bytes:-0}" -ge 2500 ]  # the prompt is brief-sized
  assert_equal "$calls" 1     # the brief goes through herdr agent prompt once
  assert_equal "$(user_messages "$id")" 1  # copilot got exactly one user.message
  "$BIN/chief-teardown.sh" "$id" >/dev/null 2>&1
}

for n in $(seq 1 "${CHIEF_TEST_COPILOT_BRIEF_ATTEMPTS:-3}"); do
  bats_test_function --tags live,copilot --description "brief: arrives exactly once on attempt $n" -- attempt "$n"
done

@test "brief: at least one attempt hit agent_prompt_stalled" {
  [ "$(grep -c ' 1$' "$LIVE/prompts.log")" -ge 1 ]
}
