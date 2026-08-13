#!/usr/bin/env python3
"""
===============================================================================
DUSKY TUI: HYBRID AUTOSTART ENGINE
===============================================================================
Bridges standard Hyprland Lua AST parsing for `hl.config({ ... })` tables,
while handling `hl.exec_cmd(...)` autostart directives inside `hl.on("hyprland.start", ...)`.
===============================================================================
"""

import os
import re
import shutil
import stat
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

from python.engines.lua import HyprlandLuaEngine

# =============================================================================
# RUNTIME ACTIONS: live start/stop for "apply now" without relogin.
#   start / stop  -> shell commands executed via the user's shell
#   pcheck        -> pgrep pattern used to report whether the service is running
# Entries without a runtime definition (one-shot, transient, or toggle-only
# scripts) are intentionally omitted.
# =============================================================================
AUTOSTART_RUNTIME: dict[str, dict[str, str]] = {
    "awww_daemon": {
        "pcheck": "awww-daemon",
        "exact": True,
        "start": "awww-daemon",
        "stop": "pkill -x awww-daemon",
    },
    "waybar": {
        "pcheck": "waybar",
        "exact": True,
        "start": "$HOME/user_scripts/waybar/waybar_toggle.sh --on",
        "stop": "$HOME/user_scripts/waybar/waybar_toggle.sh --off",
    },
    "nm_applet": {
        "pcheck": "nm-applet",
        "exact": True,
        "start": "nm-applet",
        "stop": "pkill -x nm-applet",
    },
    "gnome_keyring": {
        "pcheck": "gnome-keyring",
        "start": "/usr/bin/gnome-keyring-daemon --start --components=secrets",
        "stop": "pkill -f gnome-keyring-daemon",
    },
    "hypridle": {
        "pcheck": "hypridle",
        "exact": True,
        "start": "systemctl --user start hypridle.service",
        "stop": "systemctl --user stop hypridle.service",
    },
    "clip_persist": {
        "pcheck": "wl-clip-persist",
        "exact": True,
        "start": "wl-clip-persist --clipboard regular",
        "stop": "pkill -x wl-clip-persist",
    },
    "wayclick": {
        "pcheck": "dusky_wayclick",
        "start": "$HOME/user_scripts/wayclick/dusky_wayclick.sh",
        "stop": "pkill -TERM -u $USER -f dusky_wayclick.sh",
    },
    "xhost_root": {
        "pcheck": "xhost",
        "exact": True,
        "start": "xhost +si:localuser:root",
        "stop": "",
    },
    "hyprpm_reload": {
        "pcheck": "hyprpm",
        "exact": True,
        "start": "hyprpm reload",
        "stop": "",
    },
}

# Backup retention: keep the N most recent snapshots per config file.
BACKUP_KEEP = 15

