#!/usr/bin/env bash
#d: Install MatugenFox (Firefox theme from wallpaper) extension + native host

set -euo pipefail

# --- Styling & Colors ---
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_INFO=$'\033[34m'
C_SUCCESS=$'\033[32m'
C_WARN=$'\033[33m'
C_ERR=$'\033[31m'

log_info()    { printf "${C_BOLD}${C_INFO}[INFO]${C_RESET} %s\n" "$1"; }
log_success() { printf "${C_BOLD}${C_SUCCESS}[OK]${C_RESET} %s\n" "$1"; }
log_warn()    { printf "${C_BOLD}${C_WARN}[WARN]${C_RESET} %s\n" "$1"; }
log_error()   { printf "${C_BOLD}${C_ERR}[ERROR]${C_RESET} %s\n" "$1" >&2; }

AUTO_MODE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--auto) AUTO_MODE=1; shift ;;
        *) log_error "Unknown argument: $1"; exit 1 ;;
    esac
done

# --- Configuration ---
readonly EXT_ID="matugenfox@ubaid.com"
readonly EXT_VERSION="2.0.2"
readonly XPI_URL="https://addons.mozilla.org/firefox/downloads/file/4913588/matugenfox-${EXT_VERSION}.xpi"
readonly AMO_PAGE_URL="https://addons.mozilla.org/en-US/firefox/addon/matugenfox/"
readonly SHARE_DIR="${HOME}/.local/share/matugenfox"
readonly XPI_FILE="${SHARE_DIR}/matugenfox-${EXT_VERSION}.xpi"
readonly HOST_BUNDLED="${HOME}/user_scripts/firefox/matugenfox/matugenfox_host.py"
readonly HOST_INSTALLED="${SHARE_DIR}/matugenfox_host.py"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/matugenfox"
readonly CONFIG_FILE="${CONFIG_DIR}/config.json"

# --- 1. Pre-flight ---
for cmd in curl python3; do
    command -v "$cmd" >/dev/null 2>&1 || { log_error "Missing required command: $cmd"; exit 1; }
done

# Resolve the real Firefox root — handle both ~/.mozilla and ~/.config/mozilla (XDG) layouts
# Prefer the candidate that actually contains firefox profiles
MOZ_ROOT=""
for candidate in "${HOME}/.mozilla" "${HOME}/.config/mozilla"; do
    if [[ -d "$candidate" ]]; then
        resolved=$(realpath "$candidate" 2>/dev/null || readlink -f "$candidate" || printf '%s' "$candidate")
        [[ -d "$resolved" ]] || continue
        # ~/.mozilla may contain an inner 'mozilla' symlink pointing at the real root
        if [[ -d "${resolved}/mozilla" ]]; then
            resolved=$(realpath "${resolved}/mozilla" 2>/dev/null || printf '%s' "${resolved}/mozilla")
        fi
        if [[ -d "${resolved}/firefox" ]]; then
            if compgen -G "${resolved}/firefox/*/prefs.js" > /dev/null 2>&1; then
                MOZ_ROOT="$resolved"
                break
            fi
            # Keep as fallback if it has firefox dir but no prefs yet
            if [[ -z "$MOZ_ROOT" ]]; then
                MOZ_ROOT="$resolved"
            fi
        fi
    fi
done

# Fallback: if MOZ_ROOT doesn't have firefox, try the other layout explicitly
if [[ -z "$MOZ_ROOT" || ! -d "${MOZ_ROOT}/firefox" ]]; then
    for candidate in "${HOME}/.config/mozilla" "${HOME}/.mozilla"; do
        if [[ -d "${candidate}/firefox" ]] && compgen -G "${candidate}/firefox/*/prefs.js" > /dev/null 2>&1; then
            MOZ_ROOT=$(realpath "$candidate" 2>/dev/null || printf '%s' "$candidate")
            break
        fi
    done
fi

if [[ -z "$MOZ_ROOT" ]]; then
    log_warn "No Mozilla profile root found. Skipping."
    exit 0
fi

readonly MOZ_ROOT
readonly FIREFOX_ROOT="${MOZ_ROOT}/firefox"
# Firefox reads user-scope native messaging manifests from ~/.mozilla/... ;
# also mirror into the resolved root so both layouts stay covered.
readonly MANIFEST_DIRS=("${HOME}/.mozilla/native-messaging-hosts" "${MOZ_ROOT}/native-messaging-hosts" "${HOME}/.config/mozilla/native-messaging-hosts")

if [[ ! -d "$FIREFOX_ROOT" ]]; then
    log_warn "No Firefox profiles found under ${FIREFOX_ROOT}. Skipping."
    exit 0
fi
log_info "Firefox root resolved: ${MOZ_ROOT}"

