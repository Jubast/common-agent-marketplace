#!/usr/bin/env bash
# chief-pr-provider.sh - loads one PR/MR provider adapter and nothing else.
# Mirrors chief-backend.sh's dispatch shape, but split into two entry points
# instead of one at-source-time selection, because PR provider selection has
# two different call patterns:
#   - chief-pr-open.sh doesn't know the provider yet: it must DETECT it from
#     the task's own git remote (chief_pr_detect_provider).
#   - chief-pr-state.sh/review.sh/approve.sh/merge.sh already have a cached
#     pr_provider in the task's .meta (written by chief-pr-open.sh): they
#     LOAD that exact adapter directly (chief_pr_load_provider), no detection.
#
# Adapter contract - each chief-pr-provider-<name>.sh must define all six:
#   pr_open <branch> <base> <title> <body>
#     -> creates the PR/MR. MUST be called with CWD inside the project's git
#        checkout (the task's worktree) - this is the only function that
#        needs repo context, since it's the one call with no PR URL yet to
#        derive it from. Prints the new PR/MR's canonical URL on stdout.
#   pr_state <pr-url>
#     -> read-only. Prints one line per visible blocker (failing/pending
#        check, requested changes, draft, not mergeable); prints nothing when
#        there are none. Never posts, approves, or merges.
#   pr_review <pr-url> <verdict:comment|request-changes> <body>
#     -> posts a top-level review/comment with the given text.
#   pr_review_line <pr-url> <file> <line> <body>
#     -> posts <body> as an inline comment on <file>:<line> in the diff, at
#        the PR's current head. No verdict/state - that's pr_review's job.
#   pr_approve <pr-url>
#     -> submits an approving review/vote.
#   pr_merge <pr-url> [--squash|--merge|--rebase]
#     -> re-checks live preconditions (open, non-draft, mergeable, checks
#        green at the current head) and refuses if any fails, then merges.
# Every function but pr_open takes a full PR/MR URL and re-derives whatever
# provider-specific identity it needs (owner/repo/number, or org/project/repo
# for Azure DevOps) from that URL alone - never from cached state - matching
# chief-local-merge.sh's existing "read live at merge time" precondition style.

# chief_pr_detect_provider <repo-dir> -> prints the provider name and exits 0,
# or exits 1 with a message on stderr. Honors CHIEF_PR_PROVIDER as an
# override (for self-hosted/nonstandard remotes) before inspecting origin.
chief_pr_detect_provider() {
  local dir=$1
  if [ -n "${CHIEF_PR_PROVIDER:-}" ]; then
    printf '%s\n' "$CHIEF_PR_PROVIDER"
    return 0
  fi
  local remote
  remote=$(git -C "$dir" remote get-url origin 2>/dev/null) || {
    echo "chief-pr-provider: no 'origin' remote in $dir" >&2
    return 1
  }
  case "$remote" in
    *github.com*) printf 'github\n' ;;
    *dev.azure.com*|*.visualstudio.com*) printf 'azuredevops\n' ;;
    *gitlab.com*) printf 'gitlab\n' ;;
    *)
      # Self-hosted GitLab has no fixed hostname to match on - refuse rather
      # than guess. CHIEF_PR_PROVIDER=gitlab is the way to target one.
      echo "chief-pr-provider: could not detect a provider from remote '$remote' - set CHIEF_PR_PROVIDER" >&2
      return 1
      ;;
  esac
}

# chief_pr_load_provider <name> -> sources chief-pr-provider-<name>.sh, or
# fails loudly if <name> isn't one of the known adapters.
chief_pr_load_provider() {
  local name=$1
  case "$name" in
    github|gitlab|azuredevops|mock) ;;
    *)
      echo "chief-pr-provider: unsupported provider '$name' (must be github, gitlab, azuredevops, or mock)" >&2
      return 1
      ;;
  esac
  # shellcheck source=/dev/null
  . "$CHIEF_ROOT/bin/lib/chief-pr-provider-$name.sh"
}
