#!/usr/bin/env bash
# copilot.sh - GitHub Copilot CLI agent adapter (contract in agent.sh).
# Folder trust is not handled: a trust prompt, if copilot shows one, stalls the
# spawn as "not ready".

agent_name() { echo copilot; }
# verified: --help
agent_command() { echo "copilot --allow-all${CHIEF_AGENT_MODEL:+ --model $CHIEF_AGENT_MODEL}${CHIEF_AGENT_ARGS:+ $CHIEF_AGENT_ARGS}"; }
agent_prepare() { :; }
agent_release() { :; }
# verified against copilot 1.0.97 (footer shows 'Interactive · Allow All')
agent_ready_text() { echo 'Allow All|for commands|for shortcuts'; }
# assumed
agent_paste_text() { echo '\[Pasted'; }
# assumed
agent_trust_text() { echo 'trust the files in this folder'; }
agent_trust_keys() { :; }
# assumed
agent_input_marker() { echo '❯'; }
