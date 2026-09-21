#!/usr/bin/env bash
# VPS 三网测速 v3.0
# 依赖: bash, curl/wget, tar。优先使用已安装的 Ookla Speedtest CLI。

set -uo pipefail

VERSION="3.0.0"
OOKLA_VERSION="1.2.0"
REGION=""
THREE=0
FAMILY="both"
SERVER_ID=""
LIST_ONLY=0
COLOR=1
SPEEDTEST=""
WORKDIR=""
IPV4=""
IPV6=""

if [[ ! -t 1 || "${NO_COLOR:-}" != "" ]]; then COLOR=0; fi
if (( COLOR )); then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; BOLD=""; NC=""
fi

info() { printf '%b[*]%b %s\n' "$BLUE" "$NC" "$*"; }
ok()   { printf '%b[+]%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b[!]%b %s\n' "$YELLOW" "$NC" "$*" >&2; }
err()  { printf '%b[-]%b %s\n' "$RED" "$NC" "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
  cat <<'EOF'
用法: speedtest.sh [选项]

  -r, --region <地区>   从 Ookla 返回的候选节点中匹配城市/省份
  -3, --three           分别测试电信、联通、移动（需要与 -r 同用）
  -4, --ipv4            只测 IPv4
  -6, --ipv6            只测 IPv6
  -s, --server <ID>     指定 Ookla 服务器 ID（最稳定的指定方式）
  -l, --list            列出 Ookla 候选服务器后退出
      --no-color        关闭颜色
  -h, --help            显示帮助
  -V, --version         显示版本

示例:
  bash speedtest.sh
  bash speedtest.sh -r 广东 -3 -4
  bash speedtest.sh -s 12345 -6

说明: Ookla CLI 只返回附近的候选服务器；远程地区可能搜不到，此时请用 -s ID。
EOF
}

need_arg() { [[ $# -ge 2 && -n "$2" ]] || die "选项 $1 需要参数"; }
while (($#)); do
  case "$1" in
    -r|--region) need_arg "$@"; REGION=$2; shift 2 ;;
    -s|--server) need_arg "$@"; [[ $2 =~ ^[0-9]+$ ]] || die "服务器 ID 必须是数字"; SERVER_ID=$2; shift 2 ;;
    -3|--three) THREE=1; shift ;;
    -4|--ipv4) FAMILY="4"; shift ;;
    -6|--ipv6) FAMILY="6"; shift ;;
    -l|--list) LIST_ONLY=1; shift ;;
    --no-color) COLOR=0; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; BOLD=""; NC=""; shift ;;
    -h|--help) usage; exit 0 ;;
    -V|--version) echo "$VERSION"; exit 0 ;;
    --) shift; break ;;
    -*) die "未知选项: $1（用 -h 查看帮助）" ;;
    *) [[ -z $REGION ]] || die "多余参数: $1"; REGION=$1; shift ;;
  esac
done
[[ $# -eq 0 ]] || die "多余参数: $*"
(( THREE == 0 )) || [[ -n $REGION ]] || die "-3/--three 需要同时指定 -r/--region"
(( THREE == 0 )) || [[ -z $SERVER_ID ]] || die "-3 与 -s 不能同时使用"

cleanup() { [[ -z $WORKDIR ]] || rm -rf -- "$WORKDIR"; }
WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/speedtest-cn.XXXXXXXX") || die "无法创建临时目录"
trap cleanup EXIT HUP INT TERM

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error --connect-timeout 10 --max-time 120 --retry 2 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=20 --tries=3 -O "$2" "$1"
  else
    return 127
  fi
}

ookla_arch() {
  case $(uname -m 2>/dev/null) in
    x86_64|amd64) echo x86_64 ;; aarch64|arm64) echo aarch64 ;;
    armv7l|armv7|armhf) echo armhf ;; i386|i486|i586|i686) echo i386 ;;
    *) return 1 ;;
  esac
}

