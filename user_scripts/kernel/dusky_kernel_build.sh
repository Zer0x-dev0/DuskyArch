#!/usr/bin/env bash
set -euo pipefail

systemctl --user daemon-reload
systemd-run --user --scope --slice=dusky-build.slice \
    --unit="dusky-kernel-build-$(date +%s)" \
    python3 /home/ninja/user_scripts/kernel/dusky_kernal_compile.py