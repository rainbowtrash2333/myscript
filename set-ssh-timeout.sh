#!/bin/bash
set -e

echo "=============================="
echo " SSH 自动断开时间设置脚本"
echo "=============================="

# =========================
# 输入超时时间
# =========================
read -p "请输入 SSH 超时时间（秒，例如 600 = 10分钟）: " TIMEOUT

# 简单校验
if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
    echo "错误：请输入数字"
    exit 1
fi

echo "设置 SSH Timeout = $TIMEOUT 秒"

# =========================
# 修改 sshd_config
# =========================
CONFIG="/etc/ssh/sshd_config"

echo "==== 修改 SSH 配置 ===="

# ClientAliveInterval
if grep -q "^ClientAliveInterval" $CONFIG; then
    sudo sed -i "s/^ClientAliveInterval.*/ClientAliveInterval $TIMEOUT/" $CONFIG
else
    echo "ClientAliveInterval $TIMEOUT" | sudo tee -a $CONFIG
fi

# ClientAliveCountMax（防止误断）
if grep -q "^ClientAliveCountMax" $CONFIG; then
    sudo sed -i "s/^ClientAliveCountMax.*/ClientAliveCountMax 3/" $CONFIG
else
    echo "ClientAliveCountMax 3" | sudo tee -a $CONFIG
fi

# TCPKeepAlive
if grep -q "^TCPKeepAlive" $CONFIG; then
    sudo sed -i "s/^TCPKeepAlive.*/TCPKeepAlive yes/" $CONFIG
else
    echo "TCPKeepAlive yes" | sudo tee -a $CONFIG
fi

# =========================
# 重启 SSH
# =========================
echo "==== 重启 SSH 服务 ===="

sudo systemctl restart ssh || sudo service ssh restart

echo "=============================="
echo "设置完成"
echo "当前 SSH 超时: $TIMEOUT 秒"
echo "=============================="