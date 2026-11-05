#!/usr/bin/env bash

# ==========================================================
# VIVARIUM WORKSPACES INSTALLER
# ==========================================================

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCRIPT_DIR="$HOME/.config/waybar/scripts"
CONFIG_DIR="$HOME/.config/vivarium"

SCRIPT_FILE="vivarium-workspace-item.sh"
CONFIG_FILE="workspaces.conf"

BACKUP_DIR="$HOME/.local/share/vivarium-workspaces/backup"

echo "======================================"
echo "       VIVARIUM WORKSPACES"
echo "======================================"

# Create directories
mkdir -p "$SCRIPT_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$BACKUP_DIR"

# Backup existing files
if [[ -f "$SCRIPT_DIR/$SCRIPT_FILE" ]]; then
    cp -n "$SCRIPT_DIR/$SCRIPT_FILE" "$BACKUP_DIR/$SCRIPT_FILE"
    echo "Backed up existing workspace script."
fi

if [[ -f "$CONFIG_DIR/$CONFIG_FILE" ]]; then
    cp -n "$CONFIG_DIR/$CONFIG_FILE" "$BACKUP_DIR/$CONFIG_FILE"
    echo "Backed up existing workspace configuration."
fi

# Install workspace script
install -m 755 \
    "$REPO_DIR/scripts/$SCRIPT_FILE" \
    "$SCRIPT_DIR/$SCRIPT_FILE"

# Install workspace configuration only if it does not exist
if [[ ! -f "$CONFIG_DIR/$CONFIG_FILE" ]]; then
    install -m 644 \
        "$REPO_DIR/config/$CONFIG_FILE" \
        "$CONFIG_DIR/$CONFIG_FILE"
    echo "Installed default workspace configuration."
else
    echo "Existing workspace configuration preserved."
fi
echo
echo "Installation completed successfully."
echo
echo "Installed files:"
echo "  $SCRIPT_DIR/$SCRIPT_FILE"
echo "  $CONFIG_DIR/$CONFIG_FILE"
echo
echo "Next steps:"
echo "  1. Configure Vivarium IPC."
echo "  2. Apply the Vivarium IPC patch."
echo "  3. Merge the Waybar example modules."
echo "  4. Add the supplied CSS."
echo
