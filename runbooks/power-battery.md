# Power, Battery and Fans

> Part of the `cachyPool` runbooks. Section numbers are **preserved** from
> `finish-installation-commands.md`, dissolved 2026-11-03 — a `§N` reference
> anywhere in this repo still resolves by number. Index and conventions:
> `README.md`. Live-state history: `../CHANGELOG.md`.

The 80% charge cap, the forced `predator_v4` quirk that is the only reason fan RPM and the 5-state platform profile exist on this model, and the daemon that follows the power source.

---

## 14. Battery charge cap at 80% (acer-wmi-battery) — ✅ VERIFIED WORKING 2026-10-31 (installed 2026-10-12)

**Why:** the original battery failed and was physically removed on 2026-10-12. A replacement is on order and should arrive within a few weeks. The likely cause is months spent docked at 100%, made worse by a gaming laptop's heat. Capping the charge at 80% is the standard mitigation, and it should already be in place when the new pack goes in.

**Why this tool and not TLP / KDE / GNOME:** all of those write the kernel's standard `charge_control_end_threshold` attribute on the battery's `power_supply` node. Nothing on this machine exposes that attribute. The in-kernel `acer_wmi` (7.2.8) has no battery code at all: its module contains no charge, battery or health strings. The firmware *does* expose Acer's battery-health WMI interface, GUID `79772EC5-04B1-4BFD-843C-61E7F77B6CC9`, which is what Acer Care Center / PredatorSense use on Windows. `acer-wmi-battery` is a small out-of-tree driver for exactly that GUID.

**Evidence gathered 2026-10-12, before installing:**

| Check | Result |
|---|---|
| Battery present | No. `/sys/class/power_supply/` holds only `ACAD` and two UCSI USB-C sources |
| Battery-health WMI GUID | Present (`79772EC5-04B1-4BFD-843C-61E7F77B6CC9-4`, no driver bound) |
| Charge limit in the in-kernel `acer_wmi` | None |
| Upstream `MODELS.md` | Predator Triton 300 SE and Helios Neo 16 reported working. PT516-52s not listed |
| Test build vs `7.2.8-1-cachyos` (clang 22, ThinLTO, `LLVM=1`) | ✅ clean |
| Test build vs `6.18.52-1-cachyos-lts` (GCC) | ✅ clean |
| `makepkg` of AUR `acer-wmi-battery-dkms 0.2.0-2` | ✅ source sha256 matches the PKGBUILD |
| Reviewed by hand | PKGBUILD, `dkms.conf`, `.install` (prints a notice, sleeps 5 s), Makefile (plain `obj-m`), C source (three WMI methods: 19 battery info, 20 get status, 21 set) |
| Secure Boot | Disabled, so the unsigned DKMS module loads without MOK enrolment |

**Rejected alternative:** `linuwu-sense-dkms` / `div-acer-manager-max` (DAMX). It has the same fixed 80% limiter, but it *replaces* the in-kernel `acer_wmi` to add fan, RGB and thermal control, and upstream only claims full support for the PHN16-71. More blast radius for the same cap.

### 14a. Install

Run in a Kitty terminal, since the `sudo` prompts are interactive:

```bash
paru -S --skipreview acer-wmi-battery-dkms
sudo install -Dm644 ~/code/cachyPool/configs/modprobe.d/acer-wmi-battery.conf /etc/modprobe.d/acer-wmi-battery.conf
sudo modprobe acer_wmi_battery
```

- **`dkms` comes along** as the only new dependency. pacman picks the `cachyos` repo build (`3.4.3-1`), which depends on clang/lld/llvm. Those are already installed, and the main kernel needs them because it is clang-built. The DKMS pacman hook builds the module for **both** installed kernels and rebuilds it on every kernel update.
- **Autoload:** the package ships `/usr/lib/modules-load.d/acer-wmi-battery.conf`, so the module loads at every boot.
- **The cap itself** comes from `configs/modprobe.d/acer-wmi-battery.conf`, which sets `enable_health_mode=1`. Every module load re-sends the 80% cap. Without that option the module loads but leaves the firmware setting untouched.
- **The cap is fixed at 80%** by the firmware. It is not configurable.
- **paru asks you to pick a provider** because `acer-wmi-battery-dkms-git` also provides the name. Pick `1`, the default: the pinned `0.2.0` release with a checksum, which is the one reviewed above. The `-git` package builds whatever is on the upstream branch that day.

### 14b. Verify

```bash
dkms status acer_wmi_battery                              # → installed for 7.2.8-1-cachyos and 6.18.52-1-cachyos-lts
lsmod | grep acer_wmi_battery
cat /sys/bus/wmi/drivers/acer-wmi-battery/health_mode     # 1 = cap on · 0 = off · -1 = firmware reports it unsupported
journalctl -k -b | grep acer_wmi_battery                  # "available modes: health mode, calibration mode"
systemctl is-failed systemd-modules-load.service          # must print "active", not "failed"
```

