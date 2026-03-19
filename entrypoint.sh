#!/bin/bash
set -e

LOG_PREFIX="freshell-container"
FRESHELL_DIR="/opt/freshell"
HOME_DIR="/home/coder"
EXTENSIONS_IMPORT="/extensions"
EXTENSIONS_TARGET="${HOME_DIR}/.freshell/extensions"
FRESHELL_CONFIG="${HOME_DIR}/.freshell/config.json"

# --- First-run initialization ---
# When the /home/coder volume is empty (first deploy), seed it with
# the defaults baked into the image. On subsequent starts, the volume
# already has the user's data and this is a no-op.

if [ ! -f "${HOME_DIR}/.bashrc" ]; then
    echo "[${LOG_PREFIX}] First run detected — initializing home directory..."
    cp /etc/skel/.bashrc "${HOME_DIR}/.bashrc" 2>/dev/null || true
    cp /etc/skel/.profile "${HOME_DIR}/.profile" 2>/dev/null || true
fi

# Ensure SSH directory exists with correct permissions
mkdir -p "${HOME_DIR}/.ssh"
chmod 700 "${HOME_DIR}/.ssh"

# Ensure projects directory exists as a convention
mkdir -p "${HOME_DIR}/projects"

# --- Pre-seed freshell config for remote access ---
# Freshell binds to 127.0.0.1 until the setup wizard sets
# network.host to 0.0.0.0 and network.configured to true in config.json.
# In a container, we pre-seed this so the UI is immediately accessible.

if [ ! -f "${FRESHELL_CONFIG}" ]; then
    echo "[${LOG_PREFIX}] Creating freshell config with remote access enabled..."
    mkdir -p "${HOME_DIR}/.freshell"
    cat > "${FRESHELL_CONFIG}" <<'CONFIGEOF'
{
  "version": 1,
  "settings": {
    "theme": "system",
    "uiScale": 1,
    "terminal": {
      "fontSize": 16,
      "lineHeight": 1,
      "cursorBlink": true,
      "scrollback": 5000,
      "theme": "auto",
      "warnExternalLinks": true,
      "osc52Clipboard": "ask",
      "renderer": "auto"
    },
    "logging": {
      "debug": false
    },
    "safety": {
      "autoKillIdleMinutes": 180
    },
    "notifications": {
      "soundEnabled": true
    },
    "panes": {
      "defaultNewPane": "ask",
      "iconsOnTabs": true,
      "snapThreshold": 2,
      "tabAttentionStyle": "highlight",
      "attentionDismiss": "click"
    },
    "sidebar": {
      "sortMode": "activity",
      "showProjectBadges": true,
      "showSubagents": false,
      "showNoninteractiveSessions": false,
      "hideEmptySessions": true,
      "excludeFirstChatSubstrings": [],
      "excludeFirstChatMustStart": false,
      "width": 288,
      "collapsed": false
    },
    "codingCli": {
      "enabledProviders": [
        "claude",
        "codex",
        "opencode",
        "gemini",
        "kimi"
      ],
      "providers": {
        "claude": {
          "permissionMode": "default"
        },
        "codex": {},
        "opencode": {},
        "gemini": {},
        "kimi": {}
      }
    },
    "editor": {
      "externalEditor": "auto"
    },
    "agentChat": {
      "providers": {}
    },
    "network": {
      "host": "0.0.0.0",
      "configured": true
    }
  },
  "sessionOverrides": {},
  "terminalOverrides": {},
  "projectColors": {},
  "recentDirectories": []
}
CONFIGEOF
    echo "[${LOG_PREFIX}] Config created — remote access enabled, all providers active."
fi

# --- Extension volume support ---
# If an /extensions volume is mounted, copy its contents into the
# freshell extensions directory. This allows injecting extensions
# without conflicting with freshell's own extension management.

if [ -d "${EXTENSIONS_IMPORT}" ] && [ "$(ls -A ${EXTENSIONS_IMPORT} 2>/dev/null)" ]; then
    echo "[${LOG_PREFIX}] Importing extensions from ${EXTENSIONS_IMPORT}..."
    mkdir -p "${EXTENSIONS_TARGET}"
    cp -rn "${EXTENSIONS_IMPORT}/"* "${EXTENSIONS_TARGET}/" 2>/dev/null || true
fi

# --- Hand off to CMD ---
exec "$@"
