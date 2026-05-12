#!/usr/bin/env bash
set -e

# 确保 apt 非交互 (防止 tzdata 等 debconf 弹窗卡住)
export DEBIAN_FRONTEND=noninteractive

# 应用时区 (来自 docker-compose 的 TZ 环境变量)
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

# ------------------------------------------------------------------
# 首次启动: 执行完整安装
# ------------------------------------------------------------------
if [ ! -f /opt/nodebb/.install-secrets ]; then
    echo "======================================="
    echo " 首次启动: 开始安装 NodeBB..."
    echo "======================================="
    /install-nodebb.sh
fi

# 每次启动显示凭据
if [ -f /opt/nodebb/.install-secrets ]; then
    cat /opt/nodebb/.install-secrets
fi

# ------------------------------------------------------------------
# 清理上次残留的 PID / lock 文件 (容器重启后)
# ------------------------------------------------------------------
if [ -d /opt/nodebb ]; then
    rm -f /opt/nodebb/pidfile /opt/nodebb/loader.lock 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 启动 MongoDB (幂等: 未运行才启动)
# ------------------------------------------------------------------
if ! pgrep -x mongod >/dev/null 2>&1; then
    echo "启动 MongoDB..."
    mkdir -p /var/log/mongodb /var/lib/mongodb
    chown -R mongodb:mongodb /var/log/mongodb /var/lib/mongodb
    mongod --fork --logpath /var/log/mongodb/mongod.log --config /etc/mongod.conf
fi

# 等待 MongoDB 就绪 (兼容有/无授权模式)
echo "等待 MongoDB 就绪..."
MONGO_READY=0
MONGO_ADMIN_PASS=$(sed -n '/^MongoDB admin:/{n;s/.*密码: //p}' /opt/nodebb/.install-secrets 2>/dev/null)
for i in $(seq 1 30); do
    if [ -n "$MONGO_ADMIN_PASS" ]; then
        if mongosh --quiet --username admin --password "$MONGO_ADMIN_PASS" --authenticationDatabase admin --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
            MONGO_READY=1
            break
        fi
    else
        if mongosh --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
            MONGO_READY=1
            break
        fi
    fi
    sleep 1
done
if [ "$MONGO_READY" -eq 0 ]; then
    echo "错误: MongoDB 未能启动"
    exit 1
fi
echo "MongoDB 已就绪"

# ------------------------------------------------------------------
# 启动 NodeBB
# ------------------------------------------------------------------
echo "启动 NodeBB..."
su nodebb -c 'cd /opt/nodebb && ./nodebb start' 2>&1 || true

echo "所有服务已启动, 容器进入运行状态..."
echo "======================================="

# 保持容器运行 (后台 tail 进程 + wait 阻塞)
tail -f /dev/null &
wait $!
