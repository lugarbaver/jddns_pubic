#!/bin/bash
#
# check_traffic_all.sh
# 用途：
#   1) 无参：打印当前累计流量（上行/下行/总计，单位 GB）
#   2) 带参：检测本月总流量（GB）是否超过阈值，超出则关机
# 用法：
#   sudo bash check_traffic_all.sh         # 只打印累计流量
#   sudo bash check_traffic_all.sh 2000    # 阈值 2000 GB，超出关机

set -euo pipefail

STATE_FILE="/var/lib/traffic_monitor_all.state"

# ---- 工具：统计所有非 lo 网卡的 rx/tx 字节数 ----
get_stats() {
    local rx_total=0 tx_total=0
    for path in /sys/class/net/*; do
        iface=$(basename "$path")
        [[ "$iface" == "lo" ]] && continue
        [[ -f "$path/statistics/rx_bytes" ]] && rx_total=$(( rx_total + $(<"$path/statistics/rx_bytes") ))
        [[ -f "$path/statistics/tx_bytes" ]] && tx_total=$(( tx_total + $(<"$path/statistics/tx_bytes") ))
    done
    printf "%d %d\n" "$rx_total" "$tx_total"
}

# ---- 工具：字节 转 GB，保留两位小数 ----
bytes_to_gb() {
    awk -v b="$1" 'BEGIN { printf("%.2f", b/1024/1024/1024) }'
}

# 先拿到当前累积值
read cur_rx cur_tx < <(get_stats)

# 如果无参数，直接打印当前累计（不依赖 state）
if [[ $# -eq 0 ]]; then
    up_gb=$(bytes_to_gb "$cur_tx")
    down_gb=$(bytes_to_gb "$cur_rx")
    tot_gb=$(bytes_to_gb $(( cur_rx + cur_tx )))
    echo "当前累计：上行 ${up_gb} GB，下行 ${down_gb} GB，总计 ${tot_gb} GB"
    exit 0
fi

# 带一个参数，做阈值检测
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [THRESHOLD_GB]" >&2
    exit 1
fi

THRESHOLD_GB="$1"
# GB 转 字节
THRESHOLD_BYTES=$(awk "BEGIN { printf(\"%.0f\", $THRESHOLD_GB * 1024^3) }")

CUR_MONTH=$(date +%Y-%m)
# 初始化或加载 state 文件
if [[ ! -r "$STATE_FILE" ]]; then
    mkdir -p "$(dirname "$STATE_FILE")"
    cat > "$STATE_FILE" <<EOF
first_run=yes
saved_month=$CUR_MONTH
base_rx=0
base_tx=0
EOF
fi
source "$STATE_FILE"

# 月初重置
if [[ "$first_run" == "yes" || "$saved_month" != "$CUR_MONTH" ]]; then
    cat > "$STATE_FILE" <<EOF
first_run=no
saved_month=$CUR_MONTH
base_rx=$cur_rx
base_tx=$cur_tx
EOF
    # 首次运行不做检测，只打印 0
    echo "本月已用：上行 0.00 GB，下行 0.00 GB，总计 0.00 GB（已重置基准）"
    exit 0
fi

# 计算本月增量
delta_rx=$(( cur_rx - base_rx ))
delta_tx=$(( cur_tx - base_tx ))
delta_tot=$(( delta_rx + delta_tx ))

up_gb=$(bytes_to_gb "$delta_tx")
down_gb=$(bytes_to_gb "$delta_rx")
tot_gb=$(bytes_to_gb "$delta_tot")

# 输出一次
echo "本月已用：上行 ${up_gb} GB，下行 ${down_gb} GB，总计 ${tot_gb} GB；阈值 ${THRESHOLD_GB} GB"

# 超过阈值则关机
if (( delta_tot >= THRESHOLD_BYTES )); then
    wall "流量已超 ${THRESHOLD_GB} GB，1 分钟后自动关机。"
    shutdown -h +1 "流量超过 ${THRESHOLD_GB} GB，自动关机"
fi