The real test is not any of the above: it is **charging stopping near 80% instead of climbing to 100%**. That test was finally run on 2026-10-31 and it passed — see "Results 2026-10-31" below. The 2026-10-12 results are kept because they explain what a `health_mode = 0` with no pack looks like.

```bash
upower -i $(upower -e | grep BAT)
```

**Results 2026-10-12: installed and loading, cap not active yet.**

| Check | Result |
|---|---|
| Install sequence | paru 21:02:50 → 21:03:20 (`dkms` first, then the package), option file copied 21:03:28, `modprobe` 21:03:35. The option was in place before the load |
| `dkms status` | `installed` for `7.2.8-1-cachyos` and `6.18.52-1-cachyos-lts`. The 7.2.8 `make.log` shows DKMS added `LLVM=1` by itself for the clang-built kernel |
| `modprobe -c` | `options acer_wmi_battery enable_health_mode=1`, plus the alias `wmi:79772EC5_04B1_4bfd_843C_61E7F77B6CC9`, so udev can also autoload it |
| `lsmod` | loaded |
| Kernel log | `available modes: health mode, calibration mode`, and no `active modes` line. Also `module verification failed: signature and/or required key missing - tainting kernel`, which is expected for an unsigned out-of-tree module with Secure Boot off |
| `health_mode` | **`0`** |
| `temperature` | `No such device or address`, since there is no pack to read |
| `systemd-modules-load.service` | `active` |

**Reading the `0`:** the set call succeeded at the ACPI level, because otherwise init returns `-EIO` and the module would not be loaded. Yet the firmware's own status read right after it reports health mode off. The driver ignores the firmware's return code, so a silent refusal looks exactly like this. The likely reason is that there is no pack for the EC to apply the cap to. That is not proven: it could also mean this firmware ignores the command. The successful load without a battery does settle one worry: boot will not fail `systemd-modules-load.service`.

**Results 2026-10-31: the cap works. ✅**

The replacement pack (Getac `AP20BHU`, serial `41378`, `cycle_count` 0) was fitted with the laptop off and the machine booted normally, so the module re-sent the cap as it loaded.

| Check | Result |
|---|---|
| `health_mode` | **`1`** |
| Kernel log | `acer_wmi_battery: active modes: health mode` — the line that was missing on the two pack-less boots |
| `temperature` | `27900` → 27.9 °C, readable now that there is a pack |
| **Charge stop** | the pack charged from 74% and **stopped at exactly 80%** |
| `BAT1/status` | `Not charging`, with `ACAD/online` = `1` |
| `charge_now` | identical at 11:37 and 11:43 — six minutes, not a pause |
| `current_now` | `0` |
| `upower` | `state: pending-charge`, `energy-rate: 0 W` |
| Pack health | `energy_full` 101.67 Wh vs 99.99 Wh design — factory variance on a 0-cycle pack, not cap-induced drift |

**Nothing else on this machine could have stopped it.** TLP is not installed. BAT1 exposes **no** `charge_control_*` or `charge_behaviour` node at all, because the in-kernel `acer_wmi` has no charge-limit code. The only limiter present is `health_mode`. So the `0` seen on 2026-10-12 was exactly what it looked like: no pack for the EC to apply the setting to, not a firmware refusal. The `linuwu-sense` fallback named above is **no longer needed**.

Re-run the check any time with:

```bash
cat /sys/bus/wmi/drivers/acer-wmi-battery/health_mode     # 1
cat /sys/class/power_supply/BAT1/status                   # "Not charging" at 80% on AC
upower -i $(upower -e | grep BAT)                         # state: pending-charge, 0 W
```

**Lifting the cap for travel is not persistent, by design.** `/etc/modprobe.d/acer-wmi-battery.conf` re-sends `enable_health_mode=1` on every module load, so an `echo 0` survives only until the next load or reboot. That is deliberate: forgetting to re-arm the cap is what killed the first pack. `triton-panel` exposes the same toggle as a switch and says so in the toast.

### 14c. Calibration mode: leave it alone

The driver also exposes `/sys/bus/wmi/drivers/acer-wmi-battery/calibration_mode`. Calibration turns health mode off, charges to 100%, drains, and recharges, which takes hours on AC with the laptop idle. It is not part of this setup. If it is ever used, write `0` to it by hand afterwards, because the driver does not handle the firmware's completion event, then write `1` to `health_mode` again.

### 14d. Revert

```bash
echo 0 | sudo tee /sys/bus/wmi/drivers/acer-wmi-battery/health_mode   # lift the cap in firmware first
sudo rm /etc/modprobe.d/acer-wmi-battery.conf
sudo modprobe -r acer_wmi_battery
paru -Rns acer-wmi-battery-dkms                                        # takes dkms with it if nothing else needs it
```

### 14e. Docs updated

**2026-10-31** (cap verified)

