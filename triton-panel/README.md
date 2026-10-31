# triton-panel

A small GTK4/libadwaita panel for the hardware of this specific machine — Acer
Predator Triton 500 SE (`PT516-52s`, hostname `triton500se`) on CachyOS +
Hyprland. Launched from Walker; everything in one window.

Written 2026-10-31.

## Why not an existing tool

Everything interesting on this laptop sits behind the Acer EC, and no
general-purpose monitor reads it:

| tool | why it does not fit |
|---|---|
| `mission-center` | shows no fans at all — CPU/memory/disk/network/GPU only |
| `coolercontrol` | it is a fan **control** front end, and this machine has no PWM control (the `predator_v4` quirk sets `.hwmon` but not `.pwm`); it also pulls in `qt6-webengine` and a daemon |
| `psensor` | graphs RPM, but cannot touch the charge cap or the platform profile |
| `powerprofilesctl` | reaches only 3 of the 5 platform-profile states |

## What it shows

* **Temperature graph** — CPU package, the two Acer EC sensors, NVMe, and the
  dGPU when it happens to be awake.
* **Fan graph** — both fans, 5 minutes of history.
* **Load** — CPU percentage / average frequency / package temperature, memory
  with the zram figure, iGPU clock, and dGPU state.
* **Power** — the full 5-state platform profile selector, what
  power-profiles-daemon currently reports, the power source, and the
  Thunderbolt dock.
* **Battery** — the 80% charge cap as a switch, plus charge, status, draw,
  health against design capacity, cycle count, and pack temperature.
* **Keyboard** — backlight on/off (see the caveat below).

## Also here

`waybar/` holds optional Waybar modules that show the same data in the bar
instead of in a window — a `custom/` module for fans, EC temperature, the
platform profile and the cap state, plus Waybar's built-in
`power-profiles-daemon` module. **Nothing there is applied;** the live Waybar
config is untouched. See `waybar/README.md`.

## Install

```bash
cd triton-panel

# 1. the application itself (~/.local/bin is already on PATH)
install -Dm755 triton-panel ~/.local/bin/triton-panel

# 2. the privileged helper -- MUST be root-owned, see "Privileges" below
sudo install -Dm755 -o root -g root triton-ctl /usr/local/bin/triton-ctl

# 3. the sudoers rule. ALWAYS validate first: a syntax error anywhere in
#    sudoers.d locks you out of sudo entirely.
sudo visudo -cf triton-panel.sudoers
sudo install -Dm440 -o root -g root triton-panel.sudoers /etc/sudoers.d/triton-panel

# 4. the Walker entry
install -Dm644 triton-panel.desktop ~/.local/share/applications/triton-panel.desktop
```

The window rules that make it float and centre live in
`configs/hypr/windowrules.conf`. Push them the usual way — and remember that
writing a sourced Hyprland `.conf` auto-reloads Hyprland, which snaps the
screens back to `monitors.conf` geometry, so re-apply the current monitor
profile afterwards:

```bash
cp configs/hypr/windowrules.conf ~/.config/hypr/windowrules.conf
hyprctl reload
```

Uninstall is the reverse: remove those four files and the window-rule block.

## Privileges

`triton-panel` itself runs entirely unprivileged — every number it displays
comes from a world-readable sysfs file. Only three nodes are root-write:

```
/sys/bus/wmi/drivers/acer-wmi-battery/health_mode     the 80% charge cap
/sys/firmware/acpi/platform_profile                   quiet / balanced-performance
/sys/devices/platform/acer-wmi/four_zoned_kb/...      keyboard backlight
```

Those go through `sudo -n triton-ctl`, a short shell script that takes **no path
arguments**: every value it accepts is matched against a literal in a `case`
statement, there is no `eval`, and it refuses to run unless root owns it.

That last guard matters. A `NOPASSWD` sudoers rule pointing at a file the
invoking user can write *is* root, so installing `triton-ctl` anywhere
user-writable would hand away the box. Install it exactly as step 2 above.

## Hard dependencies

* **`predator_v4=1`** (`/etc/modprobe.d/acer-wmi-predator-v4.conf`). The
  PT516-52s is absent from the `acer_wmi` DMI quirk table, so without that
  parameter the driver selects no quirk, and neither the `acer` hwmon (fans, EC
  temperatures) nor `/sys/firmware/acpi/platform_profile` exists. The panel then
  shows those groups as unavailable with the reason, rather than zeros. Check:

  ```bash
  cat /sys/module/acer_wmi/parameters/predator_v4   # Y
  ```

* **`acer-wmi-battery-dkms`** for the charge cap. The in-kernel `acer_wmi` has
  no charge-limit support and BAT1 exposes no `charge_control_*` node, so
  TLP/powerdevil thresholds do nothing on this machine.

Neither is installed by this app; see `finish-installation-commands.md`.

