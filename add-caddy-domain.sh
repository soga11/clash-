#!/bin/bash

# Caddy 域名配置管理脚本（优化版）
# 支持：反向代理、重定向、静态站点等

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_success() { echo -e "${CYAN}[SUCCESS]${NC} $1"; }

# 检查 root
if [ "$EUID" -ne 0 ]; then 
    print_error "请使用 root 用户运行此脚本"
    echo "使用方法：sudo bash add-caddy-domain.sh"
    exit 1
fi

# 检查 Caddy
if ! command -v caddy &> /dev/null; then
    print_error "Caddy 未安装！请先运行安装脚本"
    exit 1
fi

CADDYFILE="/etc/caddy/Caddyfile"

# 获取公网 IP（IPv4 和 IPv6）
get_public_ip() {
    echo ""
    print_info "本机公网 IP 地址："
    
    # 获取 IPv4
    IPV4=$(curl -s -4 https://api.ipify.org 2>/dev/null || curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null)
    if [ -n "$IPV4" ]; then
        echo "  IPv4: $IPV4"
    fi
    
    # 获取 IPv6
    IPV6=$(curl -s -6 https://api64.ipify.org 2>/dev/null || curl -s -6 ifconfig.me 2>/dev/null || curl -s -6 icanhazip.com 2>/dev/null)
    if [ -n "$IPV6" ]; then
        echo "  IPv6: $IPV6"
    fi
    
    if [ -z "$IPV4" ] && [ -z "$IPV6" ]; then
        print_warning "无法获取公网 IP，显示内网 IP："
        ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print "  - " $2}' | cut -d'/' -f1
    fi
    echo ""
}

# 显示菜单
show_menu() {
    clear
    echo "========================================"
    echo "     Caddy 域名配置管理"
    echo "========================================"
    echo ""
    echo "【配置管理】"
    echo "  1. 反向代理 - 域名"
    echo "  2. 反向代理 - IP+端口"
    echo "  3. 站点重定向"
    echo "  4. 静态文件站点"
    echo ""
    echo "【查看管理】"
    echo "  5. 查看当前配置"
    echo "  6. 查看域名列表"
    echo "  7. 删除域名配置"
    echo ""
    echo "【服务管理】"
    echo "  8. 重启 Caddy"
    echo "  9. 查看日志"
    echo " 10. 查看状态"
    echo ""
    echo "  0. 退出"
    echo "========================================"
}

# 备份配置
backup_config() {
    cp "$CADDYFILE" "${CADDYFILE}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null
    print_info "已备份配置文件"
}

# 检查域名是否存在
check_domain_exists() {
    local DOMAIN=$1
    if grep -q "^${DOMAIN}" "$CADDYFILE" 2>/dev/null; then
        print_warning "域名 ${DOMAIN} 已存在配置！"
        read -p "是否覆盖？(y/N): " OVERWRITE
        if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
            print_info "已取消"
            return 1
        fi
        sed -i "/^${DOMAIN}/,/^}/d" "$CADDYFILE"
        sed -i "/# .*${DOMAIN}/d" "$CADDYFILE"
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
                print_info "下一步：将域名的 DNS A 记录解析到本服务器"
                get_public_ip
                print_info "等待 5-10 分钟 DNS 生效后访问：https://${DOMAIN}"
            else
                print_error "Caddy 重启失败"
            fi
        fi
    else
        print_error "配置验证失败！已恢复备份"
        LATEST_BACKUP=$(ls -t ${CADDYFILE}.bak.* 2>/dev/null | head -1)
        if [ -n "$LATEST_BACKUP" ]; then
            cp "$LATEST_BACKUP" "$CADDYFILE"
        fi
    fi
}

# 1. 反向代理 - 域名
add_reverse_proxy_domain() {
    echo ""
    print_info "配置反向代理 - 后端域名"
    echo ""
    
    read -p "请输入前端域名（如：a.089.pp.ua）: " FRONTEND
    [ -z "$FRONTEND" ] && { print_error "域名不能为空"; return; }
    
    read -p "请输入后端地址（如：https://203.pp.ua）: " BACKEND
    [ -z "$BACKEND" ] && { print_error "后端地址不能为空"; return; }
    
    # 如果后端地址不包含协议，默认添加 https://
    if [[ ! "$BACKEND" =~ ^https?:// ]]; then
        BACKEND="https://${BACKEND}"
        print_info "自动添加协议，后端地址：$BACKEND"
    fi
    
    backup_config
    check_domain_exists "$FRONTEND" || return
    
    cat >> "$CADDYFILE" <<EOF

# 反向代理 - 域名
# 前端: ${FRONTEND}
# 后端: ${BACKEND}
# 时间: $(date +"%Y-%m-%d %H:%M:%S")
${FRONTEND} {
    reverse_proxy ${BACKEND} {
        header_up Host {upstream_hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF
    
    DOMAIN="$FRONTEND"
    apply_config
}

# 2. 反向代理 - IP+端口
add_reverse_proxy_ip() {
    echo ""
    print_info "配置反向代理 - 后端 IP+端口"
    echo ""
    
    read -p "请输入前端域名（如：app.089.pp.ua）: " FRONTEND
    [ -z "$FRONTEND" ] && { print_error "域名不能为空"; return; }
    
    read -p "请输入后端 IP（如：127.0.0.1）: " BACKEND_IP
    [ -z "$BACKEND_IP" ] && { print_error "后端 IP 不能为空"; return; }
    
    read -p "请输入后端端口（如：8080）: " BACKEND_PORT
    [ -z "$BACKEND_PORT" ] && { print_error "后端端口不能为空"; return; }
    
    echo ""
    echo "选择后端协议："
    echo "1. HTTP（默认，推荐）"
    echo "2. HTTPS"
    read -p "请选择 [1-2]（直接回车默认 HTTP）: " PROTO
    
    # 默认使用 HTTP
    if [ -z "$PROTO" ] || [ "$PROTO" == "1" ]; then
        BACKEND_URL="http://${BACKEND_IP}:${BACKEND_PORT}"
        print_info "使用 HTTP 协议"
    else
        BACKEND_URL="https://${BACKEND_IP}:${BACKEND_PORT}"
        print_info "使用 HTTPS 协议"
    fi
    
    backup_config
    check_domain_exists "$FRONTEND" || return
    
    # 判断是本地还是远程
    if [[ "$BACKEND_IP" == "127.0.0.1" || "$BACKEND_IP" == "localhost" ]]; then
        HEADER_HOST="{host}"
        COMMENT="本地应用"
    else
        HEADER_HOST="{upstream_hostport}"
        COMMENT="远程服务器"
    fi
    
    cat >> "$CADDYFILE" <<EOF

# 反向代理 - IP+端口（${COMMENT}）
# 前端: ${FRONTEND}
# 后端: ${BACKEND_URL}
# 时间: $(date +"%Y-%m-%d %H:%M:%S")
${FRONTEND} {
    reverse_proxy ${BACKEND_URL} {
        header_up Host ${HEADER_HOST}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF
    
    DOMAIN="$FRONTEND"
    apply_config
}

# 3. 站点重定向
add_redirect() {
    echo ""
    print_info "配置站点重定向"
    echo ""
    
    read -p "请输入源域名（如：old.089.pp.ua）: " SOURCE
    [ -z "$SOURCE" ] && { print_error "源域名不能为空"; return; }
    
    read -p "请输入目标地址（如：https://new.089.pp.ua）: " TARGET
    [ -z "$TARGET" ] && { print_error "目标地址不能为空"; return; }
    
    # 如果目标地址不包含协议，默认添加 https://
    if [[ ! "$TARGET" =~ ^https?:// ]]; then
        TARGET="https://${TARGET}"
        print_info "自动添加协议，目标地址：$TARGET"
    fi
    
    echo ""
    echo "选择重定向类型："
    echo "1. 301 永久重定向（默认，推荐）"
    echo "2. 302 临时重定向"
    read -p "请选择 [1-2]（直接回车默认 301）: " RTYPE
    
    if [ -z "$RTYPE" ] || [ "$RTYPE" == "1" ]; then
        RCODE="301"
    else
        RCODE="302"
    fi
    
    backup_config
    check_domain_exists "$SOURCE" || return
    
    cat >> "$CADDYFILE" <<EOF

# 站点重定向
# 源: ${SOURCE}
# 目标: ${TARGET}
# 类型: ${RCODE}
# 时间: $(date +"%Y-%m-%d %H:%M:%S")
${SOURCE} {
    redir ${TARGET} ${RCODE}
}
EOF
    
    DOMAIN="$SOURCE"
    apply_config
}

# 4. 静态文件站点
add_static_site() {
    echo ""
    print_info "配置静态文件站点"
    echo ""
    
    read -p "请输入域名（如：static.089.pp.ua）: " DOMAIN
    [ -z "$DOMAIN" ] && { print_error "域名不能为空"; return; }
    
    read -p "请输入网站根目录（如：/var/www/html）: " ROOT_DIR
    [ -z "$ROOT_DIR" ] && { print_error "根目录不能为空"; return; }
    
    if [ ! -d "$ROOT_DIR" ]; then
        read -p "目录不存在，是否创建？(Y/n): " CREATE
        if [ "$CREATE" != "n" ] && [ "$CREATE" != "N" ]; then
            mkdir -p "$ROOT_DIR"
            cat > "$ROOT_DIR/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>网站运行正常</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 50px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        h1 { font-size: 48px; margin-bottom: 20px; }
        p { font-size: 20px; opacity: 0.9; }
        .info { margin-top: 30px; font-size: 14px; }
    </style>
</head>
<body>
    <h1>🎉 网站运行正常</h1>
    <p>这是由 Caddy 提供服务的静态网站</p>
    <p>请上传你的网站文件到服务器</p>
    <div class="info">
        <p>由 Caddy 自动配置 HTTPS</p>
    </div>
</body>
</html>
HTMLEOF
            print_info "已创建目录和默认首页"
        else
            return
        fi
    fi
    
    # 设置权限
    chown -R caddy:caddy "$ROOT_DIR" 2>/dev/null || chown -R www-data:www-data "$ROOT_DIR" 2>/dev/null
    
    backup_config
    check_domain_exists "$DOMAIN" || return
    
    cat >> "$CADDYFILE" <<EOF

# 静态文件站点
# 域名: ${DOMAIN}
# 目录: ${ROOT_DIR}
# 时间: $(date +"%Y-%m-%d %H:%M:%S")
${DOMAIN} {
    root * ${ROOT_DIR}
    file_server browse
    encode gzip
    
    # 自定义错误页面
    handle_errors {
        respond "{err.status_code} {err.status_text}"
    }
}
EOF
    
    apply_config
    
    print_info "静态站点已配置"
    print_info "文件上传路径：${ROOT_DIR}"
}

# 5. 查看配置
view_config() {
    echo ""
    print_info "当前配置："
    echo "========================================"
    cat "$CADDYFILE"
    echo "========================================"
}

# 6. 查看域名列表
list_domains() {
    echo ""
    print_info "已配置的域名："
    echo "========================================"
    grep "^[a-zA-Z0-9]" "$CADDYFILE" 2>/dev/null | grep -v "^#" | sed 's/ {//' | nl
    echo "========================================"
}

# 7. 删除域名
delete_domain() {
    echo ""
    list_domains
    echo ""
    
    read -p "请输入要删除的域名: " DOMAIN
    [ -z "$DOMAIN" ] && { print_error "域名不能为空"; return; }
    
    backup_config
    sed -i "/^${DOMAIN}/,/^}/d" "$CADDYFILE"
    sed -i "/# .*${DOMAIN}/d" "$CADDYFILE"
    
    print_info "配置已删除"
    
    read -p "是否重启 Caddy？(Y/n): " RESTART
    if [ "$RESTART" != "n" ] && [ "$RESTART" != "N" ]; then
        systemctl restart caddy
        print_info "Caddy 已重启"
    fi
}

# 8. 重启 Caddy
restart_caddy() {
    print_info "重启 Caddy..."
    systemctl restart caddy
    if [ $? -eq 0 ]; then
        print_success "Caddy 已重启"
        echo ""
        systemctl status caddy --no-pager -l | head -10
    else
        print_error "Caddy 重启失败"
    fi
}

# 9. 查看日志
view_logs() {
    print_info "Caddy 实时日志（Ctrl+C 退出）："
    echo ""
    journalctl -u caddy -f
}

# 10. 查看状态
view_status() {
    echo ""
    print_info "Caddy 服务状态："
    echo "========================================"
    systemctl status caddy --no-pager -l
    echo "========================================"
    echo ""
    get_public_ip
}

# 主循环
while true; do
    show_menu
    read -p "请选择操作 [0-10]: " choice
    
    case $choice in
        1) add_reverse_proxy_domain ;;
        2) add_reverse_proxy_ip ;;
        3) add_redirect ;;
        4) add_static_site ;;
        5) view_config ;;
        6) list_domains ;;
        7) delete_domain ;;
        8) restart_caddy ;;
        9) view_logs ;;
        10) view_status ;;
        0) print_info "退出脚本"; exit 0 ;;
        *) print_error "无效选择，请重新输入" ;;
    esac
    
    echo ""
    read -p "按回车键继续..."
done
