# Changelog

Append-only history of this machine's live state. **Newest first.**

This file exists because the history used to live in `ACTUAL-CONFIGURATION.md`'s
`**Last updated:**` line, which had grown to 13 KB — a changelog stuffed into a
metadata field. Writing there cost nothing and refreshing the sections below it
cost real work, so the snapshot rotted while the header grew. Separating them
removes that incentive.

**When live state changes:** add one entry here *and* update the owning runbook
(see `runbooks/README.md`). Do not grow a document's header, and do not put
narrative into a table cell.

Entries before 2026-11-03 were moved here verbatim from that header line; their
internal cross-references were re-pointed to the files those sections now live in.

In those entries a bare `§N` means a section of `ACTUAL-CONFIGURATION.md` unless the
surrounding sentence names another document. Numbers inherited from the dissolved
remediation doc are findable either way: `grep -rn '§N' runbooks/ archive/`.

---

## 2026-11-04 — The owed reboot landed: 19/0, the Lua config cold-booted, four premises moved

Booted 09:05 on `7.3.1-1-cachyos`, the reboot the 662-package upgrade of 2026-11-03 had been
waiting for. `tests/check-live-system.sh` reports **19 passed, 0 failed**, one warning and six
notes. The two FAILs the 2026-11-03 entry recorded as "not faults" were artefacts of the
un-rebooted kernel and are **both gone**, exactly as that entry predicted: `dkms
acer-wmi-battery (running)` and `kernel is the installed one` now PASS.

**Verified by this boot, and only obtainable from a boot:** `predator_v4=Y` after a real
`acer_wmi` load, with `platform_profile` present and the `acer` hwmon at `hwmon5` — the
parameter is `0444`, so a boot is the only thing that ever sets it; `health_mode=1` for the
80 % cap; `nvidia` module and `nvidia-utils` both at **615.78.08**, so the version lock held
and KMS came up.

**The Lua config cold-booted.** `hyprctl reload` by design cannot fire
`hl.on("hyprland.start")`, and 0.57.1's own upgrade reboot came up on upstream's example
config, before this one existed — so this is the first session start this repo has measured on
the migrated config: `hyprctl configerrors` clean and all **twelve** `autostart.lua` entries up
(elephant, walker, waybar, mako, hyprpaper, hypridle, hyprpolkitagent, swayosd, both
`wl-paste` watchers, nm-applet, `power-autoswitch.sh`), with `scripts/edp-rate.sh` resolving
240 Hz off `BAT1=Charging`. Whether an interim logout on 2026-11-03 had already exercised the
handler is not recorded. `runbooks/updates.md` §4c.

**What the reboot moved, which is the part that needed writing down.** Four of the six rows in
`runbooks/updates.md` §3 now describe versions this machine no longer runs, and not one of the
four conclusions was re-measured: the i915 `__gen8_ppgtt_clear` deref was found on kernel
7.0.12 and 7.3.1 is the third kernel since; `hyprpaper` is **0.8.5-3.1**, so the block-syntax
workaround for 0.8.4's parser bug rests on a version that is gone; NVIDIA GSP's resume crash
was recorded on 615.71.09; `linux-cachyos-lts` is **6.18.55-2** and the rollback path has still
never booted once. `libfprint` is the one premise that held still at 1.94.100 — which is the
only reason `patches/libfprint-elan-0c4f-busy-retry.patch` still applies. `CLAUDE.md` was
carrying the dead `hyprpaper 0.8.4` claim in its own text, against its own rule; the version
now lives only in §3.

**Still owed, in the order the dependencies force.** The 11 `.pacnew` are untouched;
`/etc/pam.d/sudo.pacnew` was diffed and behaves exactly as `runbooks/updates.md` §2a predicts —
it drops `auth sufficient pam_fprintd.so` (keep) and adds `session optional pam_systemd.so
class=none` (adopt). Then `meson`, `gobject-introspection`, `gtk-doc`, `umockdev` are **still
none installed**, so the libfprint patch is unbuilt and enrolment is still blocked; `hyprpicker`
is still missing and one `paru -Syu --needed` closes both. Three mirrored files drifted
repo → live in comments only — the live `acer-wmi-predator-v4.conf` is still the Spanish draft,
and two files still cite the dissolved `finish-installation-commands.md`.

**Not verified, recorded so it is not mistaken for verified:** the dock was disconnected, so
only `eDP-1` enumerated and `lua/monitors.lua` plus the per-monitor workspace `BLOCKS` remain
untested against the externals; no suspend was taken, so GSP on 615.78.08 is unmeasured; the
battery sat at 54 % charging, so the 80 % cut-off was not reached; the AC↔battery transition is
still untried.

---

## 2026-11-03 — Hyprland 0.57.1 removed `hyprlang`: the config is Lua, with Omarchy's keymap

**The upgrade's reboot came up on upstream's example config.** 0.57.1 **removed** the
`hyprlang` parser. With no `hyprland.lua` present it writes `/usr/share/hypr/hyprland.lua`
into `~/.config/hypr/` and runs that, so the session had no bar, no wallpaper, no keybinds,
one monitor, none of `env.conf`'s variables — and `hyprctl configerrors` clean the whole
time. The 13-file `.conf` tree was read by nobody. `Super+M`, which this machine binds to a
monitor profile, was `exit` in the example.

What the evidence was: `[cfg] Regular config at …/hyprland.lua` + `No config file found;
attempting to generate` where 0.56.2 logged `using legacy config at …/hyprland.conf`;
`Hyprland --verify-config -c hyprland.conf` answering `hyprland.conf:2: unexpected symbol
near '/'` (the explicit path goes to the **Lua** parser, so there is no way back);
`strings /usr/bin/Hyprland` without `using legacy config` but with `RIP hyprlang`; and
`hyprctl keyword` answering **`unknown request`** rather than 0.56's "use eval".

**Migrated the same evening, keymap replaced rather than ported.** Omarchy has itself moved
to Lua (branch `quattro`, every file `.lua`), so its config served as the reference
implementation for this binary, and its shortcut system was adopted deliberately:

- `configs/hypr/hyprland.lua` + `configs/hypr/lua/*.lua` — 13 modules in the same shape as
  the old split. The entrypoint derives `package.path` from its own location, so
  `Hyprland --verify-config -c <repo>/configs/hypr/hyprland.lua` verifies the repo's modules
  and not the live ones. It prints `config ok` and is the gate before every push.
- **137 binds, 118 of them described** (the old `keybindings.conf` had 58 `bind*` lines). `lua/bind.lua` carries a `description` into
  `hyprctl binds -j`, and `scripts/show-shortcuts.sh` now **generates** the `Super+K`
  cheatsheet from it, so the cheatsheet cannot drift from the binds again.
- Adopted from Omarchy: Quake console (`Super+grave`), scratchpad (`Super+S`), window groups
  (`Super+G`), Alt+Tab cycling, three-scale keyboard resize on `Super+-`/`=`, workspace and
  window moves across monitors, `Super+Tab` per-monitor workspace walking, swap instead of
  move on `Super+Shift+arrows`, maximize on `Super+Alt+F`, screen zoom, colour picker,
  notification control through `makoctl`, transparency and gaps toggles, the clamshell lid
  bind, and the universal clipboard on `Super+C/V/X/A` (floating moved to `Super+T`).
