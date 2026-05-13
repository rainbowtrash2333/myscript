#!/usr/bin/env bash
# NodeBB container entrypoint
# Flow:
#   0. Fix ownership on bind-mounted directories
#   1. Wait for MongoDB to accept TCP connections
#   2. On first boot, generate setup.json and run non-interactive NodeBB setup
#   3. Start NodeBB in the foreground as the nodebb user

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

: "${MONGO_PASS:?ERROR: environment variable MONGO_PASS is required}"
: "${ADMIN_PASS:?ERROR: environment variable ADMIN_PASS is required}"

if [ "$(id -u)" = "0" ]; then
    mkdir -p "$CONFIG_DIR" "$UPLOADS_DIR"
    chown -R "${APP_USER}:${APP_USER}" "$CONFIG_DIR" "$UPLOADS_DIR"
fi

cd "$APP_DIR"

echo "==> Waiting for MongoDB (${MONGO_HOST}:${MONGO_PORT}) ..."
for i in $(seq 1 60); do
    if nc -z "${MONGO_HOST}" "${MONGO_PORT}" 2>/dev/null; then
        echo "==> MongoDB is reachable"
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "ERROR: MongoDB did not become reachable within 120 seconds" >&2
        exit 1
    fi
    sleep 2
done

if [ ! -f "$CONFIG" ]; then
    echo "==> First boot: generating ${SETUP_JSON} and running NodeBB setup"

    SECRET="$(gosu "$APP_USER" node -e 'console.log(require("crypto").randomBytes(32).toString("hex"))')"

    # Build JSON with node so special characters in env vars cannot corrupt the file.
    SECRET="$SECRET" gosu "$APP_USER" node - "$SETUP_JSON" <<'EOF'
const fs = require('fs');

const outputPath = process.argv[2];
const config = {
    url: process.env.NODEBB_URL,
    secret: process.env.SECRET,
    database: 'mongo',
    port: Number(process.env.NODEBB_PORT || 4567),
    'mongo:host': process.env.MONGO_HOST,
    'mongo:port': process.env.MONGO_PORT,
    'mongo:username': process.env.MONGO_USER,
    'mongo:password': process.env.MONGO_PASS,
    'mongo:database': process.env.MONGO_DB,
    'admin:username': process.env.ADMIN_USER,
    'admin:email': process.env.ADMIN_EMAIL,
    'admin:password': process.env.ADMIN_PASS,
    'admin:password:confirm': process.env.ADMIN_PASS,
};

fs.writeFileSync(outputPath, `${JSON.stringify(config, null, 4)}\n`);
EOF

    # NodeBB v4 expects the setup argument to be JSON content, not a file path.
    INITIAL_CONFIG="$(gosu "$APP_USER" node -e 'const fs = require("fs"); process.stdout.write(JSON.stringify(JSON.parse(fs.readFileSync(process.argv[1], "utf8"))));' "$SETUP_JSON")"
    gosu "$APP_USER" "${APP_DIR}/nodebb" setup "$INITIAL_CONFIG"

    if [ -f "${APP_DIR}/config.json" ]; then
        gosu "$APP_USER" mv "${APP_DIR}/config.json" "$CONFIG"
    fi

    rm -f "$SETUP_JSON"

    echo "==> First-time installation finished. Admin user: ${ADMIN_USER}, email: ${ADMIN_EMAIL}"
fi

if [ ! -e "${APP_DIR}/config.json" ]; then
    gosu "$APP_USER" ln -sf "$CONFIG" "${APP_DIR}/config.json"
fi

echo "==> Starting NodeBB in foreground ..."
exec gosu "$APP_USER" node loader.js --no-silent --no-daemon
