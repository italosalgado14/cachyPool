# CLAUDE.md

Guidance for Claude Code working in this repository.

**This file holds rules, not narrative.** Every entry is something that will break if you
get it wrong, stated as an imperative, with a pointer to the runbook that holds the
reasoning. If you need the *why*, follow the pointer; do not re-derive it here, and do not
grow this file with incident write-ups — those go in the runbook and `CHANGELOG.md`.

## What this repo is

`cachyPool` is **not a software project** — it is documentation plus a dotfile mirror for a
single machine (Acer Predator PT516-52s, hostname `triton500se`) running **CachyOS +
Hyprland on Wayland with NVIDIA**. There is no build, test, or lint pipeline. The one
exception is `triton-panel/`, which is real source (a GTK4 app). Four regression tests:
`triton-panel/test-enroll.py`, `triton-panel/test-battery.py`,
`tests/test-power-autoswitch.sh` and `tests/check-doc-refs.sh`. Run them when you touch
what they cover. The Python ones must be run from inside `triton-panel/`.

## Documentation structure — scope, not rank

Restructured 2026-11-03. There is **no source-of-truth hierarchy any more**; there is one
owner per subject. If two files appear to cover the same ground, that is a bug — fix the
ownership, do not add a ranking.

| Ask | File |
|---|---|
| What the machine **is** right now | `ACTUAL-CONFIGURATION.md` — facts only, no history |
| What **changed** and when | `CHANGELOG.md` — append-only, newest first |
| How to **drive** it day to day | `shortcuts.md` |
| How a subsystem **works, breaks, gets fixed** | `runbooks/<subsystem>.md` (index: `runbooks/README.md`) |
| Superseded, kept for the record | `archive/` (index: `archive/README.md`) |

Rules for writing in it:

- **New live state goes in exactly two places:** one `CHANGELOG.md` entry and the owning
  runbook. Never in a document's header line, never as prose inside a table cell. Both of
  those are what caused the 2026-11-03 restructure.
- **`ACTUAL-CONFIGURATION.md` §15 is the running todo list.** Rows are status lines that
  point at a runbook's *Issue history*. Move an item to ✅ when resolved; never delete one.
- **Section numbers in `runbooks/` and `archive/` are preserved** from the dissolved
  `finish-installation-commands.md`, so numbering is not contiguous within a file. A `§N`
  reference anywhere still resolves: `grep -rn '§20g' runbooks/ archive/`. A **new** runbook
  numbers its own sections from §1.
- **Nothing is deleted.** Superseded material moves to `archive/` with a banner. The reason
  is in `archive/README.md` and it is not stylistic: a wrong conclusion that lived in *this
  file* blocked a real fix for three sessions, and the retracted reasoning is what made the
  fix possible (`runbooks/fingerprint.md` §20g, §20l).
- **After moving a section or renaming a document, run `tests/check-doc-refs.sh`.** It must
  report zero errors before you commit. It exists because the breakage is silent: a `§N`
  reference still reads correctly after its target has moved, and a file moved into a
  subdirectory goes on naming root documents with no `../` prefix. Write references to
  documents **relative to the referring file**; paths to config and source files keep
  their repo-root form (`configs/hypr/monitors.conf`).
- **Dates are in the 2026 timeline.** Do not "correct" them to a past year.
- Repo docs are written in **English**, including file comments in `configs/`.

## Hyprland config architecture

`configs/hypr/hyprland.conf` is a thin entrypoint that **sources modular files**:

```
hyprland.conf  → env.conf → monitors.conf → input.conf → look.conf
              → keybindings.conf → windowrules.conf → autostart.conf
```

Plus three sibling daemons with their own configs: `hyprpaper.conf`, `hyprlock.conf`,
`hypridle.conf`.

- **Edit the right modular file** — never dump behaviour into `hyprland.conf`. The three
  most-edited are `keybindings.conf`, `monitors.conf`, `autostart.conf` (`shortcuts.md` §11).
- **`hyprctl reload` re-reads all sourced files but not the sibling daemons.** Restart those
  individually: `pkill hyprpaper; hyprpaper & disown`.
