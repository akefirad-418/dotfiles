#!/usr/bin/env bash
# macOS env prep: ensure Homebrew is installed (prerequisite for the cask
# installs in 01-install-packages). macOS-only — gated in via .chezmoiignore.
# run_onchange: re-runs only when this file's contents change.
set -euo pipefail

if command -v brew >/dev/null 2>&1; then
  echo "✅ Homebrew already installed."
  exit 0
fi

echo "🍺 Homebrew not found. Installing…"
# Interactive: the installer prompts for your sudo password to create
# /opt/homebrew. chezmoi passes the terminal through from install.sh, so the
# prompt reaches you. (Don't set NONINTERACTIVE here — that's for headless
# CI/Docker and would instead require passwordless sudo. Homebrew also refuses
# to run as root, so we never sudo the installer itself.)
/bin/bash -c \
  "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# chezmoi runs each script in a fresh process; put brew on PATH for this one.
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"

if ! command -v brew >/dev/null 2>&1; then
  echo "❌ Homebrew installation failed." >&2
  exit 1
fi
echo "✅ Homebrew installed."
