#!/bin/bash

# ============================================
# Caddy 域名配置管理脚本（增强版 v3.0）
# 作者：soga11
# 功能：反向代理、重定向、静态站点、批量导入、备份恢复、SSL管理、Telegram通知、证书监控
# ============================================

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

# ============================================
# 基础配置
# ============================================

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
TG_CONFIG="/etc/caddy/telegram.conf"
COMPLETE_BACKUP_DIR="/root/caddy_backups"

# 创建必要目录
mkdir -p "$BACKUP_DIR"
mkdir -p "$COMPLETE_BACKUP_DIR"

# ============================================
# Telegram 通知功能
# ============================================

# 发送 Telegram 消息
send_telegram() {
    local message="$1"
    
    # 加载配置
    if [ ! -f "$TG_CONFIG" ]; then
        return 0
    fi
    
    source "$TG_CONFIG"
    
    if [ "$TG_ENABLED" != "true" ]; then
        return 0
    fi
    
    # 发送消息
    local api_url="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"
    
    curl -s -X POST "$api_url" \
        -d chat_id="${TG_CHAT_ID}" \
        -d text="$message" \
        -d parse_mode="HTML" \
        > /dev/null 2>&1
    
    return $?
}

# 配置 Telegram 通知
init_telegram() {
    echo ""
    print_info "配置 Telegram 通知"
    echo ""
    echo "Telegram Bot 创建步骤："
    echo "1. 在 Telegram 中搜索 @BotFather"
    echo "2. 发送 /newbot 创建新机器人"
    echo "3. 获取 Bot Token"
    echo "4. 与你的 Bot 对话，然后访问："
    echo "   https://api.telegram.org/bot<TOKEN>/getUpdates"
    echo "5. 找到 chat 中的 id 字段"
    echo ""
    
    read -p "请输入 Telegram Bot Token: " TG_BOT_TOKEN
    
    if [ -z "$TG_BOT_TOKEN" ]; then
        print_error "Bot Token 不能为空"
        return 1
    fi
    
    echo ""
    read -p "请输入 Chat ID: " TG_CHAT_ID
    
    if [ -z "$TG_CHAT_ID" ]; then
        print_error "Chat ID 不能为空"
        return 1
    fi
    
    # 保存配置
    cat > "$TG_CONFIG" <<EOF
# Telegram 通知配置
# 配置时间: $(date '+%Y-%m-%d %H:%M:%S')
TG_BOT_TOKEN="${TG_BOT_TOKEN}"
TG_CHAT_ID="${TG_CHAT_ID}"
TG_ENABLED="true"
EOF
    
    chmod 600 "$TG_CONFIG"
    
    print_success "配置已保存到: $TG_CONFIG"
    
    # 测试通知
    echo ""
    print_info "发送测试消息..."
    
    local test_msg="✅ <b>Caddy 管理脚本</b>

📡 服务器: $(hostname)
🌐 IP: $(curl -s ifconfig.me 2>/dev/null || echo '未知')
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')

🔔 Telegram 通知已成功配置！"
    
    if send_telegram "$test_msg"; then
        print_success "测试消息发送成功！请查看 Telegram"
    else
        print_error "测试消息发送失败，请检查配置"
    fi
}

# 测试 Telegram 通知
test_telegram() {
    echo ""
    
    if [ ! -f "$TG_CONFIG" ]; then
        print_warning "未配置 Telegram 通知"
        read -p "是否现在配置？(Y/n): " config_now
        if [ "$config_now" != "n" ] && [ "$config_now" != "N" ]; then
            init_telegram
        fi
        return
    fi
    
    print_info "发送测试消息..."
    
    local test_msg="🔔 <b>Caddy 通知测试</b>

📡 服务器: $(hostname)
🌐 IP: $(curl -s ifconfig.me 2>/dev/null || echo '未知')
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')
🔐 Caddy 版本: $(caddy version 2>/dev/null | head -1 || echo '未知')

✅ 通知功能正常运行"
    
    if send_telegram "$test_msg"; then
        print_success "测试消息发送成功！"
    else
        print_error "测试消息发送失败"
        echo ""
        echo "可能的原因："
        echo "  1. Bot Token 或 Chat ID 错误"
        echo "  2. 网络连接问题"
        echo "  3. Bot 被封禁"
        echo ""
        read -p "是否重新配置？(y/N): " reconfig
        if [ "$reconfig" = "y" ] || [ "$reconfig" = "Y" ]; then
            init_telegram
        fi
    fi
}

