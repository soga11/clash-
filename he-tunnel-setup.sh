#!/bin/bash

#####################################################################
# HE IPv6 隧道配置脚本 - AWS 兼容版 + 状态保存
# 支持 Netplan、传统网络配置、状态持久化
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

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本必须以 root 权限运行"
   exit 1
fi

# 状态文件路径
STATE_FILE="/root/.he-tunnel-state"

# 全局变量
LOCAL_IPV4=""
HE_SERVER=""
CLIENT_IPV6=""
ROUTED_IPV6=""
GATEWAY_IPV6=""
MAIN_IFACE=""
BACKUP_DIR=""
NETWORK_TYPE=""  # netplan, traditional, aws

# 配置状态
STEP_1_DONE=false
STEP_2_DONE=false
STEP_3_DONE=false
STEP_4_DONE=false
STEP_5_DONE=false

# ========================================
# 状态管理
# ========================================

# 保存状态
save_state() {
    cat > "$STATE_FILE" << EOF
LOCAL_IPV4="$LOCAL_IPV4"
HE_SERVER="$HE_SERVER"
CLIENT_IPV6="$CLIENT_IPV6"
ROUTED_IPV6="$ROUTED_IPV6"
GATEWAY_IPV6="$GATEWAY_IPV6"
MAIN_IFACE="$MAIN_IFACE"
BACKUP_DIR="$BACKUP_DIR"
NETWORK_TYPE="$NETWORK_TYPE"
STEP_1_DONE=$STEP_1_DONE
STEP_2_DONE=$STEP_2_DONE
STEP_3_DONE=$STEP_3_DONE
STEP_4_DONE=$STEP_4_DONE
STEP_5_DONE=$STEP_5_DONE
EOF
    chmod 600 "$STATE_FILE"
}

# 加载状态
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        return 0
    fi
    return 1
}

# 清除状态
clear_state() {
    rm -f "$STATE_FILE"
    log_info "已清除保存的配置"
}

