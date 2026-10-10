#!/usr/bin/env bash
# codex.sh - OpenAI Codex CLI agent adapter (contract in agent.sh).
# No folder-trust handling: Chief cannot pre-trust a worktree for codex, so a
# trust prompt, if codex shows one, stalls the spawn as "not ready".

agent_name() { echo codex; }
agent_args() { echo "--dangerously-bypass-approvals-and-sandbox${CHIEF_AGENT_MODEL:+ --model $CHIEF_AGENT_MODEL}"; }
agent_command() { echo "codex $(agent_args)"; }
agent_require() { command -v codex >/dev/null || { echo "chief-agent: the 'codex' CLI is not installed" >&2; return 1; }; }
agent_prepare() { :; }
agent_release() { :; }
agent_ready_text() { echo 'context left'; }
agent_paste_text() { echo '\[Pasted Content'; }
agent_input_marker() { echo '›'; }
