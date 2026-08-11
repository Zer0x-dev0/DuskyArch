#!/usr/bin/env bash
#d: Install Spotube — open-source music client (no Premium, no ads)

set -euo pipefail
IFS=$'\n\t'

# --- Styling & Colors ---
readonly C_RESET=$'\033[0m'
readonly C_BOLD=$'\033[1m'
readonly C_INFO=$'\033[34m'    # Blue
readonly C_SUCCESS=$'\033[32m' # Green
readonly C_ERR=$'\033[31m'     # Red
readonly C_WARN=$'\033[33m'    # Yellow

# --- Configuration ---
readonly SPOTUBE_API="https://api.github.com/repos/KRTirtho/spotube/releases/latest"
readonly SYS_ARCH="$(uname -m)"
readonly LOCAL_DIR="$HOME/.local/share/spotube"
readonly LOCAL_BIN="$HOME/.local/bin"
readonly LOCAL_APPS="$HOME/.local/share/applications"
readonly LOCAL_ICONS="$HOME/.local/share/icons"
TMP_DIR=""

# --- Logging Helpers ---
log_info()    { printf "${C_BOLD}${C_INFO}[INFO]${C_RESET} %s\n" "$1"; }
log_success() { printf "${C_BOLD}${C_SUCCESS}[OK]${C_RESET} %s\n" "$1"; }
log_warn()    { printf "${C_BOLD}${C_WARN}[WARN]${C_RESET} %s\n" "$1"; }
log_error()   { printf "${C_BOLD}${C_ERR}[ERROR]${C_RESET} %s\n" "$1" >&2; }

# --- Cleanup Trap ---
cleanup() {
    local exit_code=$?
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code."
    fi
}
trap cleanup EXIT

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
    for pkg in spotify spotifyd ncspot; do
        if pacman -Q "$pkg" &>/dev/null; then
            installed+=("$pkg")
        fi
    done

    if [[ ${#installed[@]} -gt 0 ]]; then
        log_warn "Removing old Spotify packages: ${installed[*]}"
        systemctl --user disable --now spotifyd.service 2>/dev/null || true
        systemctl --user disable --now "spotifyd@$(hostname).service" 2>/dev/null || true
        "$AUR_HELPER" -Rns --noconfirm "${installed[@]}" || true
    fi
}

install_spotube_arm() {
    # Runtime dependencies (all in the ALARM repos) — same set the AUR package declares
    install_packages "$AUR_HELPER" mpv libappindicator-gtk3 libsecret jsoncpp libnotify \
        xdg-user-dirs webkit2gtk-4.1

    local asset_url=""
    log_info "Fetching latest Spotube release info..."
    asset_url="$(curl -sSLf "$SPOTUBE_API" 2>/dev/null \
        | grep -oE '"browser_download_url":\s*"[^"]*aarch64\.tar\.xz"' \
        | grep -oE 'https://[^"]+' | head -1 || true)"

    if [[ -z "$asset_url" ]]; then
        log_error "No aarch64 build found. Check https://github.com/KRTirtho/spotube/releases"
        exit 1
    fi

    TMP_DIR="$(mktemp -d)"
    log_info "Downloading $(basename "$asset_url") ..."
    curl -sSLf "$asset_url" -o "$TMP_DIR/spotube.tar.xz"

    log_info "Extracting to $LOCAL_DIR ..."
    mkdir -p "$LOCAL_DIR" "$LOCAL_BIN" "$LOCAL_APPS" "$LOCAL_ICONS"
    tar -xJf "$TMP_DIR/spotube.tar.xz" -C "$LOCAL_DIR" --strip-components=1

    # Launcher in ~/.local/bin
    ln -sf "$LOCAL_DIR/spotube" "$LOCAL_BIN/spotube"

    # Icon + desktop entry with corrected local paths
    install -m644 "$LOCAL_DIR/spotube-logo.png" "$LOCAL_ICONS/spotube.png"
    sed -e "s|Exec=.*|Exec=$LOCAL_BIN/spotube|" \
        -e "s|Icon=.*|Icon=$LOCAL_ICONS/spotube.png|" \
        "$LOCAL_DIR/spotube.desktop" > "$LOCAL_APPS/spotube.desktop"
    update-desktop-database "$LOCAL_APPS" 2>/dev/null || true

    log_success "Spotube installed to $LOCAL_DIR (launcher: spotube)."
}

# --- Main Logic ---

# 1. User Confirmation
printf "${C_BOLD}${C_WARN}[?]${C_RESET} Do you want to install/update Spotube? [y/N] "
read -r response

if [[ "${response,,}" != "y" && "${response,,}" != "yes" ]]; then
    log_info "Operation cancelled by user."
    exit 0
fi

# 2. Environment Setup
detect_aur_helper
remove_old_spotify

# 3. Install Spotube (official client & AUR package are x86_64-only)
if [[ "$SYS_ARCH" == "x86_64" ]]; then
    install_packages "$AUR_HELPER" spotube-bin
else
    install_spotube_arm
fi

log_success "Process finished. Spotube is ready — no Spotify Premium needed."