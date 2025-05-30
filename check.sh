#!/bin/bash
# ================================================
# check.sh — 一键部署 & 定时检查当月流量超限并关机
# URL: https://raw.githubusercontent.com/lugarbaver/jddns_pubic/refs/heads/main/check.sh
#
# 用法：
#   wget -O - https://raw.githubusercontent.com/lugarbaver/jddns_pubic/refs/heads/main/check.sh | bash -s -- <流量阈值GB> [网卡名称]
#
# 示例：
#   wget -O - https://raw.githubusercontent.com/lugarbaver/jddns_pubic/refs/heads/main/check.sh | bash -s -- 1700        # 监听所有网卡
#   wget -O - https://raw.githubusercontent.com/lugarbaver/jddns_pubic/refs/heads/main/check.sh | bash -s -- 1700 ens5   # 只监听 ens5
# ================================================

set -e

# —— 参数检查 —— 
if [ -z "$1" ]; then
    echo " 错误：必须指定每月流量阈值（单位：GB）"
    echo "wget -O - https://raw.githubusercontent.com/lugarbaver/jddns_pubic/refs/heads/main/check.sh | bash -s -- <流量阈值GB> [网卡名称]"
    exit 1
fi

TRAFFIC_LIMIT="$1"
CUSTOM_IFACE="$2"

# —— 安装依赖 —— 
echo " 安装依赖：cron, vnstat, bc"
sudo apt update
sudo apt install -y cron vnstat bc

# —— 配置 vnStat —— 
echo " 配置 /etc/vnstat.conf"
if [ -n "$CUSTOM_IFACE" ]; then
    sudo sed -i 's|^Interface.*|Interface "'$CUSTOM_IFACE'"|' /etc/vnstat.conf
else
    sudo sed -i 's|^Interface.*|Interface "default"|' /etc/vnstat.conf
fi
sudo sed -i 's|^#* *UnitMode.*|UnitMode 1|'   /etc/vnstat.conf
sudo sed -i 's|^#* *MonthRotate.*|MonthRotate 1|' /etc/vnstat.conf

# —— 重启并更新 vnstat 数据库 —— 
sudo systemctl restart vnstat
sleep 2
vnstat --update

# —— 部署实际检查脚本到 /root/check.sh —— 
echo " 部署 /root/check.sh"
sudo tee /root/check.sh > /dev/null << 'EOF'
#!/bin/bash
# 自动按月统计流量，超限关机

traffic_limit=__TRAFFIC_LIMIT__   # GB
custom_iface="__CUSTOM_IFACE__"

current_ym=$(date +%Y%m)

get_iface_month_bytes() {
    local iface="$1"
    vnstat --dumpdb -i "$iface" 2>/dev/null \
      | awk -F';' -v ym="$current_ym" \
            '$1=="M" && $2==ym {print $3+$4; exit}' \
      || echo 0
}

total_bytes=0
if [ -n "$custom_iface" ]; then
    total_bytes=$(get_iface_month_bytes "$custom_iface")
else
    for iface in $(vnstat --iflist | grep -oP '(?<=\s)\w+'); do
        total_bytes=$(( total_bytes + $(get_iface_month_bytes "$iface") ))
    done
fi

used_gb=$(echo "scale=2; $total_bytes / 1073741824" | bc)

# 日志调试（如需启用，去掉下行注释）
# echo "$(date '+%Y-%m-%d %H:%M:%S') used=${used_gb}GB limit=${traffic_limit}GB" >> /root/shutd
