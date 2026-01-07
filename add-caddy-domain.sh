#!/bin/bash

# Caddy 域名配置管理脚本（增强版 v2.0）
# 作者：soga11
# 功能：反向代理、重定向、静态站点、批量导入、备份恢复、SSL管理等

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_success() { echo -e "${CYAN}[SUCCESS]${NC} $1"; }

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then 
    print_error "请使用 root 用户运行此脚本"
    echo "使用方法：sudo bash $0"
    exit 1
fi

# 检查 Caddy 是否安装
if ! command -v caddy &> /dev/null; then
    print_error "Caddy 未安装！请先安装 Caddy"
    exit 1
fi

CADDYFILE="/etc/caddy/Caddyfile"
BACKUP_DIR="/etc/caddy/backups"

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 获取公网 IP
get_public_ip() {
    echo ""
    print_info "本机公网 IP 地址："
    
    IPV4=$(curl -s -4 --connect-timeout 3 https://api.ipify.org 2>/dev/null || curl -s -4 ifconfig.me 2>/dev/null)
    if [ -n "$IPV4" ]; then
        echo "  IPv4: $IPV4"
    fi
    
    IPV6=$(curl -s -6 --connect-timeout 3 https://api64.ipify.org 2>/dev/null)
    if [ -n "$IPV6" ]; then
        echo "  IPv6: $IPV6"
    fi
    
    if [ -z "$IPV4" ] && [ -z "$IPV6" ]; then
        print_warning "无法获取公网 IP，显示内网 IP："
        ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print "  - " $2}' | cut -d'/' -f1
    fi
    echo ""
}

# 显示主菜单
show_menu() {
    clear
    echo "========================================"
    echo "     Caddy 域名配置管理 v2.0"
    echo "========================================"
    echo ""
    echo "【配置管理】"
    echo "  1. 反向代理 - 域名"
    echo "  2. 反向代理 - IP+端口"
    echo "  3. 站点重定向"
    echo "  4. 静态文件站点"
    echo "  5. 修改现有配置 ⭐"
    echo "  6. 批量导入配置 ⭐"
    echo ""
    echo "【查看管理】"
    echo "  7. 查看当前配置"
    echo "  8. 查看域名列表"
    echo "  9. 删除域名配置"
    echo " 10. 导出配置"
    echo ""
    echo "【备份恢复】"
    echo " 11. 手动备份配置 ⭐"
    echo " 12. 恢复备份 ⭐"
    echo " 13. 查看备份列表 ⭐"
    echo ""
    echo "【证书管理】"
    echo " 14. 查看 SSL 证书状态 ⭐"
    echo " 15. 强制更新证书 ⭐"
    echo ""
    echo "【服务管理】"
    echo " 16. 重启 Caddy"
    echo " 17. 查看日志"
    echo " 18. 查看状态"
    echo " 19. 验证配置 ⭐"
    echo ""
    echo "【系统工具】"
    echo " 20. 查看本机 IP ⭐"
    echo " 21. 测试域名解析 ⭐"
    echo " 22. 性能优化 ⭐"
    echo ""
    echo "  0. 退出"
    echo "========================================"
}

# 备份配置文件
backup_config() {
    local backup_file="$BACKUP_DIR/Caddyfile.$(date +%Y%m%d_%H%M%S).backup"
    cp "$CADDYFILE" "$backup_file"
    print_info "已备份到: $backup_file"
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
        sed -i "/# .*${DOMAIN}/,/^}/d" "$CADDYFILE"
        sed -i "/^${DOMAIN}/,/^}/d" "$CADDYFILE"
    fi
    return 0
}

# 应用配置并重启
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
                print_info "下一步：将域名的 DNS 记录解析到本服务器"
                get_public_ip
                print_info "等待 DNS 生效后访问：https://${DOMAIN}"
            else
                print_error "Caddy 重启失败"
                journalctl -u caddy -n 20 --no-pager
            fi
        fi
    else
        print_error "配置验证失败！"
        caddy validate --config "$CADDYFILE"
        echo ""
        print_info "正在恢复最近的备份..."
        LATEST_BACKUP=$(ls -t ${BACKUP_DIR}/Caddyfile.*.backup 2>/dev/null | head -1)
        if [ -n "$LATEST_BACKUP" ]; then
            cp "$LATEST_BACKUP" "$CADDYFILE"
            print_success "已恢复备份: $LATEST_BACKUP"
        fi
    fi
}