# ============================================
# 基础工具函数
# ============================================

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
    echo "   Caddy 域名配置管理 v3.0 增强版"
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
    echo " 23. 完整备份（配置+证书）🆕"
    echo " 24. 一键恢复完整备份 🆕"
    echo ""
    echo "【证书管理】"
    echo " 14. 查看 SSL 证书状态 ⭐"
    echo " 15. 强制更新证书 ⭐"
    echo " 25. 检查证书到期状态 🆕"
    echo ""
    echo "【监控告警】🆕"
    echo " 26. 配置 Telegram 通知 🔔"
    echo " 27. 测试 Telegram 通知 🔔"
    echo " 28. 安装证书监控任务 🔔"
    echo " 29. 查看监控日志 🔔"
    echo ""
    echo "【域名管理】🆕"
    echo " 30. 导出域名列表（CSV）📋"
    echo " 31. 域名统计报告 📊"
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
    
    # 显示快速状态
    if [ -f "$TG_CONFIG" ]; then
        source "$TG_CONFIG" 2>/dev/null
        if [ "$TG_ENABLED" = "true" ]; then
            echo "🔔 Telegram: 已启用 ✅"
        fi
    fi
    
    if crontab -l 2>/dev/null | grep -q "caddy-cert-monitor"; then
        echo "📊 证书监控: 已启用 ✅"
    fi
    
    echo ""
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
                if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "optimized" ] && [ "$DOMAIN" != "restored" ]; then
                    print_info "等待 DNS 生效后访问：https://${DOMAIN}"
                fi
                
                # 发送 Telegram 通知
                send_telegram "✅ <b>Caddy 配置已更新</b>

🌐 域名: ${DOMAIN}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')
✅ 状态: 配置已生效"
            else
                print_error "Caddy 重启失败"
                journalctl -u caddy -n 20 --no-pager
                
                # 发送失败通知
                send_telegram "❌ <b>Caddy 重启失败</b>

🌐 域名: ${DOMAIN}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')
❌ 请检查日志"
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
            
            # 发送失败通知
            send_telegram "⚠️ <b>Caddy 配置验证失败</b>

🌐 域名: ${DOMAIN}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')
♻️ 已自动恢复备份"
        fi
    fi
}

# ============================================
# 配置管理功能
# ============================================

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
    }
    encode gzip
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
    }
    encode gzip
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
    
    local domains=($(grep -E '^\S+\s+{' "$CADDYFILE" | grep -v '^{' | sed 's/ {//'))
    
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
            
            # 发送通知
            send_telegram "🔄 <b>配置已修改</b>

🌐 域名: ${target_domain}
📍 新后端: ${new_backend}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')"
            
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
    }
    encode gzip
}
CONF
            ((count++))
            print_success "已添加: $frontend -> $backend"
        fi
    done
    
    echo ""
    print_info "共导入 $count 个配置"
    
    # 发送通知
    send_telegram "📦 <b>批量导入配置</b>

📊 数量: ${count} 个域名
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    DOMAIN="batch_import"
    apply_config
}

# ============================================
# 查看管理功能
# ============================================

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
    grep -E '^\S+\s+{' "$CADDYFILE" 2>/dev/null | grep -v '^{' | sed 's/ {//' | nl
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
    
    # 发送通知
    send_telegram "🗑️ <b>域名配置已删除</b>

🌐 域名: ${DOMAIN}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
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

# ============================================
# 备份恢复功能
# ============================================

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

