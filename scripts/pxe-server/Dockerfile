# PXE server container for Ubuntu Server autoinstall
# Usage: docker compose -f scripts/pxe-server/compose.yaml up --build
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dnsmasq \
        gettext-base \
        iproute2 \
        openssh-client \
        openssl \
        python3 \
        python3-yaml && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY scripts/bootstrap.sh /app/scripts/bootstrap.sh
COPY scripts/pxe-server/ /app/scripts/pxe-server/

RUN mkdir -p /app/scripts/pxe-server/.cache && \
    chmod +x /app/scripts/pxe-server/docker-entrypoint.sh \
        /app/scripts/pxe-server/gen-password-hash.sh

ENTRYPOINT ["/app/scripts/pxe-server/docker-entrypoint.sh"]
