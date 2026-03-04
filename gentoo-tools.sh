#!/usr/bin/env bash
# gentoo-tools.sh — Helpful Gentoo administration menu

# ─── Colors ───────────────────────────────────────────────────────────────────
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
MAGENTA='\033[1;35m'
BG_BLUE='\033[44m'
BG_DARK='\033[48;5;234m'

# ─── Helpers ──────────────────────────────────────────────────────────────────
HR() { printf "${DIM}${BLUE}%*s${RESET}\n" 70 '' | tr ' ' '─'; }
HEADER() {
    echo
    printf "${BG_BLUE}${WHITE}${BOLD}  %-66s  ${RESET}\n" "$1"
    HR
}
INFO()    { printf "  ${CYAN}●${RESET}  %s\n" "$1"; }
SUCCESS() { printf "  ${GREEN}✔${RESET}  %s\n" "$1"; }
WARN()    { printf "  ${YELLOW}⚠${RESET}  %s\n" "$1"; }
ERROR()   { printf "  ${RED}✘${RESET}  %s\n" "$1"; }
LABEL()   { printf "  ${YELLOW}${BOLD}%-28s${RESET} %s\n" "$1" "$2"; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        ERROR "This option must be run as root (use sudo or su)."
        return 1
    fi
}

press_enter() {
    echo
    printf "  ${DIM}Press [Enter] to return to the menu...${RESET}"
    read -r
}

# ─── Option 1 — make.conf: CPU flags + optimal defaults + USE + VIDEO_CARDS ───
opt_makeconf() {
    HEADER "make.conf — CPU Flags, Optimal Defaults, USE & VIDEO_CARDS"
    require_root || { press_enter; return; }

    local MAKECONF="/etc/portage/make.conf"

    # ── Install cpuid2cpuflags if missing ──────────────────────────────────────
    if ! command -v cpuid2cpuflags &>/dev/null; then
        INFO "cpuid2cpuflags not found — installing app-portage/cpuid2cpuflags ..."
        emerge --ask=n app-portage/cpuid2cpuflags
        if ! command -v cpuid2cpuflags &>/dev/null; then
            ERROR "Installation failed. Aborting."
            press_enter; return
        fi
        SUCCESS "cpuid2cpuflags installed."
    else
        SUCCESS "cpuid2cpuflags already installed."
    fi

    # ── Gather values ──────────────────────────────────────────────────────────
    local CPU_FLAGS
    CPU_FLAGS="$(cpuid2cpuflags | sed 's/^CPU_FLAGS_X86: //')"
    local JOBS
    JOBS="$(nproc)"
    local LOAD
    LOAD="$(nproc)"          # -l = load limit = same as job count keeps system responsive

    INFO "Detected CPU_FLAGS_X86 : ${CPU_FLAGS}"
    INFO "Detected CPU cores     : ${JOBS}"

    # ── Backup ────────────────────────────────────────────────────────────────
    cp -n "${MAKECONF}" "${MAKECONF}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null \
        && SUCCESS "Backup created."

    # ── Update / append each key (idempotent) ─────────────────────────────────
    update_conf() {
        local key="$1" value="$2" file="$3"
        if grep -q "^${key}=" "${file}" 2>/dev/null; then
            sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
        else
            echo "${key}=${value}" >> "${file}"
        fi
    }

    update_conf 'COMMON_FLAGS'     '"-O2 -pipe -march=native"'          "${MAKECONF}"
    update_conf 'CFLAGS'           '"${COMMON_FLAGS}"'                   "${MAKECONF}"
    update_conf 'CXXFLAGS'         '"${COMMON_FLAGS}"'                   "${MAKECONF}"
    update_conf 'FCFLAGS'          '"${COMMON_FLAGS}"'                   "${MAKECONF}"
    update_conf 'FFLAGS'           '"${COMMON_FLAGS}"'                   "${MAKECONF}"
    update_conf 'MAKEOPTS'         '"-j'"${JOBS}"' -l'"${LOAD}"'"       "${MAKECONF}"
    update_conf 'EMERGE_DEFAULT_OPTS' '"--jobs='"${JOBS}"' --load-average='"${LOAD}"'"' "${MAKECONF}"
    update_conf 'CPU_FLAGS_X86'    '"'"${CPU_FLAGS}"'"                  "${MAKECONF}"
    update_conf 'PORTAGE_NICENESS' '"15"'                                "${MAKECONF}"
    update_conf 'FEATURES'         '"parallel-fetch parallel-install"'   "${MAKECONF}"

    # ── Global USE flags — KDE Plasma + AMD GPU stack ─────────────────────────
    local USE_FLAGS
    USE_FLAGS='"X wayland'
    USE_FLAGS+=' kde plasma qt5 qt6 dbus'
    USE_FLAGS+=' opengl vulkan drm kms vaapi vdpau llvm'
    USE_FLAGS+=' alsa pipewire pulseaudio sound-server jack'
    USE_FLAGS+=' networkmanager wifi bluetooth'
    USE_FLAGS+=' elogind policykit udev acl udisks cups'
    USE_FLAGS+=' gstreamer ffmpeg mp3 ogg vorbis flac aac x264 x265'
    USE_FLAGS+=' jpeg png gif webp svg'
    USE_FLAGS+=' truetype fontconfig nls unicode'
    USE_FLAGS+=' zip zlib bzip2 lzma xz'
    USE_FLAGS+=' spell hunspell semantic-desktop activities kwallet ssl curl libnotify"'

    update_conf 'USE'          "${USE_FLAGS}"                              "${MAKECONF}"

    # ── VIDEO_CARDS — modern AMD GPU (amdgpu/radeonsi/radv) ───────────────────
    update_conf 'VIDEO_CARDS' '"amdgpu radeonsi radv"'                    "${MAKECONF}"

    echo
    SUCCESS "make.conf updated.  Relevant lines:"
    HR
    grep -E 'COMMON_FLAGS|CFLAGS|CXXFLAGS|MAKEOPTS|EMERGE_DEFAULT_OPTS|CPU_FLAGS_X86|PORTAGE_NICENESS|FEATURES|^USE=|VIDEO_CARDS' \
        "${MAKECONF}" | while IFS= read -r line; do
        printf "  ${GREEN}%s${RESET}\n" "${line}"
    done
    HR
    WARN "Run: emerge --update --deep --newuse @world  to apply new USE/VIDEO_CARDS flags."
    press_enter
}

