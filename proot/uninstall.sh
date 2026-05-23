#!/data/data/com.termux/files/usr/bin/env bash
# ============================================================
# 卸载 Tab S8 Linux 桌面
# 删除: proot 容器 + 启动脚本 + 元数据
# 不会删: pkg 安装的 termux 包 (proot-distro / pulseaudio / termux-x11-nightly)
#         需要时用户自行 'pkg uninstall'
# ============================================================

set -uo pipefail

APP_HOME="$HOME/.tabs8-linux"
BIN_DIR="$HOME/bin"

c_info() { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

if [ ! -f "$APP_HOME/meta" ]; then
    c_warn "未检测到安装记录, 没什么可卸载的"
    exit 0
fi
# shellcheck source=/dev/null
. "$APP_HOME/meta"

cat <<EOF

==== 卸载 Tab S8 Linux 桌面 ====

将删除以下内容:
  1. proot-distro 容器: ${DISTRO_ALIAS}  (~3-5 GB)
  2. 启动器: ${BIN_DIR}/tabs8-start, tabs8-stop, tabs8-uninstall
  3. 元数据: ${APP_HOME}

不会自动删除的内容 (Termux 主环境保持干净, 但 pkg 装的包还在):
  - proot-distro / pulseaudio / termux-x11-nightly / termux-api
  - 如需删除请自行: pkg uninstall <包名>

EOF

read -rp "确认卸载？输入 'yes' 继续: " confirm
if [ "$confirm" != "yes" ]; then
    echo "已取消"
    exit 0
fi

# 1. 停止运行中的进程
c_info "停止运行中的服务"
pkill -f "termux-x11 :0"  >/dev/null 2>&1 || true
pulseaudio --kill         >/dev/null 2>&1 || true

# 2. 删除 proot 容器
c_info "删除容器 ${DISTRO_ALIAS}"
if proot-distro list --installed 2>/dev/null | grep -q "$DISTRO_ALIAS"; then
    proot-distro remove "$DISTRO_ALIAS"
    c_ok "容器已删除"
else
    c_warn "容器 ${DISTRO_ALIAS} 已不存在"
fi

# 3. 删除启动器
c_info "删除启动器"
rm -f "$BIN_DIR/tabs8-start" "$BIN_DIR/tabs8-stop" "$BIN_DIR/tabs8-uninstall"

# 4. 删除元数据
rm -rf "$APP_HOME"

c_ok "卸载完成"
echo
echo "如需彻底清理, 可执行:"
echo "  pkg uninstall proot-distro pulseaudio termux-x11-nightly termux-api"
