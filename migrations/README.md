# smplOS Migrations

Migrations are timestamped shell scripts that run **exactly once** per user.
They handle breaking changes from upstream packages (Hyprland, EWW, etc.)
and smplOS config format changes.

## Naming Convention

```
YYYYMMDD-HHMMSS-description.sh
```

The timestamp prefix ensures migrations run in chronological order.
Use the date/time of the commit, not the event.

## Writing a Migration

```bash
#!/bin/bash
# Migration: Brief description of what this fixes
# Context: Why this migration exists (upstream change, config rename, etc.)

set -euo pipefail

# Check if migration is needed (idempotent guard)
if [[ ! -f "$HOME/.config/hypr/hyprland.conf" ]]; then
    echo "  Hyprland config not found, skipping"
    exit 0
fi

# Do the actual migration work
sed -i 's/old_setting/new_setting/' "$HOME/.config/hypr/hyprland.conf"

echo "  Updated hyprland.conf: old_setting -> new_setting"
```

## Rules

1. **Always be idempotent.** Check if the change is needed before applying.
2. **Never delete user data.** Rename or back up instead.
3. **Keep it focused.** One migration per breaking change.
4. **Exit 0 on success**, non-zero on failure.
5. **Print what you did** so the user sees it in the update log.
6. **Test both paths** — fresh install (migration not needed) and upgrade
   (migration needed).
7. **Never touch the live session directly.** See below.

## Session-scoped commands (hyprctl, eww, systemctl --user, …)

**Migrations do not have a graphical session.** `smplos-update` elevates with
`pkexec`, which strips `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY`, `DISPLAY`,
`DBUS_SESSION_BUS_ADDRESS` and `HYPRLAND_INSTANCE_SIGNATURE`.
`smplos-os-update` then runs migrations under
`runuser -u $SMPLOS_INVOKER_USER`, which restores the *identity* but cannot
restore variables that no longer exist in the parent environment.

Without those variables:

| Command | What actually happens |
|---|---|
| `hyprctl …` | `HYPRLAND_INSTANCE_SIGNATURE not set! (is hyprland running?)` |
| `systemctl --user …` | `Failed to connect to user scope bus via local transport` |
| `eww` / `bar-ctl` | IPC socket falls back from `/run/user/<uid>/…` to `/tmp/…`, then `Failed to initialize GTK` |

A migration that ran `bar-ctl stop && bar-ctl start` therefore **closed the
user's working bar and could never bring it back**. This actually shipped.

### Use the shared helper

```bash
# shellcheck source=../src/shared/lib/smplos-session-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../src/shared/lib/smplos-session-env.sh" 2>/dev/null || {
    echo "  WARNING: smplos-session-env.sh not found — skipping session-scoped steps"
    smplos_have_session()  { return 1; }
    smplos_have_hyprland() { return 1; }
    smplos_have_user_bus() { return 1; }
    smplos_run_as_user()   { return 1; }
}
```

Then:

```bash
if smplos_have_hyprland; then
    smplos_run_as_user hyprctl reload &>/dev/null || true
fi
```

The helper lives at `src/shared/lib/smplos-session-env.sh` (also installed to
`/usr/local/lib/smplos/`) and provides:

| Function | Purpose |
|---|---|
| `smplos_resolve_session_env` | Resolve invoker uid + runtime dir + Wayland/X11/D-Bus/Hyprland. Memoized. |
| `smplos_have_session` | True when a Wayland or X11 session was found. |
| `smplos_have_hyprland` | True when a live Hyprland instance was found. |
| `smplos_have_user_bus` | True when the user's systemd manager is reachable. |
| `smplos_run_as_user CMD…` | Run `CMD` as the invoker with the session env restored. |
| `smplos_session_summary` | One-line debug dump of everything resolved. |

`smplos_run_as_user` uses `runuser` when we are root and execs directly when we
are already unprivileged, so a migration behaves identically under `pkexec` and
from a plain user shell.

### Safety invariant — never tear down what you cannot restore

**Check `smplos_have_session` BEFORE stopping or killing anything.** Leaving a
user with no status bar (or no idle daemon) is far worse than deferring a
restart to the next login. Always print how to recover when you skip:

```bash
if ! smplos_have_session; then
    echo "  No graphical session detected — NOT restarting the bar"
    echo "  Run 'bar-ctl start', or log out and back in, to apply the change."
elif restart_bar; then
    echo "  Bar restarted"
fi
```

Use the predicates for gating; they are safe under `set -e` only inside
`if`/`&&`/`||`. `smplos_run_as_user` returns the command's exit status (and `1`
without running anything when no session resolved), so terminate it with
`|| true` when failure is acceptable.

## How It Works

`smplos-migrate` runs all pending migrations in order. State is tracked in
`~/.local/state/smplos/migrations/` — an empty file per completed migration.
Skipped migrations go in `~/.local/state/smplos/migrations/skipped/`.

Migrations are triggered by `smplos-os-update` after `git pull`, before
the pinned packages (Hyprland, EWW) are updated by `smplos-update`.