# ========================================
# 检测网络配置类型
# ========================================
detect_network_type() {
    if [[ -d /etc/netplan ]] && ls /etc/netplan/*.yaml &>/dev/null; then
        NETWORK_TYPE="netplan"
        log_info "检测到 Netplan 配置系统"
    elif [[ -f /etc/network/interfaces ]]; then
        NETWORK_TYPE="traditional"
        log_info "检测到传统网络配置（Debian/Ubuntu）"
    elif [[ -f /etc/sysconfig/network-scripts/ifcfg-eth0 ]]; then
        NETWORK_TYPE="redhat"
        log_info "检测到 RedHat 系网络配置"
    else
        NETWORK_TYPE="unknown"
        log_warning "未识别的网络配置类型，将使用通用方法"
    fi
}

# ========================================
# 显示 Banner
# ========================================
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        HE IPv6 隧道配置向导 - 增强版                      ║
║        Hurricane Electric Tunnel Setup Wizard            ║
║        支持 AWS/Vultr/传统配置 + 状态保存                 ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# ========================================
# 确认函数
# ========================================
confirm() {
    local prompt="$1"
    local default="${2:-y}"
    
    if [[ "$default" == "y" ]]; then
        read -p "${prompt} [Y/n]: " response
        response=${response:-y}
    else
        read -p "${prompt} [y/N]: " response
        response=${response:-n}
    fi
    
    [[ "$response" =~ ^[Yy]$ ]]
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
        echo "      网络类型: ${NETWORK_TYPE}"
    else
        echo -e "  ${YELLOW}○${NC} 步骤 1: 获取系统信息"
    fi
    
    echo ""
    
    if [[ "$STEP_2_DONE" == true ]]; then
        echo -e "  ${GREEN}✓${NC} 步骤 2: HE 隧道信息已配置"
        echo "      Server IPv4: ${HE_SERVER}"
        echo "      Client IPv6: ${CLIENT_IPV6}"
        echo "      Routed IPv6: ${ROUTED_IPV6}"
    else
        echo -e "  ${YELLOW}○${NC} 步骤 2: 输入 HE 隧道信息"
    fi
    
    echo ""
    
    [[ "$STEP_3_DONE" == true ]] && echo -e "  ${GREEN}✓${NC} 步骤 3: 原生 IPv6 已禁用（可选）" || echo -e "  ${YELLOW}○${NC} 步骤 3: 禁用原生 IPv6（可选）"
    echo ""
    [[ "$STEP_4_DONE" == true ]] && echo -e "  ${GREEN}✓${NC} 步骤 4: HE 隧道已创建" || echo -e "  ${YELLOW}○${NC} 步骤 4: 创建 HE 隧道"
    echo ""
    [[ "$STEP_5_DONE" == true ]] && echo -e "  ${GREEN}✓${NC} 步骤 5: 配置已验证" || echo -e "  ${YELLOW}○${NC} 步骤 5: 验证配置"
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}请选择操作：${NC}"
    echo ""
    echo -e "  ${GREEN}1${NC}. 获取系统信息"
    echo -e "  ${GREEN}2${NC}. 输入 HE 隧道信息"
    echo -e "  ${GREEN}3${NC}. 禁用原生 IPv6（可选）"
    echo -e "  ${GREEN}4${NC}. 安装 HE 隧道"
    echo -e "  ${GREEN}5${NC}. 验证配置"
    echo ""
    echo -e "  ${GREEN}9${NC}. 一键完整安装（推荐）"
    echo -e "  ${YELLOW}8${NC}. 清除保存的配置"
    echo -e "  ${RED}0${NC}. 退出脚本"
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
    
    log_info "检测本机 IPv4..."
    LOCAL_IPV4=$(curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null || \
                 ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    
    if [[ -n "$LOCAL_IPV4" ]]; then
        log_success "本机 IPv4: ${LOCAL_IPV4}"
    else
        read -p "无法自动检测，请输入本机 IPv4: " LOCAL_IPV4
    fi
    
    log_info "检测主网卡..."
    MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    log_success "主网卡: ${MAIN_IFACE}"
    
    log_info "检测网络配置类型..."
    detect_network_type
    
    NATIVE_IPV6=$(ip -6 addr show scope global | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=/)' | head -n1)
    [[ -n "$NATIVE_IPV6" ]] && log_warning "原生 IPv6: ${NATIVE_IPV6}" || log_info "无原生 IPv6"
    
    echo ""
    STEP_1_DONE=true
    save_state
    log_success "步骤 1 完成！配置已保存"
    echo ""
    read -p "按回车继续..."
}

# ========================================
# 步骤 2: 输入 HE 隧道信息
# ========================================
step_2_input_tunnel_info() {
    if [[ "$STEP_1_DONE" != true ]]; then
        log_error "请先完成步骤 1"
        sleep 1
        return
    fi
    
    clear
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  步骤 2: 输入 HE 隧道信息${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
    
    echo "从 https://tunnelbroker.net/ 复制以下信息："
    echo ""
    
    # Server IPv4
    echo -e "${CYAN}[1/3] Server IPv4 Address${NC}"
    echo -e "${BLUE}示例: 216.66.87.134${NC}"
    while true; do
        read -p "输入: " HE_SERVER
        HE_SERVER=$(echo "$HE_SERVER" | tr -d ' ')
        [[ -n "$HE_SERVER" && "$HE_SERVER" =~ ^[0-9.]+$ ]] && break
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
        [[ -n "$CLIENT_IPV6" && "$CLIENT_IPV6" == *":"* ]] && break
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
        [[ -n "$ROUTED_INPUT" && "$ROUTED_INPUT" == *":"* ]] && break
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
    
    if confirm "确认信息无误？"; then
        STEP_2_DONE=true
        save_state
        log_success "步骤 2 完成！配置已保存"
    else
        log_warning "已取消，请重新输入"
        STEP_2_DONE=false
    fi
    
    echo ""
    read -p "按回车继续..."
}

# ========================================
# 步骤 3: 禁用原生 IPv6（支持多种系统）
# ========================================
step_3_disable_native_ipv6() {
    if [[ "$STEP_1_DONE" != true ]]; then
        log_error "请先完成步骤 1"
        sleep 1
        return
    fi
    
    clear
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  步骤 3: 禁用原生 IPv6（可选）${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
    
    # 检查是否有原生 IPv6
    NATIVE_IPV6=$(ip -6 addr show scope global | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=/)' | head -n1)
    if [[ -z "$NATIVE_IPV6" ]]; then
        log_info "未检测到原生 IPv6，将配置预防性禁用参数"
        if ! confirm "继续配置？"; then
            STEP_3_DONE=true
            save_state
            log_info "已跳过步骤 3"
            read -p "按回车继续..."
            return
        fi
    else
        log_warning "检测到原生 IPv6: ${NATIVE_IPV6}"
        if ! confirm "即将禁用 ${MAIN_IFACE} 的原生 IPv6，继续？"; then
            log_warning "操作已取消"
            sleep 1
            return
        fi
    fi
    
    echo ""
    log_info "备份配置..."
    BACKUP_DIR="/root/network-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # 根据不同系统类型备份
    case "$NETWORK_TYPE" in
        netplan)
            cp -r /etc/netplan/* "$BACKUP_DIR/" 2>/dev/null || true
            ;;
        traditional)
            cp /etc/network/interfaces "$BACKUP_DIR/" 2>/dev/null || true
            ;;
        redhat)
            cp /etc/sysconfig/network-scripts/ifcfg-${MAIN_IFACE} "$BACKUP_DIR/" 2>/dev/null || true
            ;;
    esac
    
    log_success "已备份到: $BACKUP_DIR"
    
    log_info "配置系统参数..."
    tee /etc/sysctl.d/99-disable-native-ipv6.conf > /dev/null <<EOF
net.ipv6.conf.${MAIN_IFACE}.disable_ipv6=0
net.ipv6.conf.${MAIN_IFACE}.accept_ra=0
net.ipv6.conf.${MAIN_IFACE}.autoconf=0
net.ipv6.conf.default.accept_ra=0
net.ipv6.conf.all.accept_ra=0
EOF
    sysctl -p /etc/sysctl.d/99-disable-native-ipv6.conf >/dev/null 2>&1
    log_success "系统参数已配置"
    
    log_info "更新网络配置..."
    
    case "$NETWORK_TYPE" in
        netplan)
            # Netplan 配置
            if [[ -f /etc/netplan/50-cloud-init.yaml ]]; then
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
                log_success "Netplan 配置已更新"
            else
                log_warning "未找到 Netplan 配置文件，跳过"
            fi
            ;;
            
        traditional)
            # 传统 Debian/Ubuntu 配置
            if ! grep -q "iface ${MAIN_IFACE} inet6" /etc/network/interfaces; then
                echo "" >> /etc/network/interfaces
                echo "# Disable IPv6 on ${MAIN_IFACE}" >> /etc/network/interfaces
                echo "iface ${MAIN_IFACE} inet6 manual" >> /etc/network/interfaces
                echo "    pre-up echo 0 > /proc/sys/net/ipv6/conf/${MAIN_IFACE}/accept_ra" >> /etc/network/interfaces
            fi
            log_success "传统网络配置已更新"
            ;;
            
        redhat)
            # RedHat 系配置
            if [[ -f /etc/sysconfig/network-scripts/ifcfg-${MAIN_IFACE} ]]; then
                if ! grep -q "IPV6INIT=no" /etc/sysconfig/network-scripts/ifcfg-${MAIN_IFACE}; then
                    echo "IPV6INIT=no" >> /etc/sysconfig/network-scripts/ifcfg-${MAIN_IFACE}
                    echo "IPV6_AUTOCONF=no" >> /etc/sysconfig/network-scripts/ifcfg-${MAIN_IFACE}
                fi
                log_success "RedHat 网络配置已更新"
            fi
            ;;
            
        *)
            log_warning "未知网络类型，仅配置 sysctl 参数"
            ;;
    esac
    
    log_info "清理 IPv6..."
    ip -6 addr flush dev ${MAIN_IFACE} scope global 2>/dev/null || true
    ip -6 route flush dev ${MAIN_IFACE} 2>/dev/null || true
    log_success "清理完成"
    
    echo ""
    STEP_3_DONE=true
    save_state
    log_success "步骤 3 完成！配置已保存"
    echo ""
    read -p "按回车继续..."
}

# ========================================
# 步骤 4: 安装 HE 隧道
# ========================================
step_4_install_he_tunnel() {
    if [[ "$STEP_1_DONE" != true || "$STEP_2_DONE" != true ]]; then
        log_error "请先完成步骤 1 和步骤 2"
        sleep 1
        return
    fi
    
    # 步骤 3 可选，如果未执行则自动配置基础禁用
    if [[ "$STEP_3_DONE" != true ]]; then
        log_warning "步骤 3 未执行，将自动配置基础参数..."
        tee /etc/sysctl.d/99-disable-ipv6-ra.conf > /dev/null <<EOF
net.ipv6.conf.default.accept_ra=0
net.ipv6.conf.all.accept_ra=0
EOF
        sysctl -p /etc/sysctl.d/99-disable-ipv6-ra.conf >/dev/null 2>&1
        log_success "基础参数已配置"
    fi
    
    clear
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  步骤 4: 安装 HE 隧道${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
    
    if ! confirm "开始安装 HE 隧道？"; then
        log_warning "操作已取消"
        sleep 1
        return
    fi
    
    echo ""
    log_info "安装工具..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y net-tools iproute2 curl iptables-persistent jq >/dev/null 2>&1
    log_success "工具已安装"
    
    log_info "创建配置文件..."
    
    # 创建启动脚本（通用方法）
    tee /usr/local/bin/he-ipv6-tunnel.sh > /dev/null <<EOF
#!/bin/bash
# HE IPv6 Tunnel Startup Script

# 删除旧隧道
ip tunnel del he-ipv6 2>/dev/null || true

# 创建隧道
ip tunnel add he-ipv6 mode sit remote ${HE_SERVER} local ${LOCAL_IPV4} ttl 255
ip link set he-ipv6 mtu 1480
ip link set he-ipv6 up

# 添加地址
ip -6 addr add ${CLIENT_IPV6}/64 dev he-ipv6
ip -6 addr add ${ROUTED_IPV6}/64 dev he-ipv6

# 添加路由
ip -6 route add default via ${GATEWAY_IPV6} dev he-ipv6 metric 1024 2>/dev/null || true

# 刷新缓存
ip -6 route flush cache

echo "HE IPv6 tunnel started successfully"
EOF
    chmod +x /usr/local/bin/he-ipv6-tunnel.sh
    log_success "启动脚本已创建"
    
    log_info "创建 systemd 服务..."
    tee /etc/systemd/system/he-ipv6-tunnel.service > /dev/null <<EOF
[Unit]
Description=HE IPv6 Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/he-ipv6-tunnel.sh
ExecStop=/sbin/ip tunnel del he-ipv6

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable he-ipv6-tunnel.service >/dev/null 2>&1
    log_success "服务已创建并设置开机启动"
    
    log_info "启动隧道..."
    /usr/local/bin/he-ipv6-tunnel.sh
    log_success "隧道已启动"
    
    log_info "配置防火墙..."
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    ip6tables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    netfilter-persistent save >/dev/null 2>&1 || true
    log_success "防火墙已配置"
    
    echo ""
    STEP_4_DONE=true
    save_state
    log_success "步骤 4 完成！配置已保存"
    echo ""
    read -p "按回车继续..."
}

# ========================================
# 步骤 5: 验证配置
# ========================================
step_5_verify_config() {
    if [[ "$STEP_4_DONE" != true ]]; then
        log_error "请先完成步骤 4"
        sleep 1
        return
    fi
    
    clear
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  步骤 5: 验证配置${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
    
    # 检查接口
    if ip link show he-ipv6 &>/dev/null; then
        log_success "隧道接口存在"
        ip -6 addr show he-ipv6 | grep inet6 | sed 's/^/    /'
    else
        log_error "隧道接口不存在"
    fi
    
    echo ""
    
    # 测试网关
    log_info "测试 HE 网关..."
    timeout 10 ping6 -c 3 ${GATEWAY_IPV6} >/dev/null 2>&1 && log_success "网关连通" || log_warning "网关无响应"
    
    # 测试外部
    log_info "测试 Google DNS..."
    timeout 10 ping6 -c 3 2001:4860:4860::8888 >/dev/null 2>&1 && log_success "外部连通" || log_warning "外部无响应"
    
    # 出站 IP
    echo ""
    log_info "检测出站 IPv6..."
    OUTBOUND_IPV6=$(timeout 10 curl -6 -s https://api64.ipify.org?format=json 2>/dev/null | jq -r '.ip' 2>/dev/null || echo "")
    
    if [[ -n "$OUTBOUND_IPV6" ]]; then
        log_success "出站 IPv6: ${OUTBOUND_IPV6}"
        
        # 地理位置
        GEO_INFO=$(timeout 10 curl -6 -s https://ipapi.co/json/ 2>/dev/null)
        if [[ -n "$GEO_INFO" ]]; then
            COUNTRY=$(echo "$GEO_INFO" | jq -r '.country_name' 2>/dev/null)
            CITY=$(echo "$GEO_INFO" | jq -r '.city' 2>/dev/null)
            COUNTRY_CODE=$(echo "$GEO_INFO" | jq -r '.country' 2>/dev/null)
            log_success "位置: ${COUNTRY} (${COUNTRY_CODE}) - ${CITY}"
        fi
    else
        log_error "无法获取出站 IPv6"
    fi
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    
    if [[ -n "$OUTBOUND_IPV6" ]]; then
        STEP_5_DONE=true
        save_state
        echo -e "${GREEN}✅ HE 隧道配置成功！${NC}"
        echo ""
        echo "配置摘要："
        echo "  出站 IPv6: ${OUTBOUND_IPV6}"
        [[ -n "$COUNTRY" ]] && echo "  显示位置: ${COUNTRY} - ${CITY}"
        echo "  配置文件: /usr/local/bin/he-ipv6-tunnel.sh"
        echo "  服务状态: systemctl status he-ipv6-tunnel"
    else
        echo -e "${YELLOW}⚠️ 配置可能存在问题${NC}"
    fi
    
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    read -p "按回车继续..."
}

# ========================================
# 一键完整安装
# ========================================
one_click_install() {
    clear
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  一键完整安装 HE IPv6 隧道${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo ""
    
    # 步骤 1
    log_info "【1/5】获取系统信息..."
    LOCAL_IPV4=$(curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null || \
                 ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    detect_network_type
    
    if [[ -z "$LOCAL_IPV4" ]]; then
        read -p "无法检测 IPv4，请输入: " LOCAL_IPV4
    fi
    
    log_success "IPv4: ${LOCAL_IPV4}, 网卡: ${MAIN_IFACE}, 类型: ${NETWORK_TYPE}"
    STEP_1_DONE=true
    save_state
    echo ""
    
    # 步骤 2
    log_info "【2/5】输入 HE 隧道信息..."
    echo ""
    
    echo -e "${CYAN}[1/3] Server IPv4:${NC}"
    while true; do
        read -p "输入: " HE_SERVER
        HE_SERVER=$(echo "$HE_SERVER" | tr -d ' ')
        [[ -n "$HE_SERVER" && "$HE_SERVER" =~ ^[0-9.]+$ ]] && break
        log_error "格式错误"
    done
    
    echo -e "${CYAN}[2/3] Client IPv6:${NC}"
    while true; do
        read -p "输入: " CLIENT_IPV6
        CLIENT_IPV6=$(echo "$CLIENT_IPV6" | tr -d ' ')
        [[ -n "$CLIENT_IPV6" && "$CLIENT_IPV6" == *":"* ]] && break
        log_error "格式错误"
    done
    
    GATEWAY_IPV6=$(echo "$CLIENT_IPV6" | sed 's/::[0-9a-f]*$/::1/')
    [[ "$GATEWAY_IPV6" == "$CLIENT_IPV6" ]] && GATEWAY_IPV6=$(echo "$CLIENT_IPV6" | sed 's/2$/1/')
    
    echo -e "${CYAN}[3/3] Routed /64:${NC}"
    while true; do
        read -p "输入: " ROUTED_INPUT
        ROUTED_INPUT=$(echo "$ROUTED_INPUT" | tr -d ' ')
        [[ -n "$ROUTED_INPUT" && "$ROUTED_INPUT" == *":"* ]] && break
        log_error "格式错误"
    done
    
    if [[ $ROUTED_INPUT == *"/64" ]]; then
        ROUTED_IPV6=$(echo "$ROUTED_INPUT" | sed 's|::/64|::1|')
    elif [[ $ROUTED_INPUT == *"::" && $ROUTED_INPUT != *"::1" ]]; then
        ROUTED_IPV6="${ROUTED_INPUT}1"
    else
        ROUTED_IPV6="$ROUTED_INPUT"
    fi
    
    log_success "配置已设置"
    STEP_2_DONE=true
    save_state
    echo ""
    
    if ! confirm "开始安装？"; then
        log_warning "已取消"
        sleep 1
        return
    fi
    
    echo ""
    
    # 步骤 3
    log_info "【3/5】配置系统参数..."
    tee /etc/sysctl.d/99-disable-ipv6-ra.conf > /dev/null <<EOF
net.ipv6.conf.default.accept_ra=0
net.ipv6.conf.all.accept_ra=0
net.ipv6.conf.${MAIN_IFACE}.accept_ra=0
net.ipv6.conf.${MAIN_IFACE}.autoconf=0
EOF
    sysctl -p /etc/sysctl.d/99-disable-ipv6-ra.conf >/dev/null 2>&1
    
    BACKUP_DIR="/root/network-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    ip -6 addr flush dev ${MAIN_IFACE} scope global 2>/dev/null || true
    ip -6 route flush dev ${MAIN_IFACE} 2>/dev/null || true
    
    log_success "系统参数已配置"
    STEP_3_DONE=true
    save_state
    echo ""
    
    # 步骤 4
    log_info "【4/5】安装 HE 隧道..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y net-tools iproute2 curl iptables-persistent jq >/dev/null 2>&1
    
    # 创建启动脚本
    tee /usr/local/bin/he-ipv6-tunnel.sh > /dev/null <<EOF
#!/bin/bash
ip tunnel del he-ipv6 2>/dev/null || true
ip tunnel add he-ipv6 mode sit remote ${HE_SERVER} local ${LOCAL_IPV4} ttl 255
ip link set he-ipv6 mtu 1480 up
ip -6 addr add ${CLIENT_IPV6}/64 dev he-ipv6
ip -6 addr add ${ROUTED_IPV6}/64 dev he-ipv6
ip -6 route add default via ${GATEWAY_IPV6} dev he-ipv6 metric 1024 2>/dev/null || true
ip -6 route flush cache
EOF
    chmod +x /usr/local/bin/he-ipv6-tunnel.sh
    
    # 创建服务
    tee /etc/systemd/system/he-ipv6-tunnel.service > /dev/null <<EOF
[Unit]
Description=HE IPv6 Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/he-ipv6-tunnel.sh
ExecStop=/sbin/ip tunnel del he-ipv6

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable he-ipv6-tunnel.service >/dev/null 2>&1
    /usr/local/bin/he-ipv6-tunnel.sh
    
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    ip6tables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    netfilter-persistent save >/dev/null 2>&1 || true
    
    log_success "隧道已安装"
    STEP_4_DONE=true
    save_state
    echo ""
    
    # 步骤 5
    log_info "【5/5】验证配置..."
    sleep 2
    
    OUTBOUND_IPV6=$(timeout 10 curl -6 -s https://api64.ipify.org?format=json 2>/dev/null | jq -r '.ip' 2>/dev/null || echo "")
    
    if [[ -n "$OUTBOUND_IPV6" ]]; then
        log_success "出站 IPv6: ${OUTBOUND_IPV6}"
        
        GEO_INFO=$(timeout 10 curl -6 -s https://ipapi.co/json/ 2>/dev/null)
        if [[ -n "$GEO_INFO" ]]; then
            COUNTRY=$(echo "$GEO_INFO" | jq -r '.country_name' 2>/dev/null)
            CITY=$(echo "$GEO_INFO" | jq -r '.city' 2>/dev/null)
            log_success "位置: ${COUNTRY} - ${CITY}"
        fi
        
        STEP_5_DONE=true
        save_state
        
        echo ""
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo -e "${GREEN}✅ 安装成功！${NC}"
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo ""
        echo "  出站 IPv6: ${OUTBOUND_IPV6}"
        echo "  显示位置: ${COUNTRY} - ${CITY}"
        echo "  服务状态: systemctl status he-ipv6-tunnel"
        echo ""
    else
        log_error "验证失败，请检查配置"
    fi
    
    echo ""
    read -p "按回车返回主菜单..."
}

# ========================================
# 主循环
# ========================================
main() {
    # 尝试加载保存的状态
    if load_state; then
        log_info "检测到保存的配置，已自动加载"
        sleep 1
    fi
    
    while true; do
        show_menu
        
        read -p "请选择 [0-5,8,9]: " choice
        
        case $choice in
            1) step_1_get_system_info ;;
            2) step_2_input_tunnel_info ;;
            3) step_3_disable_native_ipv6 ;;
            4) step_4_install_he_tunnel ;;
            5) step_5_verify_config ;;
            8) clear_state; sleep 1 ;;
            9) one_click_install ;;
            0) echo ""; log_info "退出"; save_state; exit 0 ;;
            *) log_error "无效选择"; sleep 1 ;;
        esac
    done
}

# 启动
main
