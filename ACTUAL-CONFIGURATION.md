# Actual System Configuration

**Snapshot date:** 2026-05-21
**Hostname:** triton500se
**User:** isalgado

This is an honest dump of the current state of the machine: hardware, OS, kernel, all installed software groups, services, configs, and the live Hyprland session. Use it as a reference snapshot before/after big changes and as a basis for replicating this setup elsewhere.

> Live config files are mirrored in `configs/` in this repo so they can be tracked in git.

---

## 1. Hardware

| Component | Spec |
|---|---|
| Model | Acer Predator PT516-52s (Triton 500 SE) |
| CPU | 12th Gen Intel Core i9-12900H (20 logical CPUs, Alder Lake) |
| iGPU | Intel Iris Xe Graphics |
| dGPU | NVIDIA GeForce RTX 3080 Ti Laptop GPU (16 GB) |
| RAM | 31 GiB DDR5 |
| Disk 1 | `nvme0n1` 953.9 GiB — CachyOS root (btrfs `/home`) + EFI (vfat `/boot`) |
| Disk 2 | `nvme1n1` 953.9 GiB — leftover Windows EFI/MSR/NTFS + old Ubuntu ext4 (unmounted, reclaim candidate) |
| Swap | 31 GiB zram (`zram0`) |
| Backlight | `nvidia_wmi_ec_backlight` (255 max, currently ~77/30%) |

### Display setup (live from `hyprctl monitors`)

