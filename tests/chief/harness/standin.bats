# The stand-in agent's modes and the helpers that drive them.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
}

teardown() { chief_herdr_stop; }

agent_working() { herdr agent get "$1" | jq -e '.result.agent.agent_status == "working"'; }
agent_not_working() { ! agent_working "$1"; }
pid_dead() { ! kill -0 "$(cat "$STANDIN_DIR/$1.pid")" 2>/dev/null; }

@test "a turn is logged and the agent settles after it" {
  spawn t-1
  wait_settled t-1
  run standin_turns t-1
  assert_output --partial "turn:"
}

@test "hold keeps the turn working until released" {
  standin_hold t-1
  spawn t-1
  eventually 10 agent_working t-1
  standin_release t-1
  eventually 10 agent_not_working t-1
}

@test "exit ends the stand-in after its turn" {
  standin_mode t-1 exit
  spawn t-1
  eventually 10 pid_dead t-1
}

@test "never-ready makes the spawn fail and roll back" {
  standin_mode t-1 never-ready
  CHIEF_HERDR_START_WAIT=3 run spawn t-1
  assert_failure
  assert_not_exist "$CHIEF_HOME/worktrees/t-1"
}