is_ookla() { "$1" --version 2>&1 | grep -qi 'Speedtest by Ookla'; }
ensure_speedtest() {
  local candidate arch archive url
  candidate=$(command -v speedtest 2>/dev/null || true)
  if [[ -n $candidate ]] && is_ookla "$candidate"; then SPEEDTEST=$candidate; return; fi
  [[ -z $candidate ]] || warn "已安装的 speedtest 不是 Ookla 版，将使用临时官方版"
  arch=$(ookla_arch) || die "Ookla 不支持当前架构: $(uname -m)"
  command -v tar >/dev/null 2>&1 || die "缺少 tar"
  archive="$WORKDIR/ookla.tgz"
  url="https://install.speedtest.net/app/cli/ookla-speedtest-${OOKLA_VERSION}-linux-${arch}.tgz"
  info "下载 Ookla Speedtest CLI ${OOKLA_VERSION} (${arch})"
  fetch "$url" "$archive" || die "下载 Ookla Speedtest CLI 失败"
  tar -xzf "$archive" -C "$WORKDIR" || die "解压 Ookla Speedtest CLI 失败"
  SPEEDTEST="$WORKDIR/speedtest"
  [[ -f $SPEEDTEST ]] || die "压缩包中没有 speedtest 可执行文件"
  chmod 700 "$SPEEDTEST" || die "无法设置执行权限"
}

route_ip() {
  local family=$1 target out
  if [[ $family == 4 ]]; then target=1.1.1.1; else target=2606:4700:4700::1111; fi
  out=$(ip "-$family" route get "$target" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
  if [[ -z $out ]]; then
    out=$(ip "-$family" -o addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}')
  fi
  printf '%s' "$out"
}

region_regex() {
  case ${1,,} in
    广西|guangxi|gx) echo 'Guangxi|Nanning|Guilin|Liuzhou|Beihai|Wuzhou|Yulin|Qinzhou|Baise|Hezhou|Hechi|Laibin|Chongzuo|Guigang|Fangchenggang|广西|南宁|桂林|柳州' ;;
    广东|guangdong|gd) echo 'Guangdong|Guangzhou|Shenzhen|Dongguan|Foshan|Zhuhai|Zhongshan|Huizhou|Shantou|Jiangmen|Zhanjiang|广东|广州|深圳|东莞|佛山' ;;
    北京|beijing) echo 'Beijing|北京' ;; 上海|shanghai) echo 'Shanghai|上海' ;;
    *) printf '%s' "$1" ;;
  esac
}

isp_regex() {
  case $1 in
    电信) echo 'Telecom|ChinaNet|CTCC|电信' ;;
    联通) echo 'Unicom|CUCC|联通' ;;
    移动) echo 'Mobile|CMCC|移动' ;;
  esac
}

list_servers() {
  local bind=$1
  "$SPEEDTEST" -I "$bind" -L --accept-license --accept-gdpr 2>/dev/null
}

find_server() {
  local list=$1 region_rx=$2 isp_rx=$3
  awk -v r="$region_rx" -v p="$isp_rx" 'BEGIN{IGNORECASE=1} /^[[:space:]]*[0-9]+[[:space:]]/ && $0~r && $0~p {print $1; exit}' <<<"$list"
}

json_number() {
  local json=$1 path=$2
  if command -v jq >/dev/null 2>&1; then jq -r ".$path // empty" <<<"$json"; return; fi
  if command -v python3 >/dev/null 2>&1; then
    JSON_INPUT=$json python3 -c 'import json,os,sys; v=json.loads(os.environ["JSON_INPUT"]); [v:=v.get(k,{}) for k in sys.argv[1].split(".")]; print(v if isinstance(v,(int,float,str)) else "")' "$path" 2>/dev/null
    return
  fi
  case $path in
    download.bandwidth) sed -nE 's/.*"download":\{[^}]*"bandwidth":([0-9.]+).*/\1/p' <<<"$json" ;;
    upload.bandwidth) sed -nE 's/.*"upload":\{[^}]*"bandwidth":([0-9.]+).*/\1/p' <<<"$json" ;;
    ping.latency) sed -nE 's/.*"ping":\{[^}]*"latency":([0-9.]+).*/\1/p' <<<"$json" ;;
  esac
}

