#!/usr/bin/env bash
# codex.sh - OpenAI Codex CLI agent adapter (contract in agent.sh).
# Folder trust is not handled: a trust prompt, if codex shows one, stalls the
# spawn as "not ready".

agent_name() { echo codex; }
# verified: --help
agent_command() { echo "codex --dangerously-bypass-approvals-and-sandbox${CHIEF_AGENT_MODEL:+ --model $CHIEF_AGENT_MODEL}${CHIEF_AGENT_ARGS:+ $CHIEF_AGENT_ARGS}"; }
agent_prepare() { :; }
agent_release() { :; }
# verified: string in the codex binary
agent_ready_text() { echo 'context left'; }
# verified: string in the codex binary
agent_paste_text() { echo '\[Pasted Content'; }
# assumed: the glyph is in the binary, its use as the input prompt is not confirmed
agent_input_marker() { echo '›'; }
