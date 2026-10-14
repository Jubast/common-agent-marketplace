#!/usr/bin/env bash
# layout.sh - where things live under $CHIEF_HOME. Pure definitions, no side
# effects, so the session hook can source it too. Needs $CHIEF_HOME.
#
#   tasks/<id>/   one folder per task: meta status inbox/ lifecycle turn-ended
#                 brief.md report.md evidence/
#   archive/<id>/ a torn-down task's folder
#   state/        global machine state only: locks, agent cursors, trust-owned,
#                 watcher heartbeat
#   backlog.md    the backlog
#   config/       operator configuration
#   worktrees/    one disposable checkout per task

TASKS="$CHIEF_HOME/tasks"
ARCHIVE="$CHIEF_HOME/archive"
STATE="$CHIEF_HOME/state"
BACKLOG="$CHIEF_HOME/backlog.md"
CONFIG="$CHIEF_HOME/config"
WORKTREES="$CHIEF_HOME/worktrees"

# chief_task_dir <id> -> the task's folder: under $TASKS, or $ARCHIVE once torn down.
chief_task_dir() {
  if [ ! -d "$TASKS/$1" ] && [ -d "$ARCHIVE/$1" ]; then
    printf '%s/%s' "$ARCHIVE" "$1"
  else
    printf '%s/%s' "$TASKS" "$1"
  fi
}

# chief_task_path <id> <name> -> a file or folder inside the task's folder.
chief_task_path() {
  printf '%s/%s' "$(chief_task_dir "$1")" "$2"
}

# chief_task_archive <id> -> moves the task's folder into $ARCHIVE.
chief_task_archive() {
  mkdir -p "$ARCHIVE"
  mv "$TASKS/$1" "$ARCHIVE/$1"
}
