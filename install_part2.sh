#!/bin/bash
set -e

echo "=== 6. Post-chroot configuration ==="
# Timezone
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc

# Locale (automated edit)
sed -i 's/#ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=ja_JP.UTF-8" > /etc/locale.conf

# Hostname (variable is NEW_HOSTNAME; HOSTNAME is a bash special variable, avoid it)
echo "$NEW_HOSTNAME" > /etc/hostname

# Generate /etc/hosts (loopback addresses)
cat << EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $NEW_HOSTNAME.localdomain   $NEW_HOSTNAME
EOF

# Set passwords (values passed in from part1)
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/zsh "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Enable wheel group in sudoers
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "=== 7. Adding CachyOS repo and kernel ==="
cd /tmp
# NOTE: the original URL (https://cachyos.org) only returns the homepage HTML
# and cannot be extracted as a tarball. Use the correct mirror tarball URL.
curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz && cd cachyos-repo
# already root inside chroot, so sudo is not needed
./cachyos-repo.sh
# NOTE: install the NVIDIA driver afterward with pacman as needed.
# Once installed, add nvidia-drm.modeset=1 to GRUB_CMDLINE_LINUX_DEFAULT
# in /etc/default/grub and re-run grub-mkconfig -o /boot/grub/grub.cfg.

echo "=== 8. Installing bootloader ==="
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "=== 9. Network configuration ==="
pacman -S --noconfirm networkmanager
systemctl enable NetworkManager

exit 0
