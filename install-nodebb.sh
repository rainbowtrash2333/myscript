#!/usr/bin/env bash

set -e

echo "======================================="
echo " NodeBB Ubuntu Auto Install"
echo "======================================="

if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 运行"
    exit 1
fi

# -----------------------------
# 配置
# -----------------------------

NODEBB_DIR="/opt/nodebb"
NODEBB_PORT="4567"

ADMIN_USER="admin"
ADMIN_EMAIL="admin@example.com"

MONGO_ADMIN_PASS=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
MONGO_NODEBB_PASS=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
NODEBB_ADMIN_PASS=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)

# -----------------------------
# 更新系统
# -----------------------------

apt-get update

apt-get install -y \
    curl \
    git \
    build-essential \
    ca-certificates \
    gnupg \
    unzip \
    wget \
    openssl

# -----------------------------
# 安装 Node.js LTS
# -----------------------------

echo "安装 Node.js..."

curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/nodesource_setup.sh
bash /tmp/nodesource_setup.sh

apt-get install -y nodejs

# -----------------------------
# 安装 MongoDB 8
# -----------------------------

echo "安装 MongoDB..."

curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg \
--dearmor

UBUNTU_CODENAME=$(lsb_release -cs)

echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/8.0 multiverse" \
| tee /etc/apt/sources.list.d/mongodb-org-8.0.list

apt-get update
apt-get install -y mongodb-org

systemctl enable mongod
systemctl start mongod

sleep 5

# -----------------------------
# 配置 MongoDB
# -----------------------------

echo "配置 MongoDB..."

mongosh <<EOF
use admin
db.createUser({
  user: "admin",
  pwd: "${MONGO_ADMIN_PASS}",
  roles: [ { role: "root", db: "admin" } ]
})

use nodebb
db.createUser({
  user: "nodebb",
  pwd: "${MONGO_NODEBB_PASS}",
  roles: [
    { role: "readWrite", db: "nodebb" },
    { role: "clusterMonitor", db: "admin" }
  ]
})
EOF

grep -q "authorization: enabled" /etc/mongod.conf || cat >> /etc/mongod.conf <<EOF

security:
  authorization: enabled
EOF

systemctl restart mongod

# -----------------------------
# 创建 nodebb 用户
# -----------------------------

id -u nodebb &>/dev/null || useradd -m -s /bin/bash nodebb

# -----------------------------
# 下载 NodeBB
# -----------------------------

echo "下载 NodeBB..."

sudo -u nodebb git clone -b v4.x https://github.com/NodeBB/NodeBB.git ${NODEBB_DIR}

cd ${NODEBB_DIR}

# -----------------------------
# 写入 config.json
# -----------------------------

cat > ${NODEBB_DIR}/config.json <<EOF
{
    "url": "http://0.0.0.0:${NODEBB_PORT}",
    "secret": "$(openssl rand -hex 32)",
    "database": "mongo",
    "mongo": {
        "host": "127.0.0.1",
        "port": "27017",
        "username": "nodebb",
        "password": "${MONGO_NODEBB_PASS}",
        "database": "nodebb"
    },
    "port": "${NODEBB_PORT}",
    "bind_address": "0.0.0.0"
}
EOF

chown -R nodebb:nodebb ${NODEBB_DIR}

# -----------------------------
# 安装 NodeBB
# -----------------------------

echo "安装 NodeBB 依赖..."

cd ${NODEBB_DIR}

sudo -u nodebb npm install --production

# -----------------------------
# 创建管理员
# -----------------------------

echo "初始化 NodeBB..."

sudo -u nodebb ./nodebb build

sudo -u nodebb ./nodebb start

sleep 15

sudo -u nodebb ./nodebb user:create "${ADMIN_USER}" "${ADMIN_EMAIL}" "${NODEBB_ADMIN_PASS}" --administrator

sudo -u nodebb ./nodebb stop

# -----------------------------
# systemd 服务
# -----------------------------

cat > /etc/systemd/system/nodebb.service <<EOF
[Unit]
Description=NodeBB Forum
After=network.target mongod.service

[Service]
Type=forking
User=nodebb
Group=nodebb
WorkingDirectory=${NODEBB_DIR}
ExecStart=${NODEBB_DIR}/nodebb start
ExecStop=${NODEBB_DIR}/nodebb stop
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nodebb
systemctl start nodebb

# -----------------------------
# 防火墙
# -----------------------------

ufw allow ${NODEBB_PORT}/tcp || true

# -----------------------------
# 输出信息
# -----------------------------

IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

echo
echo "======================================="
echo " 安装完成"
echo "======================================="
echo
echo "访问地址:"
echo "http://${IP}:${NODEBB_PORT}"
echo
echo "NodeBB 管理员:"
echo "用户名: ${ADMIN_USER}"
echo "密码: ${NODEBB_ADMIN_PASS}"
echo
echo "MongoDB admin:"
echo "用户名: admin"
echo "密码: ${MONGO_ADMIN_PASS}"
echo
echo "MongoDB nodebb:"
echo "用户名: nodebb"
echo "密码: ${MONGO_NODEBB_PASS}"
echo
echo "Node.js 版本:"
node -v
echo
echo "MongoDB 版本:"
mongod --version | head -n 1
echo
echo "======================================="
