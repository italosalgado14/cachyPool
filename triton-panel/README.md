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
  power-profiles-daemon currently reports, the power source, the Thunderbolt
  dock, and **automatic power saving**: a switch, plus a row showing the mode
  the daemon is actually in.
* **Battery** — a graph of how much has been consumed and how long the draw
  right now leaves (below), the 80% charge cap as a switch, plus charge,
  status, draw, health against design capacity, cycle count, and pack
  temperature.
* **Keyboard** — backlight on/off (see the caveat below).
* **Fingerprint** — the reader, what is enrolled, enrolling and deleting, and
  whether hyprlock unlocks with it.

## Automatic power saving

The **Automatic power saving** switch in the Power group turns on a daemon that
follows the power source:

| | laptop panel | platform profile |
|---|---|---|
| on battery | `2560x1600@60` | `power-saver` |
| on AC | `2560x1600@240` | whatever was active before |

The panel only writes `~/.config/triton-panel/power-auto` (`1`/`0`, and **absent
means on**) and sends `SIGUSR1` so the change takes effect at once. The work is
done by `configs/hypr/scripts/power-autoswitch.sh`, started from `autostart.conf`;
`finish-installation-commands.md` §19 has the full design.

Two things about this are worth knowing before editing either side:

* **The panel cannot ask Hyprland anything.** It is launched from Walker, i.e.
  by the systemd `--user` manager, which never sees `HYPRLAND_INSTANCE_SIGNATURE`
  — `hyprctl` just answers "is hyprland running?". So the refresh rate shown in
  the *Power mode* row is the rate the **daemon** observed and wrote into
  `$XDG_RUNTIME_DIR/triton-power-mode`, never a reading of the panel's own. If
  that file is missing or its `ts` is stale, the row says "daemon not running"
  rather than showing a number nothing is maintaining.
* **Signal the daemon by the `pid` it publishes**, never
  `pkill -f power-autoswitch.sh`: `-f` matches whole command lines, so it also
  hits any shell or editor whose argv merely mentions the script.

Turning the switch **off** restores 240 Hz and then leaves the rate alone; it
deliberately does *not* undo the platform profile you are currently sitting on.

## Battery: what has gone, and what is left

The Battery group opens with one picture that puts the history and the
projection on the **same linear time axis**: a green line for the charge that
was actually observed, an amber band for how much has been consumed since the
run began, and a dashed blue line carrying the present draw forward to empty —
or up to the 80% cap when the pack is charging.

The join in the middle is the point of it. The dashed line is literally the
solid line's current rate extended, so a projection that disagrees with the
slope you can see is one you can catch. Two scales side by side would make
every slope look alike, which is the usual way a battery widget manages to be
both pretty and useless. For the same reason the y axis is pinned to 0–100%
and never autoscales: here the floor *is* the question.

Three numbers, and they are not interchangeable:

| | what it is | where |
|---|---|---|
| **draw** | EMA of `current_now × voltage_now`, ~45 s time constant | *Consumption* value |
| **average** | charge moved ÷ elapsed, over the whole run | *Consumption* subtitle |
| **time left** | remaining Wh ÷ draw | *Time left* value, and the dashed line |

The draw is the one that answers "at the consumption *right now*", which is why
the projection divides by it. A single `current_now` sample is too noisy to
divide by — one read on 2026-11-02 gave 23.2 W while upower's smoothed figure
for the same minute said 30.3 W, a 40-minute difference in the answer — so it
is smoothed over seconds, never over the run. The run average sits beside it as
the cross-check: when the two disagree the session has not been uniform, and
having both on screen is how that shows, instead of being averaged into one
authoritative-looking figure.

### Where the history comes from

This panel is a window launched from Walker, not a daemon, so its own trace is
empty at exactly the moment someone opens it to ask how much battery has gone.
The stretch from before the window existed is read **once per run** from
upower's `GetHistory` over D-Bus — the only reading in this app that does not
come from sysfs; the live sample still does.

upower marks the places where it lost track of the device with a
`(timestamp, 0.0, 0)` entry, and the walk backwards stops at the first one. A
real answer from this machine:

```
(1793667268, 64.0, 2), (1793667268, 0.0, 0), (1793640616, 64.0, 2)
```

