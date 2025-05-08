# POSIX rewrites of the helpers that used to live in
# ohmyzsh/custom/functions.zsh. Hyphenated function names work in both
# bash and zsh (not in dash, which we don't target).

confirm() {
  prompt=${1:-"Are you sure?"}
  printf '%s ' "$prompt"
  read -r answer
  case "$answer" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

mvn-or-mvnw() {
  dir="$PWD"
  while [ ! -x "$dir/mvnw" ] && [ "$dir" != "/" ]; do
    dir="$(dirname "$dir")"
  done

  if [ -x "$dir/mvnw" ]; then
    echo "Running \`$dir/mvnw\`..." >&2
    "$dir/mvnw" "$@"
    return $?
  fi

  command mvn "$@"
}

gradle-or-gradlew() {
  dir="$PWD"
  while [ ! -x "$dir/gradlew" ] && [ "$dir" != "/" ]; do
    dir="$(dirname "$dir")"
  done

  if [ -x "$dir/gradlew" ]; then
    echo "Running \`$dir/gradlew\`..." >&2
    "$dir/gradlew" "$@"
    return $?
  fi

  command gradle "$@"
}
