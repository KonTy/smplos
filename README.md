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

---

#### Start Menu

The launcher is built with Rofi and styled to match the active theme. Tap <kbd>Super</kbd> to open it — it searches installed apps, does basic math, and closes on selection. No dock, no taskbar, no wasted pixels. Just a fast, keyboard-driven menu that stays out of your way until you need it.

<a href="images/1-start-menu.png"><img src="images/1-start-menu.png" width="720" /></a>

#### Memory Footprint

A cold boot sits under 800 MB of RAM with the full desktop running — bar, notifications, compositor, and all background services. Unlike other lightweight distros that sacrifice usability to hit low numbers, smplOS keeps quality-of-life features like auto-mount, theme switching, a notification center, and a full app launcher. Light enough for a 2 GB VM, comfortable enough for daily driving.

<a href="images/2-mem.png"><img src="images/2-mem.png" width="720" /></a>

#### Notification Center

We couldn't find a notification center that met our requirements: low RAM usage, works on both X11 and Wayland, and looks modern out of the box. So we wrote one from scratch in Rust. It integrates with Dunst, groups notifications by app, supports dismiss and clear-all, and uses a fraction of the memory that Electron-based alternatives need.

<a href="images/3-notif-center.png"><img src="images/3-notif-center.png" width="720" /></a>

#### Terminal (st-wl)

st is our terminal of choice — a suckless terminal patched for the features that matter. It starts in milliseconds and idles at around 25 MB of RAM. We added SIXEL image support, scrollback, clipboard integration, Page Up/Down, and alpha transparency. The result is a terminal that can display inline images just like Kitty (~350 MB), but at a fraction of the footprint. Every fix was made in `config.def.h` following the suckless philosophy: if you don't need it, it doesn't exist.

We also fixed several upstream bugs found in the suckless st codebase:

- **History buffer allocation** — the default scrollback patch pre-allocates the entire buffer (HISTSIZE x columns) at startup, wasting tens of MB. We rewrote it to use page-based lazy allocation (256-line pages, allocated on demand).
- **HISTSIZE default** — upstream ships with `HISTSIZE = 99999` (~80 MB for a wide terminal). Reduced to 2000 lines, which is plenty for real use.
- **Page Up/Down not working** — the scrollback patch only bound Shift+PageUp/Down but left plain PageUp/Down doing nothing. Added `MOD_MASK_NONE` bindings so both work.
- **X11-only patches breaking Wayland** — several patches (e.g. `sixelbyteorder = LSBFirst`) use X11 macros that don't exist in the Wayland build. Identified and disabled them.
- **Font fallback crash** — st-wl crashed on launch when no `-f` flag was given. Fixed the default font fallback path.
- **SIXEL linker errors** — enabling the SIXEL patch in `patches.def.h` alone wasn't enough; the SIXEL source files and imlib2 libs also need uncommenting in `config.mk`.

<a href="images/4.term.png"><img src="images/4.term.png" width="720" /></a>

#### Themes

smplOS ships with 14 themes inherited and expanded from the Omarchy project. A single `theme-set` command applies colors system-wide — terminal, EWW bar, notifications, Hyprland borders, lock screen, btop, neovim, and VS Code. Every theme includes matching wallpapers and is generated from a single `colors.toml` source of truth.

<a href="images/5-themes.png"><img src="images/5-themes.png" width="720" /></a>

---

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

smplOS ships in focused editions that **stack on top of each other**. Pick the ones you need — they all merge cleanly:

| Flag | Edition | Focus | Example apps |
|------|---------|-------|-------------|
| `-p` | **Productivity** | Office & workflow | Logseq, LibreOffice, KeePassXC |
| `-c` | **Creators** | Design & media | OBS, Kdenlive, GIMP |
| `-m` | **Communication** | Chat & calls | Discord, Signal, Slack |
| `-d` | **Development** | Developer tools | VSCode, LazyVim (neovim), lazygit |
| `-a` | **AI** | AI tools | Ollama, open-webui |