# ─── Option 2 — Generate /etc/fstab ───────────────────────────────────────────
opt_fstab() {
    HEADER "Generate /etc/fstab with UUIDs & Optimal Options"
    require_root || { press_enter; return; }

    local FSTAB="/etc/fstab"
    cp -n "${FSTAB}" "${FSTAB}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null \
        && SUCCESS "Existing fstab backed up."

    # ── Derive optimal options per filesystem type ─────────────────────────────
    mount_opts() {
        local fs="$1" mp="$2"
        case "${fs}" in
            ext4)
                if [[ "${mp}" == "/" ]]; then
                    echo "noatime,errors=remount-ro"
                else
                    echo "defaults,noatime"
                fi ;;  
            btrfs)
                echo "defaults,noatime,compress=zstd:1,space_cache=v2" ;; 
            xfs)
                echo "defaults,noatime,largeio" ;; 
            vfat|fat32|msdos)
                echo "defaults,noatime,fmask=0022,dmask=0022,codepage=437,iocharset=utf8,shortname=mixed" ;; 
            swap)
                echo "sw" ;; 
            tmpfs)
                echo "defaults,noatime,mode=0755" ;; 
            *)
                echo "defaults,noatime" ;; 
        esac
    }

    dump_pass() {
        local fs="$1" mp="$2"
        case "${fs}" in
            swap|tmpfs|vfat|fat32) echo "0 0" ;; 
            *)
                if [[ "${mp}" == "/" ]]; then echo "0 1" 
                else echo "0 2"; fi ;; 
        esac
    }

    # ── Build new fstab ───────────────────────────────────────────────────────
    {
        echo "# /etc/fstab — generated by gentoo-tools.sh on $(date)"
        echo "# <fs uuid/path>                                <mp>     <type>   <options>                                         <dump> <pass>"
        echo

        # Real block devices (skip loop, ram, devtmpfs etc.)
        while IFS= read -r line; do
            local dev mp fstype opts _rest
            read -r dev mp fstype opts _rest <<< "${line}"
            [[ "${dev}" == /dev/sd*   || "${dev}" == /dev/nvme* || \
               "${dev}" == /dev/vd*   || "${dev}" == /dev/hd*   || \
               "${dev}" == /dev/mmcblk* ]] || continue

            local uuid
            uuid="$(blkid -s UUID -o value "${dev}" 2>/dev/null)"
            [[ -z "${uuid}" ]] && { WARN "Could not get UUID for ${dev} — skipping." >&2; continue; }

            local chosen_opts
            chosen_opts="$(mount_opts "${fstype}" "${mp}")"
            local dp
            dp="$(dump_pass "${fstype}" "${mp}")"

            printf "UUID=%-38s %-12s %-8s %-50s %s\n" \
                "${uuid}" "${mp}" "${fstype}" "${chosen_opts}" "${dp}"
        done < <(findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS --real)

        # tmpfs entries worth keeping
        echo
        echo "# tmpfs"
        printf "%42s %-12s %-8s %-50s %s\n" \
            "tmpfs" "/tmp" "tmpfs" "defaults,noatime,nosuid,nodev,size=2G,mode=1777" "0 0"

    } > "${FSTAB}"

    echo
    SUCCESS "New fstab written to ${FSTAB}:"
    HR
    while IFS= read -r l; do
        printf "  ${GREEN}%s${RESET}\n" "${l}"
    done < "${FSTAB}"
    HR
    WARN "Review the file carefully before rebooting.  Back up at ${FSTAB}.bak.*"
    press_enter
}

