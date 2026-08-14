#!/usr/bin/env bash

{
  COLOR_FILE="$HOME/.config/matugen/generated/papirus"
  [[ -f "$COLOR_FILE" ]] || exit 0

  # 1. Read the palette file into RAM
  mapfile -t lines < "$COLOR_FILE"

  # 2. Extract and clean the target color
  TARGET="${lines[0]//[# ]/}"
  [[ ${#TARGET} -ge 6 ]] || exit 0
  TARGET=${TARGET:0:6}

  TR=$((16#${TARGET:0:2}))
  TG=$((16#${TARGET:2:2}))
  TB=$((16#${TARGET:4:2}))

  # 3. Extract the mapping array
  MAPPING="${lines[${#lines[@]}-1]}"

  # 4. Find the closest named Papirus color
  closest=$(
    awk -v r="$TR" -v g="$TG" -v b="$TB" -v m="$MAPPING" '
    BEGIN {
      n = split(m, arr)
      for (i = 1; i <= n; i++) {
        split(arr[i], p, ":")
        cr = strtonum("0x" substr(p[2],1,2))
        cg = strtonum("0x" substr(p[2],3,2))
        cb = strtonum("0x" substr(p[2],5,2))
        d = (r-cr)^2 + (g-cg)^2 + (b-cb)^2

        if (min == "" || d < min) {
          min = d
          name = p[1]
        }
      }
      print name
    }
  ')

  # 5. Resolve the accent hex and a 0.8x darkened back color
  HEX=$(awk -v m="$MAPPING" -v name="$closest" '
    BEGIN {
      n = split(m, arr)
      for (i = 1; i <= n; i++) {
        split(arr[i], p, ":")
        if (p[1] == name) print toupper(p[2])
      }
    }')
  [[ -n "$HEX" ]] || exit 0

  DARK=$(awk -v h="$HEX" '
    BEGIN {
      r = int(strtonum("0x" substr(h,1,2)) * 0.8)
      g = int(strtonum("0x" substr(h,3,2)) * 0.8)
      b = int(strtonum("0x" substr(h,5,2)) * 0.8)
      printf "%02X%02X%02X", r, g, b
    }')
  HEX=${HEX,,}
  DARK=${DARK,,}

  NCPU=$(nproc 2>/dev/null || printf '4')
  for theme in Papirus Papirus-Dark; do
    dir="$HOME/.local/share/icons/$theme"
    [[ -d "$dir" ]] || continue

    # 6. Restore the active color set from the pristine system theme.
    #    papirus-folders only symlinks folder.svg -> folder-$closest.svg; it
    #    never copies the color-set files themselves, and local copies can
    #    carry stale colors from older recolor passes (e.g. a folder stuck
    #    in adwaita/nordic blue) that no sed pattern could ever match.
    #    The 8x8/16x16/*@2x dirs are fed by the size-sync below instead of
    #    being re-stocked here (their content must not go back to stock
    #    after the sed pass has already recolored the 22x22 sources).
    #    Papirus-Dark symlinks its 22x22/24x24 places dirs into the Papirus
    #    theme (folder SVGs are identical between variants); writing through
    #    the symlink would re-stock files the Papirus pass already
    #    recolored, and find-based passes never descend into symlinked dirs
    #    to fix them again - so those dirs are skipped here.
    if [[ -n "$closest" ]]; then
      for sz in 22x22 24x24 32x32 48x48 64x64; do
        dest="$dir/$sz/places"
        [[ -L "$dest" ]] && continue
        src="/usr/share/icons/$theme/$sz/places"
        [[ -d "$src" ]] || continue
        mkdir -p "$dest"
        cp -f "$src/folder-$closest"*.svg "$dest/" 2>/dev/null || :
        cp -f "$src/user-$closest"*.svg "$dest/" 2>/dev/null || :
        for plain in drive-harddisk computer network-workgroup user-bookmarks; do
          cp -f "$src/$plain.svg" "$dest/" 2>/dev/null || :
        done
      done
      if ! papirus-folders -o -C "$closest" -t "$theme" >/dev/null 2>&1; then
        sudo papirus-folders -o -C "$closest" -t "$theme" >/dev/null 2>&1 || :
      fi
    fi

    # 7. Drop dead color-set leftovers (regular files that no longer
    #    match the active set). Every folder/user icon name is a symlink
    #    to the active set, so non-active regular files are unreferenced
    #    stale copies (e.g. corrupt blue variants from older recolor
    #    passes) - and the rebuild above recreates any set from the
    #    system theme the moment it becomes active.
    find "$dir" \
      \( -path "*/places/folder-*.svg" -o -path "*/places/user-*.svg" \) \
      ! -name "folder.svg" ! -name "folder-$closest*.svg" \
      ! -name "user-$closest*.svg" -type f -delete 2>/dev/null || :

    # 8. Normalize the active folder palette to the current accent. Every
    #    known stock Papirus folder accent is mapped to the accent hex /
    #    darkened back color. Only the in-place sizes are sed'd here; the
    #    8x8/16x16/*@2x dirs are fed solely by the size-sync below (their
    #    mtimes must stay untouched so rsync --update can detect changes).
    #    Symlinked folder.svg is never touched (sed -i would replace the
    #    symlink with a regular file) and symlinked dirs are naturally
    #    skipped by find.
    find "$dir" \
      \( -path "*/22x22/*" -o -path "*/24x24/*" -o -path "*/32x32/*" \
         -o -path "*/48x48/*" -o -path "*/64x64/*" \) \
      \( -name "folder-$closest*.svg" -o -name "user-$closest*.svg" \
         -o -name "drive-harddisk.svg" -o -name "computer.svg" \
         -o -name "network-workgroup.svg" -o -name "user-bookmarks.svg" \) \
      ! -name "folder.svg" -type f -print0 2>/dev/null | \
      xargs -0 -P"$NCPU" -I'{}' sed -i \
        -e "s/#5294e2/#$HEX/gI" -e "s/#4877b1/#$DARK/gI" -e "s/#1d344f/#$DARK/gI" \
        -e "s/#eeca8f/#$HEX/gI" -e "s/#c89e6b/#$DARK/gI" -e "s/#917359/#$DARK/gI" \
        -e "s/#93c0ea/#$HEX/gI" -e "s/#3a87e5/#$DARK/gI" -e "s/#bea172/#$DARK/gI" \
        -e "s/#7599bb/#$DARK/gI" \
        -e "s/#81a1c1/#$HEX/gI" -e "s/#5e81ac/#$DARK/gI" \
        -e "s/#16a085/#$HEX/gI" -e "s/#12806a/#$DARK/gI" \
        -e "s/#607d8b/#$DARK/gI" -e "s/#57b8ec/#$HEX/gI" \
        -e "s/#00bcd4/#$HEX/gI" -e "s/#45abb7/#$DARK/gI" \
        -e "s/#eb6637/#$HEX/gI" -e "s/#87b158/#$HEX/gI" \
        -e "s/#5c6bc0/#$HEX/gI" -e "s/#ca71df/#$HEX/gI" \
        -e "s/#ee923a/#$HEX/gI" -e "s/#f06292/#$HEX/gI" \
        -e "s/#e25252/#$HEX/gI" -e "s/#7e57c2/#$HEX/gI" \
        -e "s/#ae8e6c/#$DARK/gI" -e "s/#d1bfae/#$DARK/gI" \
        -e "s/#a30002/#$DARK/gI" -e "s/#676767/#$DARK/gI" \
        '{}' 2>/dev/null || :

    # 9. Unify the Desktop/Public folder variants with the plain folder
    #    design: stock Papirus draws them as a monitor and a photo-person,
    #    which looks inconsistent next to the other folders (and the photo/
    #    person never reads as the accent color). The places sidebar's
    #    "Desktop" entry resolves through user-desktop, so that is unified
    #    too. Runs before the size-sync so every size inherits the design.
    if [[ -n "$closest" ]]; then
      for sz in 22x22 24x24 32x32 48x48 64x64; do
        dest="$dir/$sz/places"
        [[ -L "$dest" ]] && continue
        [[ -f "$dest/folder-$closest.svg" ]] || continue
        cp -f "$dest/folder-$closest.svg" "$dest/folder-$closest-desktop.svg" 2>/dev/null || :
        cp -f "$dest/folder-$closest.svg" "$dest/folder-$closest-public.svg" 2>/dev/null || :
        cp -f "$dest/folder-$closest.svg" "$dest/user-$closest-desktop.svg" 2>/dev/null || :
      done
    fi

    # 10. Small-size and HiDPI lookups: populate the 8x8/16x16/*@2x dirs with
    #    the recolored 22px vector files, so every lookup hits the accent
    #    (the @2x dirs are never covered by papirus-folders and would stay
    #    stock otherwise). rsync --update syncs only changed files in one
    #    pass per dir, so repeat runs are near-instant.
    for dst in 16x16 8x8 16x16@2x 22x22@2x 24x24@2x 32x32@2x 48x48@2x 64x64@2x; do
      mkdir -p "$dir/$dst/places"
      rsync -a --update --quiet \
        --include='folder*.svg' --include='user*.svg' \
        --include='drive-harddisk.svg' --include='computer.svg' \
        --include='network-workgroup.svg' --include='user-bookmarks.svg' \
        --include='gtk-directory.svg' --include='inode-directory.svg' \
        --include='stock_folder.svg' --include='insync-folder.svg' \
        --exclude='*' \
        "$dir/22x22/places/" "$dir/$dst/places/" 2>/dev/null || :
    done

    gtk-update-icon-cache -f -t "$dir" >/dev/null 2>&1 || :
  done

} >/dev/null 2>&1 </dev/null