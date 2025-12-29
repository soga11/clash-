#!/bin/bash

#####################################################################
# HE IPv6 隧道自动配置脚本（交互式版本）
# 适用于：已有原生 IPv6 的 VPS，需要用 HE 隧道替代
# 作者：Based on your successful configuration
# 支持：Ubuntu 20.04/22.04, Debian 11/12
#####################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本必须以 root 权限运行"
   echo "请使用: sudo bash $0"
   exit 1
fi

# Banner
clear
echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     HE IPv6 隧道自动配置脚本                              ║
║     Hurricane Electric Tunnel Configuration              ║
║                                                           ║
║     功能：禁用原生 IPv6，配置 HE 隧道                     ║
║     支持：Ubuntu/Debian                                   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 检测系统信息
log_info "检测系统环境..."
echo ""

# 检测本机 IPv4
LOCAL_IPV4=$(curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null || \
             ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)

if [[ -z "$LOCAL_IPV4" ]]; then
    log_error "无法检测到本机 IPv4 地址"
    exit 1
fi

# 检测原生 IPv6
NATIVE_IPV6=$(ip -6 addr show scope global | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=/)' | head -n1)

# 检测主网卡
MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# 显示系统信息
echo -e "${GREEN}系统信息：${NC}"
echo "  本机 IPv4: ${LOCAL_IPV4}"
if [[ -n "$NATIVE_IPV6" ]]; then
    echo "  原生 IPv6: ${NATIVE_IPV6} (将被禁用)"
else
    echo "  原生 IPv6: 未检测到"
fi
echo "  主网卡: ${MAIN_IFACE}"
echo ""

