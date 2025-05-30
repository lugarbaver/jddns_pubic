#!/bin/bash
#
# check_traffic_all.sh
# 用途：检测所有网卡（除 lo）累计流量，超过自定义阈值则关机
# 用法：
#   sudo bash check_traffic_all.sh THRESHOLD_TB
#   THRESHOLD_TB: 必填，阈值（单位 TB），支持整数或小数

set -euo pipefail

# ---- 参数 & 配置 ----
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 THRESHOLD_TB" >&2
    echo "  THRESHOLD_TB: 流量阈值，单位 TB，必须指定" >&2
    exit 1
fi

THRESHOLD_TB="$1"
STATE_FILE="/var/lib/traffic_monitor_all.state"
# 转换 TB 到字节（1024^4）
THRESHOLD_BYTES=$(awk "BEGIN { printf(\"%.0f\", $THRESHOLD_TB * 1024^4) }")

# ---- 获取所有网卡的累计字节数 ----
get_bytes_all() {
    local total=0
    for path in /sys/class/net/*; do
        iface=$(basename "$path")
        [[ "$iface" == "lo" ]] && continue
        for stat in rx_bytes tx_bytes; do
            [[ -f "$path/statistics/$stat" ]] && total=$(( total + $(<"$path/statistics/$stat") ))
        done
    done
    echo "$total"
}

# ---- 主流程 ----
CUR_MONTH=$(date +%Y-%m)
CUR_BYTES=$(get_bytes_all)

# 初始化状态文件或跨月重置
if [[ ! -r "$STATE_FILE" ]]; then
    mkdir -p "$(dirname "$STATE_FILE")"
    cat > "$STATE_FILE" <<EOF
first_run=yes
saved_month=$CUR_MONTH
base_bytes=0
EOF
fi
# 导入状态
source "$STATE_FILE"

if [[ "$first_run" == "yes" || "$saved_month" != "$CUR_MONTH" ]]; then
    echo "[$(date)] 重置基准：月份 $CUR_MONTH，基准字节数 = $CUR_BYTES"
    cat > "$STATE_FILE" <<EOF
first_run=no
saved_month=$CUR_MONTH
base_bytes=$CUR_BYTES
EOF
    exit 0
fi

# 计算本月已用流量
DELTA_BYTES=$(( CUR_BYTES - base_bytes ))
echo "[$(date)] 已用 ${DELTA_BYTES}B，阈值 ${THRESHOLD_BYTES}B（${THRESHOLD_TB}TB）"

# 超过阈值则关机
if (( DELTA_BYTES >= THRESHOLD_BYTES )); then
    wall "流量已超 ${THRESHOLD_TB}TB，1 分钟后自动关机。"
    shutdown -h +1 "流量超过 ${THRESHOLD_TB}TB，自动关机"
fi
