#!/usr/bin/env bash
# Install the Dusky SDDM theme + activate it in SDDM config.
# Safe to re-run: preserves existing [X11] / [General] sections.

set -euo pipefail

readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly CYAN=$'\033[0;36m'
readonly RESET=$'\033[0m'

log_info() { printf '%b[INFO]%b %s\n' "${CYAN}" "${RESET}" "$1"; }
log_success() { printf '%b[OK]%b %s\n' "${GREEN}" "${RESET}" "$1"; }
log_warn() { printf '%b[WARN]%b %s\n' "${YELLOW}" "${RESET}" "$1" >&2; }

# Remember the calling user's home before dropping to root
USER_HOME="${HOME}"
if [[ $EUID -ne 0 ]]; then
	exec sudo "$0" "$@"
fi

readonly THEME_NAME="dusky_sddm"
readonly SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/dusky_sddm" && pwd)"
readonly DST_DIR="/usr/share/sddm/themes/${THEME_NAME}"
readonly SDDM_CONF="/etc/sddm.conf.d/10-dusky-theme.conf"

[[ -d "${SRC_DIR}" ]] || { log_warn "Theme source not found at ${SRC_DIR}"; exit 1; }

log_info "Installing theme to ${DST_DIR}"
install -d "${DST_DIR}/components"
cp -f "${SRC_DIR}/Main.qml" "${SRC_DIR}/theme.conf" "${SRC_DIR}/metadata.desktop" "${DST_DIR}/"
cp -f "${SRC_DIR}/components/"*.qml "${DST_DIR}/components/"

# Wallpaper: use the current user's active wallpaper if available
WALLPAPER_SRC=""
if [[ -f "${USER_HOME}/.cache/current_wallpaper" ]]; then
	WALLPAPER_SRC="${USER_HOME}/.cache/current_wallpaper"
fi

if [[ -n "${WALLPAPER_SRC}" ]]; then
	cp -f "${WALLPAPER_SRC}" "${DST_DIR}/wallpaper.jpg"
	log_success "Wallpaper copied from ${WALLPAPER_SRC}"
elif [[ ! -f "${DST_DIR}/wallpaper.jpg" ]]; then
	log_warn "No wallpaper found; theme will use a dark background."
	touch "${DST_DIR}/wallpaper.jpg"
fi

# Activate theme in SDDM config (idempotent, keeps other sections)
install -d /etc/sddm.conf.d
if grep -q '^\[Theme\]' "${SDDM_CONF}" 2>/dev/null; then
	grep -q '^Current=' "${SDDM_CONF}" || sed -i '/^\[Theme\]/a Current='"${THEME_NAME}" "${SDDM_CONF}"
else
	printf '\n[Theme]\nCurrent=%s\n' "${THEME_NAME}" >>"${SDDM_CONF}"
fi

log_success "Theme activated in ${SDDM_CONF}:"
grep -A2 '^\[Theme\]' "${SDDM_CONF}" | sed 's/^/  /'

log_info "Restart SDDM to see it: sudo systemctl restart sddm"
log_info "  (only do this from a logged-out console, or reboot)"
