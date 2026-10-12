# Lifecycle checklist: {TASK_ID} (brainstormer)

Explicit-only: spawned only because the operator asked to brainstorm. Chief never relays the conversation.

- [ ] filed (chief-backlog.sh add)
- [ ] spawned (chief-spawn.sh); operator told the `attach:` line it printed
- [ ] watching until a terminal state (done/failed/blocked); the brainstormer asks its questions in the pane, never via needs-decision
- [ ] spec skimmed (self-contained: goal, scope, acceptance criteria, decisions with rationale), then reported to operator and held (chief-backlog.sh hold <id> "reported: ...")
- [ ] outcome chosen: handed off to a successor (chief-spawn.sh --from or chief-promote.sh; go-ahead states the exact agent from --dry-run), OR accepted as-is (chief-backlog.sh done, then chief-teardown.sh)

## Conditional (mark N/A if it never applied)
- [ ] steered mid-task (chief-send.sh)
- [ ] escalated (chief-control.sh interrupt/relaunch)
