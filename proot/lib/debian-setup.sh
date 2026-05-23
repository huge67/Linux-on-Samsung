#!/bin/bash
# ============================================================
# 在 Debian 容器内执行的配置脚本
# 由 install.sh 通过 proot-distro login 调用
# ============================================================

set -euo pipefail

# 来自外部的环境变量
USER_NAME="${DEBIAN_USER:-tab}"

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8

log() { printf '  -> %s\n' "$*"; }

# ---------- 1. 系统更新 ----------
log "更新 apt 索引"
apt-get update -qq
apt-get upgrade -y -qq

# ---------- 2. 基础工具 ----------
log "安装基础工具"
apt-get install -y --no-install-recommends \
    sudo nano vim curl wget git ca-certificates \
    locales tzdata \
    procps psmisc less \
    dbus-x11

# ---------- 3. Locale (中英双语) ----------
log "配置 locale (en_US + zh_CN UTF-8)"
sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen
sed -i 's/^# *\(zh_CN.UTF-8\)/\1/' /etc/locale.gen
locale-gen >/dev/null
update-locale LANG=en_US.UTF-8

# 时区: 默认 Asia/Shanghai (用户可自行 dpkg-reconfigure tzdata 修改)
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone

# ---------- 4. 创建普通用户 ----------
log "创建用户 '$USER_NAME' (免密 sudo)"
if ! id "$USER_NAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USER_NAME"
    # 不设密码 (proot 内无密码也能用)
    passwd -d "$USER_NAME" >/dev/null
fi
echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-"$USER_NAME"
chmod 440 /etc/sudoers.d/90-"$USER_NAME"

# ---------- 5. XFCE4 桌面 (精简版) ----------
log "安装 XFCE4 桌面环境"
apt-get install -y --no-install-recommends \
    xfce4-session \
    xfce4-panel \
    xfwm4 \
    xfdesktop4 \
    xfce4-settings \
    xfce4-terminal \
    xfce4-taskmanager \
    thunar \
    mousepad \
    ristretto \
    xorg \
    xinit

# 不装 xfce4-goodies (太重，包含一堆插件)

# ---------- 6. 中文字体 ----------
log "安装中文字体"
apt-get install -y --no-install-recommends \
    fonts-noto-cjk \
    fonts-wqy-microhei \
    fonts-wqy-zenhei \
    fonts-noto-color-emoji

# ---------- 7. 常用图形软件 ----------
log "安装 Firefox-ESR"
apt-get install -y --no-install-recommends firefox-esr || \
    log "Firefox 安装失败 (可能架构不支持)，跳过"

# ---------- 8. 部署用户脚本 ----------
log "部署用户启动脚本"
USER_HOME="/home/$USER_NAME"
install -d -m 755 -o "$USER_NAME" -g "$USER_NAME" \
    "$USER_HOME/.local/bin" \
    "$USER_HOME/.config/xfce4"

install -m 755 -o "$USER_NAME" -g "$USER_NAME" \
    /root/xstartup.sh "$USER_HOME/.local/bin/xstartup"

# ---------- 9. XFCE 默认设置 ----------
log "应用 XFCE 默认设置 (DPI / 主题 / 字体)"
# Tab S8 屏幕 274 ppi, 默认 DPI 设到 144 (~1.5x 缩放) 触屏更友好
mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
cat > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Xft" type="empty">
    <property name="DPI" type="int" value="144"/>
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Adwaita"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Noto Sans CJK SC 11"/>
    <property name="MonospaceFontName" type="string" value="Noto Sans Mono CJK SC 11"/>
    <property name="CursorThemeSize" type="int" value="32"/>
  </property>
</channel>
XML
chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.config"

# ---------- 10. 清理 ----------
log "清理 apt 缓存 (节省空间)"
apt-get autoremove -y -qq
apt-get clean
rm -rf /var/lib/apt/lists/*

log "Debian 容器配置完成"
