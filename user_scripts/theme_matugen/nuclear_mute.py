#!/usr/bin/env python3
"""Calm the Nuclear theme for readability.

Nuclear's UI paints `primary` on large surfaces (selected rows, buttons,
progress, focus rings). A fully saturated matugen primary is too loud and
washes out text; this mutes saturation and caps luminance while keeping the
wallpaper's hue, so the theme stays fresh on every wallpaper but readable.

Only primary/ring (matugen-derived) are touched; backgrounds and the muted
fixed accents pass through untouched.

Usage: nuclear_mute.py <nuclear-theme.json>
"""
import colorsys
import json
import sys

MAX_SAT = 0.40   # primary saturation ceiling (was up to ~0.9)
LUM_FLOOR = 0.12
LUM_CEIL = 0.58  # keeps bright yellows/oranges from glowing


def mute_hex(hexval: str) -> str:
    h = hexval.lstrip("#")
    if len(h) != 6:
        return hexval
    r, g, b = int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255
    hue, lum, sat = colorsys.rgb_to_hls(r, g, b)
    sat = min(sat, MAX_SAT)
    lum = max(LUM_FLOOR, min(lum, LUM_CEIL))
    r, g, b = colorsys.hls_to_rgb(hue, lum, sat)
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: nuclear_mute.py <theme.json>")
    path = sys.argv[1]
    with open(path, encoding="utf-8") as fh:
        theme = json.load(fh)
    for block in ("vars", "dark"):
        if block not in theme:
            continue
        for key in ("primary", "ring"):
            val = theme[block].get(key)
            if isinstance(val, str) and val.startswith("#"):
                theme[block][key] = mute_hex(val)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(theme, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