- `../ACTUAL-CONFIGURATION.md`: header, §1 battery row, §8 `acer-wmi-battery-dkms` row, §15 battery row moved to ✅ with the evidence, §15 hypridle row annotated (battery-only suspend armed again).
- `../CLAUDE.md`: battery bullet rewritten.
- `../shortcuts.md`: §7 lid-close note and the hypridle suspend bullet — both paths are live again now that there is a pack.

**2026-10-12** (installed)

- `../ACTUAL-CONFIGURATION.md`: §1 battery row, §8 rows for `acer-wmi-battery-dkms` and `dkms`, §9 counts, §15 new row, §16 repo layout gained `configs/modprobe.d/`.
- `configs/modprobe.d/acer-wmi-battery.conf`: new mirror of `/etc/modprobe.d/acer-wmi-battery.conf`. Restore path on a rebuild is the `sudo install` line in §14a.
- `../CLAUDE.md`: hardware-constraints bullet.

---

## 17. Fan RPM and the platform profile: force `predator_v4` — ✅ APPLIED 2026-10-31, reboot-verified 2026-11-03

**Why:** this laptop had no fan readings and no `/sys/firmware/acpi/platform_profile` at all. Not a missing package — the in-kernel `acer_wmi` (7.2.8) simply selects no quirk on this model.

The driver carries `module_param(predator_v4, bool, 0444)`, and `find_quirks()` does:

```c
if (predator_v4)
        quirks = &quirk_acer_predator_v4;   /* .hwmon = true, .platform_profile = true */
else if (!force_series)
        dmi_check_system(acer_quirks);
```

Its DMI quirk table lists only `Predator PHN16-71`, `PH16-71` and `PH18-71`. The **PT516-52s is absent**, so the DMI path finds nothing and the driver falls back to `quirk_unknown`. Forcing the parameter skips the DMI match entirely.

**What it gives, verified live on 2026-10-31 with a real unload/reload (confirmed in `dmesg`):**

| | |
|---|---|
| `/sys/firmware/acpi/platform_profile` | appears, with five states: `low-power quiet balanced balanced-performance performance` |
| `/sys/class/hwmon/hwmonN` (`name` = `acer`) | `fan1_input`, `fan2_input`, `temp1_input`, `temp3_input` (`temp2_input` is wired but always reads 0) |
| lm_sensors chip name | `acer-isa-0ace` |
| Load test | 0/0 RPM at 41 °C → 20 threads for 45 s → **2564/2307 RPM at 56 °C** → back to 2097/2027 |
| Survived the reload | `Acer WMI hotkeys` input device, the `acer-*` rfkill switches, and `health_mode` = 1 |

**0 RPM at idle is a real reading**, not a failure: this laptop stops both fans when it is cool.

**What it does NOT give:**

- **No fan control.** `quirk_acer_predator_v4` sets `.hwmon` but not `.pwm`, so the fans are readable and nothing more.
- **No keyboard RGB.** The in-tree `acer_wmi` never exposes `four_zoned_kb`. That needs an out-of-tree driver — the route, and why it is uncertain on this 3-zone keyboard, is in `../triton-panel/README.md`.

### 17a. Install

The parameter is `0444`: settable only at module load, never writable through sysfs. So it has to be a modprobe drop-in.

```bash
sudo install -Dm644 ~/code/cachyPool/configs/modprobe.d/acer-wmi-predator-v4.conf \
     /etc/modprobe.d/acer-wmi-predator-v4.conf
sudo systemctl restart power-profiles-daemon
```

- **No initramfs rebuild.** `acer_wmi` appears in no mkinitcpio `MODULES` list; the only `MODULES+=` on this machine is the NVIDIA one in `/etc/mkinitcpio.conf.d/10-chwd.conf`.
- **The `power-profiles-daemon` restart is required, not optional.** ppd probes platform drivers once at startup. Until it is restarted it keeps reporting `PlatformDriver: placeholder`, and switching profiles moves the `intel_pstate` EPP and nothing thermal.

### 17b. Verify

```bash
cat /sys/module/acer_wmi/parameters/predator_v4   # Y
cat /sys/firmware/acpi/platform_profile           # must exist
cat /sys/firmware/acpi/platform_profile_choices   # 5 states
sensors acer-isa-0ace                             # fan1/fan2 + temp1/temp3
powerprofilesctl list                             # no "placeholder" left
```

✅ **Reboot-verified 2026-11-03.** The parameter reads `Y` after a live reload too, so the only
honest test was a reboot across the drop-in. Run after the boot of 2026-11-03 08:12:
`predator_v4` = `Y`, `/sys/firmware/acpi/platform_profile` present and reading `balanced`,
`platform_profile_choices` = `low-power quiet balanced balanced-performance performance`,
`sensors acer-isa-0ace` = `fan1 0 RPM / fan2 0 RPM / temp1 +35.0 °C / temp3 +33.0 °C`
(0 RPM at 35 °C is genuine — this machine stops both fans when cold), and
`powerprofilesctl list` no longer mentions `placeholder`. The drop-in is picked up at boot,
so nothing here depends on a manual `modprobe -r` / `modprobe` any more.