# 23. 完整备份（配置+证书）
complete_backup() {
    echo ""
    print_info "创建完整备份（配置 + 证书）"
    echo ""
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="caddy_complete_${timestamp}"
    local backup_path="${COMPLETE_BACKUP_DIR}/${backup_name}"
    
    mkdir -p "$backup_path"
    
    # 1. 备份配置文件
    print_info "备份配置文件..."
    cp "$CADDYFILE" "$backup_path/Caddyfile"
    
    # 2. 备份证书
    print_info "备份证书..."
    local cert_count=0
    if [ -d "/var/lib/caddy/.local/share/caddy/certificates" ]; then
        cp -r /var/lib/caddy/.local/share/caddy/certificates "$backup_path/"
        cert_count=$(find "$backup_path/certificates" -name "*.crt" 2>/dev/null | wc -l)
    else
        print_warning "未找到证书目录"
    fi
    
    # 3. 备份账户密钥
    print_info "备份账户密钥..."
    if [ -d "/var/lib/caddy/.local/share/caddy/acme" ]; then
        cp -r /var/lib/caddy/.local/share/caddy/acme "$backup_path/"
    fi
    
    # 4. 备份 Telegram 配置
    if [ -f "$TG_CONFIG" ]; then
        cp "$TG_CONFIG" "$backup_path/"
    fi
    
    # 5. 生成备份信息
    cat > "$backup_path/backup_info.txt" <<EOF
========================================
Caddy 完整备份信息
========================================

备份时间: $(date '+%Y-%m-%d %H:%M:%S')
服务器: $(hostname)
IP 地址: $(curl -s ifconfig.me 2>/dev/null || echo '未知')
Caddy 版本: $(caddy version 2>/dev/null | head -1 || echo "未知")

备份内容:
- 配置文件: Caddyfile
- 证书数量: ${cert_count} 个
- 账户密钥: $([ -d "$backup_path/acme" ] && echo "已备份" || echo "无")
- TG 配置: $([ -f "$backup_path/telegram.conf" ] && echo "已备份" || echo "无")

域名列表:
$(grep -E '^\S+\s+{' "$CADDYFILE" 2>/dev/null | grep -v '^{' | sed 's/ {//' | nl)

========================================
恢复方法:
========================================

1. 传输备份到新服务器:
   scp ${backup_name}.tar.gz root@新服务器:/root/

2. 在新服务器解压:
   tar -xzf ${backup_name}.tar.gz -C /tmp/

3. 恢复配置:
   cp /tmp/${backup_name}/Caddyfile /etc/caddy/

4. 恢复证书:
   cp -r /tmp/${backup_name}/certificates /var/lib/caddy/.local/share/caddy/
   cp -r /tmp/${backup_name}/acme /var/lib/caddy/.local/share/caddy/

5. 设置权限:
   chown -R caddy:caddy /var/lib/caddy
   chmod -R 755 /var/lib/caddy

6. 重启服务:
   systemctl restart caddy

========================================
EOF
    
    # 6. 打包压缩
    print_info "创建压缩包..."
    cd "$COMPLETE_BACKUP_DIR"
    tar -czf "${backup_name}.tar.gz" "$backup_name"
    
    local backup_file="${COMPLETE_BACKUP_DIR}/${backup_name}.tar.gz"
    local backup_size=$(du -h "$backup_file" | cut -f1)
    
    # 清理临时目录
    rm -rf "$backup_path"
    
    # 清理旧备份（保留最近 10 个）
    print_info "清理旧备份..."
    ls -t ${COMPLETE_BACKUP_DIR}/caddy_complete_*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm
    
    print_success "完整备份已创建！"
    echo ""
    echo "备份信息："
    echo "  文件: $backup_file"
    echo "  大小: $backup_size"
    echo "  证书: ${cert_count} 个"
    echo ""
    
    # 发送 Telegram 通知
    local notify_msg="💾 <b>Caddy 完整备份</b>

📁 文件: ${backup_name}.tar.gz
📊 大小: ${backup_size}
🔐 证书: ${cert_count} 个
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    send_telegram "$notify_msg"
    print_info "已发送 Telegram 通知"
}

