<p align="center">
  <img src="src/shared/configs/smplos/branding/plymouth/logo.png" alt="smplOS" width="300">
</p>

<h3 align="center">A simple OS that just works.</h3>

<p align="center">
  Minimal &bull; Lightweight &bull; Offline-first &bull; Cross-compositor
</p>

---

## What is smplOS?

smplOS is a minimal Arch Linux distribution built around one idea: **simplicity**.

It draws inspiration from projects like [Omarchy](https://omakub.org/) but takes a different path. Where others ship opinions, smplOS ships sensible defaults that stay out of your way. No bloat, no decisions made for you — just a clean, fast, good-looking system that works the moment you boot it.

### Why smplOS?

- **Lightweight.** Under 850 MB of RAM on a cold boot. Every package earns its place.
- **Fast installs.** Fully offline — no internet required. A fresh install completes in under 2 minutes.
- **Cross-compositor.** Built from the ground up to support multiple compositors. Hyprland (Wayland) ships first, DWM (X11) is next. Shared configs, shared themes, shared keybindings — the compositor is just a thin layer.
- **One UI toolkit.** EWW powers the bar, widgets, and dialogs. It runs on both X11 and Wayland. No waybar, no polybar, no redundant tools.
- **14 built-in themes.** One command switches colors across the entire system — terminal, bar, notifications, borders, lock screen, and editor.

### Design Decisions

Every tool in smplOS was chosen to work across compositors — Wayland and X11 — so the OS feels identical regardless of which one you run.

| Component | Choice | Why |
|-----------|--------|-----|
| **Bar & widgets** | EWW | GTK3-based — runs natively on both X11 and Wayland. One codebase for bar, launcher, theme picker, and keybind help. Replaces waybar, polybar, and rofi. |
| **Launcher** | Rofi | Wayland fork (lbonn/rofi) and X11 original share the same config format and theming. One theme file, two backends. |
| **Terminal** | st / st-wl | Suckless st has an X11 build and a Wayland port (marchaesen/st-wl). Same config.h, same patches, same look. Starts in ~5ms and uses ~4 MB of RAM — critical for staying under the 850 MB cold-boot target. |
| **Notifications** | Dunst | Works on both X11 and Wayland with the same config. Lightweight, themeable, no dependencies on a specific compositor. |

The rule is simple: if a tool only works on one display server, it doesn't ship in `src/shared/`. Compositor-specific code stays in `src/compositors/<name>/` and is kept as thin as possible.

### Editions

smplOS ships in focused editions, each adding curated tools on top of the same minimal base:

| Edition | Focus | Example apps |
|---------|-------|-------------|
| **Lite** | Minimal base | Browser, terminal, file manager |
| **Creators** | Design & media | GIMP, OBS, Kdenlive, Inkscape |
| **Productivity** | Office & workflow | LibreOffice, Thunderbird, Obsidian |
| **Communication** | Chat & calls | Discord, Signal, Slack |

Every edition installs offline, in under 2 minutes, from the same ISO.

---

## Architecture

smplOS separates shared infrastructure from compositor-specific configuration. The goal is maximum code reuse — compositors are a thin layer on top of a shared foundation.

```
src/
  shared/              Everything here works on ALL compositors
    bin/               User-facing scripts (installed to /usr/local/bin/)
    eww/               EWW bar and widgets (GTK3 -- works on X11 + Wayland)
    configs/smplos/    Cross-compositor configs (bindings.conf, branding)
    themes/            14 themes with templates for all apps
    installer/         OS installer
    settings-panel/    System settings
  compositors/
    hyprland/          Hyprland-specific config (hypr/, st-wl terminal)
    dwm/               DWM-specific config (st terminal, future)
  editions/            Edition-specific package lists and post-install scripts
  builder/             ISO build pipeline
  iso/                 ISO resources (boot entries, offline repo)
release/               VM testing tools (dev-push, test-iso, QEMU scripts)
```

## Design Principles

- **Simple over opinionated.** Provide good defaults, not forced workflows.
- **Cross-compositor first.** Every feature must work across Hyprland (Wayland) and DWM (X11). Compositor-specific code stays in `src/compositors/<name>/`.
- **EWW is the UI layer.** Bar, widgets, dialogs — all EWW. It runs on both GTK3/X11 and GTK3/Wayland.
- **One theme system.** `theme-set` applies colors to EWW, terminals, btop, notifications, compositor borders, lock screen, and neovim.
- **bindings.conf is the single source of truth** for keybindings across all compositors.
- **Minimal packages.** One terminal, one launcher, one bar. No redundant tools.
- **Offline-first.** The ISO carries everything needed. No downloads during install.

## Compositors

| Compositor | Display Server | Terminal | Status |
|------------|---------------|----------|--------|
| Hyprland   | Wayland       | st-wl    | Active |
| DWM        | X11           | st       | Planned |

## Building

### ISO

```bash
cd src && ./build-iso.sh
```

This produces a bootable Arch Linux ISO with smplOS pre-configured. Takes ~15 minutes.

### Development Iteration

For config/script changes, avoid full ISO rebuilds:

```bash
# Host: push changes to VM shared folder
cd release && ./dev-push.sh eww    # or: bin, hypr, themes, all

# VM: apply changes to the live system
sudo bash /mnt/dev-apply.sh
```

### VM Testing

```bash
cd release && ./test-iso.sh
```

## Themes

14 built-in themes. Press <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>T</kbd> to open the theme picker and switch instantly.

Catppuccin Mocha, Catppuccin Latte, Ethereal, Everforest, Flexoki Light, Gruvbox, Hackerman, Kanagawa, Matte Black, Nord, Osaka Jade, Ristretto, Rose Pine, Tokyo Night.

One command -- `theme-set <name>` -- applies colors across the entire system: terminal, bar, notifications, compositor borders, lock screen, launcher, system monitor, editor, fish shell, and browser chrome.

### How It Works

The theme system is a **build-time template pipeline** plus a **runtime switcher**:

```
colors.toml ──► generate-theme-configs.sh ──► 9 pre-baked configs per theme
                      (sed templates)
                                               theme-set copies them to
                                               their target locations and
                                               restarts/reloads each app
```

Each theme is a directory under `src/shared/themes/<name>/` containing:

| File | Source | Purpose |
|------|--------|---------|
| `colors.toml` | Hand-authored | Single source of truth -- all colors and decoration variables |
| `btop.theme` | Generated | btop color scheme |
| `dunstrc.theme` | Generated | Dunst notification colors |
| `eww-colors.scss` | Generated | EWW bar/widget SCSS variables |
| `eww-colors.yuck` | Generated | EWW yuck variables (for SVG fills) |
| `fish.theme` | Generated | Fish shell syntax highlighting |
| `foot.ini` | Generated | Foot terminal colors |
| `hyprland.conf` | Generated | Hyprland border colors, rounding, blur, opacity |
| `hyprlock.conf` | Generated | Lock screen colors |
| `rofi.rasi` | Generated | Rofi launcher theme |
| `neovim.lua` | Hand-authored | Lazy.nvim colorscheme spec |
| `vscode.json` | Hand-authored | VS Code/Codium/Cursor theme name + extension ID |
| `icons.theme` | Hand-authored | GTK icon theme name |
| `light.mode` | Hand-authored (optional) | Marker file -- if present, GTK + browser use light mode |
| `backgrounds/` | Hand-authored | Wallpapers bundled with the theme |
| `preview.png` | Hand-authored | Theme preview screenshot for the picker |

### colors.toml Reference

Every theme defines all its values in a single `colors.toml` file. Here's the full set of variables:

#### Colors

| Variable | Description | Example |
|----------|-------------|---------|
| `accent` | Primary accent color (bar icons, active borders, highlights) | `"#89b4fa"` |
| `cursor` | Terminal cursor color | `"#f5e0dc"` |
| `foreground` | Default text color | `"#cdd6f4"` |
| `background` | Window/terminal background | `"#1e1e2e"` |
| `selection_foreground` | Text color in selections | `"#1e1e2e"` |
| `selection_background` | Background color of selections | `"#f5e0dc"` |
| `color0` - `color15` | Standard 16-color terminal palette | `"#45475a"` |

> **Note:** `color7` and `color15` are the colors terminals actually display for normal text in most shells. If terminal text looks dim, brighten these to match `foreground`.

#### Decoration

| Variable | Default | Description |
|----------|---------|-------------|
| `rounding` | `"10"` | Window corner radius in pixels |
| `blur_size` | `"6"` | Background blur kernel size |
| `blur_passes` | `"3"` | Number of blur passes (higher = smoother, more GPU) |
| `opacity_active` | `"0.92"` | Opacity of focused windows (0.0 - 1.0) |
| `opacity_inactive` | `"0.85"` | Opacity of unfocused windows |
| `term_opacity_active` | `"1.0"` | Opacity of focused terminal windows |
| `term_opacity_inactive` | `"1.0"` | Opacity of unfocused terminal windows |
| `popup_opacity` | `"0.60"` | Opacity of EWW popups (calendar, etc.) |

Terminal opacity is separated from general window opacity so themes can give terminals a frosted-glass look while keeping other apps more opaque (or vice versa).

#### Example: Catppuccin Mocha

```toml
accent = "#89b4fa"
cursor = "#f5e0dc"
foreground = "#cdd6f4"
background = "#1e1e2e"
selection_foreground = "#1e1e2e"
selection_background = "#f5e0dc"

color0 = "#45475a"
color1 = "#f38ba8"
color2 = "#a6e3a1"
color3 = "#f9e2af"
color4 = "#89b4fa"
color5 = "#f5c2e7"
color6 = "#94e2d5"
color7 = "#cdd6f4"
color8 = "#585b70"
color9 = "#f38ba8"
color10 = "#a6e3a1"
color11 = "#f9e2af"
color12 = "#89b4fa"
color13 = "#f5c2e7"
color14 = "#94e2d5"
color15 = "#cdd6f4"

rounding = "12"
blur_size = "14"
blur_passes = "3"
opacity_active = "0.60"
opacity_inactive = "0.50"
term_opacity_active = "1.0"
term_opacity_inactive = "1.0"
popup_opacity = "0.40"
```

### Template System

Templates live in `src/shared/themes/_templates/` and use `{{ variable }}` placeholders.

The generator provides three variants of each color variable:

| Variant | Example input | Output | Use case |
|---------|--------------|--------|----------|
| `{{ accent }}` | `"#89b4fa"` | `#89b4fa` | CSS, config files |
| `{{ accent_strip }}` | `"#89b4fa"` | `89b4fa` | Hyprland `rgb()`, btop, foot |
| `{{ accent_rgb }}` | `"#89b4fa"` | `137,180,250` | Hyprlock `rgba()` |

### Creating a New Theme

1. **Create the directory:**
   ```bash
   mkdir src/shared/themes/my-theme
   ```

2. **Write `colors.toml`** with all color and decoration values. Copy an existing theme as a starting point:
   ```bash
   cp src/shared/themes/catppuccin/colors.toml src/shared/themes/my-theme/
   ```

3. **Add optional hand-authored files:**
   - `neovim.lua` -- Lazy.nvim colorscheme plugin spec
   - `vscode.json` -- `{"name": "Theme Name", "extension": "publisher.extension-id"}`
   - `icons.theme` -- GTK icon theme name (e.g., `Papirus-Dark`)
   - `light.mode` -- Create this empty file if the theme is light
   - `backgrounds/` -- Add wallpapers (named `1-name.png`, `2-name.png`, etc.)
   - `preview.png` -- Screenshot for the theme picker

4. **Generate configs:**
   ```bash
   cd src && bash generate-theme-configs.sh
   ```
   This reads your `colors.toml`, expands all 9 templates, and writes the results into your theme directory.

5. **Test it:**
   ```bash
   theme-set my-theme
   ```

### What theme-set Does

When you run `theme-set <name>`, it:

1. Resolves the theme (user themes in `~/.config/smplos/themes/` take precedence over stock themes)
2. Atomically swaps the active theme directory at `~/.config/smplos/current/theme/`
3. Copies pre-baked configs to their target locations:
   - `eww-colors.scss` &#x2192; `~/.config/eww/theme-colors.scss`
   - `hyprland.conf` &#x2192; `~/.config/hypr/theme.conf`
   - `hyprlock.conf` &#x2192; `~/.config/hypr/hyprlock-theme.conf`
   - `foot.ini` &#x2192; `~/.config/foot/theme.ini`
   - `btop.theme` &#x2192; `~/.config/btop/themes/current.theme`
   - `fish.theme` &#x2192; `~/.config/fish/theme.fish`
   - `rofi.rasi` &#x2192; `~/.config/rofi/smplos.rasi`
   - `dunstrc.theme` &#x2192; appended to `~/.config/dunst/dunstrc.active`
   - `neovim.lua` &#x2192; `~/.config/nvim/lua/plugins/colorscheme.lua`
4. Bakes accent/fg colors into SVG icon templates for the EWW bar
5. Sets the wallpaper from `backgrounds/`
6. Restarts/reloads all running apps:
   - EWW bar: kill + restart (re-compiles SCSS)
   - Hyprland: `hyprctl reload`
   - st/st-wl: OSC escape sequences (live, no restart)
   - Foot: `SIGUSR1`
   - Dunst: `dunstctl reload`
   - btop: `SIGUSR2`
   - GTK: `gsettings` (dark/light mode)
   - Brave/Chromium: managed policy + flags file

### Opacity Architecture

Window opacity is controlled at two levels:

1. **Application level** -- st-wl has a compiled-in alpha patch. `DEFAULT_ALPHA` in `config.h` is set to `1.0` (fully opaque) so the terminal renders solid pixels. The `-A` flag can override this at launch.

2. **Compositor level** -- Hyprland window rules in `windows.conf` apply per-theme opacity:
   ```
   # All windows get the theme's default opacity
   windowrule = opacity $themeOpacityActive $themeOpacityInactive, match:class .*

   # Terminals get their own opacity (can be more or less transparent)
   windowrule = opacity $themeTermOpacityActive $themeTermOpacityInactive, match:class ^(terminal|com\.mitchellh\.ghostty)$

   # Media apps and fullscreen are always fully opaque
   windowrule = opacity 1.0 1.0, match:class ^(mpv|imv|vlc|firefox|chromium|brave)$
   ```

   Rule order matters -- **last match wins** in Hyprland. Terminal and media rules come after the generic rule to override it.

## License

MIT License. See [LICENSE](LICENSE) for details.

Terminal emulators (st, st-wl) are under their own licenses — see their respective directories.
