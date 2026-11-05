#!/bin/bash
#
# Dynamic GNOME Terminal + xdotool launcher
# Adds workspace support via `xdotool set_desktop <N>`
# Adds return to initial workspace
# Version 0.4

CURRENT_DESKTOP=$(xdotool get_desktop)
echo "Starting in workspace $CURRENT_DESKTOP"

CONFIG_FILE="${1:-./terminals.conf}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Config file not found: $CONFIG_FILE"
  echo "Usage: $0 [config_file]"
  exit 1
fi

echo "Using configuration: $CONFIG_FILE"

# --- DATA STRUCTURES ---
declare -A TERMINAL_GEOM
declare -A TERMINAL_OPTS
declare -A TERMINAL_WS
declare -A COMMANDS_BY_TERM_TAB
declare -A DELAY_BY_TERM_TAB
declare -A TABS_BY_TERM
declare -a TERMINAL_ORDER

# --- PARSE CONFIG FILE ---
while IFS='|' read -r WS TERM GEOM OPTS TAB DELAY CMDS; do
  # Skip comments and blank lines
  [[ -z "$WS" || "$WS" =~ ^# ]] && continue

  OPTS=${OPTS:-""}
  DELAY=${DELAY:-0}
  WS=${WS:-0}

  # Only add to ordered list if not already present
  if [[ ! " ${TERMINAL_ORDER[*]} " =~ " ${TERM} " ]]; then
    TERMINAL_ORDER+=("$TERM")
  fi

  TERMINAL_GEOM["$TERM"]="$GEOM"
  TERMINAL_OPTS["$TERM"]="$OPTS"
  TERMINAL_WS["$TERM"]="$WS"
  COMMANDS_BY_TERM_TAB["${TERM}_${TAB}"]="$CMDS"
  DELAY_BY_TERM_TAB["${TERM}_${TAB}"]="$DELAY"

  # Track tabs per terminal
  if [[ -z "${TABS_BY_TERM[$TERM]}" ]]; then
    TABS_BY_TERM["$TERM"]="$TAB"
  else
    TABS_BY_TERM["$TERM"]+=$'\n'"$TAB"
  fi
done < "$CONFIG_FILE"

# --- FUNCTION: run_commands() ---
run_commands() {
  local cmd_string="$1"
  IFS=';' read -r -a cmds <<< "$cmd_string"
  for cmd in "${cmds[@]}"; do
    xdotool type "$cmd"
    xdotool key Return
    sleep 0.1
  done
}

# --- MAIN LOOP ---
CURRENT_WS=-1

for TERM in "${TERMINAL_ORDER[@]}"; do
  GEOM="${TERMINAL_GEOM[$TERM]}"
  OPTS="${TERMINAL_OPTS[$TERM]}"
  WS="${TERMINAL_WS[$TERM]}"

  # Switch workspace only if needed
  if [[ "$WS" != "$CURRENT_WS" ]]; then
    echo "Switching to workspace $WS..."
    xdotool set_desktop "$WS"
    sleep 0.5
    CURRENT_WS="$WS"
  fi

  echo "Launching terminal '$TERM' on workspace $WS at geometry $GEOM with options: [$OPTS]"
  eval gnome-terminal --geometry="$GEOM" --title="$TERM" $OPTS &
  sleep 0.8

  WIN_ID=$(xdotool search --name "$TERM" | head -n 1)
  xdotool windowactivate "$WIN_ID"

  TAB_LIST=($(printf '%s\n' "${TABS_BY_TERM[$TERM]}" | sort -V))

  for idx in "${!TAB_LIST[@]}"; do
    TAB="${TAB_LIST[$idx]}"
    CMD_KEY="${TERM}_${TAB}"
    CMD_STRING="${COMMANDS_BY_TERM_TAB[$CMD_KEY]}"
    DELAY="${DELAY_BY_TERM_TAB[$CMD_KEY]}"

    if (( $(echo "$DELAY > 0" | bc -l) )); then
      echo "Waiting ${DELAY}s before executing $TERM $TAB..."
      sleep "$DELAY"
    fi

    echo "Running commands for $TERM $TAB..."
    run_commands "$CMD_STRING"

    # If there’s another tab, open it
    if (( idx < ${#TAB_LIST[@]} - 1 )); then
      sleep 0.4
      xdotool key "ctrl+shift+t"
      sleep 0.6
    fi
  done

  xdotool set_window --name "$TERM" "$WIN_ID"
done

# Return to the desktop we started with
echo "Return to initial workspace $CURRENT_DESKTOP "
xdotool set_desktop $CURRENT_DESKTOP