**Mapping ppd onto the five states.** ppd has only three targets, so `quiet` and
`balanced-performance` are unreachable through it. ✅ **Confirmed live 2026-11-03** — each
`powerprofilesctl set` moved `platform_profile` exactly as predicted
(`power-saver`→`low-power`, `balanced`→`balanced`, `performance`→`performance`), and the
profile was restored to `balanced` afterwards:

```bash
powerprofilesctl set power-saver && cat /sys/firmware/acpi/platform_profile   # expect low-power
powerprofilesctl set balanced    && cat /sys/firmware/acpi/platform_profile   # expect balanced
powerprofilesctl set performance && cat /sys/firmware/acpi/platform_profile   # expect performance
```

To use the other two, write the file directly (`triton-panel` does this through its helper). Note that ppd **monitors** that sysfs file, so a direct write makes ppd relabel its own active profile — `quiet` reads back as `power-saver`, `balanced-performance` as `balanced`. That is ppd behaving correctly, not a conflict.

### 17c. Revert

```bash
sudo rm /etc/modprobe.d/acer-wmi-predator-v4.conf
sudo modprobe -r acer_wmi && sudo modprobe acer_wmi
sudo systemctl restart power-profiles-daemon
```

Everything the parameter adds disappears; hotkeys, rfkill and the battery cap are untouched, since the cap lives in the separate `acer_wmi_battery` module.

### 17d. Docs updated 2026-10-31

- `configs/modprobe.d/acer-wmi-predator-v4.conf`: new mirror of the live drop-in.
- `../ACTUAL-CONFIGURATION.md`: header, §15 new row, §16 repo layout.
- `../CLAUDE.md`: new hardware-constraints bullet.

---

## 19. Automatic power saving by power source — ✅ APPLIED 2026-10-31, re-homed 2026-11-03

> **2026-11-03 — the rate's owner moved out of `monitor-mode.sh`.** Hyprland 0.57.1 removed
> `hyprctl keyword`, which parked that whole script (`monitors.md` §16), so `edp_mode()` and
> the `edp-rate` hook were lifted verbatim into **`scripts/edp-rate.sh`** — same two modes,
> same `Discharging` test, same pref file, same three guards — with the apply changed to
> `hyprctl eval 'hl.monitor({output = "eDP-1", mode = …, position = …, scale = …})'`.
> `power-autoswitch.sh` now calls `"$RATE_SCRIPT"` where it called `"$MODE_SCRIPT" edp-rate`;
> nothing else in its logic moved and `tests/test-power-autoswitch.sh` still passes 10/10.
> **Verified end to end on battery the same day:** `hyprctl reload` put eDP-1 back to 240 Hz
> from `lua/monitors.lua`, and the next tick of the loop took it to 60 Hz with the platform
> profile at `low-power`. Read every "`monitor-mode.sh`" below as "`edp-rate.sh`".

On battery the machine now drops the laptop panel to 60 Hz and switches the
platform profile to `power-saver`; on AC it restores 240 Hz and the profile that
was active before. Two actions only — no backlight, no hypridle changes, no
charge-cap changes, no dGPU parameters.

eDP-1 has exactly two modes (`2560x1600@240` and `2560x1600@60`, same resolution
and scale), so this costs nothing but smoothness and is the cheapest real saving
available here.

### 19a. Why the refresh rate needed a single owner first

`2560x1600@240` was hardcoded at **8 sites** in `monitor-mode.sh` plus a **9th**
path through `apply_from_profile`, which emits `.Hz` straight out of the hyprmon
JSON — and `configs/hyprmon/profiles/desktop.json` carries eDP-1 at `240.00301`
because it was saved while docked on AC. Anything setting the rate from outside
was therefore undone by the next profile apply, hotplug autoswitch or
`hyprctl reload`.

So the rate is now resolved in one place:

```bash
# scripts/edp-rate.sh   (was monitor-mode.sh's edp_mode() until 2026-11-03)
edp_mode() { if power_auto && on_battery; then printf %s "$EDP_LO"; else printf %s "$EDP_HI"; fi; }
```

**Never reintroduce a `2560x1600@240` literal in that script.** `apply_from_profile`
overrides eDP-1's Hz with `--argjson edphz`; the externals keep their JSON rate.

`on_battery` is `grep -q Discharging /sys/class/power_supply/BAT1/status`, the
same test hypridle's suspend listener uses — not `ACAD/online`, which reads 1
when only the TB4 dock is feeding the machine, and `Not charging` (the 80% cap
holding on AC) must count as AC.

### 19b. The two policies are deliberately different

