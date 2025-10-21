# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Overview

Single-file POSIX shell project for configuring Debian Installer targets to use Btrfs subvolumes. Entry point: `debian-btrfs-boot.sh`. Documentation: `README.md` (EN) and `README.es.md` (ES).

Key assumptions (from README):
- UEFI firmware with GPT partitioning
- Debian 12/13 installer environment with `/cdrom` present
- Target root mounted at `/target` (Btrfs) and EFI at `/target/boot/efi` (vfat)
- Single root partition (no separate root/home/var) and no swap

## Common commands

Lint (recommended in CONTRIBUTING):
- shellcheck: `shellcheck ./debian-btrfs-boot.sh`

Script usage (run inside Debian installer shell):
- Help: `./debian-btrfs-boot.sh --help`
- Dry run (no changes): `./debian-btrfs-boot.sh --dry-run`
- Interactive apply (double confirmation): `./debian-btrfs-boot.sh`
- Non-interactive: `./debian-btrfs-boot.sh -y`

Logs:
- Writes `install.YYYY-MM-DD_HH-MM-SS.log` to the current working directory; on success (non-dry-run) copies the log to `/target/root/`.

Notes:
- There is no build step and no test suite configured.

## Architecture and flow

High-level flow (single script):
1) CLI parsing and defaults
- Flags: `--dry-run`, `-y|--yes`, `--target PATH`, `--help`

2) Safety and environment checks
- Requires root, `/cdrom`, `awk/sed/grep/mount/umount/btrfs` present
- Ensures `/target` and `/target/boot/efi` are mounted; detects devices and fstypes from `/proc/mounts` (expects `btrfs` for root, `vfat` for EFI)

3) fstab read and option normalization
- Reads `/target/etc/fstab`; extracts root and EFI specifiers and options
- Builds base Btrfs options by preserving non-subvol/non-compress flags, ensuring `noatime`, and forcing `compress=zstd`

4) User confirmation gates
- Prompts for exact `YES` before unmounting; later prompts for `Proceed` before installing the modified fstab (skipped with `-y`)

5) Subvolume operations (via mounting top-level `subvolid=5`)
- Idempotently rename `@rootfs` → `@` if present
- Ensure `@`, `@home`, `@snapshots`, `@log`, `@cache` exist

6) Remount new layout and rebuild fstab
- Mounts: `@`→`/`, `@home`→`/home`, `@snapshots`→`/.snapshots`, `@log`→`/var/log`, `@cache`→`/var/cache`
- Re-mounts EFI; filters old entries for these mountpoints; appends new Btrfs entries with consistent options and `0 0` fsck fields

7) Install and logging
- Writes preview to `fstab.modified.TIMESTAMP`, shows diff-like additions, then installs as `/target/etc/fstab`
- Copies the installer log into the target root on success

Core helpers and behaviors:
- Colored `log` with levels (INFO/STEP/WARN/OK/FAIL) and emoji; all actions mirrored to the log file
- `confirm_exact` for explicit typed confirmations
- `create_subvol` and `mount_btrfs_subvol` encapsulate Btrfs operations, honoring `--dry-run`
- Traps interrupts and warns about remounting if needed

## Files of interest
- `debian-btrfs-boot.sh` — the script (POSIX `/bin/sh`)
- `README.md` / `README.es.md` — usage, assumptions, and quick-start
- `img/` — screenshots referenced by the README
- `CONTRIBUTING.md` — requests that changes run clean under `shellcheck`

## Development notes for agents
- Prefer proposing changes that preserve the script’s idempotency, explicit confirmations, and logging conventions
- Keep option handling consistent: preserve existing non-subvol/non-compress options, ensure `noatime`, enforce `compress=zstd`
- Any edits that alter mount layout or fstab filtering should be explained in PRs and validated against the described flow above
