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

COPY scripts/pxe-server/ /app/scripts/pxe-server/

# Ensure the cache directory exists and is writable by the entrypoint
RUN mkdir -p /app/scripts/pxe-server/.cache

ENTRYPOINT ["/app/scripts/pxe-server/docker-entrypoint.sh"]
