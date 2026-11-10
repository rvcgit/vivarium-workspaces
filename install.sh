#!/usr/bin/env bash

# ==========================================================
# VIVARIUM WORKSPACES — UNIFIED INSTALLER
# ==========================================================

set -Eeuo pipefail
# Optional dry-run mode: inspect planned changes without modifying anything.
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

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WAYBAR_SCRIPT_DIR="$HOME/.config/waybar/scripts"
WORKSPACE_CONFIG_DIR="$HOME/.config/vivarium"
STATE_DIR="$HOME/.local/share/vivarium-workspaces"

WORKSPACE_SCRIPT="vivarium-workspace-item.sh"
WORKSPACE_CONFIG="workspaces.conf"
RULES_CONFIG="window_rules.conf"

IPC_PATCH="$REPO_DIR/patches/vivarium-ipc.patch"
APP_PATCH="$REPO_DIR/ws_allocate/patches/application-workspace-rules.patch"

echo
echo "=========================================="
echo "       VIVARIUM WORKSPACES"
echo "          Unified Installer"
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
# DETECTION FUNCTIONS
# ----------------------------------------------------------

has_workspace_script() {
    [[ -x "$WAYBAR_SCRIPT_DIR/$WORKSPACE_SCRIPT" ]]
}

has_workspace_config() {
    [[ -f "$WORKSPACE_CONFIG_DIR/$WORKSPACE_CONFIG" ]]
}

has_ipc_patch() {
    grep -q 'workspace_occupancy_signature' \
        "$VIVARIUM_SRC/src/viv_ipc.c" 2>/dev/null &&
    grep -q 'have_last_occupancy_signature' \
        "$VIVARIUM_SRC/src/viv_ipc.c" 2>/dev/null
}

has_app_patch() {
    git -C "$VIVARIUM_SRC" apply --reverse --check \
        "$APP_PATCH" >/dev/null 2>&1
}

has_app_rules() {
    [[ -f "$VIVARIUM_CONFIG_DIR/$RULES_CONFIG" ]]
}
# ----------------------------------------------------------
# USER SELECTION
# ----------------------------------------------------------

echo "Choose what you want to install:"
echo
echo "  1) Workspace presentation (Waybar + IPC)"
echo "  2) Application workspace allocation"
echo "  3) Both features"
echo "  4) Quit"
echo

read -r -p "Enter your choice [1-4]: " CHOICE

case "$CHOICE" in
    1) INSTALL_WS=true; INSTALL_APP=false ;;
    2) INSTALL_WS=false; INSTALL_APP=true ;;
    3) INSTALL_WS=true; INSTALL_APP=true ;;
    4) echo "Installation cancelled."; exit 0 ;;
    *) die "Invalid selection." ;;
esac

# ----------------------------------------------------------
# VIVARIUM SOURCE AND CONFIGURATION
# ----------------------------------------------------------

read -r -p "Vivarium source directory [$HOME/viv_src]: " VIVARIUM_SRC
VIVARIUM_SRC="${VIVARIUM_SRC:-$HOME/viv_src}"

[[ -e "$VIVARIUM_SRC/.git" ]] ||
    die "The selected directory is not a Git working tree."

[[ -f "$VIVARIUM_SRC/src/viv_ipc.c" ]] ||
    die "Vivarium IPC source file was not found."
    VIVARIUM_SRC="$(cd "$VIVARIUM_SRC" && pwd -P)"

VIVARIUM_CONFIG_DIR="$HOME/.config/viv_src"

if [[ "$INSTALL_APP" == true ]]; then
    read -r -p "Vivarium configuration directory [$VIVARIUM_CONFIG_DIR]: " INPUT_CONFIG_DIR
    VIVARIUM_CONFIG_DIR="${INPUT_CONFIG_DIR:-$VIVARIUM_CONFIG_DIR}"

    [[ -d "$VIVARIUM_CONFIG_DIR" ]] ||
        die "The selected Vivarium configuration directory does not exist."
        VIVARIUM_CONFIG_DIR="$(cd "$VIVARIUM_CONFIG_DIR" && pwd -P)"
fi
# ----------------------------------------------------------
# INSTALLATION STATE
# ----------------------------------------------------------

STATE_FILE="$STATE_DIR/install-state.sh"

WS_SCRIPT_OWNED=0
WS_CONFIG_OWNED=0
IPC_PATCH_OWNED=0
APP_PATCH_OWNED=0
APP_RULES_OWNED=0

if [[ -e "$STATE_FILE" || -L "$STATE_FILE" ]]; then
    load_install_state
fi

# Preserve the previously recorded rules directory when
# application allocation is not part of this installation.
VIVARIUM_RULES_DIR="${VIVARIUM_RULES_DIR:-$VIVARIUM_CONFIG_DIR}"

