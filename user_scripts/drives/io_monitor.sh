#!/bin/bash
# Compatibility shim — io_monitor.sh was renamed to dusky_disk_monitor_io.py
# This wrapper preserves old Waybar/Rofi calls.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL="$SCRIPT_DIR/dusky_disk_monitor_io.py"
if [ -x "$REAL" ]; then
  exec python3 "$REAL" "$@"
else
  echo "Error: $REAL not found or not executable" >&2
  exit 1
fi
