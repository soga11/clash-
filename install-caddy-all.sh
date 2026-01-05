#!/bin/bash

# Caddy 完整安装脚本
# 包含：Caddy 安装 + 配置脚本 + 快捷命令

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_success() { echo -e "${BLUE}[SUCCESS]${NC} $1"; }

clear
echo "========================================"
echo "  Caddy 一键安装配置脚本"
echo "========================================"
echo ""

# 检查 root
if [ "$EUID" -ne 0 ]; then 
    print_error "请使用 root 用户运行"
    echo "使用方法：sudo bash $0"
    exit 1
fi

# 检测系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    print_error "无法检测系统类型"
    exit 1
fi

print_info "检测到系统：$OS"
echo ""

# ========================================
# 第一步：安装 Caddy
# ========================================

print_info "步骤 1/3：检查并安装 Caddy"
echo ""

if command -v caddy &> /dev/null; then
    print_success "Caddy 已安装"
    caddy version
else
    print_info "开始安装 Caddy..."
    
    case $OS in
        ubuntu|debian)
            apt update
            apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
            apt update
            apt install -y caddy
            ;;
        centos|rhel|rocky|almalinux)
            yum install -y yum-utils curl
            cat > /etc/yum.repos.d/caddy.repo <<'EOF'
[caddy]
name=Caddy
baseurl=https://dl.cloudsmith.io/public/caddy/stable/rpm/el/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl.cloudsmith.io/public/caddy/stable/gpg.key
EOF
            yum install -y caddy
            ;;
        fedora)
            dnf install -y curl
            cat > /etc/yum.repos.d/caddy.repo <<'EOF'
[caddy]
name=Caddy
baseurl=https://dl.cloudsmith.io/public/caddy/stable/rpm/fedora/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl.cloudsmith.io/public/caddy/stable/gpg.key
EOF
            dnf install -y caddy
            ;;
        arch|manjaro)
            pacman -Sy
            pacman -S --noconfirm caddy
            ;;
    esac
    
    if command -v caddy &> /dev/null; then
        print_success "Caddy 安装成功"
        caddy version
    else
        print_error "Caddy 安装失败"
        exit 1
    fi
fi

# 启动 Caddy
systemctl enable caddy
systemctl start caddy
echo ""

# ========================================
# 第二步：下载配置脚本
# ========================================

print_info "步骤 2/3：下载配置管理脚本"
echo ""

SCRIPT_URL="https://raw.githubusercontent.com/soga11/clash-/refs/heads/main/add-caddy-domain.sh"
SCRIPT_PATH="/usr/local/bin/caddy-manage.sh"

curl -sS -o "$SCRIPT_PATH" "$SCRIPT_URL"
chmod +x "$SCRIPT_PATH"

if [ -f "$SCRIPT_PATH" ]; then
    print_success "配置脚本下载成功"
else
    print_error "配置脚本下载失败"
    exit 1
fi
echo ""

# ========================================
# 第三步：创建快捷命令
# ========================================

print_info "步骤 3/3：创建快捷命令"
echo ""

# 1. ca - 配置管理
cat > /usr/local/bin/ca << 'EOF'
#!/bin/bash
bash /usr/local/bin/caddy-manage.sh "$@"
EOF
chmod +x /usr/local/bin/ca
print_success "✓ ca - 配置管理菜单"

