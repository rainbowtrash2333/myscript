FROM ubuntu:24.04

ENV NODE_ENV=production \
    DAEMON=false \
    SILENT=false

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        git \
        tini \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/nodesource_setup.sh \
    && bash /tmp/nodesource_setup.sh \
    && apt-get install -y nodejs \
    && rm /tmp/nodesource_setup.sh \
    && rm -rf /var/lib/apt/lists/*

RUN node -v && npm -v && git --version

RUN groupadd -r nodebb && useradd -r -g nodebb -m -d /home/nodebb nodebb

WORKDIR /app

RUN git clone -b v4.x https://github.com/NodeBB/NodeBB.git /app/nodebb

RUN chown -R nodebb:nodebb /app

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER nodebb

WORKDIR /app/nodebb

RUN cp install/package.json package.json

RUN npm install --omit=dev

EXPOSE 4567

VOLUME ["/app/nodebb"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
