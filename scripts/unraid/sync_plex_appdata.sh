#!/bin/bash
#
# sync_plex_appdata.sh — Track C Phase 2 ZFS appdata replication (TrueNAS → Unraid)
#
# Performs incremental ZFS send/recv of the Plex appdata dataset from TrueNAS
# to Unraid. Keeps the replica current so it can serve as a verified duplicate
# ahead of the Phase 3 Plex cutover decision.
#
# Plex on TrueNAS continues running throughout — sends read from snapshots,
# not the live dataset, so no disruption to the running container.
#
# Run from Unraid host as root. Designed to be scheduled "At Startup of Array"
# in Unraid User Scripts — idempotent, exits cleanly if already current.
#
# DESIGN DECISIONS (see project_track_c_next_actions.md):
#   - Pull pattern: Unraid orchestrates, same as reverse_sync.sh.
#   - SSH + AES-128-GCM, no compression. Same transport as reverse_sync.sh.
#     AES-GCM leverages hardware AES-NI for line-rate throughput.
#     LZ4 compression handles data reduction on the ZFS recv side.
#   - /usr/sbin/zfs full path required — non-interactive SSH on TrueNAS
#     does not load the shell PATH, so bare 'zfs' is not found.
#   - zfs allow grants send permission to admin without sudo.
#     One-time setup on TrueNAS: sudo zfs allow admin send <SRC_ZFS_DATASET>
#   - Destination dataset is readonly=on — replica only, no application writes.
#     zfs recv bypasses readonly; this prevents drift between snapshots.
#   - -F flag on recv: rolls back any unexpected uncommitted state before
#     applying the incremental. Belt-and-suspenders given readonly=on.
#   - canmount=on, dataset stays mounted permanently. Allows data inspection
#     without manual intervention. recv into a mounted dataset is safe.
#   - Snapshot names are preserved from source — TrueNAS auto-* names appear
#     on both sides, making the incremental base unambiguous.
#
# PREREQUISITES:
#   - Seed run already completed (zfs_appdata/appdata_replicated/plex exists
#     and has at least one snapshot).
#   - SSH key auth working: admin@<truenas_10g_ip> with RS_SSH_KEY.
#   - Known hosts: RS_KNOWN_HOSTS populated for TrueNAS 10G IP.
#   - zfs allow: sudo zfs allow admin send <SRC_ZFS_DATASET> on TrueNAS.
#   - Destination dataset: readonly=on, canmount=on, encryption key loaded.
#
# IaC REPO: scripts/unraid/sync_plex_appdata.sh
# LOCAL CONFIG (not committed): /boot/config/reverse_sync.env
#

set -euo pipefail

# ---- env override (sourced if present, NOT committed to repo) ----------
# Shared with reverse_sync.sh — same file, same RS_* namespace.
# See scripts/unraid/README.md for all supported variables.
ENV_FILE="/boot/config/reverse_sync.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

# ---- config (override via reverse_sync.env) ----------------------------

# RS_SRC_HOST is required — no default. Script fails fast if not set.
SRC_HOST="${RS_SRC_HOST:?RS_SRC_HOST not set — add to /boot/config/reverse_sync.env}"
SRC_USER="${RS_SRC_USER:-admin}"                   # zfs allow send granted to this user
SRC_BIND="${RS_SRC_BIND:-}"                        # SSH source-bind (force specific interface); leave empty to let OS choose
SSH_KEY="${RS_SSH_KEY:-/root/.ssh/reverse_sync_key}"
KNOWN_HOSTS="${RS_KNOWN_HOSTS:?RS_KNOWN_HOSTS not set — add to /boot/config/reverse_sync.env}"

# ZFS-specific vars (add to reverse_sync.env alongside RS_* vars)
# RS_ZFS_SRC and RS_ZFS_DST are required — no defaults.
SRC_ZFS_DATASET="${RS_ZFS_SRC:?RS_ZFS_SRC not set — add to /boot/config/reverse_sync.env}"
DST_ZFS_DATASET="${RS_ZFS_DST:?RS_ZFS_DST not set — add to /boot/config/reverse_sync.env}"
TRUENAS_ZFS_BIN="${RS_ZFS_BIN:-/usr/sbin/zfs}"    # full path — PATH not set in non-interactive SSH

LOG_DIR="${RS_LOG_DIR:?RS_LOG_DIR not set — add to /boot/config/reverse_sync.env}"

# ---- helpers -----------------------------------------------------------

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

