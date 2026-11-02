FROM debian:trixie-slim

# Build-time only (ARG, not ENV): no interactive apt prompts during the build.
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    nodejs \
    npm \
    git \
    git-lfs \
    curl \
    ca-certificates \
    gpg \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    fd-find \
    jq \
    openssh-client \
    sudo \
    vim \
    bash \
    tzdata \
    g++ \
    shellcheck \
    iputils-ping \
    socat \
    rsync \
    git-delta \
    && git lfs install --system \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
# add more dependencies above if needed

# delta as git pager, system-wide. Appended: /etc/gitconfig already holds the
# git-lfs filter. An area's ~/.gitconfig can still override every setting.
# Side by side for one call: git -c delta.side-by-side=true diff
RUN cat >> /etc/gitconfig <<'EOF'
[core]
	pager = delta
[interactive]
	diffFilter = delta --color-only
[delta]
	navigate = true
	line-numbers = true
[merge]
	conflictStyle = zdiff3
EOF

# Docker CLI + buildx/compose plugins from Docker's Debian repository (codename
# read from os-release). Only usable where the socket is mounted (area args or
# --mclaude-docker).
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    . /etc/os-release && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y --no-install-recommends \
      docker-ce-cli docker-buildx-plugin docker-compose-plugin && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create the working user (UID/GID are remapped to the host user at runtime).
RUN useradd -m --shell /bin/bash --home-dir /home/claude claude

# Let claude install packages (apt, pip, ...) without a password prompt.
RUN echo "claude ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/claude && \
    chmod 0440 /etc/sudoers.d/claude
# Versioning: mclaude tracks the Claude Code CLI version it bundles — the VERSION
# file IS the pinned @anthropic-ai/claude-code release. Passed in by `docker buildx
# bake` from that file. Declared here (not earlier) so a version bump reinstalls
# Claude Code + rebuilds the layers below, but keeps the apt layers above cached.
# A `dev` fallback (no version passed) installs the latest release instead.
ARG MCLAUDE_VERSION=dev
RUN if [ "$MCLAUDE_VERSION" = "dev" ]; then \
      npm install -g @anthropic-ai/claude-code; \
    else \
      npm install -g @anthropic-ai/claude-code@"$MCLAUDE_VERSION"; \
    fi && \
    npm cache clean --force && \
    chown -R claude:claude /usr/local/lib/node_modules /usr/local/bin /usr/local/share/man
# ^ Let the claude user manage global npm packages (npm install -g, claude update)
#   without sudo. The chown must stay in the same RUN as the install: in a layer of
#   its own it would copy the whole node_modules tree into the image a second time.

# Satisfy the claude /doctor check which expects claude at ~/.local/bin/claude
RUN mkdir -p /home/claude/.local/bin && \
    ln -s /usr/local/bin/claude /home/claude/.local/bin/claude && \
    chown -R claude:claude /home/claude/.local

ENV PATH="/usr/local/bin:$PATH"
ENV SHELL=/bin/bash

# Expose the bundled Claude Code version both as an env var (readable inside the
# container) and as OCI labels (readable via `docker inspect` / `mclaude
# --mclaude-version`). MCLAUDE_VERSION is already in scope from the ARG above.
ARG BUILD_DATE=unknown
ENV MCLAUDE_VERSION=$MCLAUDE_VERSION
LABEL org.opencontainers.image.title="mclaude" \
      org.opencontainers.image.description="Dockerized Claude Code wrapper" \
      org.opencontainers.image.source="https://github.com/unimock/mclaude" \
      org.opencontainers.image.version="$MCLAUDE_VERSION" \
      org.opencontainers.image.created="$BUILD_DATE"

WORKDIR /src
# Setup (user remapping) is a separate, sourced script so images built FROM
# this one can reuse it with their own command (see README).
COPY mclaude-setup /usr/local/lib/mclaude/setup.sh
COPY claude-wrapper /usr/local/bin/
CMD ["/usr/local/bin/claude-wrapper"]

