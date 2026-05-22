# Hyprland Install — System State Findings

**Scan date:** 2026-05-21
**Compared against:** `cachyos-hyprland-setup.md` (planned setup) + `spected-installation.md` (expected stack)
**Currently in session:** Hyprland 0.55.2 / Wayland / kernel 7.0.9-1-cachyos / NVIDIA 595.71.05

---

## TL;DR

The base install is **working** — Hyprland is running on Wayland with NVIDIA, KMS is enabled, all three monitors are detected, the correct kernel is booted, and most packages from section 4 are installed. What's missing is mostly **userland configuration** (no waybar/mako/kitty/walker/yazi configs), a couple of **autostart entries silently failing** (hyprpolkitagent, hypridle, nm-applet), the **Plymouth/Thunderbolt boot hang fix is NOT applied**, and **SDDM is not the display manager** — plasma-login-manager is. There are also a few small discrepancies between the planned package list and what's actually on the system.

---

## ✅ What's working (no action needed)

### Kernel / NVIDIA / Wayland (section 3 of plan)
- `uname -r` = `7.0.9-1-cachyos` ✓ (not the LTS fallback — correct default booted)
- `/proc/cmdline` contains `nvidia-drm.modeset=1 nvidia_drm.fbdev=1` ✓
- `nvidia-smi` works: driver **595.71.05**, RTX 3080 Ti detected, 16 GB VRAM ✓
- Kernel modules loaded: `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm` ✓
- Session: `XDG_SESSION_TYPE=wayland`, `XDG_CURRENT_DESKTOP=Hyprland` ✓
- Hyprland version 0.55.2 (matches plan), `Hyprland --verify-config` → `config ok` ✓

### Monitors (section 5)
All three detected in correct positions at correct refresh rates:
- `eDP-1` 2560×1600 @ 240 Hz at 0×0 ✓
- `DP-1` (Samsung) 1920×1080 @ 120 Hz at 2560×0 ✓
- `DP-2` 2560×1600 @ 120 Hz at 4480×0 ✓
- Workspace mapping per `monitors.conf` matches plan ✓

### Hyprland modular config (section 5)
All eight expected `~/.config/hypr/*.conf` files exist and are populated:
`hyprland.conf, env.conf, monitors.conf, input.conf, look.conf, keybindings.conf, windowrules.conf, autostart.conf, hyprpaper.conf` ✓

### Installed packages (section 4)
All present: `hyprland, hyprlock, hypridle, hyprpaper, hyprpolkitagent, hyprshutdown, waybar, mako, kitty, walker, yazi, swayosd, grim, slurp, satty, wl-clipboard, cliphist, brightnessctl, pavucontrol, playerctl, qt5-wayland, qt6-wayland, xdg-desktop-portal-hyprland, ttf-jetbrains-mono-nerd, noto-fonts, noto-fonts-emoji, noto-fonts-cjk, papirus-icon-theme` ✓

### Running daemons
`waybar` (PID 1387), `mako` (1388), `hyprpaper` (1389), `swayosd-server` (1393), `wl-paste` x2 watchers (1394/1395), `xdg-desktop-portal-hyprland` (1497), `polkitd` (system) — all running ✓

---

## ⚠️ Needs attention — autostart entries silently failing

Three `exec-once` lines in `~/.config/hypr/autostart.conf` are NOT producing a running process:

### 1. `hyprpolkitagent` — wrong invocation (binary not in PATH)
- Package is installed, but binary is at `/usr/lib/hyprpolkitagent/hyprpolkitagent` — there is **no `hyprpolkitagent` on `$PATH`**, so `exec-once = hyprpolkitagent` silently fails.
- A systemd user unit ships with the package: `/usr/lib/systemd/user/hyprpolkitagent.service`.
- **Fix options:** either `exec-once = systemctl --user start hyprpolkitagent.service` or `exec-once = /usr/lib/hyprpolkitagent/hyprpolkitagent`.
- Impact: GUI sudo/polkit auth prompts (e.g., installing in pamac, mounting USB) currently have no agent — they fall through to whatever else is registered.

