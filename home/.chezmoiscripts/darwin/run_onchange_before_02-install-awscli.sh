#!/usr/bin/env bash
# Tier 3 (vendor installer): AWS CLI v2, sudo-free current-user install. Uses
# the official .pkg with a choices.xml that redirects the install into
# ~/.local/aws-cli, then symlinks the binaries into ~/.local/bin. macOS-only.
#
# Pin the version here; bumping it re-triggers run_onchange.
set -euo pipefail

version="2.35.1"
prefix="$HOME/.local"           # installer creates $prefix/aws-cli inside this
bindir="$HOME/.local/bin"

# No-op if the pinned version is already installed.
if [[ -x "$bindir/aws" ]] && "$bindir/aws" --version 2>&1 | grep -qF "aws-cli/$version "; then
  echo "✅ aws-cli $version already installed."
  exit 0
fi

mkdir -p "$prefix" "$bindir"   # attributeSetting folder must already exist
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2-${version}.pkg" -o "$tmp/AWSCLIV2.pkg"

cat > "$tmp/choices.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <array>
    <dict>
      <key>choiceAttribute</key>
      <string>customLocation</string>
      <key>attributeSetting</key>
      <string>$prefix</string>
      <key>choiceIdentifier</key>
      <string>default</string>
    </dict>
  </array>
</plist>
EOF

# -target CurrentUserHomeDirectory => no sudo; symlinks are not auto-created.
installer -pkg "$tmp/AWSCLIV2.pkg" \
          -target CurrentUserHomeDirectory \
          -applyChoiceChangesXML "$tmp/choices.xml"

ln -sf "$prefix/aws-cli/aws"           "$bindir/aws"
ln -sf "$prefix/aws-cli/aws_completer" "$bindir/aws_completer"

"$bindir/aws" --version
