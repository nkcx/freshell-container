#!/bin/bash
set -eo pipefail

LOG_PREFIX="freshell-container"
PROVIDERS_DIR="/opt/providers"
PROVIDERS_BIN="${PROVIDERS_DIR}/bin"
PROVIDERS_CACHE="${PROVIDERS_DIR}/.cache"
LOCK_FILE="${PROVIDERS_DIR}/.lock"

KNOWN_PROVIDERS="claude codex opencode agy kimi"
VALID_MODES="install uninstall update"

# --- Argument parsing ---

MODES=""
PROVIDERS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --modes)   MODES="$2"; shift 2 ;;
        --providers) PROVIDERS="$2"; shift 2 ;;
        *) echo "[${LOG_PREFIX}] Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# --- Validation ---

IFS=',' read -ra MODE_LIST <<< "$MODES"
for mode in "${MODE_LIST[@]}"; do
    mode=$(echo "$mode" | tr -d '[:space:]')
    if ! echo "$VALID_MODES" | grep -qw "$mode"; then
        echo "[${LOG_PREFIX}] ERROR: Invalid mode '$mode'. Valid modes: $VALID_MODES" >&2
        exit 1
    fi
done

IFS=',' read -ra PROVIDER_LIST <<< "$PROVIDERS"
for provider in "${PROVIDER_LIST[@]}"; do
    provider=$(echo "$provider" | tr -d '[:space:]')
    if [ -n "$provider" ] && ! echo "$KNOWN_PROVIDERS" | grep -qw "$provider"; then
        echo "[${LOG_PREFIX}] ERROR: Unknown provider '$provider'. Known: $KNOWN_PROVIDERS" >&2
        exit 1
    fi
done

# Normalize: trim whitespace from each element
CLEAN_PROVIDERS=()
for p in "${PROVIDER_LIST[@]}"; do
    p=$(echo "$p" | tr -d '[:space:]')
    [ -n "$p" ] && CLEAN_PROVIDERS+=("$p")
done

has_mode() { echo "$MODES" | grep -qw "$1"; }
has_provider() {
    local target="$1"
    for p in "${CLEAN_PROVIDERS[@]}"; do
        [ "$p" = "$target" ] && return 0
    done
    return 1
}

# --- Provider install/uninstall functions ---

install_claude() {
    echo "[${LOG_PREFIX}] Installing Claude Code..."
    NPM_CONFIG_PREFIX="$PROVIDERS_DIR" npm_config_cache="$PROVIDERS_CACHE/npm" \
        npm install -g @anthropic-ai/claude-code 2>&1
}

install_codex() {
    echo "[${LOG_PREFIX}] Installing Codex CLI..."
    NPM_CONFIG_PREFIX="$PROVIDERS_DIR" npm_config_cache="$PROVIDERS_CACHE/npm" \
        npm install -g @openai/codex 2>&1
}

install_opencode() {
    echo "[${LOG_PREFIX}] Installing OpenCode..."
    NPM_CONFIG_PREFIX="$PROVIDERS_DIR" npm_config_cache="$PROVIDERS_CACHE/npm" \
        npm install -g opencode-ai 2>&1
}

install_agy() {
    echo "[${LOG_PREFIX}] Installing Antigravity CLI..."
    curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir "$PROVIDERS_BIN" 2>&1
}

install_kimi() {
    echo "[${LOG_PREFIX}] Installing Kimi CLI..."
    UV_TOOL_BIN_DIR="$PROVIDERS_BIN" UV_TOOL_DIR="${PROVIDERS_DIR}/uv-tools" \
    UV_CACHE_DIR="$PROVIDERS_CACHE/uv" \
        uv tool install kimi-cli --python 3.13 2>&1
}

uninstall_claude() {
    echo "[${LOG_PREFIX}] Uninstalling Claude Code..."
    NPM_CONFIG_PREFIX="$PROVIDERS_DIR" npm uninstall -g @anthropic-ai/claude-code 2>&1 || true
}

uninstall_codex() {
    echo "[${LOG_PREFIX}] Uninstalling Codex CLI..."
    NPM_CONFIG_PREFIX="$PROVIDERS_DIR" npm uninstall -g @openai/codex 2>&1 || true
}

uninstall_opencode() {
    echo "[${LOG_PREFIX}] Uninstalling OpenCode..."
    NPM_CONFIG_PREFIX="$PROVIDERS_DIR" npm uninstall -g opencode-ai 2>&1 || true
}

uninstall_agy() {
    echo "[${LOG_PREFIX}] Uninstalling Antigravity CLI..."
    rm -f "${PROVIDERS_BIN}/agy"
}

uninstall_kimi() {
    echo "[${LOG_PREFIX}] Uninstalling Kimi CLI..."
    UV_TOOL_BIN_DIR="$PROVIDERS_BIN" UV_TOOL_DIR="${PROVIDERS_DIR}/uv-tools" \
    UV_CACHE_DIR="$PROVIDERS_CACHE/uv" \
        uv tool uninstall kimi-cli 2>&1 || true
}

# Binary name for each provider
provider_binary() {
    case "$1" in
        claude)   echo "claude" ;;
        codex)    echo "codex" ;;
        opencode) echo "opencode" ;;
        agy)      echo "agy" ;;
        kimi)     echo "kimi" ;;
    esac
}

is_installed() { [ -x "${PROVIDERS_BIN}/$(provider_binary "$1")" ]; }

# --- Main logic (under flock) ---

mkdir -p "$PROVIDERS_BIN" "$PROVIDERS_CACHE"

exec 9>"$LOCK_FILE"
flock 9

FAILURES=0

# Install: add providers in the list that aren't present
if has_mode "install"; then
    for provider in "${CLEAN_PROVIDERS[@]}"; do
        if ! is_installed "$provider"; then
            if ! "install_${provider}"; then
                echo "[${LOG_PREFIX}] WARNING: Failed to install $provider" >&2
                FAILURES=$((FAILURES + 1))
            fi
        fi
    done
fi

# Update: reinstall all listed providers regardless of presence
if has_mode "update"; then
    for provider in "${CLEAN_PROVIDERS[@]}"; do
        if ! "install_${provider}"; then
            echo "[${LOG_PREFIX}] WARNING: Failed to update $provider" >&2
            FAILURES=$((FAILURES + 1))
        fi
    done
fi

# Uninstall: remove providers NOT in the list that ARE present
if has_mode "uninstall"; then
    for known in $KNOWN_PROVIDERS; do
        if is_installed "$known" && ! has_provider "$known"; then
            if ! "uninstall_${known}"; then
                echo "[${LOG_PREFIX}] WARNING: Failed to uninstall $known" >&2
                FAILURES=$((FAILURES + 1))
            fi
        fi
    done
fi

flock -u 9

if [ "$FAILURES" -gt 0 ]; then
    echo "[${LOG_PREFIX}] Provider management completed with $FAILURES failure(s)."
else
    echo "[${LOG_PREFIX}] Provider management completed successfully."
fi
