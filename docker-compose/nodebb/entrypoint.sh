#!/bin/bash
set -e

CONFIG="/app/nodebb/config.json"

echo "========================================"
echo "  NodeBB Docker (Ubuntu 24.04)"
echo "========================================"

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
