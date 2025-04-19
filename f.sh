#!/bin/sh

# 自动安装 iperf3（如果尚未安装）
if ! command -v iperf3 >/dev/null 2>&1; then
    echo "iperf3 未找到，正在安装..."
    sudo apt update
    sudo apt install iperf3 -y
fi

# 帮助文档函数
show_help() {
    cat <<EOF
Usage: f <command> [options]
Commands:
  ip4          Show public IPv4 address (curl ip.sb -4)
  ip6          Show public IPv6 address (curl ip.sb -6)
  s            Start iperf3 server on port 9123
  <IP> [-P N]  Run iperf3 client in reverse mode (-R) to <IP> on port 9123;
               optionally specify streams with -P N
  -h, help     Show this help message
EOF
}

# 如果没有参数，则显示帮助文档
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

case "$1" in
    ip4)
        curl ip.sb -4
        ;;
    ip6)
        curl ip.sb -6
        ;;
    s)
        # 启动服务器模式
        shift
        iperf3 -s -p 9123
        ;;
    -h|help)
        show_help
        ;;
    *)
        # 客户端模式，匹配 IP 地址
        if echo "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            IP="$1"
            shift
            STREAMS=""
            if [ "$1" = "-P" ] && [ -n "$2" ]; then
                STREAMS="-P $2"
            fi
            iperf3 -R -c "$IP" -p 9123 $STREAMS
        else
            show_help
            exit 1
        fi
        ;;
esac
