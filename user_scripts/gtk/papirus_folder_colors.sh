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

  # 6. Recolor the user-local theme copies. papirus-folders is unreliable for
  #     icons carrying extra accent colors (e.g. the folder-downloads arrow),
  #     so additionally run a deterministic sed pass that normalizes every
  #     known variant - stock Papirus (#5294e2/#4877b1/#1d344f), the
#     paleorange era (#eeca8f/#c89e6b/#917359/#bea172) and the adwaita
    #     era (#93c0ea/#3a87e5) - to the current accent, at every size.
  if [[ -n "$closest" ]]; then
    if ! papirus-folders -C "$closest" >/dev/null 2>&1; then
      sudo papirus-folders -C "$closest" >/dev/null 2>&1
    fi
  fi

  for theme in Papirus Papirus-Dark; do
    dir="$HOME/.local/share/icons/$theme"
    [[ -d "$dir" ]] || continue

    while IFS= read -r f; do
      sed -i \
        -e "s/#5294e2/#$HEX/gI" -e "s/#4877b1/#$DARK/gI" -e "s/#1d344f/#$DARK/gI" \
        -e "s/#eeca8f/#$HEX/gI" -e "s/#c89e6b/#$DARK/gI" -e "s/#917359/#$DARK/gI" \
        -e "s/#93c0ea/#$HEX/gI" -e "s/#3a87e5/#$DARK/gI" -e "s/#bea172/#$DARK/gI" \
        "$f"
    done < <(find "$dir" \( -path "*/places/folder*.svg" -o -path "*/places/user-home.svg" \
        -o -path "*/places/user-desktop.svg" -o -path "*/places/user-trash.svg" \
        -o -path "*/places/drive-harddisk.svg" -o -path "*/places/computer.svg" \
        -o -path "*/places/network-workgroup.svg" -o -path "*/places/user-bookmarks.svg" \))

    # 7. Small-size and HiDPI lookups: replace the currentColor 16px variants
    #     and populate the *@2x scaled dirs with the recolored 22px vector
    #     files, so every lookup hits the accent (the @2x dirs are never
    #     covered by papirus-folders and would stay stock blue otherwise).
    for src in "$dir"/22x22/places/folder*.svg; do
      [[ -f "$src" ]] || continue
      icon="$(basename "$src")"
      cp -f "$src" "$dir/16x16/places/$icon" 2>/dev/null
      cp -f "$src" "$dir/8x8/places/$icon" 2>/dev/null
      for d in 16x16@2x 22x22@2x 24x24@2x 32x32@2x 48x48@2x 64x64@2x; do
        mkdir -p "$dir/$d/places"
        cp -f "$src" "$dir/$d/places/$icon" 2>/dev/null
      done
    done
    for icon in user-home user-desktop user-trash drive-harddisk computer \
                network-workgroup folder-remote user-bookmarks; do
      src="$dir/22x22/places/$icon.svg"
      [[ -f "$src" ]] || continue
      cp -f "$src" "$dir/16x16/places/$icon.svg" 2>/dev/null
      for d in 16x16@2x 22x22@2x 24x24@2x 32x32@2x 48x48@2x 64x64@2x; do
        mkdir -p "$dir/$d/places"
        cp -f "$src" "$dir/$d/places/$icon.svg" 2>/dev/null
      done
    done

    gtk-update-icon-cache -f -t "$dir" >/dev/null 2>&1 || :
  done

} >/dev/null 2>&1 </dev/null