# 2. caadd - 快速添加
cat > /usr/local/bin/caadd << 'EOF'
#!/bin/bash
if [ $# -lt 2 ]; then
    echo "用法：caadd <域名> <后端地址> [类型]"
    echo ""
    echo "示例："
    echo "  caadd api.089.pp.ua https://203.pp.ua"
    echo "  caadd tube.089.pp.ua http://127.0.0.1:18080"
    echo "  caadd old.com https://new.com redirect"
    exit 1
fi
curl -sS https://raw.githubusercontent.com/soga11/clash-/refs/heads/main/quick-add.sh | bash -s "$@"
EOF
chmod +x /usr/local/bin/caadd
print_success "✓ caadd - 快速添加域名"

# 3. caconfig - 查看配置
cat > /usr/local/bin/caconfig << 'EOF'
#!/bin/bash
if [ ! -f /etc/caddy/Caddyfile ]; then
    echo "配置文件不存在"
    exit 1
fi
cat /etc/caddy/Caddyfile
EOF
chmod +x /usr/local/bin/caconfig
print_success "✓ caconfig - 查看配置"

# 4. carestart - 重启服务
cat > /usr/local/bin/carestart << 'EOF'
#!/bin/bash
echo "重启 Caddy..."
systemctl restart caddy
if [ $? -eq 0 ]; then
    echo "✓ Caddy 已重启"
    systemctl status caddy --no-pager -l | head -15
else
    echo "✗ Caddy 重启失败"
    exit 1
fi
EOF
chmod +x /usr/local/bin/carestart
print_success "✓ carestart - 重启服务"

# 5. calog - 查看日志
cat > /usr/local/bin/calog << 'EOF'
#!/bin/bash
journalctl -u caddy -f
EOF
chmod +x /usr/local/bin/calog
print_success "✓ calog - 查看日志"

# 6. castatus - 查看状态
cat > /usr/local/bin/castatus << 'EOF'
#!/bin/bash
systemctl status caddy --no-pager -l
echo ""
echo "公网 IP："
IPV4=$(curl -s -4 https://api.ipify.org 2>/dev/null)
IPV6=$(curl -s -6 https://api64.ipify.org 2>/dev/null)
[ -n "$IPV4" ] && echo "  IPv4: $IPV4"
[ -n "$IPV6" ] && echo "  IPv6: $IPV6"
EOF
chmod +x /usr/local/bin/castatus
print_success "✓ castatus - 查看状态"

# 7. calist - 查看域名列表
cat > /usr/local/bin/calist << 'EOF'
#!/bin/bash
if [ ! -f /etc/caddy/Caddyfile ]; then
    echo "配置文件不存在"
    exit 1
fi
echo "已配置的域名："
echo "========================================"
grep "^[a-zA-Z0-9]" /etc/caddy/Caddyfile 2>/dev/null | grep -v "^#" | sed 's/ {//' | nl
echo "========================================"
EOF
chmod +x /usr/local/bin/calist
print_success "✓ calist - 查看域名列表"

# 8. cadel - 删除域名
cat > /usr/local/bin/cadel << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "用法：cadel <域名>"
    echo ""
    echo "已配置的域名："
    grep "^[a-zA-Z0-9]" /etc/caddy/Caddyfile 2>/dev/null | grep -v "^#" | sed 's/ {//'
    exit 1
fi

DOMAIN=$1
if ! grep -q "^${DOMAIN}" /etc/caddy/Caddyfile 2>/dev/null; then
    echo "域名 ${DOMAIN} 不存在"
    exit 1
fi

# 备份
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.$(date +%Y%m%d_%H%M%S)

# 删除
sed -i "/^${DOMAIN}/,/^}/d" /etc/caddy/Caddyfile
sed -i "/# .*${DOMAIN}/d" /etc/caddy/Caddyfile

echo "✓ 已删除域名：${DOMAIN}"

read -p "是否重启 Caddy？(Y/n): " RESTART
if [ "$RESTART" != "n" ] && [ "$RESTART" != "N" ]; then
    systemctl restart caddy
    echo "✓ Caddy 已重启"
fi
EOF
chmod +x /usr/local/bin/cadel
print_success "✓ cadel - 删除域名"

echo ""

# ========================================
# 完成
# ========================================

echo ""
echo "========================================"
print_success "安装完成！"
echo "========================================"
echo ""
echo "可用命令："
echo ""
echo "  ca         - 打开配置管理菜单"
echo "  caadd      - 快速添加域名"
echo "  caconfig   - 查看当前配置"
echo "  calist     - 查看域名列表"
echo "  cadel      - 删除域名"
echo "  carestart  - 重启 Caddy 服务"
echo "  calog      - 查看实时日志"
echo "  castatus   - 查看服务状态"
echo ""
echo "========================================"
echo "使用示例："
echo "========================================"
echo ""
echo "# 打开配置菜单"
echo "ca"
echo ""
echo "# 快速添加反向代理"
echo "caadd api.089.pp.ua https://203.pp.ua"
echo ""
echo "# 快速添加本地 Docker"
echo "caadd tube.089.pp.ua http://127.0.0.1:18080"
echo ""
echo "# 查看配置"
echo "caconfig"
echo ""
echo "# 查看域名列表"
echo "calist"
echo ""
echo "# 删除域名"
echo "cadel old.089.pp.ua"
echo ""
echo "# 重启服务"
echo "carestart"
echo ""
echo "# 查看状态"
echo "castatus"
echo ""
echo "========================================"
echo ""

# 显示 Caddy 状态
print_info "Caddy 当前状态："
systemctl status caddy --no-pager -l | head -10
echo ""

# 显示公网 IP
print_info "服务器公网 IP："
IPV4=$(curl -s -4 https://api.ipify.org 2>/dev/null)
IPV6=$(curl -s -6 https://api64.ipify.org 2>/dev/null)
[ -n "$IPV4" ] && echo "  IPv4: $IPV4"
[ -n "$IPV6" ] && echo "  IPv6: $IPV6"
echo ""

print_info "开始使用：输入 ca 打开配置菜单"
echo ""
