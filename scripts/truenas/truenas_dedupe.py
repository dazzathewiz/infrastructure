#!/usr/bin/env python3
"""
truenas_dedupe.py — Identify and remove lower-quality duplicate media files
on TrueNAS based on equivalent or higher-quality versions on Unraid (or
within TrueNAS itself).

Designed to clean up the long-tail accumulation of older-quality versions
that persist on TrueNAS because the forward sync (Unraid → TrueNAS) does
not propagate deletions. After the downloader (Sonarr/Radarr) on Unraid
upgrades a file or curates the library, the old version stays on TrueNAS
forever.

RULES (per content identity group, e.g. same show+season+episode):
  1. Compute max_resolution across all files in the group.
  2. If max_resolution >= 1080p:
     - Keep all 1080p+ files (1080p AND 2160p coexist by design).
     - Delete files below 1080p.
  3. If max_resolution < 1080p:
     - Keep only files at max_resolution.
     - Delete files below max_resolution.
  4. Among same-resolution survivors: if Unraid has the file at that
     resolution, delete the TrueNAS counterpart. Unraid wins ties because
     the downloader's curation lives there.
  5. Only TrueNAS files are deletion candidates. Unraid is read-only
     reference.

CRITICAL: TrueNAS files whose relative path also exists on Unraid (i.e.
forward-synced copies — same library/show/season/file) are skipped from
analysis entirely. Only TrueNAS-only files become deletion candidates.
This prevents the script from flagging perfectly-replicated content as
duplicates.

USAGE (run on TrueNAS):
  # Dry-run (default — shows what would be deleted, deletes nothing):
  python3 truenas_dedupe.py \\
      --truenas-root '/mnt/<pool>/<plex_dataset>/TV Shows' \\
      --truenas-prefix '/mnt/<pool>/<plex_dataset>' \\
      --unraid-manifest /tmp/unraid_tvshows.txt \\
      --unraid-prefix '/mnt/user' \\
      --library tv

  # After review, actually delete:
  python3 truenas_dedupe.py \\
      --truenas-root '/mnt/<pool>/<plex_dataset>/TV Shows' \\
      --truenas-prefix '/mnt/<pool>/<plex_dataset>' \\
      --unraid-manifest /tmp/unraid_tvshows.txt \\
      --unraid-prefix '/mnt/user' \\
      --library tv \\
      --apply

BUILDING THE UNRAID MANIFEST (run on Unraid):
  # TV Shows
  find '/mnt/user/TV Shows' -type f > /tmp/unraid_tvshows.txt
  # Movies
  find '/mnt/user/Movies' -type f > /tmp/unraid_movies.txt
  # Then copy to TrueNAS:
  scp /tmp/unraid_tvshows.txt <truenas-user>@<truenas-host>:/tmp/

OUTPUT:
  Dry-run report shows per-group decisions and a final list of deletion
  candidates with sizes. The TOTAL line tells you the bytes to be freed.
  Each deletion candidate also shows WHY (e.g. "below 1080p, group has
  2160p on unraid").

EDGE CASES:
  - Files that don't parse to a recognisable identity (no S01E05 / no year
    in parens) are ignored — never deleted.
  - Only video file extensions are considered (.mkv .mp4 .avi .ts .m4v
    .mov .wmv .mpg .mpeg). Sidecar files (.srt, .nfo, .jpg) are not
    touched.
  - Unparseable identity: file is silently skipped (printed in --verbose).

SAFETY: ALWAYS take a recursive ZFS snapshot of the source dataset before
running with --apply. Example:
  sudo zfs snapshot -r <pool>/<plex_dataset>@pre-dedupe-$(date +%Y%m%d-%H%M%S)
"""

import argparse
import os
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# Resolution scoring — higher = better
RES_2160P = 4
RES_1080P = 3
RES_720P = 2
RES_LOW = 1   # 480p, SD, or unknown

VIDEO_EXTS = {'.mkv', '.mp4', '.avi', '.ts', '.m4v', '.mov', '.wmv', '.mpg', '.mpeg'}

# TV episode marker: 1x05, 12x103, S01E05, s1e5
EPISODE_RE = re.compile(r'\b(?:S(\d{1,2})E(\d{1,3})|(\d{1,2})x(\d{1,3}))\b', re.IGNORECASE)
YEAR_RE = re.compile(r'\((\d{4})\)')


@dataclass
class FileRecord:
    path: str
    size: int
    resolution: int
    location: str  # 'truenas' or 'unraid'

    @property
    def res_label(self) -> str:
        return {RES_2160P: '2160p', RES_1080P: '1080p',
                RES_720P: '720p', RES_LOW: '<720p'}[self.resolution]


def extract_resolution(filename: str) -> int:
    """Scan filename for resolution markers, return highest match."""
    upper = filename.upper()
    if '2160P' in upper or '4K' in upper or 'UHD' in upper:
        return RES_2160P
    if '1080P' in upper:
        return RES_1080P
    if '720P' in upper:
        return RES_720P
    return RES_LOW


