#!/bin/bash
set -e

echo "=============================="
echo "  Ubuntu 安全初始化脚本"
echo "=============================="

# ====== 1. 创建用户 ======
read -p "输入新用户名: " USERNAME

if id "$USERNAME" &>/dev/null; then
    echo "用户已存在，跳过创建"
else
    adduser "$USERNAME"
fi

# ====== 2. 加入 sudo ======
usermod -aG sudo "$USERNAME"
echo "[OK] 已添加 sudo 权限"

# ====== 3. 禁止 root SSH 登录 ======
echo "配置 SSH 禁止 root 登录..."

SSH_CONFIG="/etc/ssh/sshd_config"

if grep -q "^PermitRootLogin" $SSH_CONFIG; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' $SSH_CONFIG
else
    echo "PermitRootLogin no" >> $SSH_CONFIG
fi

# 可选：禁止密码 root 登录（更安全）
if grep -q "^PasswordAuthentication" $SSH_CONFIG; then
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' $SSH_CONFIG
else
    echo "PasswordAuthentication yes" >> $SSH_CONFIG
fi

# ====== 4. 重启 SSH ======
echo "重启 SSH 服务..."
systemctl restart ssh || service ssh restart

# ====== 5. 输出结果 ======
echo "=============================="
echo "完成！"
echo "新用户: $USERNAME"
echo "sudo 权限: 已开启"
echo "root SSH: 已禁止"
echo "=============================="