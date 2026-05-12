```bash id="nginx-proxy-install"
#!/usr/bin/env bash

set -e

echo "======================================="
echo " Nginx Reverse Proxy Installer"
echo "======================================="

if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 运行"
    exit 1
fi

# -----------------------------
# 输入信息
# -----------------------------

read -p "请输入域名(如 forum.example.com): " DOMAIN
read -p "请输入反代目标IP(如 127.0.0.1): " TARGET_IP
read -p "请输入反代目标端口(如 4567): " TARGET_PORT

if [ -z "$DOMAIN" ] || [ -z "$TARGET_IP" ] || [ -z "$TARGET_PORT" ]; then
    echo "输入不能为空"
    exit 1
fi

# -----------------------------
# 安装 nginx
# -----------------------------

echo
echo "安装 nginx..."

apt-get update
apt-get install -y nginx

# -----------------------------
# 创建 nginx 配置
# -----------------------------

CONFIG_FILE="/etc/nginx/sites-available/${DOMAIN}"

cat > ${CONFIG_FILE} <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    client_max_body_size 100M;

    location / {
        proxy_pass http://${TARGET_IP}:${TARGET_PORT};

        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
EOF

# -----------------------------
# 启用站点
# -----------------------------

ln -sf ${CONFIG_FILE} /etc/nginx/sites-enabled/${DOMAIN}

rm -f /etc/nginx/sites-enabled/default

# -----------------------------
# 检查配置
# -----------------------------

nginx -t

# -----------------------------
# 启动 nginx
# -----------------------------

systemctl enable nginx
systemctl restart nginx

# -----------------------------
# 防火墙
# -----------------------------

ufw allow 80/tcp || true

echo
echo "======================================="
echo " 反代完成"
echo "======================================="
echo
echo "域名:"
echo "${DOMAIN}"
echo
echo "反代目标:"
echo "http://${TARGET_IP}:${TARGET_PORT}"
echo
echo "访问地址:"
echo "http://${DOMAIN}"
echo
echo "nginx 配置文件:"
echo "${CONFIG_FILE}"
echo
echo "======================================="
```
