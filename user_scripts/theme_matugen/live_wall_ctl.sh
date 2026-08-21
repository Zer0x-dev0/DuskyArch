#!/usr/bin/env bash
# ==============================================================================
# LIVE WALLPAPER CONTROLLER (live_wall_ctl)
# ==============================================================================
# Backend: mpvpaper (AUR) — plays video files as wallpaper via mpv/libmpv.
# Sound: muted by default (audio=no); toggle with `live_wall_ctl.sh toggle-sound`.
#
# State:
#   ~/.config/dusky/settings/dusky_theme/live_wall   — active video path (if any)
#   ~/.config/dusky/settings/dusky_theme/live_wall_poster — poster frame path
#   state.conf LIVE_WALL_SOUND                        — 0 muted / 1 sound
#   ~/.cache/dusky-live-wall/posters/                 — ffmpeg-extracted poster frames
#   $XDG_RUNTIME_DIR/dusky-live-wall/mpvpaper.sock    — mpv IPC socket
#
# Usage:
#   live_wall_ctl.sh set <video>   — start live wallpaper
#   live_wall_ctl.sh stop          — stop and clear
#   live_wall_ctl.sh pause|resume|toggle-pause
#   live_wall_ctl.sh toggle-sound
#   live_wall_ctl.sh poster <video> — print (and ensure) poster frame path
#   live_wall_ctl.sh status
# ==============================================================================

set -euo pipefail

readonly STATE_DIR="${HOME}/.config/dusky/settings/dusky_theme"
readonly STATE_FILE="${STATE_DIR}/state.conf"
readonly LIVE_MARKER="${STATE_DIR}/live_wall"
readonly LIVE_POSTER_MARKER="${STATE_DIR}/live_wall_poster"
readonly POSTER_CACHE_DIR="${HOME}/.cache/dusky-live-wall/posters"
readonly IPC_DIR="${XDG_RUNTIME_DIR:-/tmp}/dusky-live-wall"
readonly IPC_SOCK="${IPC_DIR}/mpvpaper.sock"

readonly VIDEO_EXTS_REGEX='\.(mp4|mkv|webm|mov|avi|m4v)$'
readonly LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/live_wall_ctl.lock"
readonly FLOCK_TIMEOUT=10

