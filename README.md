# cachyPool

Documentation and dotfiles for a single machine: an **Acer Predator PT516-52s** (Triton 500 SE, hostname `triton500se`) running **CachyOS + Hyprland on Wayland with an NVIDIA RTX 3080 Ti**.

This is **not a software project** — there is no build, test, or lint pipeline. It's a version-tracked record of how this machine is set up, what's broken, how to fix it, and how to use it day to day. The `configs/` directory mirrors the live dotfiles so they can be tracked in git.

## What's in here

```
cachyPool/
├── ACTUAL-CONFIGURATION.md        ← authoritative live-system snapshot (start here)
├── shorcuts.md                    ← daily keybindings, workflows, troubleshooting
├── system-state-findings.md       ← audit: planned setup vs. reality
├── finish-installation-commands.md← step-by-step remediation for flagged issues
├── cachyos-hyprland-setup.md      ← original install plan (now partially stale)
├── spected-installation.md        ← pre-install stack rationale
├── CLAUDE.md                      ← guidance for Claude Code working in this repo
└── configs/                       ← mirror of live dotfiles
    ├── hypr/                      ← hyprland.conf + modular sources + sibling daemons
    ├── waybar/                    ← config.jsonc + style.css
    └── kitty/                     ← kitty.conf + Catppuccin-Mocha theme
```

## Source-of-truth hierarchy

The docs were written at different times and **disagree with each other**. Trust them in this order:

1. **`ACTUAL-CONFIGURATION.md`** — most recent, generated from a live system scan. The authoritative snapshot of installed packages, kernel state, the NVIDIA stack, monitors, and outstanding issues. **When older docs conflict with this, this wins.**
2. **`shorcuts.md`** (typo intentional) — day-to-day usage reference: cheatsheet, full keybinding tables, workflows, Walker/Yazi/Kitty deep-dives, and troubleshooting.
3. **`system-state-findings.md`** — audit comparing the planned setup against reality.
4. **`finish-installation-commands.md`** — remediation steps for items flagged in the findings.
5. **`cachyos-hyprland-setup.md`** — original install plan; some claims are now stale.
6. **`spected-installation.md`** — pre-install stack rationale.

## The system at a glance

| | |
|---|---|
| Hardware | Acer Predator PT516-52s · i9-12900H · RTX 3080 Ti Laptop (16 GB) · 31 GiB DDR5 |
| OS | CachyOS (Arch-based, rolling) · kernel `7.0.9-1-cachyos` (BORE) |
| Compositor | Hyprland on Wayland (KDE Plasma installed as fallback) |
| NVIDIA | Proprietary driver 595.71.05 (`linux-cachyos-nvidia-open`), KMS enabled |
| Bootloader | **Limine** (not GRUB) · btrfs root with Snapper snapshots |
| Display manager | **None** — `getty@tty1` autologin → fish → `exec start-hyprland` |
| Shell | `/bin/fish` (login shell) |
| Theme | Catppuccin Mocha · JetBrainsMono Nerd Font |

### Monitor layout (left-to-right)

```
eDP-1 (laptop, 0–2048px,    scale 1.25, 240Hz)
DP-1  (Samsung, 2048–3968px, scale 1.00, 120Hz)  ← primary, workspace 1
DP-2  (HDMI right, 3968–6016px, scale 1.25, 120Hz)
```

Workspace mapping (`configs/hypr/monitors.conf`): WS 1–3 → DP-1, 4–5 → eDP-1, 6–9 → DP-2.

## Hyprland config architecture

`configs/hypr/hyprland.conf` is a thin entrypoint that sources modular files:

```
hyprland.conf → env.conf → monitors.conf → input.conf → look.conf
             → keybindings.conf → windowrules.conf → autostart.conf
```

Plus three sibling daemons with their own configs: `hyprpaper.conf`, `hyprlock.conf`, `hypridle.conf`. When editing behavior, find the right modular file rather than dumping everything into `hyprland.conf`.

## Working with config changes

`configs/` is a **mirror**, not the live config — there is no sync automation, so keep both in step manually.

```bash
# After editing a file in this repo, push it live and apply:
cp configs/hypr/<file>.conf ~/.config/hypr/<file>.conf
hyprctl reload

# To pull a live edit back into the repo:
cp ~/.config/hypr/<file>.conf configs/hypr/<file>.conf
```

`hyprctl reload` re-reads all sourced files but does **not** reload `hyprpaper`, `hypridle`, or `hyprlock` — those are separate daemons and must be restarted individually (e.g. `pkill hyprpaper; hyprpaper & disown`).

## Hardware / boot gotchas

These are easy to break and hard to debug:

- **NVIDIA + Wayland requires KMS** — the kernel cmdline must contain `nvidia-drm.modeset=1 nvidia_drm.fbdev=1`, or Hyprland black-screens.
- **Limine, not GRUB** — persistent cmdline edits go in `/etc/default/limine`, then `sudo limine-mkinitcpio`. Direct edits to `/boot/limine.conf` get wiped on the next kernel update or snapshot.
- The **LTS kernel entry still lacks the NVIDIA modeset params** — booting `linux-cachyos-lts` black-screens Hyprland (open issue, see `ACTUAL-CONFIGURATION.md` §15).
- **Hardware cursor is disabled** (`look.conf`) to avoid NVIDIA artifacts.
- `env.conf` carries the NVIDIA/Qt/Wayland env vars — removing any may break VAAPI, Electron apps, or Firefox on Wayland.
- **`Super+Shift+Q` restarts the compositor**, it does not log out — exiting Hyprland drops to tty1, where getty re-autologins and re-launches it. To truly log out: `Ctrl+Alt+F2`, then `loginctl terminate-user isalgado`.

## Replicating this setup

See `ACTUAL-CONFIGURATION.md` §17 for the minimal rebuild sequence. In short: install CachyOS (Hyprland + KDE, btrfs, Limine) → `sudo cachyos-chwd -a` for NVIDIA → verify KMS → install the Hyprland stack → restore `configs/` into `~/.config/` → apply `finish-installation-commands.md` §10 for the autologin boot path.

---

*Dates in this repo are in the 2026 timeline (per the `ACTUAL-CONFIGURATION.md` snapshot). When live state changes, update `ACTUAL-CONFIGURATION.md` — its §15 "Outstanding Issues" table is the running todo list.*
