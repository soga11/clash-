#!/bin/bash
#================================================================
# Shoes Hysteria2 一键安装脚本
# 项目地址: https://github.com/cfal/shoes
# 适用系统: Ubuntu/Debian/CentOS/Alpine/OpenWrt
# 版本: 2.0.0
# 日期: 2025-12-15
#================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

SHOES_BIN="/usr/local/bin/shoes"
SHOES_CONF_DIR="/etc/shoes"
SHOES_CONF_FILE="${SHOES_CONF_DIR}/hy2-config.yaml"
SHOES_LINK_FILE="${SHOES_CONF_DIR}/hy2-link.txt"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}必须使用 root 权限运行此脚本！${RESET}"
    exit 1
fi

get_glibc_version() {
    if ldd --version 2>&1 | grep -q 'musl'; then
        GLIBC_VERSION="musl"
        GLIBC_MAJOR=0
        GLIBC_MINOR=0
        echo -e "${GREEN}系统 libc 类型：${YELLOW}musl${RESET}"
    elif ldd --version 2>&1 | grep -q 'GLIBC'; then
        GLIBC_VERSION=$(ldd --version 2>&1 | head -n1 | grep -oP '\d+\.\d+' | head -1)
        GLIBC_MAJOR=$(echo "$GLIBC_VERSION" | cut -d. -f1)
        GLIBC_MINOR=$(echo "$GLIBC_VERSION" | cut -d. -f2)
        echo -e "${GREEN}系统 glibc 版本：${YELLOW}${GLIBC_VERSION}${RESET}"
    else
        GLIBC_VERSION="2.17"
        GLIBC_MAJOR=2
        GLIBC_MINOR=17
        echo -e "${YELLOW}无法检测 libc 版本，假定 glibc 2.17${RESET}"
    fi
}

check_arch() {
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            GNU_FILE="shoes-x86_64-unknown-linux-gnu.tar.gz"
            MUSL_FILE="shoes-x86_64-unknown-linux-musl.tar.gz"
            echo -e "${GREEN}检测到架构: x86_64${RESET}"
            ;;
        aarch64|arm64)
            GNU_FILE="shoes-aarch64-unknown-linux-gnu.tar.gz"
            MUSL_FILE="shoes-aarch64-unknown-linux-musl.tar.gz"
            echo -e "${GREEN}检测到架构: ARM64${RESET}"
            ;;
        armv7l)
            GNU_FILE="shoes-armv7-unknown-linux-gnueabihf.tar.gz"
            MUSL_FILE="shoes-armv7-unknown-linux-musleabihf.tar.gz"
            echo -e "${GREEN}检测到架构: ARMv7${RESET}"
            ;;
        *)
            echo -e "${RED}不支持的 CPU 架构: $arch${RESET}"
            exit 1
            ;;
    esac
}

