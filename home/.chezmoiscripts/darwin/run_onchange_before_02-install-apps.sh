#!/usr/bin/env bash
# macOS apps shipped as a GitHub-release .dmg or .app.zip (no usable CLI binary;
# prefer the release over a cask). Download → install into ~/Applications. Personal
# + GUI only ($CLAWBOT from scriptEnv; $GUI detected at runtime). Idempotent: pass a
# VERSION to pin/upgrade via CFBundleShortVersionString, or "" for an existence-only
# check. Add an app: append an install_dmg / install_zip line at the bottom.
set -euo pipefail

# GUI is environmental — detect at runtime (not baked). Explicit GUI in env wins.
case "${GUI:-}" in
  1|true|yes) GUI=true ;;
  0|false|no) GUI=false ;;
  *) if [ "$(uname)" = Darwin ] || [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then GUI=true; else GUI=false; fi ;;
esac

if [ -n "${CLAWBOT:-}" ] || [ "$GUI" != true ]; then
  echo "apps: not a personal GUI machine — skipping."
  exit 0
fi

apps_dir="$HOME/Applications"
mkdir -p "$apps_dir"

# _installed NAME VERSION -> 0 if NAME.app is present (and matches VERSION if given).
function _installed() {
  local app="$apps_dir/$1.app"
  [[ -d "$app" ]] || return 1
  [[ -z "$2" ]] && return 0
  [[ "$(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null)" == "$2" ]]
}

# install_dmg NAME VERSION URL — mount a .dmg, copy the first .app out, detach.
function install_dmg() {
  local name="$1" version="$2" url="$3" tmp dmg mount src
  if _installed "$name" "$version"; then echo "✅ $name${version:+ $version} already installed."; return 0; fi
  echo "💿 Installing $name${version:+ $version}…"
  tmp="$(mktemp -d)"; dmg="$tmp/$name.dmg"
  curl -fsSL "$url" -o "$dmg"
  mount="$(hdiutil attach "$dmg" -nobrowse -readonly | sed -nE 's#.*(/Volumes/.*)$#\1#p' | tail -1)"
  if [[ -z "$mount" ]]; then echo "❌ $name: could not mount dmg" >&2; rm -rf "$tmp"; return 1; fi
  src="$(find "$mount" -maxdepth 1 -name '*.app' -print -quit)"
  if [[ -n "$src" ]]; then rm -rf "$apps_dir/$name.app"; cp -R "$src" "$apps_dir/"; echo "✅ $name installed."; else echo "❌ $name: no .app in dmg" >&2; fi
  hdiutil detach "$mount" -quiet || hdiutil detach "$mount" -force -quiet || true
  rm -rf "$tmp"
}

# install_zip NAME VERSION URL — unzip a .app.zip straight into ~/Applications.
function install_zip() {
  local name="$1" version="$2" url="$3" tmp
  if _installed "$name" "$version"; then echo "✅ $name${version:+ $version} already installed."; return 0; fi
  echo "💿 Installing $name${version:+ $version}…"
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/$name.zip"
  rm -rf "$apps_dir/$name.app"
  unzip -q "$tmp/$name.zip" -d "$apps_dir"
  rm -rf "$tmp"
  [[ -d "$apps_dir/$name.app" ]] && echo "✅ $name installed." || echo "❌ $name: $name.app not found in zip" >&2
}

# ── apps ──────────────────────────────────────────────────────────────────────
# (existence-only; give a VERSION to enable upgrade-on-bump)
install_zip "Scoot" "" "https://github.com/mjrusso/scoot/releases/download/v1.2/Scoot.app.zip"
install_dmg "Anki"  "" "https://github.com/ankitects/anki/releases/download/25.07.5/anki-launcher-25.07.5-mac.dmg"