Build with any combination:

```bash
./build-iso.sh -p -d          # Productivity + Development
./build-iso.sh -p -d -c -m    # Stack all four
./build-iso.sh                 # Base only (browser, terminal, file manager)
```

Every edition installs offline, in under 2 minutes, from the same ISO.

---

## Getting Started

On first boot, a notification shows the essential keybindings. Here they are for reference:

| Shortcut | Action |
|----------|--------|
| <kbd>Super</kbd> (tap) | Start menu launcher |
| <kbd>Super</kbd>+<kbd>Enter</kbd> | Terminal |
| <kbd>Super</kbd>+<kbd>Space</kbd> | App launcher |
| <kbd>Super</kbd>+<kbd>W</kbd> | Close window |
| <kbd>Super</kbd>+<kbd>F</kbd> | Fullscreen |
| <kbd>Super</kbd>+<kbd>T</kbd> | Toggle floating |
| <kbd>Super</kbd>+<kbd>1-9</kbd> | Switch workspace |
| <kbd>Super</kbd>+<kbd>K</kbd> | Keybinding cheatsheet |
| <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>F</kbd> | File manager |
| <kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd> | Web browser |
| <kbd>Print</kbd> | Screenshot |
| <kbd>Super</kbd>+<kbd>Escape</kbd> | Power menu |

Press <kbd>Super</kbd>+<kbd>K</kbd> anytime to see all bindings in an overlay.

### Themes

Switch the system theme (terminal, bar, borders, lock screen, editor) with a single command:

```bash
theme-set catppuccin     # or: dracula, nord, gruvbox, rose-pine, ...
```

Or open the theme picker from the start menu's Settings tab.

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

## Start Menu Launcher