- **Workspaces are per monitor** — ten slots per panel, blocks anchored by EDID
  (`runbooks/monitors.md` §21). Omarchy's own 713-line implementation was *not* imported:
  its tie-break orders by connector name, which is what rotates between `DP-1`/`DP-2` here.
- Decided: lock moved to `Super+Ctrl+L` with `Super+L` left free; `Super+M` minimizes and the
  monitor chords moved to Omarchy's display slots; `Super+Ctrl+Delete` toggles the laptop
  panel natively.

**Parked, not deleted:** `monitor-mode.sh` (five profiles, `apply_monitor_tf`),
`monitor-autoswitch.sh`, `monitor-menu.sh`, `hyprmon-edit.sh` — all of them apply through
`hyprctl keyword`. `lua/monitors.lua` is the only owner of geometry meanwhile. The one piece
that could not wait was lifted out verbatim into **`scripts/edp-rate.sh`**: eDP-1's refresh
rate following the power source, now applied with `hyprctl eval 'hl.monitor({…})'`.
`power-autoswitch.sh` calls it and `tests/test-power-autoswitch.sh` still passes 10/10.

**Verified live:** `config ok`; `configerrors` clean; 137 binds registered including the
`switch:` lid binds and all 47 keycode binds; `cursor:no_hardware_cursors` back to `1`;
`tests/check-live-system.sh` **19 passed, 0 failed** (was 18/1 — hyprpaper was the failure);
`check-doc-refs.sh` 0 errors. And the power chain end to end on battery: `hyprctl reload`
restored 240 Hz from `lua/monitors.lua`, the next tick took eDP-1 to 60 Hz and the platform
profile to `low-power`.

**Measured, and worth knowing:** a write to a `.lua` does **not** auto-reload anything (what
hyprlang did); `hyprctl reload` does **not** re-fire `hl.on("hyprland.start")`, so no daemon
duplicates and none restarts; a wrong config key is accepted in silence, so
`/usr/share/hypr/stubs/hl.meta.lua` is the only ground truth; the dispatchers are untyped
there, so `hl.dsp.window.set_prop({prop = "alpha"})` had to be tested to find out it answers
*Invalid prop name*; punctuation keysyms need lower case (`grave`, `slash`, `comma`).

⚠ **Not verified:** the dock (Plugable TBT4-UD5) was `disconnected` throughout, so the two
`desc:` monitor rules and the 11–20 / 21–30 workspace blocks have never been seen to bind.
⚠ `hyprpicker` for the new `Super+Print` is not installed — it waits for the next full
`paru -Syu`. ⚠ Three predictions this repo had written down about the migration were wrong;
they are kept and retracted in `runbooks/updates.md` §4g, the most useful being that Lua
*does* expose monitor hotplug events, so the autoswitcher can become a Lua handler.

→ `runbooks/updates.md` §4, `runbooks/monitors.md` §16 / §21,
`runbooks/power-battery.md` §19, `shortcuts.md` §1

## 2026-11-03 — Upgrade: 662 packages, kernel 7.3.1, NVIDIA 615.78.08 — ⚠ reboot owed

First full upgrade since **2026-09-26** — the five-week gap
`runbooks/updates.md` §1 warns about. `paru -Syu` started 18:47:56 and moved
**662 packages**, with the whole version-locked set in one transaction:

| package | from | to |
|---|---|---|
| `linux-cachyos` + `-headers` | 7.2.8-1 | **7.3.1-1** |
| `linux-cachyos-nvidia-open` | 7.2.8-1 | **7.3.1-1** |
| `nvidia-utils` | 615.71.09-1 | **615.78.08-2** |
| `nvidia-settings` | 615.71.09-1 | 615.78.08-1 |
| `linux-cachyos-lts` + `-headers` + `-nvidia-open` | 6.18.52-1 | 6.18.55-2 |
| `pam` | 1.7.2-2.1 | 1.7.3-1.1 |

⚠ **The pre-reboot gate reports two FAILs and both are the expected
post-upgrade state, not breakage.** Neither is to be "fixed" by installing
anything — that is the partial upgrade `CLAUDE.md` forbids:

- `dkms acer-wmi-battery (running) — not installed for 7.2.8-1-cachyos`. The
  transaction replaced the running kernel's module tree: `/usr/lib/modules`
  now holds only `6.18.55-2-cachyos-lts` and `7.3.1-1-cachyos`. `dkms status`
  reports the module **built and installed for both**, so nothing needs
  rebuilding. ⚠ And the cap is **not** dead meanwhile: `acer_wmi_battery` is
  still loaded from before the upgrade and
  `/sys/bus/wmi/drivers/acer-wmi-battery/health_mode` reads `1` in the same
  report. What is impossible until the reboot is *reloading* it. The checker's
  FAIL text ("the charge cap is dead") is written for the unloaded case and
  overstates this one.
- `nvidia module 615.71.09, package 615.78.08 — partial upgrade`. The loaded
  module is the old one because the new one cannot load into the running
  kernel. This is what every kernel + NVIDIA upgrade looks like until reboot.

**The upgrade produced no new `.pacnew` at all** — the newest of the 11 pending
is dated 2026-10-17. They are the audit's backlog, minus
`cachyos-mirrorlist.pacnew`, which is no longer on disk; when that one went is
not recorded. ⚠ The one that matters most is `/etc/pam.d/sudo.pacnew` (dated
**2026-06-17**, owned by `sudo`, not by `pam`): it **drops**
`auth sufficient pam_fprintd.so # chwd-fprintd` and **adds**
`session optional pam_systemd.so class=none`. A `mv` would silently end
fingerprint `sudo`; the merge is `DIFFPROG='vim -d' pacdiff -s -3` and the
keep/take split was already tabulated in `runbooks/updates.md` §2a.

`libfprint` and `fprintd` were **not** upgraded — still `1.94.100-1.1` and
`1.94.5-2.1` — so §20x's patch still applies to the installed source exactly as
verified. 1.94.100 is also upstream's **newest tag**, so no upgrade was ever
going to deliver that fix.

`runbooks/updates.md` *Issue history* has the pending list and the post-reboot
checklist.

---

## 2026-11-03 — Fingerprint: the cause is three lines in libfprint's elan driver

Reading the driver was cheaper than measuring it. `elan.c`'s
`capture_run_state` has exactly **one** `FP_DEVICE_ERROR_PROTO` site, and the
retry that avoids it is gated on `dev_type == ELAN_0C58`:

```c
else if (self->dev_type == ELAN_0C58 && self->last_read &&
         (self->last_read[0] == 0x00 || self->last_read[0] == 0xaf))
  /* 0x00 - not ready
   * 0xaf - finger removed or sensor busy (seen on 0x0c58) */
  fpi_ssm_jump_to_state_delayed (ssm, CAPTURE_WAIT_FINGER, 10);
```

