#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${IMAGE:-YOUSEF-Browser-OS.img}"
SIZE_MB="${SIZE_MB:-4096}"
ROOTFS="$(mktemp -d /tmp/yousef-rootfs.XXXXXX)"
MNT="$(mktemp -d /tmp/yousef-mnt.XXXXXX)"
LOOP=""

export DEBIAN_FRONTEND=noninteractive
cleanup() {
  set +e
  sync
  mountpoint -q "$MNT" && umount -R "$MNT"
  [ -n "$LOOP" ] && losetup -d "$LOOP"
  mountpoint -q "$ROOTFS/run" && umount -R "$ROOTFS/run"
  mountpoint -q "$ROOTFS/sys" && umount -R "$ROOTFS/sys"
  mountpoint -q "$ROOTFS/proc" && umount -R "$ROOTFS/proc"
  mountpoint -q "$ROOTFS/dev/pts" && umount -R "$ROOTFS/dev/pts"
  mountpoint -q "$ROOTFS/dev" && umount -R "$ROOTFS/dev"
  rm -rf "$ROOTFS" "$MNT"
}
trap cleanup EXIT

rm -f "$IMAGE"
apt-get update
apt-get install -y --no-install-recommends \
  debootstrap parted e2fsprogs dosfstools grub-pc-bin grub-common \
  linux-image-amd64

debootstrap --arch=amd64 --variant=minbase bookworm "$ROOTFS" https://deb.debian.org/debian

mkdir -p "$ROOTFS/dev/pts" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/run"
mount --rbind /dev "$ROOTFS/dev"
mount --make-rslave "$ROOTFS/dev"
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sysfs "$ROOTFS/sys"
mount -t tmpfs tmpfs "$ROOTFS/run"
cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

cat > "$ROOTFS/etc/apt/sources.list" <<'EOF'
deb https://deb.debian.org/debian bookworm main contrib non-free-firmware
deb https://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb https://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
EOF

chroot "$ROOTFS" apt-get update
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
  linux-image-amd64 grub-pc-bin grub-common systemd systemd-sysv dbus dbus-x11 \
  network-manager sudo passwd login locales ca-certificates xorg xinit \
  x11-xserver-utils openbox firefox-esr

# Create the account with explicit checks; do not rely on adduser defaults in a chroot.
chroot "$ROOTFS" groupadd --system yousef
chroot "$ROOTFS" useradd --create-home --home-dir /home/yousef --gid yousef --shell /bin/bash yousef
chroot "$ROOTFS" bash -c 'id yousef && echo "yousef:yousef" | chpasswd && usermod -aG sudo yousef'

chroot "$ROOTFS" bash -c 'printf "en_US.UTF-8 UTF-8\n" > /etc/locale.gen; locale-gen'
printf 'yousef-browser-os\n' > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 yousef-browser-os
::1 localhost ip6-localhost ip6-loopback
EOF

install -d -o yousef -g yousef "$ROOTFS/home/yousef/.config/openbox"
cat > "$ROOTFS/home/yousef/.xinitrc" <<'EOF'
#!/bin/sh
xsetroot -solid '#101820'
exec openbox-session
EOF
cat > "$ROOTFS/home/yousef/.config/openbox/autostart" <<'EOF'
(sleep 3; exec firefox-esr --kiosk --private-window 'https://www.google.com') &
EOF
chmod +x "$ROOTFS/home/yousef/.xinitrc"
chroot "$ROOTFS" chown -R yousef:yousef /home/yousef

cat > "$ROOTFS/etc/systemd/system/browser-session.service" <<'EOF'
[Unit]
Description=YOUSEF Browser OS graphical browser session
After=network-online.target systemd-user-sessions.service
Wants=network-online.target
Conflicts=getty@tty1.service

[Service]
User=yousef
WorkingDirectory=/home/yousef
Environment=HOME=/home/yousef
Environment=DISPLAY=:0
TTYPath=/dev/tty1
StandardInput=tty
StandardOutput=journal
StandardError=journal
ExecStart=/usr/bin/startx /home/yousef/.xinitrc -- :0 vt1 -nolisten tcp
Restart=always
RestartSec=3

[Install]
WantedBy=graphical.target
EOF
chroot "$ROOTFS" systemctl enable NetworkManager.service
chroot "$ROOTFS" systemctl enable browser-session.service
chroot "$ROOTFS" systemd-machine-id-setup
rm -f "$ROOTFS/etc/machine-id"

truncate -s "${SIZE_MB}M" "$IMAGE"
parted -s "$IMAGE" mklabel msdos
parted -s "$IMAGE" mkpart primary ext4 1MiB 100%
parted -s "$IMAGE" set 1 boot on
LOOP="$(losetup --find --show --partscan "$IMAGE")"
udevadm settle
mkfs.ext4 -F -L YOUSEF_OS "${LOOP}p1"
mount "${LOOP}p1" "$MNT"
cp -a "$ROOTFS"/. "$MNT"/

# Install legacy BIOS GRUB into the image, not into the runner.
mkdir -p "$MNT/boot/grub"
grub-install --target=i386-pc --boot-directory="$MNT/boot" "$LOOP"
chroot "$MNT" update-grub
printf 'YOUSEF Browser OS\n' > "$MNT/etc/issue"
sync
umount "$MNT"
e2fsck -fy "${LOOP}p1"
losetup -d "$LOOP"
LOOP=""