| | policy | why |
|---|---|---|
| **Rate** | reconciled every stable tick (idempotent) | no manual UI exists for it, so there is no user choice to override — and reconciling is what repairs a `hyprctl reload`, a `Super+M` switch or a hotplug autoswitch |
| **Profile** | changed only on a power-source **transition** | the profile *is* exposed in Triton Panel, so a `performance` chosen on battery must survive |

### 19c. Install

```bash
cd ~/code/cachyPool
install -m755 configs/hypr/scripts/edp-rate.sh        ~/.config/hypr/scripts/edp-rate.sh
install -m755 configs/hypr/scripts/power-autoswitch.sh ~/.config/hypr/scripts/power-autoswitch.sh
install -m644 configs/hypr/lua/autostart.lua           ~/.config/hypr/lua/autostart.lua  # starts the loop
install -Dm755 triton-panel/triton-panel     ~/.local/bin/triton-panel

# hl.on("hyprland.start") does NOT re-fire on a reload either, so start it once by hand:
~/.config/hypr/scripts/power-autoswitch.sh &
```

### 19d. Verify — results 2026-10-31

```bash
cat /run/user/1000/triton-power-mode     # source/auto/rate/saved_profile/pid/ts
hyprctl monitors -j | jq -r '.[] | select(.name=="eDP-1") | .refreshRate'
powerprofilesctl get
```

Checked on battery, all passing:

| check | result |
|---|---|
| daemon start on battery | rate 240 → **60**, profile `balanced` → **power-saver**, `saved_profile=balanced` |
| `monitor-mode.sh laptop` afterwards | stays **60** — the centralization proof; before this change it forced 240 |
| `hyprctl reload` (snaps to `monitors.conf` @240) | daemon restored **60** within one tick, unattended |
| panel switch → off | **240** restored, profile left on `power-saver` as designed |
| panel switch → on | back to **60**, and `saved_profile` still `balanced`, not `power-saver` |
| `edp-rate` while DPMS off | **no-op** — a modeset would wake the panel |
| `edp-rate` run twice | second run emits nothing (rate already matches) |

✅ **AC steady state verified 2026-11-03** — on barrel AC (`ACAD/online=1`, both USB-C PD
sources `0`, undocked) with the daemon live (pid 1579) and the panel switch on
(`~/.config/triton-panel/power-auto` = `1`): `eDP-1` at **240.00 Hz**, `powerprofilesctl get`
and `platform_profile` both `balanced`, and `/run/user/1000/triton-power-mode` reading
`source=ac auto=1 rate=240 saved_profile= profile=balanced`. The **empty `saved_profile` is
the §19h fix working on the AC side**: nothing was captured on an AC boot, so the branch
restored nothing and left `balanced` alone instead of forcing it.

⚠ **The AC *transition* is still untested** — the charger is no longer the blocker (it is
plugged in), so the sequence below is runnable now:

1. unplug → expect `balanced` captured, profile → `power-saver`, rate → **60**
2. plug in → expect `balanced` restored exactly, rate → **240**, plus an "On AC" notification

### 19e. Gotchas found while building this

* **Never signal the daemon with `pkill -f power-autoswitch.sh`.** `-f` matches
  whole command lines, so it also hits any shell, editor or pager whose argv
  merely mentions the script — during testing it killed the shell running the
  test. The daemon publishes `pid=` in its state file; signal that.
* **`edp-rate` must no-op when eDP-1 is absent from `hyprctl monitors -j`.**
  The `read` profile disables the laptop panel on purpose, and a
  `keyword monitor eDP-1,<mode>,…` against a disabled output does not set a
  rate — it *enables* the output, silently undoing `read` every few seconds.
* **Skip the modeset while `dpmsStatus` is false**, or reconciling under
  hypridle's 10-minute DPMS-off turns the screen back on by itself.

### 19f. Revert

```bash
rm ~/.config/hypr/scripts/power-autoswitch.sh
# drop the exec-once line from autostart.conf, then:
echo 0 > ~/.config/triton-panel/power-auto   # or just leave it: no daemon, no effect
~/.config/hypr/scripts/monitor-mode.sh edp-rate   # back to 240
```

`edp_mode()` itself is harmless with the daemon gone: with the pref at `0` it
always resolves to 240, exactly the old hardcoded behaviour.

### 19g. Docs updated 2026-10-31

`../ACTUAL-CONFIGURATION.md` §10 (new daemon), §11 (new script + the rate-owner
rule), §15 (new row); `../CLAUDE.md` (monitor section); `../triton-panel/README.md`;
this section.

### 19h. `saved_profile` ratcheted to `power-saver` — fixed 2026-11-02

**Symptom.** The live state file read `saved_profile=power-saver`, where §19d
recorded `saved_profile=balanced` on 2026-10-31. Consequence: the AC branch
"restores" `power-saver`, so `balanced` on AC was effectively dead.