⚠ `0c4f` carries no quirk bit, so for this reader those two **documented,
transient** status bytes become a fatal protocol error. `0xaf` is literally
*"finger removed or sensor busy"* — which is the state the sensor is in
between two enrolment stages, and it is why the reported symptom was *"al
levantar el dedo la borra"*. It also explains why calibration survives the
same error rate (each verify is independent, nothing to discard) while
enrolment cannot (one operation across six captures, discarded whole), and why
the 6/6 of 2026-11-01 logged zero protocol errors — the sensor happened to be
ready at all six transitions.

`patches/libfprint-elan-0c4f-busy-retry.patch` gives `0c4f` a unique
`driver_data` bit and lets it take the same retry — **not** widened to all
devices, which would change behaviour for untestable hardware. Every
`dev_type` site was audited against the new bit and the audit is a test,
`tests/check-libfprint-patch.sh`, because that is the failure that would be
silent: 7 passed, 0 failed, and the patch applies cleanly to a pristine
v1.94.100. ⚠ The `FP_SCAN_TYPE_SWIPE` change §20q has wanted since the eighth
pass was deliberately **not** bundled — it addresses the separate
`No minutiae found` thread, and two changes at once make the result
uninterpretable.

⚠ **Nothing was applied.** Building needs `meson`,
`gobject-introspection`, `gtk-doc` and `umockdev`, none installed, and
installing them against a refreshed database is the partial upgrade `CLAUDE.md`
forbids while an upgrade backlog is outstanding. So the order is: the
pre-upgrade gate, `paru -Syu`, the reboot, then the build — and the first
build should be tested through a drop-in under `/run` (tmpfs; a reboot undoes
it) rather than by installing a package. `patches/README.md` has the commands
and the rollback. The patch is **not compiled**: `fpi-enums.h` is generated by
meson. New top-level `patches/` directory, whose first rule is that nothing in
it is applied. `runbooks/fingerprint.md` §20x.

---

## 2026-11-03 — Fingerprint: the blocker is a protocol error *between* stages

The log file added hours earlier paid for itself in one read. Reported as
*"solo me acepta la primera ingresada y al levantar el dedo la borra"*, and
that is exactly it — ten cycles in 44 s:

```
stage:  Accepted — stage 1 of 6, 1.29s of contact
driver: Reader cut off
info:   Restarted enrollment (N) — fprintd discarded 1 stage(s)
```

**stage 2 was never reached once.** Journal for the same window: 7 ×
`during enroll` protocol error, 3 × `during identify for enroll`, 6 ×
`No minutiae found`. Contact was 1.20–1.40 s throughout and six stages were
*accepted*, so capture is not what fails here: the enrolment cannot survive
the gap between two stages. fprintd writes the print only on completion, so
one fault discards the whole partial template and the restart loop begins at
stage 1.

⚠ Not *on the lift*, though it feels that way: the accept is logged at the
lift and two faults arrived 5 s after it. What they share is landing while the
driver **arms the next capture on an empty pad** — the state §20j saw
transition invalidly — but that line is debug level and **absent** from this
journal, so it is a hypothesis, not the mechanism. ⚠ This does explain the 6/6
of 2026-11-01 completely: that run logged **zero** protocol errors, so the
restart loop never fired. Device state, not technique.

Also found in fprintd's source: the duplicate `fp_device_identify` that runs
before every `enroll_start` is gated on
`fp_device_has_feature(FP_DEVICE_FEATURE_IDENTIFY)` **alone**, with no check
that any print exists — so each restart costs a full extra device operation,
and 3 of the 10 faults came from it.

Applied: `MAX_STALLED_RESTARTS = 3` in Triton Panel, firing only when exactly
one stage was ever reached — not zero (the 6/6 run needed the loop to survive
faults *before* any stage passed) and not more (that is the intermittent case
`MAX_RESTARTS` covers). Its message names the layer and points at
`./fp-debug.sh press`, deliberately **not** at `rebind`: nothing is wedged
when the captures are being accepted. The first draft used `<= 1` and two
existing tests caught it.

⚠ Next step, and the only one worth taking first: **`./fp-debug.sh press` with
`G_MESSAGES_DEBUG=all`**, unrun since §20j. After that, and only after,
`FP_SCAN_TYPE_PRESS` for `elan` (§20q) is the best-motivated candidate it has
ever been, with the smallest blast radius it has ever had — the hyprlock block
is gone and password auth is on.

`test-enroll.py` 282 → **303 assertions, all passing**; `test-battery.py`
passing; widgets re-smoked; doc refs 0 errors; `check-live-system.sh` 19
passed, 0 failed. No live configuration changed by this pass.
`runbooks/fingerprint.md` §20w.

---

## 2026-11-03 — Fingerprint: starting an enrolment deletes the print in that slot

⚠ **There are now zero prints enrolled.** The 6/6 print of 2026-11-01 was lost
at 17:16:23, and what took it was **starting an enrolment into its own slot**.
Read in fprintd 1.94.5's `src/device.c` rather than inferred —
`fprint_device_enroll_start` does `store.print_data_load` and, if a print
exists, `delete_enrolled_fingers` → `store.print_data_delete`, **before the
first stage**; the new print is written only on completion, in `enroll_cb` via
`store.print_data_save`. So an enrolment that is abandoned or that fails leaves
the slot **empty**. The evidence chain: the calibration logged `Scoring against
— Right index` until 17:16:17 (that string comes from `VerifyFingerSelected`,
so the print existed), the enrolment started at 17:16:23, and no stage, no
`during enroll` journal line and no crash followed. Not a manual delete —
that path removes the hyprlock block, which is still live with
`enabled = true`. Triton Panel's occupied-slot warning had said enrolling
*"OVERWRITES"* the slot, which reads as *on success*; it now names both source
calls and says the deletion happens at the start. ⚠ Remaining live state:
**zero prints with the hyprlock switch still on** — a pairing the panel's own
delete path forbids. `pam_fprintd` stays `sufficient` and with no print falls
straight through, so `sudo` no longer waits on the reader. A confirmation
dialog for an occupied slot is the obvious hardening and was **not** built
unasked.

The same session exposed a defect in the tenth pass. §20s's *"is this a new
press?"* gate never excluded bucket `driver`, so across 32 s **every**
suppression was a `verify-disconnected`: it caught no repeat press at all, told
the user to lift a finger off a reader that had stopped reading, kept
`_cal_dry` at zero so `MAX_CAL_DRY` could not fire, and ⚠ **hid the thermal
lockout** — that check lives in the terminal `driver` branch below the gate's
`return`, so a cooldown with a finger resting on the pad would have spun for
the whole 215 s saying *"lift the finger clear"* and never entered it. It was
invisible to 246 assertions because every existing test of the gate fed it a
placement result. Fixed with one predicate gating both suppression branches
**and** the press-evidence reset; driver faults now reach the tally, so a storm
is visible instead of hidden behind a single line.

What the session proved about the hand: of 13 counted attempts **6 scored** and
all 6 were `verify-no-match` — the same finger below threshold against its own
template six times, so re-enrolling was right and nothing usable was lost; but
**7 of 13 never reached the matcher**, so the ~1 cm capture ceiling is still
there and re-enrolling addresses the template only.

