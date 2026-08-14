#!/bin/bash

# Nuclear (flatpak) — toggle the special music workspace
PLAYER_BIN="nuclear-music-player"
PLAYER_CLASS="nuclear-music-player"

if pgrep -x "$PLAYER_BIN" >/dev/null; then
	# If running, just toggle the special workspace
	hyprctl dispatch movetoworkspacesilent "special:music,class:^($PLAYER_CLASS)$"
	hyprctl dispatch togglespecialworkspace music
else
	# If not running, launch it
	setsid flatpak run com.nuclearplayer.Nuclear >/dev/null 2>&1 &

	# Wait for the window to actually appear (timeout after 5 seconds)
	count=0
	while [ $count -lt 50 ]; do
		if hyprctl clients | grep -qi "class: $PLAYER_CLASS"; then
			break
		fi
		sleep 0.1
		((count++))
	done

	# Force move the window to special:music
	hyprctl dispatch movetoworkspacesilent "special:music,class:^($PLAYER_CLASS)$"

	# Show the workspace
	hyprctl dispatch togglespecialworkspace music
fi