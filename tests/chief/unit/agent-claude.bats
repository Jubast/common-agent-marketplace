# agents/claude.sh: contract values and pre-trust in .claude.json.

setup() {
  load ../lib/common
  chief_common_setup
  export CHIEF_HOME="$BATS_TEST_TMPDIR/.chief"
  . "$CHIEF_BIN/lib/paths.sh"
  chief_ensure_dirs
  . "$CHIEF_BIN/lib/meta.sh"
  . "$CHIEF_BIN/lib/agents/agent.sh"
  chief_agent_load claude
  CFG="$CLAUDE_CONFIG_DIR/.claude.json"
}

flag() { jq -r --arg p "$1" '.projects[$p].hasTrustDialogAccepted // "unset"' "$CFG"; }

@test "agent contract values" {
  assert_equal "$(agent_name)" claude
  assert_equal "$(agent_command)" "claude --dangerously-skip-permissions"
  assert_equal "$(agent_ready_text)" "bypass permissions"
  assert_equal "$(agent_trust_text)" "trust this folder"
  assert_equal "$(agent_trust_keys)" "down enter"
}

@test "agent: model flag when a model is set" {
  CHIEF_AGENT_MODEL=sonnet
  assert_equal "$(agent_command)" "claude --dangerously-skip-permissions --model sonnet"
}

@test "trust: creates the config when missing and sets the flag" {
  agent_prepare /a
  assert_equal "$(flag /a)" true
}

@test "trust: preserves other keys, handles several dirs, records each dir once" {
  echo '{"theme":"dark","projects":{"/b":{"allowedTools":["x"]}}}' > "$CFG"
  agent_prepare /b; agent_prepare /b2
  assert_equal "$(jq -r .theme "$CFG")" dark
  assert_equal "$(jq -c '.projects["/b"].allowedTools' "$CFG")" '["x"]'
  assert_equal "$(flag /b2)" true
  agent_prepare /b
  assert_equal "$(grep -cxF /b "$STATE/trust-owned")" 1
}

@test "untrust: removes the flag it set and keeps the project's other keys" {
  echo '{"projects":{"/b":{"allowedTools":["x"]}}}' > "$CFG"
  agent_prepare /b
  agent_release /b
  assert_equal "$(flag /b)" unset
  assert_equal "$(jq -c '.projects["/b"].allowedTools' "$CFG")" '["x"]'
}

@test "untrust: leaves a dir the user already trusted" {
  echo '{"projects":{"/u":{"hasTrustDialogAccepted":true}}}' > "$CFG"
  agent_prepare /u; agent_release /u
  assert_equal "$(flag /u)" true
}

@test "trust: corrupt JSON warns and is left untouched" {
  echo '{not json' > "$CFG"
  run agent_prepare /d
  assert_output --partial "could not pre-trust /d"
  assert_equal "$(cat "$CFG")" "{not json"
}

@test "trust: CHIEF_NO_PRETRUST=1 warns and is a no-op" {
  CHIEF_NO_PRETRUST=1 run agent_prepare /e
  assert_output --partial "not pre-trusted"
  assert_not_exist "$CFG"
}

@test "release: untrusts the worktree and drops it from the marker" {
  agent_prepare /r
  agent_release /r
  assert_equal "$(flag /r)" unset
  assert_equal "$(grep -cxF /r "$STATE/trust-owned" || true)" 0
}

@test "a symlinked .claude.json stays a symlink; a symlinked dir is trusted under both spellings" {
  local w="$BATS_TEST_TMPDIR"
  mkdir -p "$w/real/d"; ln -s "$w/real/d" "$w/link"
  echo '{}' > "$w/real.json"; ln -sf "$w/real.json" "$CFG"
  agent_prepare "$w/link"
  assert_link_exist "$CFG"
  assert_equal "$(jq -r --arg a "$w/link" --arg b "$w/real/d" '[.projects[$a].hasTrustDialogAccepted, .projects[$b].hasTrustDialogAccepted] | join(",")' "$w/real.json")" "true,true"
  agent_release "$w/link"
  assert_equal "$(jq -c '.projects' "$w/real.json")" "{}"
}
