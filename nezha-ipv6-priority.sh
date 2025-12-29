#!/bin/bash

#####################################################################
# 哪吒监控 IPv6 优先显示脚本 - 修复版
# 自动配置 nezha-agent 优先显示 IPv6 国旗
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

# 检查 nezha-agent 是否安装（修复版）
check_nezha_agent() {
    # 方法 1: 检查文件是否存在
    if [[ -f /opt/nezha/agent/nezha-agent ]]; then
        log_success "检测到 nezha-agent (文件)"
        return 0
    fi
    
    # 方法 2: 检查进程
    if pgrep -f nezha-agent > /dev/null 2>&1; then
        log_success "检测到 nezha-agent (进程)"
        return 0
    fi
    
    # 方法 3: 检查服务
    if systemctl list-unit-files | grep -q nezha-agent 2>/dev/null; then
        log_success "检测到 nezha-agent (服务)"
        return 0
    fi
    
    # 方法 4: 检查配置文件
    if [[ -f /etc/systemd/system/nezha-agent.service ]]; then
        log_success "检测到 nezha-agent (配置)"
        return 0
    fi
    
    # 都检测不到
    log_error "未检测到 nezha-agent"
    log_info "请先安装哪吒监控 Agent"
    echo ""
    echo "安装命令："
    echo "  curl -L https://raw.githubusercontent.com/nezhahq/scripts/main/install.sh -o nezha.sh"
    echo "  chmod +x nezha.sh"
    echo "  ./nezha.sh install_agent <域名> <端口> <密钥> --tls"
    exit 1
}

# 检查是否已经配置
check_if_configured() {
    if command -v systemctl > /dev/null 2>&1; then
        if [[ -f /etc/systemd/system/nezha-agent.service ]]; then
            if grep -q "\-\-use-ipv6-countrycode" /etc/systemd/system/nezha-agent.service; then
                return 0
            fi
        fi
    elif command -v rc-service > /dev/null 2>&1; then
        if [[ -f /etc/init.d/nezha-agent ]]; then
            if grep -q "\-\-use-ipv6-countrycode" /etc/init.d/nezha-agent; then
                return 0
            fi
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
        log_info "配置已备份到: $backup_dir"
    elif command -v rc-service > /dev/null 2>&1; then
        cp /etc/init.d/nezha-agent "$backup_dir/" 2>/dev/null || true
        log_info "配置已备份到: $backup_dir"
    fi
}

# systemd 系统配置
configure_systemd() {
    log_info "配置 systemd 服务..."
    
    # 检查配置文件
    if [[ ! -f /etc/systemd/system/nezha-agent.service ]]; then
        log_error "找不到配置文件: /etc/systemd/system/nezha-agent.service"
        exit 1
    fi
    
    # 停止服务
    systemctl stop nezha-agent 2>/dev/null || true
    log_success "已停止 nezha-agent"
    
    # 备份
    backup_config
    
    # 检查是否已配置
    if grep -q "\-\-use-ipv6-countrycode" /etc/systemd/system/nezha-agent.service; then
        log_warning "已经配置过 IPv6 优先"
        echo ""
        read -p "是否重新配置？[y/N]: " reconfigure
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            log_info "跳过配置"
            systemctl start nezha-agent
            return 0
        fi
        echo ""
    fi
    
    # 修改配置
    sed -i '/ExecStart=/ s/$/ --use-ipv6-countrycode/' /etc/systemd/system/nezha-agent.service
    log_success "已添加 IPv6 优先参数"
    
    # 重载并启动
    systemctl daemon-reload
    systemctl start nezha-agent
    
    # 验证状态
    sleep 2
    if systemctl is-active --quiet nezha-agent; then
        log_success "nezha-agent 已启动"
    else
        log_error "nezha-agent 启动失败"
        log_info "查看日志: journalctl -u nezha-agent -n 50"
        return 1
    fi
}

