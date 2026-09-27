#!/usr/bin/env bash
# chief-attribution.sh - detects AI-attribution trailers on a branch's
# commits; never rewrites them.
#
# Matches trailer-shaped lines (Co-Authored-By and similar) and freeform
# "Generated with/by ..." markers naming a known AI/agent/tool - not a
# mention of those words in ordinary prose or a human co-author's name.

_CHIEF_AI_ATTRIBUTION_RE='(^[[:space:]]*(co-authored-by|authored-by|generated-by|generated-with|assisted-by|reviewed-by|signed-off-by)[[:space:]]*:.*\b(claude|anthropic|copilot|codex|chatgpt|openai)\b|generated[[:space:]]+(with|by).*\b(claude|anthropic|copilot|codex|chatgpt|openai)\b)'

# chief_detect_ai_attribution <repo> <base> <branch>
# Prints each offending line found in <branch>'s own commits past <base>,
# one per line, prefixed with that commit's short SHA. Returns 0 if none of
# <branch>'s commits (relative to <base>) contain one, 1 if it does.
chief_detect_ai_attribution() {
  local repo=$1 base=$2 branch=$3
  local sha matched hits=0
  for sha in $(git -C "$repo" rev-list "$base..$branch" 2>/dev/null); do
    matched=$(git -C "$repo" log --format=%B -1 "$sha" | grep -iE "$_CHIEF_AI_ATTRIBUTION_RE") || true
    if [ -n "$matched" ]; then
      printf '%s\n' "$matched" | sed "s/^/${sha:0:7}: /"
      hits=$((hits + 1))
    fi
  done
  [ "$hits" -eq 0 ]
}
