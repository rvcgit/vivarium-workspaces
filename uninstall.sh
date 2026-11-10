#!/usr/bin/env bash

# ==========================================================
# VIVARIUM WORKSPACES — UNIFIED UNINSTALLER
# ==========================================================

set -Eeuo pipefail

# Optional dry-run mode: inspect planned removals without
# modifying files, patches or installation records.
DRY_RUN=false

case "${1:-}" in
    "")
        ;;
    --dry-run)
        DRY_RUN=true
        ;;
    *)
        echo "Usage: $0 [--dry-run]"
        exit 2
        ;;
esac

# ----------------------------------------------------------
# PATHS AND FILE NAMES
# ----------------------------------------------------------

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WAYBAR_SCRIPT_DIR="$HOME/.config/waybar/scripts"
WORKSPACE_CONFIG_DIR="$HOME/.config/vivarium"
STATE_DIR="$HOME/.local/share/vivarium-workspaces"

WORKSPACE_SCRIPT="vivarium-workspace-item.sh"
WORKSPACE_CONFIG="workspaces.conf"
RULES_CONFIG="window_rules.conf"

IPC_PATCH="$REPO_DIR/patches/vivarium-ipc.patch"
APP_PATCH="$REPO_DIR/ws_allocate/patches/application-workspace-rules.patch"

STATE_FILE="$STATE_DIR/install-state.sh"

echo
echo "=========================================="
echo "       VIVARIUM WORKSPACES"
echo "          Unified Uninstaller"
echo "=========================================="
echo

die() {
    echo
    echo "ERROR: $1"
    exit 1
}
# ----------------------------------------------------------
# OWNERSHIP RECORD READER
# ----------------------------------------------------------

