# freshell-container

Docker container packaging [Freshell](https://github.com/danshapiro/freshell)
with all supported coding CLI providers and common development tools. Designed as a
persistent, browser-accessible, multi-device development environment.

Based on `node:22-bookworm-slim` (Debian). Alpine was evaluated but `node-pty`
(freshell's terminal spawning library) segfaults on musl libc.

## What's included

**Terminal multiplexer:**
- [Freshell](https://github.com/danshapiro/freshell) — browser-based tabs, panes,
  session persistence, mobile-responsive UI

**Code providers:**
- [Claude Code](https://code.claude.com) (Anthropic) — npm (`@anthropic-ai/claude-code`)*
- [Codex CLI](https://github.com/openai/codex) (OpenAI) — npm
- [OpenCode](https://opencode.ai) (SST) — npm
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) (Google) — npm
- [Kimi CLI](https://github.com/MoonshotAI/kimi-cli) (Moonshot AI) — uv (Python 3.13)

\* Anthropic recommends the native installer over npm for Claude Code. However, the
native installer writes to `~/.local/bin` which conflicts with the persistent
`/home/coder` volume mount, and its auto-updater creates additional conflicts at
runtime. The npm package installs to `/usr/local/bin` and is updated via container
image rebuilds, making it the better fit for Docker environments.

**Shells:** bash (default), zsh, fish, dash — configurable via `FRESHELL_SHELL` env var

**Dev tools:** git, ssh, tmux, ripgrep, jq, curl

## Quick start

```bash
docker run -d \
  --name freshell \
  -p 3001:3001 \
  -e AUTH_TOKEN=$(openssl rand -hex 32) \
  -v freshell-home:/home/coder \
  ghcr.io/nkcx/freshell-container:latest
```

Open `http://localhost:3001` and enter your auth token.

## Docker Compose

See [`docker-compose.yaml`](docker-compose.yaml) for a production-ready compose file.

### Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `AUTH_TOKEN` | Yes | (auto-generated) | Freshell authentication token (min 16 chars) |
| `PORT` | No | `3001` | Freshell listen port |
| `TZ` | No | UTC | Container timezone |
| `FRESHELL_SHELL` | No | `/bin/bash` | Shell for terminal sessions (`/bin/zsh`, `/bin/fish`, `/bin/dash`) |
| `ALLOWED_ORIGINS` | No | (auto-detect LAN) | Comma-separated CORS origins |
| `SKIP_UPDATE_CHECK` | No | `true` | Disable freshell git-based auto-update |
| `CLAUDE_CMD` | No | `claude` | Claude Code binary override |
| `CODEX_CMD` | No | `codex` | Codex CLI binary override |
| `OPENCODE_CMD` | No | `opencode` | OpenCode binary override |
| `GEMINI_CMD` | No | `gemini` | Gemini CLI binary override |
| `KIMI_CMD` | No | `kimi` | Kimi CLI binary override |
| `ANTHROPIC_API_KEY` | No | — | Anthropic API key (or authenticate interactively) |
| `OPENAI_API_KEY` | No | — | OpenAI API key (or authenticate interactively) |
| `GOOGLE_GENERATIVE_AI_API_KEY` | No | — | Gemini API key (also enables AI tab summaries) |

## Persistent data

The `/home/coder` volume persists across container recreations:

- `~/.claude/` — Claude Code credentials and session history
- `~/.codex/` — Codex CLI state
- `~/.freshell/` — Freshell configuration, state, and extensions
- `~/.ssh/` — SSH keys for git operations
- `~/.gitconfig` — Git configuration
- `~/projects/` — Cloned repositories (convention)

## Extensions

Freshell supports extensions in `~/.freshell/extensions/`. This directory is
automatically created on first run. Since it lives inside the persistent home
volume, extensions installed at runtime survive container updates.

To inject extensions from an external volume at startup, mount a read-only volume at
`/extensions`. The entrypoint copies any files found there into `~/.freshell/extensions/`
(without overwriting existing files).

## First-run setup

1. Open the Freshell UI in your browser
2. Open a terminal tab
3. Authenticate your preferred code provider (e.g., `claude` for Claude Code)
4. Set up SSH key for your Git server:
   ```bash
   ssh-keygen -t ed25519 -C "freshell"
   cat ~/.ssh/id_ed25519.pub
   # Add this public key to your Gitea/GitHub account
   ```
5. Configure git identity:
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "you@example.com"
   ```
6. Clone a project and start working:
   ```bash
   cd ~/projects
   git clone git@your-git-server:user/repo.git
   cd repo
   claude  # or codex, opencode, gemini, kimi
   ```

## Building

```bash
# Auto-detect latest freshell release
docker build -t freshell-container .

# Pin to a specific freshell version
docker build --build-arg FRESHELL_VERSION=v0.7.0 -t freshell-container .
```

## Updating

The GitHub Actions workflow rebuilds daily to pick up new freshell releases
and base image security patches. To trigger manually, use the workflow dispatch
button on GitHub.

The `FRESHELL_VERSION` build arg is intentionally unset by default so that
each build auto-detects the latest tagged release from upstream.

## Image size

The image is larger than typical containers (~4GB) due to bundling five code
providers, each with their own dependency trees. The main contributors:

- npm global packages (Codex, Gemini, OpenCode, Claude Code): ~1.2GB
- Freshell + node_modules: ~600MB
- Kimi CLI + Python 3.13 environment: ~200MB
- build-essential (required for node-pty): ~200MB

`build-essential` is retained in the runtime image because freshell's `npm run serve`
triggers a build step that may recompile native modules. If freshell ships prebuilt
binaries or skips recompilation in a future release, this can be removed.

## Multi-device usage

Freshell v0.7.0+ uses per-device tab tracking. Each browser gets a unique device ID
(stored in localStorage), and open terminal tabs are scoped to that device. This is
by design — a tab represents a live terminal session in a specific browser window.

**Coding CLI sessions** (Claude, Codex, etc.) are shared across all devices and
appear in every browser's sidebar. Only the "open tabs" state is per-device.

If you want to see tabs from other devices, the sidebar shows a "remote" section
with tabs open on other connected browsers.

## Known issues

- **Claude Code auto-update** is disabled by using the npm package instead of the
  native installer. Updates come via container image rebuilds.

## License

MIT. Individual code providers are subject to their respective terms of service.