# 24. 一键恢复完整备份
quick_restore() {
    echo ""
    print_info "可用的完整备份："
    echo "========================================"
    
    if [ ! -d "$COMPLETE_BACKUP_DIR" ] || [ -z "$(ls -A $COMPLETE_BACKUP_DIR/caddy_complete_*.tar.gz 2>/dev/null)" ]; then
        print_warning "未找到完整备份文件"
        echo ""
        echo "提示：请先使用选项 23 创建完整备份"
        return 1
    fi
    
    ls -lht ${COMPLETE_BACKUP_DIR}/caddy_complete_*.tar.gz 2>/dev/null | nl | head -10
    echo "========================================"
    echo ""
    
    read -p "选择要恢复的备份编号: " backup_num
    
    if [[ ! "$backup_num" =~ ^[0-9]+$ ]]; then
        print_error "无效的编号"
        return 1
    fi
    
    local backup_file=$(ls -t ${COMPLETE_BACKUP_DIR}/caddy_complete_*.tar.gz 2>/dev/null | sed -n "${backup_num}p")
    
    if [ ! -f "$backup_file" ]; then
        print_error "备份文件不存在"
        return 1
    fi
    
    print_warning "此操作将覆盖当前配置和证书！"
    read -p "确认恢复？(输入 yes 确认): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "已取消"
        return 0
    fi
    
    # 停止 Caddy
    print_info "停止 Caddy 服务..."
    systemctl stop caddy
    
    # 备份当前配置
    print_info "备份当前配置..."
    cp "$CADDYFILE" "${CADDYFILE}.before_restore.$(date +%s)"
    
    # 解压恢复
    local restore_tmp="/tmp/caddy_restore_$$"
    mkdir -p "$restore_tmp"
    
    print_info "解压备份文件..."
    tar -xzf "$backup_file" -C "$restore_tmp"
    
    local restore_dir="${restore_tmp}/caddy_complete_$(basename $backup_file .tar.gz | sed 's/caddy_complete_//')"
    
    if [ ! -d "$restore_dir" ]; then
        restore_dir="$restore_tmp"
    fi
    
    # 恢复配置
    print_info "恢复配置文件..."
    if [ -f "${restore_dir}/Caddyfile" ]; then
        cp "${restore_dir}/Caddyfile" "$CADDYFILE"
    fi
    
    # 恢复证书
    print_info "恢复证书..."
    if [ -d "${restore_dir}/certificates" ]; then
        rm -rf /var/lib/caddy/.local/share/caddy/certificates
        cp -r "${restore_dir}/certificates" /var/lib/caddy/.local/share/caddy/
    fi
    
    # 恢复账户密钥
    if [ -d "${restore_dir}/acme" ]; then
        rm -rf /var/lib/caddy/.local/share/caddy/acme
        cp -r "${restore_dir}/acme" /var/lib/caddy/.local/share/caddy/
    fi
    
    # 恢复 Telegram 配置
    if [ -f "${restore_dir}/telegram.conf" ]; then
        cp "${restore_dir}/telegram.conf" "$TG_CONFIG"
    fi
    
    # 设置权限
    print_info "设置权限..."
    chown -R caddy:caddy /var/lib/caddy 2>/dev/null || chown -R www-data:www-data /var/lib/caddy 2>/dev/null
    chmod -R 755 /var/lib/caddy
    
    # 清理临时文件
    rm -rf "$restore_tmp"
    
    # 验证配置
    print_info "验证配置..."
    if caddy validate --config "$CADDYFILE" 2>/dev/null; then
        print_success "配置验证通过"
    else
        print_error "配置验证失败"
        caddy validate --config "$CADDYFILE"
    fi
    
    # 启动 Caddy
    print_info "启动 Caddy 服务..."
    systemctl start caddy
    
    sleep 2
    
    if systemctl is-active --quiet caddy; then
        print_success "恢复完成！Caddy 服务已启动"
    else
        print_error "Caddy 服务启动失败"
        journalctl -u caddy -n 20 --no-pager
    fi
    
    # 发送通知
    send_telegram "♻️ <b>Caddy 完整恢复</b>

📁 来源: $(basename $backup_file)
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')
✅ 状态: $(systemctl is-active caddy)"
}

# ============================================
# 证书管理功能
# ============================================

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
    rm -rf "/var/lib/caddy/.local/share/caddy/certificates/${domain}"
    
    print_info "启动 Caddy..."
    systemctl start caddy
    
    print_success "证书将在访问时自动重新申请"
    
    # 发送通知
    send_telegram "🔄 <b>证书更新</b>

🌐 域名: ${domain}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')
✅ 证书将自动重新申请"
}