The recovery attempt then hit three more defects, all now fixed. **(a)** With
zero prints the window still offered **Calibrate**, as the *suggested* action,
although calibration is a verify loop fprintd refuses outright
(`NoEnrolledPrints` — hit five times in 12 s) and the failure branch answered
*"the reader may be wedged — run ./fp-debug.sh rebind"*, which is sending
someone to reset a USB endpoint over empty storage. **(b)** Opening the Enroll
window and closing it without pressing anything fired `EnrollStop` + `Release`
at an unclaimed device, because the guard was `not self._released`, which
starts `False` and conflates *"we hold a claim"* with *"we never claimed one"*;
fprintd logged `Device was not claimed before use` twice. **(c)** ⚠ The attempt
log now goes to a **file** — `$XDG_STATE_HOME/triton-panel/panel-<ts>.log`,
`TRITON_PANEL_LOG_DIR` to override, path shown in the window — because stderr
reaches no journal when Walker starts the panel. Two sessions this day left no
trace anywhere, so whether either completed a working enrolment before the
`DeleteEnrolledFingers` at 17:40:27 is permanently unknowable: fprintd is
silent for an accepted enrol stage, and the only other witness was discarded.

⚠ **Live configuration did change, by the panel's own hand:** that delete took
the last print, so `_on_fp_delete` turned the hyprlock fingerprint switch
**off** and removed the managed block from `~/.config/hypr/hyprlock.conf`. The
lock screen no longer invites a finger it cannot read.
`configs/hypr/hyprlock.conf` has been pulled back to match.

`test-enroll.py` 246 → **282 assertions, all passing**; `test-battery.py`
passing; widgets re-smoked; `check-live-system.sh` 19 passed, 0 failed.
`runbooks/fingerprint.md` §20v.

---

## 2026-11-03 — Fingerprint: the ten-second phantom was never a finger

The entry below found a `verify-swipe-too-short` arriving every **10 s on an
empty pad** and deliberately left the counting rule alone, because one unrun
measurement decided whether such a result means *"nobody touched"* or *"this
reader cannot report contact"*. It was run — `triton-panel/fp-debug.sh presence`,
40 s, one finger — and the separation is total:

| | real touch | phantom |
|---|---|---|
| count | 4 | 2 |
| `finger-present` before the result | **4 of 4** | **0 of 2** |
| spacing | when the finger landed | **10.17 s / 10.03 s** (`ELAN_CMD_TIMEOUT 10000`) |
| `journalctl -u fprintd` | `Failed to detect minutiae` | **nothing** |

So the rule moved on a measurement, not on an inference. Triton Panel now keeps
a `*-swipe-too-short` with no `finger-present` ON edge out of the rolling
window, the tally, the attempt count and the strip, in **both** the calibration
and the enrolment path — the latter mattered more than a bad score, because its
repeats counter had been turning three phantoms on an untouched pad into *"the
driver may simply not handle this sensor"*. The running count is shown on the
live tally line instead, since one arrives every 10 s and the log is written
once. `PRESENCE_SENSORS` keys *"this reader publishes `finger-present`"* by USB
id, like `AREA_SENSORS`, so the gate works before the first touch; a reader in
neither set keeps the old behaviour and its escape hatch.

Two more things that same 40 s settled. A `verify-disconnected` at **25 s
armed** turned out to be `PROTO` — the journal said so and the next arm worked
1.1 s later — which is the one-string-three-errors rule happening on the first
instance seen after the entry below, and the thermal check correctly declined
it. And **three of the four real touches failed as `verify-no-match`** with
minutiae extracted, so verify is now 7/7 failures and what remains is the
**template**, not detection: the original report's two halves have come apart.

`test-enroll.py` 200 → **246 assertions, all passing**; `test-battery.py`
passing; widget construction re-smoked. No live configuration changed —
`hyprlock.conf` untouched, password auth on, `pam_fprintd` still `sufficient`.
`runbooks/fingerprint.md` §20u.

**Later the same afternoon**, an enrolment attempt was reported as rejecting
repeatedly. The journal says it was never an enrolment: every line reads
`during verify`, so what rejected was the **calibration** — advice, not a gate,
though the window gives no way to tell. Three things that session proved, all
in §20u. **(a)** The calibrate-then-enrol flow **does not fit** the 180 s
budget: calibration is a verify loop that only stops when the gate opens, so it
spends the whole budget by design and the enrolment gets the remainder — §20l's
successful 6/6 took 54 s and would not have fitted. For an enrolment attempt,
**skip the calibration**. **(b)** libfprint's thermal estimate lives on the
`FpDevice` in the **daemon**, not in the window — the trip landed 180.0 s after
`fprintd` started — so a window's `armed Ns of 180s` is a **lower bound** and
restarting `fprintd` (which `fp-debug.sh rebind` does) is the only way to zero
it. **(c)** ⚠ Launched from Walker, the panel's attempt log is **lost**:
`elephant` starts it via `systemd-run` and that output reaches no journal, so
the tally that separates a template problem from a capture ceiling was
unavailable — and the fprintd journal cannot stand in, since it is silent for
`verify-no-match`. Run the panel from a terminal when diagnosing. Also
recorded: **32 protocol errors in 83 s** against **zero** in the 6/6 run, still
the sharpest discriminator available and still unexplained.

---

## 2026-11-03 — Fingerprint: the gap is a three-minute clock, not a finger

Reported as gaps in capture and detection. Measured with a new no-finger
instrument, `triton-panel/fp-debug.sh thermal`, and the cause is libfprint's
**time-based thermal model**, which no earlier pass had met because every
earlier session was shorter than three minutes.

**Measured, nothing touching the pad:** one armed `VerifyStart` is cut off at
**180.1 s** with `FP_DEVICE_ERROR_TOO_HOT` (`Device disabled to prevent
overheating` in `journalctl -u fprintd`), every re-arm is then refused in
**0.0 s**, and the reader is usable again between **180 s and 212 s** after the
trip. The model is a duty-cycle estimate, not a thermometer
(`DEFAULT_TEMP_HOT_SECONDS 3 * 60`, `DEFAULT_TEMP_COLD_SECONDS 9 * 60`), and
**an armed verify counts as use even while it waits for a finger**. The same
run exposed a second artefact: `verify-swipe-too-short` arrives every **10 s**
on an empty pad — the `elan` command timeout (`ELAN_CMD_TIMEOUT 10000`), not a
report about anyone's hand.

**Why unlock fails.** hyprlock arms one verify at lock and leaves it armed, so
three minutes in the model fires; fprintd maps `TOO_HOT`, `PROTO` and `REMOVED`
onto the **same** `verify-disconnected` string, hyprlock reads that as a
disconnect, never re-arms, and skips `releaseDevice()`. So **every lock
returned to more than ~3 minutes after it started has no fingerprint**, before
a hand is near the pad, while the prompt still invites a touch. hypridle locks
at 300 s idle, which makes those exactly the locks that matter. Upstream
hyprlock `main` behaves identically.

**Triton Panel** was mis-reporting it: a cooldown counted as a dry driver fault
and, four of them in, told the user to rebind the USB device. The lockout is now
recognised by **reading the journal** for the real error name, with the armed
budget and an instant refusal as fallbacks, kept out of
`MAX_CAL_DRY` / `MAX_DRY_RESTARTS`, waited out with a countdown instead of
re-armed into a spin, and the armed budget is on screen. `test-enroll.py`
154 → **200 assertions, all passing**; widget construction re-smoke-tested.
Nothing in the live configuration changed — `hyprlock.conf` is untouched.

