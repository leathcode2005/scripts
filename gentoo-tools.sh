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
    INFO "Auto-setting MAKEOPTS  : -j${JOBS} -l${LOAD}  (based on $(nproc) cores)"
    INFO "Auto-setting EMERGE_DEFAULT_OPTS : --jobs=${JOBS} --load-average=${LOAD}"

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

    # ── Phase 1: Sync ─────────────────────────────────────────────────────────
    local SYNC_STEPS=("Sync Portage tree" "Sync all repos (overlays)")
    local SYNC_CMDS=("emerge --sync" "emaint sync --auto")

    for i in "${!SYNC_STEPS[@]}"; do
        echo
        INFO "Sync step $((i+1))/${#SYNC_STEPS[@]}: ${SYNC_STEPS[$i]}"
        HR
        if ! eval "${SYNC_CMDS[$i]}"; then
            WARN "Sync step $((i+1)) exited non-zero — check output above."
            printf "  ${YELLOW}Continue anyway? [y/N]: ${RESET}"
            read -r cont
            [[ "${cont,,}" != "y" ]] && { ERROR "Aborted at sync step $((i+1))."; press_enter; return; }
        else
            SUCCESS "${SYNC_STEPS[$i]} completed."
        fi
    done

    # ── Phase 2: Dependency pre-check (pretend) ───────────────────────────────
    echo
    HEADER "Dependency Pre-Check"
    INFO "Running emerge in pretend mode to detect dependency conflicts..."
    HR

    local pretend_output
    pretend_output="$(emerge --pretend --update --deep --newuse --with-bdeps=y @world 2>&1)"
    local pretend_rc=$?

    if [[ ${pretend_rc} -ne 0 ]]; then
        echo
        ERROR "Dependency conflicts / errors detected!"
        ERROR "Resolve the issues below before re-running this option."
        HR
        echo "${pretend_output}" | while IFS= read -r line; do
            printf "  ${RED}%s${RESET}\n" "${line}"
        done
        HR
        WARN "Fix the issues shown above, then re-run option 3."
        press_enter
        return
    fi

    SUCCESS "Pretend run passed — no dependency conflicts found."
    echo
    INFO "Packages scheduled for update:"
    HR
    echo "${pretend_output}" | grep '^\[' | while IFS= read -r line; do
        printf "  ${CYAN}%s${RESET}\n" "${line}"
    done
    HR

    # ── Phase 3: Build & cleanup ──────────────────────────────────────────────
    local BUILD_STEPS=(
        "Rebuild @world (deep, new-use, with-bdeps)"
        "Rebuild preserved libs"
        "Run depclean (remove obsolete packages)"
        "Run revdep-rebuild (fix broken linkage)"
        "Rebuild Perl modules if perl-cleaner present"
        "Update config files (dispatch-conf)"
    )
    local BUILD_CMDS=(
        "emerge --update --deep --newuse --with-bdeps=y --backtrack=30 --keep-going --ask=n @world"
        "emerge @preserved-rebuild"
        "emerge --depclean --ask=n"
        "revdep-rebuild -- --ask=n"
        "command -v perl-cleaner &>/dev/null && perl-cleaner --all -- --ask=n || true"
        "dispatch-conf"
    )

    for i in "${!BUILD_STEPS[@]}"; do
        echo
        INFO "Build step $((i+1))/${#BUILD_STEPS[@]}: ${BUILD_STEPS[$i]}"
        HR
        if ! eval "${BUILD_CMDS[$i]}"; then
            WARN "Build step $((i+1)) exited non-zero — check output above before continuing."
            printf "  ${YELLOW}Continue anyway? [y/N]: ${RESET}"
            read -r cont
            [[ "${cont,,}" != "y" ]] && { ERROR "Aborted at build step $((i+1))."; press_enter; return; }
        else
            SUCCESS "${BUILD_STEPS[$i]} completed."
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