# 25. 检查证书到期状态
check_cert_expiry() {
    echo ""
    print_info "检查证书到期状态..."
    echo ""
    
    local cert_dir="/var/lib/caddy/.local/share/caddy/certificates"
    local warning_days=7
    local alert_count=0
    local alert_message="⚠️ <b>证书到期警告</b>\n\n"
    
    if [ ! -d "$cert_dir" ]; then
        print_warning "证书目录不存在"
        return 1
    fi
    
    echo "=========================================="
    printf "%-30s %-20s %-10s\n" "域名" "到期时间" "剩余天数"
    echo "=========================================="
    
    while IFS= read -r cert_file; do
        local domain=$(basename $(dirname "$cert_file"))
        local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
        
        if [ -n "$expiry_date" ]; then
            local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
            local current_epoch=$(date +%s)
            
            if [ -n "$expiry_epoch" ]; then
                local days_left=$(( ($expiry_epoch - $current_epoch) / 86400 ))
                
                # 颜色显示
                if [ $days_left -lt $warning_days ]; then
                    printf "${RED}%-30s %-20s %-10s${NC}\n" "$domain" "$(date -d \"$expiry_date\" '+%Y-%m-%d' 2>/dev/null)" "${days_left} 天 ⚠️"
                    alert_message="${alert_message}🔴 ${domain}\n   到期: $(date -d \"$expiry_date\" '+%Y-%m-%d' 2>/dev/null)\n   剩余: ${days_left} 天\n\n"
                    ((alert_count++))
                elif [ $days_left -lt 30 ]; then
                    printf "${YELLOW}%-30s %-20s %-10s${NC}\n" "$domain" "$(date -d \"$expiry_date\" '+%Y-%m-%d' 2>/dev/null)" "${days_left} 天"
                else
                    printf "${GREEN}%-30s %-20s %-10s${NC}\n" "$domain" "$(date -d \"$expiry_date\" '+%Y-%m-%d' 2>/dev/null)" "${days_left} 天"
                fi
            fi
        fi
    done < <(find "$cert_dir" -name "*.crt")
    
    echo "=========================================="
    
    # 发送告警通知
    if [ $alert_count -gt 0 ]; then
        alert_message="${alert_message}📊 总计: ${alert_count} 个证书需要关注\n⏰ 检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
        send_telegram "$alert_message"
        print_warning "发现 ${alert_count} 个证书即将过期，已发送 Telegram 通知"
    else
        print_success "所有证书状态正常"
    fi
}

# ============================================
# 监控告警功能
# ============================================

# 28. 安装证书监控任务
install_cert_monitor() {
    echo ""
    print_info "安装证书监控定时任务"
    echo ""
    
    # 检查是否已配置 Telegram
    if [ ! -f "$TG_CONFIG" ]; then
        print_warning "请先配置 Telegram 通知（选项 26）"
        read -p "是否现在配置？(Y/n): " config_now
        if [ "$config_now" != "n" ] && [ "$config_now" != "N" ]; then
            init_telegram
        else
            return 1
        fi
    fi
    
    local monitor_script="/usr/local/bin/caddy-cert-monitor.sh"
    
    # 创建监控脚本
    cat > "$monitor_script" <<'MONITOR_EOF'
#!/bin/bash

# Caddy 证书监控脚本
# 自动生成 - 请勿手动编辑

TG_CONFIG="/etc/caddy/telegram.conf"
LOG_FILE="/var/log/caddy-cert-monitor.log"

# 加载 Telegram 配置
if [ -f "$TG_CONFIG" ]; then
    source "$TG_CONFIG"
fi

# 发送 Telegram 消息
send_telegram() {
    local message="$1"
    
    if [ "$TG_ENABLED" != "true" ]; then
        return 0
    fi
    
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d text="$message" \
        -d parse_mode="HTML" \
        > /dev/null 2>&1
}

# 记录日志
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 检查证书
log_message "开始证书检查"

cert_dir="/var/lib/caddy/.local/share/caddy/certificates"
warning_days=7
alert_count=0
alert_message="⚠️ <b>证书到期警告</b>\n\n"

if [ -d "$cert_dir" ]; then
    while IFS= read -r cert_file; do
        domain=$(basename $(dirname "$cert_file"))
        expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
        
        if [ -n "$expiry_date" ]; then
            expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
            current_epoch=$(date +%s)
            
            if [ -n "$expiry_epoch" ]; then
                days_left=$(( ($expiry_epoch - $current_epoch) / 86400 ))
                
                if [ $days_left -lt $warning_days ]; then
                    alert_message="${alert_message}🔴 ${domain}\n   到期: $(date -d \"$expiry_date\" '+%Y-%m-%d' 2>/dev/null)\n   剩余: ${days_left} 天\n\n"
                    ((alert_count++))
                    log_message "警告: ${domain} 证书将在 ${days_left} 天后过期"
                fi
            fi
        fi
    done < <(find "$cert_dir" -name "*.crt")
    
    if [ $alert_count -gt 0 ]; then
        alert_message="${alert_message}📊 总计: ${alert_count} 个证书需要关注\n⏰ 检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
        send_telegram "$alert_message"
        log_message "发送告警通知，共 ${alert_count} 个证书"
    else
        log_message "所有证书状态正常"
    fi
else
    log_message "错误: 证书目录不存在"
fi

# 检查 Caddy 服务状态
if ! systemctl is-active --quiet caddy; then
    error_msg="🚨 <b>Caddy 服务异常</b>\n\n❌ Caddy 服务已停止\n⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')\n\n请立即检查！"
    send_telegram "$error_msg"
    log_message "错误: Caddy 服务未运行"
fi

log_message "证书检查完成"
MONITOR_EOF
    
    chmod +x "$monitor_script"
    
    # 添加 cron 任务（每天早上 9 点检查）
    local cron_job="0 9 * * * $monitor_script"
    
    # 检查是否已存在
    if crontab -l 2>/dev/null | grep -q "caddy-cert-monitor"; then
        print_info "定时任务已存在，更新中..."
        (crontab -l 2>/dev/null | grep -v "caddy-cert-monitor"; echo "$cron_job") | crontab -
    else
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    fi
    
    print_success "证书监控已安装"
    echo ""
    echo "监控配置："
    echo "  - 检查时间: 每天 09:00"
    echo "  - 告警阈值: 7 天"
    echo "  - 监控脚本: $monitor_script"
    echo "  - 日志文件: /var/log/caddy-cert-monitor.log"
    echo ""
    
    # 发送通知
    send_telegram "📊 <b>证书监控已启用</b>

⏰ 检查时间: 每天 09:00
⚠️ 告警阈值: 7 天
✅ 配置时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    read -p "是否立即执行一次测试？(Y/n): " test_now
    if [ "$test_now" != "n" ] && [ "$test_now" != "N" ]; then
        print_info "执行测试检查..."
        bash "$monitor_script"
        print_success "测试完成，请查看 Telegram 通知和日志"
    fi
}

