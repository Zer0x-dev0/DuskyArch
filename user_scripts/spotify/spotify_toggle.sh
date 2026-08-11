#!/bin/bash

# Use official client if present, otherwise fall back to ncspot (ARM/aarch64)
if command -v spotify >/dev/null; then
	PLAYER_BIN="spotify"
	PLAYER_CLASS="Spotify"
elif command -v ncspot >/dev/null; then
	PLAYER_BIN="ncspot"
	PLAYER_CLASS="ncspot"
else
	echo "No Spotify client found (spotify or ncspot)." >&2
	exit 1
fi

# Check if player process is running
if pgrep -x "$PLAYER_BIN" >/dev/null; then
	# If running, just toggle the special workspace
	hyprctl dispatch movetoworkspacesilent "special:music,class:^($PLAYER_CLASS)$"
	hyprctl dispatch togglespecialworkspace music
else
	# If not running, launch it
	"$PLAYER_BIN" &

	# Wait for the window to actually appear (timeout after 5 seconds)
	count=0
	while [ $count -lt 50 ]; do
		if hyprctl clients | grep -qi "class: $PLAYER_CLASS"; then
			break
		fi
		sleep 0.1
		((count++))
	done

	# Force move the window to special:music (quoted to fix syntax error)
	hyprctl dispatch movetoworkspacesilent "special:music,class:^($PLAYER_CLASS)$"

	# Show the workspace
	hyprctl dispatch togglespecialworkspace music
fi
