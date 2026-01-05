#!/bin/bash

# Caddy 通用一键安装脚本
# 支持系统：Ubuntu, Debian, CentOS, Rocky Linux, AlmaLinux, Fedora, Arch Linux
# 作者：AI Assistant
# 版本：1.0

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
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "请使用 root 用户运行此脚本"
        echo "使用方法：sudo bash install-caddy.sh"
        exit 1
    fi
}

# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    else
        print_error "无法检测系统类型"
        exit 1
    fi
    
    print_info "检测到系统：$OS $OS_VERSION"
}

# Ubuntu/Debian 安装
install_debian_ubuntu() {
    print_info "使用 APT 包管理器安装 Caddy..."
    
    # 更新系统
    apt update
    
    # 安装依赖
    apt install -y debian-keyring debian-archive-keyring apt-transport-https curl ca-certificates gnupg
    
    # 添加 Caddy GPG 密钥
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    
    # 添加 Caddy 软件源
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    
    # 更新并安装 Caddy
    apt update
    apt install -y caddy
}

# CentOS/RHEL/Rocky/AlmaLinux 安装
install_centos_rhel() {
    print_info "使用 YUM/DNF 包管理器安装 Caddy..."
    
    # 检测包管理器
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    else
        PKG_MANAGER="yum"
    fi
    
    # 安装依赖
    $PKG_MANAGER install -y yum-utils curl ca-certificates
    
    # 添加 Caddy 软件源
    $PKG_MANAGER install -y 'dnf-command(copr)' 2>/dev/null || true
    
    # 使用官方源
    cat > /etc/yum.repos.d/caddy.repo <<'EOF'
[caddy]
name=Caddy
baseurl=https://dl.cloudsmith.io/public/caddy/stable/rpm/el/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl.cloudsmith.io/public/caddy/stable/gpg.key
EOF
    
    # 安装 Caddy
    $PKG_MANAGER install -y caddy
}

# Fedora 安装
install_fedora() {
    print_info "使用 DNF 包管理器安装 Caddy..."
    
    # 安装依赖
    dnf install -y curl ca-certificates
    
    # 添加 Caddy 软件源
    cat > /etc/yum.repos.d/caddy.repo <<'EOF'
[caddy]
name=Caddy
baseurl=https://dl.cloudsmith.io/public/caddy/stable/rpm/fedora/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://dl.cloudsmith.io/public/caddy/stable/gpg.key
EOF
    
    # 安装 Caddy
    dnf install -y caddy
}

# Arch Linux 安装
install_arch() {
    print_info "使用 Pacman 包管理器安装 Caddy..."
    
    # 更新系统
    pacman -Sy
    
    # 安装 Caddy
    pacman -S --noconfirm caddy
}

# 通用二进制安装（备用方案）
install_binary() {
    print_warning "使用通用二进制文件安装 Caddy..."
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            CADDY_ARCH="amd64"
            ;;
        aarch64|arm64)
            CADDY_ARCH="arm64"
            ;;
        armv7l)
            CADDY_ARCH="armv7"
            ;;
        *)
            print_error "不支持的架构：$ARCH"
            exit 1
            ;;
    esac
    
    # 下载最新版本
    print_info "下载 Caddy..."
    curl -o caddy.tar.gz -L "https://caddyserver.com/api/download?os=linux&arch=${CADDY_ARCH}"
    
    # 解压
    tar -xzf caddy.tar.gz
    
    # 安装
    mv caddy /usr/bin/
    chmod +x /usr/bin/caddy
    
    # 创建用户
    useradd --system --home /var/lib/caddy --shell /bin/false caddy 2>/dev/null || true
    
    # 创建目录
    mkdir -p /etc/caddy
    mkdir -p /var/lib/caddy
    chown -R caddy:caddy /var/lib/caddy
    
    # 创建配置文件
    cat > /etc/caddy/Caddyfile <<'EOF'
