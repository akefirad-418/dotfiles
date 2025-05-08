#!/usr/bin/env bash

set -eufo pipefail


ZDOTDIR_PATH="$HOME/.config/zsh"

mkdir -p "$ZDOTDIR_PATH"
ln -sf "$ZDOTDIR_PATH/.zshenv" "$HOME/.zshenv"

# Move any pre-existing zsh config out of the way so the chezmoi-managed
# files in $ZDOTDIR own the shell. Only act on real files (not the symlinks
# we just created, and not missing files on a fresh box).
function _stash_if_present() {
  local src="$1" dst="$2"
  if [[ -e "$src" && ! -L "$src" ]]; then
    mv -f "$src" "$dst"
  fi
}

_stash_if_present "$HOME/.zprofile"  "$ZDOTDIR_PATH/.zprofile.bak"
_stash_if_present "$HOME/.zshrc"     "$ZDOTDIR_PATH/.zshrc.bak"
_stash_if_present "$HOME/.oh-my-zsh" "$ZDOTDIR_PATH/.oh-my-zsh.bak"
rm -f "$HOME/.zsh_history"