log()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# Serialize live wallpaper operations — prevents rapid keypresses from
# spawning N concurrent mpvpapers (the 12-instance RAM freeze bug).
# Theme_CTL already has its own flock; this is a second layer for direct
# calls (keybinds) and for concurrent theme_ctl instances that backgrounded
# their live_wall_ctl invocation.
with_live_lock() {
    local lock_fd=9
    exec {lock_fd}>>"$LOCK_FILE" 2>/dev/null || exec 9>>"$LOCK_FILE"
    flock -w "$FLOCK_TIMEOUT" 9 || die "Could not acquire live wallpaper lock (${LOCK_FILE})"
    "$@"
    local rc=$?
    exec 9>&- 2>/dev/null || true
    return $rc
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

is_video_file() {
    local f="${1,,}"
    [[ "$f" =~ $VIDEO_EXTS_REGEX ]]
}

ensure_dirs() {
    mkdir -p -- "$POSTER_CACHE_DIR" "$IPC_DIR" "$STATE_DIR"
}

poster_for_video() {
    # Print poster path for <video>; extract with ffmpeg if missing/stale.
    # OPTIMIZED: fast input-seek (-ss before -i), single thread, hwaccel try.
    local video="$1"
    [[ -f "$video" ]] || die "Video not found: $video"

    ensure_dirs

    local hash
    hash=$(printf '%s' "$video" | sha256sum | cut -d' ' -f1)
    local poster="${POSTER_CACHE_DIR}/${hash}.jpg"
    local meta="${POSTER_CACHE_DIR}/${hash}.meta"

    # Reuse if poster is newer than source video and meta matches
    if [[ -f "$poster" && -f "$meta" && "$poster" -nt "$video" ]]; then
        if [[ "$(<"$meta")" == "$video" ]]; then
            printf '%s\n' "$poster"
            return 0
        fi
    fi

    local tmp
    tmp=$(mktemp --tmpdir="${POSTER_CACHE_DIR}" poster.XXXXXX.jpg)

    # Fast path: input seek before -i + hwaccel + single thread. Scale to 512px.
    # Input-seek is O(1) vs output-seek which decodes from start.
    if ffmpeg -y -hide_banner -loglevel error -threads 1 \
        -ss 0.5 -hwaccel auto -i "$video" \
        -frames:v 1 -q:v 2 \
        -vf "scale=512:512:force_original_aspect_ratio=decrease" \
        "$tmp" 2>&1; then
        mv -f -- "$tmp" "$poster"
        printf '%s' "$video" > "$meta"
        printf '%s\n' "$poster"
        return 0
    fi
    # Fallback 1: without hwaccel (some builds/containers fail with hwaccel)
    if ffmpeg -y -hide_banner -loglevel error -threads 1 \
        -ss 0.5 -i "$video" \
        -frames:v 1 -q:v 2 \
        -vf "scale=512:512:force_original_aspect_ratio=decrease" \
        "$tmp" 2>&1; then
        mv -f -- "$tmp" "$poster"
        printf '%s' "$video" > "$meta"
        printf '%s\n' "$poster"
        return 0
    fi
    # Fallback 2: without scaling
    if ffmpeg -y -hide_banner -loglevel error -ss 0.5 -i "$video" -frames:v 1 -q:v 2 "$tmp" 2>&1; then
        mv -f -- "$tmp" "$poster"
        printf '%s' "$video" > "$meta"
        printf '%s\n' "$poster"
        return 0
    fi
    rm -f -- "$tmp"
    die "ffmpeg failed to extract poster from $video"
}

get_live_sound() {
    # 0 = muted (default), 1 = sound on
    local val="0"
    if [[ -f "$STATE_FILE" ]]; then
        val=$(grep -m1 '^LIVE_WALL_SOUND=' "$STATE_FILE" 2>/dev/null | cut -d= -f2 | tr -d '"'\' || true)
        [[ -n "$val" ]] || val="0"
    fi
    printf '%s' "$val"
}

write_live_sound() {
    local new_val="$1"  # 0 or 1
    ensure_dirs
    if [[ -f "$STATE_FILE" ]]; then
        # Atomic in-place update, preserving other keys
        local tmp
        tmp=$(mktemp "${STATE_DIR}/state.conf.tmp.XXXXXX")
        if grep -q '^LIVE_WALL_SOUND=' "$STATE_FILE"; then
            sed "s/^LIVE_WALL_SOUND=.*/LIVE_WALL_SOUND=\"${new_val}\"/" "$STATE_FILE" > "$tmp"
        else
            cat "$STATE_FILE" > "$tmp"
            printf 'LIVE_WALL_SOUND="%s"\n' "$new_val" >> "$tmp"
        fi
        mv -fT -- "$tmp" "$STATE_FILE"
    fi
}

get_outputs() {
    # Print Hyprland monitor names, one per line. Fallback to empty → mpvpaper auto-detects.
    if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null || true
    elif command -v hyprctl >/dev/null 2>&1; then
        hyprctl monitors 2>/dev/null | grep -oP 'Monitor \K[^ ]+' || true
    fi
}

detect_hwdec_opts() {
    # Return optimal hwdec string for this GPU (vaapi / auto-safe) — mirrors 415_mpv_setup.sh.
    # On 4GB ARM/low-end devices this is critical: software decode = lag + kswapd thrash.
    local render_node="" driver_name="" env_dev=""
    env_dev="${AQ_DRM_DEVICES:-}"
    env_dev="${env_dev%%:*}"
    if [[ -n "$env_dev" && -e "$env_dev" ]]; then
        if [[ -L "/sys/class/drm/$(basename "$env_dev")/device" ]]; then
            local pref_phys
            pref_phys=$(readlink -f "/sys/class/drm/$(basename "$env_dev")/device" 2>/dev/null || true)
            for dev in /dev/dri/renderD*; do
                [[ -e "$dev" ]] || continue
                if [[ "$(readlink -f "/sys/class/drm/$(basename "$dev")/device" 2>/dev/null)" == "$pref_phys" ]]; then
                    render_node="$dev"; break
                fi
            done
        fi
    fi
    if [[ -z "$render_node" ]]; then
        for dev in /dev/dri/renderD*; do
            [[ -e "$dev" ]] || continue
            local sys_path="/sys/class/drm/$(basename "$dev")/device/driver"
            if [[ -L "$sys_path" ]] && [[ "$(basename "$(readlink -f "$sys_path")")" == "vfio-pci" ]]; then continue; fi
            render_node="$dev"; break
        done
    fi
    if [[ -n "$render_node" ]]; then
        local sys_path="/sys/class/drm/$(basename "$render_node")/device/driver"
        if [[ -L "$sys_path" ]]; then driver_name=$(basename "$(readlink -f "$sys_path")" 2>/dev/null || true); fi
        case "$driver_name" in
            nvidia) printf 'hwdec=auto'; return 0 ;;
            i915|amdgpu|xe|radeon) printf 'hwdec=vaapi vaapi-device=%s' "$render_node"; return 0 ;;
        esac
    fi
    # Generic / ARM (rkmpp, v4l2m2m, drm) or unknown — let mpv pick best safe hwdec
    printf 'hwdec=auto-safe'
}

