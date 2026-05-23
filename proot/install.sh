#!/data/data/com.termux/files/usr/bin/env bash
# ============================================================
# Galaxy Tab S8 - Linux 桌面安装脚本
# 方案: proot-distro (Debian 12) + XFCE4 + Termux-X11
# 设计目标: 干净、可卸载、不污染 Termux 主环境
# ============================================================

set -euo pipefail

# ---------- 配置 ----------
# 注意: DISTRO_ALIAS 不用 readonly, 因为旧版 proot-distro 不支持自定义 alias 时
#       会退化到默认名 'debian', 此变量需要可改
DISTRO_ALIAS="tabs8-debian"
readonly DEBIAN_USER="tab"
readonly APP_HOME="$HOME/.tabs8-linux"
readonly BIN_DIR="$HOME/bin"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# proot-distro 的两套存储路径 (新旧版兼容)
readonly PD_ROOT_NEW="$PREFIX/var/lib/proot-distro/containers"        # >= 4.x
readonly PD_ROOT_OLD="$PREFIX/var/lib/proot-distro/installed-rootfs"  # legacy

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

    # 1) x11-repo 必须先单独安装并 pkg update, 否则 apt 索引看不到 termux-x11-nightly
    c_info "添加 x11-repo (Termux:X11 所在仓库)"
    pkg install -y x11-repo
    pkg update -y

    # 2) 主仓库的依赖
    c_info "安装核心依赖 (proot-distro / pulseaudio / termux-api)"
    pkg install -y \
        proot-distro \
        pulseaudio \
        termux-api \
        curl \
        wget

    # 3) Termux:X11 单独装, 失败时给出可执行的修复提示
    c_info "安装 Termux:X11 服务器 (termux-x11-nightly)"
    if ! pkg install -y termux-x11-nightly; then
        c_err "termux-x11-nightly 安装失败. 可能原因:"
        c_err "  1) Termux 来自 Google Play (已废弃, 包源停更)"
        c_err "     -> 卸载后从 F-Droid 重装: https://f-droid.org/packages/com.termux/"
        c_err "  2) 网络问题导致 x11-repo 索引未拉取"
        c_err "     -> 配好代理后, 手动: pkg update && pkg install termux-x11-nightly"
        c_err "  3) 架构不支持 (本包仅 aarch64/arm)"
        c_err "     -> 当前架构: $(dpkg --print-architecture 2>/dev/null || echo unknown)"
        exit 1
    fi

    c_ok "Termux 端依赖安装完成"
}

# ---------- 工具: 找出指定 alias 的 rootfs 路径 (兼容新旧布局) ----------
locate_rootfs() {
    local alias_name="$1"
    local candidates=(
        "$PD_ROOT_NEW/$alias_name/rootfs"   # 新版: containers/<name>/rootfs/
        "$PD_ROOT_OLD/$alias_name"          # 旧版: installed-rootfs/<name>/
    )
    for cand in "${candidates[@]}"; do
        if [ -d "$cand" ] && [ -f "$cand/etc/os-release" -o -f "$cand/etc/debian_version" ]; then
            echo "$cand"
            return 0
        fi
        # 即使没有 os-release, 只要目录存在且非空也算 (rootfs 可能尚未初始化完)
        if [ -d "$cand" ] && [ -n "$(ls -A "$cand" 2>/dev/null)" ]; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

# ---------- 安装 Debian 容器 ----------
install_debian() {
    step "[2/4] 安装 Debian 容器"

    # 已经装好就跳过
    if proot-distro list 2>/dev/null | grep -qw "$DISTRO_ALIAS"; then
        c_warn "容器 '$DISTRO_ALIAS' 已存在，跳过下载"
        return 0
    fi

    # 探测 proot-distro 命令风格
    local install_help
    install_help="$(proot-distro install --help 2>&1 || true)"

    if echo "$install_help" | grep -q -- '--name'; then
        # 新版 (>= 4.x): 用 --name 起 alias
        c_info "使用新版 proot-distro 命令: install debian --name $DISTRO_ALIAS"
        proot-distro install debian --name "$DISTRO_ALIAS"

    elif echo "$install_help" | grep -q -- '--override-alias'; then
        # 旧版: 用 --override-alias 起 alias
        c_info "使用旧版 proot-distro 命令: install debian --override-alias $DISTRO_ALIAS"
        proot-distro install debian --override-alias "$DISTRO_ALIAS"

    else
        # 极个别版本既不支持也不识别, 退化为默认 alias 'debian'
        c_warn "你的 proot-distro 既不支持 --name 也不支持 --override-alias"
        c_warn "退化为默认 alias = 'debian' (会和你已有的 debian 容器共用)"
        if proot-distro list 2>/dev/null | grep -qw "debian"; then
            c_warn "已有 'debian' 容器, 复用 (将在其上叠加 XFCE 配置)"
            read -rp "继续？(yes/N) " ans
            [ "$ans" = "yes" ] || exit 1
        else
            proot-distro install debian
        fi
        DISTRO_ALIAS="debian"
    fi

    c_ok "Debian 容器安装完成 (alias=$DISTRO_ALIAS)"
}

# ---------- 在 Debian 内执行配置 ----------
configure_debian() {
    step "[3/4] 配置 Debian (XFCE + 中文 + 用户)"

    local rootfs
    if ! rootfs="$(locate_rootfs "$DISTRO_ALIAS")"; then
        c_err "未找到 rootfs. 已检查的位置:"
        c_err "  - $PD_ROOT_NEW/$DISTRO_ALIAS/rootfs   (新版布局)"
        c_err "  - $PD_ROOT_OLD/$DISTRO_ALIAS          (旧版布局)"
        c_err ""
        c_err "诊断信息: proot-distro list 输出"
        proot-distro list 2>&1 | sed 's/^/    /' >&2 || true
        c_err ""
        c_err "可能的修复:"
        c_err "  1) 容器装到了别名 'debian' 而非 '$DISTRO_ALIAS'"
        c_err "     -> proot-distro rename debian $DISTRO_ALIAS    (新版有 rename)"
        c_err "     -> 或: proot-distro remove debian; 重跑 install.sh"
        c_err "  2) 上一步 proot-distro install 实际失败了"
        c_err "     -> 重跑: proot-distro install debian --name $DISTRO_ALIAS"
        exit 1
    fi
    c_info "rootfs 位置: $rootfs"

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
