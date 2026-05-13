#!/bin/bash
# MongoDB 首启初始化
# 镜像在数据库为空时执行 /docker-entrypoint-initdb.d/*.sh 与 *.js
# 此时已用 MONGO_INITDB_ROOT_* 建好 root, 这里再建一个业务用户给 NodeBB 用

set -e

: "${MONGO_USER:?MONGO_USER 未设置}"
: "${MONGO_PASS:?MONGO_PASS 未设置}"
: "${MONGO_INITDB_DATABASE:?MONGO_INITDB_DATABASE 未设置}"

mongosh \
    --host 127.0.0.1 \
    --port 27017 \
    -u "${MONGO_INITDB_ROOT_USERNAME}" \
    -p "${MONGO_INITDB_ROOT_PASSWORD}" \
    --authenticationDatabase admin \
    "${MONGO_INITDB_DATABASE}" <<EOF
db.createUser({
    user: "${MONGO_USER}",
    pwd: "${MONGO_PASS}",
    roles: [
        { role: "readWrite", db: "${MONGO_INITDB_DATABASE}" },
        { role: "clusterMonitor", db: "admin" }
    ]
});
print("==> NodeBB MongoDB user created: ${MONGO_USER} @ ${MONGO_INITDB_DATABASE}");
EOF
