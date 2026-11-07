# Cheap static checks: every script parses, every JSON file is valid,
# executable bits are where they should be.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
CHIEF="$REPO_ROOT/plugins/chief"

parses() { bash -n "$1"; }
valid_json() { jq empty "$1"; }
is_executable() { [ -x "$1" ]; }

while IFS= read -r -d '' f; do
  bats_test_function --description "bash -n: ${f#"$REPO_ROOT"/}" -- parses "$f"
done < <(find "$CHIEF" -name '*.sh' -print0)

for f in "$CHIEF/.claude-plugin/plugin.json" "$CHIEF/.codex-plugin/plugin.json" "$CHIEF/hooks/hooks.json" "$CHIEF/hooks/hooks.codex.json" "$REPO_ROOT/.claude-plugin/marketplace.json"; do
  bats_test_function --description "valid JSON: ${f#"$REPO_ROOT"/}" -- valid_json "$f"
done

while IFS= read -r -d '' f; do
  bats_test_function --description "executable: ${f#"$REPO_ROOT"/}" -- is_executable "$f"
done < <(find "$CHIEF/bin" -maxdepth 1 -name '*.sh' -print0; find "$CHIEF/bin/task" -maxdepth 1 -name '*.sh' -print0; find "$CHIEF/hooks" -maxdepth 1 -name '*.sh' -print0)

node_parses() { node --check "$1"; }
bats_test_function --description "node --check: plugins/chief/extensions/chief-watch/extension.mjs" -- node_parses "$CHIEF/extensions/chief-watch/extension.mjs"
