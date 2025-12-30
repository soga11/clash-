#!/bin/bash

#####################################################################
# HE IPv6 隧道配置脚本 - 全自动优化版
# 启动即自动: 获取信息 → 安装工具 → 创建 Swap → 等待输入
#####################################################################

set -e

# 检测管道输入
if [ ! -t 0 ]; then
    exec < /dev/tty
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# 检查 root
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本必须以 root 权限运行"
   exit 1
fi

# 全局变量
LOCAL_IPV4=""
HE_SERVER=""
CLIENT_IPV6=""
ROUTED_IPV6=""
GATEWAY_IPV6=""
MAIN_IFACE=""

# ========================================
# Banner
# ========================================
clear
echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        HE IPv6 隧道全自动配置                             ║
║        Hurricane Electric Tunnel Setup - Auto            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""

# ========================================
# 阶段 1: 自动获取系统信息
# ========================================
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}  阶段 1/5: 获取系统信息（自动）${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_info "检测本机 IPv4..."
LOCAL_IPV4=$(curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null || \
             ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)

if [[ -n "$LOCAL_IPV4" ]]; then
    log_success "本机 IPv4: ${LOCAL_IPV4}"
else
    log_error "无法自动检测 IPv4"
    exit 1
fi

log_info "检测主网卡..."
MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
log_success "主网卡: ${MAIN_IFACE}"

log_info "检测内存..."
TOTAL_MEM=$(free -m | awk 'NR==2{print $2}')
log_success "总内存: ${TOTAL_MEM} MB"

NATIVE_IPV6=$(ip -6 addr show scope global | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=/)' | head -n1)
if [[ -n "$NATIVE_IPV6" ]]; then
    log_warning "检测到原生 IPv6: ${NATIVE_IPV6}（将被禁用）"
else
    log_info "无原生 IPv6"
fi

echo ""
sleep 1

# ========================================
# 阶段 2: 自动安装必要工具
# ========================================
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}  阶段 2/5: 安装必要工具（自动）${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

export DEBIAN_FRONTEND=noninteractive

# 检查已安装的工具
MISSING=""
command -v ip >/dev/null 2>&1 || MISSING="$MISSING iproute2"
command -v curl >/dev/null 2>&1 || MISSING="$MISSING curl"
command -v jq >/dev/null 2>&1 || MISSING="$MISSING jq"

if [[ -n "$MISSING" ]]; then
    log_info "需要安装:${MISSING}"
    
    log_info "更新软件包列表..."
    apt-get update -qq 2>&1 | grep -E "Reading|Building" | sed 's/^/  /'
    
    log_info "安装工具包..."
    apt-get install -y --no-install-recommends $MISSING 2>&1 | \
        grep -E "Unpacking|Setting up|Processing" | \
        sed 's/^/  /' | \
        head -20
    
    log_success "工具已安装"
else
    log_success "所有工具已存在，跳过安装"
fi

echo ""
sleep 1

# ========================================
# 阶段 3: 自动创建 1G Swap
# ========================================
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}  阶段 3/5: 配置 Swap（自动）${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 检查是否已有 swap
CURRENT_SWAP=$(free -m | awk 'NR==3{print $2}')

if [[ "$CURRENT_SWAP" -ge 1000 ]]; then
    log_success "Swap 已存在: ${CURRENT_SWAP} MB（跳过创建）"
else
    log_info "创建 1GB Swap 文件..."
    
    # 检查磁盘空间
    FREE_SPACE=$(df -m / | awk 'NR==2{print $4}')
    if [[ "$FREE_SPACE" -lt 1100 ]]; then
        log_warning "磁盘空间不足，跳过 Swap 创建"
    else
        # 删除旧 swap（如果存在）
        if [[ -f /swapfile ]]; then
            swapoff /swapfile 2>/dev/null || true
            rm -f /swapfile
        fi
        
        # 创建 swap
        log_info "分配 1GB 空间..."
        dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress 2>&1 | \
            grep -oP '\d+\s+bytes' | tail -1 | sed 's/^/  /'
        
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon /swapfile
        
        # 持久化
        if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
        
        log_success "Swap 已创建并启用: 1024 MB"
    fi
fi

# 显示当前 swap
CURRENT_SWAP=$(free -m | awk 'NR==3{print $2}')
log_info "当前 Swap: ${CURRENT_SWAP} MB"

echo ""
sleep 1

# ========================================
# 阶段 4: 等待手动输入隧道信息
# ========================================
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}  阶段 4/5: 配置隧道信息（手动输入）${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}请登录 https://tunnelbroker.net/ 获取以下信息${NC}"
echo ""

