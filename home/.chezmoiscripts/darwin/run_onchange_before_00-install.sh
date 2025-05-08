#!/usr/bin/env bash
# macOS env prep: Command Line Developer Tools, Rosetta (Apple Silicon), Homebrew —
# prerequisites for the installs in 01/02/03. run_onchange: re-runs only on change.
set -eufo pipefail


function _ensure_cldt() {
  if xcode-select -p &>/dev/null; then
    echo "✅ Command Line Developer Tools present."
    return 0
  fi
  echo "❌ Command Line Developer Tools not found. Triggering install…"
  xcode-select --install || true
  open -a 'Install Command Line Developer Tools' 2>/dev/null || true
  echo "Finish the installation, then re-run \`chezmoi apply\`."
  exit 1
}


function _install_rosetta() {
  if [[ "$(uname -m)" == "arm64" ]]; then
    if ! arch -arch x86_64 uname -m >/dev/null 2>&1; then
      echo "🔎 Rosetta not installed. Installing…"
      softwareupdate --install-rosetta --agree-to-license
    else
      echo "✅ Rosetta already installed."
    fi
  fi
}


function _install_homebrew() {
  if command -v brew &>/dev/null; then
    echo "✅ Homebrew already installed."
    return 0
  fi

  echo "🍺 Homebrew not installed. Installing…"
  # Interactive: the installer prompts for sudo to create /opt/homebrew; chezmoi
  # passes the terminal through from install.sh. Don't set NONINTERACTIVE here
  # (that's for headless CI and needs passwordless sudo).
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

  if command -v brew &>/dev/null; then
    echo "✅ Homebrew installed."
  else
    echo "❌ Homebrew installation failed." >&2
    exit 1
  fi
}


_ensure_cldt
_install_rosetta
_install_homebrew
