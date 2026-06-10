#!/usr/bin/env bash
# macOS GUI apps shipped as a .dmg from a GitHub release (no usable CLI binary;
# prefer the release over a cask). Download the dmg, mount it, copy the .app
# into ~/Applications (no sudo), detach. macOS-only — gated via .chezmoiignore.
# run_onchange: re-runs when this file changes (e.g. you bump a version).
#
# Add an app: append an `install_dmg NAME VERSION URL` line at the bottom.
set -euo pipefail

apps_dir="$HOME/Applications"
mkdir -p "$apps_dir"

# install_dmg NAME VERSION URL
#   NAME    = .app bundle name without extension (must match what's in the dmg)
#   VERSION = expected CFBundleShortVersionString (idempotency check)
#   URL     = direct .dmg download
function install_dmg() {
  local name="$1" version="$2" url="$3"
  local app="$apps_dir/$name.app"

  if [[ -d "$app" ]] &&
     [[ "$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null)" == "$version" ]]; then
    echo "✅ $name $version already installed."
    return 0
  fi

  echo "💿 Installing $name $version…"
  local tmp dmg mount src
  tmp="$(mktemp -d)"
  dmg="$tmp/$name.dmg"
  curl -fsSL "$url" -o "$dmg"

  # Mount read-only, no Finder window; parse the /Volumes mountpoint (it may
  # contain spaces) from the attach output.
  mount="$(hdiutil attach "$dmg" -nobrowse -readonly | sed -nE 's#.*(/Volumes/.*)$#\1#p' | tail -1)"
  if [[ -z "$mount" ]]; then
    echo "❌ $name: could not mount dmg" >&2
    rm -rf "$tmp"
    return 1
  fi

  # Copy the first .app out of the image (skips any "Applications" symlink).
  src="$(find "$mount" -maxdepth 1 -name '*.app' -print -quit)"
  if [[ -n "$src" ]]; then
    rm -rf "$app"
    cp -R "$src" "$apps_dir/"
    echo "✅ $name installed to $apps_dir/"
  else
    echo "❌ $name: no .app found in dmg" >&2
  fi

  hdiutil detach "$mount" -quiet || hdiutil detach "$mount" -force -quiet || true
  rm -rf "$tmp"
}

# No dmg-only apps configured (VoiceInk is installed via cask in 01). This
# stays as the mechanism for apps that ship ONLY a .dmg / aren't in Homebrew.
# Example:
# install_dmg "VoiceInk" "1.79" "https://github.com/Beingpax/VoiceInk/releases/download/v1.79/VoiceInk.dmg"