smplOS includes a custom start menu launcher built on rofi, inspired by the [adi1090x](https://github.com/adi1090x/rofi) type-1/style-15 layout. It appears at the bottom-left of the screen (like a Plasma/Windows start menu) with a slide-left animation, blur, and per-theme transparency.

**Open it:** Press <kbd>Super</kbd> (tap and release) or click the logo in the EWW bar.

### Tabs

The launcher uses rofi's native modi system with two tabs:

| Tab | Hotkey | What it shows |
|-----|--------|---------------|
| **Apps** | <kbd>Alt</kbd>+<kbd>A</kbd> | All desktop applications (drun) |
| **Settings** | <kbd>Alt</kbd>+<kbd>S</kbd> | System settings entries (Wi-Fi, Bluetooth, Display, Audio, Themes, etc.) |

Hotkeys jump to the tab **and clear the search filter** — so you get a fresh list every time. The mode-switcher tabs at the bottom are also clickable.

### How it works

- **`launcher`** — wrapper script that runs rofi with native modi (`drun` + `settings:rofi-settings-src`). Handles <kbd>Alt</kbd>+<kbd>A</kbd>/<kbd>Alt</kbd>+<kbd>S</kbd> via `kb-custom` exit codes, restarting rofi on the target mode.
- **`rofi-settings-src`** — rofi script-mode source that reads from the app cache, filtering for settings entries.
- **`smplos-launcher.rasi.tpl`** — theme template with `rgba()` transparency using `popup_opacity` from `colors.toml`, matching the look of other popup panels.
- **Hyprland layerrules** — `animation slide left`, `blur on`, `ignore_alpha 0.1` on namespace `rofi`.

### App Cache

The launcher reads from a pre-built app index at `~/.cache/smplos/app_index`. This is automatically rebuilt by a systemd path unit (`smplos-app-cache.path`) whenever `.desktop` files, Flatpak apps, or AppImages change. You can also rebuild manually:

```bash
rebuild-app-cache
```

## GTK Theming & Credential Storage

smplOS configures the system so GTK dialogs (file pickers, VS Code popups, etc.) follow the dark/light theme automatically:

- **GTK settings.ini** — written during install for X11 fallback
- **dconf/GSettings** — written during install via `dbus-run-session` for Wayland (GTK on Wayland ignores `settings.ini`)
- **`theme-set`** — updates both `gsettings color-scheme` and `gtk-theme` on every theme switch

Credential storage (for VS Code, Brave, git, etc.) is fully configured:

- **gnome-keyring** — installed, started via Hyprland autostart, PAM-integrated for auto-unlock at login
- **VS Code argv.json** — pre-configured with `"password-store": "gnome-libsecret"` to eliminate the keyring detection dialog

## Notification Center

A custom notification center built with Rust and [Slint](https://slint.dev), accessible from the bell icon in the EWW bar. It reads dunst's notification history and displays cards with dynamic heights — long messages word-wrap naturally instead of being truncated.

**Open it:** Click the bell icon in the bar, or press <kbd>Super</kbd> + <kbd>N</kbd>.

### Features

- **Dynamic card layout** — each notification card grows to fit its content. No fixed heights, no wasted space.
- **Word-wrapped body text** — long notification bodies wrap cleanly instead of being clipped with an ellipsis.
- **Double-click to open** — double-click any notification to launch the associated app. Uses the desktop entry from dunst metadata, with a fallback to the app name.
- **Actionable notifications** — well-known notifications (like "System Update") map to specific commands. Double-click the System Update notification to open a full system update in your terminal.
- **Dismiss** — click the × button on any card to dismiss it.
- **Scrollable** — notifications overflow into a smooth-scrolling list.

### Architecture

```
dunst (notification daemon)
  └─ dunstctl history ──► notif-center (Rust + Slint)
                              ├─ Parses JSON history
                              ├─ Maps app names to nerd font icons
                              ├─ Maps summaries to actions (e.g. "System Update" → smplos-update)
                              └─ Renders scrollable card list via Slint UI
```

## System Updates

smplOS includes a built-in update system. On first boot, a persistent "System Update" notification appears. Double-click it in the notification center to run a full update, or run it manually:

```bash
smplos-update
```

The update script opens in your terminal and runs through:

1. **Pacman** — official repo packages (`pacman -Syu --noconfirm`)
2. **AUR** — if paru is installed, AUR packages (`paru -Sua --noconfirm`)
3. **Flatpak** — if Flatpak apps are installed (`flatpak update -y --noninteractive`)
4. **AppImages** — reminds you to check for updates manually

Terminal auto-detection ensures it works regardless of which terminal is installed: `xdg-terminal-exec` &#x2192; `st-wl` (Wayland) &#x2192; `st` (X11) &#x2192; `foot` &#x2192; `xterm`.

## Building

The build system is designed to work on **first run, on any Linux distro**. It runs inside a Docker container for reproducibility — your host system only needs Docker.

### Quick Start

```bash
cd src && ./build-iso.sh
```

This produces a bootable Arch Linux ISO in `release/`. First build takes ~15-20 minutes (downloads packages); subsequent same-day builds reuse the package cache and finish much faster.

### Prerequisites

The only hard requirement is **Docker**. If Docker isn't installed, the build script will detect your distro and offer to install it for you:

```
[WARN] Docker not found
Install Docker automatically? [Y/n]
```

If you prefer to install Docker yourself:

<details>
<summary><b>Arch / EndeavourOS / Manjaro / Garuda / CachyOS</b></summary>

```bash
sudo pacman -S --needed docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
# Log out and back in for group to take effect
```
</details>

<details>
<summary><b>Ubuntu / Debian / Pop!_OS / Linux Mint / Zorin</b></summary>

```bash
# Install prerequisites
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

# Add Docker GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repo (use "ubuntu" or "debian" depending on your base)
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```
</details>

<details>
<summary><b>Fedora / Nobara</b></summary>

```bash
sudo dnf install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```
</details>

<details>
<summary><b>openSUSE</b></summary>

```bash
sudo zypper install -y docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```
</details>

<details>
<summary><b>Void Linux</b></summary>

```bash
sudo xbps-install -y docker
sudo ln -s /etc/sv/docker /var/service/
sudo usermod -aG docker $USER
```
</details>

After installing Docker, **log out and back in** so the docker group takes effect. If you skip this, the build script will automatically fall back to `sudo docker`.

You also need **~10 GB of free disk space**. The script checks this and warns you if you're low.

### Build Options

```
Usage: build-iso.sh [OPTIONS]

Editions (stackable):
    -p, --productivity      Add Productivity edition (Logseq, LibreOffice, KeePassXC)
    -c, --creators          Add Creators edition (OBS, Kdenlive, GIMP)
    -m, --communication     Add Communication edition (Discord, Signal, Slack)
    -d, --development       Add Development edition (VSCode, LazyVim, lazygit)
    -a, --ai                Add AI edition (Ollama, open-webui)

General:
    --compositor NAME       Compositor to build (hyprland, dwm) [default: hyprland]
    -r, --release           Release build: max xz compression (slow, smallest ISO)
    -n, --no-cache          Force fresh package downloads
    -v, --verbose           Verbose output
    --skip-aur              Skip AUR packages (faster, no Rust compilation)
    --skip-flatpak          Skip Flatpak packages
    --skip-appimage         Skip AppImages
    -h, --help              Show this help
```

#### Common Workflows

```bash
# Base build (Hyprland, browser, terminal, file manager)
./build-iso.sh

# Productivity + Development
./build-iso.sh -p -d

# Stack everything
./build-iso.sh -p -d -c -m -a

# Fast iteration build (skip AUR packages like EWW that take ages to compile)
./build-iso.sh --skip-aur

# Release build with max compression
./build-iso.sh -p -d --release

# Full verbose output for debugging
./build-iso.sh -v
```

### What the Build Does

1. **Checks prerequisites** — detects your distro, ensures Docker is installed and running, checks disk space.
2. **Builds AUR packages** (unless `--skip-aur`) — compiles packages like EWW in a temporary container. Results are cached in `src/iso/prebuilt/` so they only build once.
3. **Pulls `archlinux:latest`** — the build runs in a fresh Arch container for reproducibility.
4. **Downloads packages** — uses `pacman -Syw` to download all packages into a local mirror. On Arch-based hosts, your system's pacman cache is mounted read-only for instant hits.
5. **Builds the ISO** — copies configs, themes, scripts, and the offline package mirror into an Arch ISO profile, then runs `mkarchiso`.
6. **Outputs** — the final `.iso` lands in `release/`.

### Caching

Builds use a **dated cache** (`build_YYYY-MM-DD/`) under `.cache/`. Same-day rebuilds reuse downloaded packages. Old caches are automatically pruned (keeps the last 3 days). To force a completely fresh build:

```bash
./build-iso.sh --no-cache
```

### Troubleshooting

| Problem | Solution |
|---------|----------|
| `permission denied` from Docker | Run `sudo usermod -aG docker $USER`, then log out and back in |
| DNS errors inside container | The build script passes `--dns 1.1.1.1 --dns 8.8.8.8` to work around systemd-resolved. If you still get DNS errors, check your firewall. |
| `no space left on device` | Need ~10 GB free. Also run `docker system prune` to reclaim Docker disk space. |
| AUR build fails | Try `--skip-aur` to skip it. Pre-built AUR packages are cached in `src/iso/prebuilt/`. |
| Slow builds | First build downloads ~2 GB of packages. After that, the cache makes rebuilds much faster. On Arch hosts, your system pacman cache is reused automatically. |

### Development Iteration

For config/script changes, avoid full ISO rebuilds:

```bash
# Host: push changes to VM shared folder
cd release && ./dev-push.sh eww    # or: bin, hypr, themes, all

# VM: apply changes to the live system
sudo bash /mnt/dev-apply.sh
```

### VM Testing

Use QEMU for testing — it provides a `virtio-gpu` device that Hyprland works with out of the box:

```bash
cd release && ./test-iso.sh
```

This launches a QEMU VM with KVM acceleration, UEFI firmware, a 20 GB virtual disk, and a 9p shared folder for live hot-reloading. The script auto-detects OVMF, finds the newest ISO in `release/`, and opens the VM window.

Once the VM boots, mount the shared folder to enable hot-reload:

```bash
# Inside the VM:
sudo mount -t 9p -o trans=virtio hostshare /mnt
```

Then iterate without rebuilding the ISO:

```bash
# Host: push changes to the shared folder
cd release && ./dev-push.sh

# VM: apply them to the live system
sudo bash /mnt/dev-apply.sh
```

The 9p mount is live — `dev-push.sh` writes to `release/vmshare/` and changes are immediately visible inside the VM. No remount needed.

Use `--reset` to wipe the VM disk and start fresh:

```bash
./test-iso.sh --reset
```

> **VirtualBox is not supported.** Hyprland requires a working DRM/KMS device with OpenGL support. VirtualBox's virtual GPU (`VBoxVGA` / `VMSVGA`) does not provide this — Hyprland will crash immediately on startup, producing a "Couldn't wait for Hyprland. No child process" error from the login manager. This is a [known limitation](https://wiki.hyprland.org/Getting-Started/Installation/#running-in-a-vm) across all Hyprland-based distros, not a smplOS bug. Use QEMU with KVM (`test-iso.sh`) or VMware with 3D acceleration instead.

## Themes

14 built-in themes. Press <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>T</kbd> to open the theme picker and switch instantly.

Catppuccin Mocha, Catppuccin Latte, Ethereal, Everforest, Flexoki Light, Gruvbox, Hackerman, Kanagawa, Matte Black, Nord, Osaka Jade, Ristretto, Rose Pine, Tokyo Night.

One command -- `theme-set <name>` -- applies colors across the entire system: terminal, bar, notifications, compositor borders, lock screen, launcher, system monitor, editor, fish shell, Logseq, and browser chrome.

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
| `fish.theme` | Generated | Fish shell syntax highlighting and pager colors |
| `foot.ini` | Generated | Foot terminal colors |
| `hyprland.conf` | Generated | Hyprland border colors, rounding, blur, opacity |
| `hyprlock.conf` | Generated | Lock screen colors |
| `logseq-custom.css` | Generated | Logseq editor colors (backgrounds, text, links, highlights) |
| `smplos-launcher.rasi` | Generated | Rofi start menu theme (rgba transparency via `popup_opacity`) |
| `neovim.lua` | Hand-authored | Lazy.nvim colorscheme spec |
| `vscode.json` | Hand-authored | VS Code/Codium/Cursor theme name + extension ID |
| `icons.theme` | Hand-authored | GTK icon theme name |
| `light.mode` | Hand-authored (optional) | Marker file -- if present, GTK + browser use light mode |
| `tide.theme` | Hand-authored | Tide prompt colors (git, pwd, vi-mode segments) |
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
   - `tide.theme` &#x2192; applied via `fish -c "source ...; tide reload"`
   - `logseq-custom.css` &#x2192; `~/.logseq/config/custom.css` + plugin theme via `preferences.json`
   - `smplos-launcher.rasi` &#x2192; `~/.config/rofi/smplos-launcher.rasi`
   - `dunstrc.theme` &#x2192; appended to `~/.config/dunst/dunstrc.active`
   - `neovim.lua` &#x2192; `~/.config/nvim/lua/plugins/colorscheme.lua`
4. Bakes accent/fg colors into SVG icon templates for the EWW bar
5. Sets the wallpaper from `backgrounds/`
6. Restarts/reloads all running apps:
   - EWW bar: kill + restart (re-compiles SCSS)
   - Hyprland: `hyprctl reload`
   - st/st-wl: OSC escape sequences (live, no restart)
   - Foot: `SIGUSR1`
   - Fish: sources `theme.fish` in all running sessions
   - Tide prompt: `tide reload` (updates git, pwd, vi-mode segment colors)
   - Dunst: `dunstctl reload`
   - btop: `SIGUSR2`
   - Logseq: writes `preferences.json` (Logseq watches this file)
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
