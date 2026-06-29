FROM node:24-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/root/.local/bin:/data/.local/bin:/data/.openclaw/bin:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        iproute2 \
        lsof \
        procps \
        python3 \
        python3-venv \
        tar \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && npm install -g openclaw

COPY entrypoint.sh /usr/local/bin/easy-miloco-nas-entrypoint
RUN chmod +x /usr/local/bin/easy-miloco-nas-entrypoint

WORKDIR /data
ENTRYPOINT ["/usr/local/bin/easy-miloco-nas-entrypoint"]
