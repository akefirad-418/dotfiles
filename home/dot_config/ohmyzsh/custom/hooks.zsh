function _exclude_commands_from_history() {
  emulate -L zsh
  if ! [[ "$1" =~ "(^ |^g |^kill |^cd |^l$|^ls$|^ll$|^pwd$|^exit$|^exit!$)" ]] ; then
      print -sr -- "${1%%$'\n'}"
      fc -p
  else
      return 1
  fi
}

add-zsh-hook zshaddhistory _exclude_commands_from_history
