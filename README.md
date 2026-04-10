# WebCom Elevators

`webcom_elevators` is a standalone elevator system for FiveM with optional ArgusAdmin/httpmanager integration.

## Features

- Standalone operation without `httpmanager`
- Elevator admin UI via `/elevatoradmin`
- Floor protection with PIN/password rules
- Optional 3D DUI labels and interactive floor panels
- Optional dashboard endpoints when `httpmanager` is running

## Start Order

Start dependencies before the resource:

```cfg
ensure oxmysql
ensure ox_lib
ensure webcom_elevators
```

If you want dashboard integration, start `httpmanager` before `webcom_elevators`.

## Database

The required SQL tables are created automatically on the first resource start.

- No manual SQL import is required for normal setup.
- The files in the `sql` folder are only there for reference/manual recovery.

## Configuration

Main settings are in `config.lua`:

- `Config.PermissionMode = 'config'` for standalone permission checks
- `Config.AdminCommand` to change the admin command
- `Config.InteractionMethod` for target or marker mode
- `Config.DUI` and `Config.InteractiveDUI` to control 3D UI behavior

### Standalone Permissions

When `Config.PermissionMode` is `config`, access is controlled by `Config.Permissions`.

Example:

```lua
Config.Permissions = {
    admin = {
        aces = { 'webcom.elevator.admin' },
        jobs = { 'police' },
        citizenids = {},
    },
}
```

Example ACE entry in `server.cfg`:

```cfg
add_ace group.admin webcom.elevator.admin allow
```

### Dashboard Mode

If `httpmanager` is present and you want dashboard-driven permissions, switch:

```lua
Config.PermissionMode = 'dashboard'
```

In that mode, `Config.WebcomBaseUrl` and `Config.ServerId` are filled from shared config automatically.

## Usage

1. Start the resource.
2. Run `/elevatoradmin` as an authorized player.
3. Create a group.
4. Create an elevator inside that group.
5. Add floors with teleport positions and optional interaction points.
6. Choose protection rules if required.

## Standalone Notes

- Without `httpmanager`, REST endpoints are disabled automatically.
- The resource will still run normally in config mode.
- If you see only the standalone banner in console, that is expected behavior.

## Troubleshooting

- If the admin UI opens but actions fail, verify ACE/job/citizenid permissions.
- If elevators do not appear, confirm floor positions and interaction points are saved.
- If dashboard data is missing, confirm `httpmanager` is started before this resource.