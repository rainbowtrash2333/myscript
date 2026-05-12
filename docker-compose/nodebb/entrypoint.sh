#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

if [ -n "$TZ" ]; then
    ln -fs "/usr/share/zoneinfo/$TZ" /etc/localtime 2>/dev/null || true
    echo "$TZ" > /etc/timezone 2>/dev/null || true
fi

cleanup() {
    echo "正在关闭 NodeBB..."
    if [ -d /opt/nodebb ]; then
        su nodebb -c 'cd /opt/nodebb && ./nodebb stop' 2>/dev/null || true
    fi
    echo "正在关闭 MongoDB..."
    mongod --shutdown 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT SIGQUIT

SECRETS_FILE="/opt/nodebb/.install-secrets"

# ------------------------------------------------------------------
# 首次启动: 初始化 MongoDB 用户 + 写入配置 + 创建管理员
# ------------------------------------------------------------------
if [ ! -f "$SECRETS_FILE" ]; then
    echo "======================================="
    echo " 首次启动: 初始化 NodeBB..."
    echo "======================================="

    MONGO_ADMIN_PASS=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
    MONGO_NODEBB_PASS=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
    NODEBB_ADMIN_PASS=$(openssl rand -base64 24 | tr -d "=+/" | cut -c1-20)
    NODEBB_PORT="${NODEBB_PORT:-4567}"
    NODEBB_URL="${NODEBB_URL:-http://localhost:${NODEBB_PORT}}"
    ADMIN_USER="${ADMIN_USER:-admin}"
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"

    echo "启动 MongoDB..."
    mongod --fork --logpath /var/log/mongodb/mongod.log --config /etc/mongod.conf

    for i in $(seq 1 30); do
        if mongosh --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

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

    sed -i 's/^#security:/security:/' /etc/mongod.conf 2>/dev/null || true
    sed -i 's/^#  authorization:/  authorization:/' /etc/mongod.conf 2>/dev/null || true
    grep -q "^security:" /etc/mongod.conf || echo -e "\nsecurity:\n  authorization: enabled" >> /etc/mongod.conf

    mongod --shutdown 2>/dev/null || true
    sleep 2
    mongod --fork --logpath /var/log/mongodb/mongod.log --config /etc/mongod.conf

    for i in $(seq 1 30); do
        if mongosh --quiet --username admin --password "${MONGO_ADMIN_PASS}" --authenticationDatabase admin --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
            echo "MongoDB 已就绪"
            break
        fi
        sleep 1
    done

    cat > /opt/nodebb/config.json <<CONFIG
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
CONFIG

    chown nodebb:nodebb /opt/nodebb/config.json

    echo "初始化 NodeBB..."
    su nodebb -c 'cd /opt/nodebb && ./nodebb build && ./nodebb start'

    for i in $(seq 1 30); do
        if curl -s http://localhost:${NODEBB_PORT} >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done

    su nodebb -c "cd /opt/nodebb && ./nodebb user:create \"${ADMIN_USER}\" \"${ADMIN_EMAIL}\" \"${NODEBB_ADMIN_PASS}\" --administrator"
    su nodebb -c 'cd /opt/nodebb && ./nodebb stop'

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

    echo "NodeBB 初始化完成"
fi

# ------------------------------------------------------------------
# 每次启动
# ------------------------------------------------------------------
cat "$SECRETS_FILE"

rm -f /opt/nodebb/pidfile /opt/nodebb/loader.lock 2>/dev/null || true

if ! pgrep -x mongod >/dev/null 2>&1; then
    echo "启动 MongoDB..."
    mkdir -p /var/log/mongodb /var/lib/mongodb
    chown -R mongodb:mongodb /var/log/mongodb /var/lib/mongodb
    mongod --fork --logpath /var/log/mongodb/mongod.log --config /etc/mongod.conf
fi

echo "等待 MongoDB 就绪..."
MONGO_ADMIN_PASS=$(sed -n '/^MongoDB admin:/{n;s/.*密码: //p}' "$SECRETS_FILE" 2>/dev/null)
for i in $(seq 1 30); do
    if [ -n "$MONGO_ADMIN_PASS" ]; then
        if mongosh --quiet --username admin --password "$MONGO_ADMIN_PASS" --authenticationDatabase admin --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
            break
        fi
    else
        if mongosh --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
            break
        fi
    fi
    sleep 1
done
echo "MongoDB 已就绪"

echo "启动 NodeBB..."
su nodebb -c 'cd /opt/nodebb && ./nodebb start' 2>&1 || true

echo "所有服务已启动, 容器进入运行状态..."
echo "======================================="

tail -f /dev/null &
wait $!
