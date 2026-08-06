# qtplatform — Qt 5.15.2 多平台构建环境（x86_64 原生 + ARM64 交叉）

在 **Linux x86_64 构建机**上构建 **Qt 5.15.2（qtbase + qtcharts）**：

- **x86_64 Linux 原生**（系统 gcc）：桌面 Linux 运行/调试用，同时兼任交叉编译
  所需的 host 工具（qmake/moc/rcc/uic）。
- **ARM64 Linux 交叉**（仓库内置 ARM GNU gcc 14.2）：嵌入式板卡 / arm64 发行版用。

本仓库**只管理**：构建脚本、CMake toolchain、内置交叉工具链、以及各目标的
**构建产物**（编译出的 Qt 库，进 git）。Qt 源码不进 git（见 `.gitignore`）。

> **Windows 版本不在本仓库**：请在 Windows 机器上用 **MSVC** 构建，或直接用
> Qt 官方安装器的 `msvc2019_64` 预编译包（Qt Charts 是可勾选组件）。
> MSVC 与 gcc 的 C++ ABI 互不兼容，两套产物各自独立，仅靠同一份 5.15.2
> 源码保证行为一致。

---

## 1. 目录结构

```
qtplatform/
├── .gitignore            # 忽略 Qt 源码与中间产物，保留构建产物
├── README.md             # 本文件
├── AGENTS.md             # 给 AI / 协作者看的架构与重建说明
├── Qt/
│   └── 5.15.2/
│       ├── Src/          # (gitignored) Qt 5.15.2 源码（qt5 超级仓库 + 子模块）
│       └── build/
│           ├── x86_64-linux-gnu/install/    # 原生 x64 产物 + host 工具（进 git）
│           └── aarch64-linux-gnu/install/   # ARM64 交叉产物（进 git）
├── toolchain/            # CMake toolchain 文件（进 git），用于交叉编译你的应用
│   └── aarch64-linux-gnu.cmake
├── tools/                # ARM GNU Toolchain 14.2.rel1（gcc 14.2，进 git）
└── scripts/              # 构建脚本（进 git）
    ├── common.sh         # 路径 / CROSS_PREFIX / SYSROOT（自动识别 tools/ 工具链）
    ├── build-qt-native.sh# 原生 x86_64 构建（产物兼任 host 工具）
    └── build-qt.sh       # 交叉编译 qtbase + qtcharts 到 aarch64-linux-gnu
```

---

## 2. 目标平台

| 目标 | 编译器 | Qt mkspec | 由谁构建 |
|------|--------|-----------|----------|
| x86_64 Linux（桌面/服务器） | 系统 gcc | `linux-g++` | `scripts/build-qt-native.sh` |
| ARM64 Linux（嵌入式板卡 / arm64 发行版） | 内置 ARM gcc 14.2 | `linux-aarch64-gnu-g++`（qtbase 官方自带） | `scripts/build-qt.sh` |
| Windows x64 | MSVC | — | **不在本仓库**，Windows 机器上自行 MSVC 构建或用官方包 |

> `arm64` 与 `aarch64` 是同一架构的两种叫法。macOS / Android / wasm 不在范围内。

---

## 3. 安装（一次性初始化）

ARM64 交叉工具链已随仓库提交在 `tools/`，**交叉编译无需 sudo 安装任何东西**。

```bash
# 0) 进入仓库
cd qtplatform

# 1) 原生构建依赖（Ubuntu/Debian）
sudo apt install build-essential perl
# 可选但推荐：桌面 GUI 支持（xcb）与字体渲染（fontconfig）。
# 不装也能编译成功，但 GUI 程序只能以 -platform minimal/offscreen 运行。
sudo apt install libfontconfig1-dev libglib2.0-dev \
  libxcb1-dev libxcb-icccm4-dev libxcb-image0-dev libxcb-keysyms1-dev \
  libxcb-randr0-dev libxcb-render-util0-dev libxcb-shape0-dev libxcb-sync-dev \
  libxcb-xinerama0-dev libxcb-xkb-dev libxkbcommon-dev libxkbcommon-x11-dev \
  libx11-xcb-dev

# 2) 获取 Qt 5.15.2 源码（gitignored）
git clone --branch v5.15.2 https://code.qt.io/qt/qt5.git Qt/5.15.2/Src
cd Qt/5.15.2/Src
# 排除 qtwebengine（Chromium 内核，体积巨大且交叉编译困难）
git config --file .gitmodules --remove-section submodule.qtwebengine 2>/dev/null || true
perl init-repository   # qtcharts 会随默认子模块一起拉取
cd -
```

