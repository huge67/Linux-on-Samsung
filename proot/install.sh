#!/data/data/com.termux/files/usr/bin/env bash
# ============================================================
# Galaxy Tab S8 - Linux 桌面安装脚本
# 方案: proot-distro (Debian 12) + XFCE4 + Termux-X11
# 设计目标: 干净、可卸载、不污染 Termux 主环境
# ============================================================

set -euo pipefail

# ---------- 配置 ----------
readonly DISTRO_ALIAS="tabs8-debian"
readonly DEBIAN_USER="tab"
readonly APP_HOME="$HOME/.tabs8-linux"
readonly BIN_DIR="$HOME/bin"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- 颜色输出 ----------
c_info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
c_ok()    { printf '\033[1;32m[ OK ]\033[0m  %s\n' "$*"; }
c_warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
c_err()   { printf '\033[1;31m[ERR ]\033[0m  %s\n' "$*" >&2; }

step() {
    printf '\n\033[1;36m==> %s\033[0m\n' "$*"
}

# ---------- 前置检查 ----------
preflight_checks() {
    step "前置检查"

    if [ ! -d /data/data/com.termux/files/usr ]; then
        c_err "请在 Termux (F-Droid 版) 中运行此脚本"
        exit 1
    fi
    c_ok "Termux 环境检测通过"

    # 网络
    if ! curl -sfI https://deb.debian.org > /dev/null 2>&1; then
        c_warn "无法访问 deb.debian.org，安装过程中可能下载失败"
    else
        c_ok "网络可达"
    fi

    # 存储空间 (至少需要 5GB)
    local avail_kb
    avail_kb=$(df -k "$HOME" | awk 'NR==2 {print $4}')
    local avail_gb=$((avail_kb / 1024 / 1024))
    if [ "$avail_gb" -lt 5 ]; then
        c_warn "可用空间仅 ${avail_gb} GB，建议至少 5 GB"
        read -rp "继续？(yes/N) " ans
        [ "$ans" = "yes" ] || exit 1
    else
        c_ok "可用空间 ${avail_gb} GB"
    fi
}

# ---------- 安装 Termux 端依赖 ----------
install_termux_deps() {
    step "[1/4] 更新 Termux 并安装依赖"

    pkg update -y
    pkg upgrade -y

    # 必装包
    pkg install -y \
        proot-distro \
        pulseaudio \
        x11-repo \
        termux-x11-nightly \
        termux-api \
        curl \
        wget

    c_ok "Termux 端依赖安装完成"
}

# ---------- 安装 Debian 容器 ----------
install_debian() {
    step "[2/4] 安装 Debian 容器"

    if proot-distro list --installed 2>/dev/null | grep -q "$DISTRO_ALIAS"; then
        c_warn "容器 '$DISTRO_ALIAS' 已存在，跳过下载"
        return 0
    fi

    # 用 alias 而不是默认名，方便和别的 Debian 容器共存
    proot-distro install debian --override-alias "$DISTRO_ALIAS"

    c_ok "Debian 容器安装完成"
}

# ---------- 在 Debian 内执行配置 ----------
configure_debian() {
    step "[3/4] 配置 Debian (XFCE + 中文 + 用户)"

    local rootfs="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO_ALIAS"

    if [ ! -d "$rootfs" ]; then
        c_err "未找到 rootfs: $rootfs"
        exit 1
    fi

    # 拷贝配置脚本到容器内 /root/
    cp "$SCRIPT_DIR/lib/debian-setup.sh" "$rootfs/root/setup.sh"
    cp "$SCRIPT_DIR/lib/xstartup.sh"     "$rootfs/root/xstartup.sh"
    chmod +x "$rootfs/root/setup.sh" "$rootfs/root/xstartup.sh"

    # 把用户名传进去
    proot-distro login "$DISTRO_ALIAS" -- \
        env DEBIAN_USER="$DEBIAN_USER" bash /root/setup.sh

    c_ok "Debian 配置完成"
}

# ---------- 部署 Termux 端启动器 ----------
deploy_launchers() {
    step "[4/4] 部署启动/停止/卸载脚本"

    mkdir -p "$BIN_DIR" "$APP_HOME"

    # 拷贝并改名 (加 tabs8- 前缀避免污染命名空间)
    install -m 755 "$SCRIPT_DIR/start.sh"     "$BIN_DIR/tabs8-start"
    install -m 755 "$SCRIPT_DIR/stop.sh"      "$BIN_DIR/tabs8-stop"
    install -m 755 "$SCRIPT_DIR/uninstall.sh" "$BIN_DIR/tabs8-uninstall"

    # 元数据 (用于 uninstall 时识别本工具装的内容)
    cat > "$APP_HOME/meta" <<EOF
DISTRO_ALIAS=$DISTRO_ALIAS
DEBIAN_USER=$DEBIAN_USER
INSTALLED_AT=$(date -Iseconds)
INSTALLED_VERSION=1.0.0
EOF

    # 确保 ~/bin 在 PATH 里
    if ! grep -q 'PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
        c_warn "已把 ~/bin 加入 PATH，请重启 Termux 或执行: source ~/.bashrc"
    fi

    c_ok "启动器部署完成"
}

# ---------- 主流程 ----------
main() {
    cat <<'BANNER'
============================================================
  Galaxy Tab S8 - Linux 桌面安装器
  Debian 12 + XFCE4 + Termux-X11
============================================================
BANNER

    preflight_checks
    install_termux_deps
    install_debian
    configure_debian
    deploy_launchers

    cat <<EOF

============================================================
  安装完成
============================================================

启动桌面:  tabs8-start
停止桌面:  tabs8-stop
卸载:      tabs8-uninstall

首次启动后请参考 README.md 的"首次使用"章节配置 Termux:X11 应用。

EOF
}

main "$@"
