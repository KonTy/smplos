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

14 built-in themes, each providing colors for all UI components:

Catppuccin Mocha, Catppuccin Latte, Dracula, Gruvbox Dark, Gruvbox Light, Nord, One Dark, Rose Pine, Rose Pine Dawn, Solarized Dark, Solarized Light, Sweet, Tokyo Night, Tokyo Night Light.

## License

MIT License. See [LICENSE](LICENSE) for details.

Terminal emulators (st, st-wl) are under their own licenses — see their respective directories.
