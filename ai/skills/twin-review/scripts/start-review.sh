#!/usr/bin/env bash
# usage: start-review.sh <pr> <author-worktree-path> <author-session-id> <orchestrator-session-id> <spec text>
# The reviewer is Codex in an Orca TERMINAL with the brief as its prompt: Orca's chat surface
# gives Codex no network, and Codex will not take instructions from a file it is pointed at.
set -euo pipefail
[ $# -eq 5 ] || { sed -n 2p "$0" >&2; exit 2; }
pr=$1 author_path=$2 author=$3 orchestrator=$4 spec=$5
model=${TWIN_REVIEW_MODEL:-gpt-6.2-sol} effort=${TWIN_REVIEW_EFFORT:-xhigh} rounds=${TWIN_REVIEW_ROUNDS:-8}
templates=$(cd "$(dirname "$0")/../templates" && pwd)
repo=$(cd "$author_path" && gh repo view --json nameWithOwner --jq .nameWithOwner)
branch=$(gh pr view "$pr" -R "$repo" --json headRefName --jq .headRefName)
git -C "$author_path" fetch -q origin "$branch"

fill() {
  python3 - "$1" "$pr" "$repo" "$branch" "$author" "$orchestrator" "$spec" "$rounds" "${2:-}" <<'PY'
import sys
text = open(sys.argv[1]).read()
keys = ["PR", "REPO", "BRANCH", "AUTHOR_SESSION", "ORCHESTRATOR_SESSION", "SPEC", "ROUND_CAP", "REVIEWER_ADDRESS"]
for key, value in zip(keys, sys.argv[2:]):
    text = text.replace("{{" + key + "}}", value)
print(text)
PY
}

created=$(orca worktree create --name "gh-$pr-review" --parent-worktree "path:$author_path" \
  --base-branch "origin/$branch" --pr "$pr" --json)
path=$(printf '%s' "$created" | python3 -c "import json,sys; r=json.load(sys.stdin)['result']; print(r.get('path') or r['worktree']['path'])")
mkdir -p "$path/.scratch"
fill "$templates/reviewer-brief.md" > "$path/.scratch/review-brief.md"
cat > "$path/.scratch/launch-reviewer.sh" <<SH
#!/usr/bin/env bash
cd "\$(dirname "\$0")/.." && exec codex -m "$model" -c model_reasoning_effort="$effort" --approve-for-me \\
  -c sandbox_workspace_write.network_access=true "\$(cat .scratch/review-brief.md)"
SH
chmod +x "$path/.scratch/launch-reviewer.sh"
terminal=$(orca terminal create --worktree "path:$path" --title "Review PR #$pr" \
  --command "./.scratch/launch-reviewer.sh" --json \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['terminal']['handle'])")
echo "reviewer terminal: $terminal"
orca orchestration send --to "orca_session_id:$author" --subject "PR #$pr: review loop with the reviewer twin" \
  --body "$(fill "$templates/author-loop.md" "$terminal")" --json \
  | python3 -c "import json,sys; print('author told:', json.load(sys.stdin).get('ok'))"