AUTOSTART_DEFAULTS: dict[str, dict[str, Any]] = {
    # --- Interface & Background Services ---
    "autostart/awww_daemon": {
        "pattern": r'awww-daemon',
        "canonical": 'hl.exec_cmd("awww-daemon")',
        "default": True
    },
    "autostart/waybar": {
        "pattern": r'(?:waybar_toggle\.sh|exec_cmd\("waybar"\))',
        "canonical": 'hl.exec_cmd("$HOME/user_scripts/waybar/waybar_toggle.sh --on")',
        "default": True
    },
    "autostart/waybar_timer": {
        "pattern": r'toggle_timer_waybar\.sh',
        "canonical": 'hl.exec_cmd("$HOME/user_scripts/waybar/toggle_timer_waybar.sh")',
        "default": False
    },
    "autostart/nm_applet": {
        "pattern": r'nm-applet',
        "canonical": 'hl.exec_cmd("nm-applet")',
        "default": False
    },
    "autostart/gnome_keyring": {
        "pattern": r'gnome-keyring-daemon',
        "canonical": 'hl.exec_cmd("/usr/bin/gnome-keyring-daemon --start --components=secrets")',
        "default": False
    },
    "autostart/xhost_root": {
        "pattern": r'xhost\s+\+si:localuser:root',
        "canonical": 'hl.exec_cmd("xhost +si:localuser:root")',
        "default": False
    },
    "autostart/hypridle": {
        "pattern": r'hypridle',
        "canonical": 'hl.exec_cmd("hypridle")',
        "default": False
    },
    "autostart/layout_notify": {
        "pattern": r'layout_notify\.sh',
        "canonical": 'hl.exec_cmd("$HOME/user_scripts/hypr/layout_notify.sh")',
        "default": False
    },
    "autostart/audio_visualizer": {
        "pattern": r'visualizer_toggle\.sh',
        "canonical": 'hl.exec_cmd("$HOME/user_scripts/way_layers/visualizer/visualizer_toggle.sh")',
        "default": False
    },
    "autostart/wayclick": {
        "pattern": r'dusky_wayclick\.sh',
        "canonical": 'hl.exec_cmd("$HOME/user_scripts/wayclick/dusky_wayclick.sh")',
        "default": False
    },
    "autostart/hyprpm_reload": {
        "pattern": r'hyprpm\s+reload',
        "canonical": 'hl.exec_cmd("hyprpm reload")',
        "default": False
    },

    # --- Clipboard Services ---
    "autostart/cliphist_text": {
        "pattern": r'wl-paste\s+--type\s+text\s+--watch\s+cliphist\s+store',
        "canonical": 'hl.exec_cmd("wl-paste --type text --watch cliphist store")',
        "default": False
    },
    "autostart/cliphist_image": {
        "pattern": r'wl-paste\s+--type\s+image\s+--watch\s+cliphist\s+store',
        "canonical": 'hl.exec_cmd("wl-paste --type image --watch cliphist store")',
        "default": False
    },
    "autostart/cliphist_db_text": {
        "pattern": r'cliphist_db_env.*text',
        "canonical": 'hl.exec_cmd("sh -c \'. $HOME/.config/dusky/settings/cliphist_db_env && exec wl-paste --type text --watch cliphist store\'")',
        "default": False
    },
    "autostart/cliphist_db_image": {
        "pattern": r'cliphist_db_env.*image',
        "canonical": 'hl.exec_cmd("sh -c \'. $HOME/.config/dusky/settings/cliphist_db_env && exec wl-paste --type image --watch cliphist store\'")',
        "default": False
    },
    "autostart/clip_persist": {
        "pattern": r'wl-clip-persist',
        "canonical": 'hl.exec_cmd("wl-clip-persist --clipboard regular")',
        "default": False
    },

    # --- Environment Integration ---
    "autostart/systemd_env": {
        "pattern": r'systemctl\s+--user\s+import-environment',
        "canonical": 'hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP CLIPHIST_DB_PATH")',
        "default": True
    },
    "autostart/dbus_env": {
        "pattern": r'dbus-update-activation-environment',
        "canonical": 'hl.exec_cmd("dbus-update-activation-environment --systemd --all")',
        "default": True
    },
    "autostart/session_target": {
        "pattern": r'systemctl\s+--user\s+start\s+hyprland-session\.target',
        "canonical": 'hl.exec_cmd("systemctl --user start hyprland-session.target")',
        "default": True
    },
    "autostart/shutdown_target": {
        "pattern": r'systemctl\s+--user\s+stop\s+hyprland-session\.target',
        "canonical": 'hl.exec_cmd("systemctl --user stop hyprland-session.target")',
        "default": True
    },
    "autostart/choom_oom": {
        "pattern": r'choom\s+-n\s+-250',
        "canonical": 'hl.exec_cmd("sudo choom -n -250 -p $(pgrep -x Hyprland)")',
        "default": True
    },

    # --- Dusky Glance Dashboards Autostart ---
    "autostart/glance_cpu": {
        "pattern": r'dusky_glance\.sh\s+--cpu(?:["\'\s]|$)',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --cpu")',
        "default": False
    },
    "autostart/glance_cpu_power": {
        "pattern": r'dusky_glance\.sh\s+--cpu-power',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --cpu-power")',
        "default": False
    },
    "autostart/glance_ram": {
        "pattern": r'dusky_glance\.sh\s+--ram(?:["\'\s]|$)',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --ram")',
        "default": False
    },
    "autostart/glance_ram_temp": {
        "pattern": r'dusky_glance\.sh\s+--ram-temp',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --ram-temp")',
        "default": False
    },
    "autostart/glance_zram": {
        "pattern": r'dusky_glance\.sh\s+--zram',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --zram")',
        "default": False
    },
    "autostart/glance_temp": {
        "pattern": r'dusky_glance\.sh\s+--temp(?:["\'\s]|$)',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --temp")',
        "default": False
    },
    "autostart/glance_battery": {
        "pattern": r'dusky_glance\.sh\s+--battery(?:["\'\s]|$)',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --battery")',
        "default": False
    },
    "autostart/glance_battery_percent": {
        "pattern": r'dusky_glance\.sh\s+--battery-percent',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --battery-percent")',
        "default": False
    },
    "autostart/glance_battery_watts": {
        "pattern": r'dusky_glance\.sh\s+--battery-watts',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --battery-watts")',
        "default": False
    },
    "autostart/glance_battery_time": {
        "pattern": r'dusky_glance\.sh\s+--battery-time',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --battery-time")',
        "default": False
    },
    "autostart/glance_gpu_power": {
        "pattern": r'dusky_glance\.sh\s+--gpu-power',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --gpu-power card1 Intel")',
        "default": False
    },
    "autostart/glance_gpu_usage": {
        "pattern": r'dusky_glance\.sh\s+--gpu-usage',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --gpu-usage card1 Intel")',
        "default": False
    },
    "autostart/glance_gpu_mem": {
        "pattern": r'dusky_glance\.sh\s+--gpu-mem',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --gpu-mem card1 Intel")',
        "default": False
    },
    "autostart/glance_network": {
        "pattern": r'dusky_glance\.sh\s+--network',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --network")',
        "default": False
    },
    "autostart/glance_uptime": {
        "pattern": r'dusky_glance\.sh\s+--uptime',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --uptime")',
        "default": False
    },
    "autostart/glance_workspace": {
        "pattern": r'dusky_glance\.sh\s+--workspace',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --workspace")',
        "default": False
    },
    "autostart/glance_clock": {
        "pattern": r'dusky_glance\.sh\s+--clock(?:["\'\s]|$)',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --clock")',
        "default": False
    },
    "autostart/glance_clock_short": {
        "pattern": r'dusky_glance\.sh\s+--clock-short',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --clock-short")',
        "default": False
    },
    "autostart/glance_disk": {
        "pattern": r'dusky_glance\.sh\s+--disk(?:["\'\s]|$)',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --disk")',
        "default": False
    },
    "autostart/glance_disk_read": {
        "pattern": r'dusky_glance\.sh\s+--disk-read',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --disk-read nvme0n1")',
        "default": False
    },
    "autostart/glance_disk_write": {
        "pattern": r'dusky_glance\.sh\s+--disk-write',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --disk-write nvme0n1")',
        "default": False
    },
    "autostart/glance_disk_temp": {
        "pattern": r'dusky_glance\.sh\s+--disk-temp',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --disk-temp nvme0n1")',
        "default": False
    },
    "autostart/glance_stopwatch": {
        "pattern": r'dusky_glance\.sh\s+--stopwatch',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --stopwatch")',
        "default": False
    },
    "autostart/glance_timer": {
        "pattern": r'dusky_glance\.sh\s+--timer',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --timer 15m")',
        "default": False
    },
    "autostart/glance_hud": {
        "pattern": r'dusky_glance\.sh\s+--hud',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --hud card1 Intel")',
        "default": False
    },
    "autostart/glance_world_ny": {
        "pattern": r'dusky_glance\.sh\s+--world-clock\s+America/New_York',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --world-clock America/New_York NY")',
        "default": False
    },
    "autostart/glance_world_tokyo": {
        "pattern": r'dusky_glance\.sh\s+--world-clock\s+Asia/Tokyo',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --world-clock Asia/Tokyo Japan")',
        "default": False
    },
    "autostart/glance_world_london": {
        "pattern": r'dusky_glance\.sh\s+--world-clock\s+Europe/London',
        "canonical": 'hl.exec_cmd("~/user_scripts/rofi/dusky_glance.sh --world-clock Europe/London London")',
        "default": False
    },
}

