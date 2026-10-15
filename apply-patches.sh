#!/bin/bash
# Applies the container's Freshell patches selected by FRESHELL_PATCHES.
#
# Upstream Freshell v0.7.x is frozen while it is rewritten, so fixes we need
# are carried here as patches against /opt/freshell. `npm run serve` rebuilds
# Freshell from source on every start, so patching the source before that
# build is enough; no flags need to be plumbed into Freshell itself.
#
# Patches live in PATCHES_DIR/<freshell tag>/ (e.g. v0.7.5/convert-eol.patch),
# since the stable and rc images package different Freshell versions. Only the
# directory matching the checkout's tag is used.
#
# The checkout is reset to its pristine tag first (tracked files restored,
# untracked files removed; ignored dist/ and node_modules/ are kept), so
# turning a patch off and restarting really removes it.
#
# Patches are opt-in. FRESHELL_PATCHES:
#   unset, "" or "none"   apply nothing
#   all                   apply every patch available for this Freshell version
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

VERSION=$(git -C "$FRESHELL_DIR" describe --tags --exact-match 2>/dev/null || echo unknown)
VERSION_DIR="${PATCHES_DIR}/${VERSION}"

SELECTED="${FRESHELL_PATCHES:-}"
if [ "$SELECTED" = "all" ]; then
    SELECTED=$(find "$VERSION_DIR" -maxdepth 1 -name '*.patch' -printf '%f\n' 2>/dev/null \
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
    patch="${VERSION_DIR}/${name}.patch"
    if [ ! -f "$patch" ]; then
        echo "[${LOG_PREFIX}] WARNING: Freshell patch '${name}' is not available for ${VERSION} (available: $(ls "$VERSION_DIR" 2>/dev/null | sed 's/\.patch$//' | paste -sd' ' -))"
        continue
    fi
    if git -C "$FRESHELL_DIR" apply "$patch"; then
        echo "[${LOG_PREFIX}] Applied Freshell patch: ${name}"
    else
        echo "[${LOG_PREFIX}] WARNING: Freshell patch '${name}' does not apply to ${VERSION}; skipped."
    fi
done
