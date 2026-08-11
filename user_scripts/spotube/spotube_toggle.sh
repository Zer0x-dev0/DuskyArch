#!/bin/bash

# Use Spotube if present, otherwise fall back to the official client
if command -v spotube >/dev/null; then
	PLAYER_BIN="spotube"
	PLAYER_CLASS="(Spotube|spotube)"
elif command -v spotify >/dev/null; then
	PLAYER_BIN="spotify"
	PLAYER_CLASS="Spotify"
else
	# No local client: open the free web player (works without Spotify Premium)
	echo "No music client found (spotube or spotify). Opening web player." >&2
	BROWSER_BIN=$(command -v firefox || command -v chromium || command -v google-chrome-stable)
	if [ -n "$BROWSER_BIN" ]; then
		"$BROWSER_BIN" --new-window "https://open.spotify.com/" >/dev/null 2>&1 &
	fi
	exit 0
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
