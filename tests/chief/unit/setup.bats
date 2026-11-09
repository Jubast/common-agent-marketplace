# chief-setup.sh: one-time backend config + gitignore.

setup() {
  load ../lib/common
  SETUP="$BIN/chief-setup.sh"
  W="$BATS_TEST_TMPDIR"
}

@test "args: refuses a missing or invalid --backend" {
  export CHIEF_HOME="$W/refused/.chief"
  run "$SETUP"
  assert_failure 1
  run "$SETUP" --backend bogus
  assert_failure 1
}

@test "config: writes the backend and adds .chief/ to .gitignore once, also on a re-run" {
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

@test "config: switching the backend updates it" {
  mkdir -p "$W/p1" && cd "$W/p1" && git init -q
  export CHIEF_HOME="$W/p1/.chief"
  "$SETUP" --backend herdr >/dev/null
  run "$SETUP" --backend orca
  assert_success
  assert_equal "$(cat "$CHIEF_HOME/config/backend")" orca
}

@test "gitignore: keeps existing content and appends .chief/" {
  mkdir -p "$W/p2" && cd "$W/p2" && git init -q
  echo "node_modules/" > .gitignore
  export CHIEF_HOME="$W/p2/.chief"
  "$SETUP" --backend herdr >/dev/null
  assert_equal "$(cat "$W/p2/.gitignore")" "$(printf 'node_modules/\n.chief/')"
}

@test "no git repo: succeeds and creates no .gitignore" {
  mkdir -p "$W/nogit" && cd "$W/nogit"
  export CHIEF_HOME="$W/nogit/.chief"
  run "$SETUP" --backend herdr
  assert_success
  assert_not_exist "$W/nogit/.gitignore"
}

# fake_cli <name> <exit code> - a <name> on PATH that exits so
fake_cli() {
  mkdir -p "$W/bin"
  printf '#!/bin/sh\nexit %s\n' "$2" > "$W/bin/$1"
  chmod +x "$W/bin/$1"
  PATH="$W/bin:$PATH"
}

@test "harness check: warns about a codex without queue, not about one with it" {
  mkdir -p "$W/h1" && cd "$W/h1" && git init -q
  export CHIEF_HOME="$W/h1/.chief"
  fake_cli codex 1
  run "$SETUP" --backend herdr
  assert_success
  assert_output --partial "no 'queue' command"
  fake_cli codex 0
  run "$SETUP" --backend herdr
  refute_output --partial "'queue'"
}

@test "harness check: warns about copilot with experimental off, not with it on" {
  mkdir -p "$W/h2" "$W/ch" && cd "$W/h2" && git init -q
  export CHIEF_HOME="$W/h2/.chief" COPILOT_HOME="$W/ch"
  fake_cli copilot 0
  echo '{}' > "$W/ch/settings.json"
  run "$SETUP" --backend herdr
  assert_success
  assert_output --partial "'experimental' off"
  echo '{"experimental":true}' > "$W/ch/settings.json"
  run "$SETUP" --backend herdr
  refute_output --partial "experimental"
}
