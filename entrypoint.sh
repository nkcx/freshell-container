#!/bin/bash
set -e

LOG_PREFIX="freshell-container"
FRESHELL_DIR="/opt/freshell"
HOME_DIR="/home/coder"
EXTENSIONS_IMPORT="/extensions"
EXTENSIONS_TARGET="${HOME_DIR}/.freshell/extensions"
FRESHELL_CONFIG="${HOME_DIR}/.freshell/config.json"
VARIANT="${FRESHELL_VARIANT:-full}"

# --- Shell configuration ---
# FRESHELL_SHELL env var lets users choose their preferred shell.
# Validates that the shell exists before applying.
if [ -n "${FRESHELL_SHELL}" ]; then
    if [ -x "${FRESHELL_SHELL}" ]; then
        export SHELL="${FRESHELL_SHELL}"
        echo "[${LOG_PREFIX}] Shell set to ${FRESHELL_SHELL}"
    else
        echo "[${LOG_PREFIX}] WARNING: ${FRESHELL_SHELL} not found or not executable, keeping default (${SHELL})"
    fi
fi

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

# Ensure freshell directories exist
mkdir -p "${HOME_DIR}/.freshell"
mkdir -p "${EXTENSIONS_TARGET}"

# --- Lite variant: provider management ---
if [ "$VARIANT" = "lite" ] && [ "${PROVIDERS+set}" = "set" ]; then
    MODES="${MANAGE_PROVIDERS:-install,uninstall}"
    echo "[${LOG_PREFIX}] Managing providers (modes: ${MODES}, providers: ${PROVIDERS:-<none>})..."
    manage-providers.sh --modes "$MODES" --providers "$PROVIDERS"
fi

# --- Provider name mapping (agy → gemini for Freshell config) ---
map_provider_name() {
    case "$1" in
        agy) echo "gemini" ;;
        *)   echo "$1" ;;
    esac
}

# Build enabledProviders JSON array from PROVIDERS env var
build_enabled_providers() {
    local result="["
    local first=true
    if [ -n "$PROVIDERS" ]; then
        IFS=',' read -ra provs <<< "$PROVIDERS"
        for p in "${provs[@]}"; do
            p=$(echo "$p" | tr -d '[:space:]')
            [ -z "$p" ] && continue
            local mapped
            mapped=$(map_provider_name "$p")
            if [ "$first" = true ]; then
                first=false
            else
                result+=","
            fi
            result+="\"${mapped}\""
        done
    fi
    result+="]"
    echo "$result"
}

# Build providers config object from PROVIDERS env var
build_providers_config() {
    local result="{"
    local first=true
    if [ -n "$PROVIDERS" ]; then
        IFS=',' read -ra provs <<< "$PROVIDERS"
        for p in "${provs[@]}"; do
            p=$(echo "$p" | tr -d '[:space:]')
            [ -z "$p" ] && continue
            local mapped
            mapped=$(map_provider_name "$p")
            if [ "$first" = true ]; then
                first=false
            else
                result+=","
            fi
            if [ "$mapped" = "claude" ]; then
                result+="\"${mapped}\":{\"permissionMode\":\"default\"}"
            else
                result+="\"${mapped}\":{}"
            fi
        done
    fi
    result+="}"
    echo "$result"
}

# --- Pre-seed freshell config for remote access ---
# Freshell binds to 127.0.0.1 until the setup wizard sets
# network.host to 0.0.0.0 and network.configured to true in config.json.
# In a container, we pre-seed this so the UI is immediately accessible.

if [ ! -f "${FRESHELL_CONFIG}" ]; then
    echo "[${LOG_PREFIX}] Creating freshell config with remote access enabled..."

    if [ "$VARIANT" = "lite" ]; then
        ENABLED_PROVIDERS=$(build_enabled_providers)
        PROVIDERS_CONFIG=$(build_providers_config)
    else
        ENABLED_PROVIDERS='["claude","codex","opencode","gemini","kimi"]'
        PROVIDERS_CONFIG='{"claude":{"permissionMode":"default"},"codex":{},"opencode":{},"gemini":{},"kimi":{}}'
    fi

    cat > "${FRESHELL_CONFIG}" <<CONFIGEOF
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
      "enabledProviders": ${ENABLED_PROVIDERS},
      "providers": ${PROVIDERS_CONFIG}
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
    echo "[${LOG_PREFIX}] Config created — remote access enabled."

elif [ "$VARIANT" = "lite" ] && [ "${PROVIDERS+set}" = "set" ]; then
    # Subsequent boot: update enabledProviders to match current PROVIDERS
    ENABLED_PROVIDERS=$(build_enabled_providers)
    TMP_CONFIG="${FRESHELL_CONFIG}.tmp"
    jq --argjson ep "$ENABLED_PROVIDERS" '
      .settings.codingCli.enabledProviders = $ep |
      reduce ($ep[] | tostring) as $p (.;
        if .settings.codingCli.providers[$p] == null then
          .settings.codingCli.providers[$p] = (if $p == "claude" then {"permissionMode":"default"} else {} end)
        else . end
      )
    ' "$FRESHELL_CONFIG" > "$TMP_CONFIG" && mv "$TMP_CONFIG" "$FRESHELL_CONFIG"
    echo "[${LOG_PREFIX}] Updated enabledProviders in config."
fi

# --- Lite variant: UPDATE_CRON ---
if [ "$VARIANT" = "lite" ] && [ -n "${UPDATE_CRON}" ] && [ "${PROVIDERS+set}" = "set" ] && [ -n "$PROVIDERS" ]; then
    CRON_FILE="${HOME_DIR}/.freshell/update-crontab"
    printf '%s /usr/local/bin/manage-providers.sh --modes update --providers %s\n' \
        "$UPDATE_CRON" "$PROVIDERS" > "$CRON_FILE"
    supercronic "$CRON_FILE" &
    echo "[${LOG_PREFIX}] Provider update cron started: ${UPDATE_CRON}"
fi

# --- Extension volume support ---
# If an /extensions volume is mounted, copy its contents into the
# freshell extensions directory. This allows injecting extensions
# without conflicting with freshell's own extension management.

if [ -d "${EXTENSIONS_IMPORT}" ] && [ "$(ls -A ${EXTENSIONS_IMPORT} 2>/dev/null)" ]; then
    echo "[${LOG_PREFIX}] Importing extensions from ${EXTENSIONS_IMPORT}..."
    cp -rn "${EXTENSIONS_IMPORT}/"* "${EXTENSIONS_TARGET}/" 2>/dev/null || true
fi

# --- Hand off to CMD ---
exec "$@"
