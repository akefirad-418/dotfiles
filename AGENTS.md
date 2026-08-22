# AGENTS.md

Agent-facing configuration for this repo. `CLAUDE.md` is a symlink to this file.

## Agent skills

### Issue tracker

Issues are GitHub issues, but this is a multi-repo workspace: each submodule
maps to its own GitHub repo, so pick the target repo before filing. External
PRs are not triaged. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical default vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Multi-context, no central map: each submodule/repo carries its own `CONTEXT.md`
at its root. See `docs/agents/domain.md`.
