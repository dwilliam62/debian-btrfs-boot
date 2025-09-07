#!/usr/bin/env bash
# Name: debian-btrfs-boot.sh
# Purpose: Configure Debian 12/13 target root on Btrfs with subvolumes during install
# Author: Don Williams (script implementation by Agent Mode)
# Created: 2025-09-07
# Usage: Run from Debian installer shell after partitions are created and /target is mounted.

set -Eeuo pipefail

# ========== Styling ==========
# ANSI colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

# Icons
ICON_OK="✅"
ICON_FAIL="❌"
ICON_WARN="⚠️ "
ICON_INFO="ℹ️ "
ICON_STEP="🛠️ "
ICON_ASK="❓"

TS() { date +"%Y-%m-%d_%H-%M-%S"; }
LOG_FILE="$(pwd)/install.$(TS).log"

log() {
  # log level, message
  local level="$1"; shift
  local msg="$*"
  # Strip ANSI for file log
  local plain
  plain="$(printf "%b" "$msg" | sed -E 's/\x1b\[[0-9;]*m//g')"
  printf "%s %s\n" "[$(date +"%F %T")]" "$plain" >>"$LOG_FILE"
  # Color to stdout
  case "$level" in
    INFO) printf "%b%s %s%b\n" "$CYAN" "$ICON_INFO" "$msg" "$RESET" ;;
    STEP) printf "%b%s %s%b\n" "$BLUE" "$ICON_STEP" "$msg" "$RESET" ;;
    WARN) printf "%b%s %s%b\n" "$YELLOW" "$ICON_WARN" "$msg" "$RESET" ;;
    OK)   printf "%b%s %s%b\n" "$GREEN" "$ICON_OK" "$msg" "$RESET" ;;
    FAIL) printf "%b%s %s%b\n" "$RED" "$ICON_FAIL" "$msg" "$RESET" ;;
    *)    printf "%s\n" "$msg" ;;
  esac
}

die() {
  log FAIL "$*"
  exit 1
}

confirm_exact() {
  # $1 prompt, $2 expected
  local prompt="$1"
  local expected="$2"
  printf "%b%s %s (type: %s)%b " "$MAGENTA" "$ICON_ASK" "$prompt" "$expected" "$RESET"
  read -r ans
  echo "$ans" >>"$LOG_FILE"
  [[ "$ans" == "$expected" ]]
}

# Defaults
DRY_RUN="false"
AUTO_YES="false"
TARGET_ROOT="/target"
TARGET_EFI="$TARGET_ROOT/boot/efi"
TOP_MNT="/mnt"

usage() {
  cat <<EOF
${BOLD}debian-btrfs-boot.sh${RESET}
Configure Btrfs subvolumes for Debian 12/13 during installation.

Options:
  --dry-run         Show what would happen without making changes (default: off)
  -y, --yes         Assume "YES" to proceed and "Proceed" to finalize
  --target PATH     Target root mount point (default: /target)
  --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN="true"; shift ;;
    -y|--yes)  AUTO_YES="true"; shift ;;
    --target)  TARGET_ROOT="${2:-/target}"; TARGET_EFI="$TARGET_ROOT/boot/efi"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "Unknown argument: $1" ;;
  esac
done

trap 'log WARN "Interrupted. You may need to remount $TARGET_ROOT and $TARGET_EFI manually."' INT TERM

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

log INFO "Logging to $LOG_FILE"

# Preflight
require_cmd awk
require_cmd sed
require_cmd grep
require_cmd blkid
require_cmd mount
require_cmd umount
require_cmd btrfs
require_cmd lsblk
require_cmd tee

[[ "$(id -u)" -eq 0 ]] || die "Must run as root"

[[ -d /cdrom ]] || die "/cdrom not found (are you in the Debian installer?)"
[[ -d "$TARGET_ROOT" ]] || die "$TARGET_ROOT not found"
[[ -f "$TARGET_ROOT/etc/fstab" ]] || die "$TARGET_ROOT/etc/fstab not found"

