FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# 预配置 tzdata，避免 apt install 时卡在交互输入
RUN apt-get update && apt-get install -y tzdata && \
    ln -fs "/usr/share/zoneinfo/$TZ" /etc/localtime && \
    echo "$TZ" > /etc/timezone && \
    rm -rf /var/lib/apt/lists/*

# 预装所有 apt 依赖 (build 阶段完成, 避免每次启动耗时)
RUN apt-get update && apt-get install -y \
    curl \
    git \
    build-essential \
    ca-certificates \
    gnupg \
    sudo \
    unzip \
    wget \
    openssl \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Node.js LTS
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/nodesource_setup.sh && \
    bash /tmp/nodesource_setup.sh && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# MongoDB 8.0
RUN curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
    gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor && \
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble") && \
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/8.0 multiverse" | \
    tee /etc/apt/sources.list.d/mongodb-org-8.0.list && \
    apt-get update && \
    apt-get install -y mongodb-org && \
    rm -rf /var/lib/apt/lists/*

# 复制安装脚本和入口脚本
COPY install-nodebb.sh /install-nodebb.sh
COPY docker-compose/nodebb/entrypoint.sh /entrypoint.sh
RUN chmod +x /install-nodebb.sh /entrypoint.sh

# MongoDB 数据目录预创建
RUN mkdir -p /var/log/mongodb /var/lib/mongodb && \
    chown -R mongodb:mongodb /var/log/mongodb /var/lib/mongodb

EXPOSE 4567

ENTRYPOINT ["/entrypoint.sh"]
