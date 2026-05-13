#!/usr/bin/env bash
# NodeBB 容器入口
# 流程:
#   0. 以 root 启动: chown 绑挂目录, 让 nodebb 用户能写
#   1. 等 MongoDB TCP 端口就绪
#   2. 首次启动: 用环境变量生成 setup.json, 跑 ./nodebb setup 非交互安装
#   3. exec gosu nodebb ./nodebb start (前台, DAEMON=false)

set -euo pipefail

APP_USER=nodebb
APP_DIR=/usr/src/app
CONFIG_DIR="${CONFIG_DIR:-/opt/config}"
CONFIG="${CONFIG:-${CONFIG_DIR}/config.json}"
SETUP_JSON="${CONFIG_DIR}/setup.json"
UPLOADS_DIR="${APP_DIR}/public/uploads"

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

# ----------------------------------------------------------------------
# 0. 修复绑挂目录所有权
#    宿主机首启时 ./data/config 与 ./data/uploads 是 root 所有,
#    覆盖了镜像内 nodebb:nodebb 的所有权 —— 必须在容器内 chown 回来
# ----------------------------------------------------------------------
if [ "$(id -u)" = "0" ]; then
    mkdir -p "$CONFIG_DIR" "$UPLOADS_DIR"
    chown -R "${APP_USER}:${APP_USER}" "$CONFIG_DIR" "$UPLOADS_DIR"
fi

cd "$APP_DIR"

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
# 2. 首次启动: 自动 setup (以 nodebb 身份)
# ----------------------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
    echo "==> 首次启动: 生成 ${SETUP_JSON} 并执行 NodeBB setup"

    SECRET="$(gosu "$APP_USER" node -e 'console.log(require("crypto").randomBytes(32).toString("hex"))')"

    # 用 gosu 写文件, 保证文件属主是 nodebb
    gosu "$APP_USER" tee "$SETUP_JSON" >/dev/null <<EOF
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

    # nodebb setup 读 setup.json, 写 config.json 到 cwd
    gosu "$APP_USER" "${APP_DIR}/nodebb" setup "$SETUP_JSON"

    if [ -f "${APP_DIR}/config.json" ]; then
        gosu "$APP_USER" mv "${APP_DIR}/config.json" "$CONFIG"
    fi

    # setup.json 含明文密码, 用完即删
    rm -f "$SETUP_JSON"

    echo "==> 首次安装完成. 管理员: ${ADMIN_USER}  邮箱: ${ADMIN_EMAIL}"
fi

# 软链 config.json 到工作目录 (NodeBB 默认从 cwd 读)
if [ ! -e "${APP_DIR}/config.json" ]; then
    gosu "$APP_USER" ln -sf "$CONFIG" "${APP_DIR}/config.json"
fi

# ----------------------------------------------------------------------
# 3. 启动 NodeBB (前台, 降权到 nodebb)
# ----------------------------------------------------------------------
echo "==> 启动 NodeBB ..."
exec gosu "$APP_USER" "${APP_DIR}/nodebb" start