**Mechanism.** `power-profiles-daemon` persists its choice in
`/var/lib/power-profiles-daemon/state.ini` (`Profile=power-saver`). The daemon
forces `power-saver` on battery; ppd persists that; the next boot restores it;
and because `last_source=unknown` makes the **first stable read count as a
transition**, the daemon's first tick then captures that same `power-saver` as
"what I had before battery". Each boot re-persists it — a self-feeding loop.
§19d's `profile balanced → power-saver` at daemon start on battery is the proof
that ppd did *not* start in `power-saver` before the loop closed (the same
`battery_aware=true` was already set then, so battery-awareness is not the
cause). The capture is simply meaningless on a battery boot: there is no
pre-battery profile to capture.

**Second bug, same branch, found while fixing this one.** With nothing
captured, the AC side ran `set_profile "${saved_profile:-balanced}"` — so an
**AC boot forced `balanced`** and silently destroyed a hand-picked
`performance`. That contradicts §19b's "a manual choice must survive", and is
likely why §19d never managed to tick the AC branch off.

**The invariant (the whole fix).** *Never record `power-saver` as
`saved_profile`.* On battery it can only ever be this daemon's own doing, so it
says nothing about what the user wanted on AC. One guard covers both paths that
reach the branch without a real transition: the boot tick, and the Triton Panel
toggle flipped off→on while already on battery.

```bash
# battery side — capture only a profile that is not our own doing
[[ -n "$saved_profile" || "$(current_profile)" == power-saver ]] \
  || saved_profile="$(current_profile)"

# AC side — restore only what was actually captured
#   capture present      -> restore it exactly
#   none, and power-saver -> that is ours: hand it back to `balanced`
#   none, anything else   -> the user picked it: leave it alone
```

No new state flag. `configs/hypr/scripts/power-autoswitch.sh`, pushed live with
`cp` and the daemon restarted via the **published pid** from the state file
(never `pkill -f` — §19e).

**Verified live 2026-11-02 (battery side).**

| Check | Result |
|---|---|
| state file before → after | `saved_profile=power-saver` → `saved_profile=` |
| profile / platform profile | `power-saver` / `low-power`, unchanged |
| eDP-1 | still `@60.002`, unchanged |
| daemon instances | 1 (a second cmdline match was a transient bash fork for `sleep 5 &`, caught pre-`exec` — the same argv-matching trap as §19e) |
| `bash -n` | clean (an earlier draft used `local` outside a function, which would have aborted the loop) |
| logic harness | 10/10 — extracts the real branch text from the script and stubs `current_profile`/`set_profile` |

✅ **The AC side of this fix is verified live 2026-11-03** — see §19d: on an AC boot the
state file reads `saved_profile=` (empty) with the profile left on `balanced`, which is
exactly the "restore only what was actually captured" branch. ⚠ What remains untested is
the **transition**, which no longer needs anything to be bought or plugged:

1. unplug → expect `balanced` captured, profile → `power-saver`, rate → 60
2. plug in → expect `balanced` restored exactly, rate → 240

The harness lives at `tests/test-power-autoswitch.sh` — a new top-level
`tests/`, deliberately not under `configs/`, which mirrors live dotfiles and so
can never hold a test. It resolves the script relative to its own location, so
it runs from anywhere:

```bash
./tests/test-power-autoswitch.sh     # 10 passed, 0 failed
```

It `awk`s the branch out of the real script and stubs `current_profile` /
`set_profile`, so it exercises the shipped code, not a transcription — if the
branch is reindented or renamed the extraction returns empty and the test
fails loudly rather than passing against nothing.

---


---

## Issue history

Moved here 2026-11-03 from `../ACTUAL-CONFIGURATION.md` §15, verbatim. Those table
cells had grown into multi-kilobyte incident analyses; §15 is now a status table
and the reasoning lives beside the runbook it explains.

### Nothing reacted to the power source

