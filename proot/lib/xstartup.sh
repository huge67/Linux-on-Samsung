#!/bin/bash
# ============================================================
# 在 Debian 容器内启动 XFCE4 桌面 (手动逐组件)
#
# 不使用 startxfce4 wrapper, 也不用 'dbus-launch --exit-with-session':
# 这套组合在 proot 容器里会因为 logind 缺失 / dbus 嵌套导致
# xfce4-session daemonize 后整条链立即退出, 表现为黑屏.
#
# 改为:
#   1) 用 'dbus-launch --sh-syntax' 启动 dbus session daemon
#   2) 顺序启动 xfwm4 / xfsettingsd / xfdesktop / xfce4-panel
#   3) wait 在 xfwm4 上, 这样桌面退出时主脚本才退出
# ============================================================

LOG="$HOME/.tabs8-xfce.log"
TMP_LOG="/tmp/tabs8-xfce.log"

# 同时写到家目录和共享 /tmp, 方便从 Termux 端 cat
exec > >(tee "$LOG" "$TMP_LOG") 2>&1

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

# ---------- 关键: 禁用 xfwm4 合成器 ----------
# proot 容器没真正的 GPU 加速, OpenGL 合成器输出空 framebuffer = 黑屏
# (xfwm4 进程仍活着, 但屏幕全黑, 是 termux-x11 + xfwm4 最经典的坑)
echo "--- 写入 xfwm4 配置 (禁用合成器) ---"
XFCONF_DIR="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$XFCONF_DIR"
cat > "$XFCONF_DIR/xfwm4.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="theme" type="string" value="Default"/>
    <property name="title_font" type="string" value="Sans Bold 9"/>
    <property name="button_layout" type="string" value="O|HMC"/>
  </property>
</channel>
XML
echo "  写入: $XFCONF_DIR/xfwm4.xml"

# ---------- 自检 ----------
echo "--- env (筛选) ---"
env | grep -E '^(DISPLAY|XDG_|LANG|LC_|PULSE_|DBUS_)' | sort

echo "--- X11 socket (/tmp/.X11-unix) ---"
ls -la /tmp/.X11-unix/ 2>&1 | head -5 || echo "  目录不存在!"

echo "--- 关键命令是否就绪 ---"
ALL_OK=1
for cmd in dbus-launch dbus-daemon xfwm4 xfsettingsd xfdesktop xfce4-panel xset; do
    if command -v "$cmd" >/dev/null 2>&1; then
        printf '  %-20s OK  (%s)\n' "$cmd" "$(command -v "$cmd")"
    else
        printf '  %-20s MISSING\n' "$cmd"
        ALL_OK=0
    fi
done
if [ "$ALL_OK" -eq 0 ]; then
    echo "  >> 缺少组件, 请进容器执行: sudo apt install -y xfce4 xfce4-terminal dbus-x11"
fi

echo "--- X server 连通性 (xset q) ---"
if ! xset q 2>&1 | head -3; then
    echo "  >> X 连接失败. 检查 termux-x11 / Termux:X11 应用"
    exit 1
fi

# ---------- 启动 dbus session daemon ----------
# --sh-syntax: 输出 'export DBUS_SESSION_BUS_ADDRESS=...; export DBUS_SESSION_BUS_PID=...'
# eval 把变量导入当前 shell, 后续子进程继承
echo "--- 启动 dbus-launch (session) ---"
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    DBUS_LAUNCH_OUT="$(dbus-launch --sh-syntax 2>&1)"
    if [ $? -ne 0 ] || ! echo "$DBUS_LAUNCH_OUT" | grep -q DBUS_SESSION_BUS_ADDRESS; then
        echo "  >> dbus-launch 失败:"
        echo "$DBUS_LAUNCH_OUT"
        exit 1
    fi
    eval "$DBUS_LAUNCH_OUT"
    echo "  DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
    echo "  DBUS_SESSION_BUS_PID=$DBUS_SESSION_BUS_PID"
    # 记录 PID 给 stop.sh 用
    echo "$DBUS_SESSION_BUS_PID" > "$XDG_RUNTIME_DIR/tabs8-dbus.pid"
fi

# ---------- 顺序启动 XFCE 组件 ----------
echo "--- 启动 XFCE 组件 ---"

# 在 xfwm4 接管前, 先把根窗口染色, 提供视觉反馈
# (如果 Termux:X11 窗口能看到这个颜色, 说明 X 渲染本身没问题)
xsetroot -solid '#3a4055' 2>/dev/null || true

echo "[start] xfwm4 --replace --compositor=off"
# --compositor=off: 命令行强制关合成器, 双保险 (xfwm4 4.16+)
xfwm4 --replace --compositor=off 2>&1 &
WMPID=$!
sleep 2

echo "[start] xfsettingsd"
xfsettingsd 2>&1 &
sleep 1

echo "[start] xfdesktop"
xfdesktop 2>&1 &
sleep 1

echo "[start] xfce4-panel"
xfce4-panel 2>&1 &
sleep 2

echo "--- 进程列表 (XFCE) ---"
ps -eo pid,comm 2>/dev/null | grep -E 'xfwm|xfdesktop|xfce4-|xfsettings|dbus' \
    | grep -v grep || echo "  (没有 xfce 相关进程, 启动失败)"

# 检查窗口管理器是否还活着
if ! kill -0 "$WMPID" 2>/dev/null; then
    echo "  >> xfwm4 已死 (PID $WMPID 不存在)"
    echo "  >> 请检查日志中 [start] xfwm4 后面是否有错误信息"
    exit 1
fi

echo
echo "===== XFCE 桌面已启动 ($(date '+%T')) ====="
echo "切到 Termux:X11 应用窗口查看桌面"
echo "正在等待 xfwm4 (PID $WMPID) 退出 ..."
echo

# wait 在窗口管理器上, 它退出代表桌面会话结束
wait "$WMPID" 2>/dev/null || true

echo "===== xfwm4 退出 ($(date '+%T')), 清理 ====="

# 清理其他组件
pkill -TERM -f xfdesktop    2>/dev/null || true
pkill -TERM -f xfce4-panel  2>/dev/null || true
pkill -TERM -f xfsettingsd  2>/dev/null || true

# 关掉 dbus session daemon
if [ -n "${DBUS_SESSION_BUS_PID:-}" ]; then
    kill "$DBUS_SESSION_BUS_PID" 2>/dev/null || true
fi

echo "===== 清理完成 ====="
