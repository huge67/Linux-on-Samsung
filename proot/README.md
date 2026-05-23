# Galaxy Tab S8 - Linux 桌面 (proot-distro 方案)

在 Samsung Galaxy Tab S8 上跑一个完整的 **Debian 12 + XFCE4** 桌面，通过 `proot-distro` 容器化运行，**不需要 root**，**可一键卸载**。

## 为什么是这套方案

| 选择 | 理由 |
|---|---|
| **Debian 12 (Bookworm)** | 稳定、社区大、apt 软件包够新够全；`proot-distro` 官方直接支持 |
| **XFCE4** | 内存占用约 300-400 MB，对 8GB Tab S8 富裕；触屏可用 |
| **proot-distro** | Termux 官方维护，rootfs 容器化，删除即干净 |
| **Termux-X11** | 性能远好于 VNC，原生 Android Surface 渲染 |

> 想跑 KDE/GNOME 也可以，但 8GB RAM + 触屏体验会比 XFCE 差，不推荐。

## 前置条件

请从 **F-Droid** 或 **GitHub Releases** 安装以下三个 APK（Google Play 版本已停止维护，**不要用**）：

1. [Termux](https://f-droid.org/packages/com.termux/)
2. [Termux:X11](https://github.com/termux/termux-x11/releases) (取最新 nightly APK)
3. [Termux:API](https://f-droid.org/packages/com.termux.api/)

> 必须三个都来自同一来源（都用 F-Droid，或都用 GitHub），否则会因签名不一致导致互相调用失败。

**Tab S8 设置项**：
- 设置 → 电池和设备维护 → 电池 → 后台使用限制 → **永不休眠的应用** → 加入 Termux 和 Termux:X11
- 否则桌面在锁屏后可能被三星杀掉

## 安装

```bash
# 在 Termux 里执行
git clone https://github.com/huge67/Linux-on-Samsung.git
cd Linux-on-Samsung/proot
bash install.sh
```

安装过程：
- 下载 Debian rootfs (~150 MB)
- 安装 XFCE + 字体 + Firefox (~1.5 GB)
- 总用时 15-30 分钟（取决于网速）
- 总占用 ~3 GB

## 使用

| 命令 | 作用 |
|---|---|
| `tabs8-start` | 启动桌面（自动唤起 Termux:X11 窗口） |
| `tabs8-stop` | 停止桌面，释放资源 |
| `tabs8-uninstall` | 完全卸载（容器 + 脚本 + 元数据） |

### 首次启动

1. 在 Termux 里输入 `tabs8-start`
2. 系统会自动调起 **Termux:X11** 应用，会出现一个黑屏 → 等几秒 XFCE 桌面就会出现
3. 默认用户是 `tab`，免密 sudo

### 切换到 Termux:X11 窗口

如果 Termux:X11 没自动弹出来：
- 从最近任务列表找到 **Termux:X11**，点开即可
- 或从应用抽屉里手动打开

### 关闭桌面

回到 Termux（**新建一个 Termux 会话**，或下拉通知栏切换），执行：
```bash
tabs8-stop
```

## 进阶配置

### 1. 中文输入法（可选）

进入容器后安装 fcitx5 + 拼音：
```bash
tabs8-start                      # 先启动桌面
# 在 XFCE 终端里:
sudo apt install -y fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk4 fcitx5-frontend-gtk3
```
在 `~/.xprofile` 或 `~/.bashrc` 里加：
```bash
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
fcitx5 -d &
```

### 2. GPU 加速（实验性 / Adreno 730）

Tab S8 用骁龙 8 Gen 1 + Adreno 730，理论上支持 Mesa 的 **Turnip** Vulkan 驱动。当前脚本默认用软件渲染（llvmpipe）—— 桌面流畅、看视频没问题，但 3D 应用会卡。

如果你想试 Turnip：
```bash
# 在 Termux 端
pkg install mesa-zink virglrenderer-android

# 启动时加环境变量
export MESA_LOADER_DRIVER_OVERRIDE=zink
export GALLIUM_DRIVER=zink
```
> 这部分稳定性不保证，遇到崩溃就回到默认软件渲染。

### 3. 接 DeX 用大屏

把 Tab S8 接到外接显示器进入 DeX 模式后，**Termux:X11 会自动跟随主屏分辨率** —— 不用改任何配置。建议接显示器后把 XFCE 的 DPI 从 144 调回 96：
```bash
# 在 Debian 桌面终端
xfconf-query -c xsettings -p /Xft/DPI -s 96
```

### 4. 改 apt 源（中国大陆加速）

```bash
sudo sed -i 's|deb.debian.org|mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list.d/debian.sources
sudo apt update
```

## 故障排查

| 现象 | 原因 / 解决 |
|---|---|
| 安装时 `Unable to locate package termux-x11-nightly` | `x11-repo` 加上后 apt 索引没刷新。手动修: `pkg install -y x11-repo && pkg update -y && pkg install -y termux-x11-nightly`。如仍失败, 检查 Termux 是否来自 F-Droid（Google Play 版已废弃） |
| 安装到 [3/4] 报 `未找到 rootfs` | 你的 proot-distro 是新版 (>= 4.x), 容器存到了 `containers/<name>/rootfs/` 而不是 `installed-rootfs/<name>/`。最新脚本已兼容。如还失败: 看 `proot-distro list` 实际 alias, 用 `proot-distro rename <现名> tabs8-debian` 改名后重跑 install.sh |
| `tabs8-start` 后 X11 一直黑屏 | 检查 Termux:X11 应用是否安装、是否被电池优化杀掉 |
| 启动后 XFCE 闪退 | 容器没共享 `/tmp`，确认用的是脚本里的 `--shared-tmp` |
| 中文显示成方块 | 字体没装好，进容器执行 `sudo apt install -y fonts-noto-cjk` |
| 没声音 | Tab S8 端 PulseAudio 没启动，重跑 `tabs8-stop && tabs8-start` |
| 提示 `command not found: tabs8-start` | 重启 Termux，或执行 `source ~/.bashrc`（首次安装会把 `~/bin` 加进 PATH） |
| 安装中途网络中断 | 重新跑 `bash install.sh`，已下载的部分会跳过 |

## 文件结构

```
proot/
├── install.sh         # 主安装脚本（在 Termux 里跑）
├── start.sh           # 启动桌面 → 装到 ~/bin/tabs8-start
├── stop.sh            # 停止桌面 → 装到 ~/bin/tabs8-stop
├── uninstall.sh       # 卸载    → 装到 ~/bin/tabs8-uninstall
├── lib/
│   ├── debian-setup.sh   # 在 Debian 容器内执行的配置
│   └── xstartup.sh       # XFCE 启动脚本（容器内）
└── README.md
```

## 卸载

```bash
tabs8-uninstall
```

会删除：
- proot 容器（约 3 GB）
- `~/bin/tabs8-*` 启动器
- `~/.tabs8-linux/` 元数据目录

**不会**删除 Termux 包（`proot-distro` / `pulseaudio` / `termux-x11-nightly` / `termux-api`），如果你也想清掉：
```bash
pkg uninstall proot-distro pulseaudio termux-x11-nightly termux-api
```

## 与同 repo 的 `setup-hacklab.sh` 的区别

| 维度 | `proot/` 方案（本目录） | `setup-hacklab.sh`（根目录原脚本） |
|---|---|---|
| 隔离性 | 容器化，删干净 | 直接污染 Termux 主环境 |
| 软件包 | apt（Debian 全量）| pkg（Termux 子集）|
| Metasploit | 不预装 | 预装 |
| 卸载 | 一键 | 需手动 |
| 用途 | 通用 Linux 桌面 | 移动渗透实验环境 |

按需选用。本目录适合**纯桌面 / 开发**用途。
