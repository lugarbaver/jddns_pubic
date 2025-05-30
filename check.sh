#!/bin/bash

# 检查是否提供了流量上限参数
if [ "$#" -ne 1 ]; then
    echo " 用法错误：必须指定每月流量上限（单位：GB）"
    echo "正确用法：wget -O - https://node1.meday.top/awsconfig.sh | bash -s -- 1700"
    exit 1
fi

traffic_limit=$1

# 安装必要组件
sudo apt update
sudo apt install cron vnstat bc -y

# 检测默认网卡（取第一个有流量的网卡）
default_iface=$(vnstat --iflist | grep -oP '(?<=\s)\w+' | head -n 1)

# 修改 vnstat 配置
sudo sed -i 's/^Interface.*/Interface "default"/' /etc/vnstat.conf
sudo sed -i 's/^#* *UnitMode.*/UnitMode 1/' /etc/vnstat.conf
sudo sed -i 's/^#* *MonthRotate.*/MonthRotate 1/' /etc/vnstat.conf

# 重启 vnstat
sudo systemctl restart vnstat
sleep 2
vnstat --update

# 创建关机检测脚本
cat << EOF | sudo tee /root/check.sh > /dev/null
#!/bin/bash

# 获取所有网卡
interfaces=\$(vnstat --iflist | grep -oP '(?<=\s)\w+')

# 流量阈值（GB）
traffic_limit=$traffic_limit
total_used_bytes=0

for iface in \$interfaces; do
    # 提取当月流量
    month_data=\$(vnstat -i \$iface --json | grep -A20 '"months"' | grep '"rx":\| "tx":' | head -n 2 | awk -F ':' '{sum+=\$2} END {print sum}')
    total_used_bytes=\$((total_used_bytes + month_data))
done

# 转换单位
used_gb=\$(echo "scale=2; \$total_used_bytes / 1073741824" | bc)

# 比较阈值
if (( \$(echo "\$used_gb > \$traffic_limit" | bc -l) )); then
    echo "流量 \$used_gb GB 超过限制 \$traffic_limit GB，执行关机"
    sudo /usr/sbin/shutdown -h now
fi
EOF

# 添加执行权限
sudo chmod +x /root/check.sh

# 添加定时任务（每3分钟检查一次）
(crontab -l 2>/dev/null; echo "*/3 * * * * /bin/bash /root/check.sh > /root/shutdown_debug.log 2>&1") | crontab -

echo " 安装完成！将每3分钟检查当月所有网卡总流量是否超过 ${traffic_limit}GB。"