| Output | Model | Native | Scale | Effective | Position | Rate |
|---|---|---|---|---|---|---|
| `eDP-1` | BOE 0x0AB5 (built-in 16") | 2560×1600 | 1.25 | 2048×1280 | `0×0` | 240 Hz |
| `DP-1` | Samsung LS24F32xG | 1920×1080 | 1.00 | 1920×1080 | `2048×0` | 120 Hz |
| `DP-2` | HDMI (RTK adapter) | 2560×1600 | 1.25 | 2048×1280 | `3968×0` | 120 Hz |

Total virtual desktop width: **6016 px**. No overlap, no gap.

---

## 2. Operating System

| Item | Value |
|---|---|
| Distro | CachyOS Linux (rolling, Arch-based) |
| Kernel (running) | `7.0.9-1-cachyos` (BORE scheduler, performance-tuned) |
| Kernel (fallback) | `linux-cachyos-lts 6.18.32-1` |
| Architecture | x86_64 |
| Bootloader | **Limine** (not GRUB) |
| EFI partition | `/dev/nvme0n1p1` 4 GiB vfat at `/boot` |
| Root subvolume | `subvol=/@` on `nvme0n1p2` btrfs |
| Init | systemd |
| Boot time | ~22s total (5s firmware / 3.5s loader / 0.9s kernel / 3s initrd / 9.5s userspace) |
| Display manager | **plasma-login-manager** (PlasmaLogin) — NOT SDDM. Active, enabled, autologin `Session=plasma` (overridden by Hyprland selection at greeter). |
| Session type | Wayland |
| Desktop env | Hyprland (with KDE Plasma as installer-bundled fallback) |
| Shell | `/usr/bin/zsh` (current shell; fish, bash, zsh all installed) |
| Audio | PipeWire 1.6.5 with `pipewire-pulse` and `wireplumber`; default sink: Samson Go Mic USB |

### Kernel command line

```
quiet nowatchdog splash rw rootflags=subvol=/@
root=UUID=d94a3435-f8db-4cc2-ade4-4ed01417dfd2
nvidia-drm.modeset=1 nvidia_drm.fbdev=1
```

> **Note:** `linux-cachyos-lts` entry in `/boot/limine.conf` does NOT have `nvidia-drm.modeset=1` — booting LTS will black-screen on Hyprland. Persistent fix lives in `/etc/default/limine`; see section 0 of `finish-installation-commands.md`.

---

## 3. NVIDIA Stack

| Item | Value |
|---|---|
| Driver | 595.71.05 (proprietary, via `linux-cachyos-nvidia-open`) |
| Kernel modules loaded | `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm` |
| Module package | `linux-cachyos-nvidia-open 7.0.9-1` (CachyOS-specific; not `nvidia-dkms`) |
| Userspace | `nvidia-utils 595.71.05-1`, `lib32-nvidia-utils`, `libva-nvidia-driver`, `egl-wayland` |
| KMS | ✅ enabled (`nvidia-drm.modeset=1`) |
| Hardware cursor | disabled in Hyprland config (`cursor.no_hardware_cursors = true` to avoid NVIDIA artifacts) |
| Wayland env vars (set in `env.conf`) | `LIBVA_DRIVER_NAME=nvidia`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`, `NVD_BACKEND=direct`, `MOZ_ENABLE_WAYLAND=1`, `ELECTRON_OZONE_PLATFORM_HINT=auto` |

---

## 4. Installed Packages — Hyprland Ecosystem

| Package | Version | Role |
|---|---|---|
| `hyprland` | 0.55.2-1.1 | Compositor (Wayland) |
| `hyprlock` | 0.9.5-3.1 | Lock screen |
| `hypridle` | 0.1.7-9.1 | Idle / lock / suspend daemon |
| `hyprpaper` | 0.8.4-1.1 | Wallpaper daemon |
| `hyprpolkitagent` | 0.1.3-7.1 | PolicyKit auth agent (binary at `/usr/lib/hyprpolkitagent/`) |
| `hyprshutdown` | 0.1.1-2.1 | Power menu helper |
| `xdg-desktop-portal-hyprland` | 1.3.12-2.1 | Portal (screensharing/file pickers) |

## 5. Installed Packages — UI / Daemons / Tools

| Package | Version | Role |
|---|---|---|
| `waybar` | 0.15.0-2.1 | Status bar |
| `mako` | 1.11.0-1.1 | Notifications |
| `kitty` | 0.46.2-1.2 | Terminal |
| `walker` | 2.16.2-1 | App launcher + provider hub (Elephant) |
| `yazi` | 26.5.6-2.1 | TUI file manager |
| `swayosd` | 0.3.1-1.1 | Volume/brightness on-screen popups |
| `grim` | 1.5.0-2.1 | Wayland screenshot tool |
| `slurp` | 1.5.0-2.1 | Region selection |
| `satty` | 0.20.1-2.2 | Screenshot annotation |
| `wl-clipboard` | 2.3.0-1.1 | Wayland clipboard |
| `cliphist` | 0.7.0-2.1 | Clipboard history store |
| `brightnessctl` | 0.5.1-3 | CLI backlight control |
| `pavucontrol` | 6.2-1.1 | Audio mixer GUI |
| `playerctl` | 2.4.1-5.1 | Media key dispatcher |
| `network-manager-applet` | 1.36.0-2.1 | NetworkManager tray icon |
| `blueman` | 2.4.6-2.1 | Bluetooth tray + GUI |
| `bluez` / `bluez-utils` | 5.86-6.1 | Bluetooth stack |

## 6. Installed Packages — Fonts / Themes

| Package | Version |
|---|---|
| `ttf-jetbrains-mono-nerd` | 3.4.0-2 |
| `noto-fonts` | 2026.05.01-1 |
| `noto-fonts-emoji` | 2.051-1 |
| `noto-fonts-cjk` | 20240730-1 |
| `papirus-icon-theme` | 20250501-1 |
| `qt5-wayland` | 5.15.18-1.1 |
| `qt6-wayland` | 6.11.1-1.1 |
| `qt6ct` | 0.11-6.1 |
| `kvantum` | 1.1.7-1.1 |

## 7. Installed Packages — Editors / File Managers / Browser

| Package | Version | Notes |
|---|---|---|
| `visual-studio-code-bin` | 1.121.0-1 | Primary editor (runs on Wayland) |
| `micro` | 2.0.15-2.1 | Terminal text editor (Yazi's default for text files) |
| `dolphin` | 26.04.1-1.1 | KDE file manager (GUI fallback) |
| `firefox` | 150.0.3-1 | Default browser |

> Not installed: `neovim`, `ghostty` (Ghostty is in CachyOS repos if you want to swap in for Kitty later).

## 8. Installed Packages — Boot / Snapshots / Power

| Package | Version | Role |
|---|---|---|
| `limine` | 11.4.1-1 | Bootloader |
| `limine-mkinitcpio-hook` | 1.36.0-1 | Auto-regenerates `/boot/limine.conf` on kernel updates |
| `limine-snapper-sync` | 1.29.0-1 | Adds snapper snapshots as bootable Limine entries |
| `snapper` | 0.13.1-2.1 | btrfs snapshot manager (root config: `root`) |
| `snap-pac` | 3.0.1-3 | Automatic snapshots on pacman transactions |
| `btrfs-progs` | 7.0-1 | btrfs userspace tools |
| `plymouth` | 24.004.60-14.1 | Boot splash (in mkinitcpio `HOOKS` — **TODO: remove for Thunderbolt boot fix**) |
| `power-profiles-daemon` | 0.30-3 | Power profile switching (not TLP, not auto-cpufreq) |

## 9. Installed Packages — Counts

- **Explicitly installed (user-requested):** 251
- **Total installed (with dependencies):** 1304

Get the full explicit list with `pacman -Qe`. Get only foreign packages (AUR/manual) with `pacman -Qm`.

---

## 10. Running Daemons (live)

Captured via `pgrep -af`:

| Daemon | Started via |
|---|---|
| `waybar` | `exec-once = waybar` (autostart.conf) |
| `mako` | `exec-once = mako` |
| `hyprpaper` | `exec-once = hyprpaper` |
| `hypridle` | `exec-once = hypridle` |
| `hyprpolkitagent` | `exec-once = systemctl --user start hyprpolkitagent.service` |
| `swayosd-server` | `exec-once = swayosd-server` |
| `wl-paste --type text --watch cliphist store` | autostart |
| `wl-paste --type image --watch cliphist store` | autostart |
| `nm-applet --indicator` | autostart |
| `walker --gapplication-service` | autostart (resident service for fast launches) |
| `polkitd` | system (PolicyKit daemon) |
| `xdg-desktop-portal` + `xdg-desktop-portal-hyprland` | systemd user units |
| `pipewire`, `pipewire-pulse`, `wireplumber` | systemd user units (audio) |

All Hyprland-side autostarts are live and producing visible output (bar, wallpaper, tray icons).

---

## 11. Hyprland Config Layout

All under `~/.config/hypr/` and mirrored in this repo at `configs/hypr/`:

```
hyprland.conf      ← entrypoint, sources the others
env.conf           ← NVIDIA + Qt + cursor env vars
monitors.conf      ← 3-monitor layout, scale 1.25 on 2560×1600 outputs
input.conf         ← keyboard layout, touchpad, 3-finger gesture
look.conf          ← Catppuccin Mocha colors, dwindle, animations, blur+shadow
keybindings.conf   ← every shortcut (see USABILITY.md)
windowrules.conf   ← floats for dialogs (pavucontrol, blueman, polkit, PiP)
autostart.conf     ← exec-once for all daemons
hyprpaper.conf     ← block-syntax wallpaper bindings (workaround for 0.8.4 parser bug)
hyprlock.conf      ← Catppuccin password input + big clock + blurred wallpaper
hypridle.conf      ← 5m lock / 10m DPMS / 20m suspend
```

## 12. Other Configs

```
~/.config/waybar/config.jsonc   ← bar layout + module configs (Catppuccin colors)
~/.config/waybar/style.css      ← bar CSS (purple workspace highlight, JetBrainsMono)
~/.config/kitty/kitty.conf      ← JetBrainsMono 12pt, 0.95 opacity, includes Catppuccin theme
~/.config/kitty/themes/Catppuccin-Mocha.conf  ← official Catppuccin theme file
~/.config/walker/               ← EMPTY (using upstream defaults — Omarchy pattern)
~/.config/yazi/                 ← EMPTY (using upstream defaults — image previews via Kitty auto-detected)
~/.config/mako/                 ← EMPTY (using upstream defaults)
~/.config/fish/                 ← shell config exists (config.fish, conf.d/, functions/)
```

---

## 13. Bootloader Detail (Limine + Snapper)

- Limine reads `/boot/limine.conf` (root-readable only).
- `limine-mkinitcpio-hook` regenerates entries when a kernel/initramfs changes.
- `limine-snapper-sync` adds bootable entries for each btrfs snapshot under `subvol=/@/.snapshots/<N>/snapshot`.
- Persistent kernel cmdline params live in `/etc/default/limine` (preferred) — direct edits to `/boot/limine.conf` are wiped on next regen.
- Current entries (live snapshot):
  - `linux-cachyos` — has `nvidia-drm.modeset=1 nvidia_drm.fbdev=1` ✅
  - `linux-cachyos-lts` — MISSING modeset params ⚠ (would black-screen Hyprland)
  - Snapshots 7–12: same pattern (main has modeset, LTS doesn't)
  - Snapshot 6: pre-`cachyos-chwd` baseline (neither kernel has modeset)

---

## 14. Display Manager Reality Check

- The plan in `cachyos-hyprland-setup.md` section 7 talks about forcing **SDDM** into X11 mode.
- **SDDM is NOT installed/enabled.** This system uses **plasma-login-manager** (`plasmalogin.service`) instead.
- The SDDM X11 workaround is therefore irrelevant; `/etc/sddm.conf` is a leftover stub.

---

## 15. Outstanding Issues

These are tracked in `system-state-findings.md` and `finish-installation-commands.md` (where applicable). Status as of this snapshot:

| Item | Status |
|---|---|
| Hyprland NVIDIA black-screen | ✅ Resolved (KMS + env vars) |
| Hyprland autostart daemons | ✅ All running (polkit fixed via systemd unit; hypridle started; nm-applet installed) |
| Waybar Catppuccin config | ✅ Applied (`~/.config/waybar/config.jsonc` + `style.css`) |
| Hyprpaper wallpaper binding | ✅ Resolved via block syntax (workaround for 0.8.4 config parser bug — see GitHub hyprwm/hyprpaper#204 + Arch forum thread) |
| Hyprlock styling | ✅ Catppuccin theme applied |
| Hypridle timeouts | ✅ Configured (5/10/20 min) |
| qt6ct env var | ✅ Package installed, env var valid |
| Kitty Catppuccin theme | ✅ Applied |
| Yazi config | ✅ Working on defaults (no custom config needed; image previews via Kitty auto-detected) |
| Walker config | ✅ Working on defaults (Omarchy pattern); `Super+Ctrl+E` symbols, `Super+Ctrl+V` clipboard |
| HiDPI scaling | ✅ Scale 1.25 on eDP-1 and DP-2; positions recalculated |
| LTS kernel cmdline | ⚠ Still missing `nvidia-drm.modeset=1` on `linux-cachyos-lts` entry |
| Thunderbolt boot hang | ⚠ NOT FIXED — Plymouth still in `HOOKS=`; cmdline still has `quiet splash`; no `pcie_aspm=off` or `thunderbolt.host_reset=0` (planned for next day) |
| Leftover Windows/Ubuntu partitions | ⚠ `nvme1n1p3` (NTFS 559 GiB) + `nvme1n1p4` (ext4 393 GiB) still present, unmounted, reclaim candidates |
| SDDM X11 workaround | N/A — plasma-login-manager is in use instead |

---

## 16. Repo Layout

```
cachyPool/
├── cachyos-hyprland-setup.md          ← original install guide (May 2026)
├── spected-installation.md            ← expected/recommended stack
├── system-state-findings.md           ← scan report after install
├── finish-installation-commands.md    ← step-by-step remediation
├── USABILITY.md                       ← daily shortcuts + workflows
├── ACTUAL-CONFIGURATION.md            ← this file
└── configs/                           ← live copies of all dotfiles
    ├── hypr/
    │   ├── autostart.conf
    │   ├── env.conf
    │   ├── hypridle.conf
    │   ├── hyprland.conf
    │   ├── hyprlock.conf
    │   ├── hyprpaper.conf
    │   ├── input.conf
    │   ├── keybindings.conf
    │   ├── look.conf
    │   ├── monitors.conf
    │   └── windowrules.conf
    ├── waybar/
    │   ├── config.jsonc
    │   └── style.css
    └── kitty/
        ├── kitty.conf
        └── themes/
            └── Catppuccin-Mocha.conf
```

---

## 17. How to Replicate This Setup Elsewhere

If you ever rebuild this machine (or set up a second one), the minimal sequence:

1. Install CachyOS, pick **Hyprland + KDE-Desktop**, btrfs, Limine.
2. Boot, run `sudo cachyos-chwd -a` to install NVIDIA correctly.
3. Verify `cat /proc/cmdline | grep modeset` shows `nvidia-drm.modeset=1`. If not, add via `/etc/default/limine` + `sudo limine-mkinitcpio`.
4. Install the full Hyprland stack (see section 4–8 above, or `cachyos-hyprland-setup.md` section 4).
5. Restore dotfiles: `cp -r configs/hypr ~/.config/`, same for `waybar/` and `kitty/`.
6. Wallpaper: `mkdir -p ~/Pictures/Wallpapers && cp wall.jpg ~/Pictures/Wallpapers/` (or download from a Catppuccin wallpaper repo).
7. Log out → at the PlasmaLogin greeter, pick Hyprland session → log in.
8. Verify: `hyprctl version`, `hyprctl monitors`, `nvidia-smi`.
9. The autostart entries in `~/.config/hypr/autostart.conf` bring up bar, wallpaper, notifications, polkit, clipboard, network/BT tray, and the walker resident service automatically.

---

*Generated 2026-05-21 from live system scan. Update this file whenever a major change lands (kernel upgrade, new daemon, new monitor, etc.) by re-running the verification block in section 10 of `finish-installation-commands.md`.*
