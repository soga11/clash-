#!/bin/bash

# Caddy 域名配置管理脚本
# 通用版本，支持所有系统

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then 
    print_error "请使用 root 用户运行此脚本"
    echo "使用方法：sudo bash add-caddy-domain.sh"
    exit 1
fi

# 检查 Caddy 是否安装
if ! command -v caddy &> /dev/null; then
    print_error "Caddy 未安装！请先运行 install-caddy.sh"
    exit 1
fi

# 配置文件路径
CADDYFILE="/etc/caddy/Caddyfile"

# 显示菜单
show_menu() {
    echo ""
    echo "========================================"
    echo "     Caddy 域名配置管理"
    echo "========================================"
    echo "1. 添加新域名"
    echo "2. 查看当前配置"
    echo "3. 删除域名配置"
    echo "4. 编辑配置文件"
    echo "5. 重启 Caddy"
    echo "6. 查看 Caddy 日志"
    echo "7. 查看 Caddy 状态"
    echo "8. 测试配置文件"
    echo "0. 退出"
    echo "========================================"
}

# 添加域名
add_domain() {
    echo ""
    print_info "添加新域名配置"
    echo ""
    
    # 读取域名
    read -p "请输入域名（例如：089.pp.ua）: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        print_error "域名不能为空！"
        return
    fi
    
    # 读取后端地址
    read -p "请输入后端地址（例如：https://203.pp.ua）: " BACKEND
    if [ -z "$BACKEND" ]; then
        print_error "后端地址不能为空！"
        return
    fi
    
    # 备份配置
    cp "$CADDYFILE" "${CADDYFILE}.bak.$(date +%Y%m%d_%H%M%S)"
    print_info "已备份配置文件"
    
    # 检查是否已存在
    if grep -q "^${DOMAIN}" "$CADDYFILE" 2>/dev/null; then
        print_warning "域名 ${DOMAIN} 已存在配置！"
        read -p "是否覆盖？(y/N): " OVERWRITE
        if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
            print_info "已取消"
            return
        fi
        # 删除旧配置
        sed -i "/^${DOMAIN}/,/^}/d" "$CADDYFILE"
    fi
    
    # 添加新配置
    cat >> "$CADDYFILE" <<EOF

# 域名: ${DOMAIN}
# 后端: ${BACKEND}
# 添加时间: $(date)
${DOMAIN} {
    reverse_proxy ${BACKEND} {
        header_up Host {upstream_hostport}
    }
}
EOF
    
    print_info "配置已添加"
    
    # 测试配置
    if caddy validate --config "$CADDYFILE" 2>/dev/null; then
        print_info "配置验证通过"
        
        # 询问是否重启
        read -p "是否重启 Caddy 使配置生效？(Y/n): " RESTART
        if [ "$RESTART" != "n" ] && [ "$RESTART" != "N" ]; then
            systemctl restart caddy
            if [ $? -eq 0 ]; then
                print_info "Caddy 已重启"
                echo ""
                print_info "配置已生效！请将域名 ${DOMAIN} 的 DNS 解析到本服务器"
                echo ""
                print_info "本机 IP 地址："
                ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print "  - " $2}'
            else
                print_error "Caddy 重启失败"
            fi
        fi
    else
        print_error "配置验证失败！"
        print_warning "已恢复备份配置"
        mv "${CADDYFILE}.bak.$(date +%Y%m%d_%H%M%S)" "$CADDYFILE"
    fi
}

# 查看配置
view_config() {
    echo ""
    print_info "当前配置："
    echo "========================================"
    cat "$CADDYFILE"
    echo "========================================"
}

# 删除域名
delete_domain() {
    echo ""
    print_info "删除域名配置"
    echo ""
    
    # 列出所有域名
    echo "当前配置的域名："
    grep "^[a-zA-Z0-9]" "$CADDYFILE" | grep -v "^#" | sed 's/ {//'
    echo ""
    
    read -p "请输入要删除的域名: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        print_error "域名不能为空！"
        return
    fi
    
    # 备份
    cp "$CADDYFILE" "${CADDYFILE}.bak.$(date +%Y%m%d_%H%M%S)"
    
    # 删除配置（包括注释）
    sed -i "/# 域名: ${DOMAIN}/,/^}/d" "$CADDYFILE"
    sed -i "/^${DOMAIN}/,/^}/d" "$CADDYFILE"
    
    print_info "配置已删除"
    
    # 重启
    read -p "是否重启 Caddy？(Y/n): " RESTART
    if [ "$RESTART" != "n" ] && [ "$RESTART" != "N" ]; then
        systemctl restart caddy
        print_info "Caddy 已重启"
    fi
}

# 编辑配置
edit_config() {
    # 检测编辑器
    if command -v nano &> /dev/null; then
        EDITOR="nano"
    elif command -v vim &> /dev/null; then
        EDITOR="vim"
    elif command -v vi &> /dev/null; then
        EDITOR="vi"
    else
        print_error "未找到文本编辑器"
        return
    fi
    
    # 备份
    cp "$CADDYFILE" "${CADDYFILE}.bak.$(date +%Y%m%d_%H%M%S)"
    print_info "已备份配置"
    
    # 编辑
    $EDITOR "$CADDYFILE"
    
    # 验证
    if caddy validate --config "$CADDYFILE" 2>/dev/null; then
        print_info "配置验证通过"
        read -p "是否重启 Caddy？(Y/n): " RESTART
        if [ "$RESTART" != "n" ] && [ "$RESTART" != "N" ]; then
            systemctl restart caddy
            print_info "Caddy 已重启"
        fi
    else
        print_error "配置验证失败！"
    fi
}

# 重启 Caddy
restart_caddy() {
    print_info "重启 Caddy..."
    systemctl restart caddy
    if [ $? -eq 0 ]; then
        print_info "Caddy 已重启"
        systemctl status caddy --no-pager -l | head -10
    else
        print_error "Caddy 重启失败"
    fi
}

# 查看日志
view_logs() {
    print_info "Caddy 实时日志（Ctrl+C 退出）："
    echo ""
    journalctl -u caddy -f
}

# 查看状态
view_status() {
    echo ""
    print_info "Caddy 服务状态："
    echo "========================================"
    systemctl status caddy --no-pager -l
    echo "========================================"
}

# 测试配置
test_config() {
    echo ""
    print_info "测试配置文件..."
    if caddy validate --config "$CADDYFILE"; then
        print_info "配置文件验证通过！"
    else
        print_error "配置文件验证失败！"
    fi
}

# 主循环
while true; do
    show_menu
    read -p "请选择操作 [0-8]: " choice
    
    case $choice in
        1)
            add_domain
            ;;
        2)
            view_config
            ;;
        3)
            delete_domain
            ;;
        4)
            edit_config
            ;;
        5)
            restart_caddy
            ;;
        6)
            view_logs
            ;;
        7)
            view_status
            ;;
        8)
            test_config
            ;;
        0)
            print_info "退出脚本"
            exit 0
            ;;
        *)
            print_error "无效选择，请重新输入"
            ;;
    esac
    
    echo ""
    read -p "按回车键继续..."
done
