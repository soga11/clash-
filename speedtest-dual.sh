#!/usr/bin/env bash
# ============================================================
#  speedtest-dual.sh  v3.1   (IPv4 + IPv6 双栈测速)
#  流程: ①先测"最近节点"v4+v6(反映本机地区) ②再测指定地区(广西/广东)
#  修复: 去掉非法的 --progress=no
#  用法:
#    bash speedtest-dual.sh                     # 只测最近(v4+v6)
#    bash speedtest-dual.sh -r 广东 -3           # 最近 + 广东三网
#    bash speedtest-dual.sh -r 广西 -3 -6        # 只 v6
#    bash speedtest-dual.sh -l                   # 列候选服务器
#    bash speedtest-dual.sh -s 12345             # 指定服务器ID
# ============================================================
set -u
RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';BLUE='\033[0;34m';CYAN='\033[0;36m';BOLD='\033[1m';NC='\033[0m'
info(){ printf '%b[*]%b %s\n' "$BLUE" "$NC" "$*"; }
ok(){   printf '%b[+]%b %s\n' "$GREEN" "$NC" "$*"; }
warn(){ printf '%b[!]%b %s\n' "$YELLOW" "$NC" "$*"; }
err(){  printf '%b[-]%b %s\n' "$RED" "$NC" "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

WORKDIR="$(mktemp -d 2>/dev/null || echo /tmp/sdt.$$)"; mkdir -p "$WORKDIR"
trap 'rm -rf "$WORKDIR" 2>/dev/null' EXIT

DL=""; have curl && DL=curl; [ -z "$DL" ] && have wget && DL=wget
dl_file(){ case "$DL" in
  curl) curl -fSL --connect-timeout 10 --retry 2 -o "$2" "$1";;
  wget) wget -q -T 20 -O "$2" "$1";;
  *) return 1;; esac; }

# ---------- IP 探测 ----------
get_v4(){ if have ip; then ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1
          else hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' | head -1; fi; }
get_v6(){ if have ip; then ip -6 addr show scope global 2>/dev/null | awk '/inet6/{print $2}' | cut -d/ -f1 | head -1
          else hostname -I 2>/dev/null | tr ' ' '\n' | grep ':' | head -1; fi; }
has_v6(){ [ -n "$(get_v6)" ] || return 1
  if have curl; then
    curl -6 -sI --connect-timeout 6 https://ipv6.google.com >/dev/null 2>&1 && return 0
    curl -6 -sI --connect-timeout 6 https://www.cloudflare.com >/dev/null 2>&1 && return 0
    return 1
  fi
  return 0; }

# ---------- Ookla ----------
ensure_speedtest(){
  if have speedtest; then SPEEDTEST=speedtest; return; fi
  local a=""; case "$(uname -m)" in
    x86_64|amd64) a=x86_64;; aarch64|arm64) a=aarch64;;
    armv7l|armv7) a=armhf;; i386|i686) a=i386;; esac
  [ -z "$a" ] && { err "Ookla 不支持架构 $(uname -m)"; exit 1; }
  info "下载 Ookla Speedtest CLI 1.2.0 [$a]"
  dl_file "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${a}.tgz" "$WORKDIR/o.tgz" || { err "下载失败"; exit 1; }
  tar -xzf "$WORKDIR/o.tgz" -C "$WORKDIR" 2>/dev/null || { err "解压失败"; exit 1; }
  chmod +x "$WORKDIR/speedtest" 2>/dev/null
  SPEEDTEST="$WORKDIR/speedtest"
}

# ---------- JSON 解析: jq > python3 > sed ----------
json_get(){ # $1=json  $2=path
  local j="$1" p="$2" js
  js="$(printf '%s\n' "$j" | grep -E '^\{')"; [ -z "$js" ] && js="$j"
  if have jq; then printf '%s\n' "$js" | jq -r "select(.type==\"result\")|.$p // empty" 2>/dev/null | tail -1; return; fi
  if have python3; then
    printf '%s' "$js" | python3 -c '
import json,sys
data=sys.stdin.read(); p=sys.argv[1]; obj=None
for ln in data.splitlines():
    ln=ln.strip()
    if not ln.startswith("{"): continue
    try: o=json.loads(ln)
    except: continue
    if o.get("type")=="result": obj=o
if obj is None:
    try: obj=json.loads(data)
    except: obj=None
d=obj
for k in p.split("."):
    d=d.get(k) if isinstance(d,dict) else None
    if d is None: break
print(d if d is not None else "")
' "$p" 2>/dev/null; return; fi
  case "$p" in
    download.bandwidth) printf '%s' "$js" | sed -nE 's/.*"download":\{[^}]*"bandwidth":([0-9.]+).*/\1/p';;
    upload.bandwidth)   printf '%s' "$js" | sed -nE 's/.*"upload":\{[^}]*"bandwidth":([0-9.]+).*/\1/p';;
    ping.latency)       printf '%s' "$js" | sed -nE 's/.*"ping":\{[^}]*"latency":([0-9.]+).*/\1/p';;
    server.name)        printf '%s' "$js" | sed -nE 's/.*"server":\{[^}]*"name":"([^"]*)".*/\1/p';;
    *) :;;
  esac
}

# ---------- 地区 / 运营商 ----------
region_regex(){ local k; k="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  case "$k" in
    广西|guangxi|gx) echo 'guangxi|nanning|guilin|liuzhou|beihai|wuzhou|yulin|qinzhou|baise|hezhou|hechi|laibin|chongzuo|guigang|fangchenggang';;
    广东|guangdong|gd) echo 'guangdong|guangzhou|shenzhen|dongguan|foshan|zhuhai|zhongshan|huizhou|shantou|jiangmen|zhanjiang';;
    南宁|nanning) echo 'nanning';; 广州|guangzhou) echo 'guangzhou';;
    深圳|shenzhen) echo 'shenzhen';; 东莞|dongguan) echo 'dongguan';;
    北京|beijing) echo 'beijing';; 上海|shanghai) echo 'shanghai';;
    auto|"") echo '';; *) echo "$k";; esac; }
