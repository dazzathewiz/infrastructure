# scripts/unraid/

Scripts that run on the Unraid host (root). Typically deployed via the
[User Scripts](https://forums.unraid.net/topic/48286-plugin-ca-user-scripts/)
plugin so they survive reboots and gain a UI hook.

## Deploying a script to Unraid

Two options, pick one:

**Option A — User Scripts UI (recommended).**
1. Settings → User Scripts → Add New Script.
2. Name the script (the folder under `/boot/config/plugins/user.scripts/scripts/<name>/` will match).
3. Click the gear → Edit Script. Paste the contents of the `.sh` file.
4. Save. Schedule or run on demand from the UI.

**Option B — direct sync to the boot device.**
```bash
# On Unraid as root
mkdir -p /boot/config/plugins/user.scripts/scripts/<name>
cp scripts/unraid/<script>.sh /boot/config/plugins/user.scripts/scripts/<name>/script
chmod +x /boot/config/plugins/user.scripts/scripts/<name>/script
```

## Local configuration via env file

Scripts source `/boot/config/<script_basename>.env` on startup if present.
This file holds host-specific values (IPs, paths, keys) and **is not
committed** — it lives on the Unraid boot device only.

Example for `reverse_sync.sh` — copy this skeleton to
`/boot/config/reverse_sync.env`, fill in your values, save:

```bash
# /boot/config/reverse_sync.env
RS_SRC_HOST="192.0.2.10"           # Required: TrueNAS IP or hostname
RS_SRC_USER="admin"                # Optional: defaults to "admin"
RS_SRC_BIND="192.0.2.1"            # Optional: SSH source-bind (10G IF on Unraid)
RS_SRC_ROOT="/mnt/plex_data"       # Optional: TrueNAS plex root
RS_DST_ROOT="/mnt/user"            # Optional: Unraid FUSE union root
RS_SSH_KEY="/root/.ssh/reverse_sync_key"
RS_SHARES="TV Shows,Movies,DVD Rips"   # Optional: comma-separated
```

## Scripts in this folder

### reverse_sync.sh — TrueNAS → Unraid media reverse rsync

Pulls media that exists on TrueNAS but not on Unraid (e.g. DVR recordings
captured by a Plex container running on TrueNAS). Designed to be re-runnable
indefinitely; safe to schedule.

**Safety:**
- Default mode is dry-run. `--apply` (or `DEFAULT_APPLY=1` for User Scripts)
  is required to transfer.
- Pre-flight ZFS snapshot of the destination dataset (recursive) provides
  rollback for ZFS-pool writes.
- `--backup-dir` collects any files that get overwritten in place (matters
  for files physically on the parity array, where ZFS snapshots don't reach).
- `--update` only overwrites when source is newer.
- `--delete` is FORBIDDEN — reverse sync only adds and updates.

**Required setup before first run:**
1. SSH key from Unraid root → TrueNAS source user. Generate with
   `ssh-keygen -t ed25519 -f /root/.ssh/reverse_sync_key`, push pubkey to
   TrueNAS via the WebUI under the destination user's account.
2. Backup-share on Unraid. Create via Shares UI. Default name
   `reverse_sync_backups`.
3. Local env file at `/boot/config/reverse_sync.env` (see skeleton above).

**Typical SSH usage:**
```bash
./reverse_sync.sh                          # dry-run all configured shares
./reverse_sync.sh --apply                  # commit all
./reverse_sync.sh --share "TV Shows"       # dry-run one share
./reverse_sync.sh --apply --share "Movies" # commit one share
```

**Typical User Scripts usage:**
1. Set `DEFAULT_APPLY=1` at the top of the script.
2. Save → "Run in Background".
3. Reset `DEFAULT_APPLY=0` after the run completes (prevents accidental
   re-applies if someone clicks "Run" without thinking).

**Logs:** `${RS_LOG_DIR:-/mnt/user/appdata/reverse_sync}/run-<timestamp>.log`.

**Companion tool:** for one-time TrueNAS-side cleanup of upgrade-replaced
duplicate files BEFORE the reverse sync runs (so you don't pull older
quality versions back to Unraid), see
[`../truenas/truenas_dedupe.py`](../truenas/truenas_dedupe.py).