Full analysis, options and hazards: `runbooks/fingerprint.md` §20t.

---

## 2026-11-03 — An update procedure, and a verifier for the machine itself

The repo could describe this machine but could not **check** it. Added
`tests/check-live-system.sh` (read-only, no sudo, non-zero exit on a broken invariant) and
`runbooks/updates.md`, which owns the upgrade procedure. Nothing was upgraded; the gate was
built first, deliberately, because the pending transaction is 648 packages.

**What the audit found.** Last full upgrade **2026-09-26** — five weeks and 648 repo updates.
**12 `.pacnew`** files unmerged, the oldest from April 2026, four sitting on top of hand-edited
lines (`/etc/pacman.conf`'s `[cachyos-*-v3]` repo sections, `/etc/pam.d/sudo`'s `pam_fprintd`
line, `limine-snapper-sync.conf`'s `MAX_SNAPSHOT_ENTRIES=8`, `locale.gen`'s `en_US.UTF-8`).
`paccache.timer` disabled with 15 GB / 7282 packages cached. `/etc/snap-pac.ini` at defaults,
so a kernel snapshot competes with 50 ordinary transactions under `NUMBER_LIMIT` instead of
using the separate `NUMBER_LIMIT_IMPORTANT` quota. The snapshot rollback path — `snap-pac`
hooks plus an enabled `limine-snapper-sync` — is fully installed and **has never been booted**.

**`DefaultTimeoutStopSec=15s` in `/etc/systemd/system.conf` has never been in effect.** Found
by the first run of the new verifier, which failed on it. `cachyos-settings` ships
`/usr/lib/systemd/system.conf.d/00-timeout.conf` with `10s`, and a drop-in — including a
packaged one under `/usr/lib/` — overrides the main `system.conf`. The effective value is
**10s**, confirmed with `systemd-analyze cat-config systemd/system.conf` and
`systemctl show -p DefaultTimeoutStopUSec`. The Thunderbolt shutdown-hang fix of
`runbooks/boot-suspend.md` §6 is therefore satisfied **more strictly than asked, by CachyOS,
not by us** — a wrong conclusion with a correct outcome, which is the combination least likely
to be noticed. Two consequences: `/etc/systemd/system.conf.pacnew` is safe to accept wholesale
because the line it drops is inert, and any future timeout of this machine's own must go in
`/etc/systemd/system.conf.d/`, the only tier that beats a packaged drop-in. The verifier now
asserts the **effective** value (≤ 15 s) and prints which file supplies it.
`runbooks/updates.md` §2c.

**Hyprland is retiring `hyprlang` for a Lua config, and this machine is already in legacy
mode.** 0.56.2 logs `[cfg] Lua config not found, using legacy config at …`; `lua` is a hard
dependency, the binary links `liblua.so.5.5`, and `/usr/share/hypr/hyprland.lua` plus
`stubs/hl.meta.lua` ship with the package. Deprecated upstream in 0.55; the removal release is
**unconfirmed** and 0.57.0 is in the pending queue. The blocker is not the 485 lines of `.conf`
across 13 files — it is **`hyprctl keyword`**, which the binary refuses under a non-legacy
parser (*"keyword can't work with non-legacy parsers. Use eval."*), so `monitor-mode.sh`'s
profile applies, `edp_mode()` and `apply_monitor_tf()` would all need porting to `hyprctl eval`.
A `hyprland.lua` wins whenever present, so the migration is a reversible A/B that can and should
be tested **before** 0.57.0 rather than discovered during it. Also established: `hl.on` exposes
only `hyprland.start` and `hyprland.shutdown`, so `monitor-autoswitch.sh` cannot become Lua
event handlers; emergency mode leaves `SUPER + Q` if a Lua config errors; and the auto-reload
hazard survives (`[lua] file {} modified, reloading`). `runbooks/updates.md` §4.

**Three stale references under `configs/` that no test could see.** `configs/hypr/env.conf`,
`configs/modprobe.d/acer-wmi-battery.conf` and `configs/vlc/vlcrc` still pointed at sections
§12, §14 and §13c of the snapshot doc dissolved on 2026-11-03.
`tests/check-doc-refs.sh` had never looked at them — its file list stopped at `.md`, `.sh` and
`.py` — although `CLAUDE.md` requires comments in `configs/` to be maintained like any other
document. The checker now reads **every tracked text file**, with two concessions for non-document
files: backticks are optional (a `.conf` comment should not have to use markdown punctuation) and
either the file-relative or the repo-root path form resolves, because a mirrored config is
installed at a live path where "relative to this file" means nothing. Documents stay strict —
file-relative only — which is the exact breakage the restructure shipped. The three references
were re-pointed; 0 errors across 308 references in 72 files. The deliberate narrowing kept: naming the
dissolved file as *history* is legitimate, and only a `§N` **pointer** at it is an error.

**What a snapshot rollback actually covers, verified rather than assumed.** snapper's `root`
config snapshots the subvolume at `/` (`nvme0n1p2[/@]`); `/home`, `/root`, `/srv`, `/var/cache`,
`/var/log` and `/var/tmp` are separate subvolumes and `/boot` is a vfat ESP, so none of them
roll back. Two consequences worth knowing before relying on it: `/usr/lib/modules/` **is**
inside the snapshot, so a rolled-back kernel keeps its modules; and `/home` is **not**, so a
snapshot will not undo a bad edit to the live `~/.config/hypr` — the repo's `configs/` mirror
and the snapshot cover different halves of the machine and neither substitutes for the other.
`/var/cache` being outside is a feature: a rollback leaves the package cache, and with it the
downgrade path and the `pacdiff -3` merge base, intact. `runbooks/updates.md` §6a.

**Mirror parity is now checked.** The verifier carries the manifest of every live path this repo
claims to own — 36 files — and classifies drift: effective-line drift fails, comment-only drift
is a note, and `configs/vlc/vlcrc` (VLC rewrites it on exit) and `configs/hypr/hyprlock.conf`
(Triton Panel writes the live copy) drift by design and never fail. First run: 34 in step, one
comment-only drift (`configs/modprobe.d/acer-wmi-predator-v4.conf`, whose live copy is still the
original Spanish — the `options` line is identical), none missing. This is the check that the
logind drop-in needed, which sat committed and uninstalled from 2026-07-12 to 2026-10-12.

## 2026-11-03 — Three "pending" markers closed against the live system

Immediately after the restructure, the todo list was read against the machine instead of
re-read as prose. Three items had been **done for some time** and said otherwise — doc debt,
not open work. Nothing was changed on the system to close them except the ppd mapping probe.

