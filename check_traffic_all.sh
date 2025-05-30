#!/bin/bash
#
# check_traffic_all.sh
# 用途：
#   1) 无参：输出本月流量统计（上行/下行/总计，单位 GB）
#   2) 带参：检测本月总流量是否超过给定阈值（单位 GB），超出则关机
# 用法：
#   sudo bash check_traffic_all.sh          # 只打印统计
#   sudo bash check_traffic_all.sh 2000     # 阈值 2000 GB，超出关机

set -euo pipefail

STATE_FILE="/var/lib/traffic_monitor_all.state"

# ---- 工具：统计所有非 lo 网卡的 rx/tx 字节数 ----
get_stats() {
    local rx_total=0 tx_total=0
    for path in /sys/class/net/*; do
        iface=$(basename "$path")
        [[ "$iface" == "lo" ]] && continue
        if [[ -f "$path/statistics/rx_bytes" ]]; then
            rx_total=$(( rx_total + $(<"$path/statistics/rx_bytes") ))
        fi
        if [[ -f "$path/statistics/tx_bytes" ]]; then
            tx_total=$(( tx_total + $(<"$path/statistics/tx_bytes") ))
        fi
    done
    printf "%d %d\n" "$rx_total" "$tx_total"
}

# ---- 工具：字节转 GB，保留两位小数 ----
bytes_to_gb() {
    awk -v b="$1" 'BEGIN { printf("%.2f", b/1024/1024/1024) }'
}

# ---- 主流程：读取或初始化状态文件 ----
CUR_MONTH=$(date +%Y-%m)
read cur_rx cur_tx < <( get_stats )

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

# 每月首次运行时重置基准
if [[ "$first_run" == "yes" || "$saved_month" != "$CUR_MONTH" ]]; then
    cat > "$STATE_FILE" <<EOF
first_run=no
saved_month=$CUR_MONTH
base_rx=$cur_rx
base_tx=$cur_tx
EOF
    # 如果只是打印统计，重置后本月流量自然为 0
    if [[ $# -eq 0 ]]; then
        echo "本月已用：上行 0.00 GB，下行 0.00 GB，总计 0.00 GB"
    fi
    exit 0
fi

# 计算本月增量
delta_rx=$(( cur_rx - base_rx ))
delta_tx=$(( cur_tx - base_tx ))
delta_total=$(( delta_rx + delta_tx ))

# 模式分支
if [[ $# -eq 0 ]]; then
    # 只打印统计
    up_gb=$(bytes_to_gb "$delta_tx")
    down_gb=$(bytes_to_gb "$delta_rx")
    tot_gb=$(bytes_to_gb "$delta_total")
    echo "本月已用：上行 ${up_gb} GB，下行 ${down_gb} GB，总计 ${tot_gb} GB"
    exit 0
elif [[ $# -eq 1 ]]; then
    # 带阈值检测
    threshold_gb="$1"
    # GB 转 字节
    threshold_bytes=$(awk "BEGIN { printf(\"%.0f\", $threshold_gb * 1024^3) }")
    # 输出当前统计
    up_gb=$(bytes_to_gb "$delta_tx")
    down_gb=$(bytes_to_gb "$delta_rx")
    tot_gb=$(bytes_to_gb "$delta_total")
    echo "本月已用：上行 ${up_gb} GB，下行 ${down_gb} GB，总计 ${tot_gb} GB，阈值 ${threshold_gb} GB"
    if (( delta_total >= threshold_bytes )); then
        wall "流量已超 ${threshold_gb} GB，1 分钟后自动关机。"
        shutdown -h +1 "流量超过 ${threshold_gb} GB，自动关机"
    fi
    exit 0
else
    echo "Usage: $0 [THRESHOLD_GB]" >&2
    echo "  无参：打印本月流量统计" >&2
    echo "  带参：THRESHOLD_GB=阈值（单位 GB），超出则关机" >&2
    exit 1
fi