# Validate mountpoints
if ! mountpoint -q "$TARGET_ROOT"; then
  die "$TARGET_ROOT is not mounted"
fi
if ! mountpoint -q "$TARGET_EFI"; then
  die "$TARGET_EFI is not mounted"
fi

# Detect devices and fstype from /proc/mounts
ROOT_DEV=$(awk '$2==mp{print $1}' mp="$TARGET_ROOT" /proc/mounts | tail -n1)
EFI_DEV=$(awk '$2==mp{print $1}' mp="$TARGET_EFI" /proc/mounts | tail -n1)
ROOT_FSTYPE=$(awk '$2==mp{print $3}' mp="$TARGET_ROOT" /proc/mounts | tail -n1)
EFI_FSTYPE=$(awk '$2==mp{print $3}' mp="$TARGET_EFI" /proc/mounts | tail -n1)

[[ -n "$ROOT_DEV" ]] || die "Cannot determine device for $TARGET_ROOT"
[[ -n "$EFI_DEV" ]] || die "Cannot determine device for $TARGET_EFI"
[[ "$ROOT_FSTYPE" == "btrfs" ]] || die "Root at $TARGET_ROOT is not btrfs (got $ROOT_FSTYPE)"
[[ "$EFI_FSTYPE" == "vfat" || "$EFI_FSTYPE" == "fat32" ]] || log WARN "EFI fs is $EFI_FSTYPE (expected vfat)"

log INFO "Detected: ROOT_DEV=$ROOT_DEV ($ROOT_FSTYPE), EFI_DEV=$EFI_DEV ($EFI_FSTYPE)"

# Snapshot current fstab
log STEP "Reading existing $TARGET_ROOT/etc/fstab"
FSTAB_ORIG_CONTENT=$(cat "$TARGET_ROOT/etc/fstab")
printf "%s\n" "$FSTAB_ORIG_CONTENT" >>"$LOG_FILE"

# Extract existing specifiers and options
# Accept UUID=, PARTUUID=, LABEL=, /dev/...
get_field() { awk -v mp="$1" '($0 !~ /^#/ && NF>=2 && $2==mp){print $1; exit}' "$TARGET_ROOT/etc/fstab"; }
get_opts()  { awk -v mp="$1" '($0 !~ /^#/ && NF>=4 && $2==mp){print $4; exit}' "$TARGET_ROOT/etc/fstab"; }

ROOT_SPEC=$(get_field "/") || true
EFI_SPEC=$(get_field "/boot/efi") || true
ROOT_OPTS=$(get_opts "/") || true
EFI_OPTS=$(get_opts "/boot/efi") || true

[[ -n "$ROOT_SPEC" ]] || die "Could not find root (/) entry in fstab"
[[ -n "$EFI_SPEC" ]] || die "Could not find /boot/efi entry in fstab"

log INFO "fstab root spec: $ROOT_SPEC"
log INFO "fstab efi spec:  $EFI_SPEC"
log INFO "fstab root opts: ${ROOT_OPTS:-<none>}"

# Build base options for btrfs lines
# Remove any subvol= and compress*= to rebuild consistently, preserve others
clean_opts=$(printf "%s" "${ROOT_OPTS:-defaults}" | awk -F, '{
  for(i=1;i<=NF;i++){ if($i !~ /^subvol(=|id=)/ && $i !~ /^compress/){ o[oN++]=$i }}
  for(i=0;i<oN;i++){ printf i?","o[i]:o[i] }
}')
# Ensure noatime present
if [[ ",${clean_opts}," != *",noatime,"* ]]; then
  clean_opts="${clean_opts},noatime"
fi
# Choose compression: preserve if present else use compress=zstd
if [[ "${ROOT_OPTS:-}" =~ (^|,)compress[^,]* ]]; then
  comp_opt=$(printf "%s" "$ROOT_OPTS" | tr ',' '\n' | grep -E '^compress(=|$)' | head -n1)
else
  comp_opt="compress=zstd"
fi
BASE_BTRFS_OPTS=$(printf "%s,%s" "${clean_opts#,}" "$comp_opt" | sed 's/^,//;s/,,/,/g')