# OpenRC 系统配置
configure_openrc() {
    log_info "配置 OpenRC 服务..."
    
    # 检查配置文件
    if [[ ! -f /etc/init.d/nezha-agent ]]; then
        log_error "找不到配置文件: /etc/init.d/nezha-agent"
        exit 1
    fi
    
    # 停止服务
    rc-service nezha-agent stop 2>/dev/null || true
    log_success "已停止 nezha-agent"
    
    # 备份
    backup_config
    
    # 检查是否已配置
    if grep -q "\-\-use-ipv6-countrycode" /etc/init.d/nezha-agent; then
        log_warning "已经配置过 IPv6 优先"
        echo ""
        read -p "是否重新配置？[y/N]: " reconfigure
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            log_info "跳过配置"
            rc-service nezha-agent start
            return 0
        fi
        echo ""
    fi
    
    # 修改配置
    sed -i 's#command_args="\(.*\)"#command_args="\1 --use-ipv6-countrycode"#' /etc/init.d/nezha-agent
    log_success "已添加 IPv6 优先参数"
    
    # 启动服务
    rc-update add nezha-agent 2>/dev/null || true
    rc-service nezha-agent start
    
    # 验证状态
    sleep 2
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
        log_info "查询地理位置..."
        local geo_info=$(timeout 10 curl -6 -s https://ipapi.co/json/ 2>/dev/null)
        if [[ -n "$geo_info" ]]; then
            local country=$(echo "$geo_info" | grep -oP '(?<="country_name": ")[^"]*' || echo "未知")
            local city=$(echo "$geo_info" | grep -oP '(?<="city": ")[^"]*' || echo "未知")
            local country_code=$(echo "$geo_info" | grep -oP '(?<="country": ")[^"]*' || echo "")
            log_success "地理位置: ${country} (${country_code}) - ${city}"
            echo ""
            echo -e "${GREEN}🚩 哪吒监控将显示: ${country} 国旗${NC}"
        else
            log_warning "无法获取地理位置"
        fi
    else
        log_warning "未检测到全局 IPv6 地址"
        log_info "配置 HE 隧道后可获得不同国家的 IPv6"
    fi
}

# 显示配置文件
show_config() {
    echo ""
    log_info "当前 nezha-agent 启动参数："
    echo ""
    
    if command -v systemctl > /dev/null 2>&1; then
        if [[ -f /etc/systemd/system/nezha-agent.service ]]; then
            grep "ExecStart=" /etc/systemd/system/nezha-agent.service | sed 's/^/  /' | sed 's/ExecStart=//'
        fi
    elif command -v rc-service > /dev/null 2>&1; then
        if [[ -f /etc/init.d/nezha-agent ]]; then
            grep "command_args=" /etc/init.d/nezha-agent | sed 's/^/  /'
        fi
    fi
    echo ""
}

# 主函数
main() {
    # 检查 nezha-agent
    check_nezha_agent
    echo ""
    
    # 检查是否已配置（静默检查）
    if check_if_configured; then
        log_success "检测到已配置 IPv6 优先"
        echo ""
        show_ipv6_info
        show_config
        echo -e "${YELLOW}提示：已经配置过，无需重复操作${NC}"
        echo ""
        exit 0
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
    
    # 显示结果
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}✅ 配置完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    
    show_ipv6_info
    show_config
    
    echo -e "${CYAN}后续步骤：${NC}"
    echo "  1. 等待 2-3 分钟"
    echo "  2. 刷新哪吒监控 Dashboard"
    echo "  3. 服务器国旗将显示为 IPv6 的地理位置"
    echo ""
    
    # 显示恢复命令
    echo -e "${YELLOW}恢复 IPv4 优先：${NC}"
    if command -v systemctl > /dev/null 2>&1; then
        echo "  sudo sed -i 's/ --use-ipv6-countrycode//g' /etc/systemd/system/nezha-agent.service"
        echo "  sudo systemctl daemon-reload && sudo systemctl restart nezha-agent"
    elif command -v rc-service > /dev/null 2>&1; then
        echo "  sudo sed -i 's/ --use-ipv6-countrycode//g' /etc/init.d/nezha-agent"
        echo "  sudo rc-service nezha-agent restart"
    fi
    echo ""
}

# 运行
main