---

## 4. 使用规则：如何编译

> 编译耗时，**按顺序**手动执行。**先 x64 再 ARM64**——ARM64 交叉编译依赖
> x64 产物里的 host 工具。

```bash
# 步骤 A：原生 x86_64 构建（qtbase + qtcharts，约 20–40 分钟）
#         产物同时是交叉编译的 host 工具
scripts/build-qt-native.sh

# 步骤 B：ARM64 交叉编译（qtbase + qtcharts）
scripts/build-qt.sh

# 若目标板是厂商定制系统（BSP / Yocto / Buildroot），指定板子的 sysroot：
SYSROOT=/path/to/board-sysroot scripts/build-qt.sh
```

验证产物架构：

```bash
file Qt/5.15.2/build/x86_64-linux-gnu/install/lib/libQt5Core.so*
# 期望: ELF 64-bit LSB shared object, x86-64
file Qt/5.15.2/build/aarch64-linux-gnu/install/lib/libQt5Core.so*
# 期望: ELF 64-bit LSB shared object, ARM aarch64
```

### 产物与 git 版本管理

- **产物生成在本仓库内**：`Qt/5.15.2/build/<target>/install/`，**会被 git
  跟踪**（`.gitignore` 只排除 `bld*/` 中间目录、源码与日志），直接
  `git add` / commit / push 即可留档。
- 每个目标的 install 约 300–500MB，两个目标都入库后仓库约 1.5–2GB。
  自建 GitLab + SSH 推送没有障碍；若日后觉得克隆太慢，可迁到 Git LFS 或
  改为 Release 附件分发（README 结构已为此预留）。
- 换机器使用时：克隆仓库 → 第 3 节装依赖/拉源码 → 直接编应用；Qt 库本身
  无需重编（除非要改 configure 配置）。

### Windows 检出说明（稀疏检出）

`tools/` 里的 Linux 内核头文件存在**仅大小写不同**的同名文件
（如 `xt_mark.h` / `xt_MARK.h`），Windows 的 NTFS 大小写不敏感，会导致
git status 永远显示一批幽灵"变更"。交叉工具链在 Windows 上本来就用不到
（Windows 用 MSVC），所以 Windows 机器克隆后请用稀疏检出排除 `tools/`：

```bash
git sparse-checkout init --cone
git sparse-checkout set scripts toolchain Qt
# 注意：cone 模式只接受目录名；根目录的 README.md / AGENTS.md / .gitignore
# 会自动保留，不要列进去（列了会报 'README.md' is not a directory）
```

之后 `git status` 干净，`git pull` 自动保持该规则；恢复完整检出用
`git sparse-checkout disable`。此配置是本地的，每台 Windows 机器配一次。

**纪律**：不要在 Windows 上提交 `tools/` 下的任何"变更"，也不要对这些文件
执行 `git checkout --`（大小写冲突会互相覆盖内容）。

### 用产物编译你的应用

```bash
# x86_64 原生（无需 toolchain 文件）
cmake -DCMAKE_PREFIX_PATH=$PWD/Qt/5.15.2/build/x86_64-linux-gnu/install/lib/cmake \
      <your-app-source>

# ARM64 交叉
cmake -DCMAKE_TOOLCHAIN_FILE=toolchain/aarch64-linux-gnu.cmake \
      -DCMAKE_PREFIX_PATH=$PWD/Qt/5.15.2/build/aarch64-linux-gnu/install/lib/cmake \
      <your-app-source>
# 若 Qt 构建时用了 SYSROOT，应用侧也要在环境里设同一个 SYSROOT
```

**部署到 ARM64 板子**：拷贝 `install/lib` 的 Qt `.so`、可执行文件、以及
`install/plugins/platforms/` 所需平台插件（如 `libqlinuxfb.so`），运行前设
`QT_QPA_PLATFORM=linuxfb`（或板子对应插件）与 `LD_LIBRARY_PATH`。
注意板子 glibc 版本需不低于工具链实际引用的符号版本（内置工具链 glibc 为
2.40；板子更老时请用板子 sysroot 重编）。