**`predator_v4` is reboot-verified** (`runbooks/power-battery.md` §17, header was "reboot
check pending"). The parameter reads `Y` after the 2026-11-03 08:12 boot, so the
`/etc/modprobe.d/` drop-in is picked up at boot and nothing depends on a manual module
reload: `platform_profile` present (`balanced`), five choices, `acer-isa-0ace` reading
`fan1 0 / fan2 0 RPM` and `temp1 +35.0 / temp3 +33.0 °C` (0 RPM at 35 °C is genuine — this
machine stops both fans when cold), and `powerprofilesctl list` no longer says
`placeholder`. §17b's ppd→platform_profile mapping, which had been written down as
*expected*, was then **run**: `power-saver`→`low-power`, `balanced`→`balanced`,
`performance`→`performance`, exactly as predicted; the profile was restored to `balanced`
afterwards. This is the one live change in this entry, and it is self-reverting.

**The Triton Panel sudoers rule is installed** (`runbooks/triton-panel.md` §18, header was
"sudoers rule pending"). `sudo -ln` reports `(root) NOPASSWD: /usr/local/bin/triton-ctl`, so
the charge-cap switch and the `quiet`/`balanced-performance` entries work instead of raising
a toast. `/etc/sudoers.d/` is not world-readable, which is why `sudo -ln` — what is actually
in effect for this user — is the check rather than an `ls`.

**The AC *steady state* of the power daemon is verified** (`runbooks/power-battery.md` §19,
which had read "needs the charger physically plugged in" since 2026-10-31). On barrel AC
(`ACAD/online=1`, both USB-C PD sources `0`, undocked) with the daemon live (pid 1579) and
the panel switch on: `eDP-1` at **240.00 Hz**, ppd and `platform_profile` both `balanced`,
and `/run/user/1000/triton-power-mode` reading
`source=ac auto=1 rate=240 saved_profile= profile=balanced`. The **empty `saved_profile` is
the §19h fix working on the AC side** — nothing was captured on an AC boot, so the branch
restored nothing and left `balanced` alone rather than forcing it, which is precisely the
bug §19h fixed. ⚠ The plug/unplug **transition** is still untested, but the charger is no
longer the blocker: it is plugged in. That makes it the most actionable open item in §15.

The two now-stale ⚠ claims inside §19's *Issue history* were marked **superseded** in place
rather than rewritten, and the 2026-11-02 entry below still says "the AC side still needs the
charger" — it was true on 2026-11-02 and this file is append-only. A dated entry dates
itself; it is not corrected into agreement with the present.

---

## 2026-11-03 — Documentation restructured: scope replaces ranking

`finish-installation-commands.md` (213 KB, 3830 lines, 21 sections) was
**dissolved** into per-subsystem runbooks, and the narrative that had accumulated
in `ACTUAL-CONFIGURATION.md` was moved out of its header line and out of its §15
table cells.

**Why.** The repo needed a seven-deep *source-of-truth hierarchy* because several
documents claimed the same ground. The one document nobody had to rank was
`runbooks/bluetooth.md` — because it had **scope**, not **rank**: sole owner of one
subsystem, self-contained, 11 KB. The two that rotted were the two unscoped
accumulators: everything new landed in one of them, so both grew without bound
and overlapped. Ranking was treating the symptom.

Two measurements that made the case: `ACTUAL-CONFIGURATION.md` line 4 was
**13 KB** of changelog in a metadata field, and one §15 table cell was **22.7 KB**
of incident narrative. Meanwhile §2 still reported kernel `7.0.9` (live: `7.2.8`),
LTS `6.18.32` (live: `6.18.52`), a kernel command line carrying
`nvidia-drm.modeset=1` (not present since 2026-07-02) while omitting the two
parameters that *are* live, and a warning that booting LTS "will black-screen"
that its own §3 had marked obsolete four months earlier. §4/§5 package versions
were two to three releases behind. Nobody refreshed those sections because
appending to the header was free.

**Section numbers were preserved** on every move, so any `§N` reference that was
not re-pointed is still findable with `grep -rn '§N' runbooks/ archive/`.

<!-- doc-refs: ignore — this table names the pre-2026-11-03 paths on purpose -->
| was | is now |
|---|---|
| `finish-installation-commands.md` §0, §6, §10, §11, §15 | `runbooks/boot-suspend.md` |
| `finish-installation-commands.md` §5, §16 | `runbooks/monitors.md` |
| `finish-installation-commands.md` §7, §8 | `runbooks/desktop-apps.md` |
| `finish-installation-commands.md` §12, §13 | `runbooks/gpu-video.md` |
| `finish-installation-commands.md` §14, §17, §19 | `runbooks/power-battery.md` |
| `finish-installation-commands.md` §18 | `runbooks/triton-panel.md` |
| `finish-installation-commands.md` §20 | `runbooks/fingerprint.md` |
| `finish-installation-commands.md` §1, §2, §3, §4, §9 + preamble | `archive/install-remediation-2026-05.md` |
| `bluetooth.md` | `runbooks/bluetooth.md` |
| `cachyos-hyprland-setup.md` | `archive/cachyos-hyprland-setup.md` |
| `system-state-findings.md` | `archive/system-state-findings.md` |
| `spected-installation.md` | `archive/spected-installation.md` |
| `ACTUAL-CONFIGURATION.md` `**Last updated:**` line | this file |
| `ACTUAL-CONFIGURATION.md` §15 long cells | `## Issue history` in the owning runbook |
<!-- /doc-refs: ignore -->

`ACTUAL-CONFIGURATION.md` **kept its name** — 48 references point at it, the name
is accurate, and renaming would have bought nothing. Its §2–§9 facts were
corrected against the live system the same day; §15 became a thin status table
whose rows point at runbooks. `CLAUDE.md` was cut from narrative to imperative
rules plus pointers. Nothing was deleted: superseded material moved to `archive/`
with a banner, because the one lesson this repo already recorded (`§20g`) is that
retracted reasoning has value.

**Still open after this pass:** `ACTUAL-CONFIGURATION.md` §2–§9 are corrected but
still hand-maintained. Making them regenerable from a `scripts/snapshot.sh` dump
is the follow-up that stops them drifting again.

---

## 2026-11-02 — Battery-life audit on battery, undocked

**Battery-life audit on battery, undocked.** One real defect found and fixed: `plymouth-start.service` had been running `plymouthd` for the whole session with no splash to draw and nothing left to quit it, burning **2.88 % of a core** indefinitely — a side effect of §6.3.c masking only the *quit* units. Masked the start unit too. Then measured the rest instead of guessing: a **PL1 cap on battery was considered and dropped** — RAPL reads 110 W and is never approached, because `power-saver` pins all 20 CPUs at **exactly 1100 MHz** under load (not `intel_pstate`, not `intel_lpmd`, not thermal — EPP=`power` + `platform_profile=low-power`). A fixed-work comparison makes `power-saver` a **tie on energy and 2× on wall clock** against `balanced`, so it is a performance setting, not a battery one; and at idle `power-saver` and `balanced` are **indistinguishable** (the repeat-control drift, 1.8 W, exceeds the 1.1 W gap), with only `performance` clearly worse at +5 W. Fans read 0/0 RPM in every profile, ruling out a fan floor. Also confirmed: the dGPU is genuinely idle — **+0 ms active / +60007 ms suspended over 60 s, in D3cold** — and the 21 W a `nvidia-smi` appears to show is caused by the act of running it. Two pre-existing flaws surfaced in `power-autoswitch.sh`. **The first was fixed the same day, on request, and it turned out to be two bugs:** ppd persists `Profile=power-saver` in `/var/lib/power-profiles-daemon/state.ini`, so the daemon's first-tick capture had **ratcheted `saved_profile` to `power-saver`** and the AC branch no longer restored `balanced` — and, found while fixing that, with nothing captured the AC side forced `balanced`, so an **AC boot silently destroyed a hand-picked `performance`**. Both fall to one invariant, *never record `power-saver` as `saved_profile`* (on battery it can only be the daemon's own doing), plus *restore only what was actually captured*: two conditions, no new state flag. Battery side verified live, 10/10 on a harness that runs the real branch text; **the AC side still needs the charger**. `runbooks/power-battery.md` §19h. The second flaw is **open**: that same `state.ini` carries `battery_aware=true`, so ppd may already duplicate the profile half of that daemon. §15 `plymouthd` row + power-source row annotated; `runbooks/boot-suspend.md` §6.3.c annotated. Triton Panel's **Battery** group then gained the picture that audit kept wanting: charge history and the projection on one linear time axis — consumed band, dashed line from the current draw to empty (or to the 80% cap when charging), ETA as a clock time — with the draw as a ~45 s EMA, the run average beside it as a cross-check, and the history before the window was opened seeded once per run from upower's `GetHistory`, stopping at upower's own discontinuity markers so a suspend is never stitched in as consumption. A run ends at a reversal or a wall-clock hole, never at an idle status. Regression test `triton-panel/test-battery.py`; §15 row below extended).