### 2. `hypridle` — no config file, daemon not running
- Binary exists at `/usr/bin/hypridle`, but `pgrep hypridle` returns nothing.
- No `~/.config/hypr/hypridle.conf` and no `~/.config/hypridle/`. Default config exists at `/usr/share/hypr/hypridle.conf` but the daemon needs its own config to do anything useful (lock timeout, suspend, dim).
- Section 14 of plan flags this as TODO ("Configure hypridle timeouts").
- Impact: lid-close / idle behavior currently uses system defaults; no auto-lock.

### 3. `nm-applet --indicator` — `network-manager-applet` not installed
- `which nm-applet` → not found. Package `network-manager-applet` is missing.
- NetworkManager itself is active and working.
- Impact: no tray icon for network in waybar. Either install the package or remove the autostart line.

### Bonus: hyprpaper running but rendering nothing
- `pgrep hyprpaper` shows it running, but `hyprctl hyprpaper listactive` returns empty.
- Cause: `hyprpaper.conf` uses `wallpaper = , ~/Pictures/Wallpapers/wall.jpg` (empty monitor field). Plan example was per-monitor (`eDP-1`, `DP-1`, `DP-2`). The wildcard form should work in recent hyprpaper, but it currently isn't binding.
- Likely fix: restart hyprpaper (`pkill hyprpaper; hyprpaper & disown`) or switch to explicit per-monitor lines like the plan shows.

---

## ⚠️ Missing userland config files (section 5–6 of plan, section 14 TODOs)

The directories exist but are empty — the apps are running on built-in defaults:

| Config | Path | State |
|---|---|---|
| Waybar | `~/.config/waybar/` | **empty** → falling back to `/etc/xdg/waybar/{config.jsonc,style.css}` (a default Arch theme, NOT the Catppuccin Mocha config in section 6 of the plan) |
| Mako | `~/.config/mako/` | empty |
| Walker | `~/.config/walker/` | empty (no plugins enabled — calc/emoji/clipboard) |
| Kitty | `~/.config/kitty/` | empty (no Catppuccin theme) |
| Yazi | `~/.config/yazi/` | does not exist |
| Hyprlock | `~/.config/hypr/hyprlock.conf` | missing — `Super+L` would launch hyprlock with system default lock screen |
| Hypridle | `~/.config/hypr/hypridle.conf` | missing — see point above |

**Priority:** Waybar is the most visible — the plan's `config.jsonc` + `style.css` from section 6 still needs to be dropped in `~/.config/waybar/`.

---

## ⚠️ Outstanding issues from the plan that are NOT yet applied

### Thunderbolt boot hang fix (section 10) — NOT APPLIED
- `/etc/mkinitcpio.conf` still contains `plymouth` in `HOOKS=(...)`:
  ```
  HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole plymouth filesystems)
  ```
- The cmdline still contains `quiet splash`, no `pcie_aspm=off`, no `thunderbolt.host_reset=0`, no `ignore_loglevel`.
- Plymouth package is installed.
- Result: TB-dock boot workaround is still "boot without dock, plug in after" per section 10.

### HiDPI scaling (section 14 TODO)
- `hyprctl monitors all` confirms all three monitors at `scale: 1.00`. Laptop text-too-small symptom from plan note (section 5, end) is still present.
- Plan suggests scale 1.6 on `eDP-1` and shifting `DP-1`/`DP-2` positions accordingly.

---

## ⚠️ Discrepancies between plan and reality (intentional or worth resolving)

### SDDM is not the display manager
- Plan section 7 says: force SDDM into X11 via `/etc/sddm.conf.d/10-wayland.conf`.
- Actual state:
  - `/etc/sddm.conf.d/` does not exist; `/etc/sddm.conf` exists but contains only `[Autologin]\nSession=plasma`.
  - `sddm.service` is **disabled + inactive**.
  - `plasmalogin.service` (from `plasma-login-manager 6.6.5-1.1`) is **enabled + active** — this is the actual greeter being used.
- So the X11-greeter workaround from the plan does not apply; the system bypasses SDDM entirely.

### Ghostty vs Kitty
- `spected-installation.md` says: **Ghostty** is the first choice, Kitty only as fallback.
- Plan section 4 says: Kitty.
- Actual state: **Kitty installed, Ghostty not installed.** Ghostty IS available in CachyOS repos (`cachyos-extra-v3/ghostty 1.3.1-2.2`). If the original preference still stands, `pacman -S ghostty` would resolve this — but the plan deliberately settled on Kitty, so this may be a closed decision.

