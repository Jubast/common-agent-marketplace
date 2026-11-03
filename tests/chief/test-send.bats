# chief-send.sh: durable steering inbox + doorbell, against a real herdr.

setup() {
  load lib/common
  chief_common_setup
  chief_project
  SEND="$BIN/task/chief-send.sh"
}

teardown() { chief_herdr_stop; }

@test "refuses an unknown task id" {
  run "$SEND" nope "hi"
  assert_failure
}

@test "refuses an empty message" {
  spawn t-1
  run "$SEND" t-1 "   "
  assert_failure
}

@test "numbers messages 001, 002 and stores the text verbatim" {
  spawn t-1
  run "$SEND" t-1 "please also add a README note"
  assert_success
  run "$SEND" t-1 "and run the tests"
  assert_success
  assert_file_exists "$CHIEF_HOME/tasks/t-1/inbox/001.msg"
  assert_file_exists "$CHIEF_HOME/tasks/t-1/inbox/002.msg"
  assert_equal "$(cat "$CHIEF_HOME/tasks/t-1/inbox/001.msg")" "please also add a README note"
}

@test "numbering continues from handled/ history, never reuses 001" {
  spawn t-1
  "$SEND" t-1 "first"
  "$SEND" t-1 "second"
  mv "$CHIEF_HOME/tasks/t-1/inbox/001.msg" "$CHIEF_HOME/tasks/t-1/inbox/handled/"
  run "$SEND" t-1 "third message"
  assert_success
  assert_file_exists "$CHIEF_HOME/tasks/t-1/inbox/003.msg"
}

# Zero-padded numbers must count in decimal: 008/009 are invalid octal and
# 010-017 etc. are valid-but-wrong octal.
numbering_continues_after() {
  local last=$1 tid="n-$1" box want
  spawn "$tid"
  box="$CHIEF_HOME/tasks/$tid/inbox"
  mkdir -p "$box/handled"
  echo old > "$box/handled/$last.msg"
  want=$(printf '%03d' $((10#$last + 1)))
  run "$SEND" "$tid" "next"
  assert_success
  assert_file_exists "$box/$want.msg"
}
for last in 007 008 009 010 011 019 099; do
  bats_test_function --description "numbering after a last message numbered $last continues in decimal" \
    -- numbering_continues_after "$last"
done

turns_have() { run standin_turns "$1"; assert_output --partial "$2"; }

@test "a special key reaches the backend" {
  spawn t-1
  wait_settled t-1
  standin_type t-1 "typed-by-test"
  run "$SEND" t-1 --key Enter
  assert_success
  eventually 10 turns_have t-1 "typed-by-test"
}

@test "a message rings a doorbell line, not the raw text" {
  spawn t-1
  run "$SEND" t-1 "hello"
  assert_success
  eventually 10 turns_have t-1 "instruction waiting in"
  refute_output --partial "hello"
}
