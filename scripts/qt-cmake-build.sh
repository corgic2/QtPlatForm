#!/usr/bin/env bash
# qt-cmake-build.sh — 通用 CMake 构建驱动器（C++ 项目，以 CMakeLists.txt 为核心）
#
# 消费「本 qtplatform 仓库」里已经编译安装好的 Qt（x86_64 / aarch64），
# 为你的应用工程做 配置 + 编译。本脚本【不会、也不需要重新编译 Qt】。
#
# 定位 Qt 仓库的优先级：
#   1. 环境变量 QTPLATFORM_DIR
#   2. 命令行 --repo <path>
#   3. 脚本自身位置（scripts/ 的上级 = 仓库根）
#
# 用法：
#   scripts/qt-cmake-build.sh [选项] [源码目录]
#   源码目录缺省为当前目录。
#
# 选项：
#   --repo <path>        指定 qtplatform 仓库根
#   --target <id|all>    目标：x64 / arm64 / arm32 / all（可多次，或 all）
#   --type <t>           Debug | Release（默认 Release）
#   --build-dir <dir>    指定构建目录（默认 build-<id>，各目标独立）
#   --clean              构建前清空构建目录
#   --jobs <n>           并行数（默认 nproc）
#   --deploy             构建后执行 qtbuild.local 里的 DEPLOY()（若定义）
#   --list-targets       只列出检测到的可用目标后退出
#   --yes                非交互：跳过所有提示，用上述选项（缺省 target=all）
#   -h | --help          帮助
#
# 项目级扩展（可选）：在源码目录放一个 qtbuild.local（shell 片段），脚本会
# source 它，可定义：
#   EXTRA_CMAKE_FLAGS    额外的 cmake 参数（数组或字符串）
#   REQUIRED_QT_MODULES  要求存在的 Qt 模块（如 Charts Svg），缺失则报错
#   PRE_BUILD()          配置前钩子（如 protoc 代码生成）
#   POST_BUILD()         编译后钩子（如拷贝资源）
#   DEPLOY()             打包钩子（配合 --deploy 触发，如调用 linuxdeployqt）
# 参见 qtbuild.local.example。
#
# 注意：Windows 目标不在本脚本范围（Linux 无法交叉编译 MSVC）。Windows 端
# 请在 Windows 机器上用 MSVC + 官方/自编 Qt 5.15.2 单独构建。

set -uo pipefail

QT_VER="${QT_VER:-5.15.2}"
REPO=""
REPO_ARG=""
SRC="."
TARGETS=()
TYPE="Release"
BUILD_DIR_OVERRIDE=""
CLEAN=""
JOBS="$(nproc 2>/dev/null || echo 4)"
DO_DEPLOY=""
NONINTERACTIVE=""
LIST_ONLY=""

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[qt-cmake-build] $*"; }

# ---------- 解析参数 ----------
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)        REPO_ARG="${2:-}"; shift 2;;
    --target)      TARGETS+=("${2:-}"); shift 2;;
    --type)        TYPE="$2"; shift 2;;
    --build-dir)   BUILD_DIR_OVERRIDE="$2"; shift 2;;
    --clean)       CLEAN=1; shift;;
    --jobs)        JOBS="$2"; shift 2;;
    --deploy)      DO_DEPLOY=1; shift;;
    --list-targets) LIST_ONLY=1; shift;;
    --yes)         NONINTERACTIVE=1; shift;;
    -h|--help)     sed -n '3,48p' "$0"; exit 0;;
    --)            shift; [ $# -gt 0 ] && SRC="$1"; break;;
    -*)            die "未知选项: $1";;
    *)             SRC="$1"; break;;
  esac
done

# ---------- 定位仓库 ----------
if [ -n "${QTPLATFORM_DIR:-}" ]; then
  REPO="$QTPLATFORM_DIR"
elif [ -n "$REPO_ARG" ]; then
  REPO="$REPO_ARG"
else
  sdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO="$(cd "$sdir/.." && pwd)"
fi
[ -d "$REPO/Qt/$QT_VER/build" ] || die "找不到 qtplatform 仓库（请设 QTPLATFORM_DIR 或用 --repo）。当前推断: $REPO"

