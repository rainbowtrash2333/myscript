```bash id=docker-install
#!usrbinenv bash

set -e

echo =======================================
echo  Docker Engine Auto Install
echo =======================================

if [ $(id -u) != 0 ]; then
    echo 请使用 root 运行
    exit 1
fi

CURRENT_USER=${SUDO_USER-$(logname 2devnull  echo root)}

echo
echo 当前用户 ${CURRENT_USER}

# -----------------------------
# 卸载旧版本
# -----------------------------

echo
echo 卸载旧版本 Docker...

for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    apt-get remove -y $pkg  true
done

# -----------------------------
# 更新系统
# -----------------------------

echo
echo 安装依赖...

apt-get update

apt-get install -y 
    ca-certificates 
    curl 
    gnupg 
    lsb-release

# -----------------------------
# 添加 Docker GPG Key
# -----------------------------

echo
echo 添加 Docker 官方 GPG Key...

install -m 0755 -d etcaptkeyrings

curl -fsSL httpsdownload.docker.comlinuxubuntugpg  
gpg --dearmor -o etcaptkeyringsdocker.gpg

chmod a+r etcaptkeyringsdocker.gpg

# -----------------------------
# 添加 Docker 仓库
# -----------------------------

echo
echo 添加 Docker 仓库...

ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)

echo 
  deb [arch=${ARCH} signed-by=etcaptkeyringsdocker.gpg] 
  httpsdownload.docker.comlinuxubuntu 
  ${CODENAME} stable  
  tee etcaptsources.list.ddocker.list  devnull

# -----------------------------
# 安装 Docker
# -----------------------------

echo
echo 安装 Docker Engine...

apt-get update

apt-get install -y 
    docker-ce 
    docker-ce-cli 
    containerd.io 
    docker-buildx-plugin 
    docker-compose-plugin

# -----------------------------
# 启动 Docker
# -----------------------------

echo
echo 启动 Docker...

systemctl enable docker
systemctl start docker

# -----------------------------
# docker group
# -----------------------------

echo
echo 配置 docker 用户组...

groupadd docker 2devnull  true
usermod -aG docker ${CURRENT_USER}  true

# -----------------------------
# 测试 Docker
# -----------------------------

echo
echo 测试 Docker...

docker run --rm hello-world  true

# -----------------------------
# 输出信息
# -----------------------------

echo
echo =======================================
echo  Docker 安装完成
echo =======================================
echo

echo Docker Version
docker --version

echo
echo Docker Compose Version
docker compose version

echo
echo Docker 服务状态
systemctl is-active docker

echo
echo 当前用户已加入 docker 组
echo ${CURRENT_USER}

echo
echo 请重新登录 SSH 或执行
echo
echo newgrp docker
echo
echo 之后即可免 sudo 使用 docker
echo

echo 测试命令
echo docker run hello-world

echo
echo =======================================
```
