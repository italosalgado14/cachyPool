# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`cachyPool` is **not a software project** — it's a documentation + dotfiles repository for a single machine (Acer Predator PT516-52s, hostname `triton500se`) running **CachyOS + Hyprland on Wayland with NVIDIA**. There is no build, test, or lint pipeline.

It contains:
- Markdown docs that describe and audit the live system state.
- `configs/` — a mirror of live dotfiles (`~/.config/hypr/`, `~/.config/waybar/`, `~/.config/kitty/`) so they can be version-tracked.

The repo is a git repository (branch `main`).

## Source-of-truth hierarchy

The docs were written at different times and **disagree with each other**. Trust them in this order:

1. **`ACTUAL-CONFIGURATION.md`** — most recent (snapshot 2026-05-21, §3/§15 updated through 2026-07-02), generated from a live system scan. This is the authoritative snapshot of installed packages, kernel state, NVIDIA stack, monitors, and outstanding issues.
2. **`shortcuts.md`** — day-to-day usage reference. Combined cheatsheet + full keybinding tables + workflows + Walker/Yazi/Kitty deep-dives + troubleshooting. Pulled from `configs/hypr/keybindings.conf`. **Merged 2026-05-23** from the previous split between `shortcuts.md` (one-page cheatsheet) and `USABILITY.md` (full reference); `USABILITY.md` no longer exists.
3. **`bluetooth.md`** — Bluetooth pairing + audio runbook (Sony WH-1000XM4). Authoritative for the Bluetooth stack; written 2026-08-20 after the `br-connection-key-missing` half-bond failure. Covers the diagnosis, the re-pair procedure (discovery must be live in the same `bluetoothctl` session), and why LDAC is unavailable.
4. **`system-state-findings.md`** — audit comparing the planned setup against reality. Marks what's working vs. broken.
5. **`finish-installation-commands.md`** — remediation steps for items flagged in the findings.
6. **`cachyos-hyprland-setup.md`** — original install plan (May 2026). Now partially stale.
7. **`spected-installation.md`** — pre-install stack rationale.

**When `cachyos-hyprland-setup.md` conflicts with `ACTUAL-CONFIGURATION.md`, the latter wins.** Common stale claims in the older docs:

- "SDDM is the display manager" / "plasma-login-manager is the display manager" — neither is. SDDM isn't installed; `plasmalogin.service` is installed but **disabled and inactive** since 2026-05-22 (`finish-installation-commands.md` §10 disabled it to fix the phantom-cursor handoff bug). Current boot path: `getty@tty1` autologin (`/etc/systemd/system/getty@tty1.service.d/override.conf`) → fish login shell → `~/.config/fish/conf.d/99-hyprland-autostart.fish` → `exec start-hyprland`. `/etc/sddm.conf` is a leftover stub; any "force SDDM X11" instructions are irrelevant.
- Hyprpaper config using flat `wallpaper = ...` lines — current installed version (0.8.4) has a parser bug requiring **block syntax** (see `configs/hypr/hyprpaper.conf` and the comment in section 15 of `ACTUAL-CONFIGURATION.md`).
- "Exit Hyprland returns to SDDM" / "returns to plasma-login-manager greeter" — no longer true. Exiting Hyprland (`Super+Shift+Q`) drops back to tty1, where `getty` immediately re-autologins and the fish snippet re-`exec start-hyprland`'s. So `Super+Shift+Q` behaves like "restart compositor". To actually log out: `Ctrl+Alt+F2` to tty2, then `loginctl terminate-user isalgado`.
- "VA-API runs through the NVIDIA driver" (`LIBVA_DRIVER_NAME=nvidia` + `libva-nvidia-driver` + `NVD_BACKEND=direct`) — rerouted 2026-07-02 to the iGPU's iHD driver after the Firefox-freeze incident; the shim package is dropped. Firefox additionally has hardware video decode paused via profile `user.js` until the i915 hang-recovery bug in kernel 7.0.12 is fixed (`finish-installation-commands.md` §12).

## Hyprland config architecture

`configs/hypr/hyprland.conf` is a thin entrypoint that **sources modular files**:

```
hyprland.conf  → env.conf → monitors.conf → input.conf → look.conf
              → keybindings.conf → windowrules.conf → autostart.conf
```

Plus three sibling daemons with their own configs: `hyprpaper.conf`, `hyprlock.conf`, `hypridle.conf`.

When editing Hyprland behavior, find the right modular file rather than dumping everything into `hyprland.conf`. The three most-edited files are documented in §11 of `shortcuts.md`: `keybindings.conf`, `monitors.conf`, `autostart.conf`.

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

`configs/` also mirrors two **system** paths: `configs/systemd/logind.conf.d/` → `/etc/systemd/logind.conf.d/` and `configs/modprobe.d/` → `/etc/modprobe.d/`. Push those with `sudo install -Dm644 <repo file> <live path>`. Always check the live copy exists before trusting the repo: the logind lid drop-in sat in the repo from 2026-07-12 to 2026-10-12 without ever being installed, while the docs described it as live (`finish-installation-commands.md` §15).