— the same 64%, 7.4 hours apart, with the machine asleep in between. The run
that is still going starts at the marker. Stitching across it would draw a
seven-hour flat segment and then call it consumption.

### What ends a run

* **A reversal** — discharging to charging, or back.
* **A hole in the wall clock** longer than 30 s. `time.monotonic()` does not
  advance across s2idle and `time.time()` jumps, so a suspend appears here as a
  gap. The machine was not consuming at its awake rate while it slept, so the
  trace and the EMA both restart and the row says so. hypridle suspends this
  laptop on battery, so this is the ordinary path, not an edge case. A
  **backwards** jump counts as a hole too — without that an NTP step would
  freeze the EMA for the rest of the session.

  Thirty seconds, not `4 × POLL_SECONDS`, because the panel's own main loop
  blocks: `sudo -n triton-ctl` waits up to 8 s on a cap or profile write,
  `nvidia-smi` up to 4 s on **Read now**. At a tighter threshold, pressing a
  switch was indistinguishable from a resume. And upower is re-asked after
  *every* gap, which is what makes a false one self-healing: a stall leaves no
  marker in upower's history, so it hands the whole run back and the trace is
  rebuilt rather than lost for the rest of the session.

What does *not* end a run is an idle status. `Not charging` is what this
machine reports all day with AC connected and the cap holding, and it is also
what a one-tick blip looks like; wiping the curve there would throw away the
discharge someone is looking at. Idle stops the projection, says why, and
nothing more.

### What the projection is not

It divides the **whole** remaining charge by the draw. The firmware cuts off a
few percent above zero, so the clock time is the outer edge rather than a
promise, and the subtitle says so. A charge is projected to 80% whenever the
cap is on, because that is where charging actually stops — and `charge_full` is
the denominator, not `charge_full_design`: this pack reads 101.7 Wh full
against a 100.0 Wh design, so a target computed from the design figure would
never arrive. Under 0.5 W nothing is divided at all, and past 24 h the answer
reads `> 24 h` instead of a clock time nobody should believe.

`test-battery.py` replays the whole thing headlessly — the suspend, the idle
blip, the reversal, the clamp, the decimation, and a recorded `GetHistory`
answer from this machine — and renders the widget onto a Cairo image surface in
every state, because an exception inside a draw handler becomes a GTK warning
and an empty widget rather than a crash:

```bash
cd triton-panel && python3 test-battery.py
```

## Fingerprint

Everything fingerprint in one group: the sensor (name, scan type, enroll
stages), the enrolled fingers, a picker + **Enroll**, **Delete all prints**, an
**Unlock hyprlock with fingerprint** switch, and a read-only `sudo` row.

Why it needs no privileges of its own: polkit here grants
`net.reactivated.fprint.device.verify` to the active session outright, so
listing never prompts, and `…device.enroll` is `auth_self_keep`, so `Claim()`
raises a dialog for your *own* password. `/var/lib/fprint` is root-only, so
nothing is read from the filesystem — it is all D-Bus.

✅ **Enrolment works** — `right-index-finger`, 2026-11-01, 6/6 in ~54 s with two
rejections and **zero** protocol errors. It had failed for three sessions, and
the cause was the panel's *instructions*, not the hardware: the window asked
for a swipe on a pad that cannot be swiped, and never said to lift between
stages. `FP_DEVICE_ERROR_PROTO` does still appear in `journalctl -u fprintd`,
but it is **intermittent, not blocking** — the successful run had none. The
lesson worth keeping is in `finish-installation-commands.md` §20l: `No minutiae
found` is a *geometry* result, and reading it as a driver verdict is what cost
three sessions. The device's declared `scan-type = swipe` comes from that same
driver and was checked against the chassis on 2026-11-01 — it is simply
**wrong**:
the part is a ~1 cm square pad in the corner of the touchpad, an area/press
sensor with nothing to slide a finger along. `AREA_SENSORS` keys that fact by
USB id, `fprint_device()` exposes it as `info["gesture"]`, and **every
instruction in the UI plus the hyprlock `ready_message` is built from
`gesture`, never from `scan_type`** — which is kept and displayed only because
what the driver claims is evidence about the driver. This also explains the
`No minutiae found`: a press on an area pad gives frames with no displacement,
so `elan`'s multi-frame motion assembly has nothing to stitch.

