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
- Waybar.
- Bash.
- ydotool for clickable workspace switching.
- A Nerd Font if you want to use workspace icons.
- Git.
- Vivarium source code for applying the IPC patch.

## Installation

Clone the repository:

```bash
git clone https://github.com/rvcgit/vivarium-workspaces.git
cd vivarium-workspaces
```

Make the installer executable and run it:

```bash
chmod +x install.sh
./install.sh
```

The installer:

- Installs the workspace script.
- Installs the default workspace configuration if one does not already exist.
- Backs up existing workspace files before installation.
- Preserves an existing workspace configuration.

Backups are stored in:

```~/.local/share/vivarium-workspaces/backup/
```
*Note:* The installer does not modify your Vivarium source, Waybar configuration, CSS, or IPC settings. These steps are performed separately.

## Vivarium IPC Configuration

Open your Vivarium configuration file:

`~/.config/vivarium/config.toml`

Add the following section:

```toml
[ipc]
workspaces-filename = "/tmp/vivarium-workspaces.txt"
```

This tells Vivarium where to write workspace information.

## Applying the Vivarium IPC Patch

The supplied patch modifies Vivarium's IPC code to report workspace occupancy.

First, enter your Vivarium source directory:


```bash
cd PATH/TO/vivarium
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

## Waybar Integration

The repository includes:

- `waybar/config.example`
- `waybar/style.css`

Use the example configuration as a reference. Merge the nine workspace modules into your existing Waybar configuration.

Do not replace your entire Waybar configuration.

Each module calls the workspace script with its workspace number (1-9).

The modules use `ydotool` to switch workspaces when clicked.

Add the supplied CSS rules to your existing Waybar stylesheet to control spacing, padding, and module width.

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

- `<name>` - Active workspace.
- `name*` - Occupied workspace.
- `<name>*` - Active and occupied workspace.
- `name` - Empty workspace.

The active workspace takes priority over the occupied state.

## Uninstallation

To uninstall the integration, enter the repository directory and run:

```bash
./uninstall.sh
```

The uninstaller restores previously backed-up workspace files when available.

If no previous workspace configuration backup exists, the current configuration is preserved.

The uninstaller does not modify Waybar modules, CSS, or Vivarium IPC settings. Remove these manually if you no longer need them.

Backups are retained at:

`~/.local/share/vivarium-workspaces/backup/`

## Project Structure

```text
vivarium-workspaces/
|-- config/
|   |-- workspaces.conf
|-- patches/
|   |-- vivarium-ipc.patch
|-- scripts/
|   |-- vivarium-workspace-item.sh
|-- waybar/
|   |-- config.example
|   |-- style.css
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
