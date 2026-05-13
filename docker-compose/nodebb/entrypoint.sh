#!/usr/bin/env bash
# NodeBB 容器入口
# 流程:
#   1. 等 MongoDB TCP 端口就绪
#   2. 首次启动: 用环境变量生成 setup.json, 跑 ./nodebb setup 非交互安装
#   3. exec ./nodebb start (前台, DAEMON=false)

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-/opt/config}"
CONFIG="${CONFIG:-${CONFIG_DIR}/config.json}"
SETUP_JSON="${CONFIG_DIR}/setup.json"

MONGO_HOST="${MONGO_HOST:-mongo}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_USER="${MONGO_USER:-nodebb}"
MONGO_DB="${MONGO_DB:-nodebb}"

NODEBB_URL="${NODEBB_URL:-http://localhost:4567}"
NODEBB_PORT="${NODEBB_PORT:-4567}"

ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"

: "${MONGO_PASS:?ERROR: 环境变量 MONGO_PASS 未设置}"
: "${ADMIN_PASS:?ERROR: 环境变量 ADMIN_PASS 未设置}"

cd /usr/src/app/

# ----------------------------------------------------------------------
# 1. 等 MongoDB
# ----------------------------------------------------------------------
echo "==> 等待 MongoDB (${MONGO_HOST}:${MONGO_PORT}) ..."
for i in $(seq 1 60); do
    if nc -z "${MONGO_HOST}" "${MONGO_PORT}" 2>/dev/null; then
        echo "==> MongoDB 已可达"
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "ERROR: MongoDB 120 秒内未就绪" >&2
        exit 1
    fi
    sleep 2
done

# ----------------------------------------------------------------------
# 2. 首次启动: 自动 setup
# ----------------------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
    echo "==> 首次启动: 生成 ${SETUP_JSON} 并执行 NodeBB setup"

    SECRET="$(node -e 'console.log(require("crypto").randomBytes(32).toString("hex"))')"

    cat > "$SETUP_JSON" <<EOF
{
    "url": "${NODEBB_URL}",
    "secret": "${SECRET}",
    "database": "mongo",
    "port": ${NODEBB_PORT},
    "mongo:host": "${MONGO_HOST}",
    "mongo:port": "${MONGO_PORT}",
    "mongo:username": "${MONGO_USER}",
    "mongo:password": "${MONGO_PASS}",
    "mongo:database": "${MONGO_DB}",
    "admin:username": "${ADMIN_USER}",
    "admin:email": "${ADMIN_EMAIL}",
    "admin:password": "${ADMIN_PASS}",
    "admin:password:confirm": "${ADMIN_PASS}"
}
EOF

    # nodebb setup 读 setup.json, 写出 config.json 到 cwd
    /usr/src/app/nodebb setup "$SETUP_JSON"

    if [ -f /usr/src/app/config.json ]; then
        mv /usr/src/app/config.json "$CONFIG"
    fi

    # setup.json 含明文密码, 用完即删
    rm -f "$SETUP_JSON"

    echo "==> 首次安装完成. 管理员: ${ADMIN_USER}  邮箱: ${ADMIN_EMAIL}"
fi

# 软链 config.json 到工作目录 (NodeBB 默认从 cwd 读)
if [ ! -e /usr/src/app/config.json ]; then
    ln -sf "$CONFIG" /usr/src/app/config.json
fi

# ----------------------------------------------------------------------
# 3. 启动 NodeBB (前台)
# ----------------------------------------------------------------------
echo "==> 启动 NodeBB ..."
exec /usr/src/app/nodebb start
