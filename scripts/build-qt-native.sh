#!/usr/bin/env bash
# Build Qt 5.15.2 NATIVELY for x86_64 Linux using the system gcc.  In addition
# to qtbase, the add-on list in common.sh supplies Qt Quick/QML, Controls,
# Graphical Effects, SVG, and Charts support.  This install serves two purposes:
#   1. the x86_64 product (for running/testing the app on desktop Linux)
#   2. the host tools (qmake/moc/rcc/uic) required by the aarch64 cross build
#      (scripts/build-qt.sh uses it via -hostprefix / -external-hostbindir)
#
# NOTE: pkg-config is intentionally NOT disabled here (unlike the cross
# build): on the host it is safe and lets configure auto-detect fontconfig,
# xcb, glib etc. when the corresponding -dev packages are installed. Without
# xcb dev packages the build still succeeds, but GUI apps can then only run
# with -platform minimal/offscreen. See README section 3 for the apt list.
#
# NOTE: this is an actual compile step (~20-40 min). Run it manually when
# ready; it is NOT executed during setup.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TARGET="x86_64-linux-gnu"

need_src
need_addon_modules
command -v g++ >/dev/null 2>&1 || {
  echo "ERROR: system g++ not found. Ubuntu/Debian: sudo apt install build-essential"
  exit 1
}

# shadow build of qtbase
BLD="$QT_BUILD/$TARGET/bld"
INSTALL="$QT_BUILD/$TARGET/install"
rm -rf "$BLD"; mkdir -p "$BLD"
cd "$BLD"

# Ubuntu 24.04+ 的系统 gcc 默认启用 _FORTIFY_SOURCE=3，与 Qt 5.15.2 的老代码
# （含大量手工 memcpy/strcpy 优化）冲突，编译后运行会触发 glibc
# "buffer overflow detected" 崩溃（Qt 库内部 __fortify_fail）。
# 注意:
#   - configure 不读取 CFLAGS/CXXFLAGS 环境变量，需用 QMAKE_* 参数注入；
#   - 必须用 -D_FORTIFY_SOURCE=0 显式置 0（-U 会被 glibc 头文件在 -O 下回退到 2）；
#   - 命令行参数在 Ubuntu specs 默认参数之后处理，故能覆盖默认的 =3。
# 否则 x86_64 桌面版无法启动（ARM 交叉工具链不受影响）。
"$QT_SRC/qtbase/configure" \
  -platform linux-g++ \
  -prefix "$INSTALL" \
  -release -opensource -confirm-license \
  -nomake tests -nomake examples \
  -qt-zlib -qt-libpng -qt-freetype -qt-harfbuzz -qt-pcre \
  -no-opengl \
  "QMAKE_CFLAGS+=-D_FORTIFY_SOURCE=0" \
  "QMAKE_CXXFLAGS+=-D_FORTIFY_SOURCE=0"

make -j"$(nproc)"
make install

# qtbase/configure builds qtbase only.  Build each add-on afterwards with the
# installed qmake, in the dependency order declared in common.sh.
for MODULE in "${QT_ADDON_MODULES[@]}"; do
  echo
  echo "Building native Qt add-on module: $MODULE"
  MOD_BLD="$QT_BUILD/$TARGET/bld-$MODULE"
  rm -rf "$MOD_BLD"; mkdir -p "$MOD_BLD"
  cd "$MOD_BLD"
  "$INSTALL/bin/qmake" "$QT_SRC/$MODULE" \
    "QMAKE_CFLAGS+=-D_FORTIFY_SOURCE=0" \
    "QMAKE_CXXFLAGS+=-D_FORTIFY_SOURCE=0"
  make -j"$(nproc)"
  make install
done

echo
echo "Native Qt (qtbase + QML/Quick add-ons) for x86_64 installed to $INSTALL"
echo "This install also provides the host tools for scripts/build-qt.sh."