- **`hyprpaper.conf` needs block syntax**, not flat `wallpaper = ...` lines — the installed
  0.8.4 has a config-parser bug and flat lines render **nothing, silently**. See
  `configs/hypr/hyprpaper.conf` and the `Hyprpaper wallpaper binding` row in
  `ACTUAL-CONFIGURATION.md` §15.
- **Any write to a sourced `.conf` auto-reloads Hyprland**, which snaps the screens back to
  `monitors.conf`'s boot geometry — re-apply the current profile after pushing configs.

## Working with config changes

`configs/` is a **mirror**, not the live config. There is no sync automation; keep both in
step by hand or the docs drift.

```bash
cp configs/hypr/<file>.conf ~/.config/hypr/<file>.conf   # push to live
hyprctl reload                                           # apply without logout
cp ~/.config/hypr/<file>.conf configs/hypr/<file>.conf   # pull a live edit back
```

- **Two mirrored system paths** — `configs/systemd/logind.conf.d/` →
  `/etc/systemd/logind.conf.d/` and `configs/modprobe.d/` → `/etc/modprobe.d/`. Push with
  `sudo install -Dm644 <repo file> <live path>`.
- **Always check the live copy exists before trusting the repo.** The logind lid drop-in sat
  in the repo from 2026-07-12 to 2026-10-12 without ever being installed while the docs
  called it live (`runbooks/boot-suspend.md` §15).
- **`configs/vlc/vlcrc` drifts by design** — VLC rewrites the whole file on exit. Do not try
  to keep it byte-identical; only `avcodec-hw=none` matters.

## Hardware and boot constraints

Easy to break, hard to debug.

- **NVIDIA + Wayland requires KMS**, satisfied by the driver-default `modeset` (610 series on)
  plus early module loading from `/etc/mkinitcpio.conf.d/10-chwd.conf`. **Do not add
  `nvidia-drm.modeset=1` to the kernel cmdline** — it is not there and does not need to be.
  The mechanism is kernel-agnostic, so it covers the LTS entry too. If KMS breaks, Hyprland
  black-screens. `ACTUAL-CONFIGURATION.md` §3.
- **The compositor and all three monitors run on the Intel iGPU** (aquamarine primary
  `card2`/i915, renderer `renderD129`). The dGPU is offload-only and its GSP firmware often
  fails to re-init after suspend/resume, dead until reboot. **Never design anything that
  assumes the dGPU renders the session or is available at all.**
- **Bootloader is Limine, not GRUB.** Persistent cmdline edits go in `/etc/default/limine`
  then `sudo limine-mkinitcpio`. **Never edit `/boot/limine.conf` directly** —
  `limine-mkinitcpio-hook` and `limine-snapper-sync` wipe it on the next kernel update or
  snapshot. `KERNEL_CMDLINE[default]` applies to *every* entry.
- **The LTS entry** (`linux-cachyos-lts`) is the escape hatch for bleeding-edge kernel bugs.
  It has **never been boot-tested** — verify its cmdline carries `thunderbolt.host_reset=0`
  and `mem_sleep_default=s2idle` before relying on it. `runbooks/boot-suspend.md` §0.
- **`hyprpolkitagent` is not on `$PATH`** (`/usr/lib/hyprpolkitagent/hyprpolkitagent`).
  `autostart.conf` starts it via `systemctl --user start hyprpolkitagent.service`.
- **Hardware cursor is disabled** in `look.conf` (`cursor.no_hardware_cursors = true`) to
  avoid NVIDIA artifacts. Do not re-enable without testing.
- **`env.conf`'s `env =` lines only reach processes Hyprland spawns** (keybinds, `exec-once`).
  Walker/Elephant launches apps from the systemd `--user` manager, which never sees them.
  **Never configure a Walker-launched app through `env.conf`** — that is why Firefox's
  video-decode pause lives in its profile `user.js` (`runbooks/gpu-video.md` §12). The same
  gap hid `XDG_SESSION_TYPE=wayland`, so `autostart.conf` pushes it with
  `dbus-update-activation-environment --systemd XDG_SESSION_TYPE` before starting elephant
  (`runbooks/desktop-apps.md` §7e). Current vars: `LIBVA_DRIVER_NAME=iHD` (iGPU, since
  2026-07-02), `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`,
  `MOZ_ENABLE_WAYLAND=1`, `ELECTRON_OZONE_PLATFORM_HINT=auto`.

