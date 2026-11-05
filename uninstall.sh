#!/usr/bin/env bash

# ==========================================================
# VIVARIUM WORKSPACES UNINSTALLER
# ==========================================================

set -e

SCRIPT_DIR="$HOME/.config/waybar/scripts"
CONFIG_DIR="$HOME/.config/vivarium"

SCRIPT_FILE="vivarium-workspace-item.sh"
CONFIG_FILE="workspaces.conf"

BACKUP_DIR="$HOME/.local/share/vivarium-workspaces/backup"

echo "======================================"
echo "     VIVARIUM WORKSPACES REMOVAL"
echo "======================================"

# Restore or remove workspace script
if [[ -f "$BACKUP_DIR/$SCRIPT_FILE" ]]; then
    cp "$BACKUP_DIR/$SCRIPT_FILE" "$SCRIPT_DIR/$SCRIPT_FILE"
    echo "Restored previous workspace script."
else
    rm -f "$SCRIPT_DIR/$SCRIPT_FILE"
    echo "Removed installed workspace script."
fi

# Restore or remove workspace configuration
if [[ -f "$BACKUP_DIR/$CONFIG_FILE" ]]; then
    cp "$BACKUP_DIR/$CONFIG_FILE" "$CONFIG_DIR/$CONFIG_FILE"
    echo "Restored previous workspace configuration."
else
    if [[ -f "$CONFIG_DIR/$CONFIG_FILE" ]]; then
        echo "Preserved workspace configuration."
        echo "No previous backup was available."
    fi
fi
echo
echo "Uninstallation completed."
echo
echo "Backup files retained at:"
echo "  $BACKUP_DIR"
echo
echo "Note: Waybar modules, CSS, and Vivarium IPC settings"
echo "were not modified."
echo