# Server IPv4
echo -e "${CYAN}[1/3] Server IPv4 Address${NC}"
echo -e "${BLUE}示例: 216.66.87.134${NC}"
while true; do
    read -p "输入: " HE_SERVER
    HE_SERVER=$(echo "$HE_SERVER" | tr -d ' ')
    if [[ -n "$HE_SERVER" && "$HE_SERVER" =~ ^[0-9.]+$ ]]; then
        break
    fi
    log_error "格式错误，请重新输入"
done
log_success "已设置: ${HE_SERVER}"
echo ""

# Client IPv6
echo -e "${CYAN}[2/3] Client IPv6 Address${NC}"
echo -e "${BLUE}示例: 2001:470:1f22:57::2${NC}"
while true; do
    read -p "输入: " CLIENT_IPV6
    CLIENT_IPV6=$(echo "$CLIENT_IPV6" | tr -d ' ')
    if [[ -n "$CLIENT_IPV6" && "$CLIENT_IPV6" == *":"* ]]; then
        break
    fi
    log_error "格式错误，请重新输入"
done
log_success "已设置: ${CLIENT_IPV6}"

# 自动计算 Gateway
GATEWAY_IPV6=$(echo "$CLIENT_IPV6" | sed 's/::[0-9a-f]*$/::1/')
[[ "$GATEWAY_IPV6" == "$CLIENT_IPV6" ]] && GATEWAY_IPV6=$(echo "$CLIENT_IPV6" | sed 's/2$/1/')
log_info "Gateway: ${GATEWAY_IPV6}"
echo ""

# Routed /64
echo -e "${CYAN}[3/3] Routed /64${NC}"
echo -e "${BLUE}示例: 2001:470:1f23:57::1 或 2001:470:1f23:57::/64${NC}"
while true; do
    read -p "输入: " ROUTED_INPUT
    ROUTED_INPUT=$(echo "$ROUTED_INPUT" | tr -d ' ')
    if [[ -n "$ROUTED_INPUT" && "$ROUTED_INPUT" == *":"* ]]; then
        break
    fi
    log_error "格式错误，请重新输入"
done

# 处理格式
if [[ $ROUTED_INPUT == *"/64" ]]; then
    ROUTED_IPV6=$(echo "$ROUTED_INPUT" | sed 's|::/64|::1|')
elif [[ $ROUTED_INPUT == *"::" && $ROUTED_INPUT != *"::1" ]]; then
    ROUTED_IPV6="${ROUTED_INPUT}1"
else
    ROUTED_IPV6="$ROUTED_INPUT"
fi
log_success "已设置: ${ROUTED_IPV6}"

# 显示摘要
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo "  Server IPv4:  ${HE_SERVER}"
echo "  Client IPv6:  ${CLIENT_IPV6}"
echo "  Routed IPv6:  ${ROUTED_IPV6}"
echo "  Gateway IPv6: ${GATEWAY_IPV6}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""

# 3 秒倒计时自动继续
echo -ne "${YELLOW}输入完成！3 秒后自动安装隧道...${NC}"
for i in {3..1}; do
    echo -ne "\r${YELLOW}输入完成！${i} 秒后自动安装隧道...${NC}"
    sleep 1
done
echo -e "\r${GREEN}开始安装隧道！                          ${NC}"
echo ""

