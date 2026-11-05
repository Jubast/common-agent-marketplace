# agents/claude.sh: contract values and pre-trust in .claude.json.

setup() {
  load ../lib/common
  chief_common_setup
  export CHIEF_HOME="$BATS_TEST_TMPDIR/.chief"
  . "$BIN/lib/paths.sh"
  chief_ensure_dirs
  . "$BIN/lib/meta.sh"
  . "$BIN/lib/agents/agent.sh"
  chief_agent_load claude
  CFG="$CLAUDE_CONFIG_DIR/.claude.json"
}


@test "contract: name, command, ready and trust text" {
  assert_equal "$(agent_name)" claude
  assert_equal "$(agent_command)" "claude --dangerously-skip-permissions"
  assert_equal "$(agent_ready_text)" "bypass permissions"
  assert_equal "$(agent_trust_text)" "trust this folder"
  assert_equal "$(agent_trust_keys)" "down enter"
}

@test "command: adds --model when a model is set" {
  CHIEF_AGENT_MODEL=sonnet
  assert_equal "$(agent_command)" "claude --dangerously-skip-permissions --model sonnet"
}

@test "trust: creates the config when missing and sets the flag" {
  agent_prepare /a
  assert_equal "$(trusted /a)" true
}

@test "trust: keeps other keys and records each dir once" {
  echo '{"theme":"dark","projects":{"/b":{"allowedTools":["x"]}}}' > "$CFG"
  agent_prepare /b; agent_prepare /b2
  assert_equal "$(jq -r .theme "$CFG")" dark
  assert_equal "$(jq -c '.projects["/b"].allowedTools' "$CFG")" '["x"]'
  assert_equal "$(trusted /b2)" true
  agent_prepare /b
  assert_equal "$(grep -cxF /b "$STATE/trust-owned")" 1
}

@test "release: removes its flag and marker entry, keeps the project's other keys" {
  echo '{"projects":{"/b":{"allowedTools":["x"]}}}' > "$CFG"
  agent_prepare /b
  agent_release /b
  assert_equal "$(trusted /b)" unset
  assert_equal "$(jq -c '.projects["/b"].allowedTools' "$CFG")" '["x"]'
  assert_equal "$(grep -cxF /b "$STATE/trust-owned" || true)" 0
}

@test "release: untrusts the worktree and drops it from the marker" {
  agent_prepare /r
  agent_release /r
  assert_equal "$(trusted /r)" unset
  assert_equal "$(grep -cxF /r "$STATE/trust-owned" || true)" 0
}

@test "release: leaves a dir the user already trusted" {
  echo '{"projects":{"/u":{"hasTrustDialogAccepted":true}}}' > "$CFG"
  agent_prepare /u; agent_release /u
  assert_equal "$(trusted /u)" true
}

@test "trust: warns and leaves corrupt JSON untouched" {
  echo '{not json' > "$CFG"
  run agent_prepare /d
  assert_output --partial "could not pre-trust /d"
  assert_equal "$(cat "$CFG")" "{not json"
}

@test "trust: CHIEF_NO_PRETRUST=1 warns and does nothing" {
  CHIEF_NO_PRETRUST=1 run agent_prepare /e
  assert_output --partial "not pre-trusted"
  assert_not_exist "$CFG"
}

@test "trust: keeps a symlinked .claude.json, trusts a symlinked dir under both paths" {
  local w="$BATS_TEST_TMPDIR"
  mkdir -p "$w/real/d"; ln -s "$w/real/d" "$w/link"
  echo '{}' > "$w/real.json"; ln -sf "$w/real.json" "$CFG"
  agent_prepare "$w/link"
  assert_link_exist "$CFG"
  assert_equal "$(jq -r --arg a "$w/link" --arg b "$w/real/d" '[.projects[$a].hasTrustDialogAccepted, .projects[$b].hasTrustDialogAccepted] | join(",")' "$w/real.json")" "true,true"
  agent_release "$w/link"
  assert_equal "$(jq -c '.projects' "$w/real.json")" "{}"
}
