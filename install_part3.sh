#!/bin/bash
set -e

# Run this AFTER rebooting into the new system, logged in as your normal
# user (not root). It uses sudo internally where root is needed.

if [ "$EUID" -eq 0 ]; then
    echo "Error: do not run this script as root / with sudo."
    echo "Log in as your normal user and run it directly (./install_part3.sh)."
    exit 1
fi

echo "=== 1. Installing paru (AUR helper) ==="
if ! command -v paru &> /dev/null; then
    sudo pacman -S --needed --noconfirm rust
    TMP_DIR=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$TMP_DIR/paru"
    cd "$TMP_DIR/paru"
    makepkg -si --noconfirm
    cd -
    rm -rf "$TMP_DIR"
else
    echo "paru is already installed, skipping."
fi

echo "=== 2. Installing linux-cachyos kernel + NVIDIA open driver ==="
sudo pacman -Syu --noconfirm linux-cachyos linux-cachyos-headers linux-cachyos-nvidia-open

echo "=== 3. Enabling early KMS for the NVIDIA driver (initramfs) ==="
sudo sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
sudo mkinitcpio -P

echo "=== 4. Enabling nvidia-drm.modeset in GRUB ==="
if ! grep -q 'nvidia-drm.modeset=1' /etc/default/grub; then
    sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia-drm.modeset=1"/' /etc/default/grub
fi
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo "=== 5. Installing KDE Plasma, Dolphin, Bluetooth & WezTerm ==="
sudo pacman -S --noconfirm \
    plasma-desktop sddm plasma-nm plasma-pa kscreen powerdevil kde-cli-tools breeze \
    xdg-desktop-portal-kde pipewire pipewire-pulse pipewire-alsa wireplumber power-profiles-daemon \
    dolphin bluez bluez-utils bluedevil wezterm

sudo systemctl enable sddm
sudo systemctl enable power-profiles-daemon
sudo systemctl enable bluetooth

echo "=== 6. Installing Japanese fonts & Fcitx5 ==="
sudo pacman -S --noconfirm noto-fonts noto-fonts-cjk noto-fonts-emoji fcitx5 fcitx5-configtool

echo "=== 7. Configuring Fcitx5 Environment Variables ==="
# Set environment variables for Wayland / Desktop sessions
mkdir -p ~/.config/environment.d
cat << 'EOF' > ~/.config/environment.d/im.conf
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF

echo ""
echo "=== All done! Reboot to start KDE Plasma via SDDM. ==="
echo "Note: Fcitx5 is configured via environment variables. Add your preferred input engine via fcitx5-configtool after reboot."