### One press is one measurement — but the device is NEVER deaf

Two rules, and keeping them separate is the whole point:

1. **The verify is always re-armed immediately**, on every result, whatever the
   bucket. The reader must be listening every moment the user might touch it.
2. **Counting** a result as a measurement waits for evidence of a new press.

They were briefly coupled, and that was a regression: making the *re-arm* wait
for the lift left the panel deaf for 3 s after every result and touches were
simply lost. **A missed count is a wrong measurement; a missed re-arm is a lost
touch.** Different failure modes, different decisions.

Why rule 2 exists: a real session logged 44 s of `No minutiae found` / protocol
error alternating every 1–3 s while the finger never left the pad. Every
`done = True` re-armed the verify, each fresh `VerifyStart` captured the **same
resting finger**, and each garbage image appended another reject to the rolling
window — so the gate announced "Captures are too thin" about a placement made
**once**. It was measuring the panel's own loop.

"Is this a new press?" uses two signals, and **neither is the strip's open
contact** — `close_open_contact()` shuts that artificially on every result,
which is why a dozen results from one press each showed a plausible duration:

* any `finger-present` **transition** since the last counted result (the **ON**
  edge is the best evidence something moved, and it doesn't depend on the OFF
  edge this driver emits invalidly — §20j);
* `SAME_PRESS_S = 2.0`, a wall-clock escape so unreliable presence reporting
  can never suppress the measurement forever. That path logs `Counted without a
  reported lift`, because driver-reported and assumed must stay distinguishable.

A reader that never reports contact (`strip.supported is not True`) is not
gated at all.

⚠ `MAX_CAL_DRY` does not cover any of this. It counts driver faults with **no**
finger contact — a wedged endpoint. A resting finger is the opposite case.

⚠ Before changing anything here, run `./fp-debug.sh presence` and look at the
signal. Two bugs in a row came from guessing at it.

### Each stage must capture a DIFFERENT region

An enrolled NBIS print is **not one merged template**. It is a `GPtrArray` of
per-stage minutiae sets (`FpPrint` exposes it as `fpi-prints`, plural), and
`fpi_print_bz3_match` loops over **every** stored set, returning success on the
**first** one to reach the bz3 threshold (default 40). **One-of-N, not a
composite.**

So six identical placements store six near-duplicates and waste five of the six
slots; six *different* regions are six independent chances for a single verify
capture to overlap one. On a ~1 cm pad that is the difference between a template
that can be matched and one that cannot — and it is why phone enrolment asks you
to shift the finger and then do the edges.

`ENROLL_REGIONS` holds the six, and `_stage_hint()` names the next one after
every accepted stage. `_region_for()` indexes modulo the list and stops at the
device's own stage count, so a reader reporting 5 or 8 stages still gets a
region for each.

⚠ This window used to say to use the **same** placement every stage. That
conflated the `elan` driver stitching *frames within one capture* with how
libfprint stores *stages across an enrolment* — the first is real, the second
is not stitching at all. Don't reintroduce it.

### Test a stored print

**Test** in the Fingerprint group runs one verify and puts the verdict in the
row's subtitle: `Claim` → `VerifyStart("any")` → one `VerifyStatus` → report →
`VerifyStop` → `Release`. It is the quick "does the print I have work?" check,
and the thing to press before going near the enrolment window — "enrolled" and
"works" are different states, which is the whole lesson of 2026-11-01.

`"any"` scores against every enrolled template (what `fprintd-verify` with no
`-f` does) and `VerifyFingerSelected` names whichever print matched.

**The hazard here is the claim, not the verdict.** fprintd grants one at a time
and a leaked claim leaves the next `Super+L` with no fingerprint until fprintd
times it out — and a verify nobody touches never ends by itself. So this
releases on *every* exit: the result, **Cancel**, Cancel pressed while polkit's
dialog is still up (the claim is granted server-side regardless, so it is
released in the claim callback), the window closing, and a hard
`TEST_TIMEOUT_MS = 30 s`. The timeout is a correctness requirement, not a
nicety. A retry result (`done = False`) must **not** release: fprintd keeps the
verify open and is already waiting.

A no-match says *the stored print, not your finger* — see the calibration
section for why that is the honest reading.

### Calibration: measure matching before touching the print

