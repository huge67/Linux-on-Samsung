#!/data/data/com.termux/files/usr/bin/env bash
# ============================================================
# 启动 Tab S8 Linux 桌面
# 顺序: 清理旧进程 -> PulseAudio -> Termux-X11 -> XFCE
# ============================================================

set -euo pipefail

# ---------- 读取元数据 ----------
APP_HOME="$HOME/.tabs8-linux"
if [ ! -f "$APP_HOME/meta" ]; then
    echo "错误: 未检测到安装记录 ($APP_HOME/meta)"
    echo "请先执行 install.sh"
    exit 1
fi
# shellcheck source=/dev/null
. "$APP_HOME/meta"

DISPLAY_NUM=":0"
PULSE_PORT=4713

c_info() { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }

# ---------- 1. 终止可能存在的旧进程 ----------
c_info "清理旧的 X11 / PulseAudio 进程"
pkill -f "termux-x11 ${DISPLAY_NUM}"  >/dev/null 2>&1 || true
pulseaudio --kill                     >/dev/null 2>&1 || true
sleep 1

# ---------- 2. 启动 PulseAudio ----------
c_info "启动 PulseAudio (端口 ${PULSE_PORT})"
pulseaudio --start \
    --load="module-native-protocol-tcp port=${PULSE_PORT} auth-ip-acl=127.0.0.1 auth-anonymous=1" \
    --exit-idle-time=-1
c_ok "PulseAudio 已启动"

# ---------- 3. 启动 Termux-X11 服务器 ----------
c_info "启动 Termux-X11 服务器"
# nohup 方式后台运行, 输出丢弃
nohup termux-x11 ${DISPLAY_NUM} >/dev/null 2>&1 &
sleep 2

# 自动唤起 Termux:X11 应用窗口 (需要 termux-api)
if command -v am >/dev/null 2>&1; then
    am start --user 0 \
        -n com.termux.x11/.MainActivity \
        >/dev/null 2>&1 || \
        c_info "提示: 请手动从应用列表打开 Termux:X11"
fi

c_ok "Termux-X11 已就绪 (DISPLAY=${DISPLAY_NUM})"

# ---------- 4. 进入 Debian 容器, 启动 XFCE ----------
c_info "进入 Debian 容器并启动 XFCE..."
echo
echo "  提示: 桌面运行后, 在 Termux:X11 应用窗口中查看"
echo "  关闭桌面: 在新的 Termux 会话执行 'tabs8-stop'"
echo

# --shared-tmp: 让 Debian 容器和 Termux 共享 /tmp
#               这样 PulseAudio 套接字 (如果有) 可见, 也方便文件传递
# --user:       以普通用户身份登录, 而不是 root
exec proot-distro login "$DISTRO_ALIAS" \
    --user "$DEBIAN_USER" \
    --shared-tmp \
    -- bash -lc "/home/$DEBIAN_USER/.local/bin/xstartup"
