#!/usr/bin/env bash
# usage: start-review.sh "<what the pull request must satisfy>" [escalation-session-id]
# Run by the AUTHOR, from its own checkout, once its pull request is open. The reviewer is Codex
# in an Orca TERMINAL with the brief as its prompt: Orca's chat surface gives Codex no network,
# and Codex will not take instructions from a file it is pointed at.
set -euo pipefail
[ $# -ge 1 ] && [ $# -le 2 ] || { sed -n 2p "$0" >&2; exit 2; }
spec=$1
author=${ORCA_AGENT_SESSION_ID:?run this from the author agent inside Orca}
escalate=${2:-$author}
model=${TWIN_REVIEW_MODEL:-gpt-6.2-sol} effort=${TWIN_REVIEW_EFFORT:-xhigh} rounds=${TWIN_REVIEW_ROUNDS:-8}
templates=$(cd "$(dirname "$0")/../templates" && pwd)
top=$(git rev-parse --show-toplevel)
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
pr=$(gh pr view --json number --jq .number) || { echo "no open pull request for this branch" >&2; exit 1; }
branch=$(gh pr view "$pr" --json headRefName --jq .headRefName)
[ -z "$(git status --porcelain)" ] || { echo "commit and push before starting the review" >&2; exit 1; }
git fetch -q origin "$branch"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$branch")" ] || { echo "push your branch before starting the review" >&2; exit 1; }

brief=$(python3 - "$templates/reviewer-brief.md" "$pr" "$repo" "$branch" "$author" "$escalate" "$spec" "$rounds" <<'PY'
import sys
text = open(sys.argv[1]).read()
keys = ["PR", "REPO", "BRANCH", "AUTHOR_SESSION", "ESCALATION_SESSION", "SPEC", "ROUND_CAP"]
for key, value in zip(keys, sys.argv[2:]):
    text = text.replace("{{" + key + "}}", value)
print(text)
PY
)

# A child of the author's worktree when Orca manages it; otherwise a worktree of the same repo.
create() { orca worktree create --name "gh-$pr-review" "$@" --base-branch "origin/$branch" --pr "$pr" --json || true; }
worktree_path() { python3 -c "import json,sys; r=json.load(sys.stdin).get('result') or {}; print(r.get('path') or (r.get('worktree') or {}).get('path') or '')" 2>/dev/null || true; }
path=$(create --parent-worktree "path:$top" 2>/dev/null | worktree_path)
[ -n "$path" ] || path=$(create --repo "path:$top" --no-parent | worktree_path)
[ -n "$path" ] || { echo "orca could not create the reviewer's worktree; is the repository added to Orca (orca repo add --path $top)?" >&2; exit 1; }

mkdir -p "$path/.scratch"
printf '%s\n' "$brief" > "$path/.scratch/review-brief.md"
cat > "$path/.scratch/launch-reviewer.sh" <<SH
#!/usr/bin/env bash
cd "\$(dirname "\$0")/.." && exec codex -m "$model" -c model_reasoning_effort="$effort" --approve-for-me \\
  -c sandbox_workspace_write.network_access=true "\$(cat .scratch/review-brief.md)"
SH
chmod +x "$path/.scratch/launch-reviewer.sh"
orca terminal create --worktree "path:$path" --title "Review PR #$pr" \
  --command "./.scratch/launch-reviewer.sh" --json \
  | python3 -c "import json,sys; print('reviewer terminal:', json.load(sys.stdin)['result']['terminal']['handle'])"