# ---------- 探测可用目标 ----------
declare -a TARGET_IDS=() TARGET_DIRS=() TARGET_CROSS=() TARGET_TC=()
detect_targets() {
  local d p tdir
  for d in "$REPO/Qt/$QT_VER/build"/*/install/lib/cmake/Qt5/Qt5Config.cmake; do
    [ -e "$d" ] || continue
    p="$d"
    for _ in 1 2 3 4 5; do p="$(dirname "$p")"; done
    tdir="$(basename "$p")"
    case "$tdir" in
      x86_64-linux-gnu)    TARGET_IDS+=("x64");   TARGET_DIRS+=("$tdir"); TARGET_CROSS+=("no");  TARGET_TC+=("");;
      aarch64-linux-gnu*)  TARGET_IDS+=("arm64"); TARGET_DIRS+=("$tdir"); TARGET_CROSS+=("yes"); TARGET_TC+=("aarch64-linux-gnu.cmake");;
      arm-linux-gnueabihf*) TARGET_IDS+=("arm32"); TARGET_DIRS+=("$tdir"); TARGET_CROSS+=("yes"); TARGET_TC+=("arm-linux-gnueabihf.cmake");;
      *)                   TARGET_IDS+=("$tdir"); TARGET_DIRS+=("$tdir"); TARGET_CROSS+=("yes"); TARGET_TC+=("");;
    esac
  done
  [ ${#TARGET_IDS[@]} -gt 0 ] || die "在 $REPO/Qt/$QT_VER/build 下未检测到任何已安装的 Qt 目标"
}

detect_targets

if [ -n "$LIST_ONLY" ]; then
  info "检测到以下 Qt 目标（仓库: $REPO）:"
  for i in "${!TARGET_IDS[@]}"; do
    printf "  %d) %s  (%s%s)\n" $((i+1)) "${TARGET_IDS[$i]}" "${TARGET_DIRS[$i]}" \
      "$([ "${TARGET_CROSS[$i]}" = yes ] && echo ', cross')"
  done
  exit 0
fi

# ---------- 选择目标 ----------
declare -a CHOSEN_IDX=()
select_targets() {
  echo "检测到以下 Qt 目标（仓库: $REPO）:"
  for i in "${!TARGET_IDS[@]}"; do
    printf "  %d) %s  (%s%s)\n" $((i+1)) "${TARGET_IDS[$i]}" "${TARGET_DIRS[$i]}" \
      "$([ "${TARGET_CROSS[$i]}" = yes ] && echo ', cross')"
  done
  local sel
  read -rp "选择目标 [数字逗号分隔，或 'all']: " sel
  if [ "$sel" = "all" ]; then
    CHOSEN_IDX=("${!TARGET_IDS[@]}"); return
  fi
  local IFS=','; local picks=($sel); unset IFS
  for p in "${picks[@]}"; do
    p="$(echo "$p" | tr -d ' ')"
    if [[ "$p" =~ ^[0-9]+$ ]]; then
      local idx=$((p-1))
      [ -n "${TARGET_IDS[$idx]:-}" ] && CHOSEN_IDX+=("$idx") || die "无效选择: $p"
    else
      local found=""
      for i in "${!TARGET_IDS[@]}"; do
        [ "${TARGET_IDS[$i]}" = "$p" ] && { CHOSEN_IDX+=("$i"); found=1; }
      done
      [ -n "$found" ] || die "未知目标: $p"
    fi
  done
  [ ${#CHOSEN_IDX[@]} -gt 0 ] || die "未选择任何目标"
}

# 把 --target 里的 all/x64/arm64 解析成索引
resolve_target_flags() {
  for t in "${TARGETS[@]:-}"; do
    if [ "$t" = "all" ]; then CHOSEN_IDX=("${!TARGET_IDS[@]}"); return; fi
    local found=""
    for i in "${!TARGET_IDS[@]}"; do
      [ "${TARGET_IDS[$i]}" = "$t" ] && { CHOSEN_IDX+=("$i"); found=1; }
    done
    [ -n "$found" ] || die "未知目标: $t"
  done
}

if [ ${#TARGETS[@]} -gt 0 ]; then
  resolve_target_flags
fi
if [ -z "$NONINTERACTIVE" ] && [ ${#CHOSEN_IDX[@]} -eq 0 ]; then
  select_targets
elif [ -n "$NONINTERACTIVE" ] && [ ${#CHOSEN_IDX[@]} -eq 0 ]; then
  CHOSEN_IDX=("${!TARGET_IDS[@]}")   # --yes 缺省 = all
fi
[ ${#CHOSEN_IDX[@]} -gt 0 ] || die "未选择任何目标"

# 非交互时确认构建类型
if [ -z "$NONINTERACTIVE" ]; then
  read -rp "构建类型 [Debug/Release，默认 Release]: " ans
  [ -n "$ans" ] && TYPE="$ans"
fi
case "$TYPE" in Debug|Release) ;; *) die "无效构建类型: $TYPE";; esac

# ---------- 找项目级扩展 ----------
LOCAL=""
if [ -f "$SRC/qtbuild.local" ]; then LOCAL="$SRC/qtbuild.local"
elif [ -f "./qtbuild.local" ]; then LOCAL="./qtbuild.local"; fi
[ -n "$LOCAL" ] && info "加载项目扩展: $LOCAL" || info "无 qtbuild.local，使用默认行为"

# ---------- 单个目标构建 ----------
build_one() {
  local idx="$1"
  local id="${TARGET_IDS[$idx]}" dir="${TARGET_DIRS[$idx]}" cross="${TARGET_CROSS[$idx]}"
  local tc="${TARGET_TC[$idx]}"
  local prefix="$REPO/Qt/$QT_VER/build/$dir/install/lib/cmake"
  local builddir="${BUILD_DIR_OVERRIDE:-build-$id}"

  info "===== 构建目标 $id ($dir) ====="
  info "源码: $SRC"
  info "构建目录: $builddir"
  info "Qt prefix: $prefix"
  [ "$cross" = yes ] && info "交叉编译: toolchain/$tc"

  [ -d "$SRC" ] || die "源码目录不存在: $SRC"
  command -v cmake >/dev/null 2>&1 || die "未找到 cmake，请先安装"
  mkdir -p "$builddir"
  [ -n "$CLEAN" ] && { info "清空 $builddir"; rm -rf "$builddir"/*; }

  # source 扩展（每次构建前重新加载，便于增量修改生效）
  unset -f PRE_BUILD POST_BUILD DEPLOY 2>/dev/null
  unset EXTRA_CMAKE_FLAGS REQUIRED_QT_MODULES
  [ -n "$LOCAL" ] && source "$LOCAL"

  # 模块存在性校验
  if declare -p REQUIRED_QT_MODULES >/dev/null 2>&1; then
    for m in "${REQUIRED_QT_MODULES[@]:-}"; do
      [ -f "$prefix/Qt5${m}Config.cmake" ] || \
        die "目标 $id 的 Qt 安装缺少模块 Qt5$m（该目标未编译此模块）"
    done
    info "所需 Qt 模块校验通过: ${REQUIRED_QT_MODULES[*]}"
  fi

  local -a args=(-S "$SRC" -B "$builddir" \
    -DCMAKE_PREFIX_PATH="$prefix" -DCMAKE_BUILD_TYPE="$TYPE")
  [ "$cross" = yes ] && {
    [ -n "$tc" ] || die "目标 $id 是交叉目标，但缺少对应的 CMake toolchain 文件"
    args+=(-DCMAKE_TOOLCHAIN_FILE="$REPO/toolchain/$tc")
  }
  if declare -p EXTRA_CMAKE_FLAGS >/dev/null 2>&1; then
    args+=("${EXTRA_CMAKE_FLAGS[@]}")
  fi

  declare -F PRE_BUILD >/dev/null 2>&1 && { info "PRE_BUILD 钩子"; PRE_BUILD; }

  info "cmake 配置..."
  cmake "${args[@]}" || die "cmake 配置失败 ($id)"
  info "编译 (jobs=$JOBS)..."
  cmake --build "$builddir" -j"$JOBS" || die "编译失败 ($id)"

  declare -F POST_BUILD >/dev/null 2>&1 && { info "POST_BUILD 钩子"; POST_BUILD; }
  if [ -n "$DO_DEPLOY" ]; then
    declare -F DEPLOY >/dev/null 2>&1 && { info "DEPLOY 钩子"; DEPLOY; } || \
      info "未定义 DEPLOY()，跳过打包"
  fi
  info "===== 目标 $id 完成，产物在 $builddir ====="
}

# ---------- 主循环 ----------
for idx in "${CHOSEN_IDX[@]}"; do
  build_one "$idx"
done
info "全部完成。"
