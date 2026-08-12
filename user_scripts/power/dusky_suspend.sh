#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Dusky VM-Safe Suspend
# -----------------------------------------------------------------------------
# On bare metal: real S3 suspend (systemctl suspend).
#
# In a VM (virtio-gpu / virgl, e.g. Parallels on Apple Silicon):
# S3 resume loses the GL context and Hyprland/hyprlock cannot recover, leaving
# a frozen lock screen with dead input until the VM is power-cycled.
# So instead of S3 we lock the session and turn the display off (DPMS).
# The guest keeps running; any key press/mouse move wakes the display instantly.

set -euo pipefail

is_vm() {
    systemd-detect-virt --vm >/dev/null 2>&1 || return 1
}

if is_vm; then
    loginctl lock-session
    sleep 1
    hyprctl dispatch dpms off
else
    systemctl suspend
fi