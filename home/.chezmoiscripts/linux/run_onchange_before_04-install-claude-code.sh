#!/usr/bin/env bash
# Tier 3 (vendor installer): Claude Code CLI on Linux. No apt package — Anthropic's
# official installer drops `claude` into ~/.local/bin (sudo-free). macOS installs it
# via the `claude-code` Homebrew cask in darwin/01-install-packages. Install-if-
# missing only: Claude Code self-updates, so nothing to pin.
#
# Skip with INSTALL_CLAUDE_CODE=0 (resolved once at init, delivered via scriptEnv;
# see .chezmoi.yaml.tmpl). Flipping that flag on an existing box does NOT re-run this:
# run_onchange keys on a hash of the script's *contents* (stored as contentsSHA256 in
# chezmoi's entryState bucket), unchanged when only the scriptEnv flag flips — and
# `chezmoi apply --force` only suppresses prompts, it does NOT re-run. Force it with:
#   chezmoi state delete-bucket --bucket=entryState && chezmoi apply
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"   # jq (devcontainer bootstrap below) lives here

if [ "${INSTALL_CLAUDE_CODE:-1}" = "0" ]; then
  echo "claude: INSTALL_CLAUDE_CODE=0 — skipping install."
  exit 0
fi

if command -v claude >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/claude" ]]; then
  echo "✅ Claude Code already installed."
else
  echo "🤖 Installing Claude Code…"
  curl -fsSL https://claude.ai/install.sh | bash -s stable
  "$HOME/.local/bin/claude" --version || true
fi

# Devcontainer-only: seed Claude settings and skip onboarding so the CLI is usable
# immediately when the container comes up.
if [[ "${DEVCONTAINER:-}" == "1" ]]; then
  WORKSPACE=$(find /workspaces -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1 || true)
  if [[ -z "$WORKSPACE" ]]; then
    echo "⚠️  Skipping claude devcontainer bootstrap: no /workspaces/* found."
    exit 0
  fi

  mkdir -p "$HOME/.claude"
  if [[ ! -e "$HOME/.claude/settings.json" ]]; then
    cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "theme": "dark",
  "skipAutoPermissionPrompt": true,
  "permissions": {
    "defaultMode": "auto"
  }
}
EOF
  fi

  [[ -e "$HOME/.claude.json" ]] || echo '{}' > "$HOME/.claude.json"

  tmp=$(mktemp)
  jq --arg ws "$WORKSPACE" '
    .hasCompletedOnboarding = true
    | .lastOnboardingVersion = "999.0.0"
    | .hasIdeOnboardingBeenShown.vscode = true
    | .projects[$ws].hasTrustDialogAccepted = true
    | .projects[$ws].hasCompletedProjectOnboarding = true
  ' "$HOME/.claude.json" > "$tmp" && mv "$tmp" "$HOME/.claude.json"

  echo "✅ Claude devcontainer bootstrap applied for $WORKSPACE."
fi
