#!/bin/bash
# ============================================================
# 在 Debian 容器内启动 XFCE4 桌面 (手动逐组件)
#
# 关键设计点 (一路趟坑攒的经验):
#   1) 启动前清理残留进程 - 上次会话没退干净时,
#      旧的 xfdesktop / dbus-daemon 会占用根窗口,
#      新启动的 panel 创建的窗口会被覆盖, 看起来像 panel 没出现
#   2) 不用 startxfce4 wrapper, 不用 dbus-launch --exit-with-session
#      (proot 容器无 logind, 嵌套 dbus 会让 xfce4-session 立即退出)
#   3) xfwm4 必须禁用合成器 (proot 无 GPU, 合成器输出空 framebuffer)
#   4) xfdesktop 配置预写, 不用 xfconf-query 后处理 (会卡住)
#   5) xfce4-panel 用极简配置, 不 cp /etc/xdg 的 default.xml
#      (default 含 systray/indicator 等 plugin, 在 proot 加载失败导致
#      panel 启动后立即退出)
#   6) 启动末尾跑 xrefresh 触发 Termux:X11 重绘
# ============================================================

LOG="$HOME/.tabs8-xfce.log"
TMP_LOG="/tmp/tabs8-xfce.log"
exec > >(tee "$LOG" "$TMP_LOG") 2>&1

echo "===== XFCE startup at $(date '+%F %T') ====="
echo "User : $(whoami) (uid=$(id -u))"
echo "Home : $HOME"

# ---------- 0. 清理上次会话残留 ----------
# stop.sh 不一定每次都把容器内进程清干净 (用户直接关 Termux 等情况).
# 旧的 xfdesktop / dbus 占用根窗口时, 新会话画的内容会被它们覆盖.
echo "--- 清理可能存在的残留进程 ---"
pkill -9 -f 'xfwm4|xfdesktop|xfce4-panel|xfsettingsd|xfconfd' 2>/dev/null
pkill -9 -f 'dbus-daemon|dbus-launch'                         2>/dev/null
sleep 2
echo "  清理后剩余 XFCE/dbus 进程:"
pgrep -af 'xfwm|xfdesktop|xfce4-|xfsettings|dbus|xfconf' 2>/dev/null \
    | head -5 || echo "  (无, 干净)"

# ---------- 1. 环境变量 ----------
export DISPLAY=:0
export PULSE_SERVER=tcp:127.0.0.1:4713
export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export _JAVA_AWT_WM_NONREPARENTING=1

export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

XFCONF_DIR="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$XFCONF_DIR"

# ---------- 2. xfwm4 配置 (禁用合成器) ----------
echo "--- 写 xfwm4 配置 ---"
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

# ---------- 3. xfdesktop 配置 (纯色背景, 用 xrandr 取 monitor name) ----------
MONITOR_NAME=$(xrandr 2>/dev/null | awk '/ connected/ {print $1; exit}')
MONITOR_NAME=${MONITOR_NAME:-screen}
echo "--- 写 xfdesktop 配置 (monitor: monitor${MONITOR_NAME}) ---"
cat > "$XFCONF_DIR/xfce4-desktop.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor${MONITOR_NAME}" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="0"/>
          <property name="last-image" type="string" value=""/>
          <property name="color1" type="array">
            <value type="double" value="0.227"/>
            <value type="double" value="0.251"/>
            <value type="double" value="0.333"/>
            <value type="double" value="1.000"/>
          </property>
        </property>
      </property>
    </property>
  </property>
</channel>
XML

# ---------- 4. xfce4-panel 配置 (强制极简) ----------
# 不 cp /etc/xdg/xfce4/panel/default.xml — 那个对 proot 太复杂
# (含 systray / indicator-plugin / status-notifier 等 plugin
# 在容器里因缺少对应 dbus 服务而加载失败, 导致 panel 启动后立即退出)
echo "--- 写 xfce4-panel 配置 (极简: 菜单/任务列表/分隔/时钟) ---"
cat > "$XFCONF_DIR/xfce4-panel.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=7;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="size" type="uint" value="40"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu"/>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="show-handle" type="bool" value="false"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="clock">
      <property name="digital-format" type="string" value="%H:%M"/>
    </property>
  </property>
