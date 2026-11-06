# chief-send.sh: durable steering inbox + doorbell, against a real herdr.

setup() {
  load ../lib/common
  chief_common_setup
  chief_project
  chief_herdr_server
  SEND="$BIN/task/chief-send.sh"
}

teardown() { chief_herdr_stop; }

@test "send: refuses an unknown task id" {
  run "$SEND" nope "hi"
  assert_failure 1
}

@test "send: refuses an empty message" {
  chief_spawn_quiet t-1
  run "$SEND" t-1 "   "
  assert_failure 1
}

@test "inbox: numbers messages 001, 002 and stores the text verbatim" {
  chief_spawn_quiet t-1
  run "$SEND" t-1 "please also add a README note"
  assert_success
  run "$SEND" t-1 "and run the tests"
  assert_success
  assert_file_exists "$CHIEF_HOME/tasks/t-1/inbox/001.msg"
  assert_file_exists "$CHIEF_HOME/tasks/t-1/inbox/002.msg"
  assert_equal "$(cat "$CHIEF_HOME/tasks/t-1/inbox/001.msg")" "please also add a README note"
}

@test "inbox: numbering continues from handled/ and never reuses 001" {
  chief_spawn_quiet t-1
  "$SEND" t-1 "first"
  "$SEND" t-1 "second"
  mv "$CHIEF_HOME/tasks/t-1/inbox/001.msg" "$CHIEF_HOME/tasks/t-1/inbox/handled/"
  run "$SEND" t-1 "third message"
  assert_success
  assert_file_exists "$CHIEF_HOME/tasks/t-1/inbox/003.msg"
}

# Zero-padded numbers must count in decimal: 008 is invalid octal, 010 is valid
# but wrong octal, 099 rolls over.
numbering_continues_after() {
  local last=$1 tid="n-$1" box want
  chief_spawn_quiet "$tid"
  box="$CHIEF_HOME/tasks/$tid/inbox"
  mkdir -p "$box/handled"
  echo old > "$box/handled/$last.msg"
  want=$(printf '%03d' $((10#$last + 1)))
  run "$SEND" "$tid" "next"
  assert_success
  assert_file_exists "$box/$want.msg"
}
for last in 008 010 099; do
  bats_test_function --description "inbox: numbering continues in decimal after $last" \
    -- numbering_continues_after "$last"
done

turns_have() { run standin_turns "$1"; assert_output --partial "$2"; }

@test "key: a special key reaches the backend" {
  chief_spawn_quiet t-1
  chief_wait_settled t-1
  standin_type t-1 "typed-by-test"
  run "$SEND" t-1 --key Enter
  assert_success
  eventually 10 turns_have t-1 "typed-by-test"
}

@test "doorbell: rings a line, not the raw text" {
  chief_spawn_quiet t-1
  run "$SEND" t-1 "hello"
  assert_success
  eventually 10 turns_have t-1 "instruction waiting in"
  run standin_turns t-1
  refute_output --partial "hello"
}