`hyprctl reload` re-reads all sourced files. It does **not** reload `hyprpaper`, `hypridle`, or `hyprlock` — those are separate daemons and need to be restarted individually (e.g., `pkill hyprpaper; hyprpaper & disown`).

## Hardware / boot constraints to remember

These are easy to break and hard to debug:

- **NVIDIA + Wayland requires KMS.** Satisfied since the 610-series driver by the driver-default `modeset` plus early module loading via `/etc/mkinitcpio.conf.d/10-chwd.conf` (`MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)`) — the kernel cmdline no longer carries `nvidia-drm.modeset=1` (verified 2026-07-02). The mechanism is kernel-agnostic (covers the LTS entry too). If KMS ever breaks, Hyprland black-screens.
- **The compositor and all three monitors run on the Intel iGPU** (aquamarine primary = `card2`/i915, renderer on `renderD129`). The NVIDIA dGPU is offload-only, and its GSP firmware often fails to re-init after suspend/resume, leaving the dGPU dead until reboot (`ACTUAL-CONFIGURATION.md` §15). Don't design anything that assumes the dGPU renders the session or is always available.
- **Bootloader is Limine, not GRUB.** Persistent cmdline edits go in `/etc/default/limine`, then `sudo limine-mkinitcpio`. Direct edits to `/boot/limine.conf` get wiped by `limine-mkinitcpio-hook` and `limine-snapper-sync` on the next kernel update or snapshot.
- **The LTS kernel entry** (`linux-cachyos-lts 6.18.35`) is the escape hatch for bleeding-edge kernel bugs (e.g. the i915 hang-recovery NULL deref in 7.0.12 — `ACTUAL-CONFIGURATION.md` §15). The old "LTS missing NVIDIA modeset params" worry is obsolete (see the KMS bullet), but the entry hasn't been boot-tested — verify its cmdline carries `thunderbolt.host_reset=0` and `mem_sleep_default=s2idle` before relying on it.
- **`hyprpolkitagent` binary is not on `$PATH`** — it lives at `/usr/lib/hyprpolkitagent/hyprpolkitagent`. `autostart.conf` invokes it via `systemctl --user start hyprpolkitagent.service`.
- **Battery: replacement pack fitted 2026-10-31 (Getac `AP20BHU`, 0 cycles). The 80% charge cap is installed and PROVEN** — charging stopped at exactly 80% with AC connected (`BAT1/status` = `Not charging`, upower `pending-charge`, 0 W). The in-kernel `acer_wmi` has no charge-limit support and BAT1 exposes no `charge_control_*` node, so TLP/powerdevil thresholds do nothing here; TLP isn't installed. The cap comes from AUR `acer-wmi-battery-dkms`, which drives Acer's battery-health WMI GUID, plus `enable_health_mode=1` in `/etc/modprobe.d/acer-wmi-battery.conf` (mirrored in `configs/modprobe.d/`). The main kernel is clang-built (ThinLTO), so DKMS needs clang/lld/llvm; the `cachyos` repo's `dkms` depends on them. ⚠ With `BAT1` back, hypridle's battery-only suspend and lid-close-on-battery are **armed again** for the first time since 2026-10-12 — that is the NVIDIA GSP resume-crash path. See `finish-installation-commands.md` §14 and `ACTUAL-CONFIGURATION.md` §15.
- **Fans and the platform profile only exist because of a forced module parameter.** `/etc/modprobe.d/acer-wmi-predator-v4.conf` sets `options acer_wmi predator_v4=1` (mirrored in `configs/modprobe.d/`). The PT516-52s is absent from the in-kernel driver's DMI quirk table, so without it `acer_wmi` selects no quirk and there is **no** `acer` hwmon and **no** `/sys/firmware/acpi/platform_profile`. With it: `fan1_input`/`fan2_input` (lm_sensors chip `acer-isa-0ace`) and a 5-state platform profile. It gives fan *reading* only — the quirk sets `.hwmon` but not `.pwm` — and no keyboard RGB. The parameter is `0444`, settable only at module load. After changing it, **restart `power-profiles-daemon`**: it probes platform drivers once at startup. Added 2026-10-31, `finish-installation-commands.md` §17.
- **Hardware cursor is disabled** in `look.conf` (`cursor.no_hardware_cursors = true`) to avoid NVIDIA artifacts. Don't re-enable without testing.
- **`env.conf` carries the GPU/Wayland env vars** (`LIBVA_DRIVER_NAME=iHD` — VA-API on the Intel iGPU since 2026-07-02, was `nvidia`; `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `MOZ_ENABLE_WAYLAND=1`, `ELECTRON_OZONE_PLATFORM_HINT=auto`). ⚠ `env =` lines only reach processes Hyprland spawns (keybinds/`exec-once`) — Walker/Elephant launches apps from the systemd `--user` manager, which never sees them. Never rely on env.conf to configure a Walker-launched app; that's why Firefox's video-decode pause lives in its profile `user.js` (`finish-installation-commands.md` §12), not here. The same gap hid `XDG_SESSION_TYPE=wayland` from Walker-launched apps (Hyprland's own systemd env import skips it), which kept Electron apps on XWayland and broke Discord's portal screen share. Since 2026-09-28 `autostart.conf` pushes it with `dbus-update-activation-environment --systemd XDG_SESSION_TYPE` before starting elephant (`ACTUAL-CONFIGURATION.md` §15).

## Monitor layout (left-to-right)

Static 3-across `desktop` profile, in **logical** pixels (re-fitted for the Xiaomi 2026-08-03):

```
eDP-1                    (laptop 16",     0–2048px,    scale 1.25, 240Hz)
desc:Xiaomi …Mi Monitor  (27" 4K,      2048–5120px,    scale 1.25,  60Hz)  ← primary, workspace 1
desc:Invalid Vendor …RTK (portable QHD 16", 5120–7168px, scale 1.25, 120Hz)
```

The portable is a **VCHANCE AQ16H** (16" 2560×1600@120, native). Its Realtek scaler
publishes no vendor string, which is why it appears as `Invalid Vendor Codename - RTK
HDMI 0x01010101` — that junk string is the `desc:` match key, and the serial is a
placeholder that can't disambiguate.

**Never bind anything to `DP-1`/`DP-2`.** Both externals are DP tunnels over one Thunderbolt
connector (Plugable TBT4-UD5), so whichever trains first takes the low number — the Xiaomi is
*currently* `DP-2` and the portable is `DP-1`, the reverse of what the names suggest. Since
2026-08-03 `monitors.conf` matches monitors **and workspaces** by EDID `desc:` (a prefix
match), and every profile in `monitor-mode.sh` resolves panels by capability. The old
name-bound rules had silently put workspaces 1–3 on the 16" portable.

Workspace-to-monitor mapping in `monitors.conf`: WS 1–3 → Xiaomi (primary), 4–5 → eDP-1,
6–9 → portable QHD. Check live descriptions before editing:
`hyprctl monitors -j | jq -r '.[] | "\(.name) = \(.description)"'`.

`monitor-autoswitch.sh` is **debounced** — it coalesces a hotplug burst and requires the
monitor set to hold still before applying a profile, so a display blink can't reshuffle the
layout. Don't reintroduce a per-event `sleep`-and-apply loop. See `ACTUAL-CONFIGURATION.md`
§1 / §11 / §15.

**Never set a monitor `transform` with a bare `hyprctl keyword monitor` on an output that
is already enabled.** Hyprland rotates the render pass but keeps the old layout box, so the
tiling engine hands out landscape geometry on a portrait panel (and vice versa) while
`hyprctl monitors` reports the new transform — it looks correct and isn't. Go through
`apply_monitor_tf()` in `monitor-mode.sh`, which cycles the output (disable → re-enable, the
only thing that rebuilds the box) when the transform actually changes. That cycle emits
external hotplug events, so it is paired with a fingerprint handshake that keeps
`monitor-autoswitch.sh` from reverting a manual `Super+M` choice — if you touch either
script, keep both halves in step. Fixed 2026-08-04; see `ACTUAL-CONFIGURATION.md` §11 / §15.

**Profile geometry can come from Hyprmon (since 2026-10-15).** `apply_from_profile` in
`monitor-mode.sh` applies `~/.config/hyprmon/profiles/<mode>.json` (mirrored in
`configs/hyprmon/profiles/`) when its monitors, matched by EDID `hardware_id`, are exactly
the connected set. Otherwise the hand-written `apply_<mode>` runs. Hyprmon (AUR
`hyprmon-bin`; plain `hyprmon` is an unrelated project) is only the **editor**: launch it
through `scripts/hyprmon-edit.sh` and save with `P`. Never use `hyprmon --profile` or its
`S` key: they set transforms with a bare keyword, rewrite `hyprland.conf` and
`hyprctl reload`. Also: any write to a sourced Hyprland `.conf` auto-reloads Hyprland, which
snaps the screens to `monitors.conf`'s boot geometry, so re-apply the current profile after
pushing configs. `Super+Shift+M` opens the Monitors menu (`scripts/monitor-menu.sh`).
See `finish-installation-commands.md` §16.

## Conventions when updating docs

- Dates in this repo are in the **2026** timeline (per `ACTUAL-CONFIGURATION.md` snapshot date 2026-05-21). Don't "correct" them to a past year.
- When changing live state (new package, new daemon, new monitor), update **`ACTUAL-CONFIGURATION.md`** — it's the snapshot doc — not the older install guide.
- The `## Outstanding Issues` table in `ACTUAL-CONFIGURATION.md` §15 is the running todo list. Move items to ✅ when resolved; don't delete them silently.