# Update the recorded directory only when application
# allocation is selected.
if [[ "$INSTALL_APP" == true ]]; then
    VIVARIUM_RULES_DIR="$VIVARIUM_CONFIG_DIR"
fi

# Refuse to reuse ownership records for a different Vivarium source tree.
if [[ "$IPC_PATCH_OWNED" == 1 || "$APP_PATCH_OWNED" == 1 ]]; then
    [[ "${VIVARIUM_SOURCE_PATH:-}" == "$VIVARIUM_SRC" ]] ||
        die "The Vivarium source path differs from the previous installation record."
fi

# Refuse to reuse application-rule ownership for a different config directory.
if [[ "$INSTALL_APP" == true && "$APP_RULES_OWNED" == 1 ]]; then
    [[ "${VIVARIUM_RULES_DIR:-}" == "$VIVARIUM_CONFIG_DIR" ]] ||
        die "The Vivarium configuration path differs from the previous installation record."
fi

# ----------------------------------------------------------
# INSTALLATION CHECKS
# ----------------------------------------------------------

echo
echo "Checking existing installation..."
echo

WS_SCRIPT_OK=false
WS_CONFIG_OK=false
IPC_OK=false
APP_PATCH_OK=false
APP_RULES_OK=false

has_workspace_script && WS_SCRIPT_OK=true
has_workspace_config && WS_CONFIG_OK=true

if [[ "$INSTALL_WS" == true ]]; then
    has_ipc_patch && IPC_OK=true
fi

if [[ "$INSTALL_APP" == true ]]; then
    has_app_patch && APP_PATCH_OK=true
    has_app_rules && APP_RULES_OK=true
fi

if [[ "$INSTALL_WS" == true ]]; then
    echo "Workspace script:       $WS_SCRIPT_OK"
    echo "Workspace configuration: $WS_CONFIG_OK"
    echo "IPC implementation:      $IPC_OK"
fi

if [[ "$INSTALL_APP" == true ]]; then
    echo "Application patch:       $APP_PATCH_OK"
    echo "Application rules:       $APP_RULES_OK"
fi

echo

# ----------------------------------------------------------
# REQUIRED FILE CHECKS
# ----------------------------------------------------------

if [[ "$INSTALL_WS" == true ]]; then
    [[ -f "$REPO_DIR/scripts/$WORKSPACE_SCRIPT" ]] ||
        die "Workspace script is missing from the repository."

    [[ -f "$REPO_DIR/config/$WORKSPACE_CONFIG" ]] ||
        die "Workspace configuration is missing from the repository."

    [[ -f "$IPC_PATCH" ]] ||
        die "Workspace IPC patch is missing."
fi

if [[ "$INSTALL_APP" == true ]]; then
    [[ -f "$APP_PATCH" ]] ||
        die "Application allocation patch is missing."

    [[ -f "$REPO_DIR/ws_allocate/config/window_rules.conf.example" ]] ||
        die "Application rules example is missing."
fi

echo "All required project files are present."
echo

# ----------------------------------------------------------
# SAFE INSTALLATION AND ROLLBACK
# ----------------------------------------------------------

CHANGED=false
PATCH_CHANGED=false

NEW_WS_SCRIPT=0
NEW_WS_CONFIG=0
NEW_IPC_PATCH=0
NEW_APP_PATCH=0
NEW_APP_RULES=0

ROLLBACK_ACTIVE=true

rollback_on_exit() {
    local status=$?

    if [[ "$status" -ne 0 && "$ROLLBACK_ACTIVE" == true ]]; then
        echo
        echo "Installation failed. Rolling back new changes..."

        set +e
        local ROLLBACK_FAILED=0

        if [[ "$NEW_APP_PATCH" == 1 ]]; then
            if git -C "$VIVARIUM_SRC" apply --reverse "$APP_PATCH"; then
                echo "  Reversed application allocation patch."
            else
                echo "  WARNING: Could not reverse application allocation patch."
                ROLLBACK_FAILED=1
            fi
        fi
        if [[ "$NEW_IPC_PATCH" == 1 ]]; then
            if git -C "$VIVARIUM_SRC" apply --reverse "$IPC_PATCH"; then
                echo "  Reversed workspace IPC patch."
            else
                echo "  WARNING: Could not reverse workspace IPC patch."
                ROLLBACK_FAILED=1
            fi
        fi
        if [[ "$NEW_APP_RULES" == 1 ]]; then
            if rm -f "$VIVARIUM_CONFIG_DIR/$RULES_CONFIG"; then
                echo "  Removed application rules file."
            else
                echo "  WARNING: Could not remove application rules file."
                ROLLBACK_FAILED=1
            fi
        fi
        if [[ "$NEW_WS_CONFIG" == 1 ]]; then
            if rm -f "$WORKSPACE_CONFIG_DIR/$WORKSPACE_CONFIG"; then
                echo "  Removed workspace configuration."
            else
                echo "  WARNING: Could not remove workspace configuration."
                ROLLBACK_FAILED=1
            fi
        fi
        if [[ "$NEW_WS_SCRIPT" == 1 ]]; then
            if rm -f "$WAYBAR_SCRIPT_DIR/$WORKSPACE_SCRIPT"; then
                echo "  Removed workspace script."
            else
                echo "  WARNING: Could not remove workspace script."
                ROLLBACK_FAILED=1
            fi
        fi
if [[ -n "${STATE_TMP:-}" && -e "$STATE_TMP" ]]; then
    if rm -f -- "$STATE_TMP"; then
        echo "  Removed temporary installation record."
    else
        echo "  WARNING: Could not remove temporary installation record."
        ROLLBACK_FAILED=1
    fi
fi

        if [[ "$ROLLBACK_FAILED" == 0 ]]; then
            echo "Rollback completed successfully."
        else
            echo "WARNING: Rollback was incomplete. Manual inspection is required."
        fi

        echo "Please inspect the original installation error above."
    fi

    return "$status"
}

