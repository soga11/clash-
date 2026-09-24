#!/usr/bin/env bash
set -Eeuo pipefail
#!/bin/sh
set -eu

PORT=52016
PASSWORD='sogasogasoga'
METHOD='aes-128-gcm'
MODE='tcp_and_udp'
BIN='/usr/local/bin/ssserver'
CONF_DIR='/etc/shadowsocks-rust'
CONF_FILE="$CONF_DIR/config.json"
SERVICE_FILE='/etc/systemd/system/shadowsocks-rust.service'
OPENRC_FILE='/etc/init.d/shadowsocks-rust'
PASS='sogasogasoga'
CONF=/etc/shadowsocks-rust/config.json
BIN=/usr/local/bin/ssserver

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo '请使用 root 权限运行'; exit 1; }
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  INIT_SYSTEM='systemd'
elif command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
  INIT_SYSTEM='openrc'
else
  echo '不支持的服务管理器（需要 systemd 或 OpenRC）'
  exit 1
fi
[ "$(id -u)" = 0 ] || { echo '请使用 root 运行'; exit 1; }

if command -v apt-get >/dev/null 2>&1; then
if command -v apk >/dev/null; then
  apk add --no-cache curl xz ca-certificates
elif command -v apt-get >/dev/null; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl xz-utils ca-certificates
elif command -v dnf >/dev/null 2>&1; then
elif command -v dnf >/dev/null; then
  dnf install -y curl xz ca-certificates
elif command -v yum >/dev/null 2>&1; then
elif command -v yum >/dev/null; then
  yum install -y curl xz ca-certificates
elif command -v apk >/dev/null 2>&1; then
  apk add --no-cache curl xz ca-certificates
else
  echo '不支持的包管理器（需要 apt、dnf 或 yum）'
  exit 1
  echo '不支持此系统'; exit 1
fi

case "$(uname -m)" in
  x86_64|amd64) ASSET_ARCH='x86_64-unknown-linux-musl' ;;
  aarch64|arm64) ASSET_ARCH='aarch64-unknown-linux-musl' ;;
  armv7l|armhf) ASSET_ARCH='armv7-unknown-linux-musleabihf' ;;
  i386|i686) ASSET_ARCH='i686-unknown-linux-musl' ;;
  *) echo "不支持的 CPU 架构：$(uname -m)"; exit 1 ;;
  x86_64|amd64) A=x86_64-unknown-linux-musl ;;
  aarch64|arm64) A=aarch64-unknown-linux-musl ;;
  armv7l|armhf) A=armv7-unknown-linux-musleabihf ;;
  i386|i686) A=i686-unknown-linux-musl ;;
  *) echo '不支持此架构'; exit 1 ;;
esac

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
V=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/shadowsocks/shadowsocks-rust/releases/latest)
V=${V##*/}
U="https://github.com/shadowsocks/shadowsocks-rust/releases/download/$V/shadowsocks-$V.$A.tar.xz"
curl -fL --retry 3 -o "$T/ss.tar.xz" "$U"
tar -xJf "$T/ss.tar.xz" -C "$T" ssserver
install -m755 "$T/ssserver" "$BIN"

LATEST_URL=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
  https://github.com/shadowsocks/shadowsocks-rust/releases/latest)
VERSION=${LATEST_URL##*/}
[[ $VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo '无法获取最新版本号'; exit 1; }

ARCHIVE="shadowsocks-${VERSION}.${ASSET_ARCH}.tar.xz"
DOWNLOAD_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${VERSION}/${ARCHIVE}"
echo "正在安装 Shadowsocks-Rust ${VERSION} ..."
curl -fL --retry 3 --connect-timeout 10 -o "$TMP_DIR/$ARCHIVE" "$DOWNLOAD_URL"
tar -xJf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR" ssserver
"$TMP_DIR/ssserver" --help 2>&1 | grep -q 'aes-128-gcm' || { echo '下载的版本不支持 aes-128-gcm'; exit 1; }
install -m 0755 "$TMP_DIR/ssserver" "$BIN"

install -d -m 0755 "$CONF_DIR"
cat >"$CONF_FILE" <<EOF
{
  "server": "0.0.0.0",
  "server_port": $PORT,
  "password": "$PASSWORD",
  "method": "$METHOD",
  "mode": "$MODE"
}
mkdir -p "$(dirname "$CONF")"
cat > "$CONF" <<EOF
{"server":"0.0.0.0","server_port":$PORT,"password":"$PASS","method":"aes-128-gcm","mode":"tcp_and_udp"}
EOF
chmod 600 "$CONF_FILE"
chmod 600 "$CONF"

if [[ $INIT_SYSTEM == 'systemd' ]]; then
cat >"$SERVICE_FILE" <<'EOF'
if command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then
  cat > /etc/systemd/system/shadowsocks-rust.service <<'EOF'
[Unit]
Description=Shadowsocks-Rust Server
After=network-online.target
Wants=network-online.target

Description=Shadowsocks-Rust
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks-rust/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

Restart=always
[Install]
WantedBy=multi-user.target
EOF
else
cat >"$OPENRC_FILE" <<'EOF'
  systemctl daemon-reload
  systemctl enable --now shadowsocks-rust
elif command -v rc-update >/dev/null; then
  cat > /etc/init.d/shadowsocks-rust <<'EOF'
#!/sbin/openrc-run
name="Shadowsocks-Rust Server"
command="/usr/local/bin/ssserver"
command=/usr/local/bin/ssserver
command_args="-c /etc/shadowsocks-rust/config.json"
command_background="yes"
pidfile="/run/shadowsocks-rust.pid"

depend() {
  need net
}
command_background=yes
pidfile=/run/shadowsocks-rust.pid
depend() { need net; }
EOF
chmod 755 "$OPENRC_FILE"
fi

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q 'Status: active'; then
  ufw allow "$PORT/tcp"
  ufw allow "$PORT/udp"
fi
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port="$PORT/tcp"
  firewall-cmd --permanent --add-port="$PORT/udp"
  firewall-cmd --reload
fi

if [[ $INIT_SYSTEM == 'systemd' ]]; then
  systemctl daemon-reload
  systemctl enable --now shadowsocks-rust
  systemctl is-active --quiet shadowsocks-rust || {
    journalctl -u shadowsocks-rust --no-pager -n 30
    exit 1
  }
else
  rc-update add shadowsocks-rust default >/dev/null
  chmod +x /etc/init.d/shadowsocks-rust
  rc-update add shadowsocks-rust default
  rc-service shadowsocks-rust restart
  rc-service shadowsocks-rust status >/dev/null 2>&1 || {
    echo '服务启动失败'
    exit 1
  }
else
  echo '不支持此服务管理器'; exit 1
fi

echo
echo '安装完成：'
echo "端口：$PORT"
echo "密码：$PASSWORD"
echo "加密：$METHOD"
echo '模式：TCP + UDP'
echo "版本：$VERSION"
echo "安装完成：端口 $PORT，密码 $PASS，aes-128-gcm，TCP+UDP"