# ─── Option 3 — Full Gentoo world rebuild & cleanup ───────────────────────────
opt_rebuild() {
    HEADER "Full Gentoo World Rebuild & Cleanup"
    require_root || { press_enter; return; }

    echo
    WARN "This will run a full sync → rebuild → depclean → revdep cycle."
    printf "  ${YELLOW}${BOLD}Continue? [y/N]: ${RESET}"
    read -r confirm
    [[ "${confirm,,}" != "y" ]] && { INFO "Aborted."; press_enter; return; }

    local STEPS=(
        "Sync Portage tree"
        "Sync all repos (overlays)"
        "Rebuild @world (deep, new-use, with-bdeps)"
        "Rebuild preserved libs"
        "Run depclean (remove obsolete packages)"
        "Run revdep-rebuild (fix broken linkage)"
        "Rebuild Perl modules if perl-cleaner present"
        "Update config files (dispatch-conf)"
    )
    local CMDS=(
        "emerge --sync"
        "emaint sync --auto"
        "emerge --update --deep --newuse --with-bdeps=y --backtrack=30 --keep-going --ask=n @world"
        "emerge @preserved-rebuild"
        "emerge --depclean --ask=n"
        "revdep-rebuild -- --ask=n"
        "command -v perl-cleaner &>/dev/null && perl-cleaner --all -- --ask=n || true"
        "dispatch-conf"
    )

    for i in "${!STEPS[@]}"; do
        echo
        INFO "Step $((i+1))/${#STEPS[@]}: ${STEPS[$i]}"
        HR
        if ! eval "${CMDS[$i]}"; then
            WARN "Step $((i+1)) exited non-zero — check output above before continuing."
            printf "  ${YELLOW}Continue anyway? [y/N]: ${RESET}"
            read -r cont
            [[ "${cont,,}" != "y" ]] && { ERROR "Aborted at step $((i+1))."; press_enter; return; }
        else
            SUCCESS "${STEPS[$i]} completed."
        fi
    done

    echo
    SUCCESS "Full rebuild & cleanup sequence complete."
    press_enter
}

