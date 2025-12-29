#!/bin/bash

#####################################################################
# HE IPv6 隧道配置脚本 - 菜单式交互版本
# 每一步独立执行，避免出错
#####################################################################

set -e

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

# 检查 root 权限
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
BACKUP_DIR=""

# 配置状态
STEP_1_DONE=false
STEP_2_DONE=false
STEP_3_DONE=false
STEP_4_DONE=false
STEP_5_DONE=false

# ========================================
# 显示 Banner
# ========================================
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        HE IPv6 隧道配置向导 - 分步执行版                  ║
║        Hurricane Electric Tunnel Setup Wizard            ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# ========================================
# 显示主菜单
# ========================================
show_menu() {
    show_banner
    
    echo -e "${CYAN}当前配置状态：${NC}"
    echo ""
    
    if [[ "$STEP_1_DONE" == true ]]; then
        echo -e "  ${GREEN}✓${NC} 步骤 1: 系统信息已获取"
        echo "      本机 IPv4: ${LOCAL_IPV4}"
        echo "      主网卡: ${MAIN_IFACE}"
    else
        echo -e "  ${YELLOW}○${NC} 步骤 1: 获取系统信息（未完成）"
    fi
    
    echo ""
    
    if [[ "$STEP_2_DONE" == true ]]; then
        echo -e "  ${GREEN}✓${NC} 步骤 2: HE 隧道信息已配置"
        echo "      Server IPv4: ${HE_SERVER}"
        echo "      Client IPv6: ${CLIENT_IPV6}"
        echo "      Routed IPv6: ${ROUTED_IPV6}"
    else
        echo -e "  ${YELLOW}○${NC} 步骤 2: 输入 HE 隧道信息（未完成）"
    fi
    
    echo ""
    
    if [[ "$STEP_3_DONE" == true ]]; then
        echo -e "  ${GREEN}✓${NC} 步骤 3: 原生 IPv6 已禁用"
    else
        echo -e "  ${YELLOW}○${NC} 步骤 3: 禁用原生 IPv6（未完成）"
    fi
    
    echo ""
    
    if [[ "$STEP_4_DONE" == true ]]; then
        echo -e "  ${GREEN}✓${NC} 步骤 4: HE 隧道已创建"
    else
        echo -e "  ${YELLOW}○${NC} 步骤 4: 创建 HE 隧道（未完成）"
    fi
    
    echo ""
    
    if [[ "$STEP_5_DONE" == true ]]; then
        echo -e "  ${GREEN}✓${NC} 步骤 5: 配置已验证"
    else
        echo -e "  ${YELLOW}○${NC} 步骤 5: 验证配置（未完成）"
    fi
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}请选择操作：${NC}"
    echo ""
    echo "  1. 获取系统信息"
    echo "  2. 输入 HE 隧道信息"
    echo "  3. 禁用原生 IPv6"
    echo "  4. 安装 HE 隧道"
    echo "  5. 验证配置"
    echo ""
    echo "  0. 退出脚本"
    echo ""
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
}