run_test() {
  local bind=$1 label=$2 sid=${3:-} output rc down up ping
  local args=(-I "$bind" --accept-license --accept-gdpr --format=json --progress=no)
  [[ -z $sid ]] || args+=(-s "$sid")
  info "$label 测速中…"
  output=$("$SPEEDTEST" "${args[@]}" 2>&1); rc=$?
  if (( rc != 0 )); then warn "$label 失败: ${output//$'\n'/ }"; return 1; fi
  down=$(json_number "$output" download.bandwidth)
  up=$(json_number "$output" upload.bandwidth)
  ping=$(json_number "$output" ping.latency)
  if [[ $down =~ ^[0-9]+([.][0-9]+)?$ && $up =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    awk -v l="$label" -v d="$down" -v u="$up" -v p="${ping:-0}" 'BEGIN {printf "  %-12s 延迟 %7.2f ms   ↓ %9.2f Mbps   ↑ %9.2f Mbps\n",l,p,d*8/1000000,u*8/1000000}'
  else
    warn "$label 已完成，但无法解析 JSON 结果"
    printf '%s\n' "$output"
  fi
}

run_family() {
  local fam=$1 bind=$2 servers="" sid="" label region_rx isp_rx failures=0
  printf '\n%b===== IPv%s 测速 =====%b\n' "$BOLD" "$fam" "$NC"
  [[ -n $bind ]] || { warn "IPv${fam} 无可用的全局地址/路由，跳过"; return 2; }
  if (( LIST_ONLY )); then list_servers "$bind" || return 1; return 0; fi
  if [[ -n $SERVER_ID ]]; then run_test "$bind" "服务器 $SERVER_ID" "$SERVER_ID"; return; fi
  if [[ -z $REGION ]]; then run_test "$bind" "自动最佳节点"; return; fi
  servers=$(list_servers "$bind") || { warn "IPv${fam} 无法获取候选服务器"; return 1; }
  region_rx=$(region_regex "$REGION")
  if (( THREE )); then
    for label in 电信 联通 移动; do
      isp_rx=$(isp_regex "$label")
      sid=$(find_server "$servers" "$region_rx" "$isp_rx")
      if [[ -z $sid ]]; then warn "IPv${fam}: 未在候选列表中找到${REGION}${label}节点"; failures=$((failures+1)); continue; fi
      run_test "$bind" "${REGION}${label}" "$sid" || failures=$((failures+1))
    done
  else
    sid=$(find_server "$servers" "$region_rx" '.*')
    [[ -n $sid ]] || { warn "IPv${fam}: 未在候选列表中找到 $REGION 节点；可用 -l 查看或 -s 指定 ID"; return 1; }
    run_test "$bind" "$REGION" "$sid"
  fi
  (( failures == 0 ))
}

ensure_speedtest
command -v ip >/dev/null 2>&1 || die "缺少 iproute2 的 ip 命令"
IPV4=$(route_ip 4)
IPV6=$(route_ip 6)

printf '%b========================================%b\n' "$CYAN" "$NC"
printf ' IPv4 : %s\n IPv6 : %s\n 地区 : %s\n' "${IPV4:-不可用}" "${IPV6:-不可用}" "${REGION:-自动（最佳节点）}"
printf '%b========================================%b\n' "$CYAN" "$NC"

status=0
case $FAMILY in
  4) run_family 4 "$IPV4" || status=1 ;;
  6) run_family 6 "$IPV6" || status=1 ;;
  both)
    run_family 4 "$IPV4" || status=1
    if [[ -n $IPV6 ]]; then run_family 6 "$IPV6" || status=1; else warn "IPv6 不可用，已跳过"; fi
    ;;
esac

if (( status == 0 )); then ok "完成"; else warn "完成，但部分测试失败或未找到节点"; fi
exit "$status"
