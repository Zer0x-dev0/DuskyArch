#!/usr/bin/env python3
"""Generate a matugen-templated hyprcursor theme from Bibata_Cursor SVG sources.

Fetches the "modern" shape set of ful1e5/Bibata_Cursor and rewrites its
placeholder palette (green body / blue outline / colored accents) into matugen
color tokens. The result is a hyprcursor "working state" theme under
~/.config/matugen/templates/cursor/  — every file in an input_path directory is
rendered by matugen, so each theme change recolors the compiled cursor theme
(see [templates.hyprcursor] in ~/.config/matugen/config.toml).

Toggle which Material tone each placeholder maps to in COLOR_TOKENS below.

Usage:
    python3 gen_cursor_templates.py [--output DIR] [--cache CACHE_DIR]

Rerun after upstream SVGs change; cached downloads live in
~/.cache/dusky/bibata_cursor_svg/ and are reused between runs.
"""

from __future__ import annotations

import argparse
import pathlib
import sys
import urllib.request

BASE_URL = "https://raw.githubusercontent.com/ful1e5/Bibata_Cursor/main/svg"

OUTPUT_DIR = pathlib.Path.home() / ".config" / "matugen" / "templates" / "cursor"
CACHE_DIR = pathlib.Path.home() / ".cache" / "dusky" / "bibata_cursor_svg"

THEME_NAME = "Matugen-Cursor"
THEME_DESCRIPTION = "Bibata Modern shapes, recolored from the wallpaper by matugen"
THEME_VERSION = "1.0"

FRAME_DELAY_MS = 40  # matches Bibata's x11_delay

# Bibata placeholder palette -> matugen color tokens.
# #00FF00 is the cursor body, #0000FF the outline; the rest are accents
# (forbidden badges, copy/help icons, spinner arcs, quote boxes...).
COLOR_TOKENS = {
    "#00FF00": "{{colors.primary.default.hex}}",
    "#0000FF": "{{colors.outline.default.hex}}",
    "#FE0000": "{{colors.error.default.hex}}",
    "#F05024": "{{colors.error.default.hex}}",
    "#FF0000": "{{colors.error.default.hex}}",
    "#06B231": "{{colors.tertiary.default.hex}}",
    "#7EBA41": "{{colors.tertiary.default.hex}}",
    "#0A6857": "{{colors.tertiary.default.hex}}",
    "#32A0DA": "{{colors.primary.default.hex}}",
    "#179DD8": "{{colors.primary.default.hex}}",
    "#FCB813": "{{colors.secondary.default.hex}}",
    "#5F3BE4": "{{colors.secondary_container.default.hex}}",
    "#2C2C2C": "{{colors.on_surface.default.hex}}",
    "#606060": "{{colors.on_surface_variant.default.hex}}",
}
WHITE_TOKEN = "{{colors.on_primary_container.default.hex}}"

