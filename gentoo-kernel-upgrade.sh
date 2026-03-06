#!/usr/bin/env bash
# =============================================================================
# gentoo-kernel-upgrade.sh
# Automatic dist-kernel upgrade for Gentoo — EFI Stub + OpenRC + AMD64
# No GRUB. Scans the system and handles everything.
# Run as root.
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m';  YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m';      DIM='\033[2m';  RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { err "$*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══ $* ${RESET}"; }
confirm() {
    local msg="$1"
    local ans
    echo -e "${YELLOW}[?]${RESET} ${msg} [y/N] "
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "This script must be run as root."

# =============================================================================
header "STEP 0 — System Scan"
# =============================================================================

# ── Find all installed dist-kernels ──────────────────────────────────────────
info "Scanning /usr/src for installed kernels..."
mapfile -t KERNEL_DIRS < <(find /usr/src -maxdepth 1 -type d -name 'linux-*' | sort -V)
[[ ${#KERNEL_DIRS[@]} -gt 0 ]] || die "No kernel source directories found in /usr/src."

echo ""
echo -e "  ${DIM}Found kernel source directories:${RESET}"
for d in "${KERNEL_DIRS[@]}"; do
    echo -e "    ${DIM}•${RESET} $(basename "$d")"
done
echo ""

# ── Current running kernel ───────────────────────────────────────────────────
RUNNING_KVER=$(uname -r)
info "Currently running kernel : ${BOLD}${RUNNING_KVER}${RESET}"

# ── Currently selected /usr/src/linux symlink ────────────────────────────────
if [[ -L /usr/src/linux ]]; then
    CURRENT_SELECTED=$(readlink -f /usr/src/linux)
    CURRENT_SELECTED_VER=$(basename "$CURRENT_SELECTED" | sed 's/^linux-//')
    info "Current /usr/src/linux    : ${BOLD}${CURRENT_SELECTED_VER}${RESET}"
else
    CURRENT_SELECTED=""
    CURRENT_SELECTED_VER="(none)"
    warn "/usr/src/linux symlink not set."
fi

# ── Newest installed kernel ───────────────────────────────────────────────────
NEWEST_DIR="${KERNEL_DIRS[-1]}"
NEWEST_VER=$(basename "$NEWEST_DIR" | sed 's/^linux-//')
info "Newest installed kernel   : ${BOLD}${NEWEST_VER}${RESET}"

# ── Check if upgrade is actually needed ──────────────────────────────────────
if [[ "$RUNNING_KVER" == "$NEWEST_VER" ]]; then
    ok "You are already running the newest installed kernel (${NEWEST_VER})."
    confirm "Continue anyway (force reinstall)?" || { info "Nothing to do. Exiting."; exit 0; }
fi

echo ""

# =============================================================================
header "STEP 1 — Locate EFI Partition & Boot Files"
# =============================================================================

# ── Find EFI mount point ─────────────────────────────────────────────────────
EFI_MOUNT=""
for candidate in /boot/efi /boot /efi; do
    if mountpoint -q "$candidate" 2>/dev/null; then
        # Check it looks like an EFI partition (has EFI dir or vfat)
        if [[ -d "${candidate}/EFI" ]] || blkid "$(findmnt -n -o SOURCE "$candidate")" 2>/dev/null | grep -qi 'vfat\|fat'; then
            EFI_MOUNT="$candidate"
            break
        fi
    fi
done

# Fallback: check fstab for efi/boot
if [[ -z "$EFI_MOUNT" ]]; then
    FSTAB_EFI=$(grep -iE 'vfat|efi' /etc/fstab | awk '{print $2}' | head -1)
    if [[ -n "$FSTAB_EFI" ]]; then
        warn "EFI partition not currently mounted. Attempting to mount from fstab: ${FSTAB_EFI}"
        mount "$FSTAB_EFI" && EFI_MOUNT="$FSTAB_EFI"
    fi
fi

[[ -n "$EFI_MOUNT" ]] || die "Cannot detect EFI partition mount point. Mount it manually and re-run."
ok "EFI partition mounted at  : ${BOLD}${EFI_MOUNT}${RESET}"

# ── Locate existing vmlinuz ───────────────────────────────────────────────────
VMLINUZ_DEST=""
for f in "${EFI_MOUNT}/vmlinuz" "${EFI_MOUNT}/EFI/gentoo/vmlinuz" "${EFI_MOUNT}/EFI/BOOT/vmlinuz"; do
    if [[ -f "$f" ]]; then
        VMLINUZ_DEST="$f"
        break
    fi
done

# Check for versioned filenames (e.g. vmlinuz-6.6.21-gentoo-dist)
if [[ -z "$VMLINUZ_DEST" ]]; then
    VMLINUZ_DEST_VERSIONED=$(find "${EFI_MOUNT}" -maxdepth 3 -name "vmlinuz*" | head -1)
    if [[ -n "$VMLINUZ_DEST_VERSIONED" ]]; then
        VMLINUZ_DEST="$VMLINUZ_DEST_VERSIONED"
        warn "Found versioned kernel filename: ${VMLINUZ_DEST}"
        warn "Will overwrite in-place. Adjust VMLINUZ_DEST in script if needed."
    fi
fi

# If still not found, propose a default
if [[ -z "$VMLINUZ_DEST" ]]; then
    VMLINUZ_DEST="${EFI_MOUNT}/vmlinuz"
    warn "No existing kernel image found in EFI. Will create: ${VMLINUZ_DEST}"
fi
ok "Kernel destination        : ${BOLD}${VMLINUZ_DEST}${RESET}"

# ── Locate existing initramfs ─────────────────────────────────────────────────
INITRAMFS_DEST=""
for f in "${EFI_MOUNT}/initramfs.img" "${EFI_MOUNT}/initrd.img" \
          "${EFI_MOUNT}/EFI/gentoo/initramfs.img" "${EFI_MOUNT}/EFI/BOOT/initramfs.img"; do
    if [[ -f "$f" ]]; then
        INITRAMFS_DEST="$f"
        break
    fi
done

if [[ -z "$INITRAMFS_DEST" ]]; then
    INITRAMFS_VERSIONED=$(find "${EFI_MOUNT}" -maxdepth 3 -name "initr*" | head -1)
    [[ -n "$INITRAMFS_VERSIONED" ]] && INITRAMFS_DEST="$INITRAMFS_VERSIONED"
fi

if [[ -z "$INITRAMFS_DEST" ]]; then
    INITRAMFS_DEST="${EFI_MOUNT}/initramfs.img"
    warn "No existing initramfs found. Will create: ${INITRAMFS_DEST}"
fi
ok "Initramfs destination     : ${BOLD}${INITRAMFS_DEST}${RESET}"

# ── Locate new bzImage ────────────────────────────────────────────────────────
BZIMAGE="/usr/src/linux-${NEWEST_VER}/arch/x86/boot/bzImage"
if [[ ! -f "$BZIMAGE" ]]; then
    # Try via symlink path after eselect
    BZIMAGE_SYMLINK="/usr/src/linux/arch/x86/boot/bzImage"
    [[ -f "$BZIMAGE_SYMLINK" ]] && BZIMAGE="$BZIMAGE_SYMLINK"
fi

# =============================================================================
header "STEP 2 — Confirm Plan"
# =============================================================================
echo ""
echo -e "  ${BOLD}Plan of action:${RESET}"
echo -e "  ${DIM}────────────────────────────────────────────────────────${RESET}"
echo -e "  New kernel version   : ${GREEN}${NEWEST_VER}${RESET}"
echo -e "  Running kernel       : ${DIM}${RUNNING_KVER}${RESET}"
echo -e "  Kernel image source  : ${DIM}${BZIMAGE}${RESET}"
echo -e "  Kernel destination   : ${BOLD}${VMLINUZ_DEST}${RESET}"
echo -e "  Initramfs dest       : ${BOLD}${INITRAMFS_DEST}${RESET}"
echo -e "  EFI mount            : ${BOLD}${EFI_MOUNT}${RESET}"
echo -e "  ${DIM}────────────────────────────────────────────────────────${RESET}"
echo ""
confirm "Proceed with kernel upgrade?" || { info "Aborted by user."; exit 0; }

# =============================================================================
header "STEP 3 — Switch Kernel Symlink"
# =============================================================================

ESELECT_NUM=""
while IFS= read -r line; do
    if echo "$line" | grep -q "$NEWEST_VER"; then
        ESELECT_NUM=$(echo "$line" | grep -oP '(?<=\[)\d+(?=\])')
        break
    fi
done < <(eselect kernel list 2>/dev/null)

if [[ -n "$ESELECT_NUM" ]]; then
    info "Running: eselect kernel set ${ESELECT_NUM}"
    eselect kernel set "$ESELECT_NUM"
    ok "Kernel symlink set to ${NEWEST_VER}"
else
    warn "Could not auto-detect eselect number. Setting symlink manually..."
    ln -sfn "/usr/src/linux-${NEWEST_VER}" /usr/src/linux
    ok "Symlink set manually: /usr/src/linux -> linux-${NEWEST_VER}"
fi

# =============================================================================
header "STEP 4 — Rebuild External Kernel Modules"
# =============================================================================

info "Running emerge @module-rebuild..."
if emerge --ask=n @module-rebuild; then
    ok "Module rebuild complete."
else
    warn "emerge @module-rebuild had issues. Continuing — check output above."
fi

# =============================================================================
header "STEP 5 — Regenerate initramfs with dracut"
# =============================================================================

# ── Check dracut is available ─────────────────────────────────────────────────
if ! command -v dracut &>/dev/null; then
    warn "dracut not found. Installing..."
    emerge --ask=n sys-kernel/dracut || die "Failed to install dracut."
fi

# ── Check /lib/modules for the new kernel ────────────────────────────────────
MODULES_DIR="/lib/modules/${NEWEST_VER}"
if [[ ! -d "$MODULES_DIR" ]]; then
    # dist-kernel may use a slightly different name — fuzzy match
    MODULES_DIR=$(find /lib/modules -maxdepth 1 -type d -name "*${NEWEST_VER%%-gentoo*}*" | sort -V | tail -1)
    [[ -n "$MODULES_DIR" ]] || die "Cannot find modules directory for ${NEWEST_VER} in /lib/modules/. Is the kernel fully installed?"
    NEWEST_VER_KMOD=$(basename "$MODULES_DIR")
    warn "Using modules dir: ${MODULES_DIR} (kver: ${NEWEST_VER_KMOD})"
else
    NEWEST_VER_KMOD="$NEWEST_VER"
fi
ok "Modules found at: ${MODULES_DIR}"

# ── AMD firmware check ────────────────────────────────────────────────────────
if [[ -d /lib/firmware/amdgpu ]]; then
    AMD_FW_COUNT=$(find /lib/firmware/amdgpu -name "*.bin" | wc -l)
    ok "AMD GPU firmware blobs found: ${AMD_FW_COUNT} files"
else
    warn "/lib/firmware/amdgpu not found. Consider: emerge sys-kernel/linux-firmware"
fi

info "Generating initramfs for ${NEWEST_VER_KMOD}..."
dracut --force --kver "${NEWEST_VER_KMOD}" "${INITRAMFS_DEST}"
ok "Initramfs written to: ${INITRAMFS_DEST}"

# =============================================================================
header "STEP 6 — Copy New Kernel to EFI"
# =============================================================================

# ── Verify bzImage exists (symlink should be set by now) ──────────────────────
BZIMAGE="/usr/src/linux/arch/x86/boot/bzImage"
[[ -f "$BZIMAGE" ]] || die "bzImage not found at ${BZIMAGE}. Is this a bin dist-kernel? Checking alternate paths..."

# ── Backup existing kernel ────────────────────────────────────────────────────
if [[ -f "$VMLINUZ_DEST" ]]; then
    info "Backing up existing kernel -> ${VMLINUZ_DEST}.old"
    cp -f "$VMLINUZ_DEST" "${VMLINUZ_DEST}.old"
    ok "Backup created: ${VMLINUZ_DEST}.old"
fi

info "Copying bzImage -> ${VMLINUZ_DEST}"
cp -f "$BZIMAGE" "$VMLINUZ_DEST"
ok "Kernel image installed."

# ── Sync EFI partition writes ─────────────────────────────────────────────────
sync
ok "EFI partition synced."

# =============================================================================
header "STEP 7 — Check EFI Boot Entry"
# =============================================================================

EFIBOOTMGR_FOUND=false
if command -v efibootmgr &>/dev/null; then
    VMLINUZ_BASENAME=$(basename "$VMLINUZ_DEST")
    INITRAMFS_BASENAME=$(basename "$INITRAMFS_DEST")

    echo ""
    info "Current EFI boot entries:"
    efibootmgr -v | grep -E 'BootCurrent|BootOrder|Boot[0-9A-F]{4}' | head -20
    echo ""

    # Check if any entry already references our vmlinuz filename
    if efibootmgr -v 2>/dev/null | grep -q "$VMLINUZ_BASENAME"; then
        ok "Existing EFI entry references ${VMLINUZ_BASENAME} — no changes needed."
        EFIBOOTMGR_FOUND=true
    else
        warn "No EFI entry found referencing ${VMLINUZ_BASENAME}."
        warn "You may need to create/update an EFI entry manually."
        echo ""
        echo -e "  ${DIM}Example command (adjust disk, partition, root UUID):${RESET}"
        # Try to auto-detect root UUID
        ROOT_UUID=$(findmnt -n -o UUID / 2>/dev/null || blkid "$(findmnt -n -o SOURCE /)" -s UUID -o value 2>/dev/null || echo "YOUR-ROOT-UUID")
        # Try to detect EFI disk and partition
        EFI_DEV=$(findmnt -n -o SOURCE "$EFI_MOUNT" 2>/dev/null || echo "/dev/nvme0n1p1")
        EFI_DISK=$(echo "$EFI_DEV" | sed 's/p[0-9]*$//' | sed 's/[0-9]*$//')
        EFI_PART=$(echo "$EFI_DEV" | grep -oP '[0-9]+$')
        # Build EFI path (relative to EFI partition root)
        EFI_REL_PATH=$(echo "$VMLINUZ_DEST" | sed "s|${EFI_MOUNT}||" | sed 's|/|\\|g')
        INITRAMFS_REL_PATH=$(echo "$INITRAMFS_DEST" | sed "s|${EFI_MOUNT}||" | sed 's|/|\\|g')

        echo ""
        echo -e "  ${CYAN}efibootmgr \\${RESET}"
        echo -e "    ${CYAN}--create \\${RESET}"
        echo -e "    ${CYAN}--disk ${EFI_DISK} \\${RESET}"
        echo -e "    ${CYAN}--part ${EFI_PART} \\${RESET}"
        echo -e "    ${CYAN}--label \"Gentoo Linux\" \\${RESET}"
        echo -e "    ${CYAN}--loader '${EFI_REL_PATH}' \\${RESET}"
        echo -e "    ${CYAN}--unicode 'root=UUID=${ROOT_UUID} rw initrd=${INITRAMFS_REL_PATH} amd_iommu=on iommu=pt quiet'${RESET}"
        echo ""

        if confirm "Run the above efibootmgr command now?"; then
            efibootmgr \
                --create \
                --disk "$EFI_DISK" \
                --part "$EFI_PART" \
                --label "Gentoo Linux" \
                --loader "${EFI_REL_PATH}" \
                --unicode "root=UUID=${ROOT_UUID} rw initrd=${INITRAMFS_REL_PATH} amd_iommu=on iommu=pt quiet"
            ok "EFI boot entry created."
        else
            warn "Skipped EFI entry creation. Run the command above manually before rebooting."
        fi
    fi
else
    warn "efibootmgr not found. Install it with: emerge sys-apps/efibootmgr"
fi

# =============================================================================
header "STEP 8 — Summary"
# =============================================================================

echo ""
echo -e "  ${BOLD}Upgrade Summary${RESET}"
echo -e "  ${DIM}───────────────────────────────────────────────${RESET}"

check_item() {
    local label="$1"; local path="$2"
    if [[ -f "$path" ]]; then
        local size mod
        size=$(du -h "$path" | cut -f1)
        mod=$(date -r "$path" '+%Y-%m-%d %H:%M')
        echo -e "  ${GREEN}✓${RESET} ${label}: ${DIM}${path}${RESET} ${size} ${DIM}(${mod})${RESET}"
    else
        echo -e "  ${RED}✗${RESET} ${label}: ${RED}MISSING — ${path}${RESET}"
    fi
}

check_item "Kernel image  " "$VMLINUZ_DEST"
check_item "Initramfs     " "$INITRAMFS_DEST"
check_item "Kernel backup " "${VMLINUZ_DEST}.old"
check_item "Initrd backup " "${INITRAMFS_DEST}.old"

echo -e "  ${DIM}───────────────────────────────────────────────${RESET}"
echo ""
ok "Upgrade complete! New kernel: ${GREEN}${BOLD}${NEWEST_VER}${RESET}"
echo ""
echo -e "  ${YELLOW}After reboot, verify with:${RESET}"
echo -e "  ${CYAN}  uname -r${RESET}"
echo ""

if confirm "Reboot now?"; then
    info "Rebooting..."
    reboot
else
    warn "Remember to reboot to activate the new kernel."
fi
