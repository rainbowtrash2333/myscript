#!/bin/bash
set -e

CONF_FILE="/etc/ssh/sshd_config.d/99-ssh-keepalive.conf"

echo "=============================="
echo " SSH 保活设置脚本"
echo " Ubuntu 24.04"
echo "=============================="
echo

# 如果带参数 --show，直接查看当前配置
if [ "$1" = "--show" ]; then
    echo "当前 SSH 保活相关配置:"
    sudo sshd -T | grep -iE "clientalive|tcpkeepalive"
    exit 0
fi

echo "你的 SSH 连接频繁断开，通常不是因为 SSH 服务器主动超时，"
echo "而是中间网络设备（NAT 网关/防火墙）在没有流量时掐断了连接。"
echo "解决方案: 让 SSH 服务器定期发送心跳包，保持连接活跃。"
echo

PS3="请选择模式: "
select opt in "一键保活模式 (推荐)" "自定义模式" "查看当前配置" "退出"; do
    case $REPLY in
        1)
            echo
            echo ">> 保活模式: 每 60 秒心跳，容忍 20 次丢包 (约 20 分钟)"
            interval=60
            count_max=20
            break
            ;;
        2)
            echo
            read -p "心跳间隔（秒，建议 30-120）: " interval
            if ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -lt 1 ]; then
                echo "错误：请输入正整数"
                exit 1
            fi
            read -p "最大丢包次数（建议 5-30）: " count_max
            if ! [[ "$count_max" =~ ^[0-9]+$ ]] || [ "$count_max" -lt 1 ]; then
                echo "错误：请输入正整数"
                exit 1
            fi
            echo ">> 自定义: 每 ${interval} 秒心跳，容忍 ${count_max} 次丢包 (约 $((interval * count_max)) 秒)"
            break
            ;;
        3)
            echo
            echo "当前 SSH 保活相关配置:"
            sudo sshd -T | grep -iE "clientalive|tcpkeepalive"
            exit 0
            ;;
        4)
            echo "已退出"
            exit 0
            ;;
        *)
            echo "无效选择，请重试"
            continue
            ;;
    esac
done

echo
echo "写入配置..."
sudo mkdir -p "$(dirname "$CONF_FILE")"

sudo tee "$CONF_FILE" > /dev/null <<EOF
# SSH 保活配置（由脚本生成）
# 每 ${interval} 秒通过加密通道发送心跳
ClientAliveInterval $interval
# 连续 ${count_max} 次心跳无回应才断开
ClientAliveCountMax $count_max
EOF

echo "重启 SSH 服务..."
sudo systemctl restart ssh

echo
echo "=============================="
echo " 配置已生效"
echo "=============================="
echo
sudo sshd -T | grep -iE "clientalive|tcpkeepalive"
echo

echo "=============================="
echo " 建议: 本地客户端也配置保活"
echo "=============================="
echo "在本地机器的 ~/.ssh/config 中添加:"
echo
echo "  Host *"
echo "      ServerAliveInterval 60"
echo "      ServerAliveCountMax 5"
echo
echo "然后运行: chmod 600 ~/.ssh/config"
echo "=============================="
