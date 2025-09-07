## Name: debian-btrfs-boot.sh

## Author: Don Williams

## Created: 9/7/2025

## Purpose: Properly configure a Debian 12 or 13 boot drive with Btrfs subvolumes during install

```text
Use during the Debian 12/13 install with GPT partitioning and UEFI. After
partitioning the drive in the GUI, switch to the shell and fetch this script
(via curl or wget). Run it when filesystems are created and mounted (before
package installation). The script will unmount the current @rootfs, rename
@rootfs to @, create Btrfs subvolumes, remount them at the correct paths, and
update /target/etc/fstab.

Fetch commands (choose one):

```bash
# curl
curl -fsSL https://raw.githubusercontent.com/dwilliam62/debian-btrfs-boot/main/debian-btrfs-boot.sh -o debian-btrfs-boot.sh
chmod +x debian-btrfs-boot.sh

# wget
wget -qO debian-btrfs-boot.sh https://raw.githubusercontent.com/dwilliam62/debian-btrfs-boot/main/debian-btrfs-boot.sh
chmod +x debian-btrfs-boot.sh
```

Script links:
- Repo view: https://github.com/dwilliam62/debian-btrfs-boot/blob/main/debian-btrfs-boot.sh
- Raw file:  https://raw.githubusercontent.com/dwilliam62/debian-btrfs-boot/main/debian-btrfs-boot.sh
```

## Visuals
- Use color coding and icons to highlight steps, warnings, and confirmations.

## Detailed install log `install.DATE-TIME.log`
- Show steps performed and their results
- When you read a file, save the contents
- When you modify a file, save the resulting contents
- When you run a command, save the output to the log file

## Mandatory checks — Don’t proceed if not met
```text
Debian 12 or Debian 13 installer
GPT partitioning and UEFI firmware (/sys/firmware/efi present)
/cdrom exists (installer media)
Btrfs partition mounted at /target
EFI (vfat) mounted at /target/boot/efi
Initial root subvolume is @rootfs (if created by installer)
```

## Final Btrfs layout after modifications
```text
@            /
@snapshots   /.snapshots
@home        /home
@log         /var/log
@cache       /var/cache
```

## Determine the boot device and partitions
- Store detected devices in:
  - $BOOTDEVICE_P1 — EFI System Partition (first partition)
  - $BOOTDEVICE_P2 — Root partition (second partition)
  - $SWAPDEVICE    — If a swap partition is found

```text
e.g.
/dev/sda1, /dev/sda2
/dev/vda1, /dev/vda2
/dev/nvme0n1p1, /dev/nvme0n1p2
```

- $BOOTDEVICE_P1 should currently be mounted at /target/boot/efi
- $BOOTDEVICE_P2 should currently be mounted at /target

## Validate that /target/etc/fstab is as expected
- Use flexible logic; the installer may set additional flags (e.g., ssd, autodefrag, noatime)
- Enforce compression to compress=zstd (do not preserve a different compress value)
- Check for Linux swap; if present save specifier in $SWAPDEVICE

```text
Find the current specifier for / in /target/etc/fstab; typically it looks like:
UUID=XXXXXXXXXXXXXXX / btrfs defaults,subvol=@rootfs 0 0
Find the current specifier for /boot/efi; typically it looks like:
UUID=XXXXXXXXXXXXXXX /boot/efi vfat umask=0077 0 1
```

## If validations fail, exit with an error message
- Indicate which checks failed
  - can’t find $BOOTDEVICE_P1
  - can’t find $BOOTDEVICE_P2
  - partitions not mounted or mounted at unexpected paths
  - /target/etc/fstab not found
  - /target/etc/fstab cannot determine devices

## Print results for confirmation
- Display current /target/etc/fstab (nicely formatted)
- Display detected values for:
  - $BOOTDEVICE_P1
  - $BOOTDEVICE_P2

## User must confirm before proceeding
- Case-sensitive: the user must type `YES`
- Otherwise exit

## Unmount current $BOOTDEVICE_P1 and $BOOTDEVICE_P2
```bash
umount /target/boot/efi
umount /target
```

## Mount the Btrfs top-level and rename subvolumes
- Mount the top-level Btrfs (subvolid=5) to a work directory (e.g., /mnt)
- If @rootfs exists and @ does not, rename @rootfs to @

```bash
mount -o subvolid=5 $BOOTDEVICE_P2 /mnt
if [ -d /mnt/@rootfs ] && [ ! -e /mnt/@ ]; then
  mv /mnt/@rootfs /mnt/@
fi
umount /mnt
```

## Create the Btrfs subvolumes (idempotent)
```bash
mount -o subvolid=5 $BOOTDEVICE_P2 /mnt
btrfs subvolume create /mnt/@       || true
btrfs subvolume create /mnt/@home   || true
btrfs subvolume create /mnt/@snapshots || true
btrfs subvolume create /mnt/@log    || true
btrfs subvolume create /mnt/@cache  || true
umount /mnt
```

## Final layout
```text
@            /
@snapshots   /.snapshots
@home        /home
@log         /var/log
@cache       /var/cache
```

## Mount subvolumes and /boot/efi
```bash
mount -o noatime,compress=zstd,subvol=@ $BOOTDEVICE_P2 /target
mkdir -p /target/boot/efi /target/home /target/.snapshots /target/var/log /target/var/cache
mount -o noatime,compress=zstd,subvol=@home      $BOOTDEVICE_P2 /target/home
mount -o noatime,compress=zstd,subvol=@snapshots $BOOTDEVICE_P2 /target/.snapshots
mount -o noatime,compress=zstd,subvol=@log       $BOOTDEVICE_P2 /target/var/log
mount -o noatime,compress=zstd,subvol=@cache     $BOOTDEVICE_P2 /target/var/cache
mount $BOOTDEVICE_P1 /target/boot/efi
```

## Find current UUID/specifiers in /target/etc/fstab
```text
Root line example:
UUID=XXXXXXXXXXXXXXX / btrfs defaults,subvol=@rootfs 0 0
EFI line example:
UUID=XXXXXXXXXXXXXXX /boot/efi vfat umask=0077 0 1
```

## Back up /target/etc/fstab
- Save a timestamped backup: /target/etc/fstab.DATE.TIME.backup

## Modify /target/etc/fstab
- Replace root and related mountpoints with enforced compress=zstd and 0 0 pass fields
- Preserve other (non-subvol, non-compress) options such as ssd, noatime, autodefrag

```text
UUID=XXXXXXXXXXXXXXX /           btrfs noatime,compress=zstd,subvol=@          0 0
UUID=XXXXXXXXXXXXXXX /home       btrfs noatime,compress=zstd,subvol=@home      0 0
UUID=XXXXXXXXXXXXXXX /.snapshots btrfs noatime,compress=zstd,subvol=@snapshots 0 0
UUID=XXXXXXXXXXXXXXX /var/log    btrfs noatime,compress=zstd,subvol=@log       0 0
UUID=XXXXXXXXXXXXXXX /var/cache  btrfs noatime,compress=zstd,subvol=@cache     0 0
```

## Show the modified /target/etc/fstab and confirm
- The user must answer "Proceed" (case-sensitive) to apply changes
- On second failure attempt:
  - Move the modified file to /target/etc/fstab.modified.DATE.TIME
  - Restore from /target/etc/fstab.DATE.TIME.backup
  - Print "Reverting fstab file..." and exit 1
- On success print: "Modification successful — Press CTRL+ALT+F1 to return to the installer"
- Exit 0