# Confirmation: show current state
log STEP "Planned Btrfs subvol layout:"
cat <<LAYOUT | tee -a "$LOG_FILE"
@            -> /
@home        -> /home
@snapshots   -> /.snapshots
@log         -> /var/log
@cache       -> /var/cache
LAYOUT

if [[ "$AUTO_YES" != "true" ]]; then
  printf "%b" "$YELLOW"
  if ! confirm_exact "About to unmount $TARGET_EFI and $TARGET_ROOT and modify subvolumes." "YES"; then
    printf "%b" "$RESET"; die "User aborted"
  fi
  printf "%b" "$RESET"
fi

# Back up fstab early
BACKUP_PATH="$TARGET_ROOT/etc/fstab.$(TS).backup"
log STEP "Backing up fstab to $BACKUP_PATH"
$DRY_RUN && log WARN "DRY-RUN: would copy $TARGET_ROOT/etc/fstab -> $BACKUP_PATH" || cp -a "$TARGET_ROOT/etc/fstab" "$BACKUP_PATH"

# Unmount target mounts
log STEP "Unmounting $TARGET_EFI and $TARGET_ROOT"
if $DRY_RUN; then
  log WARN "DRY-RUN: would umount $TARGET_EFI"
  log WARN "DRY-RUN: would umount $TARGET_ROOT"
else
  umount "$TARGET_EFI"
  umount "$TARGET_ROOT"
fi

# Mount top-level subvolume to manipulate subvolumes
log STEP "Mounting top-level subvolume (subvolid=5) at $TOP_MNT"
mkdir -p "$TOP_MNT"
if $DRY_RUN; then
  log WARN "DRY-RUN: would mount -o subvolid=5 $ROOT_DEV $TOP_MNT"
else
  mount -o subvolid=5 "$ROOT_DEV" "$TOP_MNT"
fi

# Rename @rootfs to @ if present
if $DRY_RUN; then
  log WARN "DRY-RUN: would check and rename $TOP_MNT/@rootfs -> $TOP_MNT/@ if needed"
else
  if [[ -d "$TOP_MNT/@rootfs" && ! -e "$TOP_MNT/@" ]]; then
    log STEP "Renaming @rootfs to @"
    mv "$TOP_MNT/@rootfs" "$TOP_MNT/@"
  else
    log INFO "@rootfs not present or @ already exists; skipping rename"
  fi
fi

# Create subvolumes idempotently
create_subvol() {
  local path="$1"
  if $DRY_RUN; then
    log WARN "DRY-RUN: would create subvolume $path if missing"
    return 0
  fi
  if [[ -d "$path" ]]; then
    log INFO "Subvolume already exists: $path"
  else
    log STEP "Creating subvolume: $path"
    btrfs subvolume create "$path"
  fi
}

create_subvol "$TOP_MNT/@"
create_subvol "$TOP_MNT/@home"
create_subvol "$TOP_MNT/@snapshots"
create_subvol "$TOP_MNT/@log"
create_subvol "$TOP_MNT/@cache"

# Unmount top-level
if $DRY_RUN; then
  log WARN "DRY-RUN: would umount $TOP_MNT"
else
  umount "$TOP_MNT"
fi

# Mount new layout under $TARGET_ROOT
mount_btrfs_subvol() {
  local sub="$1" mp="$2"
  local opts="$BASE_BTRFS_OPTS,subvol=$sub"
  if $DRY_RUN; then
    log WARN "DRY-RUN: would mount -o $opts $ROOT_DEV $mp"
  else
    mkdir -p "$mp"
    mount -o "$opts" "$ROOT_DEV" "$mp"
  fi
}

log STEP "Mounting new layout to $TARGET_ROOT"
if $DRY_RUN; then
  log WARN "DRY-RUN: would mount root @ to $TARGET_ROOT"
else
  mkdir -p "$TARGET_ROOT"
