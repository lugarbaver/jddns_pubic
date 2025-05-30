#!/bin/bash

# 默认流量上限（单位：GB）
DEFAULT_LIMIT=2000

# 用户可通过参数自定义流量上限
if [ "$1" != "" ]; then
    traffic_limit="$1"
else
    traffic_limit=$DEFAULT_LIMIT
fi

# 安装必要组件
sudo apt update
sudo apt install cron vnstat bc -y

# 检测默认网卡（取第一个有进出流量的网卡）
default_iface=$(vnstat --iflist | grep -oP '(?<=\s)\w+' | head -n 1)

# 修改 vnstat 配置：监听所有网卡，设置以 GB 单位显示，启用月轮换
sudo sed -i 's/^Interface.*/Interface "default"/' /etc/vnstat.conf
sudo sed -i 's/^#* *UnitMode.*/UnitMode 1/' /etc/vnstat.conf
sudo sed -i 's/^#* *MonthRotate.*/MonthRotate 1/' /etc/vnstat.conf

# 重启 vnstat
sudo systemctl restart vnstat
sleep 2

# 确保 vnstat 已初始化所有网卡
vnstat --update

# 创建自动关机脚本
cat << EOF | sudo tee /root/check.sh > /dev/null
#!/bin/bash

# 获取所有活跃网卡
interfaces=\$(vnstat --iflist | grep -oP '(?<=\s)\w+')

# 流量阈值（GB）
traffic_limit=$traffic_limit

total_used_bytes=0

for iface in \$interfaces; do
    # 获取当前网卡本月流量（单位：Bytes）
    month_data=\$(vnstat -i \$iface --json | grep -A20 '"months"' | grep '"rx":\| "tx":' | head -n 2 | awk -F ':' '{sum+=\$2} END {print sum}')
    total_used_bytes=\$((total_used_bytes + month_data))
done

# 转换为 GB
used_gb=\$(echo "scale=2; \$total_used_bytes / 1073741824" | bc)

# 判断是否超过限制
if (( \$(echo "\$used_gb > \$traffic_limit" | bc -l) )); then
    echo "流量 \$used_gb GB 超过限制 \$traffic_limit GB，执行关机。"
    sudo /usr/sbin/shutdown -h now
fi
EOF

# 设置权限
sudo chmod +x /root/check.sh

# 设置定时任务：每3分钟检查一次
(crontab -l 2>/dev/null; echo "*/3 * * * * /bin/bash /root/check.sh > /root/shutdown_debug.log 2>&1") | crontab -

echo " 配置完成。系统将每3分钟自动检测当月流量是否超出 ${traffic_limit}GB。"
