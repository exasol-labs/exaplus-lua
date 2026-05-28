#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS="$(uname -s)"
ARCH="$(uname -m)"
OUTDIR="$ROOT_DIR/build/out"
mkdir -p "$OUTDIR"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 2
  fi
}

have_runtime() {
  if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
    return 0
  fi
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

ensure_sources() {
  local srcdir="$ROOT_DIR/build/sources"
  local lua="$srcdir/lua-5.1.5.tar.gz"
  local luasocket="$srcdir/luasocket-3.1.0.tar.gz"
  local luasec="$srcdir/luasec-1.3.2.tar.gz"
  if [[ -f "$lua" && -f "$luasocket" && -f "$luasec" ]]; then
    return 0
  fi
  if [[ -x "$ROOT_DIR/tools/fetch_sources.sh" ]]; then
    "$ROOT_DIR/tools/fetch_sources.sh"
  else
    echo "Missing source tarballs under build/sources and tools/fetch_sources.sh not found." >&2
    exit 2
  fi
}

build_darwin() {
  need_cmd clang
  need_cmd make
  need_cmd python3
  need_cmd pkg-config
  ensure_sources
  LUA_TARBALL="$ROOT_DIR/build/sources/lua-5.1.5.tar.gz" \
  LUASOCKET_TARBALL="$ROOT_DIR/build/sources/luasocket-3.1.0.tar.gz" \
  LUASEC_TARBALL="$ROOT_DIR/build/sources/luasec-1.3.2.tar.gz" \
  TARGET_ARCH="$1" \
  "$ROOT_DIR/tools/build_static_darwin.sh"
}

build_linux() {
  if ! have_runtime; then
    echo "Skipping Linux static build (podman/docker not available)." >&2
    return 0
  fi
  "$ROOT_DIR/tools/build_static_alpine.sh"
}

collect_artifacts() {
  local built=()
  local exa
  for exa in "$ROOT_DIR"/build/static/*/exaplus; do
    if [[ -x "$exa" ]]; then
      built+=("$exa")
    fi
  done

  if [[ ${#built[@]} -eq 0 ]]; then
    echo "No binaries found under build/static/." >&2
    return 1
  fi

  for exa in "${built[@]}"; do
    local dir
    dir="$(basename "$(dirname "$exa")")"
    local name="exaplus-${VERSION_TAG:-0.6}-${dir}.tar.gz"
    tar -czf "$OUTDIR/$name" -C "$(dirname "$exa")" exaplus
  done

  echo
  echo "Built binaries:"
  for exa in "${built[@]}"; do
    echo "- $exa"
  done
  echo
  echo "Artifacts in build/out:"
  ls -1 "$OUTDIR"
}

case "$OS" in
  Darwin)
    case "$ARCH" in
      arm64|x86_64)
        echo "Building macOS static binary for $ARCH..."
        build_darwin "$ARCH"
        ;;
      *)
        echo "Unsupported macOS arch: $ARCH" >&2
        ;;
    esac
    echo "Building Linux static binary (container)..."
    build_linux
    ;;
  Linux)
    echo "Building Linux static binary..."
    build_linux
    ;;
  *)
    echo "Unsupported OS: $OS" >&2
    exit 2
    ;;
esac

collect_artifacts
