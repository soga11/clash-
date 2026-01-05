#!/bin/bash

# Caddy 增强版域名配置管理脚本
# 支持：反向代理、重定向、静态站点、负载均衡等

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then 
    print_error "请使用 root 用户运行此脚本"
    echo "使用方法：sudo bash add-caddy-domain.sh"
    exit 1
fi

# 检查 Caddy 是否安装
if ! command -v caddy &> /dev/null; then
    print_error "Caddy 未安装！请先运行安装脚本"
    exit 1
fi

# 配置文件路径
CADDYFILE="/etc/caddy/Caddyfile"

# 显示主菜单
show_main_menu() {
    clear
    echo "========================================"
    echo "       Caddy 域名配置管理"
    echo "========================================"
    echo ""
    echo "【配置管理】"
    echo "  1. 反向代理 - 域名"
    echo "  2. 反向代理 - IP+端口"
    echo "  3. 站点重定向"
    echo "  4. 静态文件站点"
    echo "  5. 负载均衡"
    echo "  6. 自定义配置"
    echo ""
    echo "【查看管理】"
    echo "  7. 查看当前配置"
    echo "  8. 查看已配置域名列表"
    echo "  9. 删除域名配置"
    echo " 10. 编辑配置文件"
    echo ""
    echo "【服务管理】"
    echo " 11. 重启 Caddy"
    echo " 12. 查看 Caddy 日志"
    echo " 13. 查看 Caddy 状态"
    echo " 14. 测试配置文件"
    echo ""
    echo "  0. 退出"
    echo "========================================"
}

# 反向代理 - 域名
add_reverse_proxy_domain() {
    echo ""
    print_info "配置反向代理 - 后端域名"
    echo ""
    
    read -p "请输入前端域名（访问域名，如：a.089.pp.ua）: " FRONTEND
    if [ -z "$FRONTEND" ]; then
        print_error "域名不能为空！"
        return
    fi
    
    read -p "请输入后端域名（如：https://203.pp.ua）: " BACKEND
    if [ -z "$BACKEND" ]; then
        print_error "后端地址不能为空！"
        return
    fi
    
    # 备份配置
    backup_config
    
    # 检查是否已存在
    check_domain_exists "$FRONTEND"
    
    # 添加配置
    cat >> "$CADDYFILE" <<EOF

# 反向代理 - 域名
# 前端: ${FRONTEND}
# 后端: ${BACKEND}
# 时间: $(date)
${FRONTEND} {
    reverse_proxy ${BACKEND} {
        header_up Host {upstream_hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF
    
    apply_config
}

# 反向代理 - IP+端口
add_reverse_proxy_ip() {
    echo ""
    print_info "配置反向代理 - 后端 IP+端口"
    echo ""
    
    read -p "请输入前端域名（如：a.089.pp.ua）: " FRONTEND
    if [ -z "$FRONTEND" ]; then
        print_error "域名不能为空！"
        return
    fi
    
    read -p "请输入后端 IP（如：127.0.0.1）: " BACKEND_IP
    if [ -z "$BACKEND_IP" ]; then
        print_error "后端 IP 不能为空！"
        return
    fi
    
    read -p "请输入后端端口（如：8080）: " BACKEND_PORT
    if [ -z "$BACKEND_PORT" ]; then
        print_error "后端端口不能为空！"
        return
    fi
    
    # 询问协议
    echo ""
    echo "选择后端协议："
    echo "1. HTTP"
    echo "2. HTTPS"
    read -p "请选择 [1-2]: " PROTOCOL_CHOICE
    
    case $PROTOCOL_CHOICE in
        1)
            BACKEND_URL="http://${BACKEND_IP}:${BACKEND_PORT}"
            ;;
        2)
            BACKEND_URL="https://${BACKEND_IP}:${BACKEND_PORT}"
            ;;
        *)
            BACKEND_URL="http://${BACKEND_IP}:${BACKEND_PORT}"
            ;;
    esac
    
    # 备份配置
    backup_config
    
    # 检查是否已存在
    check_domain_exists "$FRONTEND"
    
    # 添加配置
    cat >> "$CADDYFILE" <<EOF

# 反向代理 - IP+端口
# 前端: ${FRONTEND}
# 后端: ${BACKEND_URL}
# 时间: $(date)
${FRONTEND} {
    reverse_proxy ${BACKEND_URL} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF
    
    apply_config
}

# 站点重定向
add_redirect() {
    echo ""
    print_info "配置站点重定向"
    echo ""
    
    read -p "请输入源域名（如：old.089.pp.ua）: " SOURCE
    if [ -z "$SOURCE" ]; then
        print_error "源域名不能为空！"
        return
    fi
    
    read -p "请输入目标地址（如：https://new.089.pp.ua）: " TARGET
    if [ -z "$TARGET" ]; then
        print_error "目标地址不能为空！"
        return
    fi
    
    # 选择重定向类型
    echo ""
    echo "选择重定向类型："
    echo "1. 301 永久重定向（推荐）"
    echo "2. 302 临时重定向"
    echo "3. 307 临时重定向（保留请求方法）"
    echo "4. 308 永久重定向（保留请求方法）"
    read -p "请选择 [1-4]: " REDIRECT_TYPE
    
    case $REDIRECT_TYPE in
        1)
            REDIRECT_CODE="301"
            ;;
        2)
            REDIRECT_CODE="302"
            ;;
        3)
            REDIRECT_CODE="307"
            ;;
        4)
            REDIRECT_CODE="308"
            ;;
        *)
            REDIRECT_CODE="301"
            ;;
    esac
    
    # 备份配置
    backup_config
    
    # 检查是否已存在
    check_domain_exists "$SOURCE"
    
    # 添加配置
    cat >> "$CADDYFILE" <<EOF