ssh_truenas() {
    local bind_opt=()
    [[ -n "${SRC_BIND:-}" ]] && bind_opt=(-o "BindAddress=${SRC_BIND}")

    ssh \
        -c aes128-gcm@openssh.com \
        -o Compression=no \
        "${bind_opt[@]}" \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o UserKnownHostsFile="${KNOWN_HOSTS}" \
        -o StrictHostKeyChecking=accept-new \
        -i "${SSH_KEY}" \
        "${SRC_USER}@${SRC_HOST}" \
        "$@"
}

# ---- pre-flight --------------------------------------------------------

preflight() {
    if [[ ! -f "$SSH_KEY" ]]; then
        log "ERROR: SSH key not found at $SSH_KEY"
        log "       Generate: ssh-keygen -t ed25519 -f $SSH_KEY -N ''"
        log "       Install:  ssh-copy-id -i ${SSH_KEY}.pub ${SRC_USER}@${SRC_HOST}"
        exit 3
    fi

    mkdir -p "$(dirname "$KNOWN_HOSTS")"
    touch "$KNOWN_HOSTS"

    if ! ssh_truenas "true" 2>/dev/null; then
        log "ERROR: Cannot SSH to ${SRC_USER}@${SRC_HOST} — check key auth and network."
        exit 3
    fi

    if ! zfs list "$DST_ZFS_DATASET" &>/dev/null; then
        log "ERROR: Destination dataset $DST_ZFS_DATASET not found on Unraid."
        log "       Seed run required before incrementals can proceed."
        exit 3
    fi

    local key_status
    key_status=$(zfs get -H -o value keystatus "$(echo "$DST_ZFS_DATASET" | cut -d/ -f1-2)" 2>/dev/null || echo "unavailable")
    if [[ "$key_status" != "available" ]]; then
        log "ERROR: Encryption key not loaded for parent dataset."
        log "       Run: zfs load-key $(echo "$DST_ZFS_DATASET" | cut -d/ -f1-2)"
        exit 3
    fi
}

# ---- main --------------------------------------------------------------

main() {
    mkdir -p "$LOG_DIR"
    TS=$(date +%Y%m%d-%H%M%S)
    LOG="$LOG_DIR/plex_appdata_sync-${TS}.log"

    {
        echo "=========================================="
        echo "Plex appdata ZFS sync"
        echo "Started:  $(date -Iseconds)"
        echo "Source:   ${SRC_USER}@${SRC_HOST}:${SRC_ZFS_DATASET}"
        echo "Dest:     ${DST_ZFS_DATASET}"
        echo "=========================================="
    } | tee "$LOG"

    preflight 2>&1 | tee -a "$LOG"

    # Latest snapshot on each side (just the @suffix, without dataset name)
    local remote_snap local_snap
    remote_snap=$(ssh_truenas \
        "${TRUENAS_ZFS_BIN} list -H -t snapshot -o name ${SRC_ZFS_DATASET} \
        | tail -1 | cut -d@ -f2" 2>/dev/null)
    local_snap=$(zfs list -H -t snapshot -o name "$DST_ZFS_DATASET" 2>/dev/null \
        | tail -1 | cut -d@ -f2)

    if [[ -z "$remote_snap" ]]; then
        log "ERROR: No snapshots found on TrueNAS source ${SRC_ZFS_DATASET}. Aborting."
        exit 1
    fi

    if [[ -z "$local_snap" ]]; then
        log "ERROR: No local snapshot found on ${DST_ZFS_DATASET}."
        log "       Seed run required: see sync_plex_appdata.sh header for seed command."
        exit 1
    fi

    if [[ "$local_snap" == "$remote_snap" ]]; then
        log "Already current (${local_snap}). Nothing to do."
        exit 0
    fi

    log "Sending incremental: ${local_snap} → ${remote_snap}"

    ssh_truenas \
        "${TRUENAS_ZFS_BIN} send -i \
        ${SRC_ZFS_DATASET}@${local_snap} \
        ${SRC_ZFS_DATASET}@${remote_snap}" \
        | zfs recv -F "$DST_ZFS_DATASET" 2>&1 | tee -a "$LOG"

    local rc=${PIPESTATUS[0]}
    if [[ $rc -ne 0 ]]; then
        log "ERROR: zfs send exited ${rc}"
        exit $rc
    fi

    log "Sync complete. Local now at: ${remote_snap}"

    {
        echo "=========================================="
        echo "Done"
        echo "Finished: $(date -Iseconds)"
        echo "Log:      $LOG"
        echo "=========================================="
    } | tee -a "$LOG"
}

main