### Battery, fans and the platform profile

- **The 80% charge cap is proven** (replacement Getac `AP20BHU` fitted 2026-10-31). It comes
  from AUR `acer-wmi-battery-dkms` plus `enable_health_mode=1` in
  `/etc/modprobe.d/acer-wmi-battery.conf`. **TLP and powerdevil charge thresholds do nothing
  on this machine** — the in-kernel `acer_wmi` has no charge-limit support and `BAT1` exposes
  no `charge_control_*` node. DKMS needs clang/lld/llvm (the main kernel is clang/ThinLTO).
  ⚠ With `BAT1` back, hypridle's battery-only suspend and lid-close-on-battery are **armed**,
  which is the NVIDIA GSP resume-crash path. `runbooks/power-battery.md` §14.
- **Fans and `/sys/firmware/acpi/platform_profile` exist only because of a forced module
  parameter:** `options acer_wmi predator_v4=1` in
  `/etc/modprobe.d/acer-wmi-predator-v4.conf`. The PT516-52s is absent from the driver's DMI
  quirk table, so without it there is no `acer` hwmon and no platform profile at all. It
  gives fan **reading** only (the quirk sets `.hwmon`, not `.pwm`) and no keyboard RGB. The
  parameter is `0444` — load-time only, never writable via sysfs. **After changing it,
  restart `power-profiles-daemon`**, which probes platform drivers once at startup.
  `runbooks/power-battery.md` §17.
- **`edp_mode()` in `monitor-mode.sh` is the only owner of eDP-1's refresh rate.** **Never
  write a `2560x1600@240` literal into that script** — it used to be hardcoded at 8 sites plus
  a 9th path through `apply_from_profile`, so anything setting the rate from outside was undone
  by the next profile apply, hotplug or `hyprctl reload`. It resolves the rate from
  `grep -q Discharging /sys/class/power_supply/BAT1/status` — **never `ACAD/online`**, which
  reads 1 when only the TB4 dock feeds the machine — plus the
  `~/.config/triton-panel/power-auto` toggle. `monitor-mode.sh edp-rate` is the reconcile hook
  driven by `scripts/power-autoswitch.sh`. `runbooks/power-battery.md` §19.

### Triton Panel

- **It writes the *live* `~/.config/hypr/hyprlock.conf`** when the *Unlock hyprlock with
  fingerprint* switch is used — a marker-delimited block (`# >>> triton-panel: fingerprint
  unlock >>>`). `hyprlock.conf` is **not** in `hyprland.conf`'s `source` list, so this does
  not trigger an auto-reload; hyprlock re-reads at the next lock. **`configs/hypr/hyprlock.conf`
  therefore drifts and must be pulled back by hand.**
- Fingerprint unlock needs **no PAM change** — hyprlock talks to fprintd over D-Bus, and the
  panel never edits `/etc/pam.d/sudo` (`chwd` already put `pam_fprintd` there).
  `runbooks/triton-panel.md` §18, `runbooks/fingerprint.md` §20.

### Fingerprint reader (`04f3:0c4f`, in-tree `elan`)

Enrolment works (`right-index-finger`, 6/6, 2026-11-01). ⚠ **Verify fails 4/4** — unlock is
wired and correct but not usable; the blocker is capture quality on a ~1 cm area pad. ⚠ Do
not overclaim the enrolment fix: the corrected instructions were already in place for a run
that got 0 of 8, so they are necessary but **not shown sufficient**. A second finger is the
reproducibility test. Three rules, all earned the hard way:

1. **A driver-reported property is evidence about the driver, not about the hardware.** Never
   build an instruction from `scan_type`: this driver declares `swipe` and the part is an
   area/press pad. `AREA_SENSORS` keys the physical type by **USB id**, `fprint_device()`
   exposes it as `info["gesture"]`, and every instruction site plus the hyprlock
   `ready_message` comes from that (`Touch`, not `Swipe`).