# (shape, group dir, hotspot on the 256x256 artboard, X11 alias names)
# Hotspots and aliases follow Bibata's configs/normal/x.build.toml.
SHAPES = [
    ("X_cursor", "shared", (128, 128), ["pirate", "x-cursor"]),
    ("bd_double_arrow", "modern-arrow", (128, 128), ["nwse-resize", "size_fdiag"]),
    ("bottom_left_corner", "shared", (26, 232), ["sw-resize"]),
    ("bottom_right_corner", "shared", (229, 232), ["se-resize"]),
    ("bottom_side", "shared", (129, 234), ["s-resize"]),
    ("bottom_tee", "shared", (128, 230), []),
    ("center_ptr", "modern", (127, 17), []),
    ("circle", "modern", (55, 17), ["forbidden"]),
    ("context-menu", "modern", (57, 17), []),
    ("copy", "modern", (55, 17), []),
    ("cross", "shared", (128, 128), ["cross_reverse", "diamond_cross"]),
    ("crossed_circle", "shared", (128, 128), ["not-allowed"]),
    ("crosshair", "shared", (128, 128), []),
    ("dnd-ask", "hand", (100, 65), []),
    ("dnd-copy", "hand", (100, 65), []),
    ("dnd-link", "hand", (100, 65), ["alias"]),
    ("dnd_no_drop", "hand", (100, 65), ["no-drop"]),
    ("dotbox", "shared", (128, 128), ["dot_box_mask", "draped_box", "icon", "target"]),
    ("fd_double_arrow", "modern-arrow", (128, 128), ["nesw-resize", "size_bdiag"]),
    ("grabbing", "hand", (128, 66), ["closedhand", "dnd-move", "dnd-none"]),
    ("hand1", "hand", (144, 79), ["grab", "openhand"]),
    ("hand2", "hand", (114, 18), ["pointer", "pointing_hand"]),
    ("left_ptr", "modern", (55, 17), ["arrow", "default", "top_left_arrow"]),
    ("left_ptr_watch", "modern", (55, 17), ["progress"]),
    ("left_side", "shared", (21, 128), ["w-resize"]),
    ("left_tee", "shared", (230, 128), []),
    ("link", "modern", (55, 17), []),
    ("ll_angle", "shared", (30, 223), []),
    ("lr_angle", "shared", (224, 230), []),
    ("move", "modern-arrow", (128, 128), ["all-scroll", "fleur", "size_all"]),
    ("pencil", "shared", (46, 211), ["draft"]),
    ("plus", "shared", (128, 128), ["cell"]),
    ("pointer-move", "modern", (55, 17), []),
    ("question_arrow", "shared", (42, 86), ["help", "left_ptr_help", "whats_this"]),
    ("right_ptr", "modern", (204, 17), ["draft_large", "draft_small"]),
    ("right_side", "shared", (233, 128), ["e-resize"]),
    ("right_tee", "shared", (29, 128), []),
    ("sb_down_arrow", "modern-arrow", (128, 222), ["down-arrow"]),
    ("sb_h_double_arrow", "modern-arrow", (128, 128), ["col-resize", "ew-resize", "h_double_arrow", "size-hor", "size_hor", "split_h"]),
    ("sb_left_arrow", "modern-arrow", (33, 128), ["left-arrow"]),
    ("sb_right_arrow", "modern-arrow", (223, 128), ["right-arrow"]),
    ("sb_up_arrow", "modern-arrow", (128, 33), ["up-arrow"]),
    ("sb_v_double_arrow", "modern-arrow", (128, 128), ["double_arrow", "ns-resize", "row-resize", "size-ver", "size_ver", "split_v", "v_double_arrow"]),
    ("tcross", "shared", (128, 128), ["color-picker"]),
    ("top_left_corner", "shared", (29, 24), ["nw-resize"]),
    ("top_right_corner", "shared", (229, 24), ["ne-resize"]),
    ("top_side", "shared", (128, 23), ["n-resize"]),
    ("top_tee", "shared", (128, 27), []),
    ("ul_angle", "shared", (33, 33), []),
    ("ur_angle", "shared", (225, 33), []),
    ("vertical-text", "shared", (128, 128), []),
    ("wait", "shared", (128, 128), ["watch"]),
    ("wayland-cursor", "shared", (128, 128), []),
    ("xterm", "shared", (128, 128), ["ibeam", "text"]),
    ("zoom-in", "shared", (116, 116), []),
    ("zoom-out", "shared", (116, 116), []),
]

# Animated shapes: (group dir, frame count).
ANIMS = {
    "left_ptr_watch": ("modern", 54),
    "wait": ("shared", 54),
}

MANIFEST_HL = f"""name = {THEME_NAME}
description = {THEME_DESCRIPTION}
version = {THEME_VERSION}
cursors_directory = hyprcursors
"""

META_TEMPLATE = """resize_algorithm = bilinear
hotspot_x = {hotspot_x}
hotspot_y = {hotspot_y}
{overrides}{sizes}"""


