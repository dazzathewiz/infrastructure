#!/bin/bash
#
# reverse_sync.sh — Pull TrueNAS → Unraid media via rsync.
#
# Designed for the case where:
#   - Plex (or other ingest) writes new content to TrueNAS that doesn't
#     exist on Unraid yet (DVR recordings, Plex auto-downloads, etc.).
#   - The forward sync (Unraid → TrueNAS) doesn't propagate Unraid's
#     deletions, so older curated-out files accumulate on TrueNAS.
#   - You want a re-runnable, idempotent way to bring genuinely-new
#     TrueNAS content back home without re-pulling the older versions.
#
# Run from the Unraid host as root. Default mode is dry-run preview;
# pass --apply (or set DEFAULT_APPLY=1 below) to actually transfer.
#
# DUAL SAFETY NET on apply:
#   1. Recursive ZFS snapshot of $RS_DST_ROOT before any transfer
#      (rollback for ZFS-pool writes).
#   2. --backup --backup-dir=$RS_BACKUP_ROOT/<TS>/ for any in-place
#      overwrites (ZFS snapshots don't cover files on the parity array).
#
# DESIGN PROPERTIES:
#   - Destination is the Unraid FUSE union (/mnt/user/<share>/), not the
#     ZFS pool directly. This ensures rsync sees every existing file
#     regardless of which physical disk holds it, and writes obey the
#     share's allocation policy.
#   - SSH transport with AES-128-GCM cipher (AES-NI accelerated, much
#     faster than the default chacha20 inside a VM).
#   - --no-perms --no-owner --no-group: don't fight the destination's
#     share-level perms; just move bytes + timestamps.
#   - --update: only overwrite when source is newer.
#   - --delete is FORBIDDEN. Reverse sync only adds and updates.
#
# CONFIGURATION:
#   Set the RS_* environment variables below, either by:
#   - Creating /boot/config/reverse_sync.env on Unraid (sourced if present);
#     this file is NOT committed and persists across reboots via boot device.
#   - Exporting in your shell before running (interactive use).
#   See scripts/unraid/README.md for the full variable list.
#
# USAGE — manual / SSH:
#   ./reverse_sync.sh                          # dry-run all configured shares
#   ./reverse_sync.sh --apply                  # commit all
#   ./reverse_sync.sh --share "TV Shows"       # dry-run one share
#   ./reverse_sync.sh --apply --share "Movies" # commit one share
#
# USAGE — Unraid User Scripts (no CLI args from the UI):
#   1. Set DEFAULT_APPLY=1 in this file before saving.
#   2. Save → "Run in Background".
#   3. Reset DEFAULT_APPLY=0 after the run completes.
#

set -euo pipefail

# ---- mode (User Scripts users edit this line) ---------------------
# 0 = dry-run preview (default, safe). 1 = apply (transfer + snapshot).
# CLI --apply / --share flags override this when run from a shell.
DEFAULT_APPLY=0

# ---- local config (env file) --------------------------------------
# Source local config if present. Variables defined here are picked up
# by the ${VAR:-default} expansions below.
if [[ -f /boot/config/reverse_sync.env ]]; then
    # shellcheck disable=SC1091
    source /boot/config/reverse_sync.env
fi

# ---- config (env vars override defaults) --------------------------

# Required — fail fast if not set.
SRC_HOST="${RS_SRC_HOST:?RS_SRC_HOST not set. See scripts/unraid/README.md.}"

# Optional with sensible defaults.
SRC_USER="${RS_SRC_USER:-admin}"
SRC_ROOT="${RS_SRC_ROOT:-/mnt/nas/plex_data}"
DST_ROOT="${RS_DST_ROOT:-/mnt/user}"
SSH_KEY="${RS_SSH_KEY:-/root/.ssh/reverse_sync_key}"
KNOWN_HOSTS="${RS_KNOWN_HOSTS:-/mnt/user/appdata/reverse_sync/known_hosts}"
LOG_DIR="${RS_LOG_DIR:-/mnt/user/appdata/reverse_sync}"
BACKUP_ROOT="${RS_BACKUP_ROOT:-/mnt/user/reverse_sync_backups}"

# Optional — leave empty to skip SSH source-bind.
SRC_BIND="${RS_SRC_BIND:-}"

# Shares — comma-separated list. Default reflects a typical Plex layout.
RS_SHARES_DEFAULT="TV Shows,Movies,DVD Rips"
IFS=',' read -ra ALL_SHARES <<< "${RS_SHARES:-$RS_SHARES_DEFAULT}"

# ---- argument parsing ---------------------------------------------
# CLI args override DEFAULT_APPLY. From User Scripts (no args), DEFAULT_APPLY wins.

APPLY=$DEFAULT_APPLY
SHARE_FILTER=""