isp_regex(){ case "$1" in
  电信) echo 'telecom|chinanet|ctcc';;
  联通) echo 'unicom|cucc';;
  移动) echo 'mobile|cmcc';;
  *) echo "$1";; esac; }

list_servers(){ "$SPEEDTEST" -L --accept-license --accept-gdpr 2>/dev/null; }
find_server(){ awk -v r="$2" -v p="$3" '{L=tolower($0)} $1 ~ /^[0-9]+$/ && L ~ r && L ~ p {print $1; exit}' <<<"$1"; }

# ---------- 跑一个测试（关键修复：用 -f json，去掉 --progress）----------
run_test(){ # $1=fam(4|6)  $2=sid  $3=label
  local fam="$1" sid="$2" label="$3"
  local -a args=("-$fam" --accept-license --accept-gdpr -f json)
  [ -n "$sid" ] && args+=(-s "$sid")
  info "$label 测速中…"
  local out; out="$("$SPEEDTEST" "${args[@]}" 2>/dev/null)"
  if [ -z "$out" ]; then warn "$label 失败（无输出）"; return 1; fi
  if printf '%s' "$out" | grep -q 'official command line client'; then
    warn "$label: 参数不被支持 → 请运行  $SPEEDTEST -h  查看可用参数"; return 1; fi
  local dl ul pg sv
  dl="$(json_get "$out" download.bandwidth)"
  ul="$(json_get "$out" upload.bandwidth)"
  pg="$(json_get "$out" ping.latency)"
  sv="$(json_get "$out" server.name)"
  if [ -n "$dl" ] && [ -n "$ul" ]; then
    awk -v l="$label" -v s="$sv" -v d="$dl" -v u="$ul" -v p="${pg:-0}" \
      'BEGIN{printf "  %-12s %-30s ↓ %8.2f  ↑ %8.2f Mbps  延迟 %.1f ms\n",l,s,d*8/1e6,u*8/1e6,p}'
  else
    warn "$label 完成但解析失败，原始输出："; printf '%s\n' "$out" | head -3
  fi
}

run_family(){ # $1=fam
  local fam="$1"; printf '\n%b===== IPv%s 测速 =====%b\n' "$BOLD" "$fam" "$NC"
  if [ "$fam" = 6 ] && [ "$V6OK" -ne 1 ]; then warn "IPv6 不可用，跳过"; return 0; fi

  # ① 最近节点（本机在哪，就测哪：HK→HK，SG→SG）
  if [ -n "$SERVER_ID" ]; then run_test "$fam" "$SERVER_ID" "指定服务器"
  else run_test "$fam" "" "最近节点"; fi

  # ② 指定地区
  if [ -n "$REGION" ] && [ "$REGION" != auto ]; then
    local servers rx; servers="$(list_servers)"
    [ -z "$servers" ] && { warn "IPv$fam 获取服务器列表失败"; return 1; }
    rx="$(region_regex "$REGION")"
    if [ "$THREE" -eq 1 ]; then
      local isp sid
      for isp in 电信 联通 移动; do
        sid="$(find_server "$servers" "$rx" "$(isp_regex "$isp")")"
        if [ -n "$sid" ]; then run_test "$fam" "$sid" "${REGION}${isp}"; else warn "IPv$fam: 未找到 ${REGION}${isp}"; fi
      done
    else
      local sid; sid="$(find_server "$servers" "$rx" "")"
      if [ -n "$sid" ]; then run_test "$fam" "$sid" "$REGION"; else warn "IPv$fam: 未找到 $REGION（-l 查看）"; fi
    fi
  fi
}

# ---------- 参数 / 主流程 ----------
REGION=""; THREE=0; SERVER_ID=""; FAMILY=both; LIST_ONLY=0
while [ $# -gt 0 ]; do case "$1" in
  -r|--region) REGION="${2:-}"; shift 2;;
  -3|--three)  THREE=1; shift;;
  -4|--v4)     FAMILY=4; shift;;
  -6|--v6)     FAMILY=6; shift;;
  -l|--list)   LIST_ONLY=1; shift;;
  -s|--server) SERVER_ID="${2:-}"; shift 2;;
  -h|--help)   sed -n '2,12p' "$0"; exit 0;;
  *) REGION="$1"; shift;;
esac; done

ensure_speedtest
IPV4="$(get_v4)"; IPV6="$(get_v6)"; V6OK=0; has_v6 && V6OK=1
if [ "$LIST_ONLY" -eq 1 ]; then list_servers; exit 0; fi

printf '%b================================================%b\n' "$CYAN" "$NC"
printf ' IPv4 : %s\n' "${IPV4:-无}"
printf ' IPv6 : %s\n' "${IPV6:-无}"
if [ "$V6OK" -eq 1 ]; then ok "IPv6 可用 → 一并测试"; else warn "IPv6 不可用 → 跳过"; fi
printf ' 地区 : %s   模式: %s\n' "${REGION:-仅最近节点}" "$([ "$THREE" -eq 1 ] && echo 三网 || echo 单测)"
printf '%b================================================%b\n' "$CYAN" "$NC"

case "$FAMILY" in
  4) run_family 4;;
  6) run_family 6;;
  both) run_family 4
        if [ "$V6OK" -eq 1 ]; then run_family 6; else warn "IPv6 不可用，已跳过"; fi;;
esac
echo; ok "完成 ✅"
