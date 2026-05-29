#!/usr/bin/env bash

set -e

echo "======================================="
echo " Docker Engine Auto Install"
echo "======================================="

# =====================================================
# 提权检测: 直接 root → SUDO="" / 有 sudo → SUDO="sudo"
# =====================================================
if [ "$(id -u)" = "0" ]; then
    SUDO=""
elif command -v sudo &>/dev/null && sudo -v &>/dev/null 2>&1; then
    SUDO="sudo"
else
    echo "错误：需要 root 或 sudo 权限运行" >&2
    echo "请执行: sudo ./$(basename "$0")" >&2
    exit 1
fi

# 优先用 SUDO_USER（sudo 调用时为原始用户），回退到 whoami
CURRENT_USER="${SUDO_USER:-$(whoami)}"

echo
echo "当前用户: ${CURRENT_USER}"

# -----------------------------
# 卸载旧版本
# -----------------------------

echo
echo "卸载旧版本 Docker..."

for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    $SUDO apt-get remove -y $pkg || true
done

# -----------------------------
# 更新系统
# -----------------------------

echo
echo "安装依赖..."

$SUDO apt-get update

$SUDO apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# -----------------------------
# Docker GPG Key
# -----------------------------

echo
echo "添加 Docker 官方 GPG Key..."

$SUDO install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
$SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg

$SUDO chmod a+r /etc/apt/keyrings/docker.gpg

# -----------------------------
# Docker Repo
# -----------------------------

echo
echo "添加 Docker 仓库..."

ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)

echo \
  "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  ${CODENAME} stable" | \
$SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

# -----------------------------
# 安装 Docker
# -----------------------------

echo
echo "安装 Docker Engine..."

$SUDO apt-get update

$SUDO apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# -----------------------------
# 启动 Docker
# -----------------------------

echo
echo "启动 Docker..."

$SUDO systemctl enable docker
$SUDO systemctl start docker

# -----------------------------
# docker group
# -----------------------------

echo
echo "配置 docker 用户组..."

$SUDO groupadd docker 2>/dev/null || true

if [[ "$CURRENT_USER" == "root" ]]; then
    echo "警告：无法确定目标用户（当前为 root），跳过 docker 组添加。"
    echo "请手动执行: sudo usermod -aG docker YOUR_USERNAME"
else
    $SUDO usermod -aG docker "${CURRENT_USER}"
fi

# -----------------------------
# 测试
# -----------------------------

echo
echo "测试 Docker..."

$SUDO docker run --rm hello-world || true

# -----------------------------
# 输出
# -----------------------------

echo
echo "======================================="
echo " Docker 安装完成"
echo "======================================="
echo

echo "Docker Version:"
docker --version || $SUDO docker --version

echo
echo "Docker Compose Version:"
docker compose version || $SUDO docker compose version

echo
echo "当前用户已加入 docker 组:"
echo "${CURRENT_USER}"

echo
echo "请重新登录 SSH"
echo "或者执行:"
echo
echo "newgrp docker"
echo
echo "之后即可免 sudo 使用 docker"
echo

echo "测试命令:"
echo "docker run hello-world"

echo
echo "======================================="
