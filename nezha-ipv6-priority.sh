#!/bin/bash

#####################################################################
# 哪吒监控 IPv6 优先显示脚本 - 优化版
# 自动配置 nezha-agent 优先显示 IPv6 国旗
# 使用: bash <(curl -sL https://your-url/ipv6flag.sh)
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
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# Banner
clear
echo -e "${CYAN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     哪吒监控 IPv6 优先显示配置                            ║
║     Nezha Agent IPv6 Priority Configuration              ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_info "此脚本将自动配置 nezha-agent 优先显示 IPv6 国旗"
echo ""

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本需要 root 权限"
   echo "请使用: sudo bash $0"
   exit 1
fi

# 检查 nezha-agent 是否安装
check_nezha_agent() {
    if ! command -v nezha-agent &> /dev/null; then
        log_error "未检测到 nezha-agent"
        log_info "请先安装哪吒监控 Agent"
        exit 1
    fi
    log_success "检测到 nezha-agent"
}

# 检查是否已经配置
check_if_configured() {
    if command -v systemctl > /dev/null 2>&1; then
        if grep -q "\-\-use-ipv6-countrycode" /etc/systemd/system/nezha-agent.service 2>/dev/null; then
            return 0
        fi
    elif command -v rc-service > /dev/null 2>&1; then
        if grep -q "\-\-use-ipv6-countrycode" /etc/init.d/nezha-agent 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# 备份配置
backup_config() {
    local backup_dir="/root/nezha-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    if command -v systemctl > /dev/null 2>&1; then
        cp /etc/systemd/system/nezha-agent.service "$backup_dir/" 2>/dev/null || true
    elif command -v rc-service > /dev/null 2>&1; then
        cp /etc/init.d/nezha-agent "$backup_dir/" 2>/dev/null || true
    fi
    
    log_info "配置已备份到: $backup_dir"
}

# systemd 系统配置
configure_systemd() {
    log_info "配置 systemd 服务..."
    
    # 停止服务
    systemctl stop nezha-agent
    log_success "已停止 nezha-agent"
    
    # 备份
    backup_config
    
    # 修改配置
    if grep -q "\-\-use-ipv6-countrycode" /etc/systemd/system/nezha-agent.service; then
        log_warning "已经配置过 IPv6 优先，跳过修改"
    else
        sed -i '/ExecStart=/ s/$/ --use-ipv6-countrycode/' /etc/systemd/system/nezha-agent.service
        log_success "已添加 IPv6 优先参数"
    fi
    
    # 重载并启动
    systemctl daemon-reload
    systemctl start nezha-agent
    
    # 验证状态
    if systemctl is-active --quiet nezha-agent; then
        log_success "nezha-agent 已启动"
    else
        log_error "nezha-agent 启动失败"
        return 1
    fi
}

# OpenRC 系统配置
configure_openrc() {
    log_info "配置 OpenRC 服务..."
    
    # 停止服务
    rc-service nezha-agent stop
    log_success "已停止 nezha-agent"
    
    # 备份
    backup_config
    
    # 修改配置
    if grep -q "\-\-use-ipv6-countrycode" /etc/init.d/nezha-agent; then
        log_warning "已经配置过 IPv6 优先，跳过修改"
    else
        sed -i 's#command_args="\(.*\)"#command_args="\1 --use-ipv6-countrycode"#' /etc/init.d/nezha-agent
        log_success "已添加 IPv6 优先参数"
    fi
    
    # 启动服务
    rc-update add nezha-agent
    rc-service nezha-agent start
    
    # 验证状态
    if rc-service nezha-agent status | grep -q "started"; then
        log_success "nezha-agent 已启动"
    else
        log_error "nezha-agent 启动失败"
        return 1
    fi
}

# 显示当前 IPv6 信息
show_ipv6_info() {
    log_info "检测当前 IPv6 配置..."
    echo ""
    
    # 检测 IPv6 地址
    local ipv6_addr=$(ip -6 addr show scope global | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=/)' | head -n1)
    
    if [[ -n "$ipv6_addr" ]]; then
        log_success "IPv6 地址: ${ipv6_addr}"
        
        # 获取地理位置
        local geo_info=$(timeout 10 curl -6 -s https://ipapi.co/json/ 2>/dev/null)
        if [[ -n "$geo_info" ]]; then
            local country=$(echo "$geo_info" | grep -oP '(?<="country_name": ")[^"]*' || echo "未知")
            local city=$(echo "$geo_info" | grep -oP '(?<="city": ")[^"]*' || echo "未知")
            local country_code=$(echo "$geo_info" | grep -oP '(?<="country": ")[^"]*' || echo "")
            log_success "地理位置: ${country} (${country_code}) - ${city}"
            echo ""
            log_info "哪吒监控将显示此位置的国旗 🚩"
        fi
    else
        log_warning "未检测到 IPv6 地址"
        log_info "配置 HE 隧道后可获得不同国家的 IPv6 地址"
    fi
}

# 显示配置文件
show_config() {
    echo ""
    log_info "当前 nezha-agent 配置："
    echo ""
    
    if command -v systemctl > /dev/null 2>&1; then
        grep "ExecStart=" /etc/systemd/system/nezha-agent.service | sed 's/^/  /'
    elif command -v rc-service > /dev/null 2>&1; then
        grep "command_args=" /etc/init.d/nezha-agent | sed 's/^/  /'
    fi
    echo ""
}

# 主函数
main() {
    # 检查 nezha-agent
    check_nezha_agent
    echo ""
    
    # 检查是否已配置
    if check_if_configured; then
        log_warning "检测到已经配置过 IPv6 优先"
        read -p "是否重新配置？[y/N]: " reconfigure
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            log_info "跳过配置"
            show_ipv6_info
            show_config
            exit 0
        fi
        echo ""
    fi
    
    # 根据系统类型配置
    if command -v systemctl > /dev/null 2>&1; then
        configure_systemd
    elif command -v rc-service > /dev/null 2>&1; then
        configure_openrc
    else
        log_error "不支持的系统类型"
        log_info "仅支持 systemd 和 OpenRC"
        exit 1
    fi
    
    # 等待服务稳定
    sleep 2
    
    # 显示结果
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ 配置完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    
    show_ipv6_info
    show_config
    
    echo -e "${CYAN}提示：${NC}"
    echo "  1. 等待 2-3 分钟后刷新哪吒监控 Dashboard"
    echo "  2. 服务器国旗将显示为 IPv6 的地理位置"
    echo "  3. 如需恢复，删除 --use-ipv6-countrycode 参数"
    echo ""
    
    # 显示恢复命令
    echo -e "${YELLOW}恢复命令：${NC}"
    if command -v systemctl > /dev/null 2>&1; then
        echo "  sudo sed -i 's/ --use-ipv6-countrycode//g' /etc/systemd/system/nezha-agent.service"
        echo "  sudo systemctl daemon-reload"
        echo "  sudo systemctl restart nezha-agent"
    elif command -v rc-service > /dev/null 2>&1; then
        echo "  sudo sed -i 's/ --use-ipv6-countrycode//g' /etc/init.d/nezha-agent"
        echo "  sudo rc-service nezha-agent restart"
    fi
    echo ""
}

# 运行
main
