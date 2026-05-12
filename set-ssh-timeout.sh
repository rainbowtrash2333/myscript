#!/bin/bash
set -e

echo "=============================="
echo " SSH 空闲超时设置脚本"
echo "=============================="

read -p "请输入希望的空闲断开时间（秒，如 600 表示 10 分钟）: " idle_timeout

if ! [[ "$idle_timeout" =~ ^[0-9]+$ ]] || [ "$idle_timeout" -eq 0 ]; then
    echo "错误：请输入大于 0 的数字"
    exit 1
fi

# 固定心跳次数为 3，计算间隔（整除取整）
count_max=3
interval=$(( idle_timeout / count_max ))

if [ "$interval" -eq 0 ]; then
    interval=1       # 至少 1 秒
fi

CONF_FILE="/etc/ssh/sshd_config.d/99-ssh-idle-timeout.conf"

echo "实际设置: 每 ${interval} 秒心跳, ${count_max} 次无响应断开 (约 $((interval * count_max)) 秒)"
echo "写入配置文件 ${CONF_FILE} ..."

sudo tee "$CONF_FILE" > /dev/null <<EOF
# SSH 空闲断开配置（由脚本生成）
ClientAliveInterval $interval
ClientAliveCountMax $count_max
TCPKeepAlive yes
EOF

echo "重启 SSH 服务..."
sudo systemctl restart ssh

echo "=============================="
echo "设置完成，生效后空闲 $((interval * count_max)) 秒断开"
echo "=============================="
