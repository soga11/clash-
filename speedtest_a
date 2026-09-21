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