# 29. 查看监控日志
view_monitor_log() {
    local log_file="/var/log/caddy-cert-monitor.log"
    
    echo ""
    if [ ! -f "$log_file" ]; then
        print_warning "监控日志不存在"
        echo ""
        echo "可能原因："
        echo "  1. 尚未安装监控任务（选项 28）"
        echo "  2. 监控任务尚未执行"
        return 1
    fi
    
    print_info "证书监控日志（最近 50 条）："
    echo "========================================"
    tail -50 "$log_file"
    echo "========================================"
}

# ============================================
# 域名管理增强
# ============================================

# 30. 导出域名列表（CSV）
export_domains_csv() {
    echo ""
    print_info "导出域名列表"
    
    local export_file="/root/caddy_domains_$(date +%Y%m%d_%H%M%S).csv"
    
    # CSV 表头
    echo "序号,域名,类型,后端地址,添加时间,证书状态,到期时间" > "$export_file"
    
    local index=1
    local cert_dir="/var/lib/caddy/.local/share/caddy/certificates"
    
    # 解析 Caddyfile
    while IFS= read -r domain; do
        # 判断类型
        local type="未知"
        local backend="N/A"
        local add_time="未知"
        
        # 提取配置块
        local config_block=$(sed -n "/^${domain} {/,/^}/p" "$CADDYFILE")
        
        if echo "$config_block" | grep -q "reverse_proxy"; then
            type="反向代理"
            backend=$(echo "$config_block" | grep "reverse_proxy" | awk '{print $2}')
        elif echo "$config_block" | grep -q "redir"; then
            type="重定向"
            backend=$(echo "$config_block" | grep "redir" | awk '{print $2}')
        elif echo "$config_block" | grep -q "file_server"; then
            type="静态站点"
            backend=$(echo "$config_block" | grep "root" | awk '{print $3}')
        fi
        
        # 提取添加时间
        local comment_line=$(grep -B3 "^${domain} {" "$CADDYFILE" | grep "时间:" | tail -1)
        if [ -n "$comment_line" ]; then
            add_time=$(echo "$comment_line" | sed 's/.*时间: //' | sed 's/ *#.*//')
        fi
        
        # 检查证书状态
        local cert_status="无证书"
        local expiry_date="N/A"
        
        if [ -d "${cert_dir}/${domain}" ]; then
            local cert_file=$(find "${cert_dir}/${domain}" -name "*.crt" 2>/dev/null | head -1)
            if [ -f "$cert_file" ]; then
                cert_status="正常"
                expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
                if [ -n "$expiry_date" ]; then
                    expiry_date=$(date -d "$expiry_date" '+%Y-%m-%d' 2>/dev/null)
                    
                    # 检查是否即将过期
                    local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
                    local current_epoch=$(date +%s)
                    if [ -n "$expiry_epoch" ]; then
                        local days_left=$(( ($expiry_epoch - $current_epoch) / 86400 ))
                        
                        if [ $days_left -lt 7 ]; then
                            cert_status="即将过期"
                        fi
                    fi
                fi
            fi
        fi
        
        # 写入 CSV
        echo "${index},${domain},${type},${backend},${add_time},${cert_status},${expiry_date}" >> "$export_file"
        
        ((index++))
    done < <(grep -E '^\S+\s+{' "$CADDYFILE" 2>/dev/null | grep -v '^{' | sed 's/ {//')
    
    print_success "域名列表已导出"
    echo ""
    echo "文件位置: $export_file"
    echo ""
    echo "预览（前 10 行）："
    echo "========================================"
    head -10 "$export_file" | column -t -s ','
    echo "========================================"
    
    # 发送通知
    local domain_count=$((index - 1))
    send_telegram "📋 <b>域名列表导出</b>

📁 文件: $(basename $export_file)
🌐 域名数: ${domain_count}
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')"
}

