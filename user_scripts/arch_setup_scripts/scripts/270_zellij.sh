#!/usr/bin/env bash
#d: Install Zellij — terminal multiplexer with plugin support

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

    log_info "Installing/Verifying packages: $(IFS=' '; echo "${packages[*]}")"

    if "$helper" -S --needed --noconfirm "${packages[@]}"; then
        log_success "Packages installed/verified."
    else
        log_error "Failed to install packages via $helper."
        exit 1
    fi
}

setup_zellij_config() {
    log_info "Setting up Zellij configuration..."
    
    mkdir -p "$HOME/.config/zellij"
    
    # Enable matugen template for zellij
    if [[ -f "$HOME/.config/matugen/config.toml" ]]; then
        log_info "Enabling Zellij matugen template..."
        sed -i '/^\[templates\.zellij\]/,/^\[/s/^enabled\s*=.*/enabled = true/' "$HOME/.config/matugen/config.toml"
    fi
    
    # Create basic config.kdl if it doesn't exist
    if [[ ! -f "$HOME/.config/zellij/config.kdl" ]]; then
        cat > "$HOME/.config/zellij/config.kdl" << 'EOF'
// Zellij configuration
// Theme is managed by matugen - symlink points to generated theme

theme "matugen"

// UI settings
pane_frames true
pane_frame_colors true
scrollback_lines 10000

// Keybindings (customize as needed)
keybinds {
    shared_except "locked" {
        bind "Ctrl p" { SwitchTabNext; }
        bind "Ctrl n" { SwitchTabPrev; }
        bind "Ctrl h" { MoveFocus Left; }
        bind "Ctrl j" { MoveFocus Down; }
        bind "Ctrl k" { MoveFocus Up; }
        bind "Ctrl l" { MoveFocus Right; }
    }
}

// Session settings
default_shell "/usr/bin/zsh"
EOF
        log_success "Created basic Zellij config at ~/.config/zellij/config.kdl"
    else
        log_info "Zellij config already exists, skipping creation"
    fi
    
    # Create themes directory
    mkdir -p "$HOME/.config/zellij/themes"
    
    log_success "Zellij configuration ready"
}

# --- Main Logic ---

printf "${C_BOLD}${C_WARN}[?]${C_RESET} Do you want to install/update Zellij? [y/N] "
read -r response

if [[ "${response,,}" != "y" && "${response,,}" != "yes" ]]; then
    log_info "Operation cancelled by user."
    exit 0
fi

# 1. Environment Setup
detect_aur_helper

# 2. Install Zellij
log_info "Installing Zellij..."
install_packages "$AUR_HELPER" zellij

# 3. Setup configuration
setup_zellij_config

# 4. Regenerate matugen theme for zellij
if command -v matugen &>/dev/null; then
    log_info "Regenerating matugen theme for Zellij..."
    matugen --config ~/.config/matugen/config.toml json ~/.config/matugen/generated_profiles/scheme-tonal-spot/colors.json 2>/dev/null || true
    log_info "Run 'theme_ctl refresh' to apply theme to Zellij"
fi

log_success "Zellij installed and configured. Run 'zellij' to start."