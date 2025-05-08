#!/usr/bin/env bash
# Personal Linux only ($CLAWBOT empty): CLI tools from the distro repos (apt).
# Mirrors darwin/01-install-packages (brew bundle). Base deps are handled in
# 00-install; bun/btop/eza come from tier-1 externals — there's no Linuxbrew.
set -euo pipefail

if [ -n "${CLAWBOT:-}" ]; then
  echo "packages: clawbot — skipping personal apt tools."
  exit 0
fi

command -v apt-get >/dev/null 2>&1 || { echo "⚠️  apt-get not found; skipping personal apt tools." >&2; exit 0; }

if [ "$(id -u)" -eq 0 ]; then sudo=""
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then sudo="sudo"
else echo "❌ need root or passwordless sudo." >&2; exit 1; fi

pkgs=(ffmpeg git-delta httpie tree shellcheck)
$sudo apt-get update -qq
$sudo apt-get install -y --no-install-recommends "${pkgs[@]}"
echo "✅ personal apt tools installed: ${pkgs[*]}"
