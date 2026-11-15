#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Breno Rodrigues Alves
#
# rectify.sh - Deep universal updater for Linux distributions
#
# Updates the system with the native package manager, previews removals
# and ASKS before removing obsolete/orphaned packages or cleaning caches.
# The user may choose to KEEP the packages (answer "N").
#
# Usage: sudo ./rectify.sh [options]
#

set -euo pipefail

# ---------- Colors ----------
readonly RED='\033[0;35m'
readonly GREEN='\033[38;5;35m'
readonly YELLOW='\033[38;5;226m'
readonly BLUE='\033[38;2;28;57;187m'
readonly NC='\033[0m'

# ---------- Options ----------
ASSUME_YES=false     # -y: don't prompt for UPGRADES
AUTO_REMOVE=false    # --auto-remove: also remove obsolete pkgs without asking

show_help() {
    cat <<EOF
Usage: sudo $0 [options]

Options:
  -y, --yes         Do not ask for confirmation on UPGRADES.
                    REMOVAL steps of obsolete packages WILL STILL
                    prompt the user.
  --auto-remove     Remove obsolete packages WITHOUT asking (careful!
                    combine with -y for fully non-interactive mode).
  -h, --help        Show this help.

Default behavior (no options):
  • Updates the system showing the native package manager's plan.
  • BEFORE removing orphaned/obsolete packages or cleaning caches,
    lists them and asks [y/N]. Answering "N" keeps the packages.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)      ASSUME_YES=true ;;
        --auto-remove) AUTO_REMOVE=true ;;
        -h|--help)     show_help; exit 0 ;;
        *) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
    esac
    shift
done

# ---------- Logging ----------
log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------- Helpers ----------
run_sudo() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Asks the user whether to accept removal/cleanup. Returns 0 (yes) or 1 (no).
# If --auto-remove was given, skips the prompt and returns 0.
ask_remove() {
    local description="$1"
    if $AUTO_REMOVE; then
        log_warn "Automatic removal enabled (--auto-remove): $description"
        return 0
    fi
    echo
    log_warn "Removal/cleanup step: $description"
    echo "  Packages will NOT be removed if you answer 'N'."
    local reply=""
    read -r -p "  Proceed? [y/N] " reply || true
    case "$reply" in
        [yYsS]) return 0 ;;
        *) log_info "Step skipped — packages kept."; return 1 ;;
    esac
}

# Confirms whether to continue an upgrade that would remove packages
confirm_upgrade_with_removals() {
    local removals="$1"
    if [[ -z "$removals" ]]; then
        return 0
    fi
    log_warn "The upgrade would remove the following packages:"
    echo "$removals" | sed 's/^/    /'
    if $ASSUME_YES; then
        log_warn "-y mode active: proceeding anyway."
        return 0
    fi
    local reply=""
    read -r -p "  Continue the upgrade anyway? [y/N] " reply || true
    case "$reply" in
        [yYsS]) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------- Package manager detection ----------
detect_pm() {
    for cmd in apt dnf yum pacman zypper apk xbps-install emerge; do
        if command -v "$cmd" &>/dev/null; then
            case "$cmd" in
                xbps-install) echo "xbps" ;;
                *)            echo "$cmd" ;;
            esac
            return 0
        fi
    done
    echo "unknown"
}

# =========================================================
#  Per-manager routines
# =========================================================

update_apt() {
    log_info "Updating APT (Debian/Ubuntu/Mint)…"
    run_sudo apt update

    local upgrade_removals
    upgrade_removals=$(apt-get -s full-upgrade 2>/dev/null | sed -n '/^Remv/p' || true)
    if ! confirm_upgrade_with_removals "$upgrade_removals"; then
        log_warn "Upgrade canceled by user."
        return 0
    fi

    if $ASSUME_YES; then
        run_sudo apt full-upgrade -y
    else
        run_sudo apt full-upgrade
    fi

    # autoremove — always asks
    local autoremovals
    autoremovals=$(apt-get -s autoremove 2>/dev/null | sed -n '/^Remv/p' || true)
    if [[ -n "$autoremovals" ]]; then
        echo
        log_info "Packages 'apt autoremove' would remove:"
        echo "$autoremovals" | sed 's/^/    /'
        if ask_remove "remove these obsolete packages with 'apt autoremove'?"; then
            run_sudo apt autoremove -y
        fi
    else
        log_ok "No obsolete packages for 'autoremove'."
    fi

    if ask_remove "clean the package cache with 'apt autoclean'?"; then
        run_sudo apt autoclean -y
    fi
    log_ok "APT finished."
}

update_dnf() {
    log_info "Updating DNF (Fedora/RHEL/CentOS Stream)…"
    if $ASSUME_YES; then
        run_sudo dnf upgrade --refresh -y
    else
        run_sudo dnf upgrade --refresh
    fi

    echo
    log_info "Preview of orphaned packages (dnf autoremove --assumeno):"
    run_sudo dnf autoremove --assumeno 2>&1 | sed 's/^/    /' || true

    if ask_remove "remove orphaned packages with 'dnf autoremove'?"; then
        run_sudo dnf autoremove -y
    fi
    log_ok "DNF finished."
}

