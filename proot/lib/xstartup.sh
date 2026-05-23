#!/bin/bash
# ============================================================
# 在 Debian 容器内启动 XFCE4 桌面
# 由 Termux 端 start.sh 通过 proot-distro login 调用
# ============================================================

# 显示输出到 Termux:X11
export DISPLAY=:0

# 从 Termux 端 PulseAudio 走 TCP
export PULSE_SERVER=tcp:127.0.0.1:4713

# 必要的运行时目录
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# 解决 GTK / 图形库相关警告
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export _JAVA_AWT_WM_NONREPARENTING=1

# 中文 locale (前提是 setup 时 locale-gen 过)
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

# 启动 dbus 会话并执行 XFCE
# 用 dbus-launch 包一层，确保桌面下应用能正常通信
exec dbus-launch --exit-with-session startxfce4
