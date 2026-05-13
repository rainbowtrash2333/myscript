# syntax=docker/dockerfile:1
# NodeBB 镜像
# 思路: 按官方 Ubuntu 安装指引 (https://docs.nodebb.org/installing/os/ubuntu/) 的步骤,
#       但以多阶段构建落到 Docker 镜像中:
#         - build 阶段: node:lts + git + build-essential, git clone v4.x, npm install
#         - final 阶段: node:lts-slim + tini + netcat, 只拷贝构建产物
# MongoDB 不在本镜像内, 由 compose 中独立服务提供.

ARG NODE_VERSION=lts
ARG NODEBB_VERSION=v4.x

# ----------------------------------------------------------------------
# Build stage
# ----------------------------------------------------------------------
FROM node:${NODE_VERSION} AS build

ENV NODE_ENV=production \
    DAEMON=false \
    SILENT=false \
    USER=nodebb \
    UID=1001 \
    GID=1001

ARG NODEBB_VERSION

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
        git \
        build-essential \
        ca-certificates \
        tini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app/

# 浅克隆指定分支
RUN git clone --depth=1 --branch=${NODEBB_VERSION} \
        https://github.com/NodeBB/NodeBB.git /usr/src/app/

# 启用 corepack (与官方 Dockerfile 一致, 支持 yarn/pnpm)
RUN corepack enable

# 清理 .git 等隐藏文件以减小体积
RUN find . -mindepth 1 -maxdepth 1 -name '.*' \
        ! -name '.' ! -name '..' \
        -exec bash -c 'echo "Deleting {}"; rm -rf {}' \;

# 使用生产 package.json (官方约定: install/package.json 是仅含 runtime 依赖的版本)
RUN cp /usr/src/app/install/package.json /usr/src/app/package.json

RUN groupadd --gid ${GID} ${USER} \
    && useradd --uid ${UID} --gid ${GID} --home-dir /usr/src/app/ \
        --shell /bin/bash ${USER} \
    && chown -R ${USER}:${USER} /usr/src/app/

USER ${USER}

RUN npm install --omit=dev \
    && rm -rf .npm

# ----------------------------------------------------------------------
# Final stage
# ----------------------------------------------------------------------
FROM node:${NODE_VERSION}-slim AS final

ENV NODE_ENV=production \
    DAEMON=false \
    SILENT=false \
    USER=nodebb \
    UID=1001 \
    GID=1001 \
    CONFIG_DIR=/opt/config \
    CONFIG=/opt/config/config.json

# tini 处理 PID 1 信号转发; netcat 用于 entrypoint 探测 mongo 端口
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
        tini \
        ca-certificates \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable \
    && groupadd --gid ${GID} ${USER} \
    && useradd --uid ${UID} --gid ${GID} --home-dir /usr/src/app/ \
        --shell /bin/bash ${USER} \
    && mkdir -p /usr/src/app/ /usr/src/app/logs/ /opt/config/ \
    && chown -R ${USER}:${USER} /usr/src/app/ /opt/config/

WORKDIR /usr/src/app/

COPY --from=build --chown=${USER}:${USER} /usr/src/app/ /usr/src/app/
COPY --chown=${USER}:${USER} entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

USER ${USER}

EXPOSE 4567

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
