# AGENTS.md — 给 AI / 协作者的项目说明

本仓库在 **Linux x86_64 构建机**上构建 **Qt 5.15.2（qtbase + qtcharts）**：
x86_64 原生（系统 gcc）+ ARM64 / ARM32 Linux 交叉（仓库内置 ARM GNU
gcc 14.2，另有 arm32 用的 gcc 10.3），构建产物纳入 git 留档。

## 关键事实（务必先读）
- **构建主机是 Linux x86_64，不是 Windows。** Windows 目标不在本仓库范围：
  公司 Windows 版本在 Windows 机器上用 **MSVC** 自行构建（或 Qt 官方 MSVC 包）。
  MSVC 与 gcc 的 C++ ABI 不兼容。
- **没有独立的 host 工具构建**：`scripts/build-qt-native.sh` 的 x86_64 原生
  install 兼任交叉编译的 host 工具（`common.sh` 里 `QT_HOST` 默认指向
  `build/x86_64-linux-gnu/install`）。**构建顺序固定：先 native 再 cross**，
  `build-qt.sh` / `build-qt-arm32.sh` 会检查 `$QT_HOST/bin/qmake` 存在。
- **mkspec 全部用 Qt 官方**：原生 `linux-g++`、交叉 `linux-aarch64-gnu-g++`
  与 `linux-arm-gnueabihf-g++`（qtbase 自带），本仓库**没有**自写 mkspec。
- **Qt 源码在 `Qt/5.15.2/Src/`**（gitignored），来自 `code.qt.io/qt/qt5` 的
  `v5.15.2` 标签 + `perl init-repository`。**qtwebengine 已被刻意排除**。
- **qtcharts 不在 qtbase 里**：`qtbase/configure` 只编 qtbase；三个构建脚本
  （native / aarch64 / arm32）在 qtbase 装好后用装好的 qmake 单独构建
  qtcharts。新增模块照抄该循环。
- **arm64 == aarch64**（同一架构）；**arm32 == arm-linux-gnueabihf**（32 位
  硬浮点），产物目录 `arm-linux-gnueabihf/`（gcc 14.2）与
  `arm-linux-gnueabihf_10_3_1/`（gcc 10.3，靠 `TARGET_SUFFIX=_10_3_1` 区分）。
- **不进 git**：`Qt/5.15.2/Src/`、`Qt/5.15.2/build/*/bld*/`（含 `bld-qtcharts`）、
  `Qt/5.15.2/*.log`、根目录 `qtbuild.env`（用户本地定制，模板
  `scripts/qtbuild.env.example`）。
- **进 git**：`tools/`（交叉工具链）、`toolchain/`、`scripts/`、`README.md`、
  `AGENTS.md`、`Qt/5.15.2/build/<target>/install/` 下的构建产物、`.gitkeep`。
- **路径全部可定制**：`scripts/common.sh` 每次构建前加载仓库根 `qtbuild.env`
  （存在时），可覆盖 `QT_SRC` / `QT_BUILD` / `QT_HOST` / `VENDORED_TC` /
  `CROSS_PREFIX` / `SYSROOT` / `TARGET_SUFFIX`；不建文件则用仓库内默认路径。
  排查路径问题时先看是否有人设了 `qtbuild.env`。

## sysroot 设计
- 板子是标准 Debian/Ubuntu arm64 用户态 → 不设 `SYSROOT`，交叉工具链自带
  匹配 libc（注意：内置工具链 glibc 为 2.40，板子系统更老时不能直接用）。
- 板子是厂商定制系统（BSP/Yocto/Buildroot）→ `SYSROOT=<板子sysroot>` 传给
  `build-qt.sh` / `build-qt-arm32.sh`（configure 加 `-sysroot`），也可写进
  `qtbuild.env`；应用侧 CMake 构建时也要在环境里设同一个 `SYSROOT`
  （`toolchain/aarch64-linux-gnu.cmake`、`toolchain/arm-linux-gnueabihf.cmake`
  都会读取）。

## 如何重建
1. 装原生构建依赖并克隆 Qt 源码（见 README 第 3 节）。交叉工具链已随仓库
   提交在 `tools/`，无需安装；需要定制路径/工具链/sysroot 时，复制
   `scripts/qtbuild.env.example` 为根目录 `qtbuild.env` 后修改。
2. `scripts/build-qt-native.sh`（x86_64 原生产物 + host 工具，约 20–40 分钟）。
3. `scripts/build-qt.sh`（ARM64 交叉产物）或 `scripts/build-qt-arm32.sh`
   （ARM32 交叉产物），耗时，按需执行。
   以上步骤不要在初始化阶段跑，留给用户手动执行或专门的构建任务。

## 约束 / 警告
- **真正的编译非常耗时**，初始化阶段不要执行构建脚本。
- Qt 5.15.2 比 gcc 11–14 老，编译可能遇到零星缺头文件报错；按报错补
  `#include`，或应用 KDE Qt 5.15 patch collection。不要预先打补丁。
- pkg-config 策略：交叉 `-no-pkg-config`，原生不关（自动检测 fontconfig/xcb）。
- 当前 configure 带 `-no-opengl`：Qt Charts 的 Widgets 用法不需要 OpenGL，
  嵌入式 GUI 走 linuxfb 插件。若未来需要 eglfs / Qt Quick，需配板子 sysroot
  并重新评估（工作量大一档）。
- macOS / wasm / Android 不在本仓库范围内。
- 不要改 Qt 源码本身；定制只发生在脚本与 toolchain 文件。