def download(url: str, dest: pathlib.Path) -> None:
    if dest.is_file():
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "dusky-matugen-cursor"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read()
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    tmp.write_bytes(data)
    tmp.rename(dest)


def convert_to_template(svg: str) -> str:
    svg = svg.replace('fill="white"', f'fill="{WHITE_TOKEN}"')
    svg = svg.replace('stroke="white"', f'stroke="{WHITE_TOKEN}"')
    svg = svg.replace('fill="#fff"', f'fill="{WHITE_TOKEN}"')
    for hex_color, token in COLOR_TOKENS.items():
        svg = svg.replace(hex_color, token)
    return svg


def alias_list(shape: str, aliases: list[str]) -> list[str]:
    names: list[str] = []
    for name in [shape, *aliases]:
        for candidate in (name, name.replace("-", "_")):
            if candidate not in names:
                names.append(candidate)
    return names


def meta_hotspot(hotspot: tuple[int, int]) -> tuple[str, str]:
    return f"{hotspot[0] / 256:.4f}", f"{hotspot[1] / 256:.4f}"


def write_shape(out: pathlib.Path, name: str, svg_text: str, hotspot: tuple[int, int], aliases: list[str], frames: int = 1) -> None:
    shape_dir = out / "hyprcursors" / name
    shape_dir.mkdir(parents=True, exist_ok=True)

    overrides = "".join(f"define_override = {alias}\n" for alias in alias_list(name, aliases))

    if frames == 1:
        sizes = "define_size = 64, image.svg\n"
        (shape_dir / "image.svg").write_text(svg_text)
    else:
        sizes = "".join(
            f"define_size = 64, image-{i:02d}.svg, {FRAME_DELAY_MS}\n"
            for i in range(1, frames + 1)
        )

    hx, hy = meta_hotspot(hotspot)
    (shape_dir / "meta.hl").write_text(
        META_TEMPLATE.format(hotspot_x=hx, hotspot_y=hy, overrides=overrides, sizes=sizes)
    )


def fetch_shape_svg(group: str, name: str) -> str:
    url = f"{BASE_URL}/groups/{group}/{name}.svg"
    dest = CACHE_DIR / f"groups_{group}" / f"{name}.svg"
    download(url, dest)
    return dest.read_text()


def build(out_dir: pathlib.Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "manifest.hl").write_text(MANIFEST_HL)

    for name, group, hotspot, aliases in SHAPES:
        if name in ANIMS:
            continue
        svg = fetch_shape_svg(group, name)
        write_shape(out_dir, name, convert_to_template(svg), hotspot, aliases)

    for name, (group, frames) in ANIMS.items():
        shape_dir = out_dir / "hyprcursors" / name
        shape_dir.mkdir(parents=True, exist_ok=True)
        meta = META_TEMPLATE.format(
            hotspot_x="0.5000", hotspot_y="0.5000", overrides="", sizes=""
        ) + "".join(
            f"define_size = 64, image-{i:02d}.svg, {FRAME_DELAY_MS}\n"
            for i in range(1, frames + 1)
        )
        (shape_dir / "meta.hl").write_text(meta)
        for i in range(1, frames + 1):
            svg = fetch_shape_svg(f"{group}/{name}", f"{name}-{i:02d}")
            (shape_dir / f"image-{i:02d}.svg").write_text(convert_to_template(svg))

    print(f"Wrote {len(SHAPES)} shapes to {out_dir}")


def main() -> None:
    global OUTPUT_DIR, CACHE_DIR
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--output", default=str(OUTPUT_DIR))
    parser.add_argument("--cache", default=str(CACHE_DIR))
    args = parser.parse_args()
    OUTPUT_DIR = pathlib.Path(args.output)
    CACHE_DIR = pathlib.Path(args.cache)
    build(OUTPUT_DIR)


if __name__ == "__main__":
    main()