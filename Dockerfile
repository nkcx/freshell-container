# --- Build stage ---
FROM node:22-bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3 build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Fetch the latest freshell release tag dynamically, or pin via build arg
ARG FRESHELL_VERSION=""
WORKDIR /opt/freshell
RUN if [ -n "${FRESHELL_VERSION}" ]; then \
      echo "Using pinned freshell version: ${FRESHELL_VERSION}"; \
      git clone --branch "${FRESHELL_VERSION}" --depth 1 \
        https://github.com/danshapiro/freshell.git .; \
    else \
      LATEST_TAG=v$(git ls-remote --tags \
        https://github.com/danshapiro/freshell.git 'refs/tags/v*' \
        | sed 's|.*refs/tags/||' \
        | grep -v '\^{}' \
        | sed 's/^v//' \
        | sort -t. -k1,1n -k2,2n -k3,3n \
        | tail -n1); \
      echo "Detected latest freshell release: ${LATEST_TAG}"; \
      git clone --branch "${LATEST_TAG}" --depth 1 \
        https://github.com/danshapiro/freshell.git .; \
    fi \
    && npm ci \
    && npm run build

# --- Runtime stage ---
FROM node:22-bookworm-slim

# Runtime dependencies (build-essential needed for node-pty native module)
# Shells: bash (default), zsh, fish, dash (configurable via FRESHELL_SHELL env var)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential python3 \
    git openssh-client tmux ripgrep jq curl wget ca-certificates \
    bash zsh fish dash \
    iputils-ping dnsutils traceroute netcat-openbsd \
    lsof htop less file tree unzip vim-tiny nano \
    && rm -rf /var/lib/apt/lists/*

# Replace the built-in 'node' user with our own at UID 1000
# (node user is not a dependency — see nodejs/docker-node best practices)
RUN userdel -r node \
    && groupadd -g 1000 coder \
    && useradd -m -u 1000 -g coder -s /bin/bash coder

# Copy freshell from build stage
COPY --from=build /opt/freshell /opt/freshell
RUN chown -R coder:coder /opt/freshell

# Install entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# --- Install code providers as root ---

# Cache-bust: changing this arg forces Docker to re-run all provider installs,
# ensuring daily builds pick up the latest versions from npm/PyPI.
ARG CACHE_BUST=""

# npm-based providers (install to /usr/local)
# Note: @anthropic-ai/claude-code is deprecated but is the most reliable method
# for Docker containers. The native installer writes to ~/.local which conflicts
# with the persistent /home/coder volume mount and has auto-update issues.
RUN echo "cache-bust: ${CACHE_BUST}" && npm install -g @openai/codex \
    && npm install -g @google/gemini-cli \
    && npm install -g @anthropic-ai/claude-code \
    && npm install -g opencode-ai \
    && npm cache clean --force

# Kimi CLI (Python-based, requires newer Python than system default)
# UV_TOOL_BIN_DIR puts executables in /usr/local/bin instead of ~/.local/bin
# UV_TOOL_DIR stores the venv in a system-wide location (survives volume mount over /home/coder)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --break-system-packages uv \
    && UV_TOOL_BIN_DIR=/usr/local/bin UV_TOOL_DIR=/opt/uv-tools \
       uv tool install kimi-cli --python 3.13 \
    && rm -rf /root/.cache/uv /root/.cache/pip

# --- Cleanup build dependencies not needed at runtime ---
# node-pty requires build-essential to compile, but only during npm install/rebuild.
# However, freshell's npm serve rebuilds on startup, so we must keep build-essential.
# TODO: If freshell ships prebuilt node-pty or skips rebuild, remove build-essential here:
# RUN apt-get purge -y --auto-remove build-essential && rm -rf /var/lib/apt/lists/*

# --- Switch to non-root user for runtime ---
USER coder
WORKDIR /home/coder

# Git defaults (overridable from persistent volume)
RUN git config --global init.defaultBranch main \
    && git config --global pull.rebase false

# Default shell for freshell PTY spawning (overridable via FRESHELL_SHELL env var)
ENV SHELL=/bin/bash

# --- Freshell configuration (overridable at runtime) ---
ENV PORT=3001
ENV NODE_ENV=production
ENV SKIP_UPDATE_CHECK=true

WORKDIR /opt/freshell
EXPOSE 3001

# Persistent home: Claude/Codex/Gemini/Kimi/OpenCode credentials,
# freshell state, SSH keys, git config, project repos, shell history
VOLUME ["/home/coder"]

ENTRYPOINT ["entrypoint.sh"]
CMD ["npm", "run", "serve"]
