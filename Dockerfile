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

# Runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential python3 \
    git openssh-client tmux ripgrep jq curl ca-certificates \
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

# npm-based providers (install to /usr/local)
RUN npm install -g @openai/codex \
    && npm install -g @google/gemini-cli \
    && npm install -g @anthropic-ai/claude-code \
    && npm install -g opencode-ai

# Claude Code native installer (preferred over npm, installs to /usr/local/bin)
# Uncomment the line below and remove @anthropic-ai/claude-code from npm if native works:
# RUN curl -fsSL https://claude.ai/install.sh | bash

# Kimi CLI (Python-based, requires newer Python than system default)
# Install as root; uv manages its own Python 3.13 for kimi-cli compatibility.
# Symlink the binary to /usr/local/bin so it's available to all users.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --break-system-packages uv \
    && uv tool install kimi-cli --python 3.13 \
    && ln -sf /root/.local/bin/kimi /usr/local/bin/kimi \
    && ln -sf /root/.local/bin/kimi-cli /usr/local/bin/kimi-cli

# --- Switch to non-root user for runtime ---
USER coder
WORKDIR /home/coder

# Git defaults (overridable from persistent volume)
RUN git config --global init.defaultBranch main \
    && git config --global pull.rebase false

# Set SHELL explicitly for freshell's PTY spawning
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
