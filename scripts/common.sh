#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Optional per-user customization: if <repo>/qtbuild.env exists, source it.
# Template: scripts/qtbuild.env.example. It may set/override QT_SRC, QT_BUILD,
# QT_HOST, VENDORED_TC, CROSS_PREFIX, SYSROOT, TARGET_SUFFIX ... Alternatively
# export the same variables in your shell before running the build scripts.
if [ -f "$REPO_DIR/qtbuild.env" ]; then
  # shellcheck disable=SC1091
  source "$REPO_DIR/qtbuild.env"
fi

export QT_SRC="${QT_SRC:-$REPO_DIR/Qt/5.15.2/Src}"
export QT_BUILD="${QT_BUILD:-$REPO_DIR/Qt/5.15.2/build}"
export QT_HOST="${QT_HOST:-$QT_BUILD/x86_64-linux-gnu/install}"

readonly -a QT_ADDON_MODULES=(
  qtdeclarative
  qtsvg
  qtgraphicaleffects
  qtquickcontrols
  qtquickcontrols2
  qtcharts
)

# auto-detect arch from calling script name
# VENDORED_TC 可被环境变量覆盖（如换成板子配套的 GCC 10.3 工具链）
case "${BASH_SOURCE[1]}" in
  *arm32*)
    VENDORED_TC="${VENDORED_TC:-$REPO_DIR/tools/arm-gnu-toolchain-14.2.rel1-x86_64-arm-none-linux-gnueabihf}"
    DEFAULT_PREFIX="arm-none-linux-gnueabihf-"
    FALLBACK_PREFIX="arm-linux-gnueabihf-"
    ;;
  *)
    VENDORED_TC="${VENDORED_TC:-$REPO_DIR/tools/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu}"
    DEFAULT_PREFIX="aarch64-none-linux-gnu-"
    FALLBACK_PREFIX="aarch64-linux-gnu-"
    ;;
esac

if [ -x "$VENDORED_TC/bin/${DEFAULT_PREFIX}g++" ]; then
  export PATH="$VENDORED_TC/bin:$PATH"
  export CROSS_PREFIX="${CROSS_PREFIX:-$DEFAULT_PREFIX}"
else
  export CROSS_PREFIX="${CROSS_PREFIX:-$FALLBACK_PREFIX}"
fi

export SYSROOT="${SYSROOT:-}"

need_src() {
  [ -d "$QT_SRC/qtbase" ] || {
    echo "ERROR: Qt source not found at $QT_SRC"
    exit 1
  }
}

need_addon_modules() {
  for module in "${QT_ADDON_MODULES[@]}"; do
    [ -d "$QT_SRC/$module" ] || {
      echo "ERROR: Qt add-on module source not found: $QT_SRC/$module"
      exit 1
    }
  done
}

need_cross() {
  command -v "${CROSS_PREFIX}g++" >/dev/null 2>&1 || {
    echo "ERROR: cross compiler '${CROSS_PREFIX}g++' not found in PATH"
    exit 1
  }
}