# ========================================
# 阶段 5: 自动安装并配置隧道
# ========================================
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}  阶段 5/5: 安装隧道（自动）${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_info "禁用原生 IPv6..."
sysctl -w net.ipv6.conf.${MAIN_IFACE}.disable_ipv6=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.${MAIN_IFACE}.accept_ra=0 >/dev/null 2>&1
sysctl -w net.ipv6.conf.default.accept_ra=0 >/dev/null 2>&1
ip -6 addr flush dev ${MAIN_IFACE} scope global 2>/dev/null || true
log_success "原生 IPv6 已禁用"

log_info "创建隧道..."
ip tunnel del he-ipv6 2>/dev/null || true
ip tunnel add he-ipv6 mode sit remote ${HE_SERVER} local ${LOCAL_IPV4} ttl 255
ip link set he-ipv6 mtu 1480 up
ip -6 addr add ${CLIENT_IPV6}/64 dev he-ipv6
ip -6 addr add ${ROUTED_IPV6}/64 dev he-ipv6
ip -6 route add default via ${GATEWAY_IPV6} dev he-ipv6 metric 100 2>/dev/null || true
ip -6 route flush cache
log_success "隧道已创建"

log_info "创建启动脚本..."
cat > /usr/local/bin/he-ipv6.sh <<EOFSCRIPT
#!/bin/bash
ip tunnel del he-ipv6 2>/dev/null || true
ip tunnel add he-ipv6 mode sit remote ${HE_SERVER} local ${LOCAL_IPV4} ttl 255
ip link set he-ipv6 mtu 1480 up
ip -6 addr add ${CLIENT_IPV6}/64 dev he-ipv6 2>/dev/null || true
ip -6 addr add ${ROUTED_IPV6}/64 dev he-ipv6 2>/dev/null || true
ip -6 route add default via ${GATEWAY_IPV6} dev he-ipv6 metric 100 2>/dev/null || true
ip -6 route flush cache
EOFSCRIPT

chmod +x /usr/local/bin/he-ipv6.sh
log_success "启动脚本: /usr/local/bin/he-ipv6.sh"

log_info "创建 systemd 服务..."
cat > /etc/systemd/system/he-ipv6.service <<'EOFSERVICE'
[Unit]
Description=HE IPv6 Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/he-ipv6.sh
ExecStop=/sbin/ip tunnel del he-ipv6
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOFSERVICE

systemctl daemon-reload
systemctl enable he-ipv6.service >/dev/null 2>&1
log_success "服务已创建并启用"

log_info "配置防火墙..."
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
ip6tables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
log_success "防火墙已配置"

echo ""
sleep 1

# ========================================
# 验证配置
# ========================================
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}  验证配置${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_info "隧道接口："
ip -6 addr show he-ipv6 | grep inet6 | grep -v fe80 | sed 's/^/  /'
echo ""

echo -n "Ping Google DNS: "
if timeout 3 ping6 -c 1 2001:4860:4860::8888 >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠ 无响应（正常）${NC}"
fi

echo -n "出站 IPv6: "
OUTBOUND=$(timeout 10 curl -6 -s https://api64.ipify.org?format=json 2>/dev/null | jq -r '.ip' 2>/dev/null || echo "")
if [[ -n "$OUTBOUND" ]]; then
    echo -e "${GREEN}${OUTBOUND}${NC}"
    
    echo -n "地理位置: "
    GEO=$(timeout 10 curl -6 -s https://ipapi.co/json/ 2>/dev/null | jq -r '"\(.country_name) - \(.city)"' 2>/dev/null || echo "查询中...")
    echo "${GEO}"
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ 配置成功！${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "配置摘要："
    echo "  出站 IPv6: ${OUTBOUND}"
    echo "  显示位置: ${GEO}"
    echo "  Swap 大小: ${CURRENT_SWAP} MB"
    echo "  启动脚本: /usr/local/bin/he-ipv6.sh"
    echo "  服务状态: systemctl status he-ipv6"
else
    echo -e "${RED}✗ 获取失败${NC}"
    echo ""
    echo -e "${YELLOW}⚠️ 可能需要检查配置${NC}"
fi

echo ""