usage() {
    cat <<EOF
Usage: $0 [--apply] [--share "<name>"]

  --apply           Actually transfer (default = dry-run preview).
  --share "<name>"  Limit to one share. Valid: ${ALL_SHARES[*]}
  -h, --help        Show this message.
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)        APPLY=1; shift ;;
        --share)        SHARE_FILTER="$2"; shift 2 ;;
        -h|--help)      usage ;;
        *)              echo "Unknown arg: $1" >&2; usage ;;
    esac
done

# ---- pick shares to run -------------------------------------------

if [[ -n "$SHARE_FILTER" ]]; then
    found=0
    for s in "${ALL_SHARES[@]}"; do
        [[ "$s" == "$SHARE_FILTER" ]] && found=1
    done
    if [[ $found -eq 0 ]]; then
        echo "ERROR: '$SHARE_FILTER' is not a known share." >&2
        echo "       Valid shares: ${ALL_SHARES[*]}" >&2
        exit 2
    fi
    SHARES=("$SHARE_FILTER")
else
    SHARES=("${ALL_SHARES[@]}")
fi

# ---- bookkeeping --------------------------------------------------

mkdir -p "$LOG_DIR"
TS=$(date +%Y%m%d-%H%M%S)
LOG="$LOG_DIR/run-${TS}.log"

if [[ $APPLY -eq 1 ]]; then
    MODE="APPLY"
    BACKUP_DIR="${BACKUP_ROOT}/${TS}"
else
    MODE="DRY-RUN"
fi

# ---- pre-flight ---------------------------------------------------

preflight() {
    echo "Pre-flight checks..."

    # SSH key exists
    if [[ ! -f "$SSH_KEY" ]]; then
        echo "ERROR: SSH key not found at $SSH_KEY" >&2
        echo "       Generate with: ssh-keygen -t ed25519 -f $SSH_KEY -N ''" >&2
        echo "       Then push pubkey to ${SRC_USER}@${SRC_HOST} via the destination's UI." >&2
        exit 3
    fi

    # Ensure known_hosts lives on a real FS (Unraid /root/.ssh is on boot
    # device, which doesn't support hardlinks for atomic rotation).
    mkdir -p "$(dirname "$KNOWN_HOSTS")"
    touch "$KNOWN_HOSTS"

    local pf_ssh="ssh -i $SSH_KEY -o BatchMode=yes -o ConnectTimeout=5 \
        -o UserKnownHostsFile=${KNOWN_HOSTS} -o StrictHostKeyChecking=accept-new"
    [[ -n "$SRC_BIND" ]] && pf_ssh="$pf_ssh -o BindAddress=${SRC_BIND}"

    # SSH reachability + auth
    if ! $pf_ssh "${SRC_USER}@${SRC_HOST}" "true" 2>/dev/null; then
        echo "ERROR: cannot SSH to ${SRC_USER}@${SRC_HOST} with key auth." >&2
        exit 3
    fi

    # Source root readable
    if ! $pf_ssh "${SRC_USER}@${SRC_HOST}" \
            "test -r '$SRC_ROOT' && test -x '$SRC_ROOT'" 2>/dev/null; then
        echo "ERROR: ${SRC_USER}@${SRC_HOST}:${SRC_ROOT} not readable." >&2
        exit 3
    fi

    # Destination root exists and writable
    if [[ ! -d "$DST_ROOT" ]] || [[ ! -w "$DST_ROOT" ]]; then
        echo "ERROR: $DST_ROOT not a writable directory." >&2
        exit 3
    fi

    # ZFS dataset validation (set in main() before this fn runs in a subshell pipe)
    if [[ $APPLY -eq 1 ]]; then
        if [[ -z "${ZFS_DATASET:-}" ]]; then
            echo "ERROR: could not auto-detect ZFS dataset for $DST_ROOT." >&2
            echo "       Run 'zfs list' to verify a dataset is mounted at $DST_ROOT," >&2
            echo "       or set ZFS_DATASET= manually in main()." >&2
            exit 3
        fi
        echo "  ZFS dataset for snapshot: $ZFS_DATASET"

        # Backup-root must exist as a share before --apply
        if [[ ! -d "$BACKUP_ROOT" ]]; then
            echo "ERROR: backup root '$BACKUP_ROOT' does not exist." >&2
            echo "       Create the share via Unraid Shares UI before running --apply." >&2
            exit 3
        fi
        if [[ ! -w "$BACKUP_ROOT" ]]; then
            echo "ERROR: backup root '$BACKUP_ROOT' exists but is not writable." >&2
            exit 3
        fi
        echo "  Backup root: $BACKUP_ROOT"
    fi

    echo "  Pre-flight OK."
}

# ---- snapshot before apply ----------------------------------------