# 31. 域名统计报告
domain_statistics() {
    echo ""
    print_info "域名统计报告"
    echo ""
    
    local total_domains=$(grep -c -E '^\S+\s+{' "$CADDYFILE" 2>/dev/null | grep -v '^{' || echo 0)
    local proxy_count=$(grep -c "reverse_proxy" "$CADDYFILE" 2>/dev/null || echo 0)
    local redirect_count=$(grep -c "redir" "$CADDYFILE" 2>/dev/null || echo 0)
    local static_count=$(grep -c "file_server" "$CADDYFILE" 2>/dev/null || echo 0)
    
    local cert_dir="/var/lib/caddy/.local/share/caddy/certificates"
    local cert_count=0
    local expiring_count=0
    
    if [ -d "$cert_dir" ]; then
        cert_count=$(find "$cert_dir" -name "*.crt" 2>/dev/null | wc -l)
        
        # 统计即将过期的证书
        while IFS= read -r cert_file; do
            local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
            if [ -n "$expiry_date" ]; then
                local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
                local current_epoch=$(date +%s)
                if [ -n "$expiry_epoch" ]; then
                    local days_left=$(( ($expiry_epoch - $current_epoch) / 86400 ))
                    
                    if [ $days_left -lt 7 ]; then
                        ((expiring_count++))
                    fi
                fi
            fi
        done < <(find "$cert_dir" -name "*.crt" 2>/dev/null)
    fi
    
    echo "=========================================="
    echo "📊 域名统计"
    echo "=========================================="
    echo ""
    echo "  总域名数: $total_domains"
    echo "  反向代理: $proxy_count"
    echo "  重定向: $redirect_count"
    echo "  静态站点: $static_count"
    echo ""
    echo "=========================================="
    echo "🔐 证书统计"
    echo "=========================================="
    echo ""
    echo "  证书总数: $cert_count"
    echo "  即将过期: $expiring_count $([ $expiring_count -gt 0 ] && echo '⚠️' || echo '✅')"
    echo ""
    echo "=========================================="
    echo "⚙️ 服务状态"
    echo "=========================================="
    echo ""
    echo "  Caddy 状态: $(systemctl is-active caddy)"
    echo "  运行时间: $(systemctl show caddy --property=ActiveEnterTimestamp --value 2>/dev/null | xargs -I {} date -d {} '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '未知')"
    echo "  内存使用: $(ps aux | grep '[c]addy' | awk '{sum+=$6} END {print sum/1024 " MB"}' 2>/dev/null || echo '未知')"
    echo ""
    echo "=========================================="
}

# ============================================
# 服务管理功能
# ============================================

