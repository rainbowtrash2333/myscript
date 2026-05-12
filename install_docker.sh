#!/usr/bin/env bash

set -e

echo "======================================="
echo " Docker Engine Auto Install"
echo "======================================="

# -----------------------------
# 检查 sudo
# -----------------------------

if ! command -v sudo >/dev/null 2>&1; then
    echo "未安装 sudo"
    echo "请先执行: su -"
    echo "然后安装 sudo"
    exit 1
fi

# -----------------------------
# sudo 权限检测
# -----------------------------

if ! sudo -v; then
    echo "sudo 验证失败"
    exit 1
fi

CURRENT_USER=$(whoami)

echo
echo "当前用户: ${CURRENT_USER}"

# -----------------------------
# 卸载旧版本
# -----------------------------

echo
echo "卸载旧版本 Docker..."

for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    sudo apt-get remove -y $pkg || true
done

# -----------------------------
# 更新系统
# -----------------------------

echo
echo "安装依赖..."

sudo apt-get update

sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# -----------------------------
# Docker GPG Key
# -----------------------------

echo
echo "添加 Docker 官方 GPG Key..."

sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg

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
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# -----------------------------
# 安装 Docker
# -----------------------------

echo
echo "安装 Docker Engine..."

sudo apt-get update

sudo apt-get install -y \
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

sudo systemctl enable docker
sudo systemctl start docker

# -----------------------------
# docker group
# -----------------------------

echo
echo "配置 docker 用户组..."

sudo groupadd docker 2>/dev/null || true
sudo usermod -aG docker ${CURRENT_USER}

# -----------------------------
# 测试
# -----------------------------

echo
echo "测试 Docker..."

sudo docker run --rm hello-world || true

# -----------------------------
# 输出
# -----------------------------

echo
echo "======================================="
echo " Docker 安装完成"
echo "======================================="
echo

echo "Docker Version:"
docker --version || sudo docker --version

echo
echo "Docker Compose Version:"
docker compose version || sudo docker compose version

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