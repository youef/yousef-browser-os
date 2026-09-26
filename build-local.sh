#!/usr/bin/env bash
# YOUSEF Browser OS - Complete standalone build script
# Run: sudo bash build-local.sh

set -Eeuo pipefail

IMAGE="${IMAGE:-YOUSEF-Browser-OS.img}"
SIZE_MB="${SIZE_MB:-4096}"
ROOTFS="/tmp/yousef-rootfs-$$"
MNT="/tmp/yousef-mnt-$$"
LOOP=""

echo "=== YOUSEF Browser OS Builder ==="
echo "Target: $IMAGE (${SIZE_MB}MB)"
echo "Root: $ROOTFS"
echo ""

# Cleanup trap
cleanup() {
  set +e
  echo "Cleaning up..."
  sync
  [ -d "$MNT" ] && mountpoint -q "$MNT" && umount -R "$MNT" 2>/dev/null || true
  [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null || true
  [ -d "$ROOTFS" ] && mountpoint -q "$ROOTFS/run" && umount -R "$ROOTFS/run" 2>/dev/null || true
  [ -d "$ROOTFS" ] && mountpoint -q "$ROOTFS/sys" && umount -R "$ROOTFS/sys" 2>/dev/null || true
  [ -d "$ROOTFS" ] && mountpoint -q "$ROOTFS/proc" && umount -R "$ROOTFS/proc" 2>/dev/null || true
  [ -d "$ROOTFS" ] && mountpoint -q "$ROOTFS/dev" && umount -R "$ROOTFS/dev" 2>/dev/null || true
  rm -rf "$ROOTFS" "$MNT"
  echo "Cleanup complete."
}
trap cleanup EXIT

# Check if running as root
if [ "$(id -u)" != "0" ]; then
  echo "ERROR: This script must run as root"
  exit 1
fi

# Step 1: Install build tools
echo "[1/10] Installing build tools..."
apt-get update >/dev/null 2>&1
apt-get install -y --no-install-recommends \
  debootstrap parted e2fsprogs grub-pc-bin grub-common \
  >/dev/null 2>&1

# Step 2: Create directories
echo "[2/10] Creating temporary directories..."
mkdir -p "$ROOTFS" "$MNT"

# Step 3: Bootstrap Debian Bookworm
echo "[3/10] Bootstrapping Debian Bookworm (this may take a few minutes)..."
debootstrap --arch=amd64 --variant=minbase bookworm "$ROOTFS" \
  https://deb.debian.org/debian >/dev/null 2>&1

# Step 4: Mount filesystems
echo "[4/10] Mounting filesystems..."
mkdir -p "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/run"
mount --rbind /dev "$ROOTFS/dev"
mount --make-rslave "$ROOTFS/dev"
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sysfs "$ROOTFS/sys"
mount -t tmpfs tmpfs "$ROOTFS/run"
cp -L /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

# Step 5: Configure APT sources
echo "[5/10] Configuring package repositories..."
rm -f "$ROOTFS/etc/apt/sources.list.d/"*.list 2>/dev/null || true
cat > "$ROOTFS/etc/apt/sources.list" <<'SOURCES'
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
SOURCES

# Step 6: Install packages
echo "[6/10] Installing system packages (this may take several minutes)..."
chroot "$ROOTFS" bash -c 'apt-get clean && rm -rf /var/lib/apt/lists/* && apt-get update' >/dev/null 2>&1
chroot "$ROOTFS" apt-get install -y --no-install-recommends \
  linux-image-amd64 grub-pc-bin grub-common systemd systemd-sysv dbus dbus-x11 \
  network-manager sudo passwd login locales ca-certificates xorg xinit \
  x11-xserver-utils openbox firefox-esr \
  >/dev/null 2>&1

# Step 7: Configure system
echo "[7/10] Configuring system..."
chroot "$ROOTFS" groupadd --system yousef || true
chroot "$ROOTFS" useradd --create-home --home-dir /home/yousef --gid yousef --shell /bin/bash yousef || true
chroot "$ROOTFS" bash -c 'echo "yousef:yousef" | chpasswd'
chroot "$ROOTFS" usermod -aG sudo yousef
chroot "$ROOTFS" bash -c 'printf "en_US.UTF-8 UTF-8\n" > /etc/locale.gen && locale-gen' >/dev/null 2>&1
printf 'yousef-browser-os\n' > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" <<'HOSTS'
127.0.0.1 localhost
127.0.1.1 yousef-browser-os
::1 localhost ip6-localhost ip6-loopback
HOSTS

# Step 8: Configure user and desktop
echo "[8/10] Setting up desktop environment..."
mkdir -p "$ROOTFS/home/yousef/.config/openbox"
cat > "$ROOTFS/home/yousef/.xinitrc" <<'XINITRC'
#!/bin/sh
xsetroot -solid '#101820'
exec openbox-session
XINITRC
cat > "$ROOTFS/home/yousef/.config/openbox/autostart" <<'AUTOSTART'
(sleep 3; firefox-esr --kiosk --private-window 'https://www.google.com') &
AUTOSTART
chmod +x "$ROOTFS/home/yousef/.xinitrc"
chroot "$ROOTFS" chown -R yousef:yousef /home/yousef

# Step 9: Create systemd service
echo "[9/10] Creating system services..."
cat > "$ROOTFS/etc/systemd/system/browser-session.service" <<'SERVICE'
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
SERVICE
chroot "$ROOTFS" systemctl enable NetworkManager.service >/dev/null 2>&1
chroot "$ROOTFS" systemctl enable browser-session.service >/dev/null 2>&1
chroot "$ROOTFS" systemd-machine-id-setup || true
rm -f "$ROOTFS/etc/machine-id"

# Step 10: Create disk image
echo "[10/10] Creating bootable disk image..."
truncate -s "${SIZE_MB}M" "$IMAGE"
parted -s "$IMAGE" mklabel msdos
parted -s "$IMAGE" mkpart primary ext4 1MiB 100%
parted -s "$IMAGE" set 1 boot on

LOOP="$(losetup --find --show --partscan "$IMAGE")"
udevadm settle

mkfs.ext4 -F -L YOUSEF_OS "${LOOP}p1"
mount "${LOOP}p1" "$MNT"
cp -a "$ROOTFS"/. "$MNT"/ 2>/dev/null || true

mkdir -p "$MNT/boot/grub"
grub-install --target=i386-pc --boot-directory="$MNT/boot" "$LOOP" >/dev/null 2>&1
chroot "$MNT" update-grub >/dev/null 2>&1
printf 'YOUSEF Browser OS\n' > "$MNT/etc/issue"

sync
umount "$MNT"
e2fsck -fy "${LOOP}p1" >/dev/null 2>&1
losetup -d "$LOOP"
LOOP=""

echo ""
echo "=== SUCCESS ==="
echo "✓ Image created: $IMAGE"
ls -lh "$IMAGE"
sha256sum "$IMAGE" | tee "${IMAGE}.sha256"
echo ""
echo "=== UTM SE Configuration ==="
echo "Architecture: x86_64"
echo "Firmware: BIOS (not UEFI)"
echo "CPU: 2 cores"
echo "RAM: 2048 MB or more"
echo "Boot: Attach $IMAGE as primary disk"
echo ""
echo "=== Login ==="
echo "User: yousef"
echo "Password: yousef"
echo ""
