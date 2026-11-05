# chief-setup.sh: one-time backend config + gitignore.

setup() {
  load ../lib/common
  SETUP="$BIN/chief-setup.sh"
  W="$BATS_TEST_TMPDIR"
}

@test "refuses with no --backend, and with an invalid backend name" {
  export CHIEF_HOME="$W/refused/.chief"
  run "$SETUP"
  assert_failure
  run "$SETUP" --backend bogus
  assert_failure
}

@test "writes the backend config and adds .chief/ to .gitignore once, also on re-run" {
  mkdir -p "$W/p1" && cd "$W/p1" && git init -q
  export CHIEF_HOME="$W/p1/.chief"
  run "$SETUP" --backend herdr
  assert_success
  assert_equal "$(cat "$CHIEF_HOME/config/backend")" herdr
  assert_file_exists "$W/p1/.gitignore"
  assert_equal "$(grep -c '^\.chief/$' "$W/p1/.gitignore")" 1
  run "$SETUP" --backend herdr
  assert_success
  assert_equal "$(grep -c '^\.chief/$' "$W/p1/.gitignore")" 1
}

@test "switching backend updates the config" {
  mkdir -p "$W/p1" && cd "$W/p1" && git init -q
  export CHIEF_HOME="$W/p1/.chief"
  "$SETUP" --backend herdr >/dev/null
  run "$SETUP" --backend orca
  assert_success
  assert_equal "$(cat "$CHIEF_HOME/config/backend")" orca
}

@test "existing .gitignore content is preserved, .chief/ appended" {
  mkdir -p "$W/p2" && cd "$W/p2" && git init -q
  echo "node_modules/" > .gitignore
  export CHIEF_HOME="$W/p2/.chief"
  "$SETUP" --backend herdr >/dev/null
  assert_equal "$(cat "$W/p2/.gitignore")" "$(printf 'node_modules/\n.chief/')"
}

@test "does not fail outside a git repo and invents no gitignore" {
  mkdir -p "$W/nogit" && cd "$W/nogit"
  export CHIEF_HOME="$W/nogit/.chief"
  run "$SETUP" --backend herdr
  assert_success
  assert_not_exist "$W/nogit/.gitignore"
}
