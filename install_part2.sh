#!/bin/bash
set -e

echo "=== 6. chroot後の設定 ==="
# タイムゾーン
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc

# ロケール自動編集
sed -i 's/#ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=ja_JP.UTF-8" > /etc/locale.conf

# ホスト名(変数名はNEW_HOSTNAME。HOSTNAMEはbashの特殊変数のため使用しない)
echo "$NEW_HOSTNAME" > /etc/hostname

# /etc/hosts の自動生成(ループバックアドレスの設定)
cat << EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $NEW_HOSTNAME.localdomain   $NEW_HOSTNAME
EOF

# パスワード設定(part1から引き継いだ値を使用)
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/zsh "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# visudoの自動解放(wheelグループ)
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "=== 7. CachyOSリポジトリとカーネルの追加 ==="
cd /tmp
# 【修正】元のURL(https://cachyos.org)はトップページのHTMLしか返らず、
# tarファイルとして展開できない。正しいミラーのtarball URLに変更。
curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz
tar xvf cachyos-repo.tar.xz && cd cachyos-repo
# chroot内はすでにrootなのでsudoは不要
./cachyos-repo.sh
# ※NVIDIAドライバはこの後、必要なパッケージを別途 pacman -S で入れてください。
#   導入後は /etc/default/grub の GRUB_CMDLINE_LINUX_DEFAULT に
#   nvidia-drm.modeset=1 を追記し、grub-mkconfig -o /boot/grub/grub.cfg を再実行してください。

echo "=== 8. ブートローダーのインストール ==="
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "=== 9. ネットワーク設定 ==="
pacman -S --noconfirm networkmanager
systemctl enable NetworkManager

exit 0