snapshot_pre_sync() {
    local snap="${ZFS_DATASET}@pre-rsync-${TS}"
    echo "Taking ZFS snapshot: $snap"
    if ! zfs snapshot -r "$snap"; then
        echo "ERROR: snapshot failed; aborting before any transfer." >&2
        exit 4
    fi
    echo "  Snapshot created: $snap"
    echo "  Rollback (if needed): zfs rollback $snap"
    echo "  List backups (overwrites): ls -la $BACKUP_DIR 2>/dev/null"
}

# ---- rsync flag construction --------------------------------------

build_rsync_flags() {
    local flags=(
        -ahv
        --no-perms --no-owner --no-group
        --info=progress2
        --partial --partial-dir=.rsync-partial
        --update
        --itemize-changes
        --stats
        # Skip forward-sync detritus on source (interrupted/older rsync runs).
        --exclude='.*.??????'    # rsync tempfile pattern: .<basename>.<6 random chars>
        --exclude='*.partial'    # legacy --partial mode resume files
        --exclude='.rsync-partial/'  # in case our own partial-dir survives a failure
    )

    if [[ $APPLY -eq 1 ]]; then
        flags+=( --backup --backup-dir="$BACKUP_DIR" )
    else
        flags+=( --dry-run )
    fi

    printf '%s\n' "${flags[@]}"
}

# ---- main ---------------------------------------------------------

main() {
    {
        echo "=========================================="
        echo "Reverse sync — ${MODE}"
        echo "Started: $(date -Iseconds)"
        echo "Shares:  ${SHARES[*]}"
        echo "Source:  ${SRC_USER}@${SRC_HOST}:${SRC_ROOT}/<share>/"
        echo "Dest:    ${DST_ROOT}/<share>/"
        echo "=========================================="
    } | tee "$LOG"

    # Detect ZFS dataset HERE (in main's shell) so the assignment survives
    # past the upcoming pipe-to-tee subshells. preflight() then validates.
    ZFS_DATASET=""
    if [[ $APPLY -eq 1 ]]; then
        ZFS_DATASET=$(zfs list -H -o name,mountpoint 2>/dev/null \
                      | awk -v dst="$DST_ROOT" '$2 == dst {print $1}' \
                      | head -1)
        # If the destination root is a FUSE union (e.g. /mnt/user), it may
        # not appear directly in `zfs list`. Fall back to the underlying
        # ZFS pool that holds the share content. Edit if your layout differs.
        if [[ -z "$ZFS_DATASET" ]]; then
            ZFS_DATASET=$(zfs list -H -o name,mountpoint 2>/dev/null \
                          | awk '$2 == "/mnt/zfs_media" {print $1}' \
                          | head -1)
        fi
    fi

    preflight 2>&1 | tee -a "$LOG"

    if [[ $APPLY -eq 1 ]]; then
        snapshot_pre_sync 2>&1 | tee -a "$LOG"
        mkdir -p "$BACKUP_DIR"
        echo "  Backup dir: $BACKUP_DIR" | tee -a "$LOG"
    fi

    # Re-touch known_hosts in main's scope (idempotent with preflight)
    mkdir -p "$(dirname "$KNOWN_HOSTS")"
    touch "$KNOWN_HOSTS"

    local ssh_cmd="ssh -i $SSH_KEY \
        -c aes128-gcm@openssh.com \
        -o Compression=no \
        -o UserKnownHostsFile=${KNOWN_HOSTS} \
        -o StrictHostKeyChecking=accept-new"
    [[ -n "$SRC_BIND" ]] && ssh_cmd="$ssh_cmd -o BindAddress=${SRC_BIND}"
    mapfile -t rsync_flags < <(build_rsync_flags)

    local exit_overall=0
    for share in "${SHARES[@]}"; do
        {
            echo ""
            echo "------------------------------------------"
            echo "Share: $share"
            echo "------------------------------------------"
        } | tee -a "$LOG"

        if rsync "${rsync_flags[@]}" \
                -e "$ssh_cmd" \
                "${SRC_USER}@${SRC_HOST}:${SRC_ROOT}/${share}/" \
                "${DST_ROOT}/${share}/" 2>&1 | tee -a "$LOG"; then
            echo "  [$share] OK" | tee -a "$LOG"
        else
            local rc=${PIPESTATUS[0]}
            echo "  [$share] FAILED (rsync exit $rc) — continuing with remaining shares" | tee -a "$LOG"
            exit_overall=$rc
        fi
    done

    {
        echo ""
        echo "=========================================="
        echo "Done — ${MODE}"
        echo "Finished: $(date -Iseconds)"
        echo "Log: $LOG"
        if [[ $APPLY -eq 1 ]]; then
            echo "Snapshot: ${ZFS_DATASET}@pre-rsync-${TS}"
            echo "Backups:  $BACKUP_DIR"
        fi
        echo "Overall exit: $exit_overall"
        echo "=========================================="
    } | tee -a "$LOG"

    exit $exit_overall
}

main
