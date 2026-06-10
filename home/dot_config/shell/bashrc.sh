# bash interactive niceties (owned by chezmoi; sourced from ~/.bashrc).
# bash-specific (uses shopt); only ~/.bashrc sources it, so that's fine.
case $- in
  *i*)
    HISTCONTROL=ignoreboth
    HISTSIZE=10000
    HISTFILESIZE=20000
    shopt -s histappend checkwinsize 2>/dev/null
    ;;
esac