# ========================================
# 步骤 1: 获取系统信息
# ========================================
step_1_get_system_info() {
    clear
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  步骤 1: 获取系统信息${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
    
    log_info "正在检测本机 IPv4..."
    LOCAL_IPV4=$(curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null || \
                 ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    
    if [[ -n "$LOCAL_IPV4" ]]; then
        log_success "检测到本机 IPv4: ${LOCAL_IPV4}"
    else
        log_warning "无法自动检测 IPv4"
        read -p "请手动输入本机 IPv4: " LOCAL_IPV4
    fi
    
    log_info "正在检测主网卡..."
    MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    log_success "检测到主网卡: ${MAIN_IFACE}"
    
    log_info "正在检测原生 IPv6..."
    NATIVE_IPV6=$(ip -6 addr show scope global | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=/)' | head -n1)
    
    if [[ -n "$NATIVE_IPV6" ]]; then
        log_warning "检测到原生 IPv6: ${NATIVE_IPV6}"
        echo "    此 IPv6 将在步骤 3 中被禁用"
    else
        log_info "未检测到原生 IPv6"
    fi
    
    echo ""
    echo -e "${GREEN}系统信息汇总：${NC}"
    echo "  本机 IPv4: ${LOCAL_IPV4}"
    echo "  主网卡: ${MAIN_IFACE}"
    echo "  原生 IPv6: ${NATIVE_IPV6:-无}"
    echo ""
    
    STEP_1_DONE=true
    log_success "步骤 1 完成！"
    echo ""
    read -p "按回车键返回主菜单..."
}

# ========================================
# 步骤 2: 输入 HE 隧道信息
# ========================================
step_2_input_tunnel_info() {
    if [[ "$STEP_1_DONE" != true ]]; then
        log_error "请先完成步骤 1（获取系统信息）"
        sleep 2
        return
    fi
    
    clear
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  步骤 2: 输入 HE 隧道信息${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
    
    echo "请先登录 https://tunnelbroker.net/ 创建隧道"
    echo "然后准备以下三个信息："
    echo ""
    echo "  1️⃣  Server IPv4 Address"
    echo "  2️⃣  Client IPv6 Address"
    echo "  3️⃣  Routed /64"
    echo ""
    read -p "准备好了吗？按回车继续..." dummy
    
    # 输入 Server IPv4
    echo ""
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo -e "${YELLOW}1/3 输入 Server IPv4 Address${NC}"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo ""
    echo "从 tunnelbroker.net 复制 'Server IPv4 Address'"
    echo -e "${BLUE}示例: 216.66.87.134${NC}"
    echo ""
    
    while true; do
        read -p "Server IPv4: " HE_SERVER
        HE_SERVER=$(echo "$HE_SERVER" | tr -d ' ')
        if [[ -n "$HE_SERVER" && "$HE_SERVER" =~ ^[0-9.]+$ ]]; then
            log_success "已设置: ${HE_SERVER}"
            break
        else
            log_error "输入无效，请重新输入"
        fi
    done
    
    # 输入 Client IPv6
    echo ""
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo -e "${YELLOW}2/3 输入 Client IPv6 Address${NC}"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo ""
    echo "从 tunnelbroker.net 复制 'Client IPv6 Address'"
    echo -e "${BLUE}示例: 2001:470:1f22:57::2${NC}"
    echo ""
    
    while true; do
        read -p "Client IPv6: " CLIENT_IPV6
        CLIENT_IPV6=$(echo "$CLIENT_IPV6" | tr -d ' ')
        if [[ -n "$CLIENT_IPV6" && "$CLIENT_IPV6" == *":"* ]]; then
            log_success "已设置: ${CLIENT_IPV6}"
            break
        else
            log_error "输入无效，请输入完整 IPv6 地址"
        fi
    done
    
    # 自动计算 Gateway
    GATEWAY_IPV6=$(echo "$CLIENT_IPV6" | sed 's/::[0-9a-f]*$/::\1/')
    if [[ "$GATEWAY_IPV6" == "$CLIENT_IPV6" ]]; then
        GATEWAY_IPV6=$(echo "$CLIENT_IPV6" | sed 's/::2$/::1/')
    fi
    log_info "自动计算 Gateway: ${GATEWAY_IPV6}"
    
    # 输入 Routed /64
    echo ""
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo -e "${YELLOW}3/3 输入 Routed /64${NC}"
    echo -e "${CYAN}────────────────────────────────────────${NC}"
    echo ""
    echo "从 tunnelbroker.net 复制 'Routed /64'"
    echo -e "${BLUE}示例 1: 2001:470:1f23:57::1${NC}"
    echo -e "${BLUE}示例 2: 2001:470:1f23:57::/64 (自动处理)${NC}"
    echo ""
    
    while true; do
        read -p "Routed /64: " ROUTED_INPUT
        ROUTED_INPUT=$(echo "$ROUTED_INPUT" | tr -d ' ')
        if [[ -n "$ROUTED_INPUT" && "$ROUTED_INPUT" == *":"* ]]; then
            # 处理不同格式
            if [[ $ROUTED_INPUT == *"/64" ]]; then
                ROUTED_IPV6=$(echo "$ROUTED_INPUT" | sed 's|::/64|::1|')
            elif [[ $ROUTED_INPUT == *"::" && $ROUTED_INPUT != *"::1" ]]; then
                ROUTED_IPV6="${ROUTED_INPUT}1"
            else
                ROUTED_IPV6="$ROUTED_INPUT"
            fi
            log_success "已设置: ${ROUTED_IPV6}"
            break
        else
            log_error "输入无效，请输入完整 IPv6 地址"
        fi
    done
    
    # 显示配置摘要
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  配置摘要${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo "  本机 IPv4:    ${LOCAL_IPV4}"
    echo "  Server IPv4:  ${HE_SERVER}"
    echo "  Client IPv6:  ${CLIENT_IPV6}"
    echo "  Routed IPv6:  ${ROUTED_IPV6}"
    echo "  Gateway IPv6: ${GATEWAY_IPV6}"
    echo ""
    
    read -p "确认信息无误？(yes/no): " confirm
    if [[ "$confirm" == "yes" || "$confirm" == "y" ]]; then
        STEP_2_DONE=true
        log_success "步骤 2 完成！"
    else
        log_warning "已取消，请重新输入"
        STEP_2_DONE=false
    fi
    
    echo ""
    read -p "按回车键返回主菜单..."
}

# ========================================
# 步骤 3: 禁用原生 IPv6
# ========================================
step_3_disable_native_ipv6() {
    if [[ "$STEP_1_DONE" != true ]]; then
        log_error "请先完成步骤 1（获取系统信息）"
        sleep 2
        return
    fi
    
    clear
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  步骤 3: 禁用原生 IPv6${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
    
    log_warning "即将禁用 ${MAIN_IFACE} 的原生 IPv6"
    read -p "确认继续？(yes/no): " confirm
    
    if [[ "$confirm" != "yes" && "$confirm" != "y" ]]; then
        log_warning "操作已取消"
        sleep 2
        return
    fi
    
    echo ""
    log_info "[1/4] 备份现有配置..."
    BACKUP_DIR="/root/network-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -r /etc/netplan/* "$BACKUP_DIR/" 2>/dev/null || true
    cp -r /etc/sysctl.d/* "$BACKUP_DIR/" 2>/dev/null || true
    log_success "已备份到: ${BACKUP_DIR}"
    
    log_info "[2/4] 配置 sysctl（禁用原生 IPv6）..."
    tee /etc/sysctl.d/99-disable-native-ipv6.conf > /dev/null <<EOF
# 禁用 ${MAIN_IFACE} 的原生 IPv6
net.ipv6.conf.${MAIN_IFACE}.disable_ipv6=1
net.ipv6.conf.${MAIN_IFACE}.accept_ra=0
net.ipv6.conf.${MAIN_IFACE}.autoconf=0
EOF
    sysctl -p /etc/sysctl.d/99-disable-native-ipv6.conf >/dev/null 2>&1
    log_success "sysctl 已配置"
    
    log_info "[3/4] 更新 Netplan 配置..."
    tee /etc/netplan/50-cloud-init.yaml > /dev/null <<EOF
network:
  version: 2
  ethernets:
    ${MAIN_IFACE}:
      dhcp4: true
      dhcp6: false
      accept-ra: false
EOF
    chmod 600 /etc/netplan/50-cloud-init.yaml
    log_success "Netplan 已更新"
    
    log_info "[4/4] 清理原生 IPv6 地址和路由..."
    ip -6 addr flush dev ${MAIN_IFACE} scope global 2>/dev/null || true
    ip -6 route flush dev ${MAIN_IFACE} 2>/dev/null || true
    log_success "原生 IPv6 已清理"
    
    echo ""
    STEP_3_DONE=true
    log_success "步骤 3 完成！原生 IPv6 已禁用"
    echo ""
    read -p "按回车键返回主菜单..."
}

# ========================================
# 步骤 4: 安装 HE 隧道
# ========================================
step_4_install_he_tunnel() {
    if [[ "$STEP_1_DONE" != true || "$STEP_2_DONE" != true || "$STEP_3_DONE" != true ]]; then
        log_error "请先完成前面的步骤（1、2、3）"
        sleep 2
        return
    fi
    
    clear
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  步骤 4: 安装 HE 隧道${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
    
    echo "即将创建 HE 隧道："
    echo "  Server: ${HE_SERVER}"
    echo "  Local: ${LOCAL_IPV4}"
    echo "  Client IPv6: ${CLIENT_IPV6}"
    echo "  Routed IPv6: ${ROUTED_IPV6}"
    echo ""
    
    read -p "确认开始安装？(yes/no): " confirm
    if [[ "$confirm" != "yes" && "$confirm" != "y" ]]; then
        log_warning "操作已取消"
        sleep 2
        return
    fi
    
    echo ""
    log_info "[1/5] 安装必要工具..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y net-tools iproute2 curl iptables-persistent jq >/dev/null 2>&1
    log_success "工具安装完成"
    
    log_info "[2/5] 创建 HE 隧道配置文件..."
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
    chmod 600 /etc/netplan/99-he-tunnel.yaml
    log_success "配置文件已创建"
    
    log_info "[3/5] 创建隧道接口..."
    ip tunnel del he-ipv6 2>/dev/null || true
    ip tunnel add he-ipv6 mode sit remote ${HE_SERVER} local ${LOCAL_IPV4} ttl 255
    ip link set he-ipv6 mtu 1480
    ip link set he-ipv6 up
    ip -6 addr add ${CLIENT_IPV6}/64 dev he-ipv6
    ip -6 addr add ${ROUTED_IPV6}/64 dev he-ipv6
    log_success "隧道接口已创建"
    
    log_info "[4/5] 配置路由..."
    ip -6 route add default via ${GATEWAY_IPV6} dev he-ipv6 metric 1024 2>/dev/null || true
    ip -6 route flush cache
    log_success "路由已配置"
    
    log_info "[5/5] 配置防火墙（MSS Clamping）..."
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    ip6tables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    netfilter-persistent save >/dev/null 2>&1 || true
    log_success "防火墙已配置"
    
    echo ""
    STEP_4_DONE=true
    log_success "步骤 4 完成！HE 隧道已安装"
    echo ""
    read -p "按回车键返回主菜单..."
}

# ========================================
# 步骤 5: 验证配置
# ========================================
step_5_verify_config() {
    if [[ "$STEP_4_DONE" != true ]]; then
        log_error "请先完成步骤 4（安装 HE 隧道）"
        sleep 2
        return
    fi
    
    clear
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  步骤 5: 验证配置${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
    
    log_info "[1/5] 检查隧道接口..."
    if ip link show he-ipv6 &>/dev/null; then
        log_success "✓ 隧道接口存在"
        ip -6 addr show he-ipv6 | grep inet6
    else
        log_error "✗ 隧道接口不存在"
    fi
    
    echo ""
    log_info "[2/5] 测试 HE 网关..."
    if timeout 10 ping6 -c 3 ${GATEWAY_IPV6} >/dev/null 2>&1; then
        log_success "✓ 可以 ping 通 HE 网关"
    else
        log_warning "⚠ 无法 ping 通网关"
    fi
    
    echo ""
    log_info "[3/5] 测试外部连通性..."
    if timeout 10 ping6 -c 3 2001:4860:4860::8888 >/dev/null 2>&1; then
        log_success "✓ 可以 ping 通 Google DNS"
    else
        log_warning "⚠ 无法 ping 通外部"
    fi
    
    echo ""
    log_info "[4/5] 检测出站 IPv6..."
    OUTBOUND_IPV6=$(timeout 10 curl -6 -s https://api64.ipify.org?format=json 2>/dev/null | jq -r '.ip' 2>/dev/null || echo "")
    
    if [[ -n "$OUTBOUND_IPV6" ]]; then
        log_success "✓ 出站 IPv6: ${OUTBOUND_IPV6}"
    else
        log_error "✗ 无法获取出站 IPv6"
    fi
    
    echo ""
    log_info "[5/5] 查询地理位置..."
    GEO_INFO=$(timeout 10 curl -6 -s https://ipapi.co/json/ 2>/dev/null)
    if [[ -n "$GEO_INFO" ]]; then
        COUNTRY=$(echo "$GEO_INFO" | jq -r '.country_name' 2>/dev/null)
        CITY=$(echo "$GEO_INFO" | jq -r '.city' 2>/dev/null)
        COUNTRY_CODE=$(echo "$GEO_INFO" | jq -r '.country' 2>/dev/null)
        log_success "✓ 位置: ${COUNTRY} (${COUNTRY_CODE}) - ${CITY}"
    else
        log_warning "⚠ 无法获取地理位置"
    fi
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  配置验证完成${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    
    if [[ -n "$OUTBOUND_IPV6" ]]; then
        STEP_5_DONE=true
        echo "✅ HE 隧道配置成功！"
        echo ""
        echo "配置摘要："
        echo "  出站 IPv6: ${OUTBOUND_IPV6}"
        echo "  显示位置: ${COUNTRY} - ${CITY}"
        echo "  备份位置: ${BACKUP_DIR}"
    else
        echo "⚠️ 配置可能存在问题，请检查"
    fi
    
    echo ""
    read -p "按回车键返回主菜单..."
}

# ========================================
# 主循环
# ========================================
main() {
    while true; do
        show_menu
        
        read -p "请选择操作 [0-5]: " choice
        
        case $choice in
            1)
                step_1_get_system_info
                ;;
            2)
                step_2_input_tunnel_info
                ;;
            3)
                step_3_disable_native_ipv6
                ;;
            4)
                step_4_install_he_tunnel
                ;;
            5)
                step_5_verify_config
                ;;
            0)
                echo ""
                log_info "退出脚本"
                exit 0
                ;;
            *)
                log_error "无效选择，请输入 0-5"
                sleep 2
                ;;
        esac
    done
}

# 启动脚本
main
