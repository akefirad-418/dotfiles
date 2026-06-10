#!/usr/bin/env bash

set -eufo pipefail


function _test_full_disk_access() {
  if ! ls ~/Library/Mail &>/dev/null; then
    echo "❌ Terminal does not have full disk access."
    echo "Please grant full disk access to Terminal in System Preferences > Privacy & Security > Full Disk Access"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    return 1
  fi
}

ln -sf "$HOME/.config/zsh/.zshenv" "$HOME/.zshenv"

_test_full_disk_access