2. **`No minutiae found` is a geometry result, not a driver verdict.** An area pad driven as a
   swipe sensor fails the gesture *that* way, never as `too-short`/`too-fast`. Reading its
   absence as "not a gesture problem" is the error that became a rule in this file and blocked
   the fix for three sessions.
3. **`FP_DEVICE_ERROR_PROTO` is intermittent, not blocking.** A `driver` terminal result must
   **restart** the enrolment (`EnrollStop` + `EnrollStart`, claim kept, no second polkit
   prompt), and that branch must stay **before** `_stop()` — which disconnects `g-signal` and
   would hang the window with nothing in the log. Covered by `triton-panel/test-enroll.py`.

⚠ `pam_fprintd` in `/etc/pam.d/sudo` went live the moment a print existed, and its prompt is
built from `scan-type`, so `sudo` says "Swipe…" — **touch** the pad. It is `sufficient`, so
Enter falls through to the password. `runbooks/fingerprint.md` §20g–§20o.

## Monitors

Static 3-across `desktop` profile, in **logical** pixels (re-fitted for the Xiaomi 2026-08-03):

```
eDP-1                    (laptop 16",         0–2048px, scale 1.25, 240Hz)
desc:Xiaomi …Mi Monitor  (27" 4K,          2048–5120px, scale 1.25,  60Hz)  ← primary, workspace 1
desc:Invalid Vendor …RTK (portable QHD 16", 5120–7168px, scale 1.25, 120Hz)
```

Workspaces in `monitors.conf`: WS 1–3 → Xiaomi (primary), 4–5 → eDP-1, 6–9 → portable QHD.
The portable is a **VCHANCE AQ16H**; its Realtek scaler publishes no vendor string, so the
junk `Invalid Vendor Codename - RTK HDMI 0x01010101` *is* the `desc:` match key and the
serial is a placeholder that cannot disambiguate.

- **Never bind anything to `DP-1`/`DP-2`.** Both externals are DP tunnels over one
  Thunderbolt connector (Plugable TBT4-UD5), so whichever trains first takes the low number —
  the Xiaomi is *currently* `DP-2`, the reverse of what the names suggest. Match monitors
  **and workspaces** by EDID `desc:` (a prefix match); every profile in `monitor-mode.sh`
  resolves panels by capability. Name-bound rules had silently put workspaces 1–3 on the
  16" portable. Check live first:
  `hyprctl monitors -j | jq -r '.[] | "\(.name) = \(.description)"'`.
- **Never set a monitor `transform` with a bare `hyprctl keyword monitor` on an output that
  is already enabled.** Hyprland rotates the render pass but keeps the old layout box, so the
  tiling engine hands out landscape geometry on a portrait panel while `hyprctl monitors`
  reports the new transform — it looks correct and isn't. Go through `apply_monitor_tf()` in
  `monitor-mode.sh`, which cycles the output (disable → re-enable is the only thing that
  rebuilds the box). That cycle emits hotplug events, so it is paired with a fingerprint
  handshake that stops `monitor-autoswitch.sh` reverting a manual `Super+M` choice — **if you
  touch either script, keep both halves in step.**
- **`monitor-autoswitch.sh` is debounced** — it coalesces a hotplug burst and requires the
  monitor set to hold still before applying a profile. **Do not reintroduce a per-event
  `sleep`-and-apply loop.**
- **Hyprmon is only the editor.** Launch it through `scripts/hyprmon-edit.sh` and save with
  `P`. **Never use `hyprmon --profile` or its `S` key** — they set transforms with a bare
  keyword, rewrite `hyprland.conf` and `hyprctl reload`. (AUR `hyprmon-bin`; plain `hyprmon`
  is an unrelated project.) `apply_from_profile` applies
  `~/.config/hyprmon/profiles/<mode>.json` when its EDID `hardware_id`s match the connected
  set exactly, else the hand-written `apply_<mode>` runs. `Super+Shift+M` opens the Monitors
  menu. `runbooks/monitors.md` §16, `ACTUAL-CONFIGURATION.md` §1 / §11.
