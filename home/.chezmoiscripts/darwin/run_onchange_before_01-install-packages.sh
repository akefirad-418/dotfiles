#!/usr/bin/env bash
# macOS apps via `brew bundle`. Idempotent (skips already-installed). No
# --cleanup, so it never uninstalls anything not listed here. CLI tools come
# from tier-1 release binaries; this is only for things packaged as casks.
# macOS-only — gated in via .chezmoiignore.
set -euo pipefail

# 00-install put brew on PATH, but each chezmoi script runs in a fresh process.
if ! command -v brew >/dev/null 2>&1; then
  [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "❌ Homebrew not found (run 00-install first)." >&2
  exit 1
fi

brew bundle --file=/dev/stdin <<'BREWFILE'
cask "google-chrome"
cask "claude-code"
cask "cursor"
cask "voiceink"
BREWFILE
