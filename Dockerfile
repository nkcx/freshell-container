# --- Build stage ---
FROM node:22-alpine AS build

RUN apk add --no-cache git python3 build-base

# Fetch the latest freshell release tag dynamically, or pin via build arg
ARG FRESHELL_VERSION=""
WORKDIR /opt/freshell
RUN if [ -n "${FRESHELL_VERSION}" ]; then \
      echo "Using pinned freshell version: ${FRESHELL_VERSION}"; \
      git clone --branch "${FRESHELL_VERSION}" --depth 1 \
        https://github.com/danshapiro/freshell.git .; \
    else \
      LATEST_TAG=$(git ls-remote --tags --sort=-v:refname \
        https://github.com/danshapiro/freshell.git 'refs/tags/v*' \
        | head -n1 | sed 's|.*refs/tags/||'); \
      echo "Detected latest freshell release: ${LATEST_TAG}"; \
      git clone --branch "${LATEST_TAG}" --depth 1 \
        https://github.com/danshapiro/freshell.git .; \
    fi \
    && npm ci \
    && npm run build

# --- Runtime stage ---
FROM node:22-alpine

# Runtime dependencies:
#   - build-base/python3 for node-pty native module rebuild
#   - bash required by freshell and most CLI tools
#   - dev workflow essentials
RUN apk add --no-cache \
    build-base python3 \
    git openssh-client tmux ripgrep jq curl bash ca-certificates

# Replace Alpine's built-in 'node' user with our own at UID 1000
# (node user is not a dependency — see nodejs/docker-node best practices)
RUN deluser --remove-home node \
    && addgroup -g 1000 coder \
    && adduser -D -u 1000 -G coder -s /bin/bash coder

# Copy freshell from build stage
COPY --from=build /opt/freshell /opt/freshell
RUN chown -R coder:coder /opt/freshell

# Install entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Switch to non-root user for tool installations
USER coder
WORKDIR /home/coder

# --- Code providers ---

# Claude Code (native binary installer)
RUN curl -fsSL https://claude.ai/install.sh | bash

# OpenAI Codex CLI (npm)
RUN npm install -g @openai/codex

# OpenCode (native binary installer)
RUN curl -fsSL https://opencode.ai/install | bash

# Google Gemini CLI (npm)
RUN npm install -g @google/gemini-cli

# Kimi CLI (official installer)
RUN curl -L https://code.kimi.com/install.sh | bash

# --- Defaults ---

# Git defaults (overridable from persistent volume)
RUN git config --global init.defaultBranch main \
    && git config --global pull.rebase false

# Ensure all tool binaries are discoverable
ENV PATH="/home/coder/.local/bin:/home/coder/.npm-global/bin:${PATH}"

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
