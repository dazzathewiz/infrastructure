# scripts/truenas/

Scripts that run on TrueNAS SCALE (root). TrueNAS' supported configuration
mechanisms are WebUI / CLI / API; per iX guidance, the OS shouldn't be
modified outside those channels. These scripts are operational tooling
only — they read state, optionally delete files in user datasets, but don't
touch system config.

## Deploying a script to TrueNAS

```bash
# As admin/root on TrueNAS
sudo nano /root/<script>.py    # or vi, paste contents from this folder
sudo chmod +x /root/<script>.py
```

There's no equivalent of Unraid's User Scripts plugin on SCALE — these
scripts are run on demand from a shell. If you want scheduling, use a
TrueNAS Cron Job (System Settings → Advanced → Cron Jobs) pointing at
`/root/<script>.py`.

## Configuration

These scripts take CLI args rather than env files. Each script's `--help`
documents its arguments. Defaults are designed for a typical TrueNAS layout
where the Plex media root is under `/mnt/<pool>/<share>/`.

## Scripts in this folder

### truenas_dedupe.py — quality-aware media deduplication

Identifies duplicate media files where TrueNAS holds a lower-quality (or
same-quality but stale) version of content that Unraid already has at
higher (or current) quality. Removes only TrueNAS-side files; Unraid is
read-only reference.

**Why this script exists:** if your forward sync is rsync-without-`--delete`
(common, as `--delete` is dangerous), Unraid's downloader can curate the
library by replacing files with higher-quality versions, and the old
versions persist on TrueNAS forever. Over time TrueNAS accumulates a
graveyard of upgrade-replaced duplicates. This script finds and removes
them on TrueNAS, preserving the curated state Unraid intended.

**Rules applied per content identity** (e.g. show + season + episode):
1. Compute max resolution across all files in the group (Unraid + TrueNAS).
2. If max resolution ≥ 1080p: keep all 1080p+ files (1080p and 2160p coexist by design), delete <1080p.
3. If max resolution < 1080p: keep only files at max, delete the rest.
4. Among same-resolution survivors: prefer Unraid's copy, delete TrueNAS's.
5. Files whose relative path also exists on Unraid (forward-sync exact-match copies) are skipped from analysis entirely.

Only TrueNAS files are deletion candidates. Unraid hygiene is out of scope.

**Building the Unraid manifest** (run on Unraid first):
```bash
# Pick the library you want to dedupe
find '/mnt/user/TV Shows' -type f > /tmp/unraid_tvshows.txt
scp /tmp/unraid_tvshows.txt <truenas-user>@<truenas-host>:/tmp/
```

**Running the dedup** (run on TrueNAS):
```bash
# ALWAYS take a ZFS snapshot of the source dataset first
sudo zfs snapshot -r <pool>/<plex_dataset>@pre-dedupe-$(date +%Y%m%d-%H%M%S)

# Dry-run (default)
sudo python3 /root/truenas_dedupe.py \
    --truenas-root '/mnt/<pool>/<plex_dataset>/TV Shows' \
    --truenas-prefix '/mnt/<pool>/<plex_dataset>' \
    --unraid-manifest /tmp/unraid_tvshows.txt \
    --unraid-prefix '/mnt/user' \
    --library tv | tee /tmp/dedupe_tv_dryrun.txt

# Eyeball the report. Then apply:
sudo python3 /root/truenas_dedupe.py \
    --truenas-root '/mnt/<pool>/<plex_dataset>/TV Shows' \
    --truenas-prefix '/mnt/<pool>/<plex_dataset>' \
    --unraid-manifest /tmp/unraid_tvshows.txt \
    --unraid-prefix '/mnt/user' \
    --library tv \
    --apply
```

**Critical:** the `--truenas-prefix` and `--unraid-prefix` flags are how
the script identifies "this TrueNAS file is already on Unraid by exact
path" — a forward-sync replicated copy that should be skipped from analysis.
Without these, every replicated file would get flagged as a duplicate.

**Edge cases the script does NOT handle:**
- Files whose names don't parse to a recognisable identity (no `S01E05` /
  `1x05` for TV, no `(YYYY)` for movies) are silently skipped — never
  deleted. The dry-run report shows the unparseable count.
- Sidecar files (`.srt`, `.nfo`, `.jpg`) are never touched.
- Unraid hygiene (Unraid having its own duplicates) is a separate concern.

**Companion tool:** the corresponding Unraid-side reverse rsync that pulls
genuinely-new TrueNAS content back home, after dedup runs:
[`../unraid/reverse_sync.sh`](../unraid/reverse_sync.sh).