get_latest_version() {
    echo -e "${CYAN}正在获取 Shoes 最新版本...${RESET}"
    LATEST_VER=$(curl -s --max-time 10 https://api.github.com/repos/cfal/shoes/releases/latest | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/' | head -1)
    if [[ -z "$LATEST_VER" ]]; then
        echo -e "${YELLOW}无法从 GitHub 获取版本，使用默认版本 0.2.2${RESET}"
        LATEST_VER="0.2.2"
    else
        echo -e "${GREEN}Shoes 最新版本：${YELLOW}v${LATEST_VER}${RESET}"
    fi
}

test_shoes_binary() {
    if ${SHOES_BIN} generate-reality-keypair >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

download_shoes() {
    get_glibc_version
    check_arch
    get_latest_version
    if [[ "$GLIBC_VERSION" == "musl" ]] || (( GLIBC_MAJOR < 2 )) || (( GLIBC_MAJOR == 2 && GLIBC_MINOR < 17 )); then
        echo -e "${YELLOW}你的 glibc 版本低于 2.17 或使用 musl，将使用 MUSL 版本${RESET}"
        DOWNLOAD_FILE=${MUSL_FILE}
        DOWNLOAD_TYPE="MUSL"
    else
        echo -e "${GREEN}你的系统支持 Shoes GNU 版本，将优先尝试 GNU…${RESET}"
        DOWNLOAD_FILE=${GNU_FILE}
        DOWNLOAD_TYPE="GNU"
    fi
    mkdir -p /tmp/shoesdl
    cd /tmp/shoesdl
    DOWNLOAD_URL="https://github.com/cfal/shoes/releases/download/v${LATEST_VER}/${DOWNLOAD_FILE}"
    echo -e "${CYAN}下载 ${DOWNLOAD_TYPE} 版本: ${YELLOW}${DOWNLOAD_URL}${RESET}"
    if wget -q --show-progress -O shoes.tar.gz "$DOWNLOAD_URL" 2>/dev/null || curl -# -L -o shoes.tar.gz "$DOWNLOAD_URL" 2>/dev/null; then
        echo -e "${GREEN}下载成功${RESET}"
    else
        echo -e "${RED}${DOWNLOAD_TYPE} 下载失败！${RESET}"
        if [[ "$DOWNLOAD_TYPE" == "GNU" ]]; then
            echo -e "${YELLOW}尝试改为下载 MUSL 版本...${RESET}"
            DOWNLOAD_URL="https://github.com/cfal/shoes/releases/download/v${LATEST_VER}/${MUSL_FILE}"
            if wget -q --show-progress -O shoes.tar.gz "$DOWNLOAD_URL" 2>/dev/null || curl -# -L -o shoes.tar.gz "$DOWNLOAD_URL" 2>/dev/null; then
                DOWNLOAD_TYPE="MUSL"
            else
                echo -e "${RED}MUSL 版本也下载失败！${RESET}"
                exit 1
            fi
        else
            exit 1
        fi
    fi
    tar -xzf shoes.tar.gz
    mv shoes ${SHOES_BIN}
    chmod +x ${SHOES_BIN}
    if test_shoes_binary; then
        echo -e "${GREEN}Shoes (${DOWNLOAD_TYPE}) 可正常运行！${RESET}"
    else
        if [[ "$DOWNLOAD_TYPE" == "GNU" ]]; then
            echo -e "${YELLOW}GNU 无法运行，自动切换 MUSL…${RESET}"
            DOWNLOAD_URL="https://github.com/cfal/shoes/releases/download/v${LATEST_VER}/${MUSL_FILE}"
            wget -q -O shoes.tar.gz "$DOWNLOAD_URL" 2>/dev/null || curl -# -L -o shoes.tar.gz "$DOWNLOAD_URL" 2>/dev/null
            tar -xzf shoes.tar.gz
            mv shoes ${SHOES_BIN}
            chmod +x ${SHOES_BIN}
            if test_shoes_binary; then
                echo -e "${GREEN}MUSL 版本运行成功！${RESET}"
            else
                echo -e "${RED}MUSL 版本也无法运行，系统无法支持 Shoes！${RESET}"
                exit 1
            fi
        else
            echo -e "${RED}MUSL 版本无法运行，系统不支持 Shoes！${RESET}"
            exit 1
        fi
    fi
    cd - >/dev/null
    rm -rf /tmp/shoesdl
}

install_hy2() {
    echo -e "${CYAN}开始安装 Shoes Hysteria2...${RESET}"
    if command -v shoes >/dev/null 2>&1; then
        echo -e "${YELLOW}Shoes 已安装，跳过下载${RESET}"
    else
        download_shoes
    fi
    mkdir -p ${SHOES_CONF_DIR}
    PORT=$(shuf -i 20000-60000 -n 1)
    PASSWORD="Aq$(openssl rand -hex 6)"
    echo -e "${CYAN}正在生成自签名证书...${RESET}"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout ${SHOES_CONF_DIR}/hy2-key.pem -out ${SHOES_CONF_DIR}/hy2-cert.pem -days 3650 -subj "/CN=www.gov.hk" 2>/dev/null
    chmod 600 ${SHOES_CONF_DIR}/hy2-key.pem
    chmod 644 ${SHOES_CONF_DIR}/hy2-cert.pem
cat > ${SHOES_CONF_FILE} <<EOF
- address: 0.0.0.0:${PORT}
  transport: quic
  quic_settings:
    cert: ${SHOES_CONF_DIR}/hy2-cert.pem
    key: ${SHOES_CONF_DIR}/hy2-key.pem
    alpn_protocols: ["h3"]
  protocol:
    type: hysteria2
    password: "${PASSWORD}"
    udp_enabled: true
EOF
cat > /etc/systemd/system/shoes.service <<EOF
[Unit]
Description=Shoes Hysteria2 Proxy Server
Documentation=https://github.com/cfal/shoes
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${SHOES_BIN} ${SHOES_CONF_FILE}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable shoes
    systemctl restart shoes
    sleep 2
    HOST_IP=$(curl -s4 --max-time 5 https://api.ipify.org)
    if [[ -z "$HOST_IP" ]]; then
        HOST_IP=$(curl -s --max-time 5 http://www.cloudflare.com/cdn-cgi/trace | grep -oP '(?<=ip=).*')
    fi
    COUNTRY=$(curl -s --max-time 5 http://ipinfo.io/${HOST_IP}/country 2>/dev/null || echo "XX")
    ENCODED_PASSWORD=$(echo -n "$PASSWORD" | jq -sRr @uri)
    HY2_URL="hysteria2://${ENCODED_PASSWORD}@${HOST_IP}:${PORT}/?insecure=1&sni=www.gov.hk#${COUNTRY}-Shoes-HY2"
    JSON_CONFIG=$(cat <<JSONEOF
{
  "type": "hysteria2",
  "tag": "shoes-hy2",
  "server": "${HOST_IP}",
  "server_port": ${PORT},
  "password": "${PASSWORD}",
  "tls": {
    "enabled": true,
    "insecure": true,
    "server_name": "www.gov.hk",
    "alpn": ["h3"]
  }
}
JSONEOF
)
    CLASH_CONFIG=$(cat <<CLASHEOF
proxies:
  - name: "Shoes-HY2-${COUNTRY}"
    type: hysteria2
    server: ${HOST_IP}
    port: ${PORT}
    password: ${PASSWORD}
    skip-cert-verify: true
    sni: www.gov.hk
    alpn:
      - h3
CLASHEOF
)
cat > ${SHOES_LINK_FILE} <<LINKEOF
========================================
Shoes Hysteria2 服务器信息
========================================
服务器地址: ${HOST_IP}
监听端口: ${PORT}
连接密码: ${PASSWORD}
========================================

Hysteria2 分享链接:
${HY2_URL}

JSON 配置 (sing-box):
${JSON_CONFIG}

Clash Meta 配置:
${CLASH_CONFIG}

========================================
客户端配置注意事项:
1. 使用自签名证书，需开启 '跳过证书验证'
2. SNI 设置为: www.gov.hk
3. ALPN 设置为: h3
========================================
LINKEOF
    echo ""
    echo -e "${GREEN}========================================${RESET}"
    echo -e "${GREEN}      Shoes Hysteria2 安装完成！${RESET}"
    echo -e "${GREEN}========================================${RESET}"
    echo ""
    cat ${SHOES_LINK_FILE}
    echo ""
}

uninstall_hy2() {
    echo -e "${YELLOW}正在卸载 Shoes Hysteria2...${RESET}"
    systemctl stop shoes 2>/dev/null
    systemctl disable shoes 2>/dev/null
    rm -f /etc/systemd/system/shoes.service
    rm -rf ${SHOES_CONF_DIR}
    rm -f ${SHOES_BIN}
    systemctl daemon-reload
    echo -e "${GREEN}Shoes Hysteria2 已完全卸载${RESET}"
}

check_installed() { 
    command -v shoes >/dev/null 2>&1 && [[ -f ${SHOES_CONF_FILE} ]]
}

check_running() { 
    systemctl is-active --quiet shoes 
}

view_config() {
    if [[ -f ${SHOES_LINK_FILE} ]]; then
        cat ${SHOES_LINK_FILE}
    else
        echo -e "${RED}配置文件不存在！请先安装 Hysteria2${RESET}"
    fi
}

show_menu() {
    clear
    echo -e "${CYAN}========================================${RESET}"
    echo -e "${CYAN}    Shoes Hysteria2 管理工具${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    echo ""
    if check_installed; then
        echo -e "安装状态: ${GREEN}已安装${RESET}"
    else
        echo -e "安装状态: ${RED}未安装${RESET}"
    fi
    if check_running; then
        echo -e "运行状态: ${GREEN}运行中${RESET}"
    else
        echo -e "运行状态: ${RED}未运行${RESET}"
    fi
    echo ""
    echo -e "${CYAN}========================================${RESET}"
    echo "1. 安装 Hysteria2 服务"
    echo "2. 卸载 Hysteria2 服务"
    echo "3. 启动 Hysteria2 服务"
    echo "4. 停止 Hysteria2 服务"
    echo "5. 重启 Hysteria2 服务"
    echo "6. 查看连接配置"
    echo "7. 查看实时日志"
    echo "8. 查看服务状态"
    echo "0. 退出"
    echo -e "${CYAN}========================================${RESET}"
    echo ""
    read -p "请输入选项 [0-8]: " choice
}

while true; do
    show_menu
    case "$choice" in
        1) 
            install_hy2
            ;;
        2) 
            read -p "确认卸载 Hysteria2? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                uninstall_hy2
            else
                echo "已取消"
            fi
            ;;
        3) 
            systemctl start shoes
            if systemctl is-active --quiet shoes; then
                echo -e "${GREEN}Hysteria2 已启动${RESET}"
            else
                echo -e "${RED}启动失败，查看日志: journalctl -u shoes -n 20${RESET}"
            fi
            ;;
        4) 
            systemctl stop shoes
            echo -e "${GREEN}Hysteria2 已停止${RESET}"
            ;;
        5) 
            systemctl restart shoes
            if systemctl is-active --quiet shoes; then
                echo -e "${GREEN}Hysteria2 已重启${RESET}"
            else
                echo -e "${RED}重启失败，查看日志: journalctl -u shoes -n 20${RESET}"
            fi
            ;;
        6) 
            view_config
            ;;
        7) 
            echo -e "${CYAN}按 Ctrl+C 退出日志查看${RESET}"
            sleep 2
            journalctl -u shoes -f
            ;;
        8)
            systemctl status shoes
            ;;
        0) 
            echo -e "${GREEN}感谢使用！${RESET}"
            exit 0
            ;;
        *) 
            echo -e "${RED}无效选项！${RESET}"
            ;;
    esac
    echo ""
    read -p "按 Enter 继续..."
done