# Caddy 配置文件
# 使用 add-caddy-domain.sh 添加域名配置
EOF
    
    # 创建 systemd 服务
    cat > /etc/systemd/system/caddy.service <<'EOF'
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载 systemd
    systemctl daemon-reload
    
    # 清理
    rm -f caddy.tar.gz
}

# 配置防火墙
configure_firewall() {
    print_info "配置防火墙..."
    
    # UFW (Ubuntu/Debian)
    if command -v ufw &> /dev/null; then
        ufw allow 80/tcp comment 'Caddy HTTP' 2>/dev/null
        ufw allow 443/tcp comment 'Caddy HTTPS' 2>/dev/null
        ufw allow 443/udp comment 'Caddy HTTP/3' 2>/dev/null
        print_info "已配置 UFW 防火墙规则"
    fi
    
    # Firewalld (CentOS/RHEL/Fedora)
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=http 2>/dev/null
        firewall-cmd --permanent --add-service=https 2>/dev/null
        firewall-cmd --permanent --add-port=443/udp 2>/dev/null
        firewall-cmd --reload 2>/dev/null
        print_info "已配置 Firewalld 防火墙规则"
    fi
}

# 启动 Caddy
start_caddy() {
    print_info "启动 Caddy 服务..."
    
    # 创建空配置（如果不存在）
    if [ ! -f /etc/caddy/Caddyfile ]; then
        cat > /etc/caddy/Caddyfile <<'EOF'
# Caddy 配置文件
# 使用 add-caddy-domain.sh 添加域名配置
EOF
    fi
    
    # 启用并启动服务
    systemctl enable caddy
    systemctl start caddy
    
    # 检查状态
    sleep 2
    if systemctl is-active --quiet caddy; then
        print_info "Caddy 服务已启动"
    else
        print_warning "Caddy 服务启动失败，请检查配置"
    fi
}

# 显示安装结果
show_result() {
    echo ""
    echo "========================================"
    print_info "Caddy 安装完成！"
    echo "========================================"
    echo ""
    caddy version
    echo ""
    print_info "Caddy 状态："
    systemctl status caddy --no-pager -l | head -10
    echo ""
    print_info "配置文件位置：/etc/caddy/Caddyfile"
    print_info "下一步：使用 add-caddy-domain.sh 添加域名配置"
    echo ""
    print_info "常用命令："
    echo "  查看状态：systemctl status caddy"
    echo "  启动服务：systemctl start caddy"
    echo "  停止服务：systemctl stop caddy"
    echo "  重启服务：systemctl restart caddy"
    echo "  查看日志：journalctl -u caddy -f"
    echo ""
}

# 主函数
main() {
    echo "========================================"
    echo "  Caddy 通用一键安装脚本"
    echo "========================================"
    echo ""
    
    # 检查 root 权限
    check_root
    
    # 检测系统
    detect_os
    
    # 检查是否已安装
    if command -v caddy &> /dev/null; then
        print_warning "检测到 Caddy 已安装"
        caddy version
        read -p "是否重新安装？(y/N): " REINSTALL
        if [ "$REINSTALL" != "y" ] && [ "$REINSTALL" != "Y" ]; then
            print_info "已取消安装"
            exit 0
        fi
    fi
    
    # 根据系统类型安装
    case $OS in
        ubuntu|debian)
            install_debian_ubuntu
            ;;
        centos|rhel|rocky|almalinux)
            install_centos_rhel
            ;;
        fedora)
            install_fedora
            ;;
        arch|manjaro)
            install_arch
            ;;
        *)
            print_warning "系统 $OS 未内置支持，尝试使用通用二进制安装"
            install_binary
            ;;
    esac
    
    # 验证安装
    if ! command -v caddy &> /dev/null; then
        print_error "Caddy 安装失败！"
        exit 1
    fi
    
    # 配置防火墙
    configure_firewall
    
    # 启动服务
    start_caddy
    
    # 显示结果
    show_result
}

# 运行主函数
main
