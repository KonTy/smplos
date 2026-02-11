# smplOS Development Principles

## Architecture: Cross-Compositor First

smplOS supports multiple compositors (Hyprland/Wayland, DWM/X11). Every feature
must be designed with this in mind. The goal is maximum code reuse — compositors
are a thin layer on top of a shared foundation.

### Directory Structure

```
src/shared/          ← Everything here works on ALL compositors
  bin/               ← User-facing scripts (installed to /usr/local/bin/)
  eww/               ← EWW bar, launcher, theme picker, keybind help (GTK3, works on X11 + Wayland)
  configs/smplos/    ← Cross-compositor configs (bindings.conf = single source of truth)
  themes/            ← 14 themes with templates for all apps
  installer/         ← OS installer

src/compositors/hyprland/   ← ONLY Hyprland-specific config
  hypr/                     ← hyprland.conf sources shared bindings.conf
  packages.txt              ← Wayland-specific packages

src/compositors/dwm/        ← ONLY DWM-specific config (future)
  config.h                  ← Will be generated from shared bindings.conf
  packages.txt              ← X11-specific packages
```

### Rules

1. **Shared by default.** New scripts go in `src/shared/bin/`. Only put code in
   `src/compositors/<name>/` if it literally cannot work elsewhere.

2. **No unnecessary dependencies.** Before adding a tool (fuzzel, rofi, wofi),
   ask: can EWW do this? EWW works on both X11 and Wayland. One fewer package
   to maintain per compositor.

3. **Compositor detection, not hardcoding.** When a script needs compositor-specific
   behavior, detect at runtime:
   ```bash
   if [[ -n "$WAYLAND_DISPLAY" ]]; then
       # Wayland path (Hyprland)
   else
       # X11 path (DWM)
   fi
   ```

4. **bindings.conf is the single source of truth** for keybindings.
   - Lives at `src/shared/configs/smplos/bindings.conf`
   - Uses Hyprland `bindd` format (human-readable, comma-delimited)
   - Build pipeline copies it as-is for Hyprland
   - DWM build will parse it and generate C structs for `config.h`
   - `get-keybindings.sh` parses it for the EWW keybind-help overlay

5. **EWW is the UI layer.** Bar, launcher, theme picker, keybind help — all EWW.
   No waybar, no polybar. EWW runs on both GTK3/X11 and GTK3/Wayland.

6. **Theme system is universal.** One `theme-set` script applies colors to:
   EWW, st, foot, btop, mako, Hyprland borders, hyprlock, neovim.
   Adding a compositor means adding one more template, not rewriting themes.

### EWW Guidelines

- **Single-line JSON for `deflisten`.** EWW reads stdout line-by-line. Multi-line
  JSON breaks `deflisten` variables. Always output compact single-line JSON.
- **No `@charset` triggers.** Avoid non-ASCII characters (em-dashes `—`, curly
  quotes, etc.) in `.scss` files. The grass SCSS compiler inserts
  `@charset "UTF-8"` which GTK3's CSS parser rejects silently → white unstyled bar.
- **Script permissions.** Always `chmod +x` EWW scripts in build pipeline AND at
  runtime (archiso/useradd can strip execute bits).
- **`--config $HOME/.config/eww`** on every `eww` CLI call.
- **Every `defwindow` must have an explicit `:namespace`.** Without it, the
  Wayland layer surface gets the default namespace `"gtk-layer-shell"`, which
  means Hyprland `layerrule` (blur, opacity, animations) cannot target individual
  windows. Use the convention `:namespace "eww-<window-name>"` (e.g.
  `"eww-bar"`, `"eww-calendar-popup"`). Then match in `windows.conf`:
  `layerrule = blur on, match:namespace eww-<window-name>`.
- **Use the shared dialog system for overlays.** Theme picker, keybind help, and
  any future overlay (settings, about, etc.) use the same pattern:
  - **CSS:** `.dialog`, `.dialog-header`, `.dialog-title`, `.dialog-close`,
    `.dialog-search`, `.dialog-scroll` -- shared classes in `eww.scss`.
  - **Script:** `dialog-toggle <window> [submap] [--pre-cmd CMD] [--post-cmd CMD]`
    handles toggle, daemon, open/close, submap. New dialogs are thin wrappers.
  - **Yuck:** Each widget uses the `.dialog` container and `.dialog-header` box.
    Only the item-specific content (e.g. theme-card, kb-row) is unique.

### Build & Iteration

- **ISO builds are expensive** (~15 min). Only rebuild for package changes.
- **Use `dev-push.sh` + `dev-apply.sh`** for config/script iteration:
  ```bash
  # Host:
  cd release && ./dev-push.sh eww    # or: bin, hypr, themes, all

  # VM:
  sudo bash /mnt/dev-apply.sh
  ```
- **QEMU VMs can't handle DPMS off or suspend.** `hypridle.conf` skips these
  inside VMs via `systemd-detect-virt -q`.

### Code Quality: Modular & DRY

- **Shapes over colors for state.** Never rely on color alone to indicate state
  (connected/disconnected, notifications/none, etc.). Use distinct icon shapes
  (filled vs outline, with/without X or slash). This ensures accessibility for
  users with color blindness. Color should reinforce the theme, not carry meaning.

- **Extract reusable functions.** If a pattern appears twice, make it a function.
  Bash scripts should define helper functions (`log()`, `die()`, `emit()`) at the
  top rather than repeating inline logic.
- **One responsibility per script.** A script does one thing well. Compose scripts
  together rather than building monoliths.
- **Shared helpers over copy-paste.** Common patterns (logging, JSON output,
  compositor detection, EWW daemon checks) should live in a shared library or
  consistent helper functions, not be duplicated across scripts.
- **Keep it concise.** Prefer short, readable code. Avoid verbose boilerplate,
  redundant comments that restate the code, or unnecessary wrapper layers.
- **Consistent patterns.** All EWW listener scripts should follow the same
  structure: setup, emit function, initial emit, watch loop. All `src/shared/bin/`
  scripts should follow the same error-handling and logging conventions.

### Packages

- Keep the package list minimal. Audit regularly for bloat.
- Known bloat candidates: wofi, fuzzel, rofi-wayland (3 redundant launchers),
  alacritty + foot (unused terminals alongside st), nwg-look (unused GUI tool).
