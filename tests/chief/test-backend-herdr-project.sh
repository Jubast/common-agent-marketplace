#!/usr/bin/env bash
# test-backend-herdr-project.sh - herdr.sh's project-workspace functions
# (backend_project_prepare / backend_project_release) against a FAKE `herdr`
# stub: created once and reused, sync run in its chief-sync tab, closed only
# when Chief created it and no linked workspace remains. Zero cost.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
CHIEF_BIN="$REPO_ROOT/plugins/chief/bin"
. "$TEST_DIR/lib/harness.sh"

echo "test-backend-herdr-project:"

if ! command -v jq >/dev/null 2>&1; then
  echo "  (skipped - jq not on PATH, required by backends/herdr.sh)"
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/fake" "$WORK/project"

# Fake `herdr`: logs every call to $FAKE/calls. Workspaces exist as
# $FAKE/ws.<id> files, each primary with its repo_root in $FAKE/root.<id>
# (`worktree open` of the project root creates one, like the real herdr); $FAKE/synctab marks that workspace's chief-sync tab
# as existing; $FAKE/tab.<id> are the open task tabs (a task pane "w2:pN"
# lives in tab "w2:tN" of the project workspace, as in a tab-per-task layout).
cat > "$WORK/bin/herdr" <<'FAKE_HERDR'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
case "$1 $2" in
  "worktree open") touch "$FAKE/ws.w9"; echo "$4" > "$FAKE/root.w9"
    echo '{"result":{"workspace":{"workspace_id":"w9"}}}' ;;
  "workspace get") [ -e "$FAKE/ws.$3" ] || exit 1; echo '{}' ;;
  "workspace close") rm -f "$FAKE/ws.$3" ;;
  "workspace list")
    for f in "$FAKE"/root.*; do
      [ -e "$f" ] || continue
      jq -n --arg r "$(cat "$f")" --arg id "${f##*root.}" '{result:{workspaces:[{workspace_id:$id,worktree:{repo_root:$r,is_linked_worktree:false}}]}}'
      exit 0
    done
    echo '{"result":{"workspaces":[]}}' ;;
  "tab list")
    if [ -e "$FAKE/synctab" ]; then echo '{"result":{"tabs":[{"label":"chief-sync","tab_id":"w9:t1"}]}}'
    else echo '{"result":{"tabs":[]}}'; fi ;;
  "tab create") touch "$FAKE/synctab"; echo '{"result":{"root_pane":{"pane_id":"w9:p1"}}}' ;;
  "tab close") rm -f "$FAKE/tab.$3"; [ "$3" != "w9:t1" ] || rm -f "$FAKE/synctab" ;;
  "pane list") echo '{"result":{"panes":[{"tab_id":"w9:t1","pane_id":"w9:p1"}]}}' ;;
  "pane get") jq -n --arg t "${3/:p/:t}" '{result:{pane:{tab_id:$t}}}' ;;
esac
exit 0
FAKE_HERDR
chmod +x "$WORK/bin/herdr"

export FAKE="$WORK/fake" PATH="$WORK/bin:$PATH"
export CHIEF_HOME="$WORK/.chief"
. "$CHIEF_BIN/lib/paths.sh"
. "$CHIEF_BIN/lib/meta.sh"
CHIEF_BACKEND=herdr . "$CHIEF_BIN/lib/backends/backend.sh"
P="$WORK/project"
REC=$(chief_project_record "$P")

assert_success "prepare: creates the project workspace when none exists" -- backend_project_prepare t-1 "$P"
assert_eq "$(grep -c '^worktree open ' "$FAKE/calls")" "1" "prepare: one project workspace open"
assert_contains "$(cat "$FAKE/calls")" "worktree open --cwd $P --path $P" "prepare: opens the project workspace"
assert_eq "$(cat "$REC")" "w9" "prepare: the created workspace id is recorded"
assert_contains "$(cat "$FAKE/calls")" "tab create --workspace w9 --cwd $P --label chief-sync" "prepare: sync gets its own chief-sync tab"
assert_contains "$(cat "$FAKE/calls")" "pane run w9:p1" "prepare: sync runs in the chief-sync pane"
assert_contains "$(cat "$FAKE/calls")" "pane wait-output w9:p1 --match chief-sync: done t-1" "prepare: waits for this run's sync to finish"

assert_success "prepare: second task" -- backend_project_prepare t-2 "$P"
assert_eq "$(grep -c '^worktree open ' "$FAKE/calls")" "1" "prepare: the workspace is reused, not reopened"
assert_eq "$(grep -c '^pane run ' "$FAKE/calls")" "2" "prepare: every task runs its own sync"

assert_eq "$(grep -c '^tab create ' "$FAKE/calls")" "1" "prepare: the chief-sync tab is reused"

backend_project_release "$P"
assert_file_missing "$FAKE/ws.w9" "release: closes the workspace Chief created"
assert_file_missing "$REC" "release: forgets it"

# An operator-owned primary workspace is reused and never closed.
rm -f "$FAKE/calls" "$FAKE/synctab" "$FAKE"/root.*; echo "$P" > "$FAKE/root.w2"; touch "$FAKE/ws.w2"
assert_success "prepare: with an operator-owned primary" -- backend_project_prepare t-3 "$P"
assert_not_contains "$(cat "$FAKE/calls")" "worktree open" "prepare: reuses the operator's workspace"
assert_contains "$(cat "$FAKE/calls")" "tab create --workspace w2 --cwd $P --label chief-sync" "prepare: syncs in its own tab, not the operator's panes"
backend_project_release "$P"
assert_contains "$(cat "$FAKE/calls")" "tab close w9:t1" "release: closes the chief-sync tab Chief added"
assert_not_contains "$(cat "$FAKE/calls")" "workspace close" "release: never closes a workspace Chief didn't create"
assert_file_missing "$FAKE/synctab" "release: the operator's workspace is left without a chief-sync tab"

# Killing one task closes only its own tab, never the project workspace.
chief_meta_set t-1 endpoint herdr:w2:p3
chief_meta_set t-2 endpoint herdr:w2:p4
touch "$FAKE/tab.w2:t3" "$FAKE/tab.w2:t4"
rm -f "$FAKE/calls"
backend_kill t-1
assert_contains "$(cat "$FAKE/calls")" "tab close w2:t3" "kill: closes the task's own tab"
assert_not_contains "$(cat "$FAKE/calls")" "workspace close" "kill: never closes the workspace"
assert_file_missing "$FAKE/tab.w2:t3" "kill: the task's tab is gone"
assert_file_exists "$FAKE/tab.w2:t4" "kill: a sibling task's tab survives"
assert_file_exists "$FAKE/ws.w2" "kill: the project workspace survives"

harness_summary
