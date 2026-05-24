#!/data/data/com.termux/files/usr/bin/env bash
# ============================================================
# 停止 Tab S8 Linux 桌面
# ============================================================

set -uo pipefail

APP_HOME="$HOME/.tabs8-linux"
if [ ! -f "$APP_HOME/meta" ]; then
    echo "未检测到安装记录, 退出"
    exit 0
fi
# shellcheck source=/dev/null
. "$APP_HOME/meta"

c_info() { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }

c_info "尝试在容器内优雅关闭 XFCE"
proot-distro login "$DISTRO_ALIAS" --user "$DEBIAN_USER" -- bash -lc '
    # 优雅 TERM
    pkill -TERM -f xfwm4         2>/dev/null || true
    pkill -TERM -f xfdesktop     2>/dev/null || true
    pkill -TERM -f xfce4-panel   2>/dev/null || true
    pkill -TERM -f xfsettingsd   2>/dev/null || true
    pkill -TERM -f xfce4-session 2>/dev/null || true
    sleep 1
    # 还活着就 KILL
    pkill -KILL -f xfwm4         2>/dev/null || true
    pkill -KILL -f xfdesktop     2>/dev/null || true
    pkill -KILL -f xfce4-panel   2>/dev/null || true
    pkill -KILL -f xfsettingsd   2>/dev/null || true
    pkill -KILL -f xfce4         2>/dev/null || true
    # dbus session daemon
    if [ -f /tmp/runtime-$(id -u)/tabs8-dbus.pid ]; then
        kill $(cat /tmp/runtime-$(id -u)/tabs8-dbus.pid) 2>/dev/null || true
        rm -f /tmp/runtime-$(id -u)/tabs8-dbus.pid
    fi
    pkill -KILL -f "dbus-daemon.*--session" 2>/dev/null || true
' >/dev/null 2>&1 || true

c_info "停止 Termux 端服务"
pkill -f "termux-x11 :0"  >/dev/null 2>&1 || true
pulseaudio --kill         >/dev/null 2>&1 || true

c_ok "已停止"
