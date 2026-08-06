#!/usr/bin/env bash
# Cross-build Qt 5.15.2 for arm-linux-gnueabihf (ARM32 hard-float).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TARGET="arm-linux-gnueabihf${TARGET_SUFFIX:-}"
# 说明: 可用 TARGET_SUFFIX 环境变量区分不同工具链的构建目录，
# 例如 TARGET_SUFFIX=_10_3_1 (GCC 10.3 工具链) -> Qt 装到 arm-linux-gnueabihf_10_3_1/install
SPEC="linux-arm-gnueabihf-g++"

need_src
need_addon_modules
need_cross
[ -x "$QT_HOST/bin/qmake" ] || {
  echo "ERROR: native build missing. Run scripts/build-qt-native.sh first."
  exit 1
}

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
  -no-dbus
  -no-feature-vulkan
)
if [ -n "$SYSROOT" ]; then
  [ -d "$SYSROOT" ] || { echo "ERROR: SYSROOT '$SYSROOT' is not a directory"; exit 1; }
  CONFIGURE_ARGS+=(-sysroot "$SYSROOT")
fi

"$QT_SRC/qtbase/configure" "${CONFIGURE_ARGS[@]}"

make -j"$(nproc)"
make install

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
echo "Cross-built Qt for $TARGET installed to $INSTALL"
echo "Verify with: file $INSTALL/lib/libQt5Core.so*"
