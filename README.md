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
- [Claude Code](https://code.claude.com) (Anthropic) — native installer
- [Codex CLI](https://github.com/openai/codex) (OpenAI) — npm
- [OpenCode](https://opencode.ai) (SST) — native installer
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) (Google) — npm
- [Kimi CLI](https://github.com/MoonshotAI/kimi-cli) (Moonshot AI) — native installer

**Dev tools:** git, ssh, tmux, ripgrep, jq, curl, bash

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

Freshell supports extensions in `~/.freshell/extensions/`. Since this path lives inside
the persistent home volume, extensions installed at runtime survive container updates.

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
docker build --build-arg FRESHELL_VERSION=v0.6.0 -t freshell-container .
```

## Updating

The GitHub Actions workflow rebuilds weekly to pick up new freshell releases
and base image security patches. To trigger manually, use the workflow dispatch
button on GitHub.

The `FRESHELL_VERSION` build arg is intentionally unset by default so that
each build auto-detects the latest tagged release from upstream.

## License

MIT. Individual code providers are subject to their respective terms of service.
