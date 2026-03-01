# scripts

A collection of Gentoo Linux administration helper scripts.

---

## gentoo-tools.sh

An interactive, color-coded bash menu with helpful Gentoo system management tools.

### Run

```bash
sudo bash gentoo-tools.sh
```

> Most options require root. Run with `sudo` or as root.

### Menu options

| # | Name | What it does |
|---|------|--------------|
| 1 | **Configure make.conf** | Installs `cpuid2cpuflags` if missing, detects CPU flags, writes `CPU_FLAGS_X86`, `COMMON_FLAGS`, `MAKEOPTS` (via `nproc`), `EMERGE_DEFAULT_OPTS`, `PORTAGE_NICENESS`, and `FEATURES` into `/etc/portage/make.conf`. Existing keys are updated in-place; a timestamped backup is made first. |
| 2 | **Generate /etc/fstab** | Scans mounted real block devices, resolves UUIDs via `blkid`, writes `/etc/fstab` with per-filesystem optimal mount options (e.g. `noatime,compress=zstd:1` for btrfs, `noatime,errors=remount-ro` for root ext4). Appends a `/tmp` tmpfs entry. |
| 3 | **Full world rebuild & cleanup** | Runs: `emerge --sync` → `emaint sync --auto` → `emerge -uDN --with-bdeps=y @world` → `@preserved-rebuild` → `depclean` → `revdep-rebuild` → `perl-cleaner` (if present) → `dispatch-conf`. Pauses on each failure. |
| 4 | **Bootloader info** | Detects UEFI vs BIOS, identifies installed bootloader (GRUB 2, systemd-boot, rEFInd, syslinux, LILO), lists relevant config files and directories, and shows `efibootmgr` entries when on EFI. |
| 5 | **Kernel info** | Shows running kernel (`uname`), kernel images and initramfs in `/boot`, all source trees in `/usr/src` (highlights the active symlink), active `.config` path, and top 20 loaded modules by reference count. |
| 0 | **Exit** | Quit. |

### Dependencies

- Standard Gentoo base system (`bash`, `blkid`, `findmnt`, `lsblk`, `lsmod`)
- `app-portage/cpuid2cpuflags` — installed automatically by option 1 if missing
- `sys-boot/efibootmgr` — optional, used by option 4 on EFI systems
- `app-portage/gentoolkit` (`revdep-rebuild`) — used by option 3

---

## crux-tools.sh

The same interactive, color-coded bash menu adapted for **CRUX Linux** — using `prt-get`, `pkgmk`, `ports`, and CRUX-specific conventions throughout.

### Run

```bash
sudo bash crux-tools.sh
```

### Menu options

| # | Name | What it does |
|---|------|--------------|
| 1 | **Configure pkgmk.conf** | Sets `CFLAGS="-O2 -march=native -pipe"`, `CXXFLAGS="$CFLAGS"`, `MAKEFLAGS="-j$(nproc)"` in `/etc/pkgmk.conf`. Auto-selects `zst` compression if `zstd` is present, otherwise `xz`. Existing keys are updated in-place; a timestamped backup is made first. |
| 2 | **Generate /etc/fstab** | Same UUID + optimal-options generation as gentoo-tools.sh — scans real block devices, applies per-filesystem mount flags, appends a `/tmp` tmpfs entry. |
| 3 | **Full system upgrade & cleanup** | Runs: `ports -u` (sync all collections) → shows `prt-get diff` → `prt-get sysup` → `revdep` check with optional rebuild → `prt-get listorphans` report → `pkgcheck` footprint scan. |
| 4 | **Bootloader info** | Detects UEFI vs BIOS, checks for GRUB 2, LILO (common on CRUX), systemd-boot, rEFInd, syslinux. Lists `/etc/lilo.conf`, grub paths, and EFI entries via `efibootmgr`. |
| 5 | **Kernel info** | Shows running kernel, images in `/boot`, sources in `/usr/src`, active `.config`, CRUX-specific `make` build command hints, and top loaded modules. |
| 0 | **Exit** | Quit. |

### Dependencies

- Standard CRUX base system (`bash`, `blkid`, `findmnt`, `lsblk`, `lsmod`)
- `prt-get`, `pkgmk`, `ports` — standard CRUX package tools
- `revdep` — from `prt-utils` port (optional but recommended for option 3)
- `efibootmgr` — optional, from `opt` port collection, used by option 4 on EFI systems
- `pkgcheck` — optional footprint checker used by option 3