build_mpv_opts() {
    # Build performance-tuned mpv option string for wallpaper.
    # Goals: lowest CPU/RAM on 4GB ARM, smooth 30fps, no audio bloat, auto-pause savings.
    local sound="$1" # 0 or 1
    local hwdec_opts
    hwdec_opts=$(detect_hwdec_opts)

    # Base: loop + hwdec + vo + low-latency tuning.
    # Keep list lean: each option is forwarded via `mpvpaper -o "..."`
    local opts="loop ${hwdec_opts} vo=gpu gpu-context=wayland"
    # Fast profile: bilinear scales are ~3x cheaper than spline36 on iGPU.
    opts+=" profile=fast scale=bilinear cscale=bilinear dscale=bilinear correct-downscaling=no linear-downscaling=no"
    opts+=" vd-lavc-threads=0 vd-lavc-skiploopfilter=all vd-lavc-skipframe=nonref"
    # Framedrop + vsync desync: never block compositor, drop wallpaper frames before dropping UI.
    opts+=" framedrop=vo video-sync=desync interpolation=no hr-seek-framedrop=yes"
    # Cache tuned for 4GB RAM: 16M max avoids OOM + 2s readahead masks single-frame hitches.
    opts+=" cache=yes demuxer-max-bytes=16M demuxer-max-back-bytes=4M demuxer-readahead-secs=2 demuxer-lavf-o=probesize=4096"
    # Wallpaper-specific niceties.
    opts+=" panscan=1.0 video-unscaled=no keep-open=yes no-osc no-osd-bar no-input-default-bindings no-input-terminal really-quiet msg-level=ffmpeg=warn,vo=warn"
    # Audio.
    if [[ "$sound" == "1" ]]; then opts+=" audio=yes"; else opts+=" audio=no"; fi
    # IPC for pause/resume/toggle-sound.
    opts+=" input-ipc-server=${IPC_SOCK}"
    printf '%s' "$opts"
}

mpv_ipc_cmd() {
    # Send JSON IPC command to mpv via python3 (no socat dependency).
    # Usage: mpv_ipc_cmd '{"command":["set_property","pause",true]}'
    local json="$1"
    [[ -S "$IPC_SOCK" ]] || return 1
    python3 -c "
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(1.5)
try:
    s.connect('${IPC_SOCK}')
    s.sendall(('${json}\n').encode())
    try:
        s.settimeout(0.8)
        data = s.recv(4096)
        sys.stdout.write(data.decode(errors='ignore'))
    except socket.timeout:
        pass
finally:
    s.close()
" 2>/dev/null
}