trap rollback_on_exit EXIT

# Refuse to overwrite unexpected existing files.

if [[ "$INSTALL_WS" == true ]]; then
    if [[ -e "$WAYBAR_SCRIPT_DIR/$WORKSPACE_SCRIPT" &&
          "$WS_SCRIPT_OK" == false ]]; then
        die "Workspace script exists but is not executable. Refusing to overwrite."
    fi

    if [[ -e "$WORKSPACE_CONFIG_DIR/$WORKSPACE_CONFIG" &&
          "$WS_CONFIG_OK" == false ]]; then
        die "Workspace configuration exists but is not a regular file."
    fi
fi

if [[ "$INSTALL_APP" == true &&
      -e "$VIVARIUM_CONFIG_DIR/$RULES_CONFIG" &&
      "$APP_RULES_OK" == false ]]; then
    die "Application rules path exists but is not a regular file."
fi

# Check patch compatibility before making any changes.
if [[ "$INSTALL_WS" == true && "$IPC_OK" == false ]]; then
    git -C "$VIVARIUM_SRC" apply --check "$IPC_PATCH" ||
        die "IPC patch is incompatible with this source tree."
fi

if [[ "$INSTALL_APP" == true && "$APP_PATCH_OK" == false ]]; then
    git -C "$VIVARIUM_SRC" apply --check "$APP_PATCH" ||
        die "Application patch is incompatible with this source tree."
fi

# ----------------------------------------------------------
# DRY-RUN REPORT — NO FILES OR PATCHES ARE MODIFIED
# ----------------------------------------------------------

if [[ "$DRY_RUN" == true ]]; then
    echo
    echo "=========================================="
    echo "          DRY RUN — PREVIEW"
    echo "=========================================="
    echo

    if [[ "$INSTALL_WS" == true ]]; then
        echo "Workspace presentation:"

        [[ "$WS_SCRIPT_OK" == true ]] &&
            echo "  Already installed: workspace script" ||
            echo "  Would install: workspace script"

        [[ "$WS_CONFIG_OK" == true ]] &&
            echo "  Already installed: workspace configuration" ||
            echo "  Would install: workspace configuration"

        [[ "$IPC_OK" == true ]] &&
            echo "  Already installed: IPC patch" ||
            echo "  Would apply: IPC patch"
    fi

    if [[ "$INSTALL_APP" == true ]]; then
        echo
        echo "Application workspace allocation:"

        [[ "$APP_PATCH_OK" == true ]] &&
            echo "  Already installed: application patch" ||
            echo "  Would apply: application patch"

        [[ "$APP_RULES_OK" == true ]] &&
            echo "  Already installed: application rules" ||
            echo "  Would install: application rules"
    fi

    echo
    echo "Dry run complete. No files, patches or state records were changed."
    read -r -p "Press Enter to exit..."
    exit 0
fi

# ----------------------------------------------------------
# INSTALLATION CONFIRMATION
# ----------------------------------------------------------

echo
echo "=========================================="
echo "       INSTALLATION CONFIRMATION"
echo "=========================================="
echo

if [[ "$INSTALL_WS" == true ]]; then
    echo "Workspace presentation:"

    [[ "$WS_SCRIPT_OK" == true ]] &&
        echo "  Already present: workspace script" ||
        echo "  Will install: workspace script"

    [[ "$WS_CONFIG_OK" == true ]] &&
        echo "  Already present: workspace configuration" ||
        echo "  Will install: workspace configuration"

    [[ "$IPC_OK" == true ]] &&
        echo "  Already present: IPC patch" ||
        echo "  Will apply: IPC patch"
fi

