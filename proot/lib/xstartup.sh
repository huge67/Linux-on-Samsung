#!/bin/bash
# ============================================================
# 在 Debian 容器内启动 XFCE4 桌面
# 由 Termux 端 start.sh 通过 proot-distro login 调用
#
# 黑屏排查: 所有输出 (含错误) 重定向到 ~/.tabs8-xfce.log
#           启动失败时可在容器内或宿主端查看
# ============================================================

LOG="$HOME/.tabs8-xfce.log"
# 同时把日志拷到 /tmp, 方便从 Termux 端访问 (--shared-tmp 已绑定)
TMP_LOG="/tmp/tabs8-xfce.log"

# 重定向 stdout/stderr 到日志文件 (保留 tee 输出到 /tmp 那份)
exec > >(tee "$TMP_LOG") 2>&1
echo "===== XFCE startup at $(date '+%F %T') ====="
echo "User : $(whoami) (uid=$(id -u))"
echo "Home : $HOME"

# ---------- 环境变量 ----------
export DISPLAY=:0
export PULSE_SERVER=tcp:127.0.0.1:4713
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export _JAVA_AWT_WM_NONREPARENTING=1

# 中文 locale (前提是 setup 时 locale-gen 过)
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

# ---------- 启动前自检 ----------
echo "--- env (筛选) ---"
env | grep -E '^(DISPLAY|XDG_|LANG|LC_|PULSE_)' | sort

echo "--- X11 socket (/tmp/.X11-unix) ---"
ls -la /tmp/.X11-unix/ 2>&1 | head -5 || echo "  目录不存在!"

echo "--- 关键命令是否就绪 ---"
for cmd in dbus-launch startxfce4 xfce4-session xset; do
    if command -v "$cmd" >/dev/null 2>&1; then
        printf '  %-20s OK  (%s)\n' "$cmd" "$(command -v "$cmd")"
    else
        printf '  %-20s MISSING\n' "$cmd"
    fi
done

echo "--- X server 连通性 (xset q) ---"
if command -v xset >/dev/null 2>&1; then
    xset q 2>&1 | head -5 || echo "  X 连接失败. 检查 termux-x11 是否启动 / Termux:X11 应用是否打开"
else
    echo "  xset 命令不存在, 跳过 (可装: sudo apt install -y x11-xserver-utils)"
fi

# ---------- 启动 XFCE ----------
echo "--- 启动 dbus + startxfce4 ($(date '+%T')) ---"

# 同时把日志保存一份(已通过 tee 写到 $TMP_LOG)
# 这里再用 cp 拷贝纯净版本到 ~/.tabs8-xfce.log (HOME 持久)
cp "$TMP_LOG" "$LOG" 2>/dev/null || true

exec dbus-launch --exit-with-session startxfce4
