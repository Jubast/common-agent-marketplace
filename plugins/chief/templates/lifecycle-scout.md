# Lifecycle checklist: {TASK_ID} (scout)

- [ ] filed (chief-backlog.sh add)
- [ ] spawned (chief-spawn.sh)
- [ ] watching until a terminal state (done/failed/blocked/needs-decision)
- [ ] reported to operator as-is (no review), and held (chief-backlog.sh hold <id> "reported: ...")
- [ ] outcome chosen: promoted to ship (chief-promote.sh - rejoins the ship checklist), OR accepted as-is (chief-backlog.sh done, then chief-teardown.sh)

## Conditional (mark N/A if it never applied)
- [ ] steered mid-task (chief-send.sh)
- [ ] escalated (chief-control.sh interrupt/relaunch)