# 16. 重启 Caddy
restart_caddy() {
    print_info "重启 Caddy..."
    systemctl restart caddy
    if [ $? -eq 0 ]; then
        print_success "Caddy 已重启"
        systemctl status caddy --no-pager -l | head -10
        
        send_telegram "🔄 <b>Caddy 服务重启</b>

⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')
✅ 状态: 正常运行"
    else
        print_error "Caddy 重启失败"
        
        send_telegram "❌ <b>Caddy 重启失败</b>

⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')
❌ 请检查配置"
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

# ============================================
# 系统工具功能
# ============================================

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
        local ipv4=$(dig +short A "$domain" 2>/dev/null | tail -1)
        if [ -n "$ipv4" ]; then
            echo "IPv4: $ipv4"
        else
            print_warning "未找到 IPv4 记录"
        fi
        
        local ipv6=$(dig +short AAAA "$domain" 2>/dev/null | tail -1)
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

# 22. 性能优化（完全修复版）
optimize_performance() {
    echo ""
    print_info "Caddy 性能优化"
    echo ""
    echo "优化功能："
    echo "  ✓ HTTP/3 (QUIC) - 下一代 HTTP 协议"
    echo "  ✓ 自动 HTTPS - 自动证书管理"
    echo "  ✓ 现代 TLS 配置 - 更安全的加密"
    echo ""
    
    # 检查是否已有全局配置
    if grep -q "^{" "$CADDYFILE"; then
        print_warning "检测到已存在全局配置块"
        echo ""
        
        # 检查是否已经启用了 HTTP/3
        if grep -q "experimental_http3" "$CADDYFILE"; then
            print_info "HTTP/3 已经启用，无需重复配置"
            return 0
        fi
        
        echo "当前 Caddyfile 已包含全局配置。"
        echo ""
        echo "选择操作："
        echo "  1. 在现有全局配置中添加 HTTP/3（推荐）"
        echo "  2. 查看手动配置指南"
        echo "  3. 取消操作"
        echo ""
        read -p "请选择 [1-3]: " opt_choice
        
        case $opt_choice in
            1)
                print_info "正在添加 HTTP/3 配置..."
                backup_config
                
                # 在全局配置的 { 后面插入 servers 配置
                sed -i '/^{$/a\
    # 性能优化 - HTTP/3\
    servers {\
        protocol {\
            experimental_http3\
        }\
    }' "$CADDYFILE"
                
                print_success "已添加 HTTP/3 配置"
                
                # 发送通知
                send_telegram "⚡ <b>性能优化已应用</b>

✅ HTTP/3 已启用
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')"
                
                DOMAIN="optimized"
                apply_config
                ;;
            2)
                echo ""
                echo "📖 手动优化指南："
                echo "=========================================="
                echo "1. 编辑配置文件："
                echo "   nano $CADDYFILE"
                echo ""
                echo "2. 在全局配置块中添加 servers 配置："
                echo ""
                cat <<'EXAMPLE'
{
    servers {
        protocol {
            experimental_http3
        }
    }
}

# 然后是你的域名配置...
EXAMPLE
                echo ""
                echo "3. 保存后执行："
                echo "   caddy validate --config $CADDYFILE"
                echo "   systemctl restart caddy"
                echo "=========================================="
                ;;
            3)
                print_info "已取消"
                ;;
        esac
        return
    fi
    
    # 如果没有全局配置，则创建新的
    read -p "是否应用优化？(y/N): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        print_info "已取消"
        return
    fi
    
    backup_config
    
    print_info "正在应用性能优化..."
    
    # 创建临时文件
    local temp_file="/tmp/caddyfile_opt_$$"
    
    # 写入优化的全局配置
    cat > "$temp_file" <<'CONF'
# ============================================
# Caddy 全局配置 - 性能优化
# ============================================
{
    # HTTP/3 支持（实验性）
    servers {
        protocol {
            experimental_http3
        }
    }
}

# ============================================
# 域名配置
# ============================================

CONF
    
    # 追加原有配置
    cat "$CADDYFILE" >> "$temp_file"
    
    # 替换原文件
    mv "$temp_file" "$CADDYFILE"
    
    print_success "性能优化配置已添加"
    echo ""
    echo "优化内容："
    echo "  ✅ HTTP/3 (QUIC) - 已启用"
    echo "  ✅ 自动 HTTPS - 默认启用"
    echo "  ✅ 自动证书续期 - 默认启用"
    echo ""
    
    # 发送通知
    send_telegram "⚡ <b>性能优化已应用</b>

✅ HTTP/3 已启用
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    DOMAIN="optimized"
    apply_config
}

# ============================================
# 主循环
# ============================================

# 主循环
while true; do
    show_menu
    read -p "请选择操作 [0-31]: " choice
    
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
        23) complete_backup ;;
        24) quick_restore ;;
        25) check_cert_expiry ;;
        26) init_telegram ;;
        27) test_telegram ;;
        28) install_cert_monitor ;;
        29) view_monitor_log ;;
        30) export_domains_csv ;;
        31) domain_statistics ;;
        0) 
            print_info "退出脚本"
            # 发送退出通知
            send_telegram "👋 <b>Caddy 管理脚本</b>

管理会话已结束
⏰ 时间: $(date '+%Y-%m-%d %H:%M:%S')"
            exit 0 
            ;;
        *) print_error "无效选择" ;;
    esac
    
    echo ""
    read -p "按回车键继续..."
done
