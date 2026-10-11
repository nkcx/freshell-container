#!/bin/bash
# Removes unreferenced objects from Freshell's tabs registry.
#
# Freshell stores tab-registry state as content-addressed JSON blobs in
# ~/.freshell/tabs-registry/v1/objects/ and points at the live ones from
# v1/manifest.json. Every commit writes new blobs, but superseded blobs are
# never deleted (upstream keeps them deliberately so overlapping server
# processes can't publish refs to missing objects). On a long-lived home
# volume this grows to millions of files and tens of GB.
#
# Only the objects named in the current manifest are live, so this script
# moves objects/ aside, rebuilds it with just those objects, and deletes the
# old directory. A fresh directory also drops the bloated directory inode.
#
# Safe to run while Freshell is running: after the swap it re-reads the
# manifest and restores any newly referenced object from the old directory
# before deleting it. Closed-tab history (the closedTombstones object) and
# open-tab snapshots are referenced by the manifest and are kept.
#
# Usage: tabs-registry-gc.sh [--foreground]
#   By default the old directory is deleted in the background so startup
#   isn't blocked. --foreground waits for the deletion to finish.
set -euo pipefail

LOG_PREFIX="freshell-container"
REGISTRY_DIR="${TABS_REGISTRY_DIR:-${HOME}/.freshell/tabs-registry/v1}"
MANIFEST="${REGISTRY_DIR}/manifest.json"
OBJECTS="${REGISTRY_DIR}/objects"
FOREGROUND=false
[ "${1:-}" = "--foreground" ] && FOREGROUND=true

log() { echo "[${LOG_PREFIX}] tabs-registry-gc: $*"; }

# Print the object paths (relative to REGISTRY_DIR) the manifest references.
referenced_objects() {
    jq -r '[.clientRevisions, .closedTombstones, .devices, (.openSnapshots // {} | .[])]
           | .[] | .path' "${MANIFEST}" | grep -E '^objects/[a-f0-9]{64}\.json$'
}

# Hard-link every referenced object that is missing from objects/ back in
# from the old directory. Returns non-zero if a referenced object can't be found.
restore_referenced() {
    local old="$1" ref name ok=0
    while IFS= read -r ref; do
        name="${ref#objects/}"
        [ -e "${OBJECTS}/${name}" ] && continue
        if [ -e "${old}/${name}" ]; then
            ln "${old}/${name}" "${OBJECTS}/${name}" 2>/dev/null \
                || cp -p "${old}/${name}" "${OBJECTS}/${name}"
        else
            log "WARNING: referenced object ${name} not found"
            ok=1
        fi
    done < <(referenced_objects)
    return "${ok}"
}

# Old directories left behind by an interrupted run are always safe to delete.
LEFTOVERS=("${REGISTRY_DIR}"/objects.gc-*)

if [ ! -d "${OBJECTS}" ] || [ ! -f "${MANIFEST}" ]; then
    exit 0
fi
if ! referenced_objects >/dev/null 2>&1; then
    log "WARNING: manifest unreadable, skipping"
    exit 0
fi

# Skip the swap when there is little to collect (live set is ~5 objects).
COUNT=$(find "${OBJECTS}" -maxdepth 1 -type f -name '*.json' 2>/dev/null | head -n 1001 | wc -l || true)
if [ "${COUNT}" -le 1000 ] && [ ! -e "${LEFTOVERS[0]}" ]; then
    exit 0
fi

OLD=""
if [ "${COUNT}" -gt 1000 ]; then
    OLD="${REGISTRY_DIR}/objects.gc-$(date +%Y%m%d-%H%M%S)"
    NEW="${REGISTRY_DIR}/objects.new"
    rm -rf "${NEW}"
    mkdir "${NEW}"
    while IFS= read -r ref; do
        name="${ref#objects/}"
        [ -e "${OBJECTS}/${name}" ] && ln "${OBJECTS}/${name}" "${NEW}/${name}"
    done < <(referenced_objects)

    mv "${OBJECTS}" "${OLD}" && mv "${NEW}" "${OBJECTS}"

    # A running Freshell may have published a manifest pointing at objects
    # written to the old directory around the swap. Re-check a few times.
    for _ in 1 2 3; do
        sleep 2
        if ! restore_referenced "${OLD}"; then
            log "WARNING: keeping ${OLD} for inspection; not deleting"
            OLD=""
            break
        fi
    done
    log "rebuilt objects/ with $(find "${OBJECTS}" -maxdepth 1 -type f | wc -l) live objects"
fi

TO_DELETE=()
[ -n "${OLD}" ] && TO_DELETE+=("${OLD}")
for d in "${LEFTOVERS[@]}"; do
    [ -e "$d" ] && TO_DELETE+=("$d")
done
[ "${#TO_DELETE[@]}" -eq 0 ] && exit 0

log "deleting superseded objects in ${TO_DELETE[*]}"
if [ "${FOREGROUND}" = true ]; then
    rm -rf "${TO_DELETE[@]}"
    log "done"
else
    nohup nice -n 19 rm -rf "${TO_DELETE[@]}" >/dev/null 2>&1 &
fi
