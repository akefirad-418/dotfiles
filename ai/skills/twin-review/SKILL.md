---
name: twin-review
description: >-
  Start and run a reviewer twin for a pull request: a Codex reviewer in an Orca terminal that
  reviews an author agent's pull request through the GitHub CLI, posts findings as inline
  comments, and loops directly with the author until it has no further comments. Use when the
  user says "twin review", "reviewer twin", "review loop", "spin up a reviewer", "have codex
  review this PR", "review the pull request in a loop", or asks for an author and a reviewer
  agent to work a pull request between themselves. Needs the `orca`, `codex` and `gh` CLIs.
---

# Twin review

Two agents work one pull request without a human relaying messages. The **author** (the agent
that wrote the change, in its own Orca worktree) and the **reviewer** (Codex, in a child
worktree checked out at the pull request's head) take turns until the reviewer posts
"No further comments at <sha>". You are the **orchestrator**: you start the loop, settle what
they escalate, and report the result. Nobody in the loop merges, closes or approves.

## Who does what

| | Reviewer | Author |
| --- | --- | --- |
| Reads the pull request through `gh` | yes | yes |
| Posts findings as inline comments, one review per round | yes | no |
| Changes code, commits, pushes | never | yes |
| Runs tests, builds, linters, type checks, any gate | **never** | yes, before every push |
| Waits for, polls or reads CI | **never** | yes, owns it |
| Replies on every thread | verifies or answers | what changed and the commit, or why not |

The reviewer judges by reading: the diff, whole files at the head, their callers, the
specification, the service's documentation. When a finding rests on behaviour only a run could
show, it says what the author must run and what result would satisfy it. This keeps a round
to minutes and keeps one owner for "is it green".

## Start it

Preconditions: the author's work is on an open pull request, the author's chat is still alive,
the repository is added to Orca (`orca repo add --path <checkout>`), and `gh auth status` is good
on this machine. The author's path may be an Orca worktree or any checkout of the repository. Opening the pull request
is the user's call unless they already asked for the loop.

```bash
scripts/start-review.sh <pr-number> <author-worktree-path> <author-session-id> <your-session-id> "<what the pull request must satisfy>"
```

- Session ids: `orca agent list --json`, field `orcaSessionId`. Yours is the working row for
  your own worktree.
- The specification argument is the reviewer's whole idea of "correct": name the issue or
  design document, the acceptance checks, and what is out of scope.
- Environment: `TWIN_REVIEW_MODEL` (default `gpt-6.2-sol`), `TWIN_REVIEW_EFFORT` (default
  `xhigh`), `TWIN_REVIEW_ROUNDS` (default `8`).

The script creates the reviewer's worktree at the pull request's head, starts Codex in an Orca
terminal with the brief as its prompt, prints the terminal handle, and sends the author its
side of the loop. Then check the reviewer's first output:

```bash
orca terminal read --terminal <handle>
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 600000
```

Its first action is `gh auth status` and `gh pr view`. If either fails it stops and says so;
fix that before anything else, because a reviewer without GitHub reviews only the local tree
and looks thorough while doing it.

## What goes wrong, and why the script is shaped this way

1. **Codex in an Orca chat cannot reach GitHub.** The chat surface runs Codex in a sandbox
   with no network and offers no flag for it, so every `gh` call fails with "error connecting
   to api.github.com". The reviewer must be Codex in a **terminal**, launched with
   `-c sandbox_workspace_write.network_access=true` for that launch only. Never write that
   setting into `~/.codex/config.toml`. It widens the sandbox on the user's machine: a request
   for a reviewer that posts through the GitHub CLI is the authorization; without one, ask.
2. **Codex refuses a brief it is told to read from a file**, treating file content as data,
   not instructions. The brief has to be the prompt itself, which is why the launcher passes
   `"$(cat brief)"`.
3. **Codex stops at its folder-trust prompt in a repository it has not seen.** The trust applies
   to the whole repository root and persists, so it is the user's to answer in the terminal;
   the reviewer does nothing until then. Do not answer it for them.
4. **A model the account does not offer loses the first turn silently.** Read the terminal
   after launch; if the model was rejected, set `TWIN_REVIEW_MODEL` and start again.
5. **Addresses differ by surface.** The author reaches the reviewer by its terminal handle
   (`--to term_...`); the reviewer reaches the author and you by `orca_session_id:<id>`.
6. **The account cannot approve its own pull request**, so the end of the loop is a review of
   kind `COMMENT` whose body is "No further comments at <sha>."
7. **GitHub creates no pull-request CI run while the pull request conflicts with its base.**
   If CI never starts after a push, the author merges the base branch in; that is the author's
   job too.

## Your part while it runs

- Messages reach you when the loop ends or something is escalated: a finding that would change
  an approved design, the same disagreement twice, or the round cap. Decide it, post the
  decision on the thread, and tell both.
- Do not relay ordinary rounds; they talk to each other.
- When the reviewer reports "review complete", check that every top-level thread has a reply
  and that the author reports CI green on the final head, then tell the user. Merging is
  theirs.

## Files

- `scripts/start-review.sh`: creates the reviewer and tells the author.
- `templates/reviewer-brief.md`: the reviewer's prompt.
- `templates/author-loop.md`: the message the author receives.
