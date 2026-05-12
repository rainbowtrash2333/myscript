#!/bin/bash
set -e

CONFIG="/app/nodebb/config.json"

echo "========================================"
echo "  NodeBB Docker (Ubuntu 24.04)"
echo "========================================"

if [ ! -f "/app/nodebb/nodebb" ]; then
    echo "[entrypoint] NodeBB source not found in mounted volume, cloning..."
    git clone -b v4.x https://github.com/NodeBB/NodeBB.git /tmp/nodebb-clone
    shopt -s dotglob
    cp -r /tmp/nodebb-clone/* /app/nodebb/
    shopt -u dotglob
    rm -rf /tmp/nodebb-clone
    cd /app/nodebb
    cp install/package.json package.json
    npm install --omit=dev
    echo "[entrypoint] NodeBB source ready."
fi

if [ -f "$CONFIG" ]; then
    echo "[entrypoint] config.json found, starting NodeBB..."
    cd /app/nodebb
    exec ./nodebb start
else
    echo "[entrypoint] No config.json found."
    echo "[entrypoint] Launching web installer on http://0.0.0.0:4567 ..."
    cd /app/nodebb
    exec ./nodebb setup
fi
