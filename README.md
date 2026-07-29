# freshell-container

Docker container packaging [Freshell](https://github.com/danshapiro/freshell)
with all supported coding CLI providers and common development tools. Designed as a
persistent, browser-accessible, multi-device development environment.

Available in two variants: **full** (all providers baked in, ~4GB) and
**lite** (providers installed on first boot, ~2GB).

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
- [Antigravity CLI](https://github.com/google-antigravity/antigravity-cli) (Google) — official installer (`agy` command)
- [Kimi CLI](https://github.com/MoonshotAI/kimi-cli) (Moonshot AI) — uv (Python 3.13)

\* Anthropic recommends the native installer over npm for Claude Code. However, the
native installer writes to `~/.local/bin` which conflicts with the persistent
`/home/coder` volume mount, and its auto-updater creates additional conflicts at
runtime. The npm package installs to `/usr/local/bin` and is updated via container
image rebuilds, making it the better fit for Docker environments.

**Note:** Freshell's provider is still named "gemini" upstream. The `GEMINI_CMD=agy`
env var redirects it to launch Antigravity CLI.

**Shells:** bash (default), zsh, fish, dash — configurable via `FRESHELL_SHELL` env var

**Dev tools:**
- **Version control:** git, gh (GitHub CLI), ssh
- **Editors / pagers:** vim-tiny, nano, less
- **Search / text:** ripgrep, jq, yq, file, tree
- **Transfer:** curl, wget, rsync
- **Networking diagnostics:** ping, dig, traceroute, nc
- **System diagnostics:** lsof, htop, tmux
- **Archives:** tar, gzip, unzip
- **Databases:** sqlite3, psql (postgresql-client), mysql (mariadb-client)
- **Containers:** docker (CLI only — requires socket mount, see below)
- **Misc:** gnupg, bash-completion

## Quick start

### Full image (all providers)

```bash
docker run -d \
  --name freshell \
  -p 3001:3001 \
  -e AUTH_TOKEN=$(openssl rand -hex 32) \
  -v freshell-home:/home/coder \
  ghcr.io/nkcx/freshell-container:latest
```

### Lite image (choose your providers)

```bash
docker run -d \
  --name freshell \
  -p 3001:3001 \
  -e AUTH_TOKEN=$(openssl rand -hex 32) \
  -e PROVIDERS=claude,codex \
  -v freshell-home:/home/coder \
  -v freshell-providers:/opt/providers \
  ghcr.io/nkcx/freshell-container:lite
```

Open `http://localhost:3001` and enter your auth token.

## Lite variant

The `lite` image ships the same base tools as `full` but without any pre-installed
coding CLI providers. Instead, providers are installed at runtime into a separate
`/opt/providers` volume based on the `PROVIDERS` environment variable.

**Advantages:**
- ~2GB smaller image (faster pulls, less storage)
- Install only the providers you need
- Provider updates without rebuilding the container

**Trade-offs:**
- First boot is slower (provider downloads)
- Requires network access on first boot
- Providers live on a separate volume that must be mounted

### Provider management

The `PROVIDERS` env var is a comma-separated list of provider names to install:
`claude`, `codex`, `opencode`, `agy`, `kimi`.

The `MANAGE_PROVIDERS` env var controls what happens at boot (default: `install,uninstall,update`):

| Mode | Behavior |
|---|---|
| `install` | Install providers in `PROVIDERS` that aren't already present |
| `uninstall` | Remove providers NOT in `PROVIDERS` that are present |
| `update` | Update all listed providers to their latest versions |

Examples:
- `MANAGE_PROVIDERS=install` — only add new providers, never remove or update
- `MANAGE_PROVIDERS=install,uninstall` — reconcile to match `PROVIDERS` exactly, no updates
- `MANAGE_PROVIDERS=install,uninstall,update` — (default) full reconcile plus update on every boot

**PROVIDERS semantics:**
- Not set — provider management is skipped entirely
- Empty (`PROVIDERS=""`) — with `uninstall` mode, removes all installed providers
- Non-empty — reconcile against the list

### Auto-updating providers

Set `UPDATE_CRON` to a cron expression to automatically update providers on a schedule:

```bash
-e UPDATE_CRON="0 4 * * *"   # update daily at 4am
```

This runs `manage-providers.sh --modes update` on the specified schedule using
[supercronic](https://github.com/aptible/supercronic).

### Provider volume

The lite variant installs providers to `/opt/providers`, which **must** be mounted as
a separate Docker volume (`-v freshell-providers:/opt/providers`). Without this
mount, providers install into the container's writable layer and are lost on
container recreation. This volume separates provider binaries from user data
(`/home/coder`), allowing you to wipe it for a clean reinstall without losing
credentials, SSH keys, or project files.

## Docker Compose

See [`docker-compose.yaml`](docker-compose.yaml) for production-ready compose files
for both full and lite variants.

### Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `AUTH_TOKEN` | Yes | (auto-generated) | Freshell authentication token (min 16 chars) |
| `PORT` | No | `3001` | Freshell listen port |
| `TZ` | No | UTC | Container timezone |
| `FRESHELL_SHELL` | No | `/bin/bash` | Shell for terminal sessions (`/bin/zsh`, `/bin/fish`, `/bin/dash`) |
| `ALLOWED_ORIGINS` | No | (auto-detect LAN) | Comma-separated CORS origins |
| `SKIP_UPDATE_CHECK` | No | `true` | Disable freshell git-based auto-update |
| `PROVIDERS` | Lite only | — | Comma-separated providers to install: `claude`, `codex`, `opencode`, `agy`, `kimi` |
| `MANAGE_PROVIDERS` | Lite only | `install,uninstall,update` | Provider management modes (see above) |
| `UPDATE_CRON` | Lite only | — | Cron expression for auto-updating providers (e.g., `0 4 * * *`) |
| `CLAUDE_CMD` | No | `claude` | Claude Code binary override |
| `CODEX_CMD` | No | `codex` | Codex CLI binary override |
| `OPENCODE_CMD` | No | `opencode` | OpenCode binary override |
| `GEMINI_CMD` | No | `agy` | Freshell "gemini" provider binary (points to Antigravity CLI) |
| `KIMI_CMD` | No | `kimi` | Kimi CLI binary override |
| `ANTHROPIC_API_KEY` | No | — | Anthropic API key (or authenticate interactively) |
| `OPENAI_API_KEY` | No | — | OpenAI API key (or authenticate interactively) |
| `GOOGLE_GENERATIVE_AI_API_KEY` | No | — | Gemini API key for Freshell AI tab summaries |

## Persistent data

The `/home/coder` volume persists across container recreations:

- `~/.claude/` — Claude Code credentials and session history
- `~/.codex/` — Codex CLI state
- `~/.freshell/` — Freshell configuration, state, and extensions
- `~/.ssh/` — SSH keys for git operations
- `~/.gitconfig` — Git configuration
- `~/projects/` — Cloned repositories (convention)

The `/opt/providers` volume (lite variant only) stores installed provider binaries
and their dependencies.

## Extensions

Freshell supports extensions in `~/.freshell/extensions/`. This directory is
automatically created on first run. Since it lives inside the persistent home
volume, extensions installed at runtime survive container updates.

To inject extensions from an external volume at startup, mount a read-only volume at
`/extensions`. The entrypoint copies any files found there into `~/.freshell/extensions/`
(without overwriting existing files).

## Docker CLI support

The container ships with the Docker CLI but no daemon. To use `docker` commands
from inside the container, mount the host's Docker socket:

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock
```

Or via `docker run`:

```bash
-v /var/run/docker.sock:/var/run/docker.sock
```

You'll also need to grant the `coder` user access to the socket. The simplest
approach is to add a supplementary group matching the host's `docker` group GID:

```yaml
user: "1000:1000"
group_add:
  - "${DOCKER_GID}"   # host's `getent group docker | cut -d: -f3`
```

### Security warning

**Mounting the Docker socket gives this container root-equivalent access to the
host.** Anything running inside — including any AI coding agent you grant
permissions to — can:

- Start privileged containers that bypass all isolation
- Mount any host filesystem path and read/write arbitrary files
- Access other containers' data, networks, and secrets
- Effectively become root on the host machine

Only enable this if you fully trust everything running inside the container,
including the AI agents. In a single-user homelab this may be an acceptable
trade-off; in a shared or production environment it almost certainly is not.

Alternatives to consider:
- **Remote Docker context**: configure `DOCKER_HOST` to point at a TCP socket
  with TLS client certificates — more access control, but more setup
- **Rootless Docker/Podman on the host**: keeps socket access from escalating
  to host root, though containers can still interfere with each other
- **Skip container support entirely**: manage host containers from the host

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
   claude  # or codex, opencode, agy, kimi
   ```

## Building

```bash
# Full variant (default) — all providers baked in
docker build --target full -t freshell-container .

# Lite variant — no providers, managed at runtime
docker build --target lite -t freshell-container:lite .

# Pin to a specific freshell version
docker build --target full --build-arg FRESHELL_VERSION=v0.7.0 -t freshell-container .
```

## Image tags

| Tag | Freshell version | Description |
|---|---|---|
| `latest` | Latest stable release | Full image; production-ready; updated daily |
| `rc` | Latest release candidate | Full image; pre-release; updated daily when an RC exists |
| `lite` | Latest stable release | Lite image; providers installed at runtime |
| `lite-rc` | Latest release candidate | Lite pre-release |
| `v0.7.5` | Pinned to Freshell v0.7.5 | Full image tracking a specific upstream release |
| `lite-v0.7.5` | Pinned to Freshell v0.7.5 | Lite image tracking a specific upstream release |
| `sha-abc1234` | Pinned to commit | Full image from a specific container commit |

When no release candidate exists (or the latest stable is newer than the latest RC),
`rc` points at the same image as `latest`, and `lite-rc` points at the same image
as `lite`.

## Updating

The GitHub Actions workflow rebuilds daily to pick up new freshell releases
and base image security patches. Both `latest` (stable) and `rc` (release
candidate) tags are rebuilt on every run, along with their lite counterparts.
To trigger manually, use the workflow dispatch button on GitHub.

Freshell versions are resolved automatically from the upstream GitHub Releases
API — stable releases go to `latest`/`lite`, prereleases go to `rc`/`lite-rc`.

## Image size

The **full** image is larger than typical containers (~4GB) due to bundling five
code providers, each with their own dependency trees. The main contributors:

- npm global packages (Codex, OpenCode, Claude Code): ~1GB
- Antigravity CLI (Go binary): ~50MB
- Freshell + node_modules: ~600MB
- Kimi CLI + Python 3.13 environment: ~200MB
- build-essential (required for node-pty): ~200MB

The **lite** image is ~2GB — the same base without pre-installed providers.
Providers are downloaded on first boot and stored on the provider volume.

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
  native installer. Updates come via container image rebuilds (full) or
  `UPDATE_CRON` / manual `manage-providers.sh --modes update` (lite).

## License

MIT. Individual code providers are subject to their respective terms of service.