# ─── Option 4 — Bootloader info ───────────────────────────────────────────────
opt_bootloader() {
    HEADER "Bootloader & Boot Method Detection"

    # ── Firmware type ─────────────────────────────────────────────────────────
    if [[ -d /sys/firmware/efi ]]; then
        local boot_type="UEFI / EFI"
        local secboot
        if command -v mokutil &>/dev/null; then
            secboot="$(mokutil --sb-state 2>/dev/null || echo 'unknown')"
        else
            secboot="$(od -An -tx1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null \
                | awk 'NR==1{v=$(NF); print (v=="01") ? "enabled" : "disabled"}' \
                || echo 'unknown')"
        fi
        LABEL "Firmware:"    "${GREEN}${boot_type}${RESET}"
        LABEL "Secure Boot:" "${secboot}"

        local efi_part
        efi_part="$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || findmnt -n -o SOURCE /efi 2>/dev/null || echo "not mounted")"
        LABEL "EFI partition:" "${efi_part}"
    else
        LABEL "Firmware:" "${YELLOW}Legacy BIOS / MBR${RESET}"
        # Check for GRUB MBR signature
        local grub_disk
        grub_disk="$(lsblk -dpn -o NAME,TYPE | awk '$2=="disk"{print $1}' | head -1)"
        if [[ -n "${grub_disk}" ]]; then
            local mbr_sig
            mbr_sig="$(dd if="${grub_disk}" bs=512 count=1 2>/dev/null | strings)"
            if echo "${mbr_sig}" | grep -qi grub; then
                LABEL "MBR signature:" "GRUB detected on ${grub_disk}"
            elif echo "${mbr_sig}" | grep -qi lilo; then
                LABEL "MBR signature:" "LILO detected on ${grub_disk}"
            else
                LABEL "MBR check:" "No known bootloader signature in ${grub_disk}"
            fi
        fi
    fi

    echo
    HR

    # ── Detect installed bootloader ───────────────────────────────────────────
    local detected=()

    # GRUB 2
    if command -v grub-mkconfig &>/dev/null || command -v grub2-mkconfig &>/dev/null; then
        detected+=("GRUB 2")
    fi
    # systemd-boot
    if command -v bootctl &>/dev/null && bootctl status &>/dev/null 2>&1; then
        detected+=("systemd-boot")
    fi
    # rEFInd
    command -v refind-install &>/dev/null && detected+=("rEFInd")
    # syslinux
    command -v syslinux &>/dev/null && detected+=("syslinux")
    # LILO
    command -v lilo &>/dev/null && detected+=("LILO")

    if [[ ${#detected[@]} -gt 0 ]]; then
        LABEL "Detected bootloader(s):" "${detected[*]}"
    else
        WARN "No known bootloader command found in PATH."
    fi

    echo
    HEADER "Important Bootloader Files & Locations"

    # GRUB
    local grub_files=(
        "/boot/grub/grub.cfg"
        "/boot/grub2/grub.cfg"
        "/etc/default/grub"
        "/etc/grub.d/"
        "/boot/grub/"
        "/boot/efi/EFI/"
    )
    for f in "${grub_files[@]}"; do
        [[ -e "${f}" ]] && LABEL "GRUB:" "${f}"
    done

    # LILO
    for f in /etc/lilo.conf /boot/map; do
        [[ -e "${f}" ]] && LABEL "LILO:" "${f}"
    done

    # systemd-boot
    local sd_files=(
        "/boot/efi/loader/loader.conf"
        "/efi/loader/loader.conf"
        "/boot/loader/loader.conf"
        "/boot/efi/loader/entries/"
        "/efi/loader/entries/"
    )
    for f in "${sd_files[@]}"; do
        [[ -e "${f}" ]] && LABEL "systemd-boot:" "${f}"
    done

    # EFI vars / boot entries
    echo
    if [[ -d /sys/firmware/efi ]]; then
        INFO "EFI boot entries (efibootmgr):"
        HR
        if command -v efibootmgr &>/dev/null; then
            efibootmgr | while IFS= read -r l; do
                printf "    ${CYAN}%s${RESET}\n" "${l}"
            done
        else
            WARN "efibootmgr not installed."
        fi
    fi

    press_enter
}

# ─── Option 5 — Kernel info ───────────────────────────────────────────────────
opt_kernel() {
    HEADER "Current Kernel & Important File Locations"

    LABEL "Running kernel:"  "$(uname -r)"
    LABEL "Architecture:"    "$(uname -m)"
    LABEL "Build date:"      "$(uname -v)"
    LABEL "Hostname:"        "$(uname -n)"

    echo
    HR
    INFO "Kernel image(s) in /boot:"
    find /boot -maxdepth 2 \( -name "vmlinuz*" -o -name "kernel*" -o -name "bzImage*" \) 2>/dev/null \
        | sort | while IFS= read -r f; do
        LABEL "  kernel image:" "${f}  $(du -sh "${f}" 2>/dev/null | cut -f1)"
    done

    echo
    INFO "Initramfs image(s):"
    find /boot -maxdepth 2 \( -name "initramfs*" -o -name "initrd*" \) 2>/dev/null \
        | sort | while IFS= read -r f; do
        LABEL "  initramfs:" "${f}  $(du -sh "${f}" 2>/dev/null | cut -f1)"
    done

    echo
    INFO "Kernel sources in /usr/src:"
    if [[ -d /usr/src ]]; then
        local active_target sym
        active_target="$(readlink /usr/src/linux 2>/dev/null)"
        while IFS= read -r d; do
            sym=""
            [[ "${active_target}" == "${d}" ]] && sym="${GREEN} ← active symlink${RESET}"
            printf "  ${CYAN}/usr/src/%-36s${RESET}%b\n" "${d}" "${sym}"
        done < <(ls /usr/src 2>/dev/null | grep -v "^$")
    else
        WARN "/usr/src not found."
    fi

    echo
    INFO "Active kernel config:"
    local kconfig=""
    for f in \
        "/usr/src/linux/.config" \
        "/proc/config.gz" \
        "/boot/config-$(uname -r)" \
        "/boot/config"; do
        if [[ -e "${f}" ]]; then
            kconfig="${f}"; break
        fi
    done
    if [[ -n "${kconfig}" ]]; then
        LABEL "  .config:" "${kconfig}"
    else
        WARN "No kernel .config found in common locations."
    fi

    echo
    INFO "Other relevant paths:"
    LABEL "  Modules dir:"    "/lib/modules/$(uname -r)"
    LABEL "  Firmware dir:"   "/lib/firmware"
    LABEL "  dracut config:"  "/etc/dracut.conf  /etc/dracut.conf.d/"
    LABEL "  genkernel conf:" "/etc/genkernel.conf"

    echo
    INFO "Loaded modules (top 20 by size):"
    HR
    lsmod 2>/dev/null | awk 'NR>1 {print $3, $1}' | sort -rn | head -20 \
        | while read -r sz mod; do
        printf "    ${CYAN}%-40s${RESET} ${DIM}%s refs${RESET}\n" "${mod}" "${sz}"
    done

    press_enter
}

# ─── Main menu ────────────────────────────────────────────────────────────────
print_menu() {
    clear
    echo
    printf "${BG_BLUE}${WHITE}${BOLD}%70s${RESET}\n" " "
    printf "${BG_BLUE}${WHITE}${BOLD}  %-66s  ${RESET}\n" "  ⚙  Gentoo Admin Toolkit"
    printf "${BG_BLUE}${WHITE}${BOLD}%70s${RESET}\n" " "
    HR
    echo
    printf "  ${GREEN}${BOLD}[1]${RESET}  ${WHITE}Configure make.conf${RESET}"
    printf "  ${DIM}— CPU flags, MAKEOPTS, USE flags & VIDEO_CARDS${RESET}\n"

    printf "  ${GREEN}${BOLD}[2]${RESET}  ${WHITE}Generate /etc/fstab${RESET}"
    printf "  ${DIM}— UUIDs, optimal mount options per filesystem${RESET}\n"

    printf "  ${GREEN}${BOLD}[3]${RESET}  ${WHITE}Full world rebuild & cleanup${RESET}"
    printf "  ${DIM}— sync → emerge @world → depclean → revdep${RESET}\n"

    printf "  ${GREEN}${BOLD}[4]${RESET}  ${WHITE}Bootloader info${RESET}"
    printf "          ${DIM}— detect GRUB/EFI/BIOS, list key files${RESET}\n"

    printf "  ${GREEN}${BOLD}[5]${RESET}  ${WHITE}Kernel info${RESET}"
    printf "               ${DIM}— running kernel, sources, config, modules${RESET}\n"

    echo
    printf "  ${RED}${BOLD}[0]${RESET}  ${WHITE}Exit${RESET}\n"
    echo
    HR
    printf "  ${YELLOW}${BOLD}Select an option: ${RESET}"
}

main() {
    while true; do
        print_menu
        read -r choice
        case "${choice}" in
            1) opt_makeconf  ;; 
            2) opt_fstab     ;;
            3) opt_rebuild   ;;
            4) opt_bootloader;;
            5) opt_kernel    ;;
            0|q|Q|exit)
                echo
                printf "  ${GREEN}Goodbye.${RESET}\n\n"
                exit 0
                ;;
            *)
                echo
                WARN "Unknown option '${choice}' — please choose 0–5."
                sleep 1
                ;;
        esac
    done
}

main "$@"