# 输入 HE 隧道信息
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}请输入 HE 隧道信息${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "请先登录 https://tunnelbroker.net/ 创建隧道"
echo ""

# Server IPv4 Address
while true; do
    read -p "$(echo -e ${CYAN}输入 Server IPv4 Address${NC}) (如 216.66.90.30): " HE_SERVER
    if [[ $HE_SERVER =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        break
    else
        log_error "无效的 IPv4 地址，请重新输入"
    fi
done

# Client IPv6 Address
while true; do
    read -p "$(echo -e ${CYAN}输入 Client IPv6 Address${NC}) (如 2001:470:1f28:26a::2): " CLIENT_IPV6
    if [[ $CLIENT_IPV6 =~ : ]]; then
        break
    else
        log_error "无效的 IPv6 地址，请重新输入"
    fi
done

# Routed /64
while true; do
    read -p "$(echo -e ${CYAN}输入 Routed /64 前缀${NC}) (如 2001:470:1f29:26a::1): " ROUTED_IPV6
    if [[ $ROUTED_IPV6 =~ : ]]; then
        break
    else
        log_error "无效的 IPv6 地址，请重新输入"
    fi
done

# 计算 Gateway（从 Client IPv6 推导）
GATEWAY_IPV6=$(echo "$CLIENT_IPV6" | sed 's/::[0-9]*$/::1/')

# 确认信息
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}配置摘要${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Server IPv4:    ${HE_SERVER}"
echo "  Local IPv4:     ${LOCAL_IPV4}"
echo "  Client IPv6:    ${CLIENT_IPV6}"
echo "  Routed IPv6:    ${ROUTED_IPV6}"
echo "  Gateway IPv6:   ${GATEWAY_IPV6}"
echo "  主网卡:         ${MAIN_IFACE}"
echo ""
echo -e "${YELLOW}操作：${NC}"
echo "  1. 禁用 ${MAIN_IFACE} 的原生 IPv6"
echo "  2. 创建 HE IPv6 隧道"
echo "  3. 配置防火墙规则"
echo "  4. 测试连通性"
echo ""

read -p "$(echo -e ${GREEN}确认配置并继续？[y/N]${NC}) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_error "配置已取消"
    exit 1
fi

# 开始配置
echo ""
log_info "开始配置 HE IPv6 隧道..."
echo ""

# 步骤 1：备份配置
log_info "[1/8] 备份现有配置..."
BACKUP_DIR="/root/network-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r /etc/netplan/* "$BACKUP_DIR/" 2>/dev/null || true
cp -r /etc/sysctl.d/* "$BACKUP_DIR/" 2>/dev/null || true
log_success "配置已备份到: ${BACKUP_DIR}"

# 步骤 2：安装必要工具
log_info "[2/8] 安装必要工具..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y net-tools iproute2 curl iptables-persistent jq >/dev/null 2>&1
log_success "工具安装完成"

# 步骤 3：配置 sysctl 禁用原生 IPv6
log_info "[3/8] 配置内核参数..."
tee /etc/sysctl.d/99-disable-native-ipv6.conf > /dev/null <<EOF
# 禁用 ${MAIN_IFACE} 的原生 IPv6
net.ipv6.conf.${MAIN_IFACE}.disable_ipv6=1
net.ipv6.conf.${MAIN_IFACE}.accept_ra=0
net.ipv6.conf.${MAIN_IFACE}.autoconf=0
net.ipv6.conf.${MAIN_IFACE}.accept_ra_defrtr=0
net.ipv6.conf.${MAIN_IFACE}.accept_ra_pinfo=0
EOF

sysctl -p /etc/sysctl.d/99-disable-native-ipv6.conf >/dev/null 2>&1
log_success "内核参数已配置"

# 步骤 4：配置 Netplan
log_info "[4/8] 配置 Netplan..."

# 主网卡配置（禁用 IPv6）
MAC_ADDR=$(ip link show ${MAIN_IFACE} | grep link/ether | awk '{print $2}')
tee /etc/netplan/50-cloud-init.yaml > /dev/null <<EOF
network:
  version: 2
  ethernets:
    ${MAIN_IFACE}:
      dhcp4: true
      dhcp6: false
      accept-ra: false
EOF

# HE 隧道配置
tee /etc/netplan/99-he-tunnel.yaml > /dev/null <<EOF
network:
  version: 2
  tunnels:
    he-ipv6:
      mode: sit
      remote: ${HE_SERVER}
      local: ${LOCAL_IPV4}
      addresses:
        - "${CLIENT_IPV6}/64"
        - "${ROUTED_IPV6}/64"
      routes:
        - to: default
          via: "${GATEWAY_IPV6}"
EOF

chmod 600 /etc/netplan/*.yaml
log_success "Netplan 配置已创建"

# 步骤 5：清理原生 IPv6
log_info "[5/8] 清理原生 IPv6..."
ip -6 addr flush dev ${MAIN_IFACE} scope global 2>/dev/null || true
ip -6 route flush dev ${MAIN_IFACE} 2>/dev/null || true
log_success "原生 IPv6 已清理"

# 步骤 6：手动创建隧道（避免 netplan apply 卡住）
log_info "[6/8] 创建 HE 隧道接口..."
ip tunnel del he-ipv6 2>/dev/null || true
ip tunnel add he-ipv6 mode sit remote ${HE_SERVER} local ${LOCAL_IPV4} ttl 255
ip link set he-ipv6 mtu 1480
ip link set he-ipv6 up
ip -6 addr add ${CLIENT_IPV6}/64 dev he-ipv6
ip -6 addr add ${ROUTED_IPV6}/64 dev he-ipv6
ip -6 route add default via ${GATEWAY_IPV6} dev he-ipv6 metric 1024 2>/dev/null || true
ip -6 route flush cache
log_success "隧道接口已创建"

# 步骤 7：配置防火墙
log_info "[7/8] 配置防火墙规则..."
# MSS Clamping
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
ip6tables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
netfilter-persistent save >/dev/null 2>&1 || true
log_success "防火墙规则已配置"

# 步骤 8：验证配置
log_info "[8/8] 验证配置..."
echo ""

# 等待网络稳定
sleep 3

# 检查隧道接口
if ip link show he-ipv6 &>/dev/null; then
    log_success "✓ 隧道接口已创建"
else
    log_error "✗ 隧道接口创建失败"
    exit 1
fi

# 检查 IPv6 地址
echo ""
echo -e "${CYAN}隧道接口信息：${NC}"
ip -6 addr show he-ipv6 | grep -E "inet6|flags"

# 测试 HE 网关
echo ""
log_info "测试 HE 网关连通性..."
if timeout 10 ping6 -c 3 ${GATEWAY_IPV6} >/dev/null 2>&1; then
    log_success "✓ 可以 ping 通 HE 网关"
else
    log_warning "⚠ 无法 ping 通 HE 网关，但可能仍能正常工作"
fi

# 测试外部连通性
echo ""
log_info "测试外部 IPv6 连通性..."
if timeout 10 ping6 -c 3 2001:4860:4860::8888 >/dev/null 2>&1; then
    log_success "✓ 可以 ping 通 Google DNS"
else
    log_warning "⚠ 无法 ping 通外部 IPv6"
fi

# 获取出站 IP
echo ""
log_info "检测出站 IPv6 地址..."
OUTBOUND_IPV6=$(timeout 10 curl -6 -s https://api64.ipify.org?format=json 2>/dev/null | jq -r '.ip' 2>/dev/null || echo "")

if [[ -n "$OUTBOUND_IPV6" ]]; then
    log_success "✓ 出站 IPv6: ${OUTBOUND_IPV6}"
    
    # 获取地理位置
    GEO_INFO=$(timeout 10 curl -6 -s https://ipapi.co/json/ 2>/dev/null)
    if [[ -n "$GEO_INFO" ]]; then
        COUNTRY=$(echo "$GEO_INFO" | jq -r '.country_name' 2>/dev/null || echo "未知")
        CITY=$(echo "$GEO_INFO" | jq -r '.city' 2>/dev/null || echo "未知")
        log_success "✓ 地理位置: ${COUNTRY} - ${CITY}"
    fi
else
    log_error "✗ 无法获取出站 IPv6 地址"
    log_warning "可能需要调整 MTU 或检查防火墙规则"
fi

# 完成
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}           HE IPv6 隧道配置完成！${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}配置摘要：${NC}"
echo "  ✓ 原生 IPv6: 已禁用"
echo "  ✓ HE 隧道: 已启用"
echo "  ✓ Client IPv6: ${CLIENT_IPV6}"
echo "  ✓ Routed IPv6: ${ROUTED_IPV6}"
if [[ -n "$OUTBOUND_IPV6" ]]; then
    echo "  ✓ 出站 IP: ${OUTBOUND_IPV6}"
    echo "  ✓ 地理位置: ${COUNTRY} - ${CITY}"
fi
echo "  ✓ 备份位置: ${BACKUP_DIR}"
echo ""

# 恢复方法
echo -e "${YELLOW}如需恢复原生 IPv6，请执行：${NC}"
echo "  sudo rm /etc/netplan/99-he-tunnel.yaml"
echo "  sudo rm /etc/sysctl.d/99-disable-native-ipv6.conf"
echo "  sudo sysctl -w net.ipv6.conf.${MAIN_IFACE}.disable_ipv6=0"
echo "  sudo ip tunnel del he-ipv6"
echo "  sudo netplan apply"
echo ""

# 哪吒监控提示
echo -e "${CYAN}下一步（可选）：${NC}"
echo "  1. 安装/重启哪吒 Agent"
echo "  2. 应用 IPv6 优先脚本："
echo "     bash <(curl https://raw.githubusercontent.com/xykt/Utilities/main/nezha/ipv6flag.sh)"
echo ""

# 测试重启
read -p "$(echo -e ${YELLOW}是否测试重启以验证持久化？[y/N]${NC}) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "系统将在 5 秒后重启..."
    sleep 5
    reboot
fi

log_success "配置完成，祝使用愉快！"