---

## 2026-11-01 — Fingerprint enrolment WORKS

**Fingerprint enrolment WORKS** — `right-index-finger` enrolled, 6/6, after three sessions of failure that had been wrongly diagnosed as a hard driver block. It was first filed as a **driver** failure because `journalctl -u fprintd` showed only `FP_DEVICE_ERROR_PROTO` + `No minutiae found` and never `too-short`/`too-fast` — a true premise with a false conclusion, because on an area pad driven as a swipe sensor the gesture failure surfaces precisely as `No minutiae found`. The in-tree `elan` driver — corrected from the earlier `elanmoc` claim — is the binding for `04f3:0c4f`, and it does enrol. Triton Panel gained a dedicated **enrolment window**: contact chart from `finger-present`, stage pills driven only by `enroll-stage-passed`, results classified gesture/driver/fatal so a driver fault never reads as bad technique, attempt log mirrored to stderr, async `Claim`, and the complete result vocabulary from the D-Bus spec — the previous code was missing `enroll-too-fast`, `enroll-duplicate` and `enroll-unknown-error`, the last being exactly what this machine emits. §15 fingerprint row rewritten. USB autosuspend was tested and ruled out as a cause. A second pass the same day added §20j: the enrolment **lift step is mandatory** — libfprint's image-device cycle will not begin the next capture until the driver reports the finger gone, so a finger left resting stalls the run silently — and the panel's enrolment window never said so, now fixed via `_cycle_hint()`. The journal also yielded an **invalid** `AWAIT_FINGER_ON → AWAIT_FINGER_OFF` transition (the driver mishandling the lift) and one `No minutiae found`, proving an image does get captured sometimes, which narrows §20g. Reference clients (`fprintd-enroll`, GNOME's `cc-fingerprint-dialog.c`) read and compared. The sensor was then checked against the chassis and the driver's `scan-type = swipe` is **wrong**: it is a ~1 cm square pad in the corner of the touchpad, an area/press sensor — which is both why `No minutiae found` happens (a press gives `elan`'s motion assembly no displacement to stitch) and why every instruction derived from `scan-type` was asking for an impossible motion. The panel now keys the physical type by USB id (`AREA_SENSORS` → `info["gesture"]`) and builds all seven instruction sites plus the hyprlock `ready_message` from it (`Touch`, not `Swipe`); `scan_type` is kept and displayed as the driver's claim. A third pass (§20k) then ran the press gesture for real: **8 images captured in 85 s** against one in the whole morning of swipe attempts — the area-pad reading confirming itself by behaviour — but **0 accepted**, every one rejected for too few minutiae, which is the small-sensor limit on a ~1 cm pad. What had been ending each session was not the `enroll-retry-scan` it looked like (that never stopped anything) but `enroll-unknown-error` with `done = True`, after which the old code released the claim so "Try again" cost another polkit password; the window now restarts the enrolment itself (`EnrollStop` + `EnrollStart`, claim kept) with two caps and a regression test, `triton-panel/test-enroll.py`, 40 assertions. Then it **enrolled** (§20l): `right-index-finger`, 6/6 in ~54 s, 2 rejections, **0** protocol errors, with no driver change and no TOD — so §20g's "cannot enrol" verdict was wrong. ⚠ The two instruction corrections are necessary but **not shown sufficient** — they were already in place for a run that got 0 of 8, and the 6/6 run was the same binary; what differed is unrecorded, and a second finger is the reproducibility test. The error worth remembering: §20g read *"no `too-short`/`too-fast` ⇒ not a gesture problem"*, but on an area pad driven as a swipe sensor the gesture failure surfaces as `No minutiae found`, which was in its own quoted journal; that became a `CLAUDE.md` rule that blocked the fix for three sessions. `pam_fprintd` in `sudo` is live now (its prompt says "Swipe" and the pad must be touched; `sufficient`, so no lockout), and the hyprlock switch is enableable. The pre-emptive driver banner was removed as disproven. ⚠ A fifth pass then measured **verify** and it **fails 4/4** (§20m): zero matches, half the runs ending in a protocol error that fprintd reports as `verify-disconnected` although the sensor never left the USB bus. Unlock is **wired and correct but not usable yet** — the blocker is template/capture quality on an image-based `elan` pad, not configuration, and no match-on-chip driver covers `04f3:0c4f`. Next step is additive: a second finger. `triton-panel/fp-debug.sh` is the harness if the protocol errors persist, and it gained a `verify` mode (§20n). A sixth pass (§20o) then changed what the panel is for: it no longer treats *enrolled* as the goal, because the 6/6 enrolment whose template matched nothing had **every number in the window reading as success**. `EnrollWindow` now runs a **calibration phase** first — a verify loop that writes nothing, bucketing each attempt as scored / rejected / driver, with a rolling 8-of-last-10 gate — so the panel can distinguish *the template is bad* (re-enrol) from *the captures are too thin* (don't bother), and it refuses to recommend enrolling in the second case. It also warns that enrolling into an occupied slot overwrites it, and that a slot name is only a label — so a free slot can hold the same physical finger, which is the non-destructive way to test a fresh template. `test-enroll.py` 40 → **81 assertions**. ⚠ Still unrun against a real finger. Details: `runbooks/fingerprint.md` §20f/§20g/§20j).

---

## 2026-10-31 — Replacement battery fitted and the 80% cap proven

