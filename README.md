# YOUSEF Browser OS

A clean browser-only x86_64 operating system built from Debian Bookworm for UTM SE.

## Target
- x86_64 / Intel PC emulation
- Legacy BIOS + GRUB
- Raw bootable `YOUSEF-Browser-OS.img`
- Firefox ESR kiosk mode
- Openbox + Xorg
- NetworkManager
- 2 GB RAM recommended minimum in UTM SE

## Build
GitHub Actions builds and validates:
- `YOUSEF-Browser-OS.img`
- `YOUSEF-Browser-OS.img.sha256`

## UTM SE
- Architecture: x86_64
- CPU: 2 cores
- RAM: 2048 MB
- Boot: BIOS
- Storage: attach the IMG as the main disk
- Network: Shared/NAT
