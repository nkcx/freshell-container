#!/bin/bash
# Applies the container's Freshell patches selected by FRESHELL_PATCHES.
#
# Upstream Freshell v0.7.x is frozen while it is rewritten, so fixes we need
# are carried here as patches against /opt/freshell. `npm run serve` rebuilds
# Freshell from source on every start, so patching the source before that
# build is enough; no flags need to be plumbed into Freshell itself.
#
# The checkout is reset to its pristine tag first (tracked files restored,
# untracked files removed; ignored dist/ and node_modules/ are kept), so
# turning a patch off and restarting really removes it.
#
# Patches are opt-in. FRESHELL_PATCHES:
#   unset, "" or "none"   apply nothing
#   all                   apply every patch in PATCHES_DIR
#   a,b,c                 apply the named patches (file names without .patch)
#
# A patch that does not apply is skipped with a warning; git apply is atomic,
# so a failed patch leaves no partial changes.
set -uo pipefail

LOG_PREFIX="freshell-container"
FRESHELL_DIR="${FRESHELL_DIR:-/opt/freshell}"
PATCHES_DIR="${PATCHES_DIR:-/opt/freshell-patches}"

if ! git -C "$FRESHELL_DIR" reset --hard -q HEAD || ! git -C "$FRESHELL_DIR" clean -fdq; then
    echo "[${LOG_PREFIX}] WARNING: could not reset ${FRESHELL_DIR}; skipping patches."
    exit 1
fi

SELECTED="${FRESHELL_PATCHES:-}"
if [ "$SELECTED" = "all" ]; then
    SELECTED=$(find "$PATCHES_DIR" -maxdepth 1 -name '*.patch' -printf '%f\n' 2>/dev/null \
        | sed 's/\.patch$//' | sort | paste -sd, -)
fi

if [ -z "${SELECTED// /}" ] || [ "$SELECTED" = "none" ]; then
    echo "[${LOG_PREFIX}] No Freshell patches enabled."
    exit 0
fi

IFS=',' read -ra NAMES <<< "$SELECTED"
for name in "${NAMES[@]}"; do
    name=$(echo "$name" | tr -d '[:space:]')
    [ -z "$name" ] && continue
    patch="${PATCHES_DIR}/${name}.patch"
    if [ ! -f "$patch" ]; then
        echo "[${LOG_PREFIX}] WARNING: unknown Freshell patch '${name}' (available: $(ls "$PATCHES_DIR" 2>/dev/null | sed 's/\.patch$//' | paste -sd' ' -))"
        continue
    fi
    if git -C "$FRESHELL_DIR" apply "$patch"; then
        echo "[${LOG_PREFIX}] Applied Freshell patch: ${name}"
    else
        echo "[${LOG_PREFIX}] WARNING: Freshell patch '${name}' does not apply to $(git -C "$FRESHELL_DIR" describe --tags 2>/dev/null); skipped."
    fi
done