### `qt6ct` referenced in env.conf but not installed
- `env.conf` line 12 sets `QT_QPA_PLATFORMTHEME=qt6ct`, but `pacman -Q qt6ct` → not found.
- Result: that env var points at a non-existent theme engine. Qt apps will fall back to system defaults; no visible breakage, but the line is currently inert. Install `qt6ct` or remove the env line.

### `nvidia-dkms` package not used
- Plan section 3 mentions installing `nvidia-dkms` as a fallback. CachyOS installed the kernel-module package directly: `linux-cachyos-nvidia-open 7.0.9-1` provides the modules in `/lib/modules/.../extramodules/`.
- This is fine and actually the preferred CachyOS approach (avoids DKMS rebuild overhead). Not a problem — just worth knowing if a `nvidia-dkms` lookup ever returns empty.

### `linux-cachyos-lts` is installed but no Wayland-kernel-params fix applied to it
- `linux-cachyos-lts 6.18.32-1` is present as the fallback kernel per plan section 2.
- Plan section 3 step 2 warned: `cachyos-chwd` only adds the modeset params to the main `linux-cachyos` entry, NOT the LTS one. Cannot verify the LTS entry's cmdline directly (`/boot/limine.conf` is root-readable only and the sudo prompt is non-interactive in this session) — needs `sudo cat /boot/limine.conf` to confirm whether booting into LTS would also have `nvidia-drm.modeset=1`.

### Leftover disk partitions
- `nvme1n1p4` (Ubuntu, ext4 393.8 GiB) and `nvme1n1p3` (NTFS 559.8 GiB Windows) are still present on the second NVMe. Plan section 2 says these were "deleted and reclaimed."
- They're unmounted, but not actually wiped. If reclaiming space is a goal, this is unfinished.

---

## Section-14 TODOs still open (from the plan itself)

These were already known unfinished items per the plan; current scan confirms they're untouched:

- [ ] Resolve Thunderbolt boot hang (see above)
- [ ] HiDPI scaling on `eDP-1` (still scale 1.0)
- [ ] Configure Yazi (`~/.config/yazi/` doesn't exist)
- [ ] Configure Walker plugins (no `~/.config/walker/` content)
- [ ] Add Kitty config with Catppuccin theme
- [ ] Set up hyprlock styling (no config)
- [ ] Configure hypridle timeouts (no config + daemon not running)
- [ ] Replace nm-applet with networkmanager_dmenu/rofi-network — currently nm-applet line in autostart is dead because the package isn't installed
- [ ] Set up Bluetooth indicator — `bluez`/`bluez-utils` installed but no `blueman` GUI; `windowrules.conf` already has float rules for `blueman-manager` anticipating it
- [ ] Battery/power profile management — `power-profiles-daemon 0.30-3` is installed (not `tlp` or `auto-cpufreq`); fine for laptops on Intel.
- [ ] Snapshot strategy with snapper — `snapper`, `snap-pac`, `btrfs-progs` all installed. Worth checking `/etc/snapper/configs/` to confirm a root config exists and that pacman snapshots are wired up — not verified here.

---

## Quick prioritized resolution list

If you want to "finish the install" in order of impact:

1. **Fix the three failing autostart lines** (`hyprpolkitagent` invocation, install `network-manager-applet` or remove the line, write a `hypridle.conf` or remove the line).
2. **Drop in the Waybar config** from plan section 6 (`~/.config/waybar/config.jsonc` and `style.css`) so the bar matches the planned Catppuccin look instead of the default.
3. **Restart/repair hyprpaper** so wallpapers actually render (current `wallpaper = ,` syntax isn't binding to any monitor).
4. **Fix `qt6ct` env var** — either `sudo pacman -S qt6ct` or remove the `QT_QPA_PLATFORMTHEME` line in `env.conf`.
5. **Apply Thunderbolt boot fix** (section 10) — only if the "boot without dock" workaround is still annoying.
6. **HiDPI scale** on `eDP-1` if laptop text is currently too small.
7. **Configs for kitty/walker/yazi/hyprlock/hypridle** — these are quality-of-life, not blocking.
8. **Decide Ghostty vs Kitty** once and for all; install Ghostty if the original preference still stands.
9. **Verify LTS kernel cmdline** with `sudo cat /boot/limine.conf` to make sure rebooting into LTS won't black-screen.

---

*Scan was read-only — no configuration was changed.*