# Safely decode ordinary legacy paths written by Bash printf %q.
# Only simple characters and backslash-escaped characters are accepted.
decode_legacy_path() {
    local encoded="$1"
    local decoded=""
    local i=0
    local char

    [[ "$encoded" != \$* ]] || return 1

    while (( i < ${#encoded} )); do
        char="${encoded:i:1}"

        if [[ "$char" == "\\" ]]; then
            ((i += 1))
            (( i < ${#encoded} )) || return 1
            char="${encoded:i:1}"
        elif [[ ! "$char" =~ ^[a-zA-Z0-9._/-]$ ]]; then
            return 1
        fi

        decoded+="$char"
        ((i += 1))
    done

    REPLY="$decoded"
}

# Read ownership information as data, never as executable shell code.
load_install_state() {
    local first=""
    local line
    local key
    local value
    local format
    local decoded

    local -A seen=()

    WS_SCRIPT_OWNED=0
    WS_CONFIG_OWNED=0
    IPC_PATCH_OWNED=0
    APP_PATCH_OWNED=0
    APP_RULES_OWNED=0

    VIVARIUM_SOURCE_PATH=""
    VIVARIUM_RULES_DIR=""

    [[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] ||
        die "Installation record is missing, invalid or a symbolic link."

    IFS= read -r first < "$STATE_FILE" || true

    if [[ "$first" == "FORMAT_VERSION=2" ]]; then
        format="v2"
    else
        format="legacy"
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *=* ]] ||
            die "Malformed installation record."

        key="${line%%=*}"
        value="${line#*=}"

        [[ "$key" =~ ^[A-Z0-9_]+$ ]] ||
            die "Invalid field name in installation record."

        [[ -z "${seen[$key]+present}" ]] ||
            die "Duplicate field in installation record: $key"

        seen["$key"]=1

        case "$key" in
            FORMAT_VERSION)
                [[ "$format" == "v2" && "$value" == "2" ]] ||
                    die "Unsupported installation record version."
                ;;

            WS_SCRIPT_OWNED|WS_CONFIG_OWNED|IPC_PATCH_OWNED|APP_PATCH_OWNED|APP_RULES_OWNED)
                case "$value" in
                    0|1) ;;
                    *) die "Invalid ownership value: $key" ;;
                esac

                printf -v "$key" '%s' "$value"
                ;;

            VIVARIUM_SOURCE_PATH_B64|VIVARIUM_RULES_DIR_B64)
                [[ "$format" == "v2" ]] ||
                    die "Unexpected version 2 field in legacy record."

                [[ "$value" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] ||
                    die "Invalid encoded path in installation record."

                decoded="$(printf '%s' "$value" | base64 --decode 2>/dev/null)" ||
                    die "Could not decode installation record path."

                [[ "$(printf '%s' "$decoded" | base64 --wrap=0)" == "$value" ]] ||
                    die "Non-canonical encoded path in installation record."

                [[ "$decoded" == /* ]] ||
                    die "Invalid directory path in installation record."

                if [[ "$key" == "VIVARIUM_SOURCE_PATH_B64" ]]; then
                    VIVARIUM_SOURCE_PATH="$decoded"
                else
                    VIVARIUM_RULES_DIR="$decoded"
                fi
                ;;

            VIVARIUM_SOURCE_PATH|VIVARIUM_RULES_DIR)
                [[ "$format" == "legacy" ]] ||
                    die "Unexpected legacy field in version 2 record."

                decode_legacy_path "$value" ||
                    die "Unsupported legacy path encoding: $key"

                [[ "$REPLY" == /* ]] ||
                    die "Invalid legacy directory path: $key"

                if [[ "$key" == "VIVARIUM_SOURCE_PATH" ]]; then
                    VIVARIUM_SOURCE_PATH="$REPLY"
                else
                    VIVARIUM_RULES_DIR="$REPLY"
                fi
                ;;

            *)
                die "Unknown field in installation record: $key"
                ;;
        esac

    done < "$STATE_FILE"

    if [[ "$format" == "v2" ]]; then
        [[ "${#seen[@]}" -eq 8 ]] ||
            die "Incomplete version 2 installation record."
    else
        [[ "${#seen[@]}" -eq 7 ]] ||
            die "Incomplete legacy installation record."
    fi

    [[ -n "$VIVARIUM_SOURCE_PATH" && -n "$VIVARIUM_RULES_DIR" ]] ||
        die "Installation record is missing directory paths."
}

# ----------------------------------------------------------
# USER SELECTION
# ----------------------------------------------------------

echo "Choose what you want to uninstall:"
echo
echo "  1) Workspace presentation (Waybar + IPC)"
echo "  2) Application workspace allocation"
echo "  3) Both features"
echo "  4) Quit"
echo

read -r -p "Enter your choice [1-4]: " CHOICE

case "$CHOICE" in
    1) REMOVE_WS=true; REMOVE_APP=false ;;
    2) REMOVE_WS=false; REMOVE_APP=true ;;
    3) REMOVE_WS=true; REMOVE_APP=true ;;
    4) echo "Uninstallation cancelled."; exit 0 ;;
    *) die "Invalid selection." ;;
esac
# ----------------------------------------------------------
# LOAD INSTALLATION STATE
# ----------------------------------------------------------

WS_SCRIPT_OWNED=0
WS_CONFIG_OWNED=0
IPC_PATCH_OWNED=0
APP_PATCH_OWNED=0
APP_RULES_OWNED=0

VIVARIUM_SOURCE_PATH=""
VIVARIUM_RULES_DIR=""

if [[ -e "$STATE_FILE" || -L "$STATE_FILE" ]]; then
    load_install_state
else
    die "No unified installation record was found. Nothing can be safely removed."
fi

# Check whether the selected features have recorded ownership.
if [[ "$REMOVE_WS" == true ]]; then
    if [[ "$WS_SCRIPT_OWNED" == 0 &&
          "$WS_CONFIG_OWNED" == 0 &&
          "$IPC_PATCH_OWNED" == 0 ]]; then
        die "No installer-owned workspace presentation components were found."
    fi
fi

if [[ "$REMOVE_APP" == true ]]; then
    if [[ "$APP_PATCH_OWNED" == 0 &&
          "$APP_RULES_OWNED" == 0 ]]; then
        die "No installer-owned application allocation components were found."
    fi
fi
# ----------------------------------------------------------
# VALIDATE RECORDED PATHS
# ----------------------------------------------------------

if [[ "$REMOVE_WS" == true && "$IPC_PATCH_OWNED" == 1 ]] ||
   [[ "$REMOVE_APP" == true && "$APP_PATCH_OWNED" == 1 ]]; then

    [[ -n "$VIVARIUM_SOURCE_PATH" ]] ||
        die "Vivarium source path is missing from the installation record."

    [[ -e "$VIVARIUM_SOURCE_PATH/.git" ]] ||
        die "The recorded Vivarium source is not a Git working tree."

    git -C "$VIVARIUM_SOURCE_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        die "The recorded Vivarium source is not a valid Git working tree."

    [[ -f "$VIVARIUM_SOURCE_PATH/src/viv_ipc.c" ]] ||
        die "Vivarium IPC source file was not found."

    VIVARIUM_SOURCE_PATH="$(cd "$VIVARIUM_SOURCE_PATH" && pwd -P)"
fi

if [[ "$REMOVE_APP" == true && "$APP_RULES_OWNED" == 1 ]]; then

    [[ -n "$VIVARIUM_RULES_DIR" ]] ||
        die "Application rules directory is missing from the installation record."

    [[ -d "$VIVARIUM_RULES_DIR" ]] ||
        die "The recorded application rules directory does not exist."

    VIVARIUM_RULES_DIR="$(cd "$VIVARIUM_RULES_DIR" && pwd -P)"
fi

# Verify the required patch files exist.
if [[ "$REMOVE_WS" == true && "$IPC_PATCH_OWNED" == 1 ]]; then
    [[ -f "$IPC_PATCH" ]] ||
        die "Workspace IPC patch is missing from the repository."
fi

if [[ "$REMOVE_APP" == true && "$APP_PATCH_OWNED" == 1 ]]; then
    [[ -f "$APP_PATCH" ]] ||
        die "Application allocation patch is missing from the repository."
fi
# ----------------------------------------------------------
# VERIFY INSTALLER-OWNED FILES
# ----------------------------------------------------------

if [[ "$REMOVE_WS" == true && "$WS_SCRIPT_OWNED" == 1 ]]; then
    [[ -f "$WAYBAR_SCRIPT_DIR/$WORKSPACE_SCRIPT" &&
       ! -L "$WAYBAR_SCRIPT_DIR/$WORKSPACE_SCRIPT" ]] ||
        die "The installer-owned Waybar script is missing or is no longer a regular file."
fi

if [[ "$REMOVE_WS" == true && "$WS_CONFIG_OWNED" == 1 ]]; then
    [[ -f "$WORKSPACE_CONFIG_DIR/$WORKSPACE_CONFIG" &&
       ! -L "$WORKSPACE_CONFIG_DIR/$WORKSPACE_CONFIG" ]] ||
        die "The installer-owned workspace configuration is missing or is no longer a regular file."
fi

if [[ "$REMOVE_APP" == true && "$APP_RULES_OWNED" == 1 ]]; then
    [[ -f "$VIVARIUM_RULES_DIR/$RULES_CONFIG" &&
       ! -L "$VIVARIUM_RULES_DIR/$RULES_CONFIG" ]] ||
        die "The installer-owned application rules file is missing or is no longer a regular file."
fi
# ----------------------------------------------------------
# CHECK PATCH REVERSIBILITY
# ----------------------------------------------------------

if [[ "$REMOVE_APP" == true && "$APP_PATCH_OWNED" == 1 ]]; then
    echo "Checking application allocation patch..."

    git -C "$VIVARIUM_SOURCE_PATH" apply \
        --reverse --check "$APP_PATCH" ||
        die "Application patch cannot be safely reversed. No changes have been made."
fi

if [[ "$REMOVE_WS" == true && "$IPC_PATCH_OWNED" == 1 ]]; then
    echo "Checking workspace IPC patch..."

    git -C "$VIVARIUM_SOURCE_PATH" apply \
        --reverse --check "$IPC_PATCH" ||
        die "Workspace IPC patch cannot be safely reversed. No changes have been made."
fi

echo "Patch reversibility checks passed."
# ----------------------------------------------------------
# DISPLAY REMOVAL PLAN
# ----------------------------------------------------------

echo
echo "The following installer-owned components are selected for removal:"
echo

if [[ "$REMOVE_WS" == true ]]; then
    [[ "$WS_SCRIPT_OWNED" == 1 ]] &&
        echo "  - Waybar workspace script"

    [[ "$WS_CONFIG_OWNED" == 1 ]] &&
        echo "  - Workspace configuration"

    [[ "$IPC_PATCH_OWNED" == 1 ]] &&
        echo "  - Vivarium workspace IPC patch"
fi

if [[ "$REMOVE_APP" == true ]]; then
    [[ "$APP_PATCH_OWNED" == 1 ]] &&
        echo "  - Application workspace allocation patch"

    [[ "$APP_RULES_OWNED" == 1 ]] &&
        echo "  - Application rules configuration"
fi

echo
# ----------------------------------------------------------
# DRY-RUN AND CONFIRMATION
# ----------------------------------------------------------

if [[ "$DRY_RUN" == true ]]; then
    echo "DRY RUN: No files or patches will be changed."
    echo
    echo "The uninstaller has completed its safety checks."
    echo "The components listed above would be removed."
    exit 0
fi

echo "No changes have been made yet."
echo
read -r -p "Proceed with this uninstallation? [y/N]: " CONFIRM

case "$CONFIRM" in
    y|Y|yes|YES)
        echo
        echo "Proceeding with uninstallation..."
        ;;
    *)
        echo
        echo "Uninstallation cancelled. No changes have been made."
        exit 0
        ;;
esac
# ----------------------------------------------------------
# PREPARE RECOVERY BACKUP
# ----------------------------------------------------------

BACKUP_DIR="$(mktemp -d "$STATE_DIR/uninstall-backup.XXXXXX")"

cp -a "$STATE_FILE" "$BACKUP_DIR/install-state.sh"

if [[ "$REMOVE_WS" == true && "$WS_SCRIPT_OWNED" == 1 ]]; then
    cp -a "$WAYBAR_SCRIPT_DIR/$WORKSPACE_SCRIPT" "$BACKUP_DIR/"
fi

if [[ "$REMOVE_WS" == true && "$WS_CONFIG_OWNED" == 1 ]]; then
    cp -a "$WORKSPACE_CONFIG_DIR/$WORKSPACE_CONFIG" "$BACKUP_DIR/"
fi

if [[ "$REMOVE_APP" == true && "$APP_RULES_OWNED" == 1 ]]; then
    cp -a "$VIVARIUM_RULES_DIR/$RULES_CONFIG" "$BACKUP_DIR/"
fi

echo
echo "Recovery backup created successfully."

# ----------------------------------------------------------
# ROLLBACK PROTECTION
# ----------------------------------------------------------

UNINSTALL_SUCCESS=false

REVERSED_IPC_PATCH=false
REVERSED_APP_PATCH=false

rollback_uninstall() {
    local EXIT_STATUS=$?
    local ROLLBACK_FAILED=0

    if [[ "$UNINSTALL_SUCCESS" == true ]]; then
        return
    fi

    echo
    echo "ERROR: Uninstallation did not complete."
    echo "Attempting to restore the previous installation..."

    set +e
    if [[ -n "${STATE_TMP:-}" && -e "$STATE_TMP" ]]; then
        if ! rm -f -- "$STATE_TMP"; then
            echo "WARNING: Could not remove temporary installation record."
            ROLLBACK_FAILED=1
        fi
    fi

    if [[ "$REVERSED_IPC_PATCH" == true ]]; then
        if ! git -C "$VIVARIUM_SOURCE_PATH" apply "$IPC_PATCH"; then
            echo "WARNING: Could not restore the workspace IPC patch."
            ROLLBACK_FAILED=1
        fi
    fi

    if [[ "$REVERSED_APP_PATCH" == true ]]; then
        if ! git -C "$VIVARIUM_SOURCE_PATH" apply "$APP_PATCH"; then
            echo "WARNING: Could not restore the application allocation patch."
            ROLLBACK_FAILED=1
        fi
    fi

if [[ -f "$BACKUP_DIR/$WORKSPACE_SCRIPT" ]]; then
        if ! cp -a "$BACKUP_DIR/$WORKSPACE_SCRIPT" \
            "$WAYBAR_SCRIPT_DIR/$WORKSPACE_SCRIPT"; then
            echo "WARNING: Could not restore the workspace script."
            ROLLBACK_FAILED=1
        fi
    fi

if [[ -f "$BACKUP_DIR/$WORKSPACE_CONFIG" ]]; then
        if ! cp -a "$BACKUP_DIR/$WORKSPACE_CONFIG" \
            "$WORKSPACE_CONFIG_DIR/$WORKSPACE_CONFIG"; then
            echo "WARNING: Could not restore the workspace configuration."
            ROLLBACK_FAILED=1
        fi
    fi

    if [[ -f "$BACKUP_DIR/$RULES_CONFIG" ]]; then
        if ! cp -a "$BACKUP_DIR/$RULES_CONFIG" \
            "$VIVARIUM_RULES_DIR/$RULES_CONFIG"; then
            echo "WARNING: Could not restore the application rules."
            ROLLBACK_FAILED=1
        fi
    fi

    if [[ -f "$BACKUP_DIR/install-state.sh" ]]; then
        if ! cp -a "$BACKUP_DIR/install-state.sh" "$STATE_FILE"; then
            echo "WARNING: Could not restore the installation state record."
            ROLLBACK_FAILED=1
        fi
    else
        echo "WARNING: Recovery copy of the installation state is missing."
        ROLLBACK_FAILED=1
    fi

    echo

    if [[ "$ROLLBACK_FAILED" == 0 ]]; then
        echo "Rollback completed successfully."
    else
        echo "WARNING: Rollback was incomplete."
        echo "The recovery backup has been preserved:"
        echo "$BACKUP_DIR"
    fi

    echo "Please inspect the installation before trying again."

    exit "$EXIT_STATUS"
}

trap rollback_uninstall EXIT
# ----------------------------------------------------------
# REMOVE APPLICATION ALLOCATION PATCH
# ----------------------------------------------------------

if [[ "$REMOVE_APP" == true && "$APP_PATCH_OWNED" == 1 ]]; then
    echo
    echo "Reversing application allocation patch..."

    git -C "$VIVARIUM_SOURCE_PATH" apply \
        --reverse "$APP_PATCH"

    REVERSED_APP_PATCH=true
    APP_PATCH_OWNED=0

    echo "Application allocation patch reversed successfully."
fi
# ----------------------------------------------------------
# REMOVE WORKSPACE IPC PATCH
# ----------------------------------------------------------

if [[ "$REMOVE_WS" == true && "$IPC_PATCH_OWNED" == 1 ]]; then
    echo
    echo "Reversing workspace IPC patch..."

    git -C "$VIVARIUM_SOURCE_PATH" apply \
        --reverse "$IPC_PATCH"

    REVERSED_IPC_PATCH=true
    IPC_PATCH_OWNED=0

    echo "Workspace IPC patch reversed successfully."
fi
# ----------------------------------------------------------
# REMOVE WORKSPACE PRESENTATION FILES
# ----------------------------------------------------------

if [[ "$REMOVE_WS" == true && "$WS_SCRIPT_OWNED" == 1 ]]; then
    echo
    echo "Removing Waybar workspace script..."

    rm -- "$WAYBAR_SCRIPT_DIR/$WORKSPACE_SCRIPT"
    WS_SCRIPT_OWNED=0

    echo "Waybar workspace script removed."
fi

if [[ "$REMOVE_WS" == true && "$WS_CONFIG_OWNED" == 1 ]]; then
    echo
    echo "Removing workspace configuration..."

    rm -- "$WORKSPACE_CONFIG_DIR/$WORKSPACE_CONFIG"
    WS_CONFIG_OWNED=0

    echo "Workspace configuration removed."
fi
# ----------------------------------------------------------
# REMOVE APPLICATION RULES CONFIGURATION
# ----------------------------------------------------------

if [[ "$REMOVE_APP" == true && "$APP_RULES_OWNED" == 1 ]]; then
    echo
    echo "Removing application rules configuration..."

    rm -- "$VIVARIUM_RULES_DIR/$RULES_CONFIG"
    APP_RULES_OWNED=0

    echo "Application rules configuration removed."
fi
# ----------------------------------------------------------
# UPDATE INSTALLATION STATE
# ----------------------------------------------------------

echo
echo "Updating installation record..."

if [[ "$WS_SCRIPT_OWNED" == 0 &&
      "$WS_CONFIG_OWNED" == 0 &&
      "$IPC_PATCH_OWNED" == 0 &&
      "$APP_PATCH_OWNED" == 0 &&
      "$APP_RULES_OWNED" == 0 ]]; then

    rm -- "$STATE_FILE"
    echo "All installer-owned components have been removed."
else
    STATE_TMP="$(mktemp "$STATE_DIR/install-state.XXXXXX")" ||
        die "Could not create a temporary installation record."

    {
        printf 'FORMAT_VERSION=2\n'
        printf 'WS_SCRIPT_OWNED=%s\n' "$WS_SCRIPT_OWNED"
        printf 'WS_CONFIG_OWNED=%s\n' "$WS_CONFIG_OWNED"
        printf 'IPC_PATCH_OWNED=%s\n' "$IPC_PATCH_OWNED"
        printf 'APP_PATCH_OWNED=%s\n' "$APP_PATCH_OWNED"
        printf 'APP_RULES_OWNED=%s\n' "$APP_RULES_OWNED"
        printf 'VIVARIUM_SOURCE_PATH_B64=%s\n' \
            "$(printf '%s' "$VIVARIUM_SOURCE_PATH" | base64 --wrap=0)"
        printf 'VIVARIUM_RULES_DIR_B64=%s\n' \
            "$(printf '%s' "$VIVARIUM_RULES_DIR" | base64 --wrap=0)"
    } > "$STATE_TMP" || {
        rm -f -- "$STATE_TMP"
        die "Could not write the installation state record."
    }

    chmod 600 "$STATE_TMP" ||
        die "Could not secure the installation state record."

    mv -f -- "$STATE_TMP" "$STATE_FILE" ||
        die "Could not save the installation state record."

    echo "Remaining installation components have been recorded."
fi

# Mark completion before cleaning up the recovery backup.
UNINSTALL_SUCCESS=true

rm -rf -- "$BACKUP_DIR" ||
    echo "WARNING: Could not remove temporary recovery backup: $BACKUP_DIR"

# ----------------------------------------------------------
# FINAL COMPLETION REPORT
# ----------------------------------------------------------

echo
echo "=========================================="
echo "       UNINSTALLATION COMPLETE"
echo "=========================================="
echo

if [[ "$REVERSED_IPC_PATCH" == true ||
      "$REVERSED_APP_PATCH" == true ]]; then
    echo "Vivarium source patches were reversed."
    echo "Rebuild Vivarium and restart the compositor"
    echo "to apply the source changes."
    echo
fi

if [[ "$REMOVE_WS" == true ]]; then
    echo "Workspace presentation removal was selected."
    echo "Review your Waybar configuration, remove any"
    echo "references to the removed custom modules, and"
    echo "reload Waybar if necessary."
    echo
fi

if [[ "$REMOVE_APP" == true ]]; then
    echo "Application workspace allocation was removed."
    echo
fi

echo "Only installer-owned components were removed."
echo "Other files and manually maintained changes were preserved."
echo
