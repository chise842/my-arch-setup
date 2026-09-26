#!/bin/bash
set -e

# === Disk and CPU settings (check/edit these for your environment) ===
TARGET_DISK="/dev/sda"
EFI_PART="${TARGET_DISK}1"
MAIN_PART="${TARGET_DISK}2"
UCODE_PKG="intel-ucode" # change to amd-ucode if using AMD
# ========================================================

echo "=========================================="
echo "   Arch Linux Automated Setup (interactive)   "
echo "=========================================="

# Username / hostname input (with lowercase check)
while true; do
    read -p "Enter the username to create (lowercase letters only): " USERNAME
    if [[ "$USERNAME" =~ ^[a-z0-9_-]+$ ]]; then break; fi
    echo "Error: username may only contain lowercase letters, digits, hyphens, and underscores."
done

# NOTE: using NEW_HOSTNAME instead of HOSTNAME on purpose.
# HOSTNAME is a bash special/builtin variable, so it may get
# reset or ignored when a new bash process starts inside arch-chroot.
read -p "Enter the hostname (PC name): " NEW_HOSTNAME

# Password input (-s hides typed characters)
echo ""
while true; do
    read -s -p "Enter the root password: " ROOT_PASSWORD
    echo ""
    read -s -p "Re-enter the root password (confirm): " ROOT_PASSWORD_CONF
    echo ""
    if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONF" ] && [ -n "$ROOT_PASSWORD" ]; then break; fi
    echo "Error: passwords do not match or are empty. Please try again."
done

while true; do
    read -s -p "Enter the password for user ($USERNAME): " USER_PASSWORD
    echo ""
    read -s -p "Re-enter the user password (confirm): " USER_PASSWORD_CONF
    echo ""
    if [ "$USER_PASSWORD" = "$USER_PASSWORD_CONF" ] && [ -n "$USER_PASSWORD" ]; then break; fi
    echo "Error: passwords do not match or are empty. Please try again."
done

echo ""
echo "Input complete. Starting setup."
echo "------------------------------------------"

echo "=== 1. Partitioning (cfdisk will open. After manual setup, Write and quit) ==="
cfdisk "$TARGET_DISK"

echo "=== 2. Formatting ==="
mkfs.vfat -F32 "$EFI_PART"
mkfs.btrfs -f "$MAIN_PART"

echo "=== 3. Creating Btrfs subvolumes ==="
mount "$MAIN_PART" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
umount /mnt

echo "=== 4. Mounting ==="
mount -o noatime,compress=zstd:1,subvol=@ "$MAIN_PART" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg}

mount -o noatime,compress=zstd:1,subvol=@home "$MAIN_PART" /mnt/home
mount -o noatime,compress=zstd:1,subvol=@log "$MAIN_PART" /mnt/var/log
mount -o noatime,compress=zstd:1,subvol=@pkg "$MAIN_PART" /mnt/var/cache/pacman/pkg
mount "$EFI_PART" /mnt/boot

echo "=== 5. Installing base system ==="
pacstrap -K /mnt base base-devel linux linux-firmware btrfs-progs $UCODE_PKG nano neovim zsh git sudo

echo "=== 6. Generating fstab ==="
genfstab -U /mnt >> /mnt/etc/fstab

# NOTE: embedding variables directly into a command-line string is risky —
# if a password contains a quote character it can break the script or
# behave unexpectedly. Instead, write them safely to a temp file inside
# the chroot and source it there.
mkdir -p /mnt/root
{
    printf 'export NEW_HOSTNAME=%q\n' "$NEW_HOSTNAME"
    printf 'export USERNAME=%q\n' "$USERNAME"
    printf 'export ROOT_PASSWORD=%q\n' "$ROOT_PASSWORD"
    printf 'export USER_PASSWORD=%q\n' "$USER_PASSWORD"
} > /mnt/root/.install_env
chmod 600 /mnt/root/.install_env

# Fetch install_part2.sh directly from GitHub instead of a local copy
curl -fsSL "https://raw.githubusercontent.com/chise842/my-arch-setup/main/install_part2.sh" -o /mnt/install_part2.sh
chmod +x /mnt/install_part2.sh

echo "=== Entering chroot to continue automated setup ==="
arch-chroot /mnt /usr/bin/bash -c "source /root/.install_env && rm -f /root/.install_env && /install_part2.sh"

# Cleanup and reboot
rm -f /mnt/install_part2.sh /mnt/root/.install_env
echo "=== All steps complete! Unmounting and rebooting ==="
umount -R /mnt
reboot
