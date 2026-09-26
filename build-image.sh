#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-YOUSEF-Browser-OS.img}"
SIZE_MB="${SIZE_MB:-4096}"
ROOTFS="/tmp/yousef-rootfs"
MNT="/tmp/yousef-mnt"

export DEBIAN_FRONTEND=noninteractive

rm -rf "$ROOTFS" "$MNT" "$IMAGE"
mkdir -p "$ROOTFS" "$MNT"

apt-get update
apt-get install -y --no-install-recommends debootstrap parted e2fsprogs grub-pc-bin grub-common

debootstrap --arch=amd64 --variant=minbase bookworm "$ROOTFS" http://deb.debian.org/debian

mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount -t proc /proc "$ROOTFS/proc"
mount -t sysfs /sys "$ROOTFS/sys"
mount -t tmpfs tmpfs "$ROOTFS/run"

cat > "$ROOTFS/etc/apt/sources.list" <<'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
EOF

cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

chroot "$ROOTFS" apt-get update
chroot "$ROOTFS" apt-get install -y --no-install-recommends linux-image-amd64 grub-pc-bin grub-common systemd systemd-sysv dbus dbus-x11 sudo xorg xinit x11-xserver-utils openbox xterm firefox-esr network-manager network-manager-gnome ca-certificates curl fonts-dejavu fonts-noto-core locales

chroot "$ROOTFS" bash -c 'echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen'
chroot "$ROOTFS" bash -c 'echo "yousef-browser-os" > /etc/hostname'
cat > "$ROOTFS/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 yousef-browser-os
::1 localhost ip6-localhost ip6-loopback
EOF

# Create the dedicated browser user explicitly and fail if it cannot be created.
chroot "$ROOTFS" groupadd -f yousef
chroot "$ROOTFS" useradd -m -d /home/yousef -g yousef -s /bin/bash yousef
chroot "$ROOTFS" bash -c 'echo "yousef:yousef" | chpasswd'
chroot "$ROOTFS" usermod -aG sudo yousef

mkdir -p "$ROOTFS/home/yousef/.config/openbox" "$ROOTFS/etc/systemd/system"

cat > "$ROOTFS/home/yousef/.xinitrc" <<'EOF'
#!/bin/sh
xsetroot -solid black
exec openbox-session
EOF
chmod +x "$ROOTFS/home/yousef/.xinitrc"

cat > "$ROOTFS/home/yousef/.config/openbox/autostart" <<'EOF'
(sleep 4; firefox-esr --kiosk --private-window "https://www.google.com") &
EOF
chown -R yousef:yousef "$ROOTFS/home/yousef"

cat > "$ROOTFS/etc/systemd/system/browser-session.service" <<'EOF'
[Unit]
Description=YOUSEF Browser OS graphical browser session
After=network-online.target
Wants=network-online.target
Conflicts=getty@tty1.service

[Service]
User=yousef
WorkingDirectory=/home/yousef
Environment=HOME=/home/yousef
Environment=DISPLAY=:0
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty
StandardOutput=journal
StandardError=journal
ExecStart=/usr/bin/startx /home/yousef/.xinitrc -- :0 vt1 -nolisten tcp
Restart=always
RestartSec=3

[Install]
WantedBy=graphical.target
EOF

chroot "$ROOTFS" systemctl enable NetworkManager.service || true
chroot "$ROOTFS" systemctl enable browser-session.service || true
chroot "$ROOTFS" systemd-machine-id-setup || true
rm -f "$ROOTFS/etc/machine-id"

truncate -s "${SIZE_MB}M" "$IMAGE"
parted -s "$IMAGE" mklabel msdos
parted -s "$IMAGE" mkpart primary ext4 1MiB 100%
parted -s "$IMAGE" set 1 boot on

LOOP="$(losetup --find --show --partscan "$IMAGE")"
cleanup() {
  set +e
  umount -R "$ROOTFS/run" 2>/dev/null || true
  umount -R "$ROOTFS/sys" 2>/dev/null || true
  umount -R "$ROOTFS/proc" 2>/dev/null || true
  umount -R "$ROOTFS/dev/pts" 2>/dev/null || true
  umount -R "$ROOTFS/dev" 2>/dev/null || true
  umount "$MNT" 2>/dev/null || true
  losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

mkfs.ext4 -F -L YOUSEF_OS "${LOOP}p1"
mount "${LOOP}p1" "$MNT"
cp -a "$ROOTFS"/. "$MNT"/

mkdir -p "$MNT/boot/grub"
chroot "$MNT" grub-install --target=i386-pc --boot-directory=/boot "$LOOP"
chroot "$MNT" update-grub
chroot "$MNT" bash -c 'printf "YOUSEF Browser OS\\n" > /etc/issue'
sync
umount "$MNT"
e2fsck -fy "${LOOP}p1"
sync
losetup -d "$LOOP"
trap - EXIT
