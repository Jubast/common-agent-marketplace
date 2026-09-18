#!/usr/bin/env bash
# chief-pr-provider-azuredevops.sh - Azure DevOps adapter, using `az repos
# pr` (the `azure-devops` az CLI extension).
#
# Azure DevOps has no single canonical PR URL the CLI accepts back as input
# (unlike gh/glab), so this adapter always builds/parses the web URL itself:
#   https://dev.azure.com/<org>/<project>/_git/<repo>/pullrequest/<id>
# pr_open is the only function that needs repo context beyond the URL: it's
# the one call with no PR yet to parse, so it derives org/project/repo from
# `git remote get-url origin` in the CALLER's CWD (the task's worktree) -
# every other function parses everything it needs from the PR URL alone.
#
# pr_merge checks mergeStatus AND branch-policy evaluations separately:
# mergeStatus only reflects conflict-freeness, not build validation/required
# reviewers/status checks, so a PR can report mergeStatus=succeeded while a
# required policy (e.g. a build) is still running or has failed. The policy
# list is the Azure DevOps equivalent of GitHub's statusCheckRollup check in
# chief-pr-provider-github.sh's pr_merge.
#
# pr_review_line is an UNVERIFIED DRAFT - built from Azure DevOps's
# documented REST shape, not run against a live install. `az repos pr thread
# create` has no exposed flags for file/line context, so this goes straight
# to `az rest` against the threads endpoint with a threadContext payload
# instead. Unconfirmed: whether `az repos pr show`'s JSON actually includes
# `.repository.id` under that name, and the exact threadContext/comment
# field names and enum values (commentType, status) at the current
# api-version.

_chief_ado_parse_remote() {
  local remote rest
  remote=$(git remote get-url origin 2>/dev/null) || {
    echo "chief-pr-provider-azuredevops: no 'origin' remote in $(pwd)" >&2
    return 1
  }
  case "$remote" in
    *dev.azure.com/*/_git/*)
      rest=${remote#*dev.azure.com/}
      _CHIEF_ADO_ORG=${rest%%/*}
      rest=${rest#*/}
      _CHIEF_ADO_PROJECT=${rest%%/_git/*}
      _CHIEF_ADO_REPO=${rest#*/_git/}
      ;;
    *.visualstudio.com/*/_git/*)
      _CHIEF_ADO_ORG=${remote#https://}
      _CHIEF_ADO_ORG=${_CHIEF_ADO_ORG%%.visualstudio.com*}
      rest=${remote#*visualstudio.com/}
      _CHIEF_ADO_PROJECT=${rest%%/_git/*}
      _CHIEF_ADO_REPO=${rest#*/_git/}
      ;;
    *)
      echo "chief-pr-provider-azuredevops: could not parse an Azure DevOps remote from '$remote'" >&2
      return 1
      ;;
  esac
  _CHIEF_ADO_REPO=${_CHIEF_ADO_REPO%.git}
}

_chief_ado_parse_url() {
  local url=$1 rest
  case "$url" in
    https://dev.azure.com/*/_git/*/pullrequest/*)
      rest=${url#https://dev.azure.com/}
      _CHIEF_ADO_ORG=${rest%%/*}
      rest=${rest#*/}
      _CHIEF_ADO_PROJECT=${rest%%/_git/*}
      rest=${rest#*/_git/}
      _CHIEF_ADO_REPO=${rest%%/pullrequest/*}
      _CHIEF_ADO_ID=${rest#*/pullrequest/}
      ;;
    *)
      echo "chief-pr-provider-azuredevops: not an Azure DevOps PR URL: $url" >&2
      return 1
      ;;
  esac
}

pr_open() {
  local branch=$1 base=$2 title=$3 body=$4
  command -v az >/dev/null 2>&1 || { echo "chief-pr-provider-azuredevops: az is required" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "chief-pr-provider-azuredevops: jq is required" >&2; return 1; }
  _chief_ado_parse_remote || return 1
  local json id
  json=$(az repos pr create --organization "https://dev.azure.com/$_CHIEF_ADO_ORG" \
    --project "$_CHIEF_ADO_PROJECT" --repository "$_CHIEF_ADO_REPO" \
    --source-branch "$branch" --target-branch "$base" \
    --title "$title" --description "$body" --output json) || return 1
  id=$(printf '%s' "$json" | jq -r '.pullRequestId')
  [ -n "$id" ] && [ "$id" != "null" ] || { echo "chief-pr-provider-azuredevops: no pullRequestId in az output" >&2; return 1; }
  printf 'https://dev.azure.com/%s/%s/_git/%s/pullrequest/%s\n' "$_CHIEF_ADO_ORG" "$_CHIEF_ADO_PROJECT" "$_CHIEF_ADO_REPO" "$id"
}

pr_state() {
  local url=$1
  command -v az >/dev/null 2>&1 || { echo "chief-pr-provider-azuredevops: az is required" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "chief-pr-provider-azuredevops: jq is required" >&2; return 1; }
  _chief_ado_parse_url "$url" || return 1
  local json status draft merge_status
  json=$(az repos pr show --organization "https://dev.azure.com/$_CHIEF_ADO_ORG" --id "$_CHIEF_ADO_ID" --output json) || return 1
  status=$(printf '%s' "$json" | jq -r '.status')
  [ "$status" = "active" ] || { echo "status: $status"; return 0; }
  draft=$(printf '%s' "$json" | jq -r '.isDraft')
  merge_status=$(printf '%s' "$json" | jq -r '.mergeStatus')
  [ "$draft" = "true" ] && echo "draft: still a draft PR"
  [ "$merge_status" = "succeeded" ] || echo "mergeStatus: $merge_status"
  local policies blocking
  policies=$(az repos pr policy list --organization "https://dev.azure.com/$_CHIEF_ADO_ORG" --id "$_CHIEF_ADO_ID" --output json) || return 0
  blocking=$(printf '%s' "$policies" | jq -r '.[]? | select(.status=="rejected" or .status=="queued" or .status=="running") | "\(.configuration.type.displayName // "policy") \(.status)"')
  [ -z "$blocking" ] || printf '%s\n' "$blocking" | while IFS= read -r line; do echo "policy: $line"; done
  return 0
}

