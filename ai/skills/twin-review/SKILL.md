---
name: twin-review
description: >-
  Have a Codex reviewer twin review your open pull request and loop with you until it has no
  further comments: it posts findings as inline comments through the GitHub CLI, you fix or
  reject each one, push, reply and hand back. Use when the user says "twin review", "reviewer
  twin", "review loop", "spin up a reviewer", "have codex review this PR", or asks for the pull
  request to be reviewed in a loop. Invoke it from the AUTHOR's own session once the pull request
  is open. Needs Orca and the `orca`, `codex` and `gh` CLIs.
---

# Twin review

You wrote a change and its pull request is open. This skill starts a **reviewer** (Codex, in its
own worktree at your pull request's head) and you work the pull request between you, without a
human relaying messages, until the reviewer posts "No further comments at <sha>". Nobody in the
loop merges, closes or approves; that stays with the user.

## Who does what

| | Reviewer | You, the author |
| --- | --- | --- |
| Reads the pull request through `gh` | yes | yes |
| Posts findings as inline comments, one review per round | yes | no |
| Changes code, commits, pushes | never | yes |
| Runs tests, builds, linters, type checks, any gate | **never** | yes, before every push |
| Waits for, polls or reads CI | **never** | yes, owns it |
| Replies on every thread | verifies or answers | what changed and the commit, or why not |

The reviewer judges by reading. When a finding rests on behaviour only a run could show, it says
what you must run and what result would satisfy it; you put the result in your reply.

## 1. Start the reviewer

Everything committed and pushed first. Then, from your own checkout:

```bash
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
pr=$(gh pr view --json number --jq .number)
branch=$(gh pr view --json headRefName --jq .headRefName)
top=$(git rev-parse --show-toplevel)
orca worktree create --name "gh-$pr-review" --parent-worktree "path:$top" \
  --base-branch "origin/$branch" --pr "$pr" --json
```

If that fails because your checkout is not an Orca worktree, use `--repo "path:$top" --no-parent`
instead of `--parent-worktree`. If the repository is unknown to Orca, add it first with
`orca repo add --path "$top"`. Take the new worktree's path from the JSON (`result.path` or
`result.worktree.path`); below it is `$reviewer`.

**Write the brief.** Copy `templates/reviewer-brief.md` from this skill to
`$(git -C "$reviewer" rev-parse --absolute-git-dir)/review-brief.md` (inside the git directory, so
it can never be committed), replacing every placeholder:

| Placeholder | Value |
| --- | --- |
| `{{PR}}`, `{{REPO}}`, `{{BRANCH}}` | from the commands above |
| `{{AUTHOR_SESSION}}` | `$ORCA_AGENT_SESSION_ID`, your own session |
| `{{ESCALATION_SESSION}}` | whoever dispatched you; your own session if nobody did |
| `{{SPEC}}` | what the pull request must satisfy: the issue or design, the acceptance checks, what is out of scope |
| `{{ROUND_CAP}}` | `8` unless told otherwise |

Check that no `{{` is left.

**Launch it.** This is the one command to copy exactly; see "What goes wrong" for why each part
is there:

```bash
brief=$(git -C "$reviewer" rev-parse --absolute-git-dir)/review-brief.md
orca terminal create --worktree "path:$reviewer" --title "Review PR #$pr" --json --command \
  "cd '$reviewer' && codex -m gpt-6.2-sol -c model_reasoning_effort=xhigh --approve-for-me -c sandbox_workspace_write.network_access=true \"\$(cat '$brief')\""
```

Keep the handle it returns (`result.terminal.handle`); it is how you reach the reviewer. Then read
its first output with `orca terminal read --terminal <handle>`. Its first action is
`gh auth status` and `gh pr view`; if either fails it stops and says so. Fix that first: a reviewer
without GitHub reviews only the local tree and looks thorough doing it. Use another model by
changing `-m`; if the account rejects it, the first turn is lost silently, so read the terminal.

## 2. Each round

1. The reviewer's message arrives in your chat. List EVERY top-level thread, never only new ones:
   `gh api repos/<owner>/<repo>/pulls/<n>/comments --paginate --jq '.[] | select(.in_reply_to_id == null) | "\(.id) \(.path):\(.line)\n\(.body)\n"'`
2. Decide each on its merits: fix it, or reject it with the reason. A finding that would change an
   approved design or decision is not yours: send it to the escalation session (or the user) and
   reply on the thread that it is escalated.
3. Fix in small commits in the repository's style, run every gate the repository and your brief
   name, push. Never force-push, never push elsewhere, never merge or close.
4. Reply on every thread (`gh api -X POST repos/<owner>/<repo>/pulls/<n>/comments/<id>/replies -f body=...`):
   what changed and the commit, or why not, plus the result of any run the finding asked for.
5. Hand back right after the push, without waiting for CI:
   `orca orchestration send --to <reviewer terminal handle> --subject "PR #<n> round <k> addressed at <sha>" --body "<one line per thread>"`.
   Then check CI on that head (`gh pr checks <n>`) and fix what is red before your next handback.
   If no run starts at all, the pull request conflicts with its base: merge the base in.
6. When the reviewer reports "review complete", see CI green on the final head and report: the
   rounds, what you rejected and why, the final head, the gate and CI results.

## What goes wrong, and why the script is shaped this way

1. **Codex in an Orca chat cannot reach GitHub.** The chat surface runs Codex in a sandbox with no
   network and offers no flag for it, so every `gh` call fails. The reviewer runs in a **terminal**,
   launched with `-c sandbox_workspace_write.network_access=true` for that launch only. Never write
   that into `~/.codex/config.toml`: it widens the sandbox on the user's machine, and a request for
   a reviewer that posts through the GitHub CLI authorizes it for this launch, nothing more.
2. **Codex refuses a brief it is told to read from a file**, treating file content as data. The
   brief is passed as the prompt itself, through `"$(cat ...)"`.
3. **Codex stops at a folder-trust prompt in a repository it has not seen.** The trust covers the
   repository root and persists, so it is the user's to answer in the terminal. Tell them; do not
   answer it.
4. **A model the account does not offer loses the first turn silently.** Read the terminal after
   launch; if the model was rejected, close the terminal and launch again with another `-m`.
5. **Addresses differ by surface.** You reach the reviewer by its terminal handle (`term_...`); it
   reaches you by `orca_session_id:<id>`.
6. **The account cannot approve its own pull request**, so the loop ends with a review of kind
   `COMMENT` whose body is "No further comments at <sha>."
7. **The repository must be added to Orca** (`orca repo add --path <checkout>`) or the reviewer's
   worktree cannot be created.

## Files

- `templates/reviewer-brief.md`: the reviewer's prompt, with the placeholders above.
