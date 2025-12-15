#!/bin/bash
#================================================================
# Shoes Hysteria2 一键安装脚本
# 项目地址: https://github.com/cfal/shoes
# 适用系统: Ubuntu/Debian/CentOS/Alpine/OpenWrt
# 版本: 1.0.0
# 日期: 2025-12-15
#================================================================

GREEN_BG='\033[42;30m'
RED_BG='\033[41;97m'
WHITE_BG='\033[47;30m'
YELLOW_BG='\033[43;30m'
NORMAL='\033[0m'

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED_BG}需要 root 权限运行此脚本${NORMAL}"
  echo "请使用以下命令之一："
  echo "  sudo bash $0"
  echo "  su root 后运行 bash $0"
  exit 1
fi

echo -e "${GREEN_BG}[系统检测] 正在检测系统架构...${NORMAL}"
cpu_arch=$(uname -m)
case "$cpu_arch" in
  x86_64) 
    arch="x86_64-unknown-linux"
    echo -e "${GREEN_BG}检测到架构: x86_64${NORMAL}"
    ;;
  aarch64) 
    arch="aarch64-unknown-linux"
    echo -e "${GREEN_BG}检测到架构: ARM64${NORMAL}"
    ;;
  armv7l) 
    arch="armv7-unknown-linux-gnueabihf"
    echo -e "${GREEN_BG}检测到架构: ARMv7${NORMAL}"
    ;;
  *) 
    echo -e "${RED_BG}不支持的架构: $cpu_arch${NORMAL}"
    echo "支持的架构: x86_64, aarch64, armv7l"
    exit 1
    ;;
esac

echo -e "${GREEN_BG}[系统检测] 正在检测 libc 类型...${NORMAL}"
if ldd --version 2>&1 | grep -q 'musl'; then
  libc_type="musl"
  echo -e "${GREEN_BG}检测到 musl libc (Alpine/OpenWrt)${NORMAL}"
elif ldd --version 2>&1 | grep -q 'GLIBC'; then
  glibc_version=$(ldd --version 2>&1 | head -n1 | grep -oP '\d+\.\d+' | head -1)
  if awk -v ver="$glibc_version" 'BEGIN{exit(ver>=2.17?0:1)}' 2>/dev/null; then
    libc_type="gnu"
    echo -e "${GREEN_BG}检测到 glibc ${glibc_version} (使用 GNU 版本)${NORMAL}"
  else
    libc_type="musl"
    echo -e "${YELLOW_BG}glibc 版本过低 (${glibc_version} < 2.17)，将使用 musl 版本${NORMAL}"
  fi
else
  libc_type="gnu"
  echo -e "${YELLOW_BG}无法检测 libc 类型，默认使用 GNU 版本${NORMAL}"
fi

arch_full="${arch}-${libc_type}"

