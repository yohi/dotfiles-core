FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl openssh-server sudo && \
    rm -rf /var/lib/apt/lists/*

# GitHub の鍵取得を模倣するローカル fixture を用意
# 注意: SSH 鍵はコンテナ起動時 (CMD) に生成し、イメージレイヤーには保存しない
RUN mkdir -p /tmp/testbin && \
    printf '%s\n' \
      '#!/bin/sh' \
      'cat /tmp/testkeys/authorized_keys' > /tmp/testbin/curl && \
    chmod 0755 /tmp/testbin/curl

# bootstrap.sh が外部 GitHub ではなく fixture を取得するようにする
ENV PATH="/tmp/testbin:${PATH}"

COPY scripts/bootstrap.sh /tmp/bootstrap.sh
COPY tests/bootstrap/test_bootstrap.sh /tmp/test_bootstrap.sh

# 実機では systemd の ssh.service (RuntimeDirectory=sshd) が /run/sshd を作成するが、
# systemd の無いこのコンテナでは作成されないため、テスト実行前に用意する
CMD ["/bin/bash", "-c", "mkdir -p /run/sshd /tmp/testkeys && ssh-keygen -t ed25519 -f /tmp/testkeys/id_ed25519 -N '' -q && cp /tmp/testkeys/id_ed25519.pub /tmp/testkeys/authorized_keys && bash /tmp/bootstrap.sh && bash /tmp/test_bootstrap.sh"]
