# dotfiles-bootstrap authorized_keys merge test image.
#
# Provides a clean Ubuntu environment with ssh-keygen (openssh-client) so the
# focused regression tests can source scripts/bootstrap.sh and exercise the
# authorized_keys merge functions. The tests do NOT run the imperative
# bootstrap flow (no apt/systemd/user creation), so root/openssh-server are
# not required at test time.
#
# Build context is the repository root:
#   docker build -t dotfiles-bootstrap-test -f tests/bootstrap/Dockerfile .
#   docker run --rm dotfiles-bootstrap-test
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y openssh-client && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY scripts/bootstrap.sh /work/scripts/bootstrap.sh
COPY tests/bootstrap/test_bootstrap.sh /work/tests/bootstrap/test_bootstrap.sh

CMD ["/bin/bash", "/work/tests/bootstrap/test_bootstrap.sh"]
