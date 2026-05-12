FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update && apt-get install -y tzdata && \
    ln -fs "/usr/share/zoneinfo/$TZ" /etc/localtime && \
    echo "$TZ" > /etc/timezone && \
    rm -rf /var/lib/apt/lists/*

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

RUN curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/nodesource_setup.sh && \
    bash /tmp/nodesource_setup.sh && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN [ -f /usr/share/keyrings/mongodb-server-8.0.gpg ] && rm -f /usr/share/keyrings/mongodb-server-8.0.gpg; \
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
        gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor && \
    UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble") && \
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/8.0 multiverse" | \
        tee /etc/apt/sources.list.d/mongodb-org-8.0.list && \
    apt-get update && apt-get install -y mongodb-org && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash nodebb && \
    mkdir -p /var/log/mongodb /var/lib/mongodb && \
    chown -R mongodb:mongodb /var/log/mongodb /var/lib/mongodb

RUN git clone -b v4.x https://github.com/NodeBB/NodeBB.git /opt/nodebb

WORKDIR /opt/nodebb

RUN chown -R nodebb:nodebb /opt/nodebb && \
    sudo -u nodebb npm install --production

COPY docker-compose/nodebb/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 4567

ENTRYPOINT ["/entrypoint.sh"]
