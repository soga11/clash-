#!/bin/bash
#================================================================
# Shoes Hysteria2 一键安装脚本
# 项目地址: https://github.com/cfal/shoes
# 适用系统: Ubuntu/Debian/CentOS/Alpine/OpenWrt
# 作者: Based on SkimProxy.sh structure
# 日期: 2025-12-15
#================================================================

GREEN_BG='\033[42;30m'
RED_BG='\033[41;97m'
WHITE_BG='\033[47;30m'
NORMAL='\033[0m'

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED_BG}需要 root 权限运行此脚本${NORMAL} 请使用 sudo 或切换到 root 用户"
  exit 1
fi

# 检测 CPU 架构
cpu_arch=$(uname -m)
case "$cpu_arch" in
  x86_64) arch="x86_64-unknown-linux-gnu" ;;
  aarch64) arch="aarch64-unknown-linux-gnu" ;;
  armv7l) arch="armv7-unknown-linux-gnueabihf" ;;
  *) echo -e "${RED_BG}不支持的架构: $cpu_arch${NORMAL}"; exit 1 ;;
esac

# 获取服务器 IP（支持 IPv4/IPv6）
if [ -z "$3" ] || [ "$3" = "auto" ]; then
  ip=$(curl -s https://cloudflare.com/cdn-cgi/trace -4 | grep -oP '(?<=ip=).*')
  if [ -z "$ip" ]; then
    ip=$(curl -s https://cloudflare.com/cdn-cgi/trace -6 | grep -oP '(?<=ip=).*')
  fi
  if echo "$ip" | grep -q ':'; then
    ip="[$ip]"
  fi
else 
  ip=$3
fi

# URL 编码函数
urlencode() {
    local LANG=C
    local input
    if [ -t 0 ]; then
        input="$1"
    else
        input=$(cat)
    fi
    local length="${#input}"
    for (( i = 0; i < length; i++ )); do
        c="${input:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "%s" "$c" ;;
            $'\n') printf "%%0A" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
    echo
}

# 检测并安装依赖
install_packages() {
  echo -e "${GREEN_BG}[依赖检查] 正在安装必要依赖...${NORMAL}"
  if command -v apk &> /dev/null; then
    apk update && apk add curl jq tar openssl
  elif command -v apt-get &> /dev/null; then
    apt-get update && apt-get install -y curl jq tar openssl
  elif command -v yum &> /dev/null; then
    yum install -y curl jq tar openssl
  elif command -v dnf &> /dev/null; then
    dnf install -y curl jq tar openssl
  else
    echo -e "${RED_BG}不支持的包管理器${NORMAL} 请手动安装: curl jq tar openssl"
    exit 1
  fi
}

# 安装 GNU grep（如果是 BusyBox）
is_busybox_grep() {
  grep --version 2>&1 | grep -q BusyBox
}

if is_busybox_grep; then
  echo -e "${GREEN_BG}[依赖检查] 检测到 BusyBox grep，正在安装 GNU grep...${NORMAL}"
  if command -v apk >/dev/null; then
    apk add grep
  elif command -v apt-get >/dev/null; then
    apt-get update && apt-get install -y grep
  fi
fi

# 检查并安装依赖工具
for tool in curl jq tar openssl; do
  if ! command -v "$tool" &> /dev/null; then
    install_packages
    break
  fi
done

# 获取 Shoes 最新版本
get_latest_version() {
  latest_version=$(curl -s "https://api.github.com/repos/cfal/shoes/releases/latest" | jq -r .tag_name)
  if [[ "$latest_version" == "null" || -z "$latest_version" ]]; then
    echo "v0.2.2"  # 回退版本
  else
    echo "$latest_version"
  fi
}

# 下载并安装 Shoes
download_shoes() {
  mkdir -p /opt/shoes-hy2/
  
  # 检测 glibc 版本（决定使用 gnu 还是 musl）
  glibc_version=$(ldd --version 2>&1 | head -n1 | grep -oP '\d+\.\d+' | head -1)
  if [[ -n "$glibc_version" ]] && awk -v ver="$glibc_version" 'BEGIN{exit(ver>=2.17?0:1)}'; then
    variant="gnu"
  else
    variant="musl"
  fi
  
  url="https://github.com/cfal/shoes/releases/download/${version}/shoes-${arch/unknown-linux-/unknown-linux-${variant}}.tar.gz"
  
  echo -e "${GREEN_BG}正在下载 Shoes ${version} (${arch}, ${variant})...${NORMAL}"
  echo -e "${GREEN_BG}下载地址: ${url}${NORMAL}"
  
  curl -sL "$url" -o /tmp/shoes.tar.gz
  tar -xzf /tmp/shoes.tar.gz -C /opt/shoes-hy2/
  chmod +x /opt/shoes-hy2/shoes
  rm -f /tmp/shoes.tar.gz
  
  echo -e "${GREEN_BG}Shoes 已安装到 /opt/shoes-hy2/${NORMAL}"
}

# 设置版本（参数2）
if [ -z "$2" ] || [ "$2" = "auto" ]; then
  version=$(get_latest_version)
else
  version="$2"
fi

# 检查已安装版本
if [[ -x "/opt/shoes-hy2/shoes" ]]; then
    installed_version=$(/opt/shoes-hy2/shoes --version 2>&1 | grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
    if [[ "$installed_version" == "$version" ]]; then
        echo -e "${GREEN_BG}[版本检查] Shoes ${version} 已安装，跳过下载${NORMAL}"
    else
        echo -e "${GREEN_BG}[版本检查] 已安装版本 ($installed_version) 与目标版本 ($version) 不同，正在更新...${NORMAL}"
        download_shoes
    fi
else
    echo -e "${GREEN_BG}[安装] Shoes 未安装，开始下载...${NORMAL}"
    download_shoes
fi

# 生成配置
if [ -z "$1" ] || [ "$1" = "auto" ]; then
  port=52015
else
  port=$1
fi

mkdir -p /opt/shoes-hy2/$port
password="Aq112211!"

# 生成自签名证书
echo -e "${GREEN_BG}[证书] 正在生成自签名证书...${NORMAL}"
cat <<EOF > /opt/shoes-hy2/$port/openssl.conf
[ req ]
default_bits           = 2048
prompt                 = no
default_md             = sha256
distinguished_name     = dn
x509_extensions        = v3_ext

[ dn ]
C                      = HK
ST                     = Hong Kong
L                      = Hong Kong
O                      = Shoes Server
OU                     = Proxy
CN                     = www.gov.hk

[ v3_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = www.gov.hk
DNS.2 = *.gov.hk
EOF

openssl req -x509 -new -nodes -days 3650 \
  -keyout /opt/shoes-hy2/$port/key.pem \
  -out /opt/shoes-hy2/$port/cert.pem \
  -config /opt/shoes-hy2/$port/openssl.conf

chmod 600 /opt/shoes-hy2/$port/key.pem
chmod 644 /opt/shoes-hy2/$port/cert.pem

# 打印证书信息
cert_fingerprint=$(openssl x509 -noout -fingerprint -sha256 -in /opt/shoes-hy2/$port/cert.pem | cut -d'=' -f2)

echo -e "${GREEN_BG}========== 配置信息 ==========${NORMAL}"
echo -e "${GREEN_BG}服务器地址${NORMAL}: $ip:$port"
echo -e "${GREEN_BG}连接密码${NORMAL}: $password"
echo -e "${GREEN_BG}证书指纹 (SHA256)${NORMAL}: $cert_fingerprint"
echo -e "${GREEN_BG}=============================${NORMAL}"

# 创建 Shoes 配置文件
cat <<EOF > /opt/shoes-hy2/$port/config.yaml
# Shoes Hysteria2 服务器配置
- address: 0.0.0.0:${port}
  transport: quic
  quic_settings:
    cert: /opt/shoes-hy2/${port}/cert.pem
    key: /opt/shoes-hy2/${port}/key.pem
    alpn_protocols: ["h3"]
  protocol:
    type: hysteria2
    password: "$password"
    udp_enabled: true
EOF

echo -e "${GREEN_BG}[配置] 已生成配置文件: /opt/shoes-hy2/$port/config.yaml${NORMAL}"

# 创建 systemd 服务
echo -e "${GREEN_BG}[服务] 正在创建 systemd 服务...${NORMAL}"
init_system=$(cat /proc/1/comm 2>/dev/null || echo "unknown")

if [[ "$init_system" == "systemd" ]]; then
  cat <<EOF > /etc/systemd/system/shoes-hy2-${port}.service
[Unit]
Description=Shoes Hysteria2 Server on port ${port}
After=network.target

[Service]
Type=simple
ExecStart=/opt/shoes-hy2/shoes /opt/shoes-hy2/$port/config.yaml
Restart=on-failure
RestartSec=5s
StandardOutput=append:/var/log/shoes-hy2-$port.log
StandardError=append:/var/log/shoes-hy2-$port.log

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable shoes-hy2-${port}
  systemctl start shoes-hy2-${port}
  
  echo -e "${GREEN_BG}[服务] systemd 服务已启动${NORMAL}"
  echo -e "${WHITE_BG}查看日志: journalctl -u shoes-hy2-${port} -f${NORMAL}"
  echo -e "${WHITE_BG}停止服务: systemctl stop shoes-hy2-${port}${NORMAL}"
  echo -e "${WHITE_BG}卸载服务: systemctl disable --now shoes-hy2-${port} && rm /etc/systemd/system/shoes-hy2-${port}.service && rm -rf /opt/shoes-hy2/$port${NORMAL}"

elif [[ "$init_system" == "init" || "$init_system" == "openrc" ]]; then
  cat <<EOF > /etc/init.d/shoes-hy2-$port
#!/sbin/openrc-run

name="Shoes Hysteria2 on :$port"
description="Shoes Hysteria2 server on port $port"
command="/opt/shoes-hy2/shoes"
command_args="/opt/shoes-hy2/$port/config.yaml"
pidfile="/var/run/shoes-hy2-$port.pid"
logfile="/var/log/shoes-hy2-$port.log"

depend() {
    need net
    after firewall
}

start() {
    ebegin "Starting \$name"
    start-stop-daemon --start --background --make-pidfile --pidfile \$pidfile \\
      --stdout \$logfile --stderr \$logfile --exec \$command -- \$command_args
    eend \$?
}

stop() {
    ebegin "Stopping \$name"
    start-stop-daemon --stop --pidfile \$pidfile
    eend \$?
}
EOF

  chmod +x /etc/init.d/shoes-hy2-${port}
  rc-update add shoes-hy2-${port} default
  rc-service shoes-hy2-${port} start
  
  echo -e "${GREEN_BG}[服务] OpenRC 服务已启动${NORMAL}"
  echo -e "${WHITE_BG}卸载服务: rc-update del shoes-hy2-${port} && rc-service shoes-hy2-${port} stop && rm /etc/init.d/shoes-hy2-${port} && rm -rf /opt/shoes-hy2/$port${NORMAL}"

else
  echo -e "${RED_BG}不支持的 init 系统: $init_system${NORMAL}"
  echo -e "${WHITE_BG}请手动运行: /opt/shoes-hy2/shoes /opt/shoes-hy2/$port/config.yaml${NORMAL}"
fi

# 生成 Hysteria2 分享链接
# 格式: hysteria2://password@server:port/?insecure=1&sni=www.gov.hk#name
hy2_url="hysteria2://$(urlencode $password)@$ip:$port/?insecure=1&sni=www.gov.hk#$(urlencode "Shoes-HY2-$ip:$port")"

# 生成客户端 JSON 配置
json_config=$(cat <<EOF
{
  "type": "hysteria2",
  "tag": "shoes-hy2-$port",
  "server": "${ip//[\[\]]/}",
  "server_port": $port,
  "password": "$password",
  "tls": {
    "enabled": true,
    "insecure": true,
    "server_name": "www.gov.hk",
    "alpn": ["h3"]
  }
}
EOF
)

echo ""
echo -e "${GREEN_BG}========== 安装完成 ==========${NORMAL}"
echo -e "${GREEN_BG}Hysteria2 分享链接:${NORMAL}"
echo "$hy2_url"
echo ""
echo -e "${GREEN_BG}JSON 配置 (sing-box/v2rayN):${NORMAL}"
echo "$json_config"
echo ""
echo -e "${GREEN_BG}=============================${NORMAL}"
echo -e "${GREEN_BG}Shoes Hysteria2 服务已启动!${NORMAL}"
echo -e "${GREEN_BG}服务名称: shoes-hy2-${port}${NORMAL}"
echo ""
echo -e "${WHITE_BG}客户端配置注意事项:${NORMAL}"
echo "1. 使用自签名证书，客户端需开启 '跳过证书验证' (insecure=1)"
echo "2. SNI 设置为: www.gov.hk"
echo "3. ALPN 设置为: h3"
echo "4. 如需正式证书，请使用 acme.sh 申请并替换 cert.pem 和 key.pem"
echo ""