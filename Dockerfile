# --- Build stage ---
FROM node:22-bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    git python3 build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Freshell version — CI resolves stable vs RC from the GitHub Releases API.
# When unset, falls back to the highest semver tag (which may be a prerelease).
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

# --- Shared runtime base ---
FROM node:22-bookworm-slim AS runtime-base

# Runtime dependencies (build-essential needed for node-pty native module)
# Shells: bash (default), zsh, fish, dash (configurable via FRESHELL_SHELL env var)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential python3 python3-dev python3-venv python3-pip \
    git openssh-client tmux ripgrep jq curl wget ca-certificates \
    bash zsh fish dash \
    iputils-ping dnsutils traceroute netcat-openbsd \
    lsof htop less file tree unzip vim-tiny nano \
    rsync gnupg sqlite3 postgresql-client mariadb-client bash-completion \
    && rm -rf /var/lib/apt/lists/*

# Install gh (GitHub CLI) and docker-ce-cli from their official apt repos.
# docker-ce-cli only — no daemon. Users who want Docker support mount the
# host's /var/run/docker.sock (see README for security caveats).
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
       -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
       gh docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# yq (Go version, mikefarah/yq) — YAML/JSON/XML processor.
ARG YQ_VERSION=v4.44.3
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_$(dpkg --print-architecture)" \
      -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# supercronic — cron for containers (single static binary, runs as non-root).
ARG SUPERCRONIC_VERSION=v0.2.33
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-${ARCH}" \
       -o /usr/local/bin/supercronic \
    && chmod +x /usr/local/bin/supercronic

# uv (Python package manager) — needed by both variants for kimi-cli support.
RUN pip install --break-system-packages uv \
    && rm -rf /root/.cache/pip

# Replace the built-in 'node' user with our own at UID 1000
RUN userdel -r node \
    && groupadd -g 1000 coder \
    && useradd -m -u 1000 -g coder -s /bin/bash coder

# Copy freshell from build stage
COPY --from=build /opt/freshell /opt/freshell
RUN chown -R coder:coder /opt/freshell

# Install entrypoint and provider management scripts
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY manage-providers.sh /usr/local/bin/manage-providers.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/manage-providers.sh

# Provider volume directory (used by lite variant, harmless for full)
RUN mkdir -p /opt/providers/bin && chown -R coder:coder /opt/providers

# Add /opt/providers/bin to PATH for all shells via profile.d
RUN echo 'export PATH="/opt/providers/bin:$PATH"' > /etc/profile.d/providers-path.sh \
    && chmod +x /etc/profile.d/providers-path.sh

# --- Cleanup build dependencies not needed at runtime ---
# node-pty requires build-essential to compile, but only during npm install/rebuild.
# However, freshell's npm serve rebuilds on startup, so we must keep build-essential.
# TODO: If freshell ships prebuilt node-pty or skips rebuild, remove build-essential here:
# RUN apt-get purge -y --auto-remove build-essential && rm -rf /var/lib/apt/lists/*

# --- Full variant (providers baked in) ---
FROM runtime-base AS full

# Cache-bust: changing this arg forces Docker to re-run all provider installs,
# ensuring daily builds pick up the latest versions from npm/PyPI.
ARG CACHE_BUST=""

# npm-based providers (install to /usr/local)
RUN echo "cache-bust: ${CACHE_BUST}" && npm install -g @openai/codex \
    && npm install -g @anthropic-ai/claude-code \
    && npm install -g opencode-ai \
    && npm cache clean --force

# Antigravity CLI (Google, Go binary — `agy` command)
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir /usr/local/bin

# Kimi CLI (Python-based)
# UV_TOOL_BIN_DIR puts executables in /usr/local/bin instead of ~/.local/bin
# UV_TOOL_DIR stores the venv in a system-wide location (survives volume mount over /home/coder)
RUN UV_TOOL_BIN_DIR=/usr/local/bin UV_TOOL_DIR=/opt/uv-tools \
       uv tool install kimi-cli --python 3.13 \
    && rm -rf /root/.cache/uv

USER coder
WORKDIR /home/coder

RUN git config --global init.defaultBranch main \
    && git config --global pull.rebase false

ENV SHELL=/bin/bash
ENV FRESHELL_VARIANT=full
ENV PATH="/opt/providers/bin:${PATH}"
ENV PORT=3001
ENV NODE_ENV=production
ENV SKIP_UPDATE_CHECK=true
ENV FRESHELL_ALLOW_NON_MAIN_SERVE=1

WORKDIR /opt/freshell
EXPOSE 3001

# Freshell's provider is still named "gemini" upstream; point it at Antigravity.
ENV GEMINI_CMD=agy

# Persistent home: Claude/Codex/Antigravity/Kimi/OpenCode credentials,
# freshell state, SSH keys, git config, project repos, shell history
VOLUME ["/home/coder"]

ENTRYPOINT ["entrypoint.sh"]
CMD ["npm", "run", "serve"]

# --- Lite variant (no providers baked in) ---
FROM runtime-base AS lite

USER coder
WORKDIR /home/coder

RUN git config --global init.defaultBranch main \
    && git config --global pull.rebase false

ENV SHELL=/bin/bash
ENV FRESHELL_VARIANT=lite
ENV PATH="/opt/providers/bin:${PATH}"
ENV PORT=3001
ENV NODE_ENV=production
ENV SKIP_UPDATE_CHECK=true
ENV FRESHELL_ALLOW_NON_MAIN_SERVE=1

WORKDIR /opt/freshell
EXPOSE 3001

ENV GEMINI_CMD=agy

VOLUME ["/home/coder"]

ENTRYPOINT ["entrypoint.sh"]
CMD ["npm", "run", "serve"]
