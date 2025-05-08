#!/usr/bin/env bash
# Test harness: build the Ubuntu image, then run install.sh inside it as a CLAWBOT
# (headless: no $DISPLAY, so .gui resolves false).
#
# Usage:
#   test/run.sh                       # build + run install.sh (host arch)
#   test/run.sh install               # same
#   test/run.sh shell                 # build + drop into an interactive zsh
#   test/run.sh bash                  # build + run install.sh, then interactive bash
#   test/run.sh verify                # build + run install.sh + the verification
#   test/run.sh reconfigure           # build + first-install + reconfigure (claude on) + verify
#   test/run.sh templates             # host-side template tests (no Docker)
#   test/run.sh build                 # build the image only
#
# Environment:
#   ARCH=amd64|arm64           target arch (default: host)
#   CLAWBOT=<non-empty>        provision as a clawbot (boolean flag; default: 1)
#   INSTALL_CLAUDE_CODE=0      skip Claude Code (passed through to the container)
#   INSTALL_OPENCODE=1         install opencode (off by default on clawbot; passed through)
#   INSTALL_HERMES=1           install Hermes (off by default; passed through)
#   GUI=1|0                    override GUI detection (passed through)

set -euo pipefail

REPO_ROOT="$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)"
DOCKERFILE="$REPO_ROOT/test/Dockerfile.linux"

host_arch="$(uname -m)"
case "$host_arch" in
  arm64|aarch64) default_arch=arm64 ;;
  x86_64|amd64)  default_arch=amd64 ;;
  *)             default_arch=amd64 ;;
esac
ARCH="${ARCH:-$default_arch}"
PLATFORM="linux/${ARCH}"
IMAGE="dotfiles-linux-test:${ARCH}"

cd "$REPO_ROOT"

cmd="${1:-install}"

# Container env: provision as a clawbot (CLAWBOT is a boolean flag; non-empty =
# yes). Forward optional switches when set.
CLAWBOT_FLAG="${CLAWBOT:-1}"
docker_env=(-e "CLAWBOT=$CLAWBOT_FLAG")
[ -n "${INSTALL_CLAUDE_CODE:-}" ] && docker_env+=(-e "INSTALL_CLAUDE_CODE=$INSTALL_CLAUDE_CODE")
[ -n "${INSTALL_OPENCODE:-}" ]    && docker_env+=(-e "INSTALL_OPENCODE=$INSTALL_OPENCODE")
[ -n "${INSTALL_HERMES:-}" ]      && docker_env+=(-e "INSTALL_HERMES=$INSTALL_HERMES")
[ -n "${GUI:-}" ]                 && docker_env+=(-e "GUI=$GUI")

build() {
  echo "==> building image $IMAGE (platform $PLATFORM)"
  docker build --platform "$PLATFORM" -t "$IMAGE" -f "$DOCKERFILE" .
}

case "$cmd" in
  templates)
    "$REPO_ROOT/test/template.sh" && "$REPO_ROOT/test/modify.sh"
    ;;
  modify)
    exec "$REPO_ROOT/test/modify.sh"
    ;;
  build)
    build
    ;;
  install)
    build
    echo "==> running install.sh in container (CLAWBOT=$CLAWBOT_FLAG)"
    docker run --rm --platform "$PLATFORM" "${docker_env[@]}" -i "$IMAGE"
    ;;
  shell)
    build
    docker run --rm --platform "$PLATFORM" "${docker_env[@]}" -it "$IMAGE" /usr/bin/zsh
    ;;
  bash)
    build
    docker run --rm --platform "$PLATFORM" "${docker_env[@]}" -it "$IMAGE" bash -c \
      '/home/tester/.dotfiles/install.sh && exec bash -i'
    ;;
  verify)
    build
    echo "==> running install.sh + verification in container (CLAWBOT=$CLAWBOT_FLAG)"
    docker run --rm --platform "$PLATFORM" "${docker_env[@]}" -i "$IMAGE" bash -c \
      '/home/tester/.dotfiles/install.sh && /home/tester/.dotfiles/test/verify.sh'
    ;;
  reconfigure)
    build
    echo "==> install (agent CLIs off) -> re-run with INSTALL_CLAUDE_CODE=1 -> verify present"
    # First install takes clawbot defaults (claude off). Re-running install.sh with
    # INSTALL_CLAUDE_CODE=1 must reconcile the switch, clear the run-state cache
    # (non-interactive => auto-confirm) and re-fire the installer so claude lands.
    # Clean -e (CLAWBOT only) so the FIRST install isn't handed INSTALL_CLAUDE_CODE.
    docker run --rm --platform "$PLATFORM" -e "CLAWBOT=$CLAWBOT_FLAG" -i "$IMAGE" bash -c \
      'D=/home/tester/.dotfiles; "$D/install.sh" && INSTALL_CLAUDE_CODE=1 "$D/install.sh" && INSTALL_CLAUDE_CODE=1 "$D/test/verify.sh"'
    ;;
  *)
    echo "unknown command: $cmd" >&2
    echo "usage: $0 [build|install|shell|bash|verify|reconfigure|templates|modify]" >&2
    exit 2
    ;;
esac
