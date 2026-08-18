#!/usr/bin/env bash
set -euo pipefail

pr_number="${1:-$(gh pr view --json number --jq '.number')}"
repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
owner="${repo%%/*}"
name="${repo#*/}"

metadata="$(gh pr view "$pr_number" --json number,url,isDraft,reviewDecision,reviews)"
query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:50){nodes{isResolved isOutdated path line comments(first:10){nodes{author{login}body url createdAt}}}}}}}'
threads="$(gh api graphql -f query="$query" -F owner="$owner" -F name="$name" -F number="$pr_number")"

jq -cn \
  --argjson metadata "$metadata" \
  --argjson threads "$threads" \
  '{
    number: $metadata.number,
    url: $metadata.url,
    draft: $metadata.isDraft,
    reviewDecision: $metadata.reviewDecision,
    reviews: [
      ($metadata.reviews // [])[]
      | select(.state == "CHANGES_REQUESTED" or ((.body // "") | length) > 0)
      | {
          author: .author.login,
          state,
          body: ((.body // "")[:1000])
        }
    ][-10:],
    unresolvedThreads: [
      ($threads.data.repository.pullRequest.reviewThreads.nodes // [])[]
      | select(.isResolved == false)
      | {
          path,
          line,
          outdated: .isOutdated,
          comments: [
            (.comments.nodes // [])[]
            | {
                author: (.author.login // "unknown"),
                body: ((.body // "")[:1000]),
                url,
                createdAt
              }
          ][-3:]
        }
    ][-20:]
  }'
