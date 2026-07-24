# dotfiles-pxe-server render-autoinstall regression test image.
#
# Provides Ubuntu with the runtime deps render-autoinstall.sh needs when
# its code paths are exercised (gettext-base for envsubst, python3+pyyaml for YAML
# validation, openssl for password hashing, curl for potential GitHub key fetch,
# openssh-client for SSH key operations). Does NOT run the imperative PXE
# flow (no dnsmasq, no network boot), so no root/network access is needed
# at test time.
#
# Build context is the repository root:
#   docker build -t dotfiles-pxe-test -f tests/pxe-server/Dockerfile .
#   docker run --rm dotfiles-pxe-test
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y openssh-client gettext-base python3 python3-yaml openssl curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY scripts/bootstrap.sh /work/scripts/bootstrap.sh
COPY scripts/pxe-server/render-autoinstall.sh /work/scripts/pxe-server/render-autoinstall.sh
COPY scripts/pxe-server/templates/ /work/scripts/pxe-server/templates/
COPY tests/pxe-server/test_render_autoinstall.sh /work/tests/pxe-server/test_render_autoinstall.sh

CMD ["/bin/bash", "/work/tests/pxe-server/test_render_autoinstall.sh"]