pr_review() {
  local url=$1 verdict=$2 body=$3
  command -v az >/dev/null 2>&1 || { echo "chief-pr-provider-azuredevops: az is required" >&2; return 1; }
  _chief_ado_parse_url "$url" || return 1
  case "$verdict" in
    comment|request-changes) ;;
    *) echo "chief-pr-provider-azuredevops: unknown verdict '$verdict'" >&2; return 1 ;;
  esac
  az repos pr thread create --organization "https://dev.azure.com/$_CHIEF_ADO_ORG" --id "$_CHIEF_ADO_ID" \
    --comment "$body" --status active
}

pr_review_line() {
  local url=$1 file=$2 line=$3 body=$4
  command -v az >/dev/null 2>&1 || { echo "chief-pr-provider-azuredevops: az is required" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "chief-pr-provider-azuredevops: jq is required" >&2; return 1; }
  _chief_ado_parse_url "$url" || return 1
  local json repo_id payload
  json=$(az repos pr show --organization "https://dev.azure.com/$_CHIEF_ADO_ORG" --id "$_CHIEF_ADO_ID" --output json) \
    || { echo "chief-pr-provider-azuredevops: could not read PR state for $url" >&2; return 1; }
  repo_id=$(printf '%s' "$json" | jq -r '.repository.id')
  [ -n "$repo_id" ] && [ "$repo_id" != "null" ] || { echo "chief-pr-provider-azuredevops: could not read repository id for $url" >&2; return 1; }
  payload=$(jq -nc --arg body "$body" --arg path "/$file" --argjson line "$line" '{
    comments: [{parentCommentId: 0, content: $body, commentType: 1}],
    status: 1,
    threadContext: {filePath: $path, rightFileStart: {line: $line, offset: 1}, rightFileEnd: {line: $line, offset: 1}}
  }')
  az rest --method post \
    --uri "https://dev.azure.com/$_CHIEF_ADO_ORG/$_CHIEF_ADO_PROJECT/_apis/git/repositories/$repo_id/pullRequests/$_CHIEF_ADO_ID/threads?api-version=7.0" \
    --body "$payload" >/dev/null
}

pr_approve() {
  local url=$1
  command -v az >/dev/null 2>&1 || { echo "chief-pr-provider-azuredevops: az is required" >&2; return 1; }
  _chief_ado_parse_url "$url" || return 1
  az repos pr set-vote --organization "https://dev.azure.com/$_CHIEF_ADO_ORG" --id "$_CHIEF_ADO_ID" --vote approve
}

pr_merge() {
  local url=$1
  shift
  command -v az >/dev/null 2>&1 || { echo "chief-pr-provider-azuredevops: az is required" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "chief-pr-provider-azuredevops: jq is required" >&2; return 1; }
  _chief_ado_parse_url "$url" || return 1
  local squash=false
  case "${1:-}" in
    --squash) squash=true ;;
    --merge|"") squash=false ;;
    --rebase) echo "chief-pr-provider-azuredevops: --rebase is not supported by Azure DevOps (use --squash or the default merge)" >&2; return 1 ;;
    *) echo "chief-pr-provider-azuredevops: unknown merge method '$1'" >&2; return 1 ;;
  esac
  local json status draft merge_status
  json=$(az repos pr show --organization "https://dev.azure.com/$_CHIEF_ADO_ORG" --id "$_CHIEF_ADO_ID" --output json) \
    || { echo "chief-pr-provider-azuredevops: could not read PR state for $url" >&2; return 1; }
  status=$(printf '%s' "$json" | jq -r '.status')
  draft=$(printf '%s' "$json" | jq -r '.isDraft')
  merge_status=$(printf '%s' "$json" | jq -r '.mergeStatus')
  [ "$status" = "active" ] || { echo "chief-pr-provider-azuredevops: PR is $status, not active" >&2; return 1; }
  [ "$draft" = "false" ] || { echo "chief-pr-provider-azuredevops: PR is still a draft" >&2; return 1; }
  [ "$merge_status" = "succeeded" ] || { echo "chief-pr-provider-azuredevops: PR is not mergeable (reported: $merge_status)" >&2; return 1; }
  local policies blocking
  policies=$(az repos pr policy list --organization "https://dev.azure.com/$_CHIEF_ADO_ORG" --id "$_CHIEF_ADO_ID" --output json) \
    || { echo "chief-pr-provider-azuredevops: could not read PR policy state for $url" >&2; return 1; }
  blocking=$(printf '%s' "$policies" | jq -r '.[]? | select(.status=="rejected" or .status=="queued" or .status=="running") | "\(.configuration.type.displayName // "policy") \(.status)"')
  [ -z "$blocking" ] || { echo "chief-pr-provider-azuredevops: PR has blocking policies: $blocking" >&2; return 1; }
  az repos pr update --organization "https://dev.azure.com/$_CHIEF_ADO_ORG" --id "$_CHIEF_ADO_ID" \
    --status completed --squash "$squash"
}
