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

Everything committed and pushed, then from your checkout:

```bash
<this skill's directory>/scripts/start-review.sh "<what the pull request must satisfy>" [escalation-session-id]
```

- The specification is the reviewer's whole idea of "correct": name the issue or design, the
  acceptance checks, and what is out of scope.
- Escalations and the final "review complete" go to the session you name, normally whoever
  dispatched you (`orca_session_id` without the prefix). Without one they come to you, and you
  bring them to the user.
- The script finds the repository, the pull request, the branch and your session
  (`ORCA_AGENT_SESSION_ID`) itself. Environment: `TWIN_REVIEW_MODEL` (default `gpt-6.2-sol`),
  `TWIN_REVIEW_EFFORT` (default `xhigh`), `TWIN_REVIEW_ROUNDS` (default `8`).

It prints the reviewer's terminal handle. Check its first output:

```bash
orca terminal read --terminal <handle>
```

Its first action is `gh auth status` and `gh pr view`; if either fails it stops and says so.
Fix that first: a reviewer without GitHub reviews only the local tree and looks thorough doing it.

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
   brief is passed as the prompt itself.
3. **Codex stops at a folder-trust prompt in a repository it has not seen.** The trust covers the
   repository root and persists, so it is the user's to answer in the terminal. Tell them; do not
   answer it.
4. **A model the account does not offer loses the first turn silently.** Read the terminal after
   launch; if the model was rejected, set `TWIN_REVIEW_MODEL` and start again.
5. **Addresses differ by surface.** You reach the reviewer by its terminal handle (`term_...`); it
   reaches you by `orca_session_id:<id>`.
6. **The account cannot approve its own pull request**, so the loop ends with a review of kind
   `COMMENT` whose body is "No further comments at <sha>."
7. **The repository must be added to Orca** (`orca repo add --path <checkout>`) or the reviewer's
   worktree cannot be created.

## Files

- `scripts/start-review.sh`: creates the reviewer's worktree and starts it.
- `templates/reviewer-brief.md`: the reviewer's prompt.