# --- 2. Download extension ---
log_info "Downloading MatugenFox ${EXT_VERSION} extension..."
mkdir -p "$SHARE_DIR"

if [[ ! -f "$XPI_FILE" ]] || [[ "$(head -c2 "$XPI_FILE")" != "PK" ]]; then
    if ! curl -sSLf "$XPI_URL" -o "$XPI_FILE" 2>/dev/null; then
        log_warn "Pinned download failed, falling back to latest release from AMO page..."
        latest_url=$(curl -sSLf "$AMO_PAGE_URL" 2>/dev/null | grep -o 'https://addons.mozilla.org[^"]*matugenfox-[0-9.]*\.xpi' | head -1 || true)
        if [[ -z "$latest_url" ]]; then
            log_error "Could not download MatugenFox extension. Skipping."
            exit 0
        fi
        curl -sSLf "$latest_url" -o "$XPI_FILE"
    fi
    [[ "$(head -c2 "$XPI_FILE")" == "PK" ]] || { log_error "Downloaded file is not a valid XPI. Skipping."; exit 0; }
fi
log_success "Extension archive ready: ${XPI_FILE}"

# --- 3. Native messaging host ---
log_info "Installing MatugenFox native messaging host..."
[[ -f "$HOST_BUNDLED" ]] || { log_error "Bundled host script not found at ${HOST_BUNDLED}. Skipping."; exit 0; }
cp -f "$HOST_BUNDLED" "$HOST_INSTALLED"
chmod +x "$HOST_INSTALLED"

for manifest_dir in "${MANIFEST_DIRS[@]}"; do
    mkdir -p "$manifest_dir"
    cat > "${manifest_dir}/matugenfox.json" <<EOF
{
  "name": "matugenfox",
  "description": "MatugenFox Native Messaging Host",
  "path": "${HOST_INSTALLED}",
  "type": "stdio",
  "allowed_extensions": [
    "${EXT_ID}"
  ]
}
EOF
    log_success "Native host manifest installed: ${manifest_dir}/matugenfox.json"
done

# --- 4. Default configuration ---
log_info "Initializing MatugenFox configuration..."
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<EOF
{
  "ecoMode": true,
  "colorsPath": "~/.config/matugen/generated/firefox_websites.css",
  "websitesDir": "~/.config/dusky_sites",
  "browserThemeEnabled": true,
  "webThemeEnabled": false
}
EOF
    log_success "Config written: ${CONFIG_FILE}"
else
    log_warn "Config already exists; keeping existing configuration."
fi

# --- 5. Install extension into every Firefox profile ---
log_info "Installing extension into Firefox profiles..."
INSTALLED=0
shopt -s nullglob
for prefs in "${FIREFOX_ROOT}"/*/prefs.js; do
    profile_dir="${prefs%/prefs.js}"
    ext_dir="${profile_dir}/extensions"
    mkdir -p "$ext_dir"
    cp -f "$XPI_FILE" "${ext_dir}/${EXT_ID}.xpi"
    log_success "Installed into profile: ${profile_dir##*/}"
    INSTALLED=$((INSTALLED + 1))

    # Ensure required prefs (silent install + theme stylesheets)
    user_js="${profile_dir}/user.js"
    touch "$user_js"
    for pref in \
        'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' \
        'user_pref("extensions.autoDisableScopes", 0);' \
        'user_pref("extensions.enabledScopes", 15);'; do
        grep -qxF "$pref" "$user_js" || printf '%s\n' "$pref" >> "$user_js"
    done
done
shopt -u nullglob

if (( INSTALLED == 0 )); then
    log_warn "No Firefox profiles found. Extension not installed."
else
    log_success "Extension installed into ${INSTALLED} profile(s). Restart Firefox to load it."
fi

# --- 6. Materialize the MatugenFox color file ---
log_info "Generating firefox_websites.css via the theme engine..."
if command -v matugen >/dev/null 2>&1 && [[ -f "${HOME}/user_scripts/theme_matugen/theme_ctl.sh" ]]; then
    if ! "${HOME}/user_scripts/theme_matugen/theme_ctl.sh" refresh >/dev/null 2>&1; then
        log_warn "Theme refresh failed (no display yet?). Colors will appear on the next theme change."
    fi
    if [[ -f "${HOME}/.config/matugen/generated/firefox_websites.css" ]]; then
        log_success "firefox_websites.css generated. Firefox will recolor live on theme changes."
    else
        log_warn "firefox_websites.css not generated yet; next theme change will create it."
    fi
else
    log_warn "Matugen engine not available; firefox_websites.css will be created on first theme generation."
fi

log_success "MatugenFox setup complete."
exit 0