if [[ "$INSTALL_APP" == true ]]; then
    echo
    echo "Application workspace allocation:"

    [[ "$APP_PATCH_OK" == true ]] &&
        echo "  Already present: application patch" ||
        echo "  Will apply: application patch"

    [[ "$APP_RULES_OK" == true ]] &&
        echo "  Already present: application rules" ||
        echo "  Will install: application rules"
fi

echo

while true; do
    read -r -p "Proceed with installation? [Y/n]: " CONFIRM

    case "${CONFIRM,,}" in
        ""|y|yes)
            echo
            echo "Confirmation received. Proceeding..."
            break
            ;;
        n|no)
            echo
            echo "Installation cancelled. No changes were made."
            exit 0
            ;;
        *)
            echo "Please answer Y or n."
            ;;
    esac
done
# ----------------------------------------------------------
# APPLY REQUIRED CHANGES
# ----------------------------------------------------------

if [[ "$INSTALL_WS" == true ]]; then

    if [[ "$WS_SCRIPT_OK" == false ]]; then
        mkdir -p "$WAYBAR_SCRIPT_DIR"
        NEW_WS_SCRIPT=1

        install -m 755 \
            "$REPO_DIR/scripts/$WORKSPACE_SCRIPT" \
            "$WAYBAR_SCRIPT_DIR/$WORKSPACE_SCRIPT"

        WS_SCRIPT_OWNED=1
        CHANGED=true
        echo "Installed workspace script."
    fi

    if [[ "$WS_CONFIG_OK" == false ]]; then
        mkdir -p "$WORKSPACE_CONFIG_DIR"
        NEW_WS_CONFIG=1

        install -m 644 \
            "$REPO_DIR/config/$WORKSPACE_CONFIG" \
            "$WORKSPACE_CONFIG_DIR/$WORKSPACE_CONFIG"

        WS_CONFIG_OWNED=1
        CHANGED=true
        echo "Installed workspace configuration."
    fi

    if [[ "$IPC_OK" == false ]]; then
        git -C "$VIVARIUM_SRC" apply --check "$IPC_PATCH" ||
            die "IPC patch is incompatible with this source tree."

        git -C "$VIVARIUM_SRC" apply "$IPC_PATCH" ||
            die "Could not apply IPC patch."

        NEW_IPC_PATCH=1
        IPC_PATCH_OWNED=1
        CHANGED=true
        PATCH_CHANGED=true

        echo "Applied workspace IPC patch."
    fi
fi

if [[ "$INSTALL_APP" == true ]]; then

    if [[ "$APP_PATCH_OK" == false ]]; then
        git -C "$VIVARIUM_SRC" apply --check "$APP_PATCH" ||
            die "Application patch is incompatible with this source tree."

        git -C "$VIVARIUM_SRC" apply "$APP_PATCH" ||
            die "Could not apply application allocation patch."

        NEW_APP_PATCH=1
        APP_PATCH_OWNED=1
        CHANGED=true
        PATCH_CHANGED=true

        echo "Applied application allocation patch."
    fi

    if [[ "$APP_RULES_OK" == false ]]; then
        NEW_APP_RULES=1

        install -m 644 \
            "$REPO_DIR/ws_allocate/config/window_rules.conf.example" \
            "$VIVARIUM_CONFIG_DIR/$RULES_CONFIG"

        APP_RULES_OWNED=1
        CHANGED=true

        echo "Installed application rules example."
    fi
fi

# ----------------------------------------------------------
# SAVE INSTALLATION RECORD
# ----------------------------------------------------------

if [[ "$CHANGED" == true ]]; then
    mkdir -p "$STATE_DIR"

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
            "$(printf '%s' "$VIVARIUM_SRC" | base64 --wrap=0)"
        printf 'VIVARIUM_RULES_DIR_B64=%s\n' \
            "$(printf '%s' "$VIVARIUM_RULES_DIR" | base64 --wrap=0)"
    } > "$STATE_TMP" || {
        rm -f -- "$STATE_TMP"
        die "Could not write the installation state record."
    }

    mv -f -- "$STATE_TMP" "$STATE_FILE" || {
        rm -f -- "$STATE_TMP"
        die "Could not save the installation state record."
    }
fi

# Installation is now committed.
ROLLBACK_ACTIVE=false
trap - EXIT

# ----------------------------------------------------------
# FINAL REPORT
# ----------------------------------------------------------

echo
echo "=========================================="

if [[ "$CHANGED" == false ]]; then
    echo "Selected features are already installed."
    echo "No changes were necessary."
else
    echo "Installation completed successfully."
fi

echo "=========================================="

if [[ "$PATCH_CHANGED" == true ]]; then
    echo
    echo "IMPORTANT:"
    echo "Rebuild Vivarium before using the patched features."
    echo "Restart Vivarium after rebuilding."
fi

echo
echo "Installation process finished."
echo
