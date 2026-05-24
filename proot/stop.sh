#!/data/data/com.termux/files/usr/bin/env bash
# ============================================================
# 停止 Tab S8 Linux 桌面
# 设计目标: 一定要清干净 (含 dbus / xfconfd 这种容易残留的)
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

c_info "在容器内强制清理所有 XFCE/dbus 进程"
# 用 root 进容器 (不加 --user), 确保权限足够 kill 任何用户的进程
# 直接 -9 KILL, 不走 TERM (XFCE 在 proot 里不响应 TERM 是常事)
proot-distro login "$DISTRO_ALIAS" -- bash -c '
    pkill -9 -f "xfwm4|xfdesktop|xfce4-panel|xfsettingsd|xfconfd" 2>/dev/null
    pkill -9 -f "dbus-daemon|dbus-launch"                          2>/dev/null
    rm -f /tmp/runtime-*/tabs8-dbus.pid                            2>/dev/null
    sleep 1
    # 报告
    REMAIN=$(pgrep -af "xfwm|xfdesktop|xfce4-|xfsettings|dbus|xfconf" 2>/dev/null)
    if [ -n "$REMAIN" ]; then
        echo "  >> 仍有残留:"
        echo "$REMAIN" | head -5
    fi
' >/dev/null 2>&1 || true

c_info "停止 Termux 端 X11 / PulseAudio"
pkill -9 -f "termux-x11"  2>/dev/null || true
pulseaudio --kill         2>/dev/null || true

c_ok "已停止"