</channel>
XML

# ---------- 5. 自检 ----------
echo "--- 自检 ---"
echo "  X11 socket:"
ls -la /tmp/.X11-unix/ 2>&1 | head -5

for cmd in dbus-launch xfwm4 xfsettingsd xfdesktop xfce4-panel xset xrefresh; do
    if command -v "$cmd" >/dev/null 2>&1; then
        printf '  %-15s OK\n' "$cmd"
    else
        printf '  %-15s MISSING\n' "$cmd"
    fi
done

if ! xset q >/dev/null 2>&1; then
    echo "  >> X 连接失败. termux-x11 / Termux:X11 应用没起来"
    exit 1
fi
echo "  X 连接 OK"

# ---------- 6. 启动 dbus session daemon ----------
echo "--- 启动 dbus-launch (session) ---"
DBUS_LAUNCH_OUT="$(dbus-launch --sh-syntax 2>&1)"
if [ $? -ne 0 ] || ! echo "$DBUS_LAUNCH_OUT" | grep -q DBUS_SESSION_BUS_ADDRESS; then
    echo "  >> dbus-launch 失败: $DBUS_LAUNCH_OUT"
    exit 1
fi
eval "$DBUS_LAUNCH_OUT"
echo "  DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
echo "  DBUS_SESSION_BUS_PID=$DBUS_SESSION_BUS_PID"
echo "$DBUS_SESSION_BUS_PID" > "$XDG_RUNTIME_DIR/tabs8-dbus.pid"

# ---------- 7. 顺序启动 XFCE 组件 ----------
echo "--- 启动 XFCE 组件 ---"

# 启动序列开始前先把根窗口染成预期颜色 (如果后面 xfdesktop 异常,
# 至少不是黑屏, 可以肉眼分辨"组件起来没")
xsetroot -solid '#3a4055' 2>/dev/null || true
sleep 1

echo "[1] xfwm4 --replace --compositor=off"
xfwm4 --replace --compositor=off 2>&1 &
WMPID=$!
sleep 3

echo "[2] xfsettingsd"
xfsettingsd 2>&1 &
sleep 2

echo "[3] xfdesktop"
xfdesktop 2>&1 &
sleep 3

echo "[4] xfce4-panel"
xfce4-panel 2>&1 &
sleep 3

# ---------- 8. 状态检查 ----------
echo "--- 进程列表 ---"
pgrep -af 'xfwm|xfdesktop|xfce4-panel|xfsettingsd|dbus-daemon' | head -10

echo "--- X 窗口列表 (panel 应该在这里) ---"
xwininfo -root -tree 2>&1 | grep -E '(panel|xfwm|xfdesktop|0x[0-9a-f]+)' \
    | head -10 || echo "  (xwininfo 无输出, 可能未装 x11-utils)"

if ! kill -0 "$WMPID" 2>/dev/null; then
    echo "  >> xfwm4 已死, 桌面无窗口管理器, 退出"
    exit 1
fi

# ---------- 9. 强制刷新 (Termux:X11 首次连接需要触发重绘) ----------
xrefresh 2>/dev/null || true
xsetroot -solid '#3a4055' 2>/dev/null || true

echo
echo "===== XFCE 桌面已启动 ($(date '+%T')) ====="
echo "切到 Termux:X11 应用窗口查看桌面"
echo "等待 xfwm4 (PID $WMPID) 退出..."
echo

wait "$WMPID" 2>/dev/null || true

echo "===== xfwm4 退出 ($(date '+%T')), 清理 ====="
pkill -TERM -f 'xfdesktop|xfce4-panel|xfsettingsd' 2>/dev/null || true
sleep 1
pkill -KILL -f 'xfdesktop|xfce4-panel|xfsettingsd' 2>/dev/null || true

if [ -n "${DBUS_SESSION_BUS_PID:-}" ]; then
    kill "$DBUS_SESSION_BUS_PID" 2>/dev/null || true
fi

echo "===== 清理完成 ====="
