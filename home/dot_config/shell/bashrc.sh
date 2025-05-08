# bash interactive niceties (owned by chezmoi; sourced from ~/.bashrc via the
# managed block). bash-specific (uses shopt); only ~/.bashrc sources it.
case $- in
  *i*)
    HISTCONTROL=ignoreboth
    HISTSIZE=10000
    HISTFILESIZE=20000
    HISTIGNORE='cd *:kill *:g *:l:ls:ll:la:pwd:exit:exit!'
    shopt -s histappend checkwinsize 2>/dev/null
    ;;
esac