echo -e "${GREEN_BG}[网络检测] 正在获取服务器 IP...${NORMAL}"
if [ -z "$3" ] || [ "$3" = "auto" ]; then
  ip=$(curl -s4 --max-time 5 https://api.ipify.org)
  if [ -z "$ip" ]; then
    ip=$(curl -s6 --max-time 5 https://api64.ipify.org)
  fi
  if [ -z "$ip" ]; then
    ip=$(curl -s --max-time 5 https://cloudflare.com/cdn-cgi/trace | grep -oP '(?<=ip=).*')
  fi
  if [ -z "$ip" ]; then
    echo -e "${RED_BG}无法自动获取服务器 IP${NORMAL}"
    read -p "请手动输入服务器 IP: " ip
  fi
  
  if echo "$ip" | grep -q ':'; then
    ip_display="[$ip]"
    echo -e "${GREEN_BG}检测到 IPv6 地址: ${ip_display}${NORMAL}"
  else
    ip_display="$ip"
    echo -e "${GREEN_BG}检测到 IPv4 地址: ${ip_display}${NORMAL}"
  fi
else 
  ip="$3"
  ip_display="$ip"
  echo -e "${GREEN_BG}使用指定 IP: ${ip_display}${NORMAL}"
fi

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

install_packages() {
  echo -e "${GREEN_BG}[依赖安装] 正在安装必要依赖...${NORMAL}"
  if command -v apk &> /dev/null; then
    apk update && apk add curl jq tar openssl wget
  elif command -v apt-get &> /dev/null; then
    apt-get update && apt-get install -y curl jq tar openssl wget
  elif command -v yum &> /dev/null; then
    yum install -y curl jq tar openssl wget
  elif command -v dnf &> /dev/null; then
    dnf install -y curl jq tar openssl wget
  elif command -v pacman &> /dev/null; then
    pacman -Sy --noconfirm curl jq tar openssl wget
  else
    echo -e "${RED_BG}不支持的包管理器${NORMAL}"
    echo "请手动安装以下工具: curl jq tar openssl wget"
    exit 1
  fi
}

is_busybox_grep() {
  grep --version 2>&1 | grep -q BusyBox
}

if is_busybox_grep; then
  echo -e "${GREEN_BG}[依赖检查] 检测到 BusyBox grep，正在安装 GNU grep...${NORMAL}"
  if command -v apk >/dev/null; then
    apk add grep
  elif command -v apt-get >/dev/null; then
    apt-get update && apt-get install -y grep
  elif command -v pacman >/dev/null; then
    pacman -Sy --noconfirm grep
  fi
fi

echo -e "${GREEN_BG}[依赖检查] 检查必要工具...${NORMAL}"
missing_tools=()
for tool in curl jq tar openssl wget; do
  if ! command -v "$tool" &> /dev/null; then
    missing_tools+=("$tool")
  fi
done

if [ ${#missing_tools[@]} -gt 0 ]; then
  echo -e "${YELLOW_BG}缺少工具: ${missing_tools[*]}${NORMAL}"
  install_packages
else
  echo -e "${GREEN_BG}所有依赖已安装${NORMAL}"
fi

get_latest_version() {
  echo -e "${GREEN_BG}[版本检测] 正在获取 Shoes 最新版本...${NORMAL}"
  latest_version=$(curl -s --max-time 10 "https://api.github.com/repos/cfal/shoes/releases/latest" | jq -r .tag_name 2>/dev/null)
  if [[ "$latest_version" == "null" || -z "$latest_version" ]]; then
    echo -e "${YELLOW_BG}无法从 GitHub 获取最新版本，使用默认版本${NORMAL}"
    echo "v0.2.2"
  else
    echo -e "${GREEN_BG}最新版本: ${latest_version}${NORMAL}"
    echo "$latest_version"
  fi
}

download_shoes() {
  echo -e "${GREEN_BG}[安装 Shoes] 开始下载...${NORMAL}"
  mkdir -p /opt/shoes-hy2/
  
  download_url="https://github.com/cfal/shoes/releases/download/${version}/shoes-${arch_full}.tar.gz"
  
  echo -e "${GREEN_BG}下载地址: ${download_url}${NORMAL}"
  echo -e "${GREEN_BG}架构: ${arch_full}${NORMAL}"
  
  if curl -sL --max-time 120 "$download_url" -o /tmp/shoes.tar.gz; then
    echo -e "${GREEN_BG}下载成功，正在解压...${NORMAL}"
    
    if tar -tzf /tmp/shoes.tar.gz &>/dev/null; then
      tar -xzf /tmp/shoes.tar.gz -C /opt/shoes-hy2/
      chmod +x /opt/shoes-hy2/shoes
      rm -f /tmp/shoes.tar.gz
      echo -e "${GREEN_BG}Shoes 已安装到 /opt/shoes-hy2/${NORMAL}"
    else
      echo -e "${RED_BG}下载的文件不是有效的 tar.gz 压缩包${NORMAL}"
      rm -f /tmp/shoes.tar.gz
      exit 1
    fi
  else
    echo -e "${RED_BG}下载失败${NORMAL}"
    echo "请检查："
    echo "  1. 网络连接是否正常"
    echo "  2. GitHub 是否可访问"
    echo "  3. 版本号是否正确 (${version})"
    echo "  4. 架构是否支持 (${arch_full})"
    exit 1
  fi
}

if [ -z "$2" ] || [ "$2" = "auto" ]; then
  version=$(get_latest_version)
else
  version="$2"
  echo -e "${GREEN_BG}[版本设置] 使用指定版本: ${version}${NORMAL}"
fi

if [[ -x "/opt/shoes-hy2/shoes" ]]; then
    installed_version=$(/opt/shoes-hy2/shoes --version 2>&1 | grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
    if [[ "$installed_version" == "$version" ]]; then
        echo -e "${GREEN_BG}[版本检查] Shoes ${version} 已安装，跳过下载${NORMAL}"
    else
        echo -e "${YELLOW_BG}[版本检查] 已安装 ${installed_version}，目标版本 ${version}${NORMAL}"
        download_shoes
    fi
else
    echo -e "${GREEN_BG}[安装检查] Shoes 未安装，开始下载...${NORMAL}"
    download_shoes
fi

if [ -z "$1" ] || [ "$1" = "auto" ]; then
  port=52015
  echo -e "${GREEN_BG}[端口设置] 使用默认端口: ${port}${NORMAL}"
else
  port=$1
  echo -e "${GREEN_BG}[端口设置] 使用指定端口: ${port}${NORMAL}"
fi

if ss -tuln 2>/dev/null | grep -q ":${port} " || netstat -tuln 2>/dev/null | grep -q ":${port} "; then
  echo -e "${YELLOW_BG}端口 ${port} 已被占用，继续安装...${NORMAL}"
fi

mkdir -p /opt/shoes-hy2/$port

if [ -z "$4" ] || [ "$4" = "auto" ]; then
  password="Aq$(date +%s | sha256sum | base64 | head -c 8)!"
  echo -e "${GREEN_BG}[密码生成] 已生成随机密码${NORMAL}"
else
  password="$4"
  echo -e "${GREEN_BG}[密码设置] 使用指定密码${NORMAL}"
fi

echo -e "${GREEN_BG}[证书生成] 正在生成自签名 TLS 证书...${NORMAL}"
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
O                      = Shoes Proxy Server
OU                     = Network Security
CN                     = www.gov.hk

[ v3_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = www.gov.hk
DNS.2 = *.gov.hk
DNS.3 = localhost
IP.1 = 127.0.0.1
EOF

openssl req -x509 -new -nodes -days 3650 \
  -keyout /opt/shoes-hy2/$port/key.pem \
  -out /opt/shoes-hy2/$port/cert.pem \
  -config /opt/shoes-hy2/$port/openssl.conf 2>/dev/null

chmod 600 /opt/shoes-hy2/$port/key.pem
chmod 644 /opt/shoes-hy2/$port/cert.pem
rm -f /opt/shoes-hy2/$port/openssl.conf

cert_fingerprint=$(openssl x509 -noout -fingerprint -sha256 -in /opt/shoes-hy2/$port/cert.pem 2>/dev/null | cut -d'=' -f2)

echo ""
echo -e "${WHITE_BG}========================================${NORMAL}"
echo -e "${GREEN_BG}         配置信息                      ${NORMAL}"
echo -e "${WHITE_BG}========================================${NORMAL}"
echo -e "${GREEN_BG}服务器地址${NORMAL}: $ip_display"
echo -e "${GREEN_BG}监听端口${NORMAL}: $port"
echo -e "${GREEN_BG}连接密码${NORMAL}: $password"
echo -e "${GREEN_BG}证书指纹${NORMAL}: $cert_fingerprint"
echo -e "${WHITE_BG}========================================${NORMAL}"
echo ""

cat <<EOF > /opt/shoes-hy2/$port/config.yaml
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

echo -e "${GREEN_BG}[配置文件] 已生成: /opt/shoes-hy2/$port/config.yaml${NORMAL}"

echo -e "${GREEN_BG}[服务安装] 正在创建系统服务...${NORMAL}"
init_system=$(cat /proc/1/comm 2>/dev/null || echo "unknown")

if [[ "$init_system" == "systemd" ]]; then
  cat <<EOF > /etc/systemd/system/shoes-hy2-${port}.service
[Unit]
Description=Shoes Hysteria2 Server on port ${port}
Documentation=https://github.com/cfal/shoes
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/opt/shoes-hy2/shoes /opt/shoes-hy2/$port/config.yaml
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
StandardOutput=append:/var/log/shoes-hy2-$port.log
StandardError=append:/var/log/shoes-hy2-$port.log

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable shoes-hy2-${port} 2>/dev/null
  systemctl start shoes-hy2-${port}
  
  sleep 2
  
  if systemctl is-active --quiet shoes-hy2-${port}; then
    echo -e "${GREEN_BG}[服务状态] ✓ 服务已成功启动${NORMAL}"
  else
    echo -e "${RED_BG}[服务状态] ✗ 服务启动失败${NORMAL}"
    echo "查看日志: journalctl -u shoes-hy2-${port} -n 50"
  fi
  
  echo ""
  echo -e "${WHITE_BG}========== 管理命令 ==========${NORMAL}"
  echo -e "查看状态: systemctl status shoes-hy2-${port}"
  echo -e "查看日志: journalctl -u shoes-hy2-${port} -f"
  echo -e "重启服务: systemctl restart shoes-hy2-${port}"
  echo -e "停止服务: systemctl stop shoes-hy2-${port}"
  echo -e "卸载: systemctl disable --now shoes-hy2-${port} && rm /etc/systemd/system/shoes-hy2-${port}.service && rm -rf /opt/shoes-hy2/$port"
  echo -e "${WHITE_BG}=============================${NORMAL}"
fi

hy2_url="hysteria2://$(urlencode "$password")@${ip_display//[\[\]]/}:$port/?insecure=1&sni=www.gov.hk#$(urlencode "Shoes-HY2-$port")"

json_config=$(cat <<EOF
{
  "type": "hysteria2",
  "tag": "shoes-hy2-$port",
  "server": "${ip_display//[\[\]]/}",
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

clash_config=$(cat <<EOF
proxies:
  - name: "Shoes-HY2-$port"
    type: hysteria2
    server: ${ip_display//[\[\]]/}
    port: $port
    password: $password
    skip-cert-verify: true
    sni: www.gov.hk
    alpn:
      - h3
EOF
)

echo ""
echo -e "${WHITE_BG}========================================${NORMAL}"
echo -e "${GREEN_BG}      🎉 安装完成！                     ${NORMAL}"
echo -e "${WHITE_BG}========================================${NORMAL}"
echo ""
echo -e "${GREEN_BG}Hysteria2 分享链接:${NORMAL}"
echo "$hy2_url"
echo ""
echo -e "${GREEN_BG}JSON 配置 (sing-box):${NORMAL}"
echo "$json_config"
echo ""
echo -e "${GREEN_BG}Clash Meta 配置:${NORMAL}"
echo "$clash_config"
echo ""
echo -e "${WHITE_BG}========================================${NORMAL}"
echo -e "${YELLOW_BG}客户端配置注意事项:${NORMAL}"
echo "1. 使用自签名证书，需开启 '跳过证书验证'"
echo "2. SNI 设置为: www.gov.hk"
echo "3. ALPN 设置为: h3"
echo ""
echo -e "${GREEN_BG}防火墙配置 (如需要):${NORMAL}"
echo "  ufw allow $port/udp"
echo "  firewall-cmd --add-port=$port/udp --permanent"
echo "  iptables -A INPUT -p udp --dport $port -j ACCEPT"
echo ""
echo -e "${WHITE_BG}========================================${NORMAL}"
echo -e "${GREEN_BG}感谢使用 Shoes Hysteria2 安装脚本！    ${NORMAL}"
echo -e "${WHITE_BG}========================================${NORMAL}"