# ─── Option 6 — Manage /etc/portage/package.use ───────────────────────────────
opt_packageuse() {
    local PKGUSE_DIR="/etc/portage/package.use"

    # ── Inner helper: list all entries with numbered index ─────────────────────
    _pkguse_list_entries() {
        local -a files entries
        local idx=0

        mapfile -t files < <(find "${PKGUSE_DIR}" -maxdepth 1 -type f 2>/dev/null | sort)

        if [[ ${#files[@]} -eq 0 ]]; then
            WARN "No package.use files found."
            return 1
        fi

        for f in "${files[@]}"; do
            while IFS= read -r line; do
                [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
                (( idx++ ))
                entries+=("${f}|${line}")
                local fname
                fname="$(basename "${f}")"
                printf "  ${GREEN}${BOLD}%3d${RESET}  ${CYAN}%-20s${RESET}  %s\n" \
                    "${idx}" "${fname}" "${line}"
            done < "${f}"
        done

        if [[ ${idx} -eq 0 ]]; then
            WARN "All package.use files are empty or contain only comments."
            return 1
        fi

        # Stash the entries array for the caller via a global
        _PKGUSE_ENTRIES=("${entries[@]}")
        return 0
    }

    # ── Inner helper: add an entry ────────────────────────────────────────────
    _pkguse_add() {
        HEADER "Add package.use Entry"
        require_root || return

        printf "  ${YELLOW}${BOLD}Package atom${RESET} (e.g. media-video/ffmpeg): "
        read -r pkg_atom
        [[ -z "${pkg_atom}" ]] && { WARN "Empty input — cancelled."; return; }

        printf "  ${YELLOW}${BOLD}USE flags${RESET} (e.g. -python x264 x265): "
        read -r use_flags
        [[ -z "${use_flags}" ]] && { WARN "Empty input — cancelled."; return; }

        # Derive filename from the package name (strip category/)
        local pkg_name
        pkg_name="$(echo "${pkg_atom}" | sed 's|.*/||')"

        # Ensure package.use directory exists
        mkdir -p "${PKGUSE_DIR}"

        local target="${PKGUSE_DIR}/${pkg_name}"
        local entry="${pkg_atom} ${use_flags}"

        # Avoid duplicates
        if [[ -f "${target}" ]] && grep -qF "${entry}" "${target}" 2>/dev/null; then
            WARN "Entry already exists in ${target}:"
            grep -nF "${entry}" "${target}" | while IFS= read -r l; do
                printf "    ${DIM}%s${RESET}\n" "${l}"
            done
            return
        fi

        echo "${entry}" >> "${target}"
        SUCCESS "Added to ${target}:"
        printf "    ${CYAN}%s${RESET}\n" "${entry}"
    }

    # ── Inner helper: edit an entry by number ─────────────────────────────────
    _pkguse_edit() {
        HEADER "Edit package.use Entry"
        require_root || return

        echo
        INFO "Current entries:"
        HR
        _pkguse_list_entries || return
        HR

        printf "\n  ${YELLOW}${BOLD}Entry number to edit${RESET} (0 to cancel): "
        read -r num
        [[ -z "${num}" || "${num}" == "0" ]] && { INFO "Cancelled."; return; }

        if ! [[ "${num}" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#_PKGUSE_ENTRIES[@]} )); then
            ERROR "Invalid selection."
            return
        fi

        local selected="${_PKGUSE_ENTRIES[$((num-1))]}"
        local file="${selected%%|*}"
        local old_line="${selected#*|}"

        echo
        LABEL "File:"         "$(basename "${file}")"
        LABEL "Current entry:" "${old_line}"
        echo
        printf "  ${YELLOW}${BOLD}New USE flags${RESET} (package atom is kept): "
        read -r new_flags
        [[ -z "${new_flags}" ]] && { WARN "Empty input — cancelled."; return; }

        # Reconstruct: keep original package atom, replace flags
        local pkg_atom
        pkg_atom="$(echo "${old_line}" | awk '{print $1}')"
        local new_line="${pkg_atom} ${new_flags}"

        # Use sed to replace the exact old line
        sed -i "s|^${old_line}$|${new_line}|" "${file}"
        SUCCESS "Updated in $(basename "${file}"):"
        printf "    ${DIM}old:${RESET} %s\n" "${old_line}"
        printf "    ${GREEN}new:${RESET} %s\n" "${new_line}"
    }

    # ── Inner helper: delete an entry by number ───────────────────────────────
    _pkguse_delete() {
        HEADER "Delete package.use Entry"
        require_root || return

        echo
        INFO "Current entries:"
        HR
        _pkguse_list_entries || return
        HR

        printf "\n  ${YELLOW}${BOLD}Entry number to delete${RESET} (0 to cancel): "
        read -r num
        [[ -z "${num}" || "${num}" == "0" ]] && { INFO "Cancelled."; return; }

        if ! [[ "${num}" =~ ^[0-9]+$ ]] || (( num < 1 || num > ${#_PKGUSE_ENTRIES[@]} )); then
            ERROR "Invalid selection."
            return
        fi

        local selected="${_PKGUSE_ENTRIES[$((num-1))]}"
        local file="${selected%%|*}"
        local old_line="${selected#*|}"

        echo
        LABEL "File:"  "$(basename "${file}")"
        LABEL "Entry:" "${old_line}"
        printf "  ${YELLOW}${BOLD}Confirm delete? [y/N]: ${RESET}"
        read -r yn
        [[ "${yn,,}" != "y" ]] && { INFO "Cancelled."; return; }

        # Escape special chars for sed and delete the line
        local escaped
        escaped="$(printf '%s\n' "${old_line}" | sed 's/[&/\]/\\&/g')"
        sed -i "/^${escaped}$/d" "${file}"

        # Remove the file if it's now empty (ignoring comments/blanks)
        if ! grep -qE '^[^#[:space:]]' "${file}" 2>/dev/null; then
            rm -f "${file}"
            SUCCESS "Entry deleted and empty file $(basename "${file}") removed."
        else
            SUCCESS "Entry deleted from $(basename "${file}")."
        fi
    }

    # ── Sub-menu loop ─────────────────────────────────────────────────────────
    while true; do
        HEADER "Manage /etc/portage/package.use"
        echo
        printf "  ${GREEN}${BOLD}[a]${RESET}  ${WHITE}Add a package.use entry${RESET}\n"
        printf "  ${GREEN}${BOLD}[l]${RESET}  ${WHITE}List all entries${RESET}\n"
        printf "  ${GREEN}${BOLD}[e]${RESET}  ${WHITE}Edit an entry${RESET}\n"
        printf "  ${GREEN}${BOLD}[d]${RESET}  ${WHITE}Delete an entry${RESET}\n"
        printf "  ${RED}${BOLD}[b]${RESET}  ${WHITE}Back to main menu${RESET}\n"
        echo
        HR
        printf "  ${YELLOW}${BOLD}Select: ${RESET}"
        read -r sub
        case "${sub}" in
            a|A) _pkguse_add    ;;
            l|L)
                HEADER "All package.use Entries"
                HR
                _pkguse_list_entries || true
                HR
                ;;
            e|E) _pkguse_edit   ;;
            d|D) _pkguse_delete ;;
            b|B|0|q|Q) break    ;;
            *) WARN "Unknown option '${sub}'." ;;
        esac
        press_enter
    done
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

    printf "  ${GREEN}${BOLD}[6]${RESET}  ${WHITE}Manage package.use${RESET}"
    printf "      ${DIM}— add, list, edit & delete per-package USE flags${RESET}\n"

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
            6) opt_packageuse;;
            0|q|Q|exit)
                echo
                printf "  ${GREEN}Goodbye.${RESET}\n\n"
                exit 0
                ;;
            *)
                echo
                WARN "Unknown option '${choice}' — please choose 0–6."
                sleep 1
                ;;
        esac
    done
}

main "$@"