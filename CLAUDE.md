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
exception is `triton-panel/`, which is real source (a GTK4 app). Six regression tests:
`triton-panel/test-enroll.py`, `triton-panel/test-battery.py`,
`tests/test-power-autoswitch.sh`, `tests/check-doc-refs.sh`,
`tests/check-live-system.sh` and `tests/check-libfprint-patch.sh`. Run them when you touch what they cover. The Python ones must
be run from inside `triton-panel/`.

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

**The config is Lua.** 0.57.1 removed the `hyprlang` parser (2026-11-03). Hyprland reads
`hyprland.lua` and nothing else — an explicit `--config hyprland.conf` is handed to the Lua
parser too — and **`hyprctl keyword` is gone as an IPC request** (`unknown request`, not
0.56's message about non-legacy parsers). Use `hyprctl eval '<lua>'`. The `.conf` files are
inert and kept only for reference. `runbooks/updates.md` §4.

```
hyprland.lua  → sets package.path from its own location, then requires lua/:
   env · monitors · workspaces · input · look · windowrules · qconsole
   · bindings-apps · bindings-tiling · bindings-utilities · bindings-clipboard · autostart
```

Plus three sibling daemons with their own, still-hyprlang configs: `hyprpaper.conf`,
`hyprlock.conf`, `hypridle.conf`.

- **Edit the right module** — never dump behaviour into `hyprland.lua`. Every module is
  `require`d, so it has **its own scope**: a Lua error takes out one file, not the session.
- **The API reference for writing these files is
  `/usr/share/hypr/stubs/hl.meta.lua`**, which the package ships and which is generated from
  the running binary. Check a key or a dispatcher there before writing it: config keys use
  underscores where hyprlang used dashes (`tap_to_click`), a wrong key is accepted **in
  silence**, and the dispatchers are declared untyped — so test an uncertain one with
  `hyprctl eval` on the live session rather than guessing (that is how
  `hl.dsp.window.set_prop({prop="alpha"})` was found to answer *Invalid prop name*).
- **`Hyprland --verify-config -c <repo>/configs/hypr/hyprland.lua` is the gate before every
  push.** It prints `config ok`, runs nothing, and because `package.path` is derived from the
  entrypoint's own path it checks the **repo's** modules instead of silently reading the live
  ones.
- **A write to a `.lua` does NOT auto-reload.** Measured on both a module and the entrypoint:
  the log does not move. hyprlang's write-triggers-reload is gone, so a push needs an explicit
  `hyprctl reload` — and the screens no longer snap back to boot geometry on every file write.
- **`hyprctl reload` re-runs the whole Lua config but does NOT re-fire
  `hl.on("hyprland.start")`**, so nothing in `autostart.lua` comes back. Start what you need
  by hand after a push, or log out. It also does not touch the sibling daemons: restart those
  individually (`pkill hyprpaper; hyprpaper & disown`).
- **Nothing in a `.lua` may shell out slowly** — the config reload budget is ~1.5 s. Read a
  file; do not call a script.
- **Emergency mode survived into 0.57.1**: a Lua error that registers no binds leaves
  `SUPER + Q` alive. That plus
  `cp /usr/share/hypr/hyprland.lua ~/.config/hypr/hyprland.lua && hyprctl reload` is the
  rollback.
- **`hyprpaper.conf` needs block syntax**, not flat `wallpaper = ...` lines — a config-parser
  bug renders flat lines as **nothing, silently**. ⚠ The bug was found on 0.8.4 and the
  installed version has since moved, with no retry; which version is live, and whether the
  workaround is still needed, is in `runbooks/updates.md` §3 — do not re-derive it here. See
  `configs/hypr/hyprpaper.conf` and the `Hyprpaper wallpaper binding` row in
  `ACTUAL-CONFIGURATION.md` §15.

## Working with config changes

`configs/` is a **mirror**, not the live config. There is no sync automation; keep both in
step by hand or the docs drift.

```bash
Hyprland --verify-config -c "$PWD/configs/hypr/hyprland.lua"   # gate: must print "config ok"
install -m644 configs/hypr/hyprland.lua ~/.config/hypr/hyprland.lua
install -m644 configs/hypr/lua/*.lua    ~/.config/hypr/lua/    # push to live
hyprctl reload                                                 # apply without logout
cp ~/.config/hypr/lua/<file>.lua configs/hypr/lua/<file>.lua   # pull a live edit back
```

- **Two mirrored system paths** — `configs/systemd/logind.conf.d/` →
  `/etc/systemd/logind.conf.d/` and `configs/modprobe.d/` → `/etc/modprobe.d/`. Push with
  `sudo install -Dm644 <repo file> <live path>`.
- **Always check the live copy exists before trusting the repo.** The logind lid drop-in sat
  in the repo from 2026-07-12 to 2026-10-12 without ever being installed while the docs
  called it live (`runbooks/boot-suspend.md` §15).
- **`configs/vlc/vlcrc` drifts by design** — VLC rewrites the whole file on exit. Do not try
  to keep it byte-identical; only `avcodec-hw=none` matters.

## Updating packages

The one routine operation that can silently revert a documented fix. Full procedure in
`runbooks/updates.md`.

- **Always `paru -Syu`. Never `pacman -Sy`, never `pacman -S <pkg>`.** The kernel,
  `linux-cachyos-nvidia-open` and `nvidia-utils` are version-locked to each other; installing
  one against a refreshed database is a partial upgrade, KMS fails and Hyprland black-screens.
  **Never `IgnorePkg` the kernel or NVIDIA** — that is the same break, held open.
- **Run `tests/check-live-system.sh` before and after an upgrade, and again after the reboot.**
  `--strict` is the pre-upgrade gate. It is read-only and needs no sudo. A FAIL means an
  invariant this repo documents is broken — fix it, or correct the document that claims it.
- **`.pacnew` files are merged with `DIFFPROG='vim -d' pacdiff -s -3`, never with `mv`.**
  Four of them carry hand-edited lines on this machine; the table of which lines must survive
  is `runbooks/updates.md` §2. Dropping the `[cachyos-*-v3]` repo sections from
  `/etc/pacman.conf` is the quietest failure available — pacman keeps working and just stops
  delivering `x86-64-v3` builds.
- **Do not prune the package cache to one version.** `paccache -k3`: the cache is the
  three-way merge base for `pacdiff -3` and the only downgrade path.
- **A drop-in under any `*.conf.d/` beats the main `.conf`, including a packaged one under
  `/usr/lib/`.** So `/etc/systemd/system.conf`'s `DefaultTimeoutStopSec=15s` is **inert** —
  `cachyos-settings` ships `00-timeout.conf` with `10s` and wins. Check an effective systemd
  value with `systemd-analyze cat-config`, never by reading the file. `runbooks/updates.md` §2c.
- **After any upgrade, re-read `runbooks/updates.md` §3.** Several open items are waiting on a
  version rather than on an idea, and an upgrade moves the premise without moving the note.

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
- **`scripts/edp-rate.sh` is the only owner of eDP-1's refresh rate** (moved there
  2026-11-03 from `edp_mode()` in the now-parked `monitor-mode.sh`; same logic, applied with
  `hyprctl eval 'hl.monitor({...})'` because `keyword` is gone). **Never write a
  `2560x1600@240` literal anywhere else** — it used to be hardcoded at 8 sites plus a 9th
  path through `apply_from_profile`, so anything setting the rate from outside was undone by
  the next profile apply, hotplug or `hyprctl reload`. It resolves the rate from
  `grep -q Discharging /sys/class/power_supply/BAT1/status` — **never `ACAD/online`**, which
  reads 1 when only the TB4 dock feeds the machine — plus the
  `~/.config/triton-panel/power-auto` toggle, and keeps all three guards (output must be
  enabled, skip while DPMS is off, emit only on a real change).
  `scripts/power-autoswitch.sh` calls it every stable tick.
  `runbooks/power-battery.md` §19.

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

