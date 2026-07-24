# dotfiles-pxe-server render-autoinstall regression test image.
#
# Provides Ubuntu with the runtime deps render-autoinstall.sh needs at
# source-time (gettext-base for envsubst, python3+pyyaml for YAML
# validation, openssl for password hashing, openssh-client because
# bootstrap.sh is sourced transitively). Does NOT run the imperative PXE
# flow (no dnsmasq, no network boot), so no root/network access is needed
# at test time beyond what curl needs for the (network-dependent) GitHub
# key fetch test cases, which use an empty github_user to skip fetching.
#
# Build context is the repository root:
#   docker build -t dotfiles-pxe-test -f tests/pxe-server/Dockerfile .
#   docker run --rm dotfiles-pxe-test
#
# NOTE: This test image intentionally runs as root because it is a throw-away
# regression-test container that never leaves the CI runner. No interactive
# shell or exposed service is started.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl gettext-base openssh-client openssl python3 python3-yaml && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY scripts/bootstrap.sh /work/scripts/bootstrap.sh
COPY scripts/pxe-server/render-autoinstall.sh /work/scripts/pxe-server/render-autoinstall.sh
COPY scripts/pxe-server/templates/ /work/scripts/pxe-server/templates/
COPY tests/pxe-server/test_render_autoinstall.sh /work/tests/pxe-server/test_render_autoinstall.sh

CMD ["/bin/bash", "/work/tests/pxe-server/test_render_autoinstall.sh"]
