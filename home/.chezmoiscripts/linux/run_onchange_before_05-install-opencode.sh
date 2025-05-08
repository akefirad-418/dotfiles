#!/usr/bin/env bash
# Tier 3 (vendor installer): opencode CLI on Linux. opencode.ai/install drops the
# binary into ~/.opencode/bin (sudo-free); env.sh adds that dir to PATH. macOS
# installs the `opencode` Homebrew formula in darwin/01. Install-if-missing only;
# opencode self-updates.
#
# Skip with INSTALL_OPENCODE=0 (resolved once at init, delivered via scriptEnv).
# Flipping that flag on an existing box does NOT re-run this: run_onchange keys on a
# hash of the script's contents (chezmoi's entryState bucket), unchanged when only the
# scriptEnv flag flips — and `chezmoi apply --force` only suppresses prompts. Force it
# with: chezmoi state delete-bucket --bucket=entryState && chezmoi apply
set -euo pipefail

if [ "${INSTALL_OPENCODE:-1}" = "0" ]; then
  echo "opencode: INSTALL_OPENCODE=0 — skipping install."
  exit 0
fi

if command -v opencode >/dev/null 2>&1 || [ -x "$HOME/.opencode/bin/opencode" ]; then
  echo "✅ opencode already installed."
  exit 0
fi

# Pre-add the install dir to PATH so the installer detects it and skips editing
# shell rc files — env.sh owns PATH; the managed bashrc/profile block is the
# single source of truth for it.
export PATH="$HOME/.opencode/bin:$PATH"
echo "📦 Installing opencode…"
curl -fsSL https://opencode.ai/install | bash
"$HOME/.opencode/bin/opencode" --version || true
