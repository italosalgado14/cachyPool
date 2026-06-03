# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`cachyPool` is **not a software project** — it's a documentation + dotfiles repository for a single machine (Acer Predator PT516-52s, hostname `triton500se`) running **CachyOS + Hyprland on Wayland with NVIDIA**. There is no build, test, or lint pipeline.

It contains:
- Markdown docs that describe and audit the live system state.
- `configs/` — a mirror of live dotfiles (`~/.config/hypr/`, `~/.config/waybar/`, `~/.config/kitty/`) so they can be version-tracked.

The repo is not currently a git repository.

## Source-of-truth hierarchy

The docs were written at different times and **disagree with each other**. Trust them in this order:

1. **`ACTUAL-CONFIGURATION.md`** — most recent (2026-05-21), generated from a live system scan. This is the authoritative snapshot of installed packages, kernel state, NVIDIA stack, monitors, and outstanding issues.
2. **`shorcuts.md`** (typo intentional) — day-to-day usage reference. Combined cheatsheet + full keybinding tables + workflows + Walker/Yazi/Kitty deep-dives + troubleshooting. Pulled from `configs/hypr/keybindings.conf`. **Merged 2026-05-23** from the previous split between `shorcuts.md` (one-page cheatsheet) and `USABILITY.md` (full reference); `USABILITY.md` no longer exists.
3. **`system-state-findings.md`** — audit comparing the planned setup against reality. Marks what's working vs. broken.
4. **`finish-installation-commands.md`** — remediation steps for items flagged in the findings.
5. **`cachyos-hyprland-setup.md`** — original install plan (May 2026). Now partially stale.
6. **`spected-installation.md`** — pre-install stack rationale.

**When `cachyos-hyprland-setup.md` conflicts with `ACTUAL-CONFIGURATION.md`, the latter wins.** Common stale claims in the older docs:

- "SDDM is the display manager" / "plasma-login-manager is the display manager" — neither is. SDDM isn't installed; `plasmalogin.service` is installed but **disabled and inactive** since 2026-05-22 (`finish-installation-commands.md` §10 disabled it to fix the phantom-cursor handoff bug). Current boot path: `getty@tty1` autologin (`/etc/systemd/system/getty@tty1.service.d/override.conf`) → fish login shell → `~/.config/fish/conf.d/99-hyprland-autostart.fish` → `exec start-hyprland`. `/etc/sddm.conf` is a leftover stub; any "force SDDM X11" instructions are irrelevant.
- Hyprpaper config using flat `wallpaper = ...` lines — current installed version (0.8.4) has a parser bug requiring **block syntax** (see `configs/hypr/hyprpaper.conf` and the comment in section 15 of `ACTUAL-CONFIGURATION.md`).
- "Exit Hyprland returns to SDDM" / "returns to plasma-login-manager greeter" — no longer true. Exiting Hyprland (`Super+Shift+Q`) drops back to tty1, where `getty` immediately re-autologins and the fish snippet re-`exec start-hyprland`'s. So `Super+Shift+Q` behaves like "restart compositor". To actually log out: `Ctrl+Alt+F2` to tty2, then `loginctl terminate-user isalgado`.

## Hyprland config architecture

`configs/hypr/hyprland.conf` is a thin entrypoint that **sources modular files**:

```
hyprland.conf  → env.conf → monitors.conf → input.conf → look.conf
              → keybindings.conf → windowrules.conf → autostart.conf
```

Plus three sibling daemons with their own configs: `hyprpaper.conf`, `hyprlock.conf`, `hypridle.conf`.

When editing Hyprland behavior, find the right modular file rather than dumping everything into `hyprland.conf`. The three most-edited files are documented in §11 of `shorcuts.md`: `keybindings.conf`, `monitors.conf`, `autostart.conf`.

## Working with config changes

The `configs/` directory is a **mirror**, not the live config. After editing a file in this repo:

```bash
cp configs/hypr/<file>.conf ~/.config/hypr/<file>.conf   # push to live
hyprctl reload                                           # apply without logout
```

To pull live → repo (e.g., after editing in place):

```bash
cp ~/.config/hypr/<file>.conf configs/hypr/<file>.conf
```

There is no sync automation — keep both in step manually, or the docs will drift from reality.

`hyprctl reload` re-reads all sourced files. It does **not** reload `hyprpaper`, `hypridle`, or `hyprlock` — those are separate daemons and need to be restarted individually (e.g., `pkill hyprpaper; hyprpaper & disown`).

## Hardware / boot constraints to remember

These are easy to break and hard to debug:

- **NVIDIA + Wayland requires KMS.** Kernel cmdline must contain `nvidia-drm.modeset=1 nvidia_drm.fbdev=1`. Without it, Hyprland black-screens.
- **Bootloader is Limine, not GRUB.** Persistent cmdline edits go in `/etc/default/limine`, then `sudo limine-mkinitcpio`. Direct edits to `/boot/limine.conf` get wiped by `limine-mkinitcpio-hook` and `limine-snapper-sync` on the next kernel update or snapshot.
- **The LTS kernel entry is still missing the NVIDIA modeset params** (open issue per `ACTUAL-CONFIGURATION.md` §15). Booting `linux-cachyos-lts` will black-screen Hyprland until that's fixed.
- **`hyprpolkitagent` binary is not on `$PATH`** — it lives at `/usr/lib/hyprpolkitagent/hyprpolkitagent`. `autostart.conf` invokes it via `systemctl --user start hyprpolkitagent.service`.
- **Hardware cursor is disabled** in `look.conf` (`cursor.no_hardware_cursors = true`) to avoid NVIDIA artifacts. Don't re-enable without testing.
- **`env.conf` carries the NVIDIA/Qt/Wayland env vars** (`LIBVA_DRIVER_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `NVD_BACKEND=direct`, `MOZ_ENABLE_WAYLAND=1`, `ELECTRON_OZONE_PLATFORM_HINT=auto`). Removing any of these may break VAAPI, Electron apps, or Firefox on Wayland.

## Monitor layout (left-to-right)

```
eDP-1 (laptop, 0–2048px, scale 1.25, 240Hz)
DP-1  (Samsung, 2048–3968px, scale 1.00, 120Hz)   ← primary, workspace 1 lives here
DP-2  (HDMI right, 3968–6016px, scale 1.25, 120Hz)
```

Workspace-to-monitor mapping in `monitors.conf`: WS 1–3 → DP-1, 4–5 → eDP-1, 6–9 → DP-2.

## Conventions when updating docs

- Dates in this repo are in the **2026** timeline (per `ACTUAL-CONFIGURATION.md` snapshot date 2026-05-21). Don't "correct" them to a past year.
- When changing live state (new package, new daemon, new monitor), update **`ACTUAL-CONFIGURATION.md`** — it's the snapshot doc — not the older install guide.
- The `## Outstanding Issues` table in `ACTUAL-CONFIGURATION.md` §15 is the running todo list. Move items to ✅ when resolved; don't delete them silently.
