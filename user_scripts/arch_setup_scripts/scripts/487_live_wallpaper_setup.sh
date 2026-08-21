#!/usr/bin/env bash
#d: Install mpvpaper for live wallpapers (video wallpapers via mpv)

set -euo pipefail

# --- Colors ---
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_GREEN=$'\033[1;32m'
    C_BLUE=$'\033[1;34m'
    C_RED=$'\033[1;31m'
    C_YELLOW=$'\033[1;33m'
else
    C_RESET='' C_GREEN='' C_BLUE='' C_RED='' C_YELLOW=''
fi

log_info()    { printf "${C_BLUE}[INFO]${C_RESET} %s\n" "$1"; }
log_success() { printf "${C_GREEN}[OK]${C_RESET} %s\n" "$1"; }
log_warn()    { printf "${C_YELLOW}[WARN]${C_RESET} %s\n" "$1" >&2; }
log_error()   { printf "${C_RED}[ERROR]${C_RESET} %s\n" "$1" >&2; }

# --- Mode ---
AUTO_MODE=false
for arg in "$@"; do
    case "$arg" in
        --auto|--yes|-y) AUTO_MODE=true ;;
    esac
done

log_info "Starting Live Wallpaper (mpvpaper) setup..."

# --- AUR helper detection ---
detect_aur_helper() {
    if command -v paru &>/dev/null; then printf 'paru'; return 0; fi
    if command -v yay  &>/dev/null; then printf 'yay';  return 0; fi
    return 1
}

# --- Network check ---
NETWORK_AVAILABLE=true
if ! timeout 2 bash -c '</dev/tcp/github.com/443' 2>/dev/null; then
    NETWORK_AVAILABLE=false
    log_warn "No internet detected (github.com:443 unreachable). Offline mode."
fi

# --- Already installed? ---
if command -v mpvpaper >/dev/null 2>&1 || pacman -Qi mpvpaper &>/dev/null; then
    log_success "mpvpaper is already installed ($(command -v mpvpaper 2>/dev/null || echo "pacman")) — skipping install."
else
    if [[ "$NETWORK_AVAILABLE" == false ]]; then
        log_warn "Offline — cannot install mpvpaper. Skipping."
        exit 0
    fi

    if ! command -v pacman &>/dev/null; then
        log_error "pacman not found — not an Arch system?"
        exit 1
    fi

    AUR_HELPER=""
    if ! AUR_HELPER=$(detect_aur_helper); then
        log_error "No AUR helper (paru/yay) found. Install paru first: https://github.com/Morganamilo/paru"
        exit 1
    fi

    log_info "Installing mpvpaper via ${AUR_HELPER} (AUR)..."
    if ! "$AUR_HELPER" -S --needed --noconfirm mpvpaper; then
        # AUR package is x86_64-only; on aarch64/ARM build from source
        if [[ "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm"* ]]; then
            log_warn "AUR build failed (likely arch mismatch) — building mpvpaper from source for $(uname -m)..."
            # Ensure build deps
            for dep in meson ninja git wayland wayland-protocols mpv; do
                if ! pacman -Qi "$dep" &>/dev/null && ! pacman -Qi "python-$dep" &>/dev/null; then
                    log_info "Installing build dep: $dep"
                    sudo pacman -S --needed --noconfirm "$dep" 2>/dev/null || true
                fi
            done
            if ! command -v meson &>/dev/null || ! command -v ninja &>/dev/null; then
                if ! sudo pacman -S --needed --noconfirm meson ninja 2>/dev/null; then
                    log_error "Failed to install meson/ninja for mpvpaper build."
                    exit 1
                fi
            fi
            tmp_src=$(mktemp -d)
            if ! git clone --depth 1 https://github.com/GhostNaN/mpvpaper.git "$tmp_src" 2>&1 | tail -3; then
                log_error "Failed to clone mpvpaper source."
                rm -rf -- "$tmp_src"
                exit 1
            fi
            # Build into $HOME/.local (no sudo needed)
            if meson setup "$tmp_src/build" --prefix="$HOME/.local" 2>&1 | tail -5 && \
               ninja -C "$tmp_src/build" 2>&1 | tail -5 && \
               ninja -C "$tmp_src/build" install 2>&1 | tail -5; then
                rm -rf -- "$tmp_src"
                if command -v mpvpaper >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/mpvpaper" ]]; then
                    log_success "mpvpaper built and installed to ~/.local/bin/mpvpaper (aarch64 source build)."
                else
                    log_warn "Build reported success but mpvpaper not in PATH. Check ~/.local/bin."
                fi
            else
                log_error "Failed to build mpvpaper from source."
                rm -rf -- "$tmp_src"
                exit 1
            fi
        else
            log_error "Failed to install mpvpaper via ${AUR_HELPER}."
            exit 1
        fi
    else
        log_success "mpvpaper installed."
    fi