⚠ **There are currently ZERO prints enrolled** (since 2026-11-03 17:16) and ⚠ **enrolment
is blocked below the panel**: a protocol error lands between two stages, fprintd discards
the partial enrolment, and the restart loop begins at stage 1 — measured ten times in 44 s
without once reaching stage 2, with contact of 1.2–1.4 s and the stages being *accepted*.
The 6/6 of 2026-11-01 is the run that logged **zero** protocol errors; that is what made
it work, not the technique. ⚠ **The cause is found and is three lines in `elan.c`**: the sensor's own documented status
bytes `0x00` ("not ready") and `0xaf` ("finger removed or sensor busy") are retried only
when `dev_type == ELAN_0C58` and are a **fatal** `FP_DEVICE_ERROR_PROTO` for `0c4f`, which
carries no quirk bit. `patches/libfprint-elan-0c4f-busy-retry.patch` fixes it and is
⚠ **not applied** — building needs `meson`, `gobject-introspection`, `gtk-doc` and
`umockdev`, **none of them installed**. The upgrade ran 2026-11-03 and its reboot landed
2026-11-04, so the only step owed is
`paru -Syu --needed meson gobject-introspection gtk-doc umockdev`. The upgrade left
`libfprint` at 1.94.100, which is also upstream's **newest tag**, so the hunks still apply
and no *released* version carries this fix (upstream's default branch was never checked — the
`origin/main` fetch failed on the branch name). Try the patch **alone** before the
`FP_SCAN_TYPE_PRESS` line or the `elanpress` fork, and expect it to fix enrolment, not
matching (`runbooks/fingerprint.md` §20x). Do not spend another pass on the panel: every measurement puts the fault
under it. That print was **destroyed by
starting an enrolment into its own slot** — see rule 8. Verify never once matched it
(7/7 failures): the blocker is the stored **template** on a ~1 cm area pad more than
detection — the 2026-11-03 calibration got 6 of 13 attempts to the matcher and all 6
scored below the bz3 threshold — but 7 of 13 never reached it, so the capture ceiling is
real too. The hyprlock switch turned itself **off** when
the last print went (`_on_fp_delete` does that), so the managed block is gone from the
live `hyprlock.conf` and the mirror was pulled back to match. ⚠ Do
not overclaim the enrolment fix: the corrected instructions were already in place for a run
that got 0 of 8, so they are necessary but **not shown sufficient**. A second finger is the
reproducibility test. Nine rules, all earned the hard way:

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
4. **Nothing here may hold the device armed for more than three minutes.** libfprint's
   thermal model is a **clock, not a thermometer**: 180 s of being *armed* — waiting for a
   finger counts as use — and the reader is cut off, then refuses everything for ~3.5 min
   more. Measured with no finger anywhere near the pad. So an enrolment must **fit** inside
   the budget, and a session that ran longer was measuring the lockout, not a hand. Measure
   it with `fp-debug.sh thermal`, which needs no finger.
