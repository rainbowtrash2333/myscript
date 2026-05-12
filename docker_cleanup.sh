#!/usr/bin/env bash

set -e

echo "======================================="
echo " Docker 环境清理工具"
echo "======================================="

# =====================================================
# 提权检测：需要 root 或 sudo
# =====================================================
if [ "$(id -u)" != "0" ]; then
    if command -v sudo &>/dev/null && sudo -v &>/dev/null 2>&1; then
        exec sudo bash "$0" "$@"
    fi
    echo "错误：需要 root 或 sudo 权限运行" >&2
    echo "请执行: sudo ./$(basename "$0")" >&2
    exit 1
fi

# -----------------------------
# 检查 Docker 是否安装并运行
# -----------------------------
if ! command -v docker &>/dev/null; then
    echo "错误：未检测到 Docker，请先安装 Docker" >&2
    exit 1
fi

echo
echo "======================================="
echo " 当前 Docker 资源使用情况"
echo "======================================="

# -----------------------------
# 显示当前状态
# -----------------------------
STOPPED_COUNT=$(docker ps -a -q -f status=exited 2>/dev/null | wc -l)
DANGLING_IMG_COUNT=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
UNUSED_VOL_COUNT=$(docker volume ls -q -f "dangling=true" 2>/dev/null | wc -l)
CREATED_COUNT=$(docker ps -a -q -f status=created 2>/dev/null | wc -l)
UNUSED_NET_COUNT=$(docker network ls --filter "type=custom" -q 2>/dev/null | wc -l)

ALL_IMG_COUNT=$(docker images -q 2>/dev/null | wc -l)
ALL_VOL_COUNT=$(docker volume ls -q 2>/dev/null | wc -l)
ALL_CONT_COUNT=$(docker ps -a -q 2>/dev/null | wc -l)

echo "已停止的容器    : ${STOPPED_COUNT}"
echo "已创建(未运行)容器: ${CREATED_COUNT}"
echo "悬空镜像(dangling): ${DANGLING_IMG_COUNT}"
echo "悬空卷(dangling)  : ${UNUSED_VOL_COUNT}"
echo ""
echo "容器总数        : ${ALL_CONT_COUNT}"
echo "镜像总数        : ${ALL_IMG_COUNT}"
echo "卷总数          : ${ALL_VOL_COUNT}"
echo "自定义网络总数  : ${UNUSED_NET_COUNT}"

# -----------------------------
# 磁盘空间预览
# -----------------------------
echo
echo "---------------------------------------"
echo " 可释放磁盘空间预估"
echo "---------------------------------------"
docker system df 2>/dev/null || echo "无法获取磁盘使用信息"

# -----------------------------
# 用户确认
# -----------------------------
echo
read -p "确认清理以上所有未使用的 Docker 资源？[y/N] " CONFIRM
if [ "${CONFIRM}" != "y" ] && [ "${CONFIRM}" != "Y" ]; then
    echo "已取消清理操作"
    exit 0
fi

echo
echo "======================================="
echo " 开始清理..."
echo "======================================="

# -----------------------------
# 1. 删除已停止的容器
# -----------------------------
if [ "${STOPPED_COUNT}" -gt 0 ] || [ "${CREATED_COUNT}" -gt 0 ]; then
    echo
    echo ">>> 删除已停止和已创建的容器..."
    docker container prune -f
else
    echo ">>> 没有需要删除的已停止容器"
fi

# -----------------------------
# 2. 删除未使用的镜像（包括悬空和未标记）
# -----------------------------
if [ "${DANGLING_IMG_COUNT}" -gt 0 ] || [ "${ALL_IMG_COUNT}" -gt 0 ]; then
    echo
    echo ">>> 删除未使用的镜像..."
    docker image prune -a -f
else
    echo ">>> 没有需要删除的未使用镜像"
fi

# -----------------------------
# 3. 删除未使用的卷
# -----------------------------
if [ "${UNUSED_VOL_COUNT}" -gt 0 ]; then
    echo
    echo ">>> 删除未使用的卷..."
    docker volume prune -f
else
    echo ">>> 没有需要删除的未使用卷"
fi

# -----------------------------
# 4. 删除未使用的网络
# -----------------------------
if [ "${UNUSED_NET_COUNT}" -gt 0 ]; then
    echo
    echo ">>> 删除未使用的网络..."
    docker network prune -f
else
    echo ">>> 没有需要删除的未使用网络"
fi

# -----------------------------
# 5. 清理构建缓存
# -----------------------------
echo
echo ">>> 清理构建缓存..."
docker builder prune -f 2>/dev/null || echo "构建缓存清理跳过（Docker 版本可能不支持）"

# -----------------------------
# 最终状态
# -----------------------------
echo
echo "======================================="
echo " 清理完成！当前 Docker 资源状态"
echo "======================================="
docker system df 2>/dev/null || true

echo
echo "======================================="
echo " 清理完毕，Docker 环境已清爽！"
echo "======================================="
