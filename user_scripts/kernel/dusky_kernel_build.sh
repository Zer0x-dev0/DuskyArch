#!/usr/bin/env bash
set -euo pipefail

sudo systemd-run --scope --slice=dusky-build.slice \
    --unit="dusky-kernel-build-$(date +%s)" \
    --uid=ninja \
    --working-directory=/home/ninja \
    python3 /home/ninja/user_scripts/kernel/dusky_kernal_compile.py