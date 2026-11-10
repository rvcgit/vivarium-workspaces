# Vivarium Workspaces

A customizable 9-workspace integration for *Vivarium + Waybar*.

Vivarium Workspaces provides nine individual, clickable Waybar modules. Each workspace can display its own name, Nerd Font icon, custom label, and state colour.

## Features

- Nine independent workspace modules.
- Active, occupied, and empty workspace indicators.
- Four display modes: number, name, icon, and custom.
- Optional icon-only display.
- Individual workspace names and Nerd Font icons.
- Custom colours for active, occupied, and empty workspaces.
- Clickable workspace switching through Waybar.
- Lightweight Bash script.
- Configurable without editing the script.
- Installer and uninstaller included.
- Small Vivarium IPC patch for workspace state reporting.
- Application workspace allocation using configurable window rules.
- Each feature can be installed independently, or both can be installed together.

## How It Works

Vivarium writes workspace information to:
```
/tmp/vivarium-workspaces.txt
```

The workspace script reads this file and generates JSON output for each individual Waybar module.

Each module displays one workspace and uses its state to determine the display colour.

The integration uses a small patch to Vivarium's IPC code to report workspace occupancy and active workspace state.

## Requirements

- Linux system running Vivarium.
- Bash.
- Git (required by the installer for patch management).
- Vivarium source code (required for applying the supplied patches).
- Waybar for workspace presentation.
- ydotool for click-based workspace switching (workspace presentation only)
- A Nerd Font (for example, `JetBrainsMono Nerd Font`) if you want to use the workspace icons.

## Installation

Clone the repository:

```bash
git clone https://github.com/rvcgit/vivarium-workspaces.git
cd vivarium-workspaces
chmod +x install.sh
./install.sh
```
The installer offers four choices:

1. Workspace presentation (Waybar + IPC).
2. Application workspace allocation.
3. Both features.
4. Quit without installing anything.

**Installation Paths**

The installer asks for the Vivarium source directory.

The default is:

`~/viv_src`

Select the Git working tree containing your Vivarium source code.

When application workspace allocation is selected, the installer also asks for the Vivarium configuration directory.

The default is:

`~/.config/viv_src`

Select the directory containing your active Vivarium configuration. The application rules file, `window_rules.conf`, is installed in this directory.

**Installation Safety**

The installer checks for existing components before making changes.

- Existing workspace scripts and configuration files are preserved.
- Existing Vivarium patches are detected and left unchanged rather than applied again.
- Existing application rules are preserved.
- The installer records ownership of newly installed components in:

  `~/.local/share/vivarium-workspaces/install-state.sh`

The ownership record allows the uninstaller to distinguish components installed by this project from components that were already present.

The installer displays its planned actions and requests confirmation before proceeding.

### Dry Run

Both scripts support a dry-run mode to inspect planned actions without modifying files or applying or reversing patches.

To preview installation:

```bash
./install.sh --dry-run
```

To preview uninstallation:
```bash
./uninstall.sh --dry-run
```

Dry run mode does not make any changes to your existing setup or installation.

## Manual IPC Patch Application (Alternative)

The unified installer normally handles the Vivarium IPC patch automatically when workspace presentation is selected.

The following instructions are provided for users who prefer to apply the patch manually.

First, enter your Vivarium source directory:


```bash
cd path/TO/vivarium
```

Check whether the patch can be applied:

```bash
git apply --check /path/to/vivarium-workspaces/patches/vivarium-ipc.patch
```

If the check succeeds, apply the patch:

```bash
git apply /path/to/vivarium-workspaces/patches/vivarium-ipc.patch
```

Replace `/path/to/` with the actual location of your cloned repository.

**Important:** The patch was prepared against the upstream Vivarium revision `1ffa436`. Other revisions may require adjustments.

## Vivarium IPC Configuration

After applying the IPC patch, configure Vivarium to write workspace information to the IPC file.

Open your active Vivarium configuration file, normally:

`~/.config/vivarium/config.toml`

Add the following section:

```toml
[ipc]
workspaces-filename = "/tmp/vivarium-workspaces.txt"
```

If an `[ipc]` section already exists, add the `workspaces-filename` setting under it rather than creating a duplicate section.

This tells Vivarium where to write workspace information for the Waybar workspace modules.

## Application Workspace Allocation

Vivarium Workspaces includes an independent application workspace allocation feature.

It allows newly opened applications to be assigned automatically to designated workspaces using configurable application identifiers.

This feature does not require Waybar or the workspace presentation feature.

### Configuration

The rules file is:

`window_rules.conf`

