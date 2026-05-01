# scripts/

Operational scripts for hosts that aren't managed by Ansible — primarily
Unraid (OS runs from RAM, no native Ansible target) and TrueNAS SCALE
(iX guidance is "WebUI/CLI/API only", not Ansible).

These scripts live in the repo so:
- Changes have a paper trail
- The "what we did" stays next to "what runs"
- A boot-device loss doesn't take the working version with it

## Layout

| Path | Host | Purpose |
|---|---|---|
| [`unraid/reverse_sync.sh`](unraid/reverse_sync.sh) | Unraid | Pull TrueNAS → Unraid media (rsync), with ZFS snapshot + backup-dir safety net |
| [`truenas/truenas_dedupe.py`](truenas/truenas_dedupe.py) | TrueNAS | Identify and remove lower-quality duplicate media files using an Unraid manifest |

Each subdirectory has its own README covering deployment + configuration.

## Conventions

**Configuration via environment variables.** No hardcoded host-specific
values (IPs, paths, dataset names) in committed code. Each script declares
its required and optional env vars in its file header and the per-host
README.

**Local config files.** Unraid scripts source `/boot/config/<name>.env`
if present (persists across reboots via the boot device). TrueNAS scripts
take CLI args. Both override env vars set on the calling shell.

**Default to dry-run.** Destructive scripts default to preview mode. An
explicit `--apply` flag or `DEFAULT_APPLY=1` is required to commit.

**No personal context in comments.** Specific IPs, hostnames, content
library names, and incident references are kept out of committed code.
That context lives in operational notes, not scripts.