✅ Resolved 2026-10-31 — the machine behaved identically on battery and on AC: eDP-1 ran at **240 Hz** either way and the platform profile never moved. New `scripts/power-autoswitch.sh` (autostart.conf, 5 s poll, single-instance) now drops the panel to **60 Hz** and the profile to **power-saver** while `BAT1/status` reads `Discharging`, and restores 240 Hz plus the previously active profile on AC. **The enabling change was making the rate have one owner:** `2560x1600@240` had been hardcoded at **8 sites** in `monitor-mode.sh` plus a 9th path through `apply_from_profile` (which emits `.Hz` from the hyprmon JSON, where `desktop.json` carries `240.00301`), so any external setter was undone by the next profile apply, hotplug autoswitch or `hyprctl reload`; all nine now go through `edp_mode()`. Rate is **reconciled** every stable tick (idempotent, self-healing); the profile changes **only on a transition**, so a `performance` picked by hand in Triton Panel survives. Toggle: Triton Panel → Power → *Automatic power saving* (`~/.config/triton-panel/power-auto` + SIGUSR1 to the daemon's published pid — never `pkill -f`, which also signals any shell whose argv mentions the script). Verified on battery: start → 240→60 Hz and balanced→power-saver; `monitor-mode.sh laptop` afterwards **stays 60**; `hyprctl reload` self-repaired within a tick; toggle off → 240 with the profile untouched; toggle on → 60 with `saved_profile` still `balanced`. ⚠ **The AC branch is untested** — it needs the charger physically plugged in. §19. [**Superseded 2026-11-03:** the AC *steady state* is verified — 240 Hz, `balanced`, empty `saved_profile` — and only the plug/unplug transition remains. See §19d.] **2026-11-02 — measured what `power-saver` actually does, and it is not what the name suggests.** On battery, 20 threads of a pure integer loop pin **every one of the 20 CPUs at exactly 1100 MHz** (avg 1100 / max 1100 at 5 s, 10 s and 18 s; at idle a core still reaches 1701 MHz, so this is a load-dependent ceiling, not a global cap). It is not `intel_pstate` — `max_perf_pct` 100, `no_turbo` 0, `cpuinfo_max_freq` 4900 MHz; not `intel_lpmd` — `online: 0-19`, nothing parked; not thermal or PL1 — 43 °C and 24.3 W system draw. The ceiling comes from EPP=`power` + `platform_profile=low-power`. **Fixed-work comparison** (same compute, 20 threads, system draw from `BAT1`): `power-saver` 1100 MHz / 69.7 s / 26.6 W / **0.515 Wh**; `balanced` 1863 MHz / 37.1 s / 45.0 W / **0.464 Wh**; `performance` 2230 MHz / 34.6 s / 53.1 W / **0.510 Wh**. Read that as a **tie on energy and 2× on time**: run-to-run spread on `power-saver` alone was 19.7 → 24.3 → 26.6 W across the session, so the 0.05 Wh gap is inside the noise. Subtracting the ~15.4 W platform baseline, the *marginal* energy of the compute is 781 J / 1099 J / 1304 J — 1100 MHz **is** the efficient operating point, and the tie comes entirely from paying the baseline for twice as long. So `power-saver` costs **performance, not battery**, and buys no battery either. **Steady-state idle by profile** (45 s settle, 20 samples over 40 s, same background load): `power-saver` 17.3 W → `balanced` 18.4 W → `performance` 23.3 W → `power-saver` again **19.1 W**. The repeat control drifted 1.8 W, which is *wider* than the 1.1 W `balanced`–`power-saver` gap, so **those two are indistinguishable at idle**; only `performance` (+5 W, 1606 MHz at idle, non-overlapping band) is clearly worse. Fans read **0/0 RPM in every profile**, so the suspected fan floor is ruled out. Conclusion: keep `power-saver` as the battery default — but it is a *performance* setting, so pick `balanced` by hand in Triton Panel before a long build; it finishes in half the time for the same Wh. ⚠ Two things this exposed, both pre-existing: (1) **`saved_profile` has ratcheted to `power-saver`.** At the daemon's first tick on a battery boot the profile is **already** `power-saver` — `/var/lib/power-profiles-daemon/state.ini` carries both `Profile=power-saver` (ppd persists its choice across reboots) and `battery_aware=true` (ppd picks power-saver on battery by itself), and **the persistence is the one doing it**: §19d's own 2026-10-31 verification recorded `profile balanced → power-saver, saved_profile=balanced` at daemon start **on battery**, so with the same `battery_aware=true` in place ppd did *not* come up in power-saver that day — it came up `balanced` and this daemon moved it. What changed since is only that ppd has had the daemon's own `power-saver` persisted into `state.ini` to restore. (ppd logs no profile changes at default verbosity and the file's mtime was already overwritten by this session's testing, so this is the repo's recorded evidence rather than a live re-test.) Either way the first-tick capture (`last_source=unknown` forces the first stable read to count as a transition) then records `power-saver` as "what I had before battery" — which is what the AC branch restores. Each boot re-persists it, so `balanced` on AC is effectively dead and the live state file now reads `saved_profile=power-saver` where 2026-10-31 recorded `balanced`. The capture is meaningless on a battery boot, because there is no pre-battery profile to capture. ✅ **Fixed 2026-11-02** (same day, on request) — and a **second, worse bug on the same branch** turned up while fixing it: with nothing captured, the AC branch ran `set_profile "${saved_profile:-balanced}"`, so an **AC boot forced `balanced`** and silently destroyed a hand-picked `performance` — which is probably why the AC branch was still marked untested. The fix is two conditions and **no new state flag**, built on one invariant: ***never record `power-saver` as `saved_profile`***, because on battery it can only ever be this daemon's own doing and therefore carries no information about what the user wanted on AC. That single guard covers both paths that reach the branch without a real transition — the boot tick and a Triton Panel toggle flipped off and on while already on battery. The AC side now **restores only what was actually captured**: with a capture, restore it exactly; with none, hand `power-saver` back to `balanced` (it is ours) but leave **any other** profile untouched (the user picked it). Verified live: the state file went `saved_profile=power-saver` → `saved_profile=` with the profile, platform profile and 60 Hz all unchanged, one daemon instance. A 10-case harness passes 10/10 — it extracts the real branch text from the script and stubs `current_profile`/`set_profile`, so it tests the shipped code rather than a copy. It lives in a new top-level `tests/` (not `configs/`, which is a live-dotfile mirror and never holds a test) and resolves the script relative to its own location, so it runs from any directory: `./tests/test-power-autoswitch.sh`. ⚠ **The AC branch is still untested on real hardware** — it needs the charger: plug in (expect → `balanced`), unplug (expect `balanced` captured, → `power-saver`), plug in again (expect `balanced` restored). [**Superseded 2026-11-03:** the AC side of the §19h fix is verified live — on an AC boot the state file reads `saved_profile=` with `balanced` left untouched, which is the "restore only what was captured" branch. The transition is what is left, and the charger is plugged in. See §19d / §19h.] (2) That same `state.ini` carries `battery_aware=true`, so ppd may already be doing part of the profile half of this daemon's job — **still open, not fixed.** ⚠ **RAPL is not the lever on this machine:** PL1 reads 110 W (`intel-rapl:0` and `intel-rapl-mmio:0` both) and is never approached — even `performance` tops out at 2230 MHz / 53 W system. Inference, not verified: the EC's battery-mode power budget, forced by the pack's discharge current, caps everything below RAPL on battery. A PL1 cap on battery was considered and **dropped** for this reason.

### Laptop battery failed; 80% charge cap for the replacement

✅ **Resolved 2026-10-31** — the replacement Getac `AP20BHU` (serial 41378, 0 cycles) went in, and the cap installed on 2026-10-12 was proven for the first time. **The proof:** the pack charged from 74% and stopped dead at **80%** with AC connected — `BAT1/status` = `Not charging`, `capacity` = 80, `charge_now` unchanged across six minutes, `current_now` = 0, `ACAD/online` = 1, upower `state: pending-charge` at `0 W`. **Nothing else could have done it:** TLP is not installed, BAT1 exposes no `charge_control_*` or `charge_behaviour` node at all (the in-kernel `acer_wmi` 7.2.8 has no charge-limit code), and the only limiter present is `/sys/bus/wmi/drivers/acer-wmi-battery/health_mode` = **1**, with the kernel logging `acer_wmi_battery: active modes: health mode`. So the `health_mode = 0` seen on 2026-10-12 was exactly what it looked like: no pack for the EC to apply the setting to. **Why a WMI driver at all:** the firmware exposes Acer's battery-health WMI interface (GUID `79772EC5-04B1-4BFD-843C-61E7F77B6CC9`, the one Acer Care Center uses) and AUR `acer-wmi-battery-dkms 0.2.0-2` drives it; the cap is fixed at 80% by firmware, not configurable. `configs/modprobe.d/acer-wmi-battery.conf` sets `enable_health_mode=1`, so every module load re-sends it — which is also why lifting the cap for travel is not persistent. The `linuwu-sense` fallback named on 2026-10-12 is no longer needed. Steps, result table, revert: §14.

### No fan RPM and no platform profile on this model

✅ **Resolved 2026-10-31** — the in-kernel `acer_wmi` (7.2.8) carries `module_param(predator_v4, bool, 0444)`, but its DMI quirk table lists only PHN16-71, PH16-71 and PH18-71. The PT516-52s is absent, so the driver booted with **no quirk**: no `acer` hwmon, no `/sys/firmware/acpi/platform_profile`, nothing to read. Forcing the parameter skips the DMI match and selects `quirk_acer_predator_v4` (`.hwmon`, `.platform_profile`). **Verified live** with a real unload/reload: `platform_profile` appears with five states (`low-power quiet balanced balanced-performance performance`), and an `acer` hwmon with `fan1_input`/`fan2_input`/`temp1_input`/`temp3_input` — lm_sensors chip `acer-isa-0ace`. Load test: 0/0 RPM at 41 °C → 2564/2307 at 56 °C → back to 2097/2027, so **0 RPM at idle is a real reading**, this laptop stops its fans when cool. Hotkeys, rfkill and `health_mode` all survived the reload. **Does not give:** fan *control* — the quirk sets `.hwmon` but not `.pwm` — nor keyboard RGB. Persisted in `/etc/modprobe.d/acer-wmi-predator-v4.conf` (mirror in `configs/modprobe.d/`); the parameter is `0444`, so it is settable only at module load. No initramfs rebuild needed — `acer_wmi` is in no mkinitcpio `MODULES` list. ⚠ `power-profiles-daemon` probes platform drivers only at startup, so it must be restarted afterwards or it keeps reporting `PlatformDriver: placeholder` and its profiles move only the intel_pstate EPP. ⚠ At the time of writing the drop-in is installed but the live `Y` still comes from the probe's reload, not from the file — **confirm on the next boot** with the five checks in §17b. Steps: §17.