It is installed in the same directory as your active Vivarium `config.toml`.

The default location is:

`~/.config/viv_src/window_rules.conf`

A sample configuration is provided at:

`ws_allocate/config/window_rules.conf.example`

### Rule Syntax

Each rule maps an application identifier to a workspace number.

```text
application_id = workspace_number
```
Example:
```text
firefox = 1
Gedit   = 2
```
**Identifiers are case-sensitive.**

- Native Wayland applications use their XDG `app_id`.
- XWayland applications use the second string returned by `xprop WM_CLASS`.

For XWayland applications, the second value returned by `xprop WM_CLASS` is normally the required identifier.

**Behaviour**

- New independent top-level windows are matched against configured rules.
- Matching applications are assigned to their designated workspaces.
- The currently active workspace is not automatically changed.
- Unmatched applications retain normal Vivarium placement behaviour.
- Child windows and transient dialogs are excluded from application workspae allocation (for example, the welcome popup in GIMP).
- Explicit fullscreen-output requests take priority.
- Invalid rules are reported and skipped.
- Changing rules does not move existing windows.

**For further details, see:**

`ws_allocate/README.md`

## Waybar Integration

The repository includes:

- `waybar/config.example`
- `waybar/style.css`

Use the example configuration as a reference. Merge the nine workspace modules into your existing Waybar configuration.

Do not replace your entire Waybar configuration.

Each module calls the workspace script with its workspace number (1-9).

The modules use ydotool for click-based workspace switching. Ensure it is installed and configured before using this feature.

Add the supplied CSS rules to your existing Waybar stylesheet. Adjust spacing,padding and module width as needed.

Restart Waybar after making the changes.

## Workspace Customization

Edit the configuration file:

`~/.config/vivarium/workspaces.conf`

### Display Modes

| Mode | Description |
|---|---|
| `number` | Displays workspace numbers |
| `name` | Displays workspace names |
| `icon` | Displays workspace icons |
| `custom` | Displays custom labels |

Set the desired mode:

```bash
WS_DISPLAY_MODE="custom"
```

Enable icon-only display:

```bash
WS_ICON_ONLY=true
```

Set it to `false` to use the selected display mode.

You can customize workspace names, icons, labels, and colours in this configuration file without modifying the Bash script.

## Workspace States

The IPC output uses the following markers:

- `<number>` - Active workspace.
- `number*` - Occupied workspace.
- `<number>*` - Active and occupied workspace.
- `number` - Empty workspace.

The active workspace takes priority when a workspace is both active and occupied.

## Uninstallation

Run the unified uninstaller from the repository directory:
```bash
./uninstall.sh
```
**The Uninstaller offers four choices**

1. Workspace presentation (Waybar + IPC).
2. Application workspace allocation.
3. Both features.
4. Quit without uninstalling.

**Uninstallation Safety**

The uninstaller uses the installation ownership record to identify components installed by this project.
- Only installer-owned files and patches selected for removal are removed.
- Pre-existing files and patches are preserved.
- Removing one feature does not remove the other.
- The installation record is updated when only one feature is removed.
- The record is removed when all installer-owned components have been uninstalled.

The uninstaller checks whether owned patches can be safely reversed before proceeding.

It also creates temporary recovery backups during the removal process.

## Dry Run

To inspect planned removal actions without making changes:
```bash
./uninstall.sh --dry-run
```

## After Uninstallation

If a Vivarium source patch was reversed, rebuild and install Vivarium using your normal build procedure, then restart the compositor.

If the workspace presentation was removed, manually remove the corresponding workspace modules and CSS rules from your Waybar configuration if they are no longer needed.

## Project Structure
```text
vivarium-workspaces/
|-- config/
|   |-- workspaces.conf
|-- patches/
|   |-- vivarium-ipc.patch
|-- scripts/
|   |-- vivarium-workspace-item.sh
|-- Screenshots/
|   |-- vivarium-waybar.png
|   |-- vivarium-workspace.png
|-- waybar/
|   |-- config.example
|   |-- style.css
|-- ws_allocate/
|   |-- config/
|   |   |-- window_rules.conf.example
|   |-- patches/
|   |   |-- application-workspace-rules.patch
|   |-- README.md
|-- install.sh
|-- uninstall.sh
|-- LICENSE
|-- README.md
```

## Contributions

Suggestions, improvements, bug reports, and contributions are welcome.

Feel free to fork the repository and adapt the integration to your setup.

## License

This project is distributed under the GNU General Public License v3.0 (GPL-3.0).

See the `LICENSE` file for details.