# 1. 反向代理 - 域名
add_reverse_proxy_domain() {
    echo ""
    print_info "配置反向代理 - 后端域名"
    echo ""
    
    read -p "请输入前端域名（如：a.example.com）: " FRONTEND
    [ -z "$FRONTEND" ] && { print_error "域名不能为空"; return; }
    
    read -p "请输入后端地址（如：https://backend.com）: " BACKEND
    [ -z "$BACKEND" ] && { print_error "后端地址不能为空"; return; }
    
    if [[ ! "$BACKEND" =~ ^https?:// ]]; then
        BACKEND="https://${BACKEND}"
        print_info "自动添加协议，后端地址：$BACKEND"
    fi
    
    backup_config
    check_domain_exists "$FRONTEND" || return
    
    cat >> "$CADDYFILE" <<CONF

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
CONF
    
    DOMAIN="$FRONTEND"
    apply_config
}

# 2. 反向代理 - IP+端口
add_reverse_proxy_ip() {
    echo ""
    print_info "配置反向代理 - 后端 IP+端口"
    echo ""
    
    read -p "请输入前端域名（如：app.example.com）: " FRONTEND
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
    
    if [ -z "$PROTO" ] || [ "$PROTO" == "1" ]; then
        BACKEND_URL="http://${BACKEND_IP}:${BACKEND_PORT}"
    else
        BACKEND_URL="https://${BACKEND_IP}:${BACKEND_PORT}"
    fi
    
    backup_config
    check_domain_exists "$FRONTEND" || return
    
    if [[ "$BACKEND_IP" == "127.0.0.1" || "$BACKEND_IP" == "localhost" ]]; then
        HEADER_HOST="{host}"
        COMMENT="本地应用"
    else
        HEADER_HOST="{upstream_hostport}"
        COMMENT="远程服务器"
    fi
    
    cat >> "$CADDYFILE" <<CONF

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
CONF
    
    DOMAIN="$FRONTEND"
    apply_config
}

# 3. 站点重定向
add_redirect() {
    echo ""
    print_info "配置站点重定向"
    echo ""
    
    read -p "请输入源域名（如：old.example.com）: " SOURCE
    [ -z "$SOURCE" ] && { print_error "源域名不能为空"; return; }
    
    read -p "请输入目标地址（如：https://new.example.com）: " TARGET
    [ -z "$TARGET" ] && { print_error "目标地址不能为空"; return; }
    
    if [[ ! "$TARGET" =~ ^https?:// ]]; then
        TARGET="https://${TARGET}"
    fi
    
    echo ""
    echo "选择重定向类型："
    echo "1. 301 永久重定向（默认）"
    echo "2. 302 临时重定向"
    read -p "请选择 [1-2]: " RTYPE
    
    if [ -z "$RTYPE" ] || [ "$RTYPE" == "1" ]; then
        RCODE="permanent"
    else
        RCODE="temporary"
    fi
    
    backup_config
    check_domain_exists "$SOURCE" || return
    
    cat >> "$CADDYFILE" <<CONF

# 站点重定向
# 源: ${SOURCE}
# 目标: ${TARGET}
# 类型: ${RCODE}
# 时间: $(date +"%Y-%m-%d %H:%M:%S")
${SOURCE} {
    redir ${TARGET} ${RCODE}
}
CONF
    
    DOMAIN="$SOURCE"
    apply_config
}

# 4. 静态文件站点
add_static_site() {
    echo ""
    print_info "配置静态文件站点"
    echo ""
    
    read -p "请输入域名（如：static.example.com）: " DOMAIN
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
    </style>
</head>
<body>
    <h1>🎉 网站运行正常</h1>
    <p>这是由 Caddy 提供服务的静态网站</p>
</body>
</html>
HTMLEOF
            print_info "已创建默认首页"
        else
            return
        fi
    fi
    
    chown -R caddy:caddy "$ROOT_DIR" 2>/dev/null || chown -R www-data:www-data "$ROOT_DIR" 2>/dev/null
    
    backup_config
    check_domain_exists "$DOMAIN" || return
    
    cat >> "$CADDYFILE" <<CONF

# 静态文件站点
# 域名: ${DOMAIN}
# 目录: ${ROOT_DIR}
# 时间: $(date +"%Y-%m-%d %H:%M:%S")
${DOMAIN} {
    root * ${ROOT_DIR}
    file_server browse
    encode gzip
}
CONF
    
    apply_config
}

# 5. 修改现有配置
modify_config() {
    echo ""
    print_info "修改现有配置"
    echo ""
    
    local domains=($(grep -E '^\S+\s+{' "$CADDYFILE" | sed 's/ {//'))
    
    if [ ${#domains[@]} -eq 0 ]; then
        print_warning "没有找到已配置的域名"
        return
    fi
    
    echo "当前配置的域名："
    echo "========================================"
    local i=1
    for domain in "${domains[@]}"; do
        echo "$i. $domain"
        ((i++))
    done
    echo "========================================"
    echo ""
    
    read -p "请选择要修改的域名编号 (或直接输入域名): " choice
    
    local target_domain
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#domains[@]}" ]; then
        target_domain="${domains[$((choice-1))]}"
    else
        target_domain="$choice"
    fi
    
    if ! grep -q "^$target_domain {" "$CADDYFILE"; then
        print_error "域名不存在: $target_domain"
        return
    fi
    
    echo ""
    echo "当前配置："
    echo "========================================"
    sed -n "/^$target_domain {/,/^}/p" "$CADDYFILE"
    echo "========================================"
    echo ""
    
    echo "修改选项:"
    echo "  1. 修改后端地址"
    echo "  2. 完全重新配置"
    echo "  3. 返回主菜单"
    echo ""
    read -p "请选择 [1-3]: " mod_choice
    
    case $mod_choice in
        1)
            read -p "输入新的后端地址: " new_backend
            if [ -z "$new_backend" ]; then
                print_error "后端地址不能为空"
                return
            fi
            
            backup_config
            
            sed -i "/^$target_domain {/,/^}/{
                s|reverse_proxy [^{]*|reverse_proxy $new_backend|
            }" "$CADDYFILE"
            
            print_success "后端地址已更新为: $new_backend"
            
            read -p "是否重启 Caddy？(Y/n): " RESTART
            if [ "$RESTART" != "n" ] && [ "$RESTART" != "N" ]; then
                systemctl restart caddy
                print_success "Caddy 已重启"
            fi
            ;;
        2)
            backup_config
            sed -i "/# .*$target_domain/,/^}/d" "$CADDYFILE"
            sed -i "/^$target_domain {/,/^}/d" "$CADDYFILE"
            print_info "旧配置已删除，请重新添加配置"
            ;;
        3)
            return
            ;;
    esac
}

# 6. 批量导入配置
batch_import() {
    echo ""
    print_info "批量导入配置"
    echo ""
    echo "格式: 前端域名,后端地址"
    echo "例如: a.com,https://backend.com"
    echo "      b.com,http://127.0.0.1:8080"
    echo ""
    echo "请输入配置（每行一个，输入 END 结束）:"
    
    backup_config
    
    local count=0
    while IFS= read -r line; do
        if [ "$line" = "END" ]; then
            break
        fi
        
        if [ -z "$line" ]; then
            continue
        fi
        
        IFS=',' read -r frontend backend <<< "$line"
        
        if [ -n "$frontend" ] && [ -n "$backend" ]; then
            cat >> "$CADDYFILE" <<CONF

# 批量导入 - $(date +"%Y-%m-%d %H:%M:%S")
${frontend} {
    reverse_proxy ${backend} {
        header_up Host {upstream_hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
CONF
            ((count++))
            print_success "已添加: $frontend -> $backend"
        fi
    done
    
    echo ""
    print_info "共导入 $count 个配置"
    
    apply_config
}

# 7. 查看当前配置
view_config() {
    echo ""
    print_info "当前配置："
    echo "========================================"
    cat "$CADDYFILE"
    echo "========================================"
}

# 8. 查看域名列表
list_domains() {
    echo ""
    print_info "已配置的域名："
    echo "========================================"
    grep -E '^\S+\s+{' "$CADDYFILE" 2>/dev/null | sed 's/ {//' | nl
    echo "========================================"
}

# 9. 删除域名配置
delete_domain() {
    echo ""
    list_domains
    echo ""
    
    read -p "请输入要删除的域名: " DOMAIN
    [ -z "$DOMAIN" ] && { print_error "域名不能为空"; return; }
    
    backup_config
    sed -i "/# .*${DOMAIN}/,/^}/d" "$CADDYFILE"
    sed -i "/^${DOMAIN}/,/^}/d" "$CADDYFILE"
    
    print_success "配置已删除"
    
    read -p "是否重启 Caddy？(Y/n): " RESTART
    if [ "$RESTART" != "n" ] && [ "$RESTART" != "N" ]; then
        systemctl restart caddy
    fi
}

# 10. 导出配置
export_config() {
    echo ""
    local export_file="/root/caddy_config_$(date +%Y%m%d_%H%M%S).txt"
    cp "$CADDYFILE" "$export_file"
    print_success "配置已导出到: $export_file"
}

# 11. 手动备份配置
manual_backup() {
    echo ""
    read -p "输入备份备注（可选）: " note
    local backup_file="$BACKUP_DIR/Caddyfile.$(date +%Y%m%d_%H%M%S)"
    if [ -n "$note" ]; then
        backup_file="${backup_file}_${note// /_}"
    fi
    backup_file="${backup_file}.backup"
    
    cp "$CADDYFILE" "$backup_file"
    print_success "已备份到: $backup_file"
}

# 12. 恢复备份
restore_backup() {
    echo ""
    print_info "可用的备份："
    echo "========================================"
    ls -lht "$BACKUP_DIR"/*.backup 2>/dev/null | nl | head -20
    echo "========================================"
    echo ""
    
    read -p "输入要恢复的备份编号: " backup_num
    
    if [[ "$backup_num" =~ ^[0-9]+$ ]]; then
        local backup_file=$(ls -t "$BACKUP_DIR"/*.backup 2>/dev/null | sed -n "${backup_num}p")
    else
        print_error "无效的编号"
        return
    fi
    
    if [ ! -f "$backup_file" ]; then
        print_error "备份文件不存在"
        return
    fi
    
    print_warning "当前配置将被替换！"
    read -p "确认恢复？(y/N): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        cp "$CADDYFILE" "$BACKUP_DIR/Caddyfile.before_restore.$(date +%Y%m%d_%H%M%S).backup"
        cp "$backup_file" "$CADDYFILE"
        print_success "已恢复备份"
        
        DOMAIN="restored"
        apply_config
    fi
}

# 13. 查看备份列表
list_backups() {
    echo ""
    print_info "备份列表："
    echo "========================================"
    ls -lht "$BACKUP_DIR"/*.backup 2>/dev/null || print_warning "没有找到备份文件"
    echo "========================================"
}

# 14. 查看 SSL 证书状态
check_ssl_status() {
    echo ""
    print_info "SSL 证书状态："
    echo "========================================"
    
    local cert_dir="/var/lib/caddy/.local/share/caddy/certificates"
    
    if [ -d "$cert_dir" ]; then
        find "$cert_dir" -name "*.crt" -exec sh -c '
            echo "域名: $(basename $(dirname {}))"
            openssl x509 -in {} -noout -dates 2>/dev/null
            echo "---"
        ' \;
    else
        print_warning "未找到证书目录"
    fi
    
    echo "========================================"
}

# 15. 强制更新证书
force_renew_cert() {
    echo ""
    list_domains
    echo ""
    
    read -p "输入要更新证书的域名: " domain
    
    if [ -z "$domain" ]; then
        print_error "域名不能为空"
        return
    fi
    
    print_info "停止 Caddy..."
    systemctl stop caddy
    
    print_info "删除旧证书..."
    rm -rf "/var/lib/caddy/.local/share/caddy/certificates/*${domain}*"
    
    print_info "重启 Caddy..."
    systemctl start caddy
    
    print_success "证书将在访问时自动重新申请"
}

# 16. 重启 Caddy
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

# 17. 查看日志
view_logs() {
    print_info "Caddy 实时日志（Ctrl+C 退出）:"
    journalctl -u caddy -f
}

# 18. 查看状态
view_status() {
    echo ""
    systemctl status caddy --no-pager -l
    echo ""
    get_public_ip
}

# 19. 验证配置
validate_config() {
    echo ""
    print_info "验证配置..."
    if caddy validate --config "$CADDYFILE"; then
        print_success "配置正确"
    else
        print_error "配置有误"
    fi
}

# 20. 查看本机 IP
show_ip() {
    get_public_ip
}

# 21. 测试域名解析
test_dns() {
    echo ""
    read -p "输入要测试的域名: " domain
    
    if [ -z "$domain" ]; then
        print_error "域名不能为空"
        return
    fi
    
    echo ""
    print_info "DNS 解析结果："
    echo "========================================"
    
    if command -v dig &> /dev/null; then
        local ipv4=$(dig +short A "$domain" | tail -1)
        if [ -n "$ipv4" ]; then
            echo "IPv4: $ipv4"
        else
            print_warning "未找到 IPv4 记录"
        fi
        
        local ipv6=$(dig +short AAAA "$domain" | tail -1)
        if [ -n "$ipv6" ]; then
            echo "IPv6: $ipv6"
        fi
    else
        print_warning "dig 命令未安装，使用 nslookup"
        nslookup "$domain"
    fi
    
    echo "========================================"
    echo ""
    
    print_info "测试 HTTPS 连接..."
    if curl -I -s --connect-timeout 5 "https://$domain" > /dev/null 2>&1; then
        print_success "HTTPS 连接正常"
    else
        print_warning "HTTPS 连接失败"
    fi
}

# 22. 性能优化
optimize_performance() {
    echo ""
    print_info "Caddy 性能优化"
    echo ""
    echo "优化项："
    echo "  1. 启用 HTTP/3"
    echo "  2. 优化 TLS 配置"
    echo "  3. 启用压缩"
    echo "  4. 增加并发连接数"
    echo ""
    
    read -p "是否应用优化？(y/N): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        return
    fi
    
    backup_config
    
    if ! grep -q "servers {" "$CADDYFILE"; then
        cat >> "$CADDYFILE" <<'CONF'

# 性能优化配置
{
    servers {
        protocol {
            experimental_http3
        }
    }
}
CONF
        print_success "已添加性能优化配置"
    else
        print_info "优化配置已存在"
    fi
    
    DOMAIN="optimized"
    apply_config
}

# 主循环
while true; do
    show_menu
    read -p "请选择操作 [0-22]: " choice
    
    case $choice in
        1) add_reverse_proxy_domain ;;
        2) add_reverse_proxy_ip ;;
        3) add_redirect ;;
        4) add_static_site ;;
        5) modify_config ;;
        6) batch_import ;;
        7) view_config ;;
        8) list_domains ;;
        9) delete_domain ;;
        10) export_config ;;
        11) manual_backup ;;
        12) restore_backup ;;
        13) list_backups ;;
        14) check_ssl_status ;;
        15) force_renew_cert ;;
        16) restart_caddy ;;
        17) view_logs ;;
        18) view_status ;;
        19) validate_config ;;
        20) show_ip ;;
        21) test_dns ;;
        22) optimize_performance ;;
        0) print_info "退出脚本"; exit 0 ;;
        *) print_error "无效选择" ;;
    esac
    
    echo ""
    read -p "按回车键继续..."
done
