alias c='cursor'
alias d='docker'
alias k='kubectl'

alias cd='z'

alias ls='eza --icons=auto'
alias l='eza --icons=auto -l'
alias la='eza --icons=auto -a'
alias ll='eza --icons=auto -la'

alias g='git'
alias gito='git checkout'
alias gitp='git push'
alias gits='git status'
alias main='git checkout main && git pull --all'

alias tf='terraform'
alias lzg='lazygit'
alias lzdc='lazydocker'
alias npr='npm run'

alias py=python3
alias python=python3

alias argo='argocd'
alias istio='istioctl'
alias redis='redis-cli'
alias lapce='open -a Lapce'

alias awsso='aws-sso'
alias asp='aws-sso-profile'
alias asc='aws-sso-clear'

alias https='http ${@:1:$((${#@}-1))} https://${@: -1}'

alias mvn='mvn-or-mvnw'
alias gradle='gradle-or-gradlew'

alias geoip='curl http://ip-api.com/line/$1'
alias myip='curl -s http://ipecho.net/plain; echo'
alias github='curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/$1'
