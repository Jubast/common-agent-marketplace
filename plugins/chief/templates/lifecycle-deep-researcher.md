# Lifecycle checklist: {TASK_ID} (deep-researcher)

- [ ] filed (chief-backlog.sh add)
- [ ] spawned from a done researcher (chief-spawn.sh --from, after operator go-ahead naming the branch and exact agent from --dry-run)
- [ ] watching until a terminal state (done/failed/blocked/needs-decision)
- [ ] reported to operator: conclusion line, recommended option, New options added: yes|no, report path (not the report's content); no review, and held (chief-backlog.sh hold <id> "reported: ...")
- [ ] outcome chosen: handed off to builder or explicitly requested brainstormer (chief-promote.sh or chief-spawn.sh --from), OR accepted as-is (chief-backlog.sh done, then chief-teardown.sh)

## Conditional (mark N/A if it never applied)
- [ ] steered mid-task (chief-send.sh)
- [ ] escalated (chief-control.sh interrupt/relaunch); a fresh retry uses chief-spawn.sh <new-id> <project> --mode deep-researcher --from <researcher-id>, also after source archival
