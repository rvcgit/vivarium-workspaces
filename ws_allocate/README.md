# Vivarium Application Workspace Allocation

Automatically place newly opened applications on their assigned Vivarium workspaces.

This feature uses application identifiers to determine where a new window should appear.

It works independently of the Vivarium workspace presentation and Waybar integration.

No particular status bar is required.

The feature is part of the Vivarium Workspaces project.

## How It Works

Vivarium checks the application identifier when a new independent top-level window is opened.

If a matching rule exists, the window is assigned to the configured workspace.

The window is placed there without automatically switching the currently active workspace.

Windows without a matching rule follow Vivarium's normal placement behaviour.

Existing windows are not moved when rules are changed.

## Application Identifiers

The identifier depends on the application backend.

- Native Wayland applications use their XDG `app_id`.
- XWayland applications use their window class.

For XWayland applications, the second value returned
by `xprop WM_CLASS` is normally the required class.

Identifiers are case-sensitive.

Use the exact identifier reported by the application,
not necessarily its desktop menu name.

## Configuration

The rules are stored in:

`window_rules.conf`

Place this file in the same directory as the
active Vivarium `config.toml`.

For example:

`~/.config/vivarium/window_rules.conf`

When Vivarium is started with a custom configuration path, place the rules file beside that configuration.

## Rule Syntax

Each rule maps an application identifier to a workspace number.

The format is:

`application_id = workspace_number`

Example:

`firefox = 1`

Blank lines and comments beginning with `#` are
allowed.

Workspace numbers must refer to configured Vivarium workspaces. Supported numbers are 1 to 50.

## Example Assignments

The following example uses nine workspaces:

| Workspace | Purpose |
|---|---|
| 1 | WEB |
| 2 | CODE |
| 3 | TERM |
| 4 | DOCS |
| 5 | MEDIA |
| 6 | FILES |
| 7 | CHAT |
| 8 | LAB |
| 9 | MISC |

Applications can share the same workspace.

## Example Rules

A sample configuration is provided at:

`config/window_rules.conf.example`

It includes application identifiers for browsers, editors, terminals, office applications, file managers and image utilities.

Copy the example to `window_rules.conf` beside your active Vivarium `config.toml`.

Edit the identifiers and workspace numbers to suit your own applications and workspace arrangement.

## Finding Application Identifiers

For XWayland applications, use:

`xprop WM_CLASS`

Click the application window when the crosshair appears. The second WM_CLASS string is normally the identifier required by the rules file.

For native Wayland applications, use the application's XDG app_id.

The identifier must match exactly, including capitalisation.

## Installation and Activation

The application-allocation patch targets Vivarium upstream commit `1ffa436`.

Use a compatible Vivarium source version before applying the patch.

Rebuild and install Vivarium using your normal build and installation procedure.

Place `window_rules.conf` beside the active `config.toml`.

Restart Vivarium to load the rules.

Changes to the rules file require a Vivarium restart to take effect.

## Behaviour and Limitations

- Only independent top-level windows are matched.
- Transient child windows and dialogs are excluded.
- Explicit fullscreen-output requests take priority.
- Unmatched applications retain normal placement.
- Invalid rules are reported and skipped.
- A missing rules file does not prevent Vivarium
  from starting.
- Changing rules does not relocate existing windows.

## Project Independence

Application workspace allocation is independent of the workspace presentation feature.

It does not require Waybar, the workspace IPC patch or any particular status bar.

Both features can be installed separately or together.

## License

This project is distributed under the GNU General Public License, version 3 (GPL-3.0).

See the repository `LICENSE` file for details.
