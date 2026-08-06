#!/usr/bin/env bash
# Cross-build Qt 5.15.2 for aarch64-linux-gnu.  In addition to qtbase, the
# add-on list in common.sh supplies Qt Quick/QML, Controls, Graphical Effects,
# SVG, and Charts support.
#
# Usage:
#   scripts/build-qt.sh                # standard Debian/Ubuntu arm64 targets
#   SYSROOT=/path/to/sysroot scripts/build-qt.sh   # embedded board vendor sysroot
#
# Steps performed:
#   1. verify the native x86_64 build exists (scripts/build-qt-native.sh) —
#      its install provides the host tools (qmake/moc/rcc/uic)
#   2. shadow-build qtbase with -xplatform linux-aarch64-gnu-g++
#      (the official aarch64 gcc mkspec shipped inside qtbase — nothing to copy)
#   3. build the QML/Quick add-ons separately with the freshly installed cross
#      qmake (qtbase/configure only builds qtbase; add-ons need this step)
#
# NOTE: this is an actual compile step (can take a long time). It is NOT run
# during setup; execute it manually when ready.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TARGET="aarch64-linux-gnu${TARGET_SUFFIX:-}"
# 说明: 可用 TARGET_SUFFIX 环境变量区分不同工具链的构建目录，
# 例如 TARGET_SUFFIX=_10_3_1 (GCC 10.3 工具链) -> Qt 装到 aarch64-linux-gnu_10_3_1/install
SPEC="linux-aarch64-gnu-g++"   # official mkspec inside qtbase/mkspecs/

need_src
need_addon_modules
need_cross
[ -x "$QT_HOST/bin/qmake" ] || {
  echo "ERROR: native build / host tools missing at $QT_HOST/bin/qmake"
  echo "       Run scripts/build-qt-native.sh first."
  exit 1
}

# 2) shadow build of qtbase
BLD="$QT_BUILD/$TARGET/bld"
INSTALL="$QT_BUILD/$TARGET/install"
rm -rf "$BLD"; mkdir -p "$BLD"
cd "$BLD"

CONFIGURE_ARGS=(
  -platform linux-g++
  -xplatform "$SPEC"
  -hostprefix "$QT_HOST"
  -prefix "$INSTALL"
  -external-hostbindir "$QT_HOST/bin"
  -release -opensource -confirm-license
  -nomake tests -nomake examples
  -no-pkg-config
  -qt-zlib -qt-libpng -qt-freetype -qt-harfbuzz -qt-pcre
  -no-opengl
)
if [ -n "$SYSROOT" ]; then
  [ -d "$SYSROOT" ] || { echo "ERROR: SYSROOT '$SYSROOT' is not a directory"; exit 1; }
  CONFIGURE_ARGS+=(-sysroot "$SYSROOT")
fi

"$QT_SRC/qtbase/configure" "${CONFIGURE_ARGS[@]}"

make -j"$(nproc)"
make install

# 3) qtbase/configure builds qtbase only.  Build each add-on afterwards with
#    the installed cross qmake, in the dependency order declared in common.sh.
for MODULE in "${QT_ADDON_MODULES[@]}"; do
  echo
  echo "Building cross Qt add-on module: $MODULE"
  MOD_BLD="$QT_BUILD/$TARGET/bld-$MODULE"
  rm -rf "$MOD_BLD"; mkdir -p "$MOD_BLD"
  cd "$MOD_BLD"
  "$QT_HOST/bin/qmake" "$QT_SRC/$MODULE"
  make -j"$(nproc)"
  make install
done

echo
echo "Cross-built Qt (qtbase + QML/Quick add-ons) for $TARGET installed to $INSTALL"
echo "Verify with: file $INSTALL/lib/libQt5Core.so*   # should show ARM aarch64"