5. **`verify-disconnected` is three different errors behind one string** — `TOO_HOT`,
   `PROTO`, `REMOVED` — collapsed by fprintd's `verify_result_to_name()`, and 1.94.5
   publishes no `temperature` property. **Read `journalctl -u fprintd`, never the D-Bus
   string**, and never call it a disconnect: the sensor has never left the USB bus here.
6. **A `*-swipe-too-short` with no `finger-present` since the last result the panel
   accounted for is the driver's own capture timeout, never a placement.** `elan` re-arms every `ELAN_CMD_TIMEOUT` (10 s) and
   calls an empty capture too short, so an **untouched** pad emits one every ten seconds.
   Measured: 4 real touches reported presence, 2 phantoms reported none, and fprintd logs
   nothing at all for a phantom. Never build a verdict out of one — not about the hand
   ("stay on the sensor longer") and not about the hardware ("the driver may simply not
   handle this sensor"). Both were being said to an idle reader.
7. **The panel's attempt log is in a FILE, not the journal.**
   `$XDG_STATE_HOME/triton-panel/panel-<ts>.log` (`TRITON_PANEL_LOG_DIR` overrides; the
   path is shown in the window). Read that, not `journalctl --user`: Walker starts the
   panel through `systemd-run` and that output is collected nowhere, which is how two
   sessions on 2026-11-03 became permanently unreconstructible. ⚠ And fprintd's journal
   cannot stand in — it is **silent** for an accepted enrol stage and for
   `verify-no-match`, so "nothing in the journal" means nothing at all.
8. **Starting an enrolment DELETES the print in that slot, before the first stage.**
   fprintd's `fprint_device_enroll_start` does `store.print_data_load` then
   `delete_enrolled_fingers` on an existing print; the new one is written only on
   completion, in `enroll_cb`. So an abandoned or failed enrolment leaves the slot
   **empty** — that is how the 2026-11-01 print was lost. **Always enrol into a free
   slot** while any print you care about exists; the slot name is only a label, so a free
   one can hold the same physical finger. "Do not delete it" is not enough protection.
9. **A `driver` result is never "the same press".** `runbooks/fingerprint.md` §20s's gate
   that stops one contact being counted twice must exclude bucket `driver`, or it swallows
   the faults — and the thermal check lives *below* it, so a lockout with a finger on the
   pad is suppressed for the whole cooldown and never entered. §20v.

⚠ `pam_fprintd` in `/etc/pam.d/sudo` went live the moment a print existed, and its prompt is
built from `scan-type`, so `sudo` says "Swipe…" — **touch** the pad. It is `sufficient`, so
Enter falls through to the password. (With zero prints enrolled it falls straight through
and `sudo` does **not** wait on the reader; that returns the moment one exists.) `runbooks/fingerprint.md` §20g–§20x.

⚠ **Calibration spends the budget the enrolment needs.** It is a verify loop that
only stops when its gate opens, so for an *enrolment* attempt skip it — and restart
`fprintd` first (`./fp-debug.sh rebind` does), because libfprint keeps the estimate on
the `FpDevice` in the **daemon**: a window's `armed Ns of 180s` counter is a lower bound
that cannot see what a lock screen or an earlier window already spent. ⚠ And **launch the
panel from a terminal when diagnosing** — from Walker its attempt log goes through
`systemd-run` and reaches no journal, and the fprintd journal cannot stand in: it is
silent for `verify-no-match`. `runbooks/fingerprint.md` §20u.

⚠ **Fingerprint unlock is dead on any lock older than ~3 minutes** and hyprlock never
re-arms (it also skips `releaseDevice()` on that path, so it holds the claim until it exits).
Upstream `main` behaves the same. Do not debug a lock-screen non-detection as a capture
problem before checking the clock. `runbooks/fingerprint.md` §20t.

## Monitors

Static 3-across `desktop` profile, in **logical** pixels (re-fitted for the Xiaomi 2026-08-03):

```
eDP-1                    (laptop 16",         0–2048px, scale 1.25, 240Hz)
desc:Xiaomi …Mi Monitor  (27" 4K,          2048–5120px, scale 1.25,  60Hz)  ← primary, workspace 1
desc:Invalid Vendor …RTK (portable QHD 16", 5120–7168px, scale 1.25, 120Hz)
```

Workspaces are **per monitor** since 2026-11-03 (`configs/hypr/lua/workspaces.lua`):
`Super+1..0` always means *the Nth workspace of the screen you are looking at*. Each panel
owns a static block of ten ids anchored by EDID — eDP-1 `1-10`, Xiaomi `11-20`, portable QHD
`21-30`, anything unknown `91-100`. **Add a row to `BLOCKS` when a fourth panel becomes
permanent**, or it shares the fallback block with every other stranger.
`runbooks/monitors.md` §21.
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
- **⚠ The whole monitor PROFILE system is parked** as of 2026-11-03 — `monitor-mode.sh`
  (five layouts, `apply_monitor_tf()`, the fingerprint handshake), `monitor-autoswitch.sh`
  (debounced hotplug) and `monitor-menu.sh` all drive the live layout through
  `hyprctl keyword monitor`, which 0.57.1 removed. They are **not started and not deleted**:
  `configs/hypr/lua/monitors.lua` is now the only owner of geometry, and there is no profile
  switching or hotplug reconcile. Port them to `hyprctl eval 'hl.monitor({...})'` before
  relying on any of it again. `runbooks/monitors.md` §16.
- **Setting a `transform` still needs the output cycled.** Hyprland rotates the render pass
  but keeps the old layout box, so the tiling engine hands out landscape geometry on a
  portrait panel while `hyprctl monitors` reports the new transform — it looks correct and
  isn't. `disabled = true` then re-enable is the only thing that rebuilds the box; that was
  `apply_monitor_tf()`'s whole job, and whatever replaces it must keep doing it. The cycle
  emits hotplug events, so **if the autoswitcher ever comes back, its fingerprint handshake
  and this cycle must stay in step.**
- **⚠ Hyprmon is parked with it** and is **not bound to any key**. It is hyprlang-era
  throughout: its `A` applies a transform with a bare `hyprctl keyword monitor`, its `S`
  rewrites `monitor=` lines in `hyprland.conf` (now inert), and the JSON profiles its `P`
  saves are only read by `apply_from_profile` in the parked `monitor-mode.sh`.
  `runbooks/monitors.md` §16, `ACTUAL-CONFIGURATION.md` §1 / §11.
