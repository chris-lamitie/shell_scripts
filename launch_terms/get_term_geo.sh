#!/bin/bash

# This script requires xdotool (gets xdotool) and ncurses (gets tput) installed on the system. Use yum/dnf to install it.

# --- 1. Get Character Dimensions (Columns x Rows) using tput ---
# tput lines and tput cols are reliable for character dimensions in scripts.
LINES_CHARS=$(tput lines)
COLUMNS_CHARS=$(tput cols)

# Check if tput returned valid numbers
if [[ -z "$COLUMNS_CHARS" || -z "$LINES_CHARS" ]]; then
    echo "Error: Could not determine terminal size using tput. Are you running this in a terminal?" >&2
    exit 1
fi

# --- 2. Get Pixel Position (X and Y Offset) ---
# We still use xdotool for the pixel coordinates.
# We suppress error messages.
eval "$(xdotool getactivewindow getwindowgeometry --shell 2>/dev/null)"

# Check if the pixel variables were successfully set by xdotool
if [[ -z "$X" || -z "$Y" ]]; then
    echo "Error: Could not determine pixel coordinates. Are you running this in a graphical environment?" >&2
    exit 1
fi

# --- 3. Construct the gnome-terminal geometry string ---
# Format: WxH+X+Y, where WxH is CHARACTERS and +X+Y is PIXELS.
GEOMETRY="${COLUMNS_CHARS}x${LINES_CHARS}+${X}+${Y}"

# Output the final string
echo "gnome-terminal geometry for this window is: \"$GEOMETRY\""