is_live_running() {
    pgrep -x mpvpaper >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_poster() {
    local video="${1:-}"
    [[ -n "$video" ]] || die "poster: missing <video> argument"
    poster_for_video "$video"
}

cmd_set() {
    # Serialize entire set operation to prevent multi-instance race
    exec 9>>"$LOCK_FILE" 2>/dev/null || true
    flock -w "$FLOCK_TIMEOUT" 9 || die "Could not acquire live wallpaper lock"
    # Ensure lock is released on return
    trap 'exec 9>&- 2>/dev/null || true; trap - RETURN' RETURN

    local video="${1:-}"
    [[ -n "$video" ]] || die "set: missing <video> argument"
    [[ -f "$video" ]] || die "Video not found: $video"
    is_video_file "$video" || warn "File does not look like a video: $video (trying anyway)"

    if ! command -v mpvpaper >/dev/null 2>&1; then
        command -v notify-send >/dev/null 2>&1 && notify-send -a "Live Wallpaper" "mpvpaper not installed" "Run: ~/user_scripts/arch_setup_scripts/scripts/487_live_wallpaper_setup.sh --auto" -u critical -t 4000 2>/dev/null || true
        die "mpvpaper not installed (run: ~/user_scripts/arch_setup_scripts/scripts/487_live_wallpaper_setup.sh --auto)"
    fi
    if ! command -v ffmpeg >/dev/null 2>&1; then
        command -v notify-send >/dev/null 2>&1 && notify-send -a "Live Wallpaper" "ffmpeg not installed" -u critical -t 3000 2>/dev/null || true
        die "ffmpeg not installed"
    fi

    ensure_dirs
    local sound
    sound=$(get_live_sound)

    # Stop any existing instance first — wait loop instead of fixed sleep (faster switch, no zombie)
    if pgrep -x mpvpaper >/dev/null 2>&1; then
        pkill -x mpvpaper 2>/dev/null || true
        local -i _wait=0
        while pgrep -x mpvpaper >/dev/null 2>&1 && (( _wait < 10 )); do
            sleep 0.08
            _wait=$((_wait+1))
        done
        pkill -9 -x mpvpaper 2>/dev/null || true
    fi
    rm -f -- "$IPC_SOCK"

    # Build performance-tuned mpv options
    local mpv_opts
    mpv_opts=$(build_mpv_opts "$sound")

    # mpvpaper flags: auto-pause when wallpaper hidden (huge CPU saver — pause when fullscreen/maximized)
    # Default: -p (pause when hidden). If user sets LIVE_WALL_AUTOPAUSE=off, disable.
    # If LIVE_WALL_AUTOPAUSE_MODE is set (FULL|MAX|ACTIVE), extend via -a.
    local -a mpvpaper_flags=()
    if [[ "${LIVE_WALL_AUTOPAUSE:-on}" != "off" ]]; then
        mpvpaper_flags+=("-p")
        if [[ -n "${LIVE_WALL_AUTOPAUSE_MODE:-}" ]]; then
            mpvpaper_flags+=("-a" "${LIVE_WALL_AUTOPAUSE_MODE}")
        fi
    fi

    # Single-decoder wildcard is far cheaper than N decoders on 4GB ARM.
    # Set LIVE_WALL_PER_OUTPUT=1 to force per-monitor decoders (multi-video setups).
    local use_per_output=0
    [[ "${LIVE_WALL_PER_OUTPUT:-0}" == "1" ]] && use_per_output=1

    local -a outputs=()
    if (( use_per_output )); then
        mapfile -t outputs < <(get_outputs || true)
        if (( ${#outputs[@]} == 0 )); then outputs=("*"); fi
    else
        # Wildcard: one decoder covers all outputs (5-10x RAM/CPU saving)
        outputs=("*")
    fi

    # Quick probe: warn if video is oversized for 4GB device (4K/60fps/high bitrate)
    if command -v ffprobe >/dev/null 2>&1; then
        local _w=0 _h=0 _fps="0/1" _br=0
        _w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$video" 2>/dev/null | head -1); _w=${_w:-0}
        _h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$video" 2>/dev/null | head -1); _h=${_h:-0}
        _fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$video" 2>/dev/null | head -1); _fps=${_fps:-0/1}
        _br=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=nw=1:nk=1 "$video" 2>/dev/null | head -1); _br=${_br:-0}
        # Parse fps numerator/denom
        local _fps_v=0
        if [[ "$_fps" == *"/"* ]]; then
            local _n=${_fps%/*} _d=${_fps#*/}
            (( _d == 0 )) && _d=1
            _fps_v=$(( _n / _d ))
        else _fps_v=${_fps%.*}; fi
        if (( _w > 1920 || _h > 1080 )); then
            warn "Video is ${_w}x${_h} — downscale to 1080p for lag-free wallpaper (try: live_wall_ctl.sh optimize \"$video\")"
        fi
        if (( _fps_v > 30 )); then
            warn "Video is ${_fps_v}fps — 30fps is ideal for wallpaper (try: live_wall_ctl.sh optimize \"$video\")"
        fi
        if (( _br > 5000000 )); then
            warn "Video bitrate is high (~$((_br/1000000))Mbps) — re-encode to <3Mbps for smooth loop"
        fi
    fi

    # Resolve absolute video path
    local abs_video
    abs_video=$(realpath -s "$video" 2>/dev/null || readlink -f "$video" 2>/dev/null || printf '%s' "$video")

    log "Starting live wallpaper: ${abs_video##*/} (sound=${sound}, outputs=${outputs[*]})"

    # Resolve absolute mpvpaper binary (systemd scope may have trimmed PATH)
    local mpvpaper_bin
    mpvpaper_bin=$(command -v mpvpaper 2>/dev/null || printf 'mpvpaper')

    # Launch mpvpaper — low priority (nice) so UI never stutters.
    # Wildcard "*" uses ONE decoder for all outputs (critical on 4GB ARM).
    # Note: close lock fd 9 in child (9>&-) so mpvpaper does NOT inherit the
    # flock — otherwise the lock stays held by mpvpaper and all future
    # live_wall_ctl invocations block (the "set failed" / stale lock bug).
    local launched=0
    for out in "${outputs[@]}"; do
        # Build command array to safely handle flags with spaces/quotes.
        local -a base_cmd=()
        # Prefer dusky-run for correct Wayland env (XDG, WAYLAND_DISPLAY).
        if command -v dusky-run >/dev/null 2>&1; then
            base_cmd=(dusky-run)
        fi
        # nice+ionice: wallpaper is lowest priority — Hyprland/awww/waybar win.
        local -a launch_cmd=(nice -n 10 ionice -c 3 "${base_cmd[@]}" "$mpvpaper_bin" "${mpvpaper_flags[@]}" -o "$mpv_opts" "$out" "$abs_video")
        if "${launch_cmd[@]}" 9>&- >/dev/null 2>&1 & then
            launched=1
        else
            # Fallback without dusky-run wrapper
            if nice -n 10 ionice -c 3 "$mpvpaper_bin" "${mpvpaper_flags[@]}" -o "$mpv_opts" "$out" "$abs_video" 9>&- >/dev/null 2>&1 & then
                launched=1
            fi
        fi
        [[ "$out" == "*" ]] && break
    done

    if (( ! launched )); then
        # Fallback: bare invocation without explicit output (some builds auto-cover)
        if command -v dusky-run >/dev/null 2>&1; then
            nice -n 10 ionice -c 3 dusky-run "$mpvpaper_bin" "${mpvpaper_flags[@]}" -o "$mpv_opts" "$abs_video" 9>&- >/dev/null 2>&1 &
        else
            nice -n 10 ionice -c 3 "$mpvpaper_bin" "${mpvpaper_flags[@]}" -o "$mpv_opts" "$abs_video" 9>&- >/dev/null 2>&1 &
        fi
        disown 2>/dev/null || true
        sleep 0.35
    else
        disown 2>/dev/null || true
        sleep 0.35
    fi

    # Verify it started
    local tries=0
    while (( tries < 10 )); do
        if is_live_running; then
            break
        fi
        sleep 0.2
        tries=$((tries+1))
    done

    if ! is_live_running; then
        warn "mpvpaper did not appear to start (check logs / Wayland session)"
        # Still write marker so theme_ctl can still theme from poster
    fi

    # Persist markers atomically
    local tmp
    tmp=$(mktemp "${STATE_DIR}/live_wall.tmp.XXXXXX")
    printf '%s\n' "$abs_video" > "$tmp"
    mv -fT -- "$tmp" "$LIVE_MARKER"

    # Poster for matugen (also warms cache)
    local poster
    poster=$(poster_for_video "$abs_video")
    tmp=$(mktemp "${STATE_DIR}/live_wall_poster.tmp.XXXXXX")
    printf '%s\n' "$poster" > "$tmp"
    mv -fT -- "$tmp" "$LIVE_POSTER_MARKER"

    log "Live wallpaper active: $abs_video"
    log "Poster cached: $poster"

    # Final dedup: if rapid keypresses managed to spawn >1, kill extras
    local count
    count=$(pgrep -c -x mpvpaper 2>/dev/null || echo 0)
    # Expected 1 for wildcard, N for per-output. If wildcard and count>1, dedup.
    if [[ "${LIVE_WALL_PER_OUTPUT:-0}" != "1" ]] && (( count > 1 )); then
        warn "Dedup: found ${count} mpvpaper instances — removing duplicates"
        # Keep newest, kill older
        pgrep -x mpvpaper | head -n -1 | xargs -r kill 2>/dev/null || true
        sleep 0.2
    fi

    trap - RETURN
    exec 9>&- 2>/dev/null || true
}

cmd_stop() {
    exec 9>>"$LOCK_FILE" 2>/dev/null || true
    flock -w "$FLOCK_TIMEOUT" 9 || die "Could not acquire live wallpaper lock"
    trap 'exec 9>&- 2>/dev/null || true; trap - RETURN' RETURN
    local -i silent=0
    [[ "${1:-}" == "--silent" ]] && silent=1

    local was_running=0
    is_live_running && was_running=1

    pkill -x mpvpaper 2>/dev/null || true
    # SIGTERM fallback grace
    sleep 0.3
    pkill -9 -x mpvpaper 2>/dev/null || true
    rm -f -- "$IPC_SOCK" "$LIVE_MARKER" "$LIVE_POSTER_MARKER" 2>/dev/null || true

    if (( was_running )); then
        (( silent )) || log "Live wallpaper stopped."
    else
        # Still clear marker if stale
        (( silent )) || log "No live wallpaper was running."
    fi
    trap - RETURN
    exec 9>&- 2>/dev/null || true
}

cmd_pause()   { mpv_ipc_cmd '{"command":["set_property","pause",true]}'  >/dev/null 2>&1 || pkill -STOP -x mpvpaper 2>/dev/null || true; log "Live wallpaper paused."; }
cmd_resume()  { mpv_ipc_cmd '{"command":["set_property","pause",false]}' >/dev/null 2>&1 || pkill -CONT -x mpvpaper 2>/dev/null || true; log "Live wallpaper resumed."; }

cmd_toggle_pause() {
    # Try IPC first (accurate toggle), fall back to SIGSTOP/CONT heuristic
    local resp
    resp=$(mpv_ipc_cmd '{"command":["get_property","pause"]}' 2>/dev/null || true)
    if [[ "$resp" == *'"data":true'* || "$resp" == *'"data": true'* ]]; then
        cmd_resume
    elif [[ "$resp" == *'"data":false'* || "$resp" == *'"data": false'* ]]; then
        cmd_pause
    else
        # No IPC — toggle via process state (check if any mpv is stopped)
        local stopped
        stopped=$(ps -o stat= -C mpvpaper 2>/dev/null | grep -q 'T' && echo 1 || echo 0)
        if [[ "$stopped" == "1" ]]; then
            pkill -CONT -x mpvpaper 2>/dev/null || true
            log "Live wallpaper resumed (SIGCONT)."
        else
            pkill -STOP -x mpvpaper 2>/dev/null || true
            log "Live wallpaper paused (SIGSTOP)."
        fi
    fi
}

cmd_toggle_sound() {
    local cur nxt
    cur=$(get_live_sound)
    if [[ "$cur" == "1" ]]; then nxt="0"; else nxt="1"; fi
    write_live_sound "$nxt"

    # If a live wallpaper is active, restart it with new sound setting
    if [[ -f "$LIVE_MARKER" ]]; then
        local cur_video
        cur_video=$(<"$LIVE_MARKER")
        if [[ -f "$cur_video" ]]; then
            log "Toggling sound: ${cur} -> ${nxt} (restarting live wallpaper)"
            cmd_set "$cur_video"
            # Re-apply matugen if theme_ctl is available (poster unchanged, but hooks may need sound-aware?)
            if [[ -x "${HOME}/user_scripts/theme_matugen/theme_ctl.sh" ]]; then
                "${HOME}/user_scripts/theme_matugen/theme_ctl.sh" refresh >/dev/null 2>&1 || true
            fi
        else
            warn "Active live video missing: $cur_video (sound preference saved)"
        fi
    fi

    if [[ "$nxt" == "1" ]]; then
        log "Live wallpaper sound: ON"
        command -v notify-send >/dev/null 2>&1 && notify-send -a "Live Wallpaper" "Sound ON" -t 1500 2>/dev/null || true
    else
        log "Live wallpaper sound: OFF (muted)"
        command -v notify-send >/dev/null 2>&1 && notify-send -a "Live Wallpaper" "Sound OFF (muted)" -t 1500 2>/dev/null || true
    fi
}

cmd_optimize() {
    local src="${1:-}"
    local dst="${2:-}"
    [[ -n "$src" ]] || die "optimize: missing <video> argument (usage: live_wall_ctl.sh optimize <input> [output])"
    [[ -f "$src" ]] || die "File not found: $src"
    if [[ -z "$dst" ]]; then
        local base dir ext
        dir=$(dirname -- "$src")
        base=$(basename -- "$src")
        ext="${base##*.}"
        base="${base%.*}"
        dst="${dir}/${base}.optimized.mp4"
        # Avoid overwrite of source if already mp4
        if [[ "$src" == "$dst" ]]; then dst="${dir}/${base}_optimized.mp4"; fi
    fi
    if ! command -v ffmpeg >/dev/null 2>&1; then die "ffmpeg not installed"; fi
    log "Optimizing: $src -> $dst"
    log "Target: 1920x1080 max, 30fps max, H264 CRF23 fastdecode, ~2-3Mbps"
    # -vf scale + fps: ensures wallpaper-friendly size. -an by default keeps audio? We strip audio for wallpaper (save RAM/CPU)
    # Use -c:v libx264 -profile high -preset fast -crf 23 -movflags +faststart -pix_fmt yuv420p -tune fastdecode
    # Keep aspect, never upscale.
    local -a vf_parts=()
    vf_parts+=("scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease:eval=frame")
    vf_parts+=("scale=trunc(iw/2)*2:trunc(ih/2)*2") # ensure even dims for yuv420p
    local vf
    vf=$(IFS=,; printf '%s' "${vf_parts[*]}")
    # Probe fps first: only apply fps filter if source >30
    local src_fps="0/1"
    src_fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$src" 2>/dev/null | head -1); src_fps=${src_fps:-0/1}
    local fps_v=0
    if [[ "$src_fps" == *"/"* ]]; then local n=${src_fps%/*} d=${src_fps#*/}; (( d==0 )) && d=1; fps_v=$(( n / d )); else fps_v=${src_fps%.*}; fi
    local fps_filter="" out_fps_args=()
    if (( fps_v > 30 )); then fps_filter=",fps=30"; out_fps_args=(-r 30); fi
    # If source is GIF with no reliable fps (0), default to 15fps wallpaper-friendly
    if (( fps_v == 0 )); then fps_filter=",fps=15"; out_fps_args=(-r 15); fps_v=15; fi
    vf="${vf}${fps_filter}"
    # GOP = fps * 2 (2 sec keyframe interval)
    local gop=$(( fps_v * 2 )); (( gop < 12 )) && gop=12; (( gop > 60 )) && gop=60
    if ffmpeg -y -hide_banner -loglevel error -threads 0 -i "$src" \
        -vf "$vf" -c:v libx264 -profile:v high -preset fast -crf 23 -pix_fmt yuv420p -movflags +faststart -tune fastdecode \
        -an "${out_fps_args[@]}" -g "$gop" -bf 2 \
        "$dst" 2>&1; then
        local out_w out_h out_br
        out_w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$dst" 2>/dev/null | head -1)
        out_h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$dst" 2>/dev/null | head -1)
        out_br=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=nw=1:nk=1 "$dst" 2>/dev/null | head -1)
        local sz
        sz=$(du -h "$dst" 2>/dev/null | cut -f1)
        log "Done: ${out_w}x${out_h} @${fps_v}fps ~$((out_br/1000))kbps ($sz) -> $dst"
        command -v notify-send >/dev/null 2>&1 && notify-send -a "Live Wallpaper" "Optimized: $(basename "$dst") (${sz})" -t 2500 2>/dev/null || true
        # Offer to set as wallpaper
        if [[ -f "$dst" ]]; then
            printf '%s\n' "$dst"
        fi
    else
        rm -f -- "$dst" 2>/dev/null || true
        die "ffmpeg optimize failed for $src"
    fi
}

cmd_optimize_all() {
    local wall_dir="${1:-$HOME/Pictures/wallpapers}"
    [[ -d "$wall_dir" ]] || die "Wallpaper dir not found: $wall_dir"
    log "Scanning $wall_dir for heavy GIFs/videos to optimize (GIF >5MB or video >1080p/>30fps/>5Mbps)"
    local -a heavy=()
    local f
    # Find GIFs >5MB (major lag source — awww decodes all frames in RAM)
    while IFS= read -r -d '' f; do heavy+=("$f"); done < <(find "$wall_dir" -type f -iname '*.gif' -size +5M -print0 2>/dev/null)
    # Also find MP4s that probe as >1080p or >30fps
    while IFS= read -r -d '' f; do
        local _w _h _fps
        _w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$f" 2>/dev/null | head -1); _w=${_w:-0}
        _h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$f" 2>/dev/null | head -1); _h=${_h:-0}
        _fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of default=nw=1:nk=1 "$f" 2>/dev/null | head -1); _fps=${_fps:-0/1}
        local fps_v=0
        if [[ "$_fps" == *"/"* ]]; then local n=${_fps%/*} d=${_fps#*/}; (( d==0 )) && d=1; fps_v=$(( n / d )); else fps_v=${_fps%.*}; fi
        if (( _w > 1920 || _h > 1080 || fps_v > 30 )); then heavy+=("$f"); fi
    done < <(find "$wall_dir" -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' \) -print0 2>/dev/null)
    if (( ${#heavy[@]} == 0 )); then
        log "No heavy files found — all wallpapers already optimal."
        return 0
    fi
    log "Found ${#heavy[@]} heavy file(s):"
    for f in "${heavy[@]}"; do
        local sz
        sz=$(du -h "$f" 2>/dev/null | cut -f1)
        printf '  %s (%s)\n' "$f" "$sz"
    done
    local ok=0 fail=0
    for f in "${heavy[@]}"; do
        if cmd_optimize "$f" 2>&1; then ok=$((ok+1)); else fail=$((fail+1)); fi
        echo
    done
    log "Done: $ok optimized, $fail failed. Delete original GIFs if mp4 looks good: rm ~/Pictures/wallpapers/*.gif"
}

cmd_status() {
    if is_live_running && [[ -f "$LIVE_MARKER" ]]; then
        local vid poster sound
        vid=$(<"$LIVE_MARKER")
        poster=""
        [[ -f "$LIVE_POSTER_MARKER" ]] && poster=$(<"$LIVE_POSTER_MARKER")
        sound=$(get_live_sound)
        printf 'running=true\nvideo=%s\nposter=%s\nsound=%s\nipc=%s\n' "$vid" "$poster" "$sound" "$IPC_SOCK"
        if [[ -S "$IPC_SOCK" ]]; then
            local pa
            pa=$(mpv_ipc_cmd '{"command":["get_property","pause"]}' 2>/dev/null || echo "")
            if [[ -n "$pa" ]]; then
                printf 'mpv_paused=%s\n' "$pa"
            fi
        fi
    elif is_live_running; then
        printf 'running=true\nvideo=unknown (no marker)\n'
    else
        printf 'running=false\n'
        if [[ -f "$LIVE_MARKER" ]]; then
            printf 'stale_marker=%s\n' "$(<"$LIVE_MARKER")"
        fi
    fi
}

usage() {
    cat <<'EOF'
Usage: live_wall_ctl.sh <command> [args]

Commands:
  set <video>     Start live wallpaper on all monitors (muted by default)
  stop            Stop live wallpaper and clear state
  poster <video>  Print (and ensure) cached poster frame for <video>
  pause           Pause playback
  resume          Resume playback
  toggle-pause    Toggle pause/resume
  toggle-sound    Toggle sound on/off (persists in state.conf, restarts wallpaper)
  mute            Alias for ensuring muted (LIVE_WALL_SOUND=0)
  unmute          Alias for ensuring sound on (LIVE_WALL_SOUND=1)
  optimize <in> [out]  Re-encode video to wallpaper-optimal 1080p/30fps H264 (~2-3Mbps)
                       Strips audio, uses fastdecode tune. Auto-names <in>.optimized.mp4
  optimize-all [dir]   Bulk-convert heavy GIFs (>5MB) + oversized videos in dir to optimized mp4
  status          Show current live wallpaper status
  help            Show this help

Poster frames are JPEGs in ~/.cache/dusky-live-wall/posters/<hash>.jpg
IPC socket: $XDG_RUNTIME_DIR/dusky-live-wall/mpvpaper.sock

Performance tips for 4GB ARM:
  - Keep wallpapers <=1080p, <=30fps, H264 (not GIF — convert GIF->mp4 via optimize)
  - Single decoder covers all monitors by default (LIVE_WALL_PER_OUTPUT=1 for per-monitor)
  - Auto-pause (-p) pauses wallpaper when hidden/fullscreen (saves 30-60% CPU)
  - Set LIVE_WALL_AUTOPAUSE=off to disable, LIVE_WALL_AUTOPAUSE_MODE=FULL|MAX|ACTIVE to tune
  - Large GIFs (16-26MB) are the #1 lag source — run optimize on them

Examples:
  live_wall_ctl.sh set ~/Pictures/wallpapers/video.mp4
  live_wall_ctl.sh optimize ~/Pictures/wallpapers/Car_-_Imgur.gif
  LIVE_WALL_AUTOPAUSE_MODE=MAX live_wall_ctl.sh set video.mp4
EOF
}

case "${1:-}" in
    set)           shift; cmd_set "$@" ;;
    stop)          shift; cmd_stop "$@" ;;
    poster)        shift; cmd_poster "$@" ;;
    optimize)      shift; cmd_optimize "$@" ;;
    optimize-all|optimize_all) shift; cmd_optimize_all "$@" ;;
    pause)         cmd_pause ;;
    resume)        cmd_resume ;;
    toggle-pause|toggle_pause|toggle) cmd_toggle_pause ;;
    toggle-sound|toggle_sound|toggle-mute|sound) cmd_toggle_sound ;;
    mute)          write_live_sound "0"; [[ -f "$LIVE_MARKER" ]] && cmd_set "$(<"$LIVE_MARKER")" || log "Sound set to muted (no active live wallpaper)." ;;
    unmute)        write_live_sound "1"; [[ -f "$LIVE_MARKER" ]] && cmd_set "$(<"$LIVE_MARKER")" || log "Sound set to on (no active live wallpaper)." ;;
    status)        cmd_status ;;
    -h|--help|help) usage ;;
    "")            usage; exit 1 ;;
    *)             die "Unknown command: $1 (try: live_wall_ctl.sh help)" ;;
esac
