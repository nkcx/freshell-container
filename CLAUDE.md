# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

freshell-container packages [Freshell](https://github.com/danshapiro/freshell) (a browser-based terminal multiplexer) into a Docker container with five AI coding CLI providers (Claude Code, Codex, Antigravity CLI, OpenCode, Kimi CLI). Available as a **full** image (all providers baked in) or **lite** image (providers installed at runtime). Provides a persistent, browser-accessible dev environment.

## Build & Run

```bash
# Build full variant (default — all providers baked in)
docker build --target full -t freshell-container .

# Build lite variant (no providers, managed at runtime)
docker build --target lite -t freshell-container:lite .

# Build with pinned Freshell version
docker build --target full --build-arg FRESHELL_VERSION=v0.7.0 -t freshell-container .

# Run with docker-compose (set AUTH_TOKEN in environment first)
docker compose up -d
```

There are no tests, linting, or local dev scripts — this is a Docker-only project.

## Architecture

**Multi-stage Dockerfile** with three targets:
- **build**: Fetches Freshell source from GitHub, runs `npm ci && npm run build`
- **runtime-base**: Debian bookworm-slim + Node 22, dev tools, supercronic, uv, user setup, `/opt/providers` directory, `/etc/profile.d/providers-path.sh`
- **full** (extends runtime-base): Installs all five AI CLI providers to `/usr/local`
- **lite** (extends runtime-base): No providers — they are managed at runtime via `manage-providers.sh`

CI builds both targets with `--target full` and `--target lite`.

**Why Debian, not Alpine**: node-pty (Freshell's terminal library) segfaults on musl/Alpine.

**entrypoint.sh** handles:
- First-run initialization: seeds `/home/coder` with skel files, SSH dir, projects dir
- **Lite variant**: runs `manage-providers.sh` to reconcile providers based on `PROVIDERS` and `MANAGE_PROVIDERS` env vars
- Pre-creates `~/.freshell/config.json` with remote access enabled; lite variant dynamically sets `enabledProviders` from `PROVIDERS`; subsequent boots update the config to match
- Sets up `UPDATE_CRON` via supercronic for scheduled provider updates (lite only)
- Copies extension files from `/extensions` volume mount if present

**manage-providers.sh** handles provider lifecycle for the lite variant:
- Installs/uninstalls/updates providers in `/opt/providers`
- Uses flock for concurrent access protection
- Validates provider names and modes against allowlists
- Isolates npm/uv caches to `/opt/providers/.cache`

**Persistence**: Two Docker volumes:
- `/home/coder` — user data (credentials, configs, repos, shell history)
- `/opt/providers` (lite only) — installed provider binaries and dependencies

**CI/CD** (`.github/workflows/build-image.yaml`): Builds and pushes to GHCR on push/PR/daily schedule. Matrix covers channel (stable/rc) × variant (full/lite). Tags include `latest`, `rc`, `lite`, `lite-rc`, freshell version tags (e.g., `v0.7.5`, `lite-v0.7.5`), and SHA-pinned tags.

## Key Design Decisions

- Runs as non-root `coder` user (UID 1000); the default `node` user is removed and recreated
- Full image: npm-based AI CLIs install globally to `/usr/local`; Python-based kimi-cli uses `uv tool install`
- Lite image: providers install to `/opt/providers` (separate volume from user data)
- Freshell config is pre-seeded only on first run (won't overwrite existing config in persistent volume)
- `AUTH_TOKEN` env var is required for web UI access (min 16 chars)
- `MANAGE_PROVIDERS` defaults to `install,uninstall,update` for full lifecycle management on every boot
- `PROVIDERS` unset vs empty: unset skips management, empty string with `uninstall` mode removes all providers
