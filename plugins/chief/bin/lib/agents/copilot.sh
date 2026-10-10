#!/usr/bin/env bash
# copilot.sh - GitHub Copilot CLI agent adapter (contract in agent.sh).
# No folder-trust handling: Chief cannot pre-trust a worktree for copilot, so a
# trust prompt, if copilot shows one, stalls the spawn as "not ready".

agent_name() { echo copilot; }
agent_args() { echo "--allow-all${CHIEF_AGENT_MODEL:+ --model $CHIEF_AGENT_MODEL}"; }
agent_command() { echo "copilot $(agent_args)"; }
agent_require() { command -v copilot >/dev/null || { echo "chief-agent: the 'copilot' CLI is not installed" >&2; return 1; }; }
agent_prepare() { :; }
agent_release() { :; }
agent_ready_text() { echo 'for commands|for shortcuts'; }
agent_paste_text() { echo '\[Pasted'; }
agent_input_marker() { echo '❯|>'; }
