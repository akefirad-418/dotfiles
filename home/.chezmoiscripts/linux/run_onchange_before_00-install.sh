#!/usr/bin/env bash
# Linux system prep (apt): base CLI prerequisites every machine needs before the
# package/installer steps. Mirrors darwin/00-install (which bootstraps Homebrew).
#   unzip      — AWS CLI installer (03)
#   curl/wget  — chezmoi externals + claude/opencode installers (04/05)
#   xz-utils   — xz-compressed tarballs
# Runs on all roles (clawbot + personal); no-op (and no sudo) when already present.
set -euo pipefail

pkgs=(git curl wget ca-certificates unzip xz-utils)

need=0
for c in git curl wget unzip xz; do command -v "$c" >/dev/null 2>&1 || need=1; done
if [ "$need" -eq 0 ]; then
  echo "✅ base deps present."
  exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "⚠️  apt-get not found; install manually: ${pkgs[*]}" >&2
  exit 0
fi

if [ "$(id -u)" -eq 0 ]; then sudo=""
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then sudo="sudo"
else echo "❌ need root or passwordless sudo to install: ${pkgs[*]}" >&2; exit 1; fi

$sudo apt-get update -qq
$sudo apt-get install -y --no-install-recommends "${pkgs[@]}"
echo "✅ base deps installed."