# 站点重定向
# 源域名: ${SOURCE}
# 目标: ${TARGET}
# 类型: ${REDIRECT_CODE}
# 时间: $(date)
${SOURCE} {
    redir ${TARGET} ${REDIRECT_CODE}
}
EOF
    
    apply_config
}

# 静态文件站点
add_static_site() {
    echo ""
    print_info "配置静态文件站点"
    echo ""
    
    read -p "请输入域名（如：static.089.pp.ua）: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        print_error "域名不能为空！"
        return
    fi
    
    read -p "请输入网站根目录路径（如：/var/www/html）: " ROOT_DIR
    if [ -z "$ROOT_DIR" ]; then
        print_error "根目录不能为空！"
        return
    fi
    
    # 创建目录（如果不存在）
    if [ ! -d "$ROOT_DIR" ]; then
        read -p "目录不存在，是否创建？(Y/n): " CREATE_DIR
        if [ "$CREATE_DIR" != "n" ] && [ "$CREATE_DIR" != "N" ]; then
            mkdir -p "$ROOT_DIR"
            print_info "已创建目录：$ROOT_DIR"
            
            # 创建默认首页
            cat > "$ROOT_DIR/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>欢迎</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 50px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        h1 { font-size: 48px; margin-bottom: 20px; }
        p { font-size: 20px; }
    </style>
</head>
<body>
    <h1>🎉 网站运行正常</h1>
    <p>这是由 Caddy 提供服务的静态网站</p>
    <p>请上传你的网站文件到服务器</p>
</body>
</html>
EOF
            print_info "已创建默认首页"
        else
            print_error "已取消配置"
            return
        fi
    fi
    
    # 设置权限
    chown -R caddy:caddy "$ROOT_DIR" 2>/dev/null || chown -R www-data:www-data "$ROOT_DIR" 2>/dev/null
    
    # 备份配置
    backup_config
    
    # 检查是否已存在
    check_domain_exists "$DOMAIN"
    
    # 添加配置
    cat >> "$CADDYFILE" <<EOF

# 静态文件站点
# 域名: ${DOMAIN}
# 根目录: ${ROOT_DIR}
# 时间: $(date)
${DOMAIN} {
    root * ${ROOT_DIR}
    file_server browse
    encode gzip
}
EOF
    
    apply_config
    
    print_info "静态站点已配置"
    print_info "上传文件到：${ROOT_DIR}"
}

