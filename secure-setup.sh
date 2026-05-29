#!/bin/bash
set -e

echo "=============================="
echo "  Ubuntu 安全初始化脚本"
echo "=============================="

# =====================================================
# 提权检测：非 root 但有 sudo 则自动重提
# =====================================================
if [ "$(id -u)" != "0" ]; then
    if command -v sudo &>/dev/null && sudo -v &>/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    fi
    echo "错误：需要 root 或 sudo 权限运行" >&2
    echo "请执行: sudo ./$(basename "$0")" >&2
    exit 1
fi

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
