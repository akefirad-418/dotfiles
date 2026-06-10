#!/usr/bin/env bash
# Tier 3 (vendor installer): AWS CLI v2. There is no v2 apt package; AWS ships
# an official installer that supports a sudo-free install into a writable
# prefix (-i/-b). Linux-only — gated in via .chezmoiignore.
#
# Pin the version here; bumping it changes this file's hash and re-triggers
# run_onchange. 00-install provides the required `unzip`.
set -euo pipefail

version="2.35.1"
prefix="$HOME/.local/aws-cli"   # install dir (-i)
bindir="$HOME/.local/bin"       # symlink dir (-b), already on PATH

case "$(uname -m)" in
  x86_64|amd64)  arch="x86_64" ;;
  aarch64|arm64) arch="aarch64" ;;
  *) echo "❌ unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

# No-op if the pinned version is already installed.
if [[ -x "$bindir/aws" ]] && "$bindir/aws" --version 2>&1 | grep -qF "aws-cli/$version "; then
  echo "✅ aws-cli $version already installed."
  exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}-${version}.zip" -o "$tmp/awscliv2.zip"
unzip -q -u "$tmp/awscliv2.zip" -d "$tmp"

# --update is required when a prior install already exists in $prefix.
update=()
[[ -d "$prefix" ]] && update=(--update)
"$tmp/aws/install" -i "$prefix" -b "$bindir" "${update[@]}"

"$bindir/aws" --version
