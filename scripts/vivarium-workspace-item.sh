#!/usr/bin/env bash

# ==========================================================
# VIVARIUM WORKSPACE ITEM
# Individual clickable workspace display
# ==========================================================

FILE="/tmp/vivarium-workspaces.txt"
CONFIG="$HOME/.config/vivarium/workspaces.conf"

# Load user appearance configuration
if [[ -f "$CONFIG" ]]; then
    source "$CONFIG"
fi

# Safe defaults if configuration is missing
WS_DISPLAY_MODE="${WS_DISPLAY_MODE:-number}"
WS_ICON_ONLY="${WS_ICON_ONLY:-false}"

ACTIVE="${ACTIVE:-#B7E3A1}"
OCCUPIED="${OCCUPIED:-#B9D9EF}"
EMPTY="${EMPTY:-#D3D5D8}"

INDEX="${1:-1}"

# Validate workspace index and IPC file
if [[ ! "$INDEX" =~ ^[1-9]$ ]] || [[ ! -f "$FILE" ]]; then
    echo '{"text":"?"}'
    exit 0
fi

read -ra WORKSPACES < "$FILE"
TOKEN="${WORKSPACES[$((INDEX - 1))]}"

[[ -z "$TOKEN" ]] && {
    echo '{"text":"?"}'
    exit 0
}

# Determine workspace state
COLOR="$EMPTY"
LABEL="$TOKEN"

if [[ "$LABEL" == *"*" ]]; then
    COLOR="$OCCUPIED"
    LABEL="${LABEL%\*}"
fi

IS_ACTIVE=false

if [[ "$LABEL" == \<*\> ]]; then
    IS_ACTIVE=true
    COLOR="$ACTIVE"
    LABEL="${LABEL#<}"
    LABEL="${LABEL%>}"
fi

# Select configured workspace appearance
NAME_VAR="WS${INDEX}_NAME"
ICON_VAR="WS${INDEX}_ICON"
CUSTOM_VAR="WS${INDEX}_CUSTOM"

NAME="${!NAME_VAR:-$LABEL}"
ICON="${!ICON_VAR:-$LABEL}"
CUSTOM="${!CUSTOM_VAR:-$LABEL}"

# Display mode
if [[ "$WS_ICON_ONLY" == "true" ]]; then
    DISPLAY="$ICON"
else
    case "$WS_DISPLAY_MODE" in
        number)
            DISPLAY="$LABEL"
            ;;
        name)
            DISPLAY="$NAME"
            ;;
        icon)
            DISPLAY="$ICON"
            ;;
        custom)
            DISPLAY="$CUSTOM"
            ;;
        *)
            DISPLAY="$LABEL"
            ;;
    esac
fi

# Retain active workspace marker in number mode
if [[ "$IS_ACTIVE" == true && "$WS_DISPLAY_MODE" == "number" && "$WS_ICON_ONLY" != "true" ]]; then
    DISPLAY="[$DISPLAY]"
fi

# Output Waybar JSON
printf '{"text":"<span foreground=\\"%s\\">%s</span>"}\n' "$COLOR" "$DISPLAY"