update_yum() {
    log_info "Updating YUM (old RHEL/CentOS)…"
    if $ASSUME_YES; then
        run_sudo yum update -y
    else
        run_sudo yum update
    fi

    echo
    log_info "Preview of orphaned packages (yum autoremove):"
    run_sudo yum autoremove 2>&1 | sed 's/^/    /' || true

    if ask_remove "remove orphaned packages with 'yum autoremove'?"; then
        run_sudo yum autoremove -y
    fi
    log_ok "YUM finished."
}

update_pacman() {
    log_info "Updating Pacman (Arch/Manjaro)…"
    if $ASSUME_YES; then
        run_sudo pacman -Syu --noconfirm
    else
        run_sudo pacman -Syu
    fi

    # Orphans
    local orphans
    orphans=$(pacman -Qtdq 2>/dev/null || true)
    echo
    if [[ -n "$orphans" ]]; then
        log_info "Orphaned packages found:"
        echo "$orphans" | sed 's/^/    /'
        if ask_remove "remove orphaned packages with 'pacman -Rns'?"; then
            # shellcheck disable=SC2086
            run_sudo pacman -Rns $orphans --noconfirm
        fi
    else
        log_ok "No orphaned packages."
    fi

    if ask_remove "clean the Pacman cache ('pacman -Sc')?"; then
        run_sudo pacman -Sc --noconfirm
    fi
    log_ok "Pacman finished."
}

update_zypper() {
    log_info "Updating Zypper (openSUSE/SUSE)…"
    run_sudo zypper refresh
    if $ASSUME_YES; then
        run_sudo zypper dup --allow-vendor-change -y
    else
        run_sudo zypper dup --allow-vendor-change
    fi

    if ask_remove "clean the Zypper cache ('zypper clean --all')?"; then
        run_sudo zypper clean --all
    fi
    log_ok "Zypper finished."
}

update_apk() {
    log_info "Updating APK (Alpine Linux)…"
    run_sudo apk update
    # apk upgrade asks for confirmation by default (no -y flag)
    run_sudo apk upgrade --available

    if ask_remove "clean the APK cache ('apk cache clean')?"; then
        run_sudo apk cache clean
    fi
    log_ok "APK finished."
}

update_xbps() {
    log_info "Updating XBPS (Void Linux)…"
    if $ASSUME_YES; then
        run_sudo xbps-install -S -u -y
    else
        run_sudo xbps-install -S -u
    fi

    # Preview orphans
    local preview
    preview=$(xbps-remove -n -o 2>/dev/null || true)
    echo
    if [[ -n "$preview" ]]; then
        log_info "Orphaned packages that would be removed:"
        echo "$preview" | sed 's/^/    /'
        if ask_remove "remove orphaned packages with 'xbps-remove -o'?"; then
            run_sudo xbps-remove -o -y
        fi
    else
        log_ok "No orphaned packages."
    fi
    log_ok "XBPS finished."
}

update_emerge() {
    log_info "Updating Portage/Emerge (Gentoo)…"
    run_sudo emerge --sync

    # --ask always shows the plan and prompts
    run_sudo emerge --ask --update --deep --newuse --with-bdeps=y @world

    echo
    log_info "Unused packages that 'emerge --depclean' would remove:"
    run_sudo emerge -p --depclean 2>/dev/null | sed 's/^/    /' || true

    if ask_remove "remove unused packages with 'emerge --depclean'?"; then
        run_sudo emerge --depclean
    fi

    if ask_remove "remove old package versions with 'emerge --prune'?"; then
        run_sudo emerge --prune
    fi
    log_ok "Portage finished."
}

# ---------- Universal managers ----------

update_flatpak() {
    command -v flatpak &>/dev/null || return 0
    log_info "Updating Flatpak…"
    if $ASSUME_YES; then
        flatpak update -y
    else
        flatpak update
    fi

    echo
    log_info "Unused Flatpak runtimes (preview):"
    flatpak uninstall --unused --dry-run 2>/dev/null | sed 's/^/    /' || true

    if ask_remove "remove unused Flatpak runtimes?"; then
        flatpak uninstall --unused -y
    fi
    log_ok "Flatpak finished."
}

update_snap() {
    command -v snap &>/dev/null || return 0
    log_info "Updating Snap…"
    run_sudo snap refresh
    log_ok "Snap finished."
}

# =========================================================
#  Main
# =========================================================
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}       Deep System Update               ${NC}"
    echo -e "${BLUE}  (removals ALWAYS ask for confirmation)${NC}"
    echo -e "${BLUE}========================================${NC}"

    local pm
    pm=$(detect_pm)
    if [[ "$pm" == "unknown" ]]; then
        log_error "No supported package manager was found."
        exit 1
    fi
    log_info "Detected package manager: $pm"
    if $ASSUME_YES;    then log_info "-y mode active (non-interactive upgrades)."; fi
    if $AUTO_REMOVE;   then log_warn "--auto-remove mode active (removals not prompted)."; fi

    case "$pm" in
        apt)    update_apt ;;
        dnf)    update_dnf ;;
        yum)    update_yum ;;
        pacman) update_pacman ;;
        zypper) update_zypper ;;
        apk)    update_apk ;;
        xbps)   update_xbps ;;
        emerge) update_emerge ;;
        *)      log_error "Manager not implemented: $pm"; exit 1 ;;
    esac

    update_flatpak
    update_snap

    echo -e "${GREEN}========================================${NC}"
    log_ok "All steps completed."
    log_warn "Reboot if the kernel or core libraries were updated."
    echo -e "${GREEN}========================================${NC}"
}

main "$@"