---

## 5. 关键设计决策

- **x64 原生构建兼任 host 工具**：交叉编译时 moc/rcc/uic 必须运行在构建机上，
  原生 install 里的 `bin/` 正好提供（`-hostprefix` / `-external-hostbindir`
  指向它），避免为 host 工具单独编译一遍 qtbase。
- **mkspec 用 Qt 官方**：ARM64 用 qtbase 自带的 `linux-aarch64-gnu-g++`，
  原生用 `linux-g++`，本仓库没有自写 mkspec。
- **qtcharts 单独构建**：`qtbase/configure` 只编 qtbase；两个脚本随后都用装好
  的 qmake 构建 qtcharts 并装进同一 prefix。新增其他模块照抄脚本里的模块循环。
- **内置第三方库**：`-qt-zlib -qt-libpng -qt-freetype -qt-harfbuzz -qt-pcre`，
  交叉时不受目标系统库缺失影响。
- **pkg-config 策略不同**：交叉构建 `-no-pkg-config`（避免误捡宿主 `.pc`）；
  原生构建**不关**（用于自动检测 fontconfig/xcb/glib 等桌面能力）。
- **`-no-opengl`**：Qt Charts 的 Widgets 用法（`QChart` + `QChartView`）不依赖
  OpenGL；嵌入式板无 GPU 时 GUI 走 linuxfb。若未来需要 eglfs / Qt Quick，
  需配板子 sysroot 并重新评估（工作量大一档）。
- **交叉工具链随仓库自带**：ARM GNU Toolchain 14.2.rel1 在 `tools/`，克隆即用；
  `CROSS_PREFIX` 环境变量可覆盖为系统工具链（如 `aarch64-linux-gnu-`）。

---

## 6. 故障排查

- `configure` 的编译测试若有个别失败，看 `Qt/5.15.2/build/<target>/bld/config.log`，
  用 `-no-feature-xxx` 跳过。
- **Qt 5.15.2 比 gcc 11–14 老**：编译中若遇到 `... is not a member of std` /
  缺少头文件之类的零星报错，是已知的新编译器兼容问题，通常补对应
  `#include` 即可；批量问题可应用 KDE 的 Qt 5.15 patch collection。
  把报错贴出来再修，不要预先打补丁。

  > 已知触发场景：本仓库交叉工具链是 **GCC 14.2**，比原生构建用的系统 gcc
  > 13.3 更新，收紧了间接头文件包含，因此交叉编译会先撞上这类缺 include
  > 报错（原生 gcc 13.3 下通常不报）。

### 6.1 已应用的 Qt 源码补丁（GCC 14.2 兼容性，交叉编译必需）

以下为在 `Qt/5.15.2/Src/` 中**已手动补的 `#include`**（均因 GCC 14.2 不再
间接包含对应标准头）。这些改动位于 gitignored 的 `Src/` 内、**不进 git**，
每次重新 `perl init-repository` 拉取源码后需再次应用：

| 文件 | 补充的 `#include` |
|------|-------------------|
| `qtbase/src/corelib/global/qfloat16.h` | `<limits>` |
| `qtbase/src/corelib/global/qendian.h` | `<limits>` |
| `qtbase/src/corelib/text/qbytearraymatcher.h` | `<limits>` |
| `qtbase/src/corelib/tools/qoffsetstringarray_p.h` | `<limits>` |
| `qtdeclarative/src/qmldebug/qqmlprofilerevent_p.h` | `<limits>`、`<type_traits>` |

若后续交叉编译又出现类似的 `... is not a member of std` / 缺头文件报错，
照此在对应文件顶部补一个标准头 `#include` 即可；或一次性应用 KDE 的 Qt 5.15
patch collection 免除逐个修补。

- 交叉 gcc 找不到：确认 `tools/` 工具链完整，或设 `CROSS_PREFIX` 指向系统
  工具链（`sudo apt install g++-aarch64-linux-gnu`）。
- 原生 GUI 程序起不来（`could not load the Qt platform plugin "xcb"`）：
  编译时缺第 3 节的 xcb 开发包，装上后重跑 `scripts/build-qt-native.sh`，
  或临时用 `-platform minimal` 验证。