# 负载均衡
add_load_balance() {
    echo ""
    print_info "配置负载均衡"
    echo ""
    
    read -p "请输入前端域名（如：lb.089.pp.ua）: " FRONTEND
    if [ -z "$FRONTEND" ]; then
        print_error "域名不能为空！"
        return
    fi
    
    echo ""
    print_info "输入后端服务器列表（每行一个，空行结束）"
    echo "格式：http://IP:端口 或 https://域名"
    echo "示例："
    echo "  http://192.168.1.10:8080"
    echo "  http://192.168.1.11:8080"
    echo ""
    
    BACKENDS=()
    while true; do
        read -p "后端 $((${#BACKENDS[@]} + 1))（空行结束）: " BACKEND
        if [ -z "$BACKEND" ]; then
            break
        fi
        BACKENDS+=("$BACKEND")
    done
    
    if [ ${#BACKENDS[@]} -eq 0 ]; then
        print_error "至少需要一个后端服务器！"
        return
    fi
    
    # 选择负载均衡策略
    echo ""
    echo "选择负载均衡策略："
    echo "1. 轮询（Round Robin）"
    echo "2. 随机（Random）"
    echo "3. IP哈希（IP Hash）"
    echo "4. 最少连接（Least Connections）"
    read -p "请选择 [1-4]: " LB_POLICY
    
    case $LB_POLICY in
        1)
            POLICY="round_robin"
            ;;
        2)
            POLICY="random"
            ;;
        3)
            POLICY="ip_hash"
            ;;
        4)
            POLICY="least_conn"
            ;;
        *)
            POLICY="round_robin"
            ;;
    esac
    
    # 备份配置
    backup_config
    
    # 检查是否已存在
    check_domain_exists "$FRONTEND"
    
    # 添加配置
    cat >> "$CADDYFILE" <<EOF

# 负载均衡
# 前端: ${FRONTEND}
# 策略: ${POLICY}
# 时间: $(date)
${FRONTEND} {
    reverse_proxy {
        lb_policy ${POLICY}
EOF
    
    for backend in "${BACKENDS[@]}"; do
        echo "        to ${backend}" >> "$CADDYFILE"
    done
    
    cat >> "$CADDYFILE" <<EOF
        
        health_uri /
        health_interval 10s
        health_timeout 5s
    }
}
EOF
    
    apply_config
}

