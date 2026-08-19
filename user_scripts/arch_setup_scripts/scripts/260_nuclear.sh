#!/usr/bin/env bash
# dusky_interactive=true
#d: Install Nuclear — open-source music client (Flatpak, no Premium, no ads)

set -euo pipefail
IFS=$'\n\t'

# --- Styling & Colors ---
readonly C_RESET=$'\033[0m'
readonly C_BOLD=$'\033[1m'
readonly C_INFO=$'\033[34m'    # Blue
readonly C_SUCCESS=$'\033[32m' # Green
readonly C_ERR=$'\033[31m'     # Red
readonly C_WARN=$'\033[33m'    # Yellow

# --- Logging Helpers ---
log_info()    { printf "${C_BOLD}${C_INFO}[INFO]${C_RESET} %s\n" "$1"; }
log_success() { printf "${C_BOLD}${C_SUCCESS}[OK]${C_RESET} %s\n" "$1"; }
log_warn()    { printf "${C_BOLD}${C_WARN}[WARN]${C_RESET} %s\n" "$1"; }
log_error()   { printf "${C_BOLD}${C_ERR}[ERROR]${C_RESET} %s\n" "$1" >&2; }

# --- Global Variables ---
AUR_HELPER=""

# --- Functions ---

detect_aur_helper() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run as root. AUR helpers require a non-root user."
        exit 1
    fi

    if command -v paru &>/dev/null; then
        AUR_HELPER="paru"
    elif command -v yay &>/dev/null; then
        AUR_HELPER="yay"
    else
        log_error "Required AUR helper not found. Install 'paru' or 'yay' first."
        exit 1
    fi
}

install_packages() {
    local helper="$1"
    shift
    local packages=("$@")

    # Local IFS override to ensure log formatting is clean (space-separated)
    log_info "Installing/Verifying packages: $(IFS=' '; echo "${packages[*]}")"

    # --needed: Idempotency (skip if installed)
    # --noconfirm: Automated install
    if "$helper" -S --needed --noconfirm "${packages[@]}"; then
        log_success "Packages installed/verified."
    else
        log_error "Failed to install packages via $helper."
        exit 1
    fi
}

remove_old_spotify() {
    # Clean up the old official client (x86_64) and the ARM spotifyd/ncspot fallback
    local installed=()
    local pkg
    for pkg in spotify spotifyd ncspot spotube spotube-bin; do
        if pacman -Q "$pkg" &>/dev/null; then
            installed+=("$pkg")
        fi
    done

    if [[ ${#installed[@]} -gt 0 ]]; then
        log_warn "Removing old Spotify/Spotube packages: ${installed[*]}"
        systemctl --user disable --now spotifyd.service 2>/dev/null || true
        systemctl --user disable --now "spotifyd@$(hostname).service" 2>/dev/null || true
        "$AUR_HELPER" -Rns --noconfirm "${installed[@]}" || true
    fi
}

install_nuclear_flatpak() {
    if ! command -v flatpak &>/dev/null; then
        log_warn "flatpak not found. Installing it first..."
        if ! "$AUR_HELPER" -S --needed --noconfirm flatpak; then
            log_error "Failed to install flatpak."
            exit 1
        fi
    fi

    log_info "Installing Nuclear via Flatpak (Flathub)..."
    
    # Ensure Flathub remote exists
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
    sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true

    # Install Nuclear
    if flatpak install --user flathub com.nuclearplayer.Nuclear -y; then
        log_success "Nuclear installed successfully via Flatpak (user scope)."
    else
        log_warn "User install failed, trying system scope..."
        if sudo flatpak install --system flathub com.nuclearplayer.Nuclear -y; then
            log_success "Nuclear installed successfully via Flatpak (system scope)."
        else
            log_error "Failed to install Nuclear via Flatpak."
            exit 1
        fi
    fi
}

# --- Main Logic ---

# 1. User Confirmation
printf "${C_BOLD}${C_WARN}[?]${C_RESET} Do you want to install/update Nuclear? [y/N] "
read -r response

if [[ "${response,,}" != "y" && "${response,,}" != "yes" ]]; then
    log_info "Operation cancelled by user."
    exit 0
fi

# 2. Environment Setup
detect_aur_helper
remove_old_spotify

# 3. Install Nuclear (Flatpak - works on all architectures)
install_nuclear_flatpak

log_success "Process finished. Nuclear is ready — no Spotify Premium needed."