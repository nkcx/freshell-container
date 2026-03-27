# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

freshell-container packages [Freshell](https://github.com/danshapiro/freshell) (a browser-based terminal multiplexer) into a Docker container with five pre-installed AI coding CLI providers (Claude Code, Codex, Gemini CLI, OpenCode, Kimi CLI). It provides a persistent, browser-accessible dev environment.

## Build & Run

```bash
# Build container (auto-detects latest Freshell release)
docker build -t freshell-container .

# Build with pinned Freshell version
docker build --build-arg FRESHELL_VERSION=v0.7.0 -t freshell-container .

# Run with docker-compose (set AUTH_TOKEN in environment first)
docker compose up -d
```

There are no tests, linting, or local dev scripts — this is a Docker-only project.

## Architecture

**Multi-stage Dockerfile** is the core of the project:
- **Build stage**: Fetches Freshell source from GitHub, runs `npm ci && npm run build`
- **Runtime stage**: Debian bookworm-slim + Node 22, installs dev tools and AI CLI providers

**Why Debian, not Alpine**: node-pty (Freshell's terminal library) segfaults on musl/Alpine.

**entrypoint.sh** handles first-run initialization:
- Seeds `/home/coder` with skel files, SSH dir, projects dir
- Pre-creates `~/.freshell/config.json` with remote access enabled and all providers on
- Copies extension files from `/extensions` volume mount if present

**Persistence**: Single Docker volume at `/home/coder` holds all state (credentials, configs, repos, shell history). Container is stateless otherwise.

**CI/CD** (`.github/workflows/build-image.yaml`): Builds and pushes to GHCR on push/tag/PR/daily schedule. `FRESHELL_VERSION` is intentionally unset so each build picks up the latest upstream release.

## Key Design Decisions

- Runs as non-root `coder` user (UID 1000); the default `node` user is removed and recreated
- npm-based AI CLIs install globally to `/usr/local`; Python-based kimi-cli uses `uv tool install`
- Freshell config is pre-seeded only on first run (won't overwrite existing config in persistent volume)
- `AUTH_TOKEN` env var is required for web UI access (min 16 chars)