def extract_tv_identity(path: str) -> Optional[tuple]:
    """Identity = (show_lower, season, episode). Show comes from path component
    after 'TV Shows'. Season+episode come from filename regex."""
    parts = Path(path).parts
    try:
        tv_idx = next(i for i, p in enumerate(parts) if p.lower() == 'tv shows')
    except StopIteration:
        return None
    if len(parts) < tv_idx + 3:
        return None
    show = parts[tv_idx + 1].lower()
    filename = Path(path).name
    m = EPISODE_RE.search(filename)
    if not m:
        return None
    if m.group(1) and m.group(2):
        season, episode = int(m.group(1)), int(m.group(2))
    else:
        season, episode = int(m.group(3)), int(m.group(4))
    return (show, season, episode)


def extract_movie_identity(path: str) -> Optional[tuple]:
    """Identity = (title_normalized, year). Year from (YYYY) in filename;
    title is everything before that."""
    stem = Path(path).stem
    m = YEAR_RE.search(stem)
    if not m:
        return None
    year = int(m.group(1))
    title = stem[:m.start()].strip().lower()
    title = re.sub(r'\s+', ' ', title)
    if not title:
        return None
    return (title, year)


def is_video(path: str) -> bool:
    return Path(path).suffix.lower() in VIDEO_EXTS


def walk_truenas(root: str) -> list:
    """Walk TrueNAS root, return video files with size."""
    files = []
    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            full = os.path.join(dirpath, fn)
            if not is_video(full):
                continue
            try:
                size = os.path.getsize(full)
            except OSError:
                continue
            files.append(FileRecord(full, size, extract_resolution(fn), 'truenas'))
    return files


def load_unraid_manifest(path: str) -> list:
    """Load Unraid file list from manifest. Sizes default to 0 (we don't need
    them — Unraid files are never delete targets)."""
    files = []
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            p = line.rstrip('\n').rstrip('\r')
            if not p or not is_video(p):
                continue
            files.append(FileRecord(p, 0, extract_resolution(Path(p).name), 'unraid'))
    return files


def decide(group: list) -> tuple:
    """Given a list of FileRecord sharing an identity, return
    (kept_files, deletion_candidates_truenas, reason_per_path_dict)."""
    max_res = max(f.resolution for f in group)
    keep_threshold = RES_1080P if max_res >= RES_1080P else max_res

    keep = []
    delete = []
    reasons = {}

    # First pass: drop anything below the keep threshold
    survivors = []
    for f in group:
        if f.resolution < keep_threshold:
            if f.location == 'truenas':
                if max_res >= RES_1080P:
                    reasons[f.path] = f"below 1080p; group has {label(max_res)}"
                else:
                    reasons[f.path] = f"below max_res={label(max_res)}"
                delete.append(f)
            # Unraid files below threshold: not our concern (Unraid hygiene)
        else:
            survivors.append(f)

    # Second pass: among survivors at each resolution, prefer Unraid
    by_res = defaultdict(list)
    for f in survivors:
        by_res[f.resolution].append(f)

    for res, group_at_res in by_res.items():
        unraid_at_res = [f for f in group_at_res if f.location == 'unraid']
        truenas_at_res = [f for f in group_at_res if f.location == 'truenas']
        if unraid_at_res:
            keep.extend(unraid_at_res)
            for tf in truenas_at_res:
                reasons[tf.path] = f"unraid has {label(res)} version (prefer unraid)"
                delete.append(tf)
        else:
            keep.extend(truenas_at_res)

    return keep, delete, reasons


