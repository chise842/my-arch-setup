#!/bin/bash
set -e

# === ディスクとCPUの設定(ここだけ環境に合わせて確認) ===
TARGET_DISK="/dev/sda"
EFI_PART="${TARGET_DISK}1"
MAIN_PART="${TARGET_DISK}2"
UCODE_PKG="intel-ucode" # AMDなら amd-ucode に変更
# ========================================================

echo "=========================================="
echo "   Arch Linux 自動セットアップ (対話版)   "
echo "=========================================="

# ユーザー名・ホスト名の入力(英小文字チェック付き)
while true; do
    read -p "作成する一般ユーザー名を入力 (英小文字のみ): " USERNAME
    if [[ "$USERNAME" =~ ^[a-z0-9_-]+$ ]]; then break; fi
    echo "エラー: ユーザー名は英小文字、数字、ハイフン、アンダースコアのみ使用できます。"
done

# 【修正】変数名を HOSTNAME から NEW_HOSTNAME に変更。
# HOSTNAME はbashの特殊変数(組み込みのシェル変数)なので、
# 上書きしてもchroot先の新しいbashプロセス起動時に無視・再設定される可能性がある。
read -p "PCの名前 (ホスト名) を入力: " NEW_HOSTNAME

# パスワードの入力(入力中の文字を非表示にする -s オプション)
echo ""
while true; do
    read -s -p "Root (最高管理者) のパスワードを入力: " ROOT_PASSWORD
    echo ""
    read -s -p "Root パスワードの再入力 (確認): " ROOT_PASSWORD_CONF
    echo ""
    if [ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONF" ] && [ -n "$ROOT_PASSWORD" ]; then break; fi
    echo "エラー: パスワードが一致しないか、空欄です。もう一度入力してください。"
done

while true; do
    read -s -p "一般ユーザー ($USERNAME) のパスワードを入力: " USER_PASSWORD
    echo ""
    read -s -p "一般ユーザー パスワードの再入力 (確認): " USER_PASSWORD_CONF
    echo ""
    if [ "$USER_PASSWORD" = "$USER_PASSWORD_CONF" ] && [ -n "$USER_PASSWORD" ]; then break; fi
    echo "エラー: パスワードが一致しないか、空欄です。もう一度入力してください。"
done

echo ""
echo "設定の入力が完了しました。セットアップを開始します。"
echo "------------------------------------------"

echo "=== 1. パーティション作成(cfdiskを起動します。手動設定後、Writeして終了してください) ==="
cfdisk "$TARGET_DISK"

echo "=== 2. フォーマット ==="
mkfs.vfat -F32 "$EFI_PART"
mkfs.btrfs -f "$MAIN_PART"

echo "=== 3. Btrfsサブボリューム作成 ==="
mount "$MAIN_PART" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
umount /mnt

echo "=== 4. マウント ==="
mount -o noatime,compress=zstd:1,subvol=@ "$MAIN_PART" /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache/pacman/pkg}

mount -o noatime,compress=zstd:1,subvol=@home "$MAIN_PART" /mnt/home
mount -o noatime,compress=zstd:1,subvol=@log "$MAIN_PART" /mnt/var/log
mount -o noatime,compress=zstd:1,subvol=@pkg "$MAIN_PART" /mnt/var/cache/pacman/pkg
mount "$EFI_PART" /mnt/boot

echo "=== 5. ベースシステムのインストール ==="
pacstrap -K /mnt base base-devel linux linux-firmware btrfs-progs $UCODE_PKG nano neovim zsh git sudo

echo "=== 6. genfstabの生成 ==="
genfstab -U /mnt >> /mnt/etc/fstab

# 【修正】変数をコマンドライン文字列に直接埋め込むと、パスワードに ' や " が
# 含まれていた場合にスクリプトが壊れたり意図しない実行をされる恐れがある。
# そのためchroot先に一時ファイルとして安全にエクスポートし、それをsourceする方式に変更。
mkdir -p /mnt/root
{
    printf 'export NEW_HOSTNAME=%q\n' "$NEW_HOSTNAME"
    printf 'export USERNAME=%q\n' "$USERNAME"
    printf 'export ROOT_PASSWORD=%q\n' "$ROOT_PASSWORD"
    printf 'export USER_PASSWORD=%q\n' "$USER_PASSWORD"
} > /mnt/root/.install_env
chmod 600 /mnt/root/.install_env

cp install_part2.sh /mnt/install_part2.sh
chmod +x /mnt/install_part2.sh

echo "=== chroot環境に移行して自動セットアップを続行します ==="
arch-chroot /mnt /usr/bin/bash -c "source /root/.install_env && rm -f /root/.install_env && /install_part2.sh"

# 後片付けと再起動
rm -f /mnt/install_part2.sh /mnt/root/.install_env
echo "=== すべての工程が完了しました!アンマウントして再起動します ==="
umount -R /mnt
reboot
