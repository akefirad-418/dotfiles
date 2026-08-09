#!/usr/bin/env bash
# Registers MCP servers with Claude Code at USER scope, i.e. into ~/.claude.json —
# which is Claude Code's own state file, not a chezmoi-managed target (same
# arrangement as the devcontainer bootstrap in linux/04-install-claude-code.sh).
# Both OSes need this, so the script lives at the .chezmoiscripts root rather than
# under darwin/ or linux/.
#
# ast-grep MCP: gives Claude Code structural (AST) search — dump_syntax_tree,
# test_match_code_rule, find_code, find_code_by_rule. It shells out to the
# `ast-grep` binary (tier-1 external) and is itself Python run through `uvx`
# (also tier-1), so nothing extra is installed eagerly.
#
# Two upstream quirks are pinned around here:
#   - the server is not published to PyPI, so it runs from a git ref;
#   - its dependency floor `mcp[cli]>=1.6.0` now resolves to mcp 2.x, which dropped
#     `mcp.server.fastmcp` — the server dies on import. `--with 'mcp[cli]<2'` holds
#     it on the 1.x line until upstream migrates.
#
# run_onchange keys on this file's contents hash, so editing the pinned ref (or
# any line here) re-registers on the next apply; flipping only a scriptEnv flag
# does not — force with:
#   chezmoi state delete-bucket --bucket=entryState && chezmoi apply
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

if [ "${INSTALL_CLAUDE_CODE:-1}" = "0" ]; then
  echo "mcp: INSTALL_CLAUDE_CODE=0 — skipping MCP registration."
  exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "⚠️  mcp: claude not on PATH — skipping MCP registration."
  exit 0
fi

AST_GREP_MCP_REF="732c339c3812a44e9111e6c3aefec64894acd58f"  # ast-grep/ast-grep-mcp main @ 2026-03-22

# `claude mcp add-json` refuses to overwrite an existing entry, so drop it first;
# remove exits non-zero when absent, which is the normal first-run path.
claude mcp remove --scope user ast-grep >/dev/null 2>&1 || true
claude mcp add-json --scope user ast-grep "$(
  cat <<EOF
{
  "type": "stdio",
  "command": "uvx",
  "args": [
    "--from", "git+https://github.com/ast-grep/ast-grep-mcp@${AST_GREP_MCP_REF}",
    "--with", "mcp[cli]<2",
    "ast-grep-server"
  ]
}
EOF
)"
