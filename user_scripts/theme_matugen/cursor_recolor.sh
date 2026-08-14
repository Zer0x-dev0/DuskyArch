#!/usr/bin/env bash
# Matugen cursor recolor: tint Bibata-based cursor template SVGs with current
# theme colors, compile to hyprcursor .hlc zips, install, and apply instantly.
#
# Colors passed via CURSOR_* env vars by matugen post_hook
# ([templates.hyprcursor] in ~/.config/matugen/config.toml).
# Fallback: matugen-generated colors.css.
#
# Performance:
# - Stamp cache keyed on (colors, template mtimes): re-runs with unchanged
#   colors skip the compile phases entirely (instant refresh / login restore).
# - Xcursor PNG render + xcursorgen runs across parallel workers instead of
#   serializing ~56 shapes x 5 sizes.
# - flock: backgrounded runs from rapid theme changes never collide on the
#   shared work dir; the newest run wins, an older queued run exits.
set -euo pipefail

TEMPLATE_DIR="${HOME}/.config/matugen/templates/cursor"
WORK_DIR="${HOME}/.cache/dusky/matugen_cursor/working"
THEME_NAME="Matugen-Cursor"
ICONS_DIR="${HOME}/.local/share/icons"
CURSOR_SIZE="${HYPRCURSOR_SIZE:-18}"
STAMP_FILE="${ICONS_DIR}/.matugen-cursor.stamp"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/matugen-cursor.lock"
readonly X11_JOBS="${CURSOR_RECOLOR_JOBS:-4}"

[[ -d "$TEMPLATE_DIR" ]] || { echo "cursor templates missing: $TEMPLATE_DIR" >&2; exit 1; }

exec 9>"$LOCK_FILE"
flock -n 9 || { echo "cursor recolor already running; skipping" >&2; exit 0; }

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

# --- Stamp cache: skip every compile phase when colors+templates unchanged ---
needs_compile=1
CURSOR_HASH="$( { printf '%s\n' "${HEX[@]}" | sort; find "$TEMPLATE_DIR" -type f -printf '%T@ %p\n' | sort; } | sha256sum | cut -d' ' -f1)"
if [[ -f "$STAMP_FILE" ]] && [[ "$(<"$STAMP_FILE")" == "$CURSOR_HASH" ]] && [[ -d "$ICONS_DIR/$THEME_NAME" ]]; then
    needs_compile=0
fi

if (( needs_compile )); then
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

    # ---------------------------------------------------------------------------
    # Xcursor (GTK/X11 apps) theme: GTK apps (file managers, etc.) cannot read
    # hyprcursor .hlc zips. Render the recolored SVGs to PNG and compile them
    # with xcursorgen so the entire desktop uses the recolored cursor, not just
    # Hyprland. Then wire GTK settings + gsettings to point at this theme.
    # Parallelized: ~56 shapes x 5 sizes run across X11_JOBS workers.
    # ---------------------------------------------------------------------------
    XCURSOR_DIR="$ICONS_DIR/$THEME_NAME/cursors"
    X11_WORK="${WORK_DIR}.x11"
    rm -rf "$XCURSOR_DIR" "$X11_WORK"
    mkdir -p "$XCURSOR_DIR" "$X11_WORK"

    if command -v rsvg-convert >/dev/null 2>&1 && command -v xcursorgen >/dev/null 2>&1; then
        render_cursor_shape() {
            local meta="$1" dir name img hx hy conf sz png xhot yhot
            dir="$(dirname "$meta")"
            name="$(basename "$dir")"
            img="$dir/image.svg"
            [[ -f "$img" ]] || img="$dir/image-01.svg"
            [[ -f "$img" ]] || return 0

            hx="$(sed -n 's/^hotspot_x = //p' "$meta" | head -1)"
            hy="$(sed -n 's/^hotspot_y = //p' "$meta" | head -1)"
            hx="${hx:-0.5}"; hy="${hy:-0.5}"

            conf="$X11_WORK/$name.conf"
            : > "$conf"
            for sz in 18 24 32 48 64; do
                png="$X11_WORK/$name-$sz.png"
                rsvg-convert -w "$sz" -h "$sz" "$img" -o "$png" 2>/dev/null || continue
                xhot="$(awk -v h="$hx" -v s="$sz" 'BEGIN{printf "%d", h*s+0.5}')"
                yhot="$(awk -v h="$hy" -v s="$sz" 'BEGIN{printf "%d", h*s+0.5}')"
                printf '%s %s %s %s\n' "$sz" "$xhot" "$yhot" "$png" >> "$conf"
            done
            [[ -s "$conf" ]] || return 0
            xcursorgen "$conf" "$XCURSOR_DIR/$name" 2>/dev/null || true
        }
        export -f render_cursor_shape
        export X11_WORK XCURSOR_DIR

        find "$WORK_DIR/hyprcursors" -name meta.hl -print0 \
            | xargs -0 -n 1 -P "$X11_JOBS" bash -c 'render_cursor_shape "$@"' _

        ALIASES=()
        while IFS= read -r -d '' meta; do
            name="$(basename "$(dirname "$meta")")"
            while IFS= read -r alias; do
                ALIASES+=("$name $alias")
            done < <(sed -n 's/^define_override = //p' "$meta")
        done < <(find "$WORK_DIR/hyprcursors" -name meta.hl -print0)

        for pair in "${ALIASES[@]}"; do
            src="${pair%% *}"; dst="${pair##* }"
            [[ "$src" == "$dst" ]] && continue
            [[ -f "$XCURSOR_DIR/$src" ]] && ln -sf "$src" "$XCURSOR_DIR/$dst" 2>/dev/null || true
        done

        cat > "$ICONS_DIR/$THEME_NAME/index.theme" <<'EOF'
[Icon Theme]
Name=Matugen-Cursor
Comment=Recolored from the wallpaper by matugen
Inherits=Adwaita
EOF
    fi

    mkdir -p "$ICONS_DIR"
    printf '%s' "$CURSOR_HASH" > "$STAMP_FILE"
fi

# Point GTK apps (file managers, etc.) at the recolored theme.
for ini in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
    [[ -f "$ini" ]] || continue
    sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=Matugen-Cursor/" "$ini"
    sed -i "s/^gtk-cursor-theme-size=.*/gtk-cursor-theme-size=$CURSOR_SIZE/" "$ini"
done
XS="$HOME/.config/xsettingsd/xsettingsd.conf"
if [[ -f "$XS" ]]; then
    sed -i "s@^Gtk/CursorThemeName .*@Gtk/CursorThemeName \"Matugen-Cursor\"@" "$XS"
    sed -i "s@^Gtk/CursorThemeSize .*@Gtk/CursorThemeSize $CURSOR_SIZE@" "$XS"
fi
gsettings set org.gnome.desktop.interface cursor-theme "Matugen-Cursor" 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE" 2>/dev/null || true
if pgrep -x xsettingsd >/dev/null 2>&1; then
    # Async restart: the daemon must re-read the conf, but nothing may wait on it.
    ( pkill -x xsettingsd >/dev/null 2>&1 || true
      sleep 0.2
      xsettingsd >/dev/null 2>&1 & ) &
fi

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