def label(res: int) -> str:
    return {RES_2160P: '2160p', RES_1080P: '1080p',
            RES_720P: '720p', RES_LOW: '<720p'}[res]


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--truenas-root', required=True,
                   help="Root path on TrueNAS to scan, e.g. '/mnt/<pool>/<plex_dataset>/TV Shows'")
    p.add_argument('--truenas-prefix', required=True,
                   help="TrueNAS storage prefix to strip when computing relative paths "
                        "(e.g. '/mnt/<pool>/<plex_dataset>')")
    p.add_argument('--unraid-manifest', required=True,
                   help="Path to file containing Unraid's `find` output")
    p.add_argument('--unraid-prefix', default='/mnt/user',
                   help="Unraid storage prefix to strip when computing relative paths "
                        "(default: /mnt/user)")
    p.add_argument('--library', choices=['tv', 'movie'], required=True,
                   help="Identity extraction mode")
    p.add_argument('--apply', action='store_true',
                   help="Actually delete files (default = dry-run)")
    p.add_argument('--verbose', '-v', action='store_true',
                   help="Show unparseable files and per-group decisions")
    args = p.parse_args()

    if not os.path.isdir(args.truenas_root):
        sys.exit(f"ERROR: --truenas-root {args.truenas_root!r} is not a directory")
    if not os.path.isfile(args.unraid_manifest):
        sys.exit(f"ERROR: --unraid-manifest {args.unraid_manifest!r} not found")

    extract = extract_tv_identity if args.library == 'tv' else extract_movie_identity

    print(f"Walking TrueNAS root: {args.truenas_root}", file=sys.stderr)
    truenas_files = walk_truenas(args.truenas_root)
    print(f"  found {len(truenas_files)} video files", file=sys.stderr)

    print(f"Loading Unraid manifest: {args.unraid_manifest}", file=sys.stderr)
    unraid_files = load_unraid_manifest(args.unraid_manifest)
    print(f"  found {len(unraid_files)} video files", file=sys.stderr)

    # Build Unraid relative-path set (path under --unraid-prefix).
    # This is the canonical "what's already replicated to Unraid" lookup.
    unraid_prefix = args.unraid_prefix.rstrip('/')
    unraid_rel_paths = set()
    for f in unraid_files:
        try:
            rel = os.path.relpath(f.path, unraid_prefix)
            if not rel.startswith('..'):
                unraid_rel_paths.add(rel)
        except ValueError:
            continue

    # Filter TrueNAS files: skip those whose relative path matches Unraid
    # (these are forward-synced copies — equivalent to their Unraid counterpart,
    # not separate duplicates).
    truenas_prefix = args.truenas_prefix.rstrip('/')
    truenas_only_files = []
    truenas_synced_count = 0
    for f in truenas_files:
        try:
            rel = os.path.relpath(f.path, truenas_prefix)
        except ValueError:
            truenas_only_files.append(f)
            continue
        if rel in unraid_rel_paths:
            truenas_synced_count += 1
        else:
            truenas_only_files.append(f)

    print(f"  TrueNAS files already on Unraid (synced): {truenas_synced_count}",
          file=sys.stderr)
    print(f"  TrueNAS-only files (analysed for dedup): {len(truenas_only_files)}",
          file=sys.stderr)

    # Build identity groups from Unraid + TrueNAS-only.
    # Forward-synced TrueNAS copies are intentionally excluded — their Unraid
    # counterpart is already in the group and represents the same content.
    groups = defaultdict(list)
    unparsed_truenas = []
    unparsed_unraid = []

    for f in truenas_only_files:
        ident = extract(f.path)
        if ident is None:
            unparsed_truenas.append(f)
        else:
            groups[ident].append(f)

    for f in unraid_files:
        ident = extract(f.path)
        if ident is None:
            unparsed_unraid.append(f)
        else:
            groups[ident].append(f)

    # Apply rules per group
    all_deletions = []
    all_reasons = {}
    groups_with_deletions = 0

    for ident, files in groups.items():
        if len(files) < 2:
            continue
        keep, delete, reasons = decide(files)
        if delete:
            groups_with_deletions += 1
            all_deletions.extend(delete)
            all_reasons.update(reasons)
            if args.verbose:
                print(f"\nGroup {ident}:")
                for f in files:
                    marker = "DELETE" if f in delete else "KEEP"
                    reason = f" — {reasons.get(f.path, '')}" if f in delete else ""
                    print(f"  [{marker}] [{f.location}] [{f.res_label}] "
                          f"{f.size / 1024**3:6.2f}G {f.path}{reason}")

    # Report
    total_size = sum(f.size for f in all_deletions)
    print()
    print("=" * 78)
    print(f"Dedupe report — library: {args.library}")
    print("=" * 78)
    print(f"TrueNAS video files (total):    {len(truenas_files)}")
    print(f"  ...already synced to Unraid:  {truenas_synced_count}  (skipped — forward-sync copies)")
    print(f"  ...TrueNAS-only (analysed):   {len(truenas_only_files)}")
    print(f"Unraid video files:             {len(unraid_files)}")
    print(f"Identity groups (analysed):     {len(groups)}")
    print(f"Groups with deletions:          {groups_with_deletions}")
    print(f"Unparseable on TrueNAS:         {len(unparsed_truenas)}")
    print(f"Unparseable on Unraid:          {len(unparsed_unraid)}")
    print(f"Deletion candidates:            {len(all_deletions)}")
    print(f"Bytes to free:                  {total_size:,} ({total_size / 1024**3:.2f} GB)")
    print("=" * 78)

    if args.verbose and unparsed_truenas:
        print("\nUnparseable TrueNAS files (NOT deleted):")
        for f in unparsed_truenas[:20]:
            print(f"  {f.path}")
        if len(unparsed_truenas) > 20:
            print(f"  ... ({len(unparsed_truenas) - 20} more)")

    print("\nDeletion candidates (sorted by size, largest first):")
    for f in sorted(all_deletions, key=lambda x: -x.size):
        print(f"  {f.size / 1024**3:7.2f} GB  [{f.res_label}]  "
              f"{f.path}")
        print(f"             reason: {all_reasons.get(f.path, '')}")

    if args.apply:
        print()
        print("APPLY mode — deleting files now...")
        deleted = 0
        failed = []
        for f in all_deletions:
            try:
                os.remove(f.path)
                deleted += 1
            except OSError as e:
                failed.append((f.path, str(e)))
        print(f"Deleted: {deleted} / {len(all_deletions)}")
        if failed:
            print(f"Failed: {len(failed)}")
            for path, err in failed:
                print(f"  {path}: {err}", file=sys.stderr)
            sys.exit(2)
    else:
        print()
        print("DRY-RUN — no files were deleted.")
        print("Run again with --apply to execute deletions.")


if __name__ == '__main__':
    main()
