#!/usr/bin/env bash
# ============================================================
#  万能测速脚本 (universal-speedtest) v1.0
#  自动识别 系统/架构/环境 → 自动选择测速方式
#  三套回退: Ookla 官方二进制 / speedtest-cli / Cloudflare
#  用法: bash <(curl -fsSL <RAW_URL>)     或    bash speedtest.sh
#        可选参数: -m ookla|py|cf   (强制指定方式)
# ============================================================
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info(){ echo -e "${BLUE}[*]${NC} $*"; }
ok(){   echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }
err(){  echo -e "${RED}[-]${NC} $*"; }
hr(){   echo -e "${CYAN}============================================================${NC}"; }

WORKDIR="$(mktemp -d 2>/dev/null || echo /tmp/spd.$$)"; mkdir -p "$WORKDIR" 2>/dev/null
trap 'rm -rf "$WORKDIR" 2>/dev/null' EXIT

# ---------------- 环境探测 ----------------
detect_env(){
  hr; echo -e "${BOLD} 环境探测${NC}"; hr
  OS="unknown"
  [ -f /etc/os-release ] && { . /etc/os-release; OS="${PRETTY_NAME:-${NAME:-unknown}}"; }
  ARCH="$(uname -m 2>/dev/null || echo unknown)"
  echo " 系统     : $OS"
  echo " 内核     : $(uname -r 2>/dev/null)"
  echo " 架构     : $ARCH"
  if [ -f /proc/cpuinfo ]; then
    c="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')"
    [ -n "$c" ] && echo " CPU      : $c"
    echo " 核心     : $(grep -c ^processor /proc/cpuinfo 2>/dev/null)"
  fi
  [ -f /proc/meminfo ] && \
    echo " 内存     : $(awk '/MemTotal/{printf "%.0f MB", $2/1024}' /proc/meminfo)  (swap $(awk '/SwapTotal/{printf "%.0f MB", $2/1024}' /proc/meminfo))"
  echo " 磁盘(/)  : $(df -h / 2>/dev/null | awk 'NR==2{print $2" 总 / "$4" 可用"}')"
  ct=""
  [ -f /.dockerenv ] && ct=docker
  [ -z "$ct" ] && grep -qa container= /proc/1/environ 2>/dev/null && ct="$(grep -ao 'container=[a-z]*' /proc/1/environ 2>/dev/null | head -1 | cut -d= -f2)"
  [ -z "$ct" ] && [ -d /dev/pve ] && ct=lxc/pve
  [ -z "$ct" ] && grep -qa lxc /proc/1/cgroup 2>/dev/null && ct=lxc
  echo " 容器     : ${ct:-否（物理/完整VPS）}"
  pkg=""; for p in apk apt-get dnf yum pacman opkg zypper; do command -v "$p" >/dev/null 2>&1 && pkg="$pkg$p "; done
  echo " 包管理器 : ${pkg:-无}"
  tls=""; for t in curl wget tar python3; do command -v "$t" >/dev/null 2>&1 && tls="$tls$t "; done
  echo " 工具     : ${tls:-无}"
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [ -z "$ip" ] && ip="$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)"
  [ -n "$ip" ] && echo " 本机IP   : $ip"
  [ -f /etc/resolv.conf ] && echo " DNS      : $(awk '/^nameserver/{printf "%s ", $2}' /etc/resolv.conf)"
  hr
}

# ---------------- 下载器 ----------------
DL=""
if command -v curl >/dev/null 2>&1; then DL=curl; elif command -v wget >/dev/null 2>&1; then DL=wget; fi
fetch(){ case "$DL" in
    curl) curl -fSL --connect-timeout 10 --retry 2 -o "$2" "$1" ;;
    wget) wget -q -T 20 -O "$2" "$1" ;;
    *) return 1 ;; esac; }
to_mbps(){ awk -v b="$1" 'BEGIN{printf "%.2f Mbps (%.2f MB/s)", b*8/1e6, b/1e6}'; }

# ---------------- 方法A: Ookla 官方 ----------------
ookla_arch(){ case "$1" in
    x86_64|amd64)     echo x86_64;;
    aarch64|arm64)    echo aarch64;;
    armv7l|armv7|armhf) echo armhf;;
    i386|i686)        echo i386;;
    *) echo "";; esac; }
method_ookla(){
  local a; a="$(ookla_arch "$ARCH")"
  [ -z "$a" ] && { warn "Ookla 不支持此架构: $ARCH"; return 1; }
  local url="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${a}.tgz"
  info "方法A: Ookla 官方二进制 [$a]"
  fetch "$url" "$WORKDIR/ookla.tgz" || { warn "下载失败"; return 1; }
  tar -xzf "$WORKDIR/ookla.tgz" -C "$WORKDIR" 2>/dev/null || { warn "解压失败"; return 1; }
  [ -f "$WORKDIR/speedtest" ] || { warn "未找到二进制"; return 1; }
  chmod +x "$WORKDIR/speedtest"
  echo; info "测速中（约 30 秒）..."; echo
  "$WORKDIR/speedtest" --accept-license --accept-gdpr
}

# ---------------- 方法B: speedtest-cli ----------------
method_py(){
  command -v python3 >/dev/null 2>&1 || { warn "无 python3"; return 1; }
  info "方法B: speedtest-cli (Python)"
  fetch "https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py" "$WORKDIR/st.py" || { warn "下载失败"; return 1; }
  python3 "$WORKDIR/st.py" --secure
}

# ---------------- 方法C: Cloudflare ----------------
method_cf(){
  [ -z "$DL" ] && { warn "无 curl/wget"; return 1; }
  info "方法C: Cloudflare 文件测速"
  local BYTES=100000000 url="https://speed.cloudflare.com/__down?bytes=$BYTES"
  echo " 下载测速中 ($((BYTES/1000000))MB) ..."
  if [ "$DL" = curl ]; then
    spd="$(curl -o /dev/null -s -w '%{speed_download}' "$url")"
  else
    t0="$(date +%s)"; wget -q -O /dev/null "$url" || { warn "下载失败"; return 1; }; t1="$(date +%s)"
    spd="$(awk -v b="$BYTES" -v t0="$t0" -v t1="$t1" 'BEGIN{d=t1-t0; if(d<1)d=1; printf "%.0f", b/d}')"
  fi
  echo " 下载: $(to_mbps "$spd")"
  if [ "$DL" = curl ]; then
    echo " 上传测速中 (50MB) ..."
    dd if=/dev/zero of="$WORKDIR/up.bin" bs=1M count=50 2>/dev/null
    uspd="$(curl -o /dev/null -s -w '%{speed_upload}' -X POST --data-binary @"$WORKDIR/up.bin" "https://speed.cloudflare.com/__up")"
    echo " 上传: $(to_mbps "$uspd")"
  fi
}

# ---------------- 主流程 ----------------
FORCE=""
[ "${1:-}" = "-m" ] && FORCE="${2:-}"

detect_env
echo
[ -z "$DL" ] && { err "既无 curl 也无 wget，无法测速"; exit 1; }
info "下载器: $DL"
echo

case "$FORCE" in
  ookla) method_ookla ;;
  py)    method_py ;;
  cf)    method_cf ;;
  *)
    if   method_ookla; then ok "测速完成（Ookla）"
    elif method_py;     then ok "测速完成（speedtest-cli）"
    elif method_cf;     then ok "测速完成（Cloudflare）"
    else err "所有测速方式均失败"; exit 1; fi ;;
esac
ok "完成 ✅"