fi

# --- Verify ffmpeg (needed for poster extraction + thumbnails) ---
if ! command -v ffmpeg &>/dev/null; then
    if [[ "$NETWORK_AVAILABLE" == false ]]; then
        log_warn "ffmpeg missing and offline — poster extraction will fail until ffmpeg is installed."
    else
        log_info "ffmpeg not found — installing..."
        if ! sudo pacman -S --needed --noconfirm ffmpeg; then
            log_warn "Failed to install ffmpeg (poster extraction requires it)."
        else
            log_success "ffmpeg installed."
        fi
    fi
else
    log_success "ffmpeg available: $(ffmpeg -version 2>/dev/null | head -n1)"
fi

# --- Verify mpv ---
if ! command -v mpv &>/dev/null; then
    log_warn "mpv not found — mpvpaper requires mpv/libmpv. Install mpv via 415_mpv_setup.sh or pacman."
else
    log_success "mpv available: $(mpv --version 2>/dev/null | head -n1)"
fi

# --- Permissions & state dir ---
mkdir -p -- "$HOME/.cache/dusky-live-wall/posters" "$HOME/.config/dusky/settings/dusky_theme" 2>/dev/null || true
chmod +x -- "$HOME/user_scripts/theme_matugen/live_wall_ctl.sh" 2>/dev/null || true
chmod +x -- "$HOME/user_scripts/theme_matugen/theme_ctl.sh" 2>/dev/null || true

# --- Ensuring state.conf has LIVE_WALL_SOUND default (theme_ctl auto-migrates) ---
if [[ -f "$HOME/user_scripts/theme_matugen/theme_ctl.sh" ]]; then
    # Touch theme_ctl to trigger read_state → write_state migration on next `get`
    "$HOME/user_scripts/theme_matugen/theme_ctl.sh" get >/dev/null 2>&1 || true
fi

# --- Summary ---
printf '\n%s====================================================%s\n' "$C_GREEN" "$C_RESET"
printf '%s   Live Wallpaper setup complete!                    %s\n' "$C_GREEN" "$C_RESET"
printf '%s====================================================%s\n' "$C_GREEN" "$C_RESET"
cat <<'EOF'
Usage:
  - Drop videos (mp4/mkv/webm/mov/avi/m4v) into ~/Pictures/wallpapers/
  - Pick them from the wallpaper selector (CTRL+SPACE or ALT+4) — they show
    with auto-generated thumbnails (ffmpeg extracts a poster frame).
  - Or run directly:  ~/user_scripts/theme_matugen/live_wall_ctl.sh set <video>
                      ~/user_scripts/theme_matugen/theme_ctl.sh set <video>
                      ~/user_scripts/theme_matugen/theme_ctl.sh next   (cycles videos too)

Controls:
  SUPER+ALT+apostrophe        Toggle pause/resume
  SUPER+CTRL+apostrophe       Stop live wallpaper
  SUPER+ALT+SHIFT+apostrophe  Toggle sound (muted by default)
  live_wall_ctl.sh status     Show current live wallpaper status
  live_wall_ctl.sh poster <video>  Print cached poster path

Theming:
  Matugen colors are extracted from an auto-cached poster frame
  (~/.cache/dusky-live-wall/posters/<hash>.jpg), so live wallpapers
  theme the system exactly like static images. Switching back to an
  image wallpaper automatically stops mpvpaper.
EOF
log_info "Done."