fi
mount_btrfs_subvol "@" "$TARGET_ROOT"
mkdir -p "$TARGET_EFI" "$TARGET_ROOT/home" "$TARGET_ROOT/.snapshots" "$TARGET_ROOT/var/log" "$TARGET_ROOT/var/cache"
mount_btrfs_subvol "@home" "$TARGET_ROOT/home"
mount_btrfs_subvol "@snapshots" "$TARGET_ROOT/.snapshots"
mount_btrfs_subvol "@log" "$TARGET_ROOT/var/log"
mount_btrfs_subvol "@cache" "$TARGET_ROOT/var/cache"

# Mount EFI back
if $DRY_RUN; then
  log WARN "DRY-RUN: would mount $EFI_DEV $TARGET_EFI"
else
  mount "$EFI_DEV" "$TARGET_EFI"
fi

# Construct new fstab content
log STEP "Constructing new fstab entries"
ROOT_SPEC_ESC=$(printf "%s" "$ROOT_SPEC")
BTRFS_ENTRIES=$(cat <<EOF
$ROOT_SPEC_ESC / btrfs $BASE_BTRFS_OPTS,subvol=@ 0 0
$ROOT_SPEC_ESC /home btrfs $BASE_BTRFS_OPTS,subvol=@home 0 0
$ROOT_SPEC_ESC /.snapshots btrfs $BASE_BTRFS_OPTS,subvol=@snapshots 0 0
$ROOT_SPEC_ESC /var/log btrfs $BASE_BTRFS_OPTS,subvol=@log 0 0
$ROOT_SPEC_ESC /var/cache btrfs $BASE_BTRFS_OPTS,subvol=@cache 0 0
EOF
)

# Filter out old root/home/.snapshots/var/log/var/cache entries; keep others (incl. EFI and swap)
FSTAB_NEW=$(awk 'BEGIN{skip["/"]=1;skip["/home"]=1;skip["/.snapshots"]=1;skip["/var/log"]=1;skip["/var/cache"]=1}
  /^#/ || NF==0 { print; next }
  { mp=$2 } (mp in skip){ next } { print }' "$TARGET_ROOT/etc/fstab")

FSTAB_FINAL="$FSTAB_NEW

# Added by debian-btrfs-boot.sh on $(TS)
$BTRFS_ENTRIES
"

log INFO "Proposed fstab changes:"
printf "%s\n" "$BTRFS_ENTRIES" | sed 's/^/  + /' | tee -a "$LOG_FILE"

# Write modified fstab to a temp file first
MODIFIED_PATH="$TARGET_ROOT/etc/fstab.modified.$(TS)"
if $DRY_RUN; then
  log WARN "DRY-RUN: would write modified fstab to $MODIFIED_PATH"
else
  printf "%s\n" "$FSTAB_FINAL" >"$MODIFIED_PATH"
fi

# Show modified fstab and confirm
if $DRY_RUN; then
  log WARN "DRY-RUN: skipping final confirmation and install of modified fstab"
  log OK "DRY-RUN complete. No changes were made."
  exit 0
fi

log STEP "Preview of modified fstab ($MODIFIED_PATH):"
if [[ -f "$MODIFIED_PATH" ]]; then
  sed 's/^/    /' "$MODIFIED_PATH" | tee -a "$LOG_FILE"
fi

if [[ "$AUTO_YES" != "true" ]]; then
  printf "%b" "$YELLOW"
  if ! confirm_exact "If this looks correct, type" "Proceed"; then
    printf "%b" "$RESET"
    # Revert
    REVERT_PATH="$TARGET_ROOT/etc/fstab.reverted.$(TS)"
    log WARN "Reverting to original fstab. Saving modified as $REVERT_PATH"
    mv "$MODIFIED_PATH" "$REVERT_PATH" || true
    cp -a "$BACKUP_PATH" "$TARGET_ROOT/etc/fstab"
    die "User aborted at final confirmation"
  fi
  printf "%b" "$RESET"
fi

# Install the modified fstab
log STEP "Installing modified fstab"
install -m 0644 "$MODIFIED_PATH" "$TARGET_ROOT/etc/fstab"
log OK "Modification successful. Press CTRL+ALT+F1 to return to the installer and continue."
exit 0