Replacement battery fitted and the 80% cap **proven** for the first time: charging stopped at exactly 80% with AC connected. Same day, five more changes. (1) `acer_wmi` forced with `predator_v4=1` via a new `/etc/modprobe.d/acer-wmi-predator-v4.conf`, which is what makes fan RPM and the 5-state `platform_profile` exist at all on this model — neither is available without it. (2) NVIDIA driver is now `615.71.09` on kernel `7.2.8-1`; a short undocked s2idle resumed clean, the first GSP re-test since the 2026-07-12 incident, but the long and docked cases are still untested. (3) New `triton-panel/` — a small GTK4 app for this machine's own hardware, launched from Walker. §1 battery row, §3 refreshed, §8 battery package row, §15 battery row resolved + two new rows + GSP and hypridle rows annotated, §16. (4) New `scripts/power-autoswitch.sh`: on battery the laptop panel drops to 60 Hz and the platform profile to `power-saver`, restored on AC — which first required giving eDP-1's refresh rate a single owner (`edp_mode()`), since `2560x1600@240` had been hardcoded at 8 sites plus the hyprmon JSON path. §10, §11, §15 new row, §16. (5) The **fingerprint reader** is wired up end to end in Triton Panel — it was never used only because no finger was enrolled; hyprlock unlocks via fprintd over D-Bus, so no PAM file is touched. §15 new row. Details: `runbooks/power-battery.md` §14/§17/§18/§19/§20 and `triton-panel/README.md`).

---

## 2026-10-15/16 — Monitor layouts become visually editable

Monitor layouts become visually editable. `hyprmon-bin 0.0.17-1` installed 2026-10-15 23:54 and verified on 2026-10-16 with a scripted `P`/`S`/`Q` session; a real drag-and-save is still to be done by hand. AUR `hyprmon-bin` is the editor, `monitor-mode.sh` stays the applier: it now reads `~/.config/hyprmon/profiles/<mode>.json` when that profile covers exactly the connected monitors, else falls back to the hand-written geometry. `desktop` and `read` profiles seeded from the existing geometry. New `hyprmon-edit.sh` wrapper neuters hyprmon's config write + `hyprctl reload`. New `Super+Shift+M` / Walker "Monitors" menu after Omarchy's *Setup > Monitors*. §5 row, §9 counts, §11, §15 new row, §16. Details: `runbooks/monitors.md` §16).

---

## 2026-10-12 — Battery failed and was removed, replacement on order

Battery failed and was removed, replacement on order. 80% charge cap installed for the new pack via AUR `acer-wmi-battery-dkms` + `/etc/modprobe.d/acer-wmi-battery.conf`. The module loads, but the firmware reports the cap as off until a pack is fitted: §1 battery row, §8 package rows, §9 counts, §15 new row, §16 `configs/modprobe.d/`. Details: `runbooks/power-battery.md` §14. Same day: the logind lid drop-in from 2026-07-12 turned out never to have been installed; installed and verified with a real lid close, new §15 row, GSP row annotated, §16 gains `configs/systemd/logind.conf.d/`, `runbooks/boot-suspend.md` §15).

---

## 2026-07-02 — Firefox-freeze root cause and the VA-API reroute

Firefox-freeze root-cause + VA-API reroute: §3 refreshed — driver now `610.43.02`/`7.0.12-1`, KMS via driver-default + chwd early-KMS, dGPU confirmed **offload-only** with the compositor on the iGPU; `env.conf` `LIBVA_DRIVER_NAME` nvidia→iHD and `NVD_BACKEND` dropped; Firefox hardware decode paused via profile `user.js`; four new §15 rows — freeze incident, i915 `__gen8_ppgtt_clear` NULL-deref bug, NVIDIA GSP resume failure, iGPU-primary discovery. Details: `runbooks/gpu-video.md` §12).

---

## 2026-05-26 — Elephant/Walker autostart and the VS Code keyring notification

Two fixes: (1) Elephant/Walker — `graphical-session.target` never activates under this getty+`start-hyprland` session, so `elephant.service` never auto-started and Walker hung on "Waiting for elephant"; fixed by adding `exec-once = systemctl --user start elephant.service` to autostart.conf, §10 + §15 reflect it, see `runbooks/desktop-apps.md` §7e.ii–iii. (2) VS Code OS-keyring notification silenced via `~/.config/code-flags.conf` → `--password-store=basic`; §7 editor row + §15 reflect it, see `runbooks/desktop-apps.md` §7f).

---

## 2026-05-23 — Walker Elephant backend installed

Walker Elephant backend installed — hub + 9 providers from AUR at `2.21.0-1`, `~/.config/systemd/user/elephant.service` user unit written + enabled; §5/§10/§12/§15 reflect new state. Earlier same-day: verified live state matches mirrored configs; phantom DP-0 EDID warning logged; display-manager row rewritten — system now boots via `getty@tty1` autologin + fish `exec start-hyprland`, plasmalogin disabled per `runbooks/boot-suspend.md` §10

---

## Appendix — package count history

Moved here 2026-11-03 from `ACTUAL-CONFIGURATION.md` §9, verbatim. That section now
carries only the current numbers and how to regenerate them.

- **Explicitly installed (user-requested):** 280 (2026-10-16 recount; was 279. +`hyprmon-bin` on 2026-10-15. Earlier history: 279 at the 2026-10-12 recount; was 274. +`acer-wmi-battery-dkms` on 2026-10-12, +`blender` 2026-09-26, +`git-filter-repo` 2026-08-26, +`inkscape` and `gimp` 2026-08-25, per `/var/log/pacman.log`. Earlier history: was 273; +`vlc` on 2026-07-31 — the other 4 packages it pulled are dependencies, not explicit. +`calibre` on 2026-07-23; +`google-chrome` earlier the same day; was 271 before that. Was 267 on 2026-05-23; +Obsidian on 2026-07-08, plus a few other installs in between)
- **Total installed (with dependencies):** 1533 (2026-10-16 recount; was 1532. +`hyprmon-bin`, no new dependencies, since `hyprland` was already there. Earlier history: 1532 at the 2026-10-12 recount; was 1432. +2 from the battery cap, `acer-wmi-battery-dkms` + `dkms`; the rest are dependencies of the 2026-08-25 → 2026-09-26 installs above. Earlier history: was 1427; +5 from `vlc` on 2026-07-31 — small because `vlc-plugins-all` had already pulled the whole codec stack. Was 1358 before `calibre`'s +69 Python/Qt stack on 2026-07-23)
- **Foreign / AUR packages:** 15 (`pacman -Qm`, 2026-10-16 recount; was 14). +`hyprmon-bin` (AUR, 2026-10-15). Earlier history: 14 at the 2026-10-12 recount; was 12. +`acer-wmi-battery-dkms` (AUR, 2026-10-12). +`litehtml0.9 0.9-2.1`, which is not an AUR package: it was installed 2026-06-16 as a dependency, nothing requires it any more, and it has since left the sync repos, so it is an orphan and a removal candidate. Earlier history: unchanged by the VLC install (repo package). Includes `elephant` + 9 providers (all `2.21.0-1`), `visual-studio-code-bin`, and `google-chrome` (added 2026-07-23). `calibre` is **not** here — it's a repo package. Obsidian is **not** here either — repo package from `extra`.

Get the full explicit list with `pacman -Qe`. Get only foreign packages (AUR/manual) with `pacman -Qm`.

---
