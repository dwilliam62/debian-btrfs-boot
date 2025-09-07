## Name: debian-btrfs-boot.sh

## Author: Don Williams

## Created: 9/7/2025

## Purpose: To properly configure a debian 12 or 13 boot drive w/btrfs

```text
To be used during the install of debian 12/13 with GPT partition and UEFI After
user partitioned the drive in the GUI they will go to the CLI Curl/Wget this script to the
system being installed. The system must be at the point where the files systems
was created but before you start installing packages The script will unmount the current
@rootfs partition, move @root to @, create and mount btrfs subvolumes
```

## Use color coding and iconography to enhance appearance and highlight areas of > [!CAUTION]

## Create a detailed install log `install.DATE-TIME.log`

- Show the steps performed and their results
- When you read a file save the contents
- When you modify a file save the contents of that saved file
- When you run a command save the output to the log file

## Mandatory checks - Don't proceed if not met

```text
Debian 12 
Debian 13 
GPT partiton 
/cdrom 
BTRFS partion on / 
/target    @rootfs
/target/boot/efi  /boot/efi
```

## Final BTRFS layout after modifcations

```text
@                   /
@snapshots          /.snapshots 
@home               /home
@log                /var/logs
@var                /var/cache
```

## First determine the boot device and partitions

- Saved in:
- $BOOTDEVICE-P1 For first partition
- $BOOTDEVICE-P2 For 2nd partition
- $SWAPDEVICE If a swap partiton if found

```text
ie. 
/dev/sda1,/dev/sda2 
/dev/vda1,/dev/vda2
/dev/nvme0n1p1,/dev/nvmen1p2
```

- $BOOTDEVICE-P1 should currently mounted on /target/boot/efi
- $BOOTDEVICE-P2 should currently be mounted on /target

## Validate that the /etc/fstab is as expected

- Use flexible logic. As user can set additional flags in the debian installer
- I.e. ssd,or compress.
- If compression is set in the installer the flag changes to compress not
  compress=zstd
- Check for Linux swap if exists save swap info in $SWAPDEVICE

```text
Find the current UUID for $BOOTDEVICE-P2 /etc/fstab it will be 
UUID=XXXXXXXXXXXXXXX / btrfs defaults,subvol=#@rootfs 0 0 
Find the current UUID for $BOOTDEVICE-P1 it will be 
UUID=XXXXXXXXXXXXXXX /boot/efi   vfat  umask=0077   0  1
```

## If validations fail exit with error message

- Indicate what what checks failed
- cant find $BOOTDEVICE-P1
- cant find $BOOTDEVICE-P2
- Partitions not mounted
- Partitons not mounted where expected
- /etc/fstab not found
- /etc/fstab can't determine devices
- etc

## Print out results for confirmation

- Display current /etc/fstab in nice formatting
- Dispaly detected values for
- $BOOTDEVICE-P1
- $BOOTDEVICE-P2

## User must confirm before proceeding

- case sensitive `YES`
- otherwise exit `

## Unmount current $BOOTDEVICE-P1 and $BOOTDEVICE-P2

```text
umount /target/boot/efi
umount /target/
mmount $BOOTDEVICE-P1 /mnt
```

## Move @rootfs to @

```text
mv @rootfs @
```

## Create the btrfs subvolumes

```text
btrfs su cr @home 
btrfs su cr @snapshots 
btrfs su cr @log 
btrfs su cr @cache
```

## Final layout

```text
@                   /
@snapshots          /.snapshots 
@home               /home
@log                /var/log
@cache              /var/cache
```

## Subvolumes: Create btrfs subvolumes and mount them and /boot/efi

```text
mount -o noatime,compress=zstd,subvol=@ $BOOTDEVICE-P2 /target 
mkdir -p /target/boot/efi 
mkdir -p /target/home 
mkdir -p /target/.snapshots 
mkdir -p /target/var/log 
mkdir -p /target/var/cache 
mount -o noatime,compress=zstd,subvol=@home $BOOTDEVICE-P2 /target/home
mount -o noatime,compress=zstd,subvol=@snapshots $BOOTDEVICE-P2 /target/.snapshots
mount -o noatime,compress=zstd,subvol=@log $BOOTDEVICE-P2 /target/var/log
mount -o noatime,compress=zstd,subvol=@cache $BOOTDEVICE-P2 /target/var/cache
mount $BOOTDEVICE-P1 /target/boot/efi
```

## Find the current UUID for $BOOTDEVICE-P2 in /target/etc/fstb

```text
UUID=XXXXXXXXXXXXXXX / btrfs defaults,subvol=@rootfs 0 0
```

## Find the current UUID for $BOOTDEVICE-P1 in /target/etc/fstab

```text
UUID=XXXXXXXXXXXXXXX /boot/efi   vfat  umask=0077   0  1
```

## Backup the current /target/etc/fstab file /target/etc/fstab.date.time.backup

## Modify /target/etc/fstab

```text
UUID=XXXXXXXXXXXXXXX / btrfs noatime,compress=ztd,subvol=@ 0 1 
UUID=XXXXXXXXXXXXXXX /home btrfs noatime,compress=ztd,subvol=@home 0 2 
UUID=XXXXXXXXXXXXXXX /.snapshots btrfs noatime,compress=ztd,subvol=@snapshots 0 2 
UUID=XXXXXXXXXXXXXXX /var/log btrfs noatime,compress=ztd,subvol=@log 0 2 
UUID=XXXXXXXXXXXXXXX /var/cache btrfs noatime,compress=ztd,subvol=@cache 0 2
```

## Print out the modified /target/etc/fstab file

## User must confirm modifications are correct

- They must answer "Proceed"
- Case sensitive
- If incorrect print correct response "Proceed"
- on 2nd failure attempt
- Move the modified /target/etc/fstab to /target/etc/fstab.modified.date.time
- copy the backup /target/etc/fstab.date.time.backup to /target/etc/fstab
- Print "Reverting fstab file... "
- exit 1 back to shell
- On success print "Modifcation succesfull -- Press CTRL + ALT + F1 to return to
  installation"
- exit 0 back to shell
