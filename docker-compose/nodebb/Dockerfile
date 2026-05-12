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

# 复制安装脚本和入口脚本
COPY install-nodebb.sh /install-nodebb.sh
COPY docker-compose/nodebb/entrypoint.sh /entrypoint.sh
RUN chmod +x /install-nodebb.sh /entrypoint.sh

EXPOSE 4567

ENTRYPOINT ["/entrypoint.sh"]
