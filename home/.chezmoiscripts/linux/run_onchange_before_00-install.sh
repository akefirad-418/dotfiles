#!/usr/bin/env bash
# Linux env prep: ensure base deps. Tier-1 release binaries cover the CLI tools
# (rg/fd/jq/gh), so there's no package manager step for those and no linuxbrew.
# Linux-only — gated in via .chezmoiignore.
set -euo pipefail

pkgs=(git curl wget ca-certificates unzip)   # unzip: required by the AWS CLI installer (02)

# Skip entirely if the binaries are already present (no sudo when it's a no-op).
need=0
for c in git curl wget unzip; do command -v "$c" >/dev/null 2>&1 || need=1; done
if [[ "$need" -eq 0 ]]; then
  echo "✅ Base deps present."
  exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "⚠️  apt-get not found; install manually: ${pkgs[*]}" >&2
  exit 0
fi

if [[ "$(id -u)" -eq 0 ]]; then
  sudo=""
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  sudo="sudo"   # -n: never prompt; avoids hanging without a tty
else
  echo "❌ Need root or passwordless sudo to install: ${pkgs[*]}" >&2
  exit 1
fi

$sudo apt-get update -qq
$sudo apt-get install -y --no-install-recommends "${pkgs[@]}"
echo "✅ Base deps installed."
