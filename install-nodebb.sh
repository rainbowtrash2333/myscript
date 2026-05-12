#!/usr/bin/env bash

set -e

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

echo "======================================="
echo " NodeBB Ubuntu 24.04 Auto Install"
echo " (Docker Compatible)"
echo "======================================="

# 检测 systemd 可用性 (Docker 通常无 systemd)
HAS_SYSTEMD=0
if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null 2>&1; then
    HAS_SYSTEMD=1
fi

if [ "$HAS_SYSTEMD" -eq 0 ]; then
    echo "检测到 Docker/非 systemd 环境，将使用替代方式管理服务"
fi

# -----------------------------
# 辅助：以降权用户执行命令 (兼容有无 sudo)
# -----------------------------

run_as_nodebb() {
    if command -v sudo &>/dev/null; then
        sudo -u nodebb "$@"
    else
        su -s /bin/bash nodebb -c "$*"
    fi
}

# -----------------------------
# 幂等检查: 已安装则跳过
# -----------------------------

SECRETS_FILE="/opt/nodebb/.install-secrets"

if [ -f "$SECRETS_FILE" ]; then
    echo "检测到 NodeBB 已安装，跳过安装流程"
    cat "$SECRETS_FILE"
    exit 0
fi

# -----------------------------
# 配置
# -----------------------------

NODEBB_DIR="/opt/nodebb"
NODEBB_PORT="${NODEBB_PORT:-4567}"

ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"

MONGO_ADMIN_PASS=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
MONGO_NODEBB_PASS=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
NODEBB_ADMIN_PASS=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
NODEBB_URL="${NODEBB_URL:-http://localhost:${NODEBB_PORT}}"

# -----------------------------
# 更新系统并安装基础依赖
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
    openssl \
    lsb-release

# -----------------------------
# 安装 Node.js LTS (v22)
# -----------------------------

echo "安装 Node.js..."

curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/nodesource_setup.sh
bash /tmp/nodesource_setup.sh

apt-get install -y nodejs

# -----------------------------
# 安装 MongoDB 8.0
# -----------------------------

echo "安装 MongoDB..."

curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
    gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg \
    --dearmor

UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble")

echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/8.0 multiverse" | \
    tee /etc/apt/sources.list.d/mongodb-org-8.0.list

apt-get update
apt-get install -y mongodb-org

# -----------------------------
# 启动 MongoDB
# -----------------------------

if [ "$HAS_SYSTEMD" -eq 1 ]; then
    systemctl enable mongod
    systemctl start mongod
else
    echo "启动 MongoDB (fork 模式)..."
    mkdir -p /var/log/mongodb /var/lib/mongodb
    chown -R mongodb:mongodb /var/log/mongodb /var/lib/mongodb
    mongod --fork --logpath /var/log/mongodb/mongod.log --config /etc/mongod.conf
fi

# -----------------------------
# 等待 MongoDB 就绪 (带超时)
# -----------------------------

echo "等待 MongoDB 就绪..."
MONGO_READY=0
for i in $(seq 1 30); do
    if mongosh --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
        MONGO_READY=1
        echo "MongoDB 已就绪"
        break
    fi
    sleep 1
done

if [ "$MONGO_READY" -eq 0 ]; then
    echo "错误: MongoDB 未能启动"
    exit 1
fi

# -----------------------------
# 配置 MongoDB — 创建用户
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

# -----------------------------
# 启用 MongoDB 授权
# -----------------------------

sed -i 's/^#security:/security:/' /etc/mongod.conf 2>/dev/null || true
sed -i 's/^#  authorization:/  authorization:/' /etc/mongod.conf 2>/dev/null || true
grep -q "^security:" /etc/mongod.conf || echo -e "\nsecurity:\n  authorization: enabled" >> /etc/mongod.conf

if [ "$HAS_SYSTEMD" -eq 1 ]; then
    systemctl restart mongod
else
    mongod --shutdown 2>/dev/null || true
    sleep 2
    mongod --fork --logpath /var/log/mongodb/mongod.log --config /etc/mongod.conf
fi

# 等待授权模式下 MongoDB 就绪
echo "等待 MongoDB (授权模式) 就绪..."
for i in $(seq 1 30); do
    if mongosh --quiet --username admin --password "${MONGO_ADMIN_PASS}" --authenticationDatabase admin --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
        echo "MongoDB 授权模式已就绪"
        break
    fi
    sleep 1
done

# -----------------------------
# 创建 nodebb 系统用户
# -----------------------------

id -u nodebb &>/dev/null || useradd -m -s /bin/bash nodebb

# -----------------------------
# 下载 NodeBB
# -----------------------------

echo "下载 NodeBB..."

run_as_nodebb git clone -b v4.x https://github.com/NodeBB/NodeBB.git ${NODEBB_DIR}

cd ${NODEBB_DIR}

# -----------------------------
# 写入 config.json
# -----------------------------

cat > ${NODEBB_DIR}/config.json <<EOF
{
    "url": "${NODEBB_URL}",
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
# 安装 NodeBB 依赖
# -----------------------------

echo "安装 NodeBB 依赖..."

cd ${NODEBB_DIR}

run_as_nodebb npm install --production

# -----------------------------
# 创建管理员
# -----------------------------

echo "初始化 NodeBB..."

run_as_nodebb ./nodebb build

run_as_nodebb ./nodebb start

echo "等待 NodeBB 启动..."
for i in $(seq 1 30); do
    if curl -s http://localhost:${NODEBB_PORT} >/dev/null 2>&1; then
        echo "NodeBB 已启动"
        break
    fi
    sleep 2
done

run_as_nodebb ./nodebb user:create "${ADMIN_USER}" "${ADMIN_EMAIL}" "${NODEBB_ADMIN_PASS}" --administrator

run_as_nodebb ./nodebb stop

# -----------------------------
# 保存凭据到文件 (Docker 持久化用)
# -----------------------------

cat > "$SECRETS_FILE" <<EOF
=======================================
 NodeBB 安装完成
=======================================

访问地址: ${NODEBB_URL}

NodeBB 管理员:
用户名: ${ADMIN_USER}
密码: ${NODEBB_ADMIN_PASS}

MongoDB admin:
用户名: admin
密码: ${MONGO_ADMIN_PASS}

MongoDB nodebb:
用户名: nodebb
密码: ${MONGO_NODEBB_PASS}
EOF

# -----------------------------
# systemd 服务 + 防火墙 (仅非 Docker)
# -----------------------------

if [ "$HAS_SYSTEMD" -eq 1 ]; then
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

    ufw allow ${NODEBB_PORT}/tcp || true
else
    echo "非 systemd 环境: 跳过 systemd 服务和防火墙配置"
fi

# -----------------------------
# 输出信息
# -----------------------------

cat "$SECRETS_FILE"
echo "Node.js 版本:"
node -v
echo
echo "MongoDB 版本:"
mongod --version | head -n 1
echo
echo "======================================="