## The keyboard caveat

**The backlight row is disabled on this machine today, and the panel says so.**

The write path is implemented and correct — `triton-ctl kbd on|off` writes
`four_zone_mode` in the format its parser actually wants (seven comma-separated
uints, `mode,speed,brightness,direction,red,green,blue`, with mode 0 = static
and brightness 0–100). It simply has nothing to write to: the in-tree `acer_wmi`
never creates `four_zoned_kb/`, and `/sys/class/leds/` holds no keyboard device
at all. The row turns itself on the moment the directory appears.

Note the Fn key probably still dims and brightens the keyboard today. That
happens inside the EC, below the operating system — the light works, it is just
not *controllable* from Linux. The Fn key therefore stays the daily control:
this row is **on/off only**, there is no colour or brightness picker, and the
setting does **not** persist across a reboot or a module reload, because the EC
returns to its firmware default. A toggle, not a configuration.

Getting it requires replacing `acer_wmi` with the out-of-tree
[`acer-wmi-linuwu`](https://github.com/adityaruplaha/acer-wmi-linuwu), which does
expose `four_zoned_kb/`. Two things make that cheaper than it sounds, and one
makes it uncertain:

* That driver keeps the `predator_v4` parameter, so the existing drop-in
  survives the swap.
* `PT516-52s` is **not** in its DMI table, and `predator_v4=1` alone selects the
  plain quirk without `four_zone_kbd`. But the sysfs group is gated on
  `has_cap(ACER_CAP_FOUR_ZONE_KBD)`, not on the quirk field, and `force_caps`
  replaces the capability mask after `set_quirks()` — so
  `options acer_wmi predator_v4=1 force_caps=0xFEC02` creates the directory with
  no source changes. Use that only as a probe: `force_caps` wipes the
  firmware-derived capabilities (wireless/rfkill) along with everything else, so
  the permanent fix is a one-line DMI entry pointing at
  `quirk_acer_predator_v4_four_zone`.
* **Uncertain:** this keyboard is 3-zone and the interface is 4-zone. The
  driver's own README documents a machine (Helios 16) that accepts the quirk
  while the WMI methods do nothing. In favour: the gaming WMI GUID
  `7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56` is present and unbound on this
  firmware, so methods 6/7 are reachable.

## Design notes worth keeping

* **hwmon indices are never hardcoded.** They are handed out in probe order and
  move between boots and across a module reload. Chips are found by their `name`
  file and re-resolved whenever a path goes missing, so reloading `acer_wmi`
  does not require restarting the panel.
* **The discrete GPU is never woken.** It sits in runtime-PM D3cold nearly all
  the time, and `nvidia-smi` is a userspace open of the device — polling it every
  two seconds would keep an idle 3080 Ti awake and drain the battery. The dGPU
  row reads only `power/runtime_status` and `power/runtime_suspended_time`, both
  free. `nvidia-smi` runs at most once every `DGPU_POLL_SECONDS` (10) and only
  while the GPU already reads `active`.

  **Read now** is the single path that may wake it — and pressing it holds the
  poll loop off for `DGPU_MANUAL_HOLD_SECONDS` (60) afterwards. Without that
  hold one press would bootstrap a permanent poll: the GPU it just woke would
  read `active` on the next tick, and every subsequent `nvidia-smi` would renew
  the idle timer, so it could never fall back to D3.
* **0 RPM is a real reading.** This laptop stops both fans below roughly 50 °C
  (measured 2026-10-31: 0/0 at 41 °C, 2564/2307 at 56 °C under load).
* **Profile writes are split on purpose.** `low-power`, `balanced` and
  `performance` go through `powerprofilesctl` so ppd also applies its
  `intel_pstate` EPP. Only `quiet` and `balanced-performance`, which ppd has no
  target for, are written directly — and ppd watches that sysfs file, so it then
  relabels itself `power-saver`/`balanced`. The panel raises a toast saying so,
  because otherwise it reads as a bug.
* **Power source is its own row** because the TB4 dock feeds this laptop over
  USB-C PD: `ACAD/online` can read 1 with no barrel jack attached. Anything
  deciding "are we on battery?" has to look at `BAT1/status`.

## Troubleshooting

| symptom | cause |
|---|---|
| fans/profile groups say "unavailable" | `predator_v4=1` is not in effect |
| charge-cap switch is insensitive | `acer-wmi-battery` is not loaded |
| toast: "triton-ctl has no sudoers rule yet" | step 3 of Install was skipped |
| ppd row says "placeholder driver, restart ppd" | `sudo systemctl restart power-profiles-daemon` — it probes platform drivers only at startup |
| window opens tiled | the window rules are not pushed to `~/.config/hypr/` |
| blank or black window | `GSK_RENDERER=gl triton-panel` (GTK4 renderer fallback) |