Added 2026-11-01. **This window does not treat "enrolled" as the goal.** On
2026-11-01 a 6/6 enrolment produced a template that then failed
`fprintd-verify` 4 times out of 4 — and every number in the window read as
success, because they were all *enrolment* signals. Enrolment passing says
almost nothing about matching.

So **Calibrate placement** runs first. It loops `VerifyStart("any")` and
buckets each attempt:

| bucket | results | meaning |
|---|---|---|
| **scored** | `verify-match`, `verify-no-match` | an image was produced **and** minutiae extracted, so the matcher ran |
| **rejected** | `verify-retry-scan`, `-too-short`, `-too-fast`, `-finger-not-centered`, `-remove-and-retry` | the capture never reached the matcher |
| **driver** | `verify-disconnected`, `verify-unknown-error` | the device faulted; nothing to do with the hand |

That split is the whole value. A **high scored rate with `no-match` every
time** is evidence about the *stored template*, not your placement — the one
case where re-enrolling helps. A **low scored rate** is placement or the
small-sensor ceiling, and enrolling from captures that thin just builds another
unmatchable template, so the window says so and labels the button *"Enroll
anyway"* rather than recommending it.

Gate: **≥10 attempts and ≥8 of the last 10 scored** — rolling, so a placement
you converge on is not dragged down by the fumbling at the start. Deliberately
**not configurable**: a knob would invite tuning the threshold until it passes,
which is the one thing that would make the measurement worthless.

Properties worth keeping if you edit this:

* **Calibration writes nothing.** Verify neither enrols nor deletes. Safe to
  repeat indefinitely.
* **"scored" is an inference, not a measurement.** It follows libfprint's flow
  (extraction fails → retry; succeeds → bozorth3 → match/no-match) and is
  consistent with the journal, but it is *not* a per-capture minutiae count —
  only `./fp-debug.sh verify` prints one. That is why the UI says "scored" and
  never "good". A missing log line is not a measurement.
* **Driver faults stay out of the rolling window.** Counting them would blame
  the hand for something it cannot fix.
* **The verify loop follows fprintd's state machine.** `VerifyStop` before the
  next `VerifyStart` once a status arrives with `done = True` — and **both**
  match and no-match are `done = True`. A retry is `done = False`, leaves the
  verify open with fprintd already waiting, and must **not** be cycled. That
  asymmetry is invisible from the UI; it is the first thing
  `test-enroll.py` asserts.
* **`VerifyFingerSelected` is not an outcome** — it names the template about to
  be scored. Logged as info, never counted as an attempt.
* **Enrolling into an occupied slot overwrites it**, and the window says so.
  The slot name is only a *label*, so a free slot can hold the same physical
  finger — that is the non-destructive way to test a fresh template. The panel
  never deletes anything on its own.

### The enrolment window

**Enroll** opens a window of its own that owns the claim for its lifetime.
Enrolling used to report through a single subtitle on a combo row, which is how
every failed attempt across three sessions produced nothing to go on. It shows a **contact strip**
(the last 12 s of fprintd's `finger-present`, with each result marked on the
same time axis), **stage pills**, a running **tally**, and a timestamped
**attempt log** mirrored to stderr for `journalctl --user`.

Rules to keep if you edit it:

1. **Classify every result `gesture` / `driver` / `fatal`, and say which.**
   This is the whole point. "Try again, slower" in response to a driver fault
   is how someone swipes forty times at a reader that was never going to
   answer. An *undocumented* result string is treated as `driver`.
2. **Bake in no target speed.** The window measures the user's own contacts and
   labels the ones that passed. The right dwell for a sensor is not something
   this panel can honestly claim to know.
3. **Advance stages only on `enroll-stage-passed`.** A rejected attempt really
   does not count, and pretending otherwise makes the next failure baffling.
4. **Keep `Claim` async.** It waits on a polkit password prompt; synchronously
   it froze the window before it painted.
5. **Take the result vocabulary from the D-Bus spec**, not from memory. The
   first version silently lacked `enroll-too-fast`, `enroll-duplicate` and
   `enroll-unknown-error` — and the last one is exactly what this machine emits.
