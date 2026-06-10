# POSIX-sh environment. Sourced by ~/.bashrc + ~/.profile (bash) and by
# ~/.config/zsh/.zshenv (zsh, the ZDOTDIR location — reached on a fresh machine
# via the ~/.zshenv symlink the configure script creates). Keep it shell-
# agnostic so login, interactive, sh, and `zsh -c` all get a sane PATH.

# Tool binaries managed by chezmoi land here. Prepend once.
case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) ;;
  *) PATH="${HOME}/.local/bin:${PATH}" ; export PATH ;;
esac

export EDITOR="${EDITOR:-vi}"
# Agents run non-interactively; avoid a pager that waits for a key.
export PAGER="${PAGER:-cat}"

# fnm (Node version manager): put the active node on PATH. Guarded so it's a
# no-op until fnm is installed (the PATH prepend above makes it discoverable).
# --shell bash emits portable POSIX `export`s, safe in bash, zsh, and sh; no
# --use-on-cd (that needs shell-specific hooks unfit for this shared file).
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --shell bash)"
fi