def _is_header_comment(lines: list[str], idx: int) -> bool:
    """Returns True if the line index is inside top-level doc/syntax header comments."""
    if idx < 15:
        for i in range(min(idx + 1, 15)):
            if "Syntax:" in lines[i] or "USER CONFIGURATION" in lines[i]:
                return True
    return False

class AutostartLuaEngine(HyprlandLuaEngine):
    def load_state(self) -> dict[str, Any]:
        state = super().load_state()

        if not self.config_path.exists():
            for full_key, meta in AUTOSTART_DEFAULTS.items():
                state[full_key] = meta["default"]
            return state

        try:
            content = self.config_path.read_text(encoding="utf-8")
        except OSError:
            for full_key, meta in AUTOSTART_DEFAULTS.items():
                state[full_key] = meta["default"]
            return state

        lines = content.splitlines()

        for full_key, meta in AUTOSTART_DEFAULTS.items():
            pattern = meta["pattern"]
            is_active = False
            found_commented = False

            for idx, line in enumerate(lines):
                if _is_header_comment(lines, idx):
                    continue

                stripped = line.strip()
                if re.search(pattern, stripped):
                    if stripped.startswith("--"):
                        found_commented = True
                    else:
                        is_active = True
                        break

            if is_active:
                state[full_key] = True
            elif found_commented:
                state[full_key] = False
            else:
                state[full_key] = meta["default"]

        return state

    # =========================================================================
    # SAFETY NET: timestamped backups + Lua syntax validation
    # =========================================================================
    def create_backup(self) -> Path | None:
        """Snapshot the current config before mutation. Mirrors the main.py backup
        convention (timestamped .bak + .latest.bak symlink) under ~/Documents/dusky_backups/autostart/."""
        if not self.config_path.exists():
            return None

        backup_dir = Path("~/Documents/dusky_backups/autostart/").expanduser()
        try:
            backup_dir.mkdir(parents=True, exist_ok=True)
            backup_dir.chmod(0o700)
        except OSError:
            return None

        stem = re.sub(r"[^\w.-]+", "_", self.config_path.stem)[:64]
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S%f")
        backup_path = backup_dir / f"{stem}.{timestamp}.bak"
        latest_link = backup_dir / f"{stem}.latest.bak"

        try:
            orig_mode = stat.S_IMODE(self.config_path.stat().st_mode)
            tmp_fd, tmp_name = tempfile.mkstemp(dir=str(backup_dir), prefix=f".{stem}.", suffix=".tmp")
            tmp_path = Path(tmp_name)
            with os.fdopen(tmp_fd, "wb") as out_f, self.config_path.open("rb") as in_f:
                shutil.copyfileobj(in_f, out_f, length=1024 * 1024)
                out_f.flush()
                os.fsync(out_f.fileno())
            tmp_path.chmod(orig_mode)
            os.replace(tmp_path, backup_path)

            tmp_link = backup_dir / f".{stem}.latest.bak.tmp-{os.getpid()}"
            if tmp_link.exists() or tmp_link.is_symlink():
                tmp_link.unlink()
            tmp_link.symlink_to(backup_path.resolve())
            os.replace(tmp_link, latest_link)

            self._prune_backups(backup_dir, stem)
            return backup_path
        except OSError:
            return None

    def _prune_backups(self, backup_dir: Path, stem: str) -> None:
        try:
            candidates = sorted(
                (p for p in backup_dir.glob(f"{stem}.*.bak") if p.is_file()),
                key=lambda p: p.stat().st_mtime,
                reverse=True,
            )
            for stale in candidates[BACKUP_KEEP:]:
                stale.unlink(missing_ok=True)
        except OSError:
            pass

    def restore_backup(self) -> bool:
        """Restore the config from the latest snapshot. Returns False if none exists."""
        backup_dir = Path("~/Documents/dusky_backups/autostart/").expanduser()
        stem = re.sub(r"[^\w.-]+", "_", self.config_path.stem)[:64]
        latest_link = backup_dir / f"{stem}.latest.bak"
        if not latest_link.exists():
            return False
        try:
            actual = latest_link.resolve(strict=True)
            self.config_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(actual, self.config_path)
            try:
                self.config_path.chmod(stat.S_IMODE(actual.stat().st_mode))
            except OSError:
                pass
            return True
        except OSError:
            return False

    def _validate_lua(self, file_path: Path) -> tuple[bool, str]:
        """Syntax-only validation via the system Lua interpreter (loadfile never executes)."""
        try:
            res = subprocess.run(
                [self.lua_bin, "-e", f"assert(loadfile({__import__('json').dumps(str(file_path))}))"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=5.0,
            )
            if res.returncode == 0:
                return True, ""
            return False, (res.stderr or res.stdout or "unknown Lua error").strip()
        except (OSError, subprocess.SubprocessError, RuntimeError):
            return False, "Lua interpreter unavailable."

    # =========================================================================
    # RUNTIME CONTROL: apply config changes live without relogin
    # =========================================================================
    def runtime_status(self, key: str) -> str:
        """Return 'running', 'stopped' or 'unknown' for a service key."""
        rt = AUTOSTART_RUNTIME.get(key)
        if not rt or not rt["pcheck"]:
            return "unknown"
        try:
            pgrep_args = ["pgrep", "-x" if rt.get("exact") else "-f", rt["pcheck"]]
            res = subprocess.run(
                pgrep_args,
                capture_output=True,
                text=True,
                timeout=3.0,
            )
            if res.returncode != 0 or not res.stdout.strip():
                return "stopped"
            # Exclude our own process and the TUI host: pgrep -f can match
            # the caller's own command line (e.g. tests embedding the name).
            excluded = {str(os.getpid()), str(os.getppid())}
            pids = [p for p in res.stdout.split() if p not in excluded]
            return "running" if pids else "stopped"
        except (OSError, subprocess.SubprocessError):
            return "unknown"

    def apply_runtime(self, key: str, enabled: bool) -> tuple[bool, str]:
        """Start or stop a service immediately, matching the toggled config state."""
        rt = AUTOSTART_RUNTIME.get(key)
        if not rt:
            return False, f"No live runtime action defined for '{key}'."

        command = rt["start"] if enabled else rt["stop"]
        if not command:
            return False, (
                f"'{key}' has no {'start' if enabled else 'stop'} action (one-shot command)."
            )

        if enabled and self.runtime_status(key) == "running":
            return True, f"'{key}' is already running."

        if enabled:
            # Daemons never exit: launch detached and only treat a fast,
            # non-zero exit as a failure.
            try:
                proc = subprocess.Popen(
                    ["/bin/sh", "-c", command],
                    start_new_session=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except (OSError, subprocess.SubprocessError) as e:
                return False, f"Failed to start '{key}': {e}"
            try:
                rc = proc.wait(timeout=1.5)
            except subprocess.TimeoutExpired:
                rc = None
            if rc is not None and rc != 0:
                return False, f"Failed to start '{key}' (exit code {rc})."
        else:
            # Already stopped -> nothing to do (pkill exits 1 on no match,
            # systemctl would also report a spurious failure).
            if self.runtime_status(key) == "stopped":
                return True, f"'{key}' is already stopped."
            try:
                subprocess.run(
                    ["/bin/sh", "-c", command],
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=15.0,
                )
            except subprocess.CalledProcessError as e:
                # The process may have vanished between the status check and
                # the stop command (pkill no-match, systemd already-inactive).
                if self.runtime_status(key) == "stopped":
                    return True, f"'{key}' is already stopped."
                detail = (e.stderr or e.stdout or "").strip()
                return False, f"Failed to stop '{key}': {detail}"
            except (OSError, subprocess.SubprocessError) as e:
                return False, f"Failed to stop '{key}': {e}"

        status = self.runtime_status(key)
        if enabled and not rt["stop"]:
            return True, f"'{key}' executed (one-shot command)."
        return True, f"'{key}' {'started' if enabled else 'stopped'} | status: {status}"

    def write_batch(self, changes: list[tuple[str, str, str, str]]) -> tuple[bool, str, str]:
        if not changes:
            return True, "No pending changes.", ""

        standard_changes = []
        autostart_changes = []

        for key, scope, val, itype in changes:
            full_key = f"{scope}/{key}" if scope and scope != "DEFAULT" else f"autostart/{key}"
            if scope == "autostart" or full_key in AUTOSTART_DEFAULTS or f"autostart/{key}" in AUTOSTART_DEFAULTS:
                autostart_changes.append((key, scope, val, itype))
            else:
                standard_changes.append((key, scope, val, itype))

        success = True
        msg = ""
        debug = ""

        backup_path = None
        if changes:
            backup_path = self.create_backup()

        input_valid, input_err = self._validate_lua(self.config_path) if self.config_path.exists() else (True, "")

        if standard_changes:
            success, msg, debug = super().write_batch(standard_changes)

        if not success:
            return success, msg, debug

        if autostart_changes:
            try:
                content = self.config_path.read_text(encoding="utf-8") if self.config_path.exists() else ""
                lines = content.splitlines() if content else []

                has_start_block = any(
                    "hyprland.start" in l and not _is_header_comment(lines, idx) and not l.strip().startswith("--")
                    for idx, l in enumerate(lines)
                )

                for key, scope, val_str, _ in autostart_changes:
                    full_key = f"{scope}/{key}" if scope and scope != "DEFAULT" else f"autostart/{key}"
                    meta = AUTOSTART_DEFAULTS.get(full_key) or AUTOSTART_DEFAULTS.get(f"autostart/{key}")

                    if not meta:
                        continue

                    pattern = meta["pattern"]
                    canonical = meta["canonical"]
                    want_enabled = str(val_str).lower() in ("true", "1", "yes", "on", "t", "y")

                    matched_idx = -1
                    is_currently_commented = False

                    for idx, line in enumerate(lines):
                        if _is_header_comment(lines, idx):
                            continue

                        stripped = line.strip()
                        if re.search(pattern, stripped):
                            matched_idx = idx
                            is_currently_commented = stripped.startswith("--")
                            if not is_currently_commented:
                                break

                    if want_enabled:
                        if matched_idx != -1:
                            if is_currently_commented:
                                raw_line = lines[matched_idx]
                                indent = raw_line[:len(raw_line) - len(raw_line.lstrip())]
                                uncommented = re.sub(r'^\s*--+\s*', '', raw_line)
                                lines[matched_idx] = indent + uncommented

                                # If the enclosing hl.on(...) block is commented, activate it
                                # as well, otherwise the uncommented entry would never run.
                                block_open = -1
                                for j in range(matched_idx - 1, -1, -1):
                                    s = lines[j].strip()
                                    if s.startswith("--") and "hl.on(" in s:
                                        block_open = j
                                        break
                                    if "hl.on(" in s:
                                        break
                                if block_open != -1:
                                    raw = lines[block_open]
                                    ind = raw[:len(raw) - len(raw.lstrip())]
                                    lines[block_open] = ind + re.sub(r'^\s*--+\s*', '', raw)
                                    for j in range(matched_idx + 1, len(lines)):
                                        s = lines[j].strip()
                                        if s.startswith("--") and s.lstrip("--").strip().startswith("end)"):
                                            raw = lines[j]
                                            ind = raw[:len(raw) - len(raw.lstrip())]
                                            lines[j] = ind + re.sub(r'^\s*--+\s*', '', raw)
                                            break
                        else:
                            insert_line = f"    {canonical}"
                            block_end_idx = -1
                            block_start_idx = -1

                            for i, l in enumerate(lines):
                                if (
                                    "hyprland.start" in l
                                    and not _is_header_comment(lines, i)
                                    and not l.strip().startswith("--")
                                ):
                                    block_start_idx = i
                                elif (
                                    block_start_idx != -1
                                    and not l.strip().startswith("--")
                                    and l.strip().startswith("end)")
                                ):
                                    block_end_idx = i
                                    break

                            if block_end_idx != -1:
                                lines.insert(block_end_idx, insert_line)
                            else:
                                if not has_start_block:
                                    lines.append('\nhl.on("hyprland.start", function()')
                                    lines.append(insert_line)
                                    lines.append('end)\n')
                                    has_start_block = True
                                else:
                                    lines.append(insert_line)

                    else: # want_enabled is False
                        if matched_idx != -1 and not is_currently_commented:
                            raw_line = lines[matched_idx]
                            indent = raw_line[:len(raw_line) - len(raw_line.lstrip())]
                            lines[matched_idx] = f"{indent}-- {raw_line.strip()}"

                new_content = "\n".join(lines) + "\n"
                self.config_path.parent.mkdir(parents=True, exist_ok=True)

                out_fd, tmp_path_str = tempfile.mkstemp(dir=self.config_path.parent, text=True, suffix=".lua")
                with os.fdopen(out_fd, "w", encoding="utf-8") as f:
                    f.write(new_content)

                tmp_path = Path(tmp_path_str)
                if self.config_path.exists():
                    try:
                        tmp_path.chmod(stat.S_IMODE(self.config_path.stat().st_mode))
                    except OSError:
                        pass

                # Post-write safety net: reject syntactically invalid output
                # before it can ever replace the live config. If the input file
                # was already broken, allow the toggle through (pre-existing error).
                valid, err = self._validate_lua(tmp_path)
                if not valid and input_valid:
                    tmp_path.unlink(missing_ok=True)
                    return False, f"Lua validation failed; config left unchanged: {err}", debug

                tmp_path.replace(self.config_path)

                if hasattr(self, "file_mtimes"):
                    self.file_mtimes[str(self.config_path)] = self.config_path.stat().st_mtime

                msg = f"Successfully batched {len(changes)} autostart changes."

            except Exception as e:
                return False, f"Autostart Engine failed to write changes: {e}", debug

        # Final belt-and-braces validation of the merged result. If a standard
        # (AST) write produced broken Lua, roll back to the pre-write snapshot.
        valid, err = self._validate_lua(self.config_path)
        if not valid:
            if not input_valid:
                msg += " [warn: file already had a Lua syntax error before this change]"
            else:
                restored = self.restore_backup()
                note = f" (restored backup {backup_path.name})" if restored and backup_path else ""
                return False, f"Lua validation failed after write{note}: {err}", debug

        return True, msg, debug