6. **Say to lift, on every stage.** libfprint's image-device cycle
   (`AWAIT_FINGER_ON → CAPTURE → AWAIT_FINGER_OFF → IDLE`) will not start the
   next capture until the driver reports the finger **gone**, so a finger left
   resting on the sensor stalls the run with no message. `_cycle_hint()` builds
   that line from `gesture` (**not** `scan-type` — see above); it is used on
   `enroll-stage-passed`, on every
   `gesture` retry, and in the guide. fprintd's own answer to a *passed* stage
   is "Lift then touch again" — this panel was the only client of the three
   that never said it. A precondition of the protocol is not an exception to
   rule 1.
7. **Restart the enrolment on a `driver` terminal; never end the session.**
   The fault ends fprintd's enrolment, not the claim the window owns, so
   `_restart_enrollment()` does `EnrollStop` + `EnrollStart` and the user is
   not sent back through polkit — which used to cost a password every few
   captures on this machine. It runs **before** `_stop()` on purpose: `_stop`
   disconnects `g-signal`, and restarting after it would leave the next
   `EnrollStatus` with nowhere to go and the window hung with nothing in the
   log. The stage count really does return to 0 (fprintd discards partial
   progress) and the hint says so rather than resetting quietly. Two caps —
   `MAX_DRY_RESTARTS` for a wedged endpoint faulting with no contact,
   `MAX_RESTARTS` as a ceiling — and the UI names which one tripped. `fatal`
   results are never restarted. Regression test: `test-enroll.py`.

Run `python3 -I test-enroll.py` from this directory after touching the
enrolment flow: 40 assertions over `_handle_result`, with the widgets and the
D-Bus proxy stubbed, covering the paths a real finger reaches only by accident.

Three invariants to keep if you edit the group:

1. **Claim → EnrollStart → EnrollStop → Release on every path out**, errors and
   `close-request` included. A claim left behind means the next `Super+L` has
   no fingerprint until fprintd times it out.
2. **Never poll the fingerprint group from the 2 s loop.** Enrolled prints
   change only when this panel changes them, and a timed `ListEnrolledFingers`
   would race the `EnrollStatus` signals. `_refresh_fingerprint()` runs at
   startup and after enroll/delete, and no-ops while `_enrolling`.
3. **`ListEnrolledFingers` raises when nothing is enrolled** rather than
   returning an empty list. Only that one error means "none"; everything else
   is a real failure and is shown as one.

The **unlock switch** writes a marker-delimited block in
`~/.config/hypr/hyprlock.conf`. That file is *not* sourced by `hyprland.conf`,
so writing it does not trigger Hyprland's auto-reload; hyprlock reads it at the
next lock. No PAM file is touched anywhere — hyprlock 0.9.6 drives fprintd over
D-Bus itself. The switch refuses to enable with zero fingers enrolled, and
refuses to write at all if `hyprlock.conf` already has its own `auth` block.

⚠ It writes the **live** file, so `configs/hypr/hyprlock.conf` in the repo then
differs and has to be pulled back by hand.

The `sudo` row is **read-only** by design. `chwd` already put
`auth sufficient pam_fprintd.so` in `/etc/pam.d/sudo`; a broken edit there costs
you sudo entirely, so the panel reports it and nothing more.

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
* **The battery trace keeps its first point fixed.** A flat percentage
  collapses into one moving endpoint so that six hours cost about eighty points
  instead of ten thousand — but letting that collapse touch the *first* point
  drags the run's start forward on every tick, so a panel left alone at 60%
  would report a run that began a second ago and an average computed from
  whatever sliver was left once the percentage finally moved. Found by
  `test-battery.py`, not by watching: it needs a percentage to hold for
  minutes, which is precisely what it does on a 100 Wh pack.

## Troubleshooting

| symptom | cause |
|---|---|
| fans/profile groups say "unavailable" | `predator_v4=1` is not in effect |
| charge-cap switch is insensitive | `acer-wmi-battery` is not loaded |
| toast: "triton-ctl has no sudoers rule yet" | step 3 of Install was skipped |
| ppd row says "placeholder driver, restart ppd" | `sudo systemctl restart power-profiles-daemon` — it probes platform drivers only at startup |
| window opens tiled | the window rules are not pushed to `~/.config/hypr/` |
| blank or black window | `GSK_RENDERER=gl triton-panel` (GTK4 renderer fallback) |