# 自定义配置
add_custom_config() {
    echo ""
    print_info "添加自定义配置"
    echo ""
    
    read -p "请输入域名（如：custom.089.pp.ua）: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        print_error "域名不能为空！"
        return
    fi
    
    echo ""
    print_info "请输入自定义的 Caddy 配置内容"
    print_warning "输入完成后，单独一行输入 END 结束"
    echo ""
    echo "示例："
    echo "reverse_proxy https://example.com"
    echo "END"
    echo ""
    
    # 备份配置
    backup_config
    
    # 检查是否已存在
    check_domain_exists "$DOMAIN"
    
    # 添加域名头部
    cat >> "$CADDYFILE" <<EOF

# 自定义配置
# 域名: ${DOMAIN}
# 时间: $(date)
${DOMAIN} {
EOF
    
    # 读取自定义内容
    while true; do
        read -p "> " LINE
        if [ "$LINE" == "END" ]; then
            break
        fi
        echo "    ${LINE}" >> "$CADDYFILE"
    done
    
    # 添加结束括号
    echo "}" >> "$CADDYFILE"
    
    apply_config
}

# 备份配置
backup_config() {
    cp "$CADDYFILE" "${CADDYFILE}.bak.$(date +%Y%m%d_%H%M%S)"
    print_info "已备份配置文件"
}

# 检查域名是否已存在
check_domain_exists() {
    local DOMAIN=$1
    if grep -q "^${DOMAIN}" "$CADDYFILE" 2>/dev/null; then
        print_warning "域名 ${DOMAIN} 已存在配置！"
        read -p "是否覆盖？(y/N): " OVERWRITE
        if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
            print_info "已取消"
            return 1
        fi
        # 删除旧配置
        sed -i "/# .*: ${DOMAIN}/,/^}/d" "$CADDYFILE"
        sed -i "/^${DOMAIN}/,/^}/d" "$CADDYFILE"
    fi
    return 0
}

# 应用配置
apply_config() {
    print_info "正在验证配置..."
    
    if caddy validate --config "$CADDYFILE" 2>/dev/null; then
        print_success "配置验证通过！"
        
        read -p "是否重启 Caddy 使配置生效？(Y/n): " RESTART
        if [ "$RESTART" != "n" ] && [ "$RESTART" != "N" ]; then
            systemctl restart caddy
            if [ $? -eq 0 ]; then
                print_success "Caddy 已重启，配置已生效！"
                echo ""
                print_info "请确保 DNS 解析已指向本服务器"
                print_info "本机 IP 地址："
                ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print "  - " $2}' | cut -d'/' -f1
            else
                print_error "Caddy 重启失败，请检查配置"
            fi
        fi
    else
        print_error "配置验证失败！"
        print_warning "已恢复备份配置"
        LATEST_BACKUP=$(ls -t ${CADDYFILE}.bak.* 2>/dev/null | head -1)
        if [ -n "$LATEST_BACKUP" ]; then
            cp "$LATEST_BACKUP" "$CADDYFILE"
        fi
    fi
}

# 查看当前配置
view_config() {
    echo ""
    print_info "当前配置内容："
    echo "========================================"
    cat "$CADDYFILE"
    echo "========================================"
}

# 查看已配置域名列表
list_domains() {
    echo ""
    print_info "已配置的域名："
    echo "========================================"
    grep "^[a-zA-Z0-9]" "$CADDYFILE" | grep -v "^#" | sed 's/ {//' | nl
    echo "========================================"
}

# 删除域名配置
delete_domain() {
    echo ""
    list_domains
    echo ""
    
    read -p "请输入要删除的域名: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        print_error "域名不能为空！"
        return
    fi
    
    # 备份
    backup_config
    
    # 删除配置（包括注释）
    sed -i "/# .*: ${DOMAIN}/,/^}/d" "$CADDYFILE"
    sed -i "/^${DOMAIN}/,/^}/d" "$CADDYFILE"
    
    print_info "配置已删除"
    
    # 重启
    read -p "是否重启 Caddy？(Y/n): " RESTART
    if [ "$RESTART" != "n" ] && [ "$RESTART" != "N" ]; then
        systemctl restart caddy
        print_info "Caddy 已重启"
    fi
}

# 编辑配置文件
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
    backup_config
    
    # 编辑
    $EDITOR "$CADDYFILE"
    
    # 验证
    if caddy validate --config "$CADDYFILE" 2>/dev/null; then
        print_success "配置验证通过"
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
        print_success "Caddy 已重启"
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
        print_success "配置文件验证通过！"
    else
        print_error "配置文件验证失败！"
    fi
}

# 主循环
while true; do
    show_main_menu
    read -p "请选择操作 [0-14]: " choice
    
    case $choice in
        1)
            add_reverse_proxy_domain
            ;;
        2)
            add_reverse_proxy_ip
            ;;
        3)
            add_redirect
            ;;
        4)
            add_static_site
            ;;
        5)
            add_load_balance
            ;;
        6)
            add_custom_config
            ;;
        7)
            view_config
            ;;
        8)
            list_domains
            ;;
        9)
            delete_domain
            ;;
        10)
            edit_config
            ;;
        11)
            restart_caddy
            ;;
        12)
            view_logs
            ;;
        13)
            view_status
            ;;
        14)
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
