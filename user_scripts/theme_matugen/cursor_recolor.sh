#!/usr/bin/env bash
# Matugen cursor recolor: tint Bibata-based cursor template SVGs with current
# theme colors, compile to hyprcursor .hlc zips, install, and apply instantly.
#
# Colors passed via CURSOR_* env vars by matugen post_hook
# ([templates.hyprcursor] in ~/.config/matugen/config.toml).
# Fallback: matugen-generated colors.css.
set -euo pipefail

TEMPLATE_DIR="${HOME}/.config/matugen/templates/cursor"
WORK_DIR="${HOME}/.cache/dusky/matugen_cursor/working"
THEME_NAME="Matugen-Cursor"
ICONS_DIR="${HOME}/.local/share/icons"
CURSOR_SIZE="${HYPRCURSOR_SIZE:-18}"

[[ -d "$TEMPLATE_DIR" ]] || { echo "cursor templates missing: $TEMPLATE_DIR" >&2; exit 1; }

declare -A HEX=(
    [primary]="${CURSOR_PRIMARY:-}"
    [outline]="${CURSOR_OUTLINE:-}"
    [error]="${CURSOR_ERROR:-}"
    [tertiary]="${CURSOR_TERTIARY:-}"
    [secondary]="${CURSOR_SECONDARY:-}"
    [secondary_container]="${CURSOR_SECONDARY_CONTAINER:-}"
    [on_surface]="${CURSOR_ON_SURFACE:-}"
    [on_surface_variant]="${CURSOR_ON_SURFACE_VARIANT:-}"
    [on_primary_container]="${CURSOR_ON_PRIMARY_CONTAINER:-}"
)

is_hex() { [[ "$1" =~ ^#[0-9a-fA-F]{6}$ ]]; }

# Profile-swap hook re-fires post_hook verbatim; unsubstituted {{colors.*}}
# tokens are treated as unset.
for role in "${!HEX[@]}"; do
    is_hex "${HEX[$role]}" || HEX[$role]=""
done

need_fallback=0
for role in "${!HEX[@]}"; do
    [[ -n "${HEX[$role]}" ]] || need_fallback=1
done

if (( need_fallback )); then
    COLORS_CSS="${HOME}/.config/matugen/generated/colors.css"
    [[ -f "$COLORS_CSS" ]] || { echo "matugen colors.css missing: $COLORS_CSS" >&2; exit 1; }
    while IFS= read -r line; do
        read -r key role hex <<< "${line%;}"
        [[ "$key" == "@define-color" ]] || continue
        HEX[$role]="${HEX[$role]:-$hex}"
    done < "$COLORS_CSS"
fi

[[ -n "${HEX[*]// /}" ]] || { echo "no colors resolved" >&2; exit 1; }

recolor_into() {
    local src="$1" dst="$2" content tok
    content=$(<"$src")
    for role in "${!HEX[@]}"; do
        [[ -n "${HEX[$role]}" ]] || continue
        tok="{{colors.${role}.default.hex}}"
        content="${content//$tok/${HEX[$role]}}"
    done
    printf '%s' "$content" > "$dst"
}

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

while IFS= read -r -d '' file; do
    dest="${WORK_DIR}/${file#"$TEMPLATE_DIR"/}"
    mkdir -p "$(dirname "$dest")"
    recolor_into "$file" "$dest"
done < <(find "$TEMPLATE_DIR" -type f -print0)

if grep -rl '{{' "$WORK_DIR" >/dev/null 2>&1; then
    echo "unresolved matugen tokens left in cursor SVGs" >&2
    exit 1
fi

# hyprcursor 0.1.13 requires compiled .hlc themes (one zip per shape).
if ! command -v hyprcursor-util >/dev/null 2>&1; then
    echo "hyprcursor-util not found, cannot compile cursor theme" >&2
    exit 1
fi
rm -rf "$ICONS_DIR/theme_$THEME_NAME" "$ICONS_DIR/$THEME_NAME"
if ! hyprcursor-util --create "$WORK_DIR" -o "$ICONS_DIR" >/dev/null 2>&1; then
    echo "hyprcursor-util failed to compile cursor theme" >&2
    exit 1
fi
mv "$ICONS_DIR/theme_$THEME_NAME" "$ICONS_DIR/$THEME_NAME"

# Clear hyprcursor render cache so new colors aren't served stale.
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/hyprcursor" 2>/dev/null || true

# Apply cursor theme and force immediate visual refresh.
# Wayland cursor surface only re-renders on shape change or mouse move.
# Strategy: clear cache → set theme → force surface rebuild via theme toggle + mouse nudge.
hyprctl setcursor "$THEME_NAME" "$CURSOR_SIZE" >/dev/null 2>&1 || {
    SIG="${HYPRLAND_INSTANCE_SIGNATURE:-}"
    if [[ -z "$SIG" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
        for dir in "$XDG_RUNTIME_DIR"/hypr/*/; do
            [[ -S "${dir}.socket.sock" ]] && { SIG="${dir%/}"; SIG="${SIG##*/}"; break; }
        done
    fi
    [[ -n "$SIG" ]] && HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl setcursor "$THEME_NAME" "$CURSOR_SIZE" >/dev/null 2>&1 || true
}

# Force immediate cursor surface rebuild:
# 1. Toggle to fallback theme and back (forces full surface rebuild)
hyprctl setcursor Adwaita "$CURSOR_SIZE" >/dev/null 2>&1
hyprctl setcursor "$THEME_NAME" "$CURSOR_SIZE" >/dev/null 2>&1

# 2. Nudge mouse if ydotool/xdotool available (forces surface commit on Wayland)
if command -v ydotool >/dev/null 2>&1; then
    (ydotool mousemove -x 1 -y 1 && ydotool mousemove -x -1 -y -1) >/dev/null 2>&1 || true
elif command -v xdotool >/dev/null 2>&1; then
    (xdotool mousemove_relative -- 1 1 && xdotool mousemove_relative -- -1 -1) >/dev/null 2>&1 || true
fi