# Fingerprint: Enrolment and Unlock

> Part of the `cachyPool` runbooks. Section numbers are **preserved** from
> `finish-installation-commands.md`, dissolved 2026-11-03 — a `§N` reference
> anywhere in this repo still resolves by number. Index and conventions:
> `README.md`. Live-state history: `../CHANGELOG.md`.

The `04f3:0c4f` ELAN reader: three sessions of misdiagnosis, the area-pad-versus-swipe error that caused them, a successful enrolment whose template matches nothing, and the calibration phase that exists so the panel stops treating *enrolled* as the goal.

---

## 20. Fingerprint: enrol and unlock from Triton Panel — ✅ WIRED 2026-10-31 · ✅ ENROLLED 2026-11-01

The machine has an **ELAN `04f3:0c4f`** reader. `fprintd 1.94.5` + `libfprint
1.94.100` were already installed and libfprint's in-tree **`elan`** driver binds
it: `fprintd-list` answers *"ElanTech Fingerprint Sensor"*, which is that
driver's `full_name` (`elanmoc` would say *"Elan MOC Sensors"* and `elanspi`
*"ElanTech Embedded Fingerprint Sensor"* — all three strings sit in
`libfprint-2.so.2`, so the reported name identifies the driver).

✅ **`right-index-finger` enrolled 2026-11-01** — 6 of 6 stages in ~54 s with
two rejections and **zero** protocol errors. It had failed for three sessions,
and **§20g's verdict that no gesture could fix it was wrong**: the cause was
the *instructions*, both of which the panel derived from bad inputs. See §20l
for the correction and what it means for reading a journal like this one.
§20a–§20f are correct and verified; §20g is kept as the record of the
misreading, annotated.

### 20a. What already existed

* **`sudo` was already wired.** CachyOS's `chwd` had put
  `auth sufficient pam_fprintd.so # chwd-fprintd` in `/etc/pam.d/sudo`. It
  starts working the moment a finger is enrolled; the panel reports its state
  but **never edits it** — that is the lockout-class file.
* **No PAM change is needed for the lock screen.** hyprlock 0.9.6 drives
  fprintd **over D-Bus itself** (`auth:fingerprint:*` config keys, strings
  `fprint: started verifying` in the binary). So unlocking by fingerprint
  carries none of the risk a `/etc/pam.d/hyprlock` edit would.
* **There is nothing else to unlock.** This machine boots via `getty@tty1`
  autologin with no display manager and no login prompt, so hyprlock
  (`Super+L`, and hypridle at 5 min) is the only gate.

### 20b. polkit, and why the panel can do this unprivileged

From `net.reactivated.fprint.device.policy` on this machine:

| action | `allow_active` | consequence |
|---|---|---|
| `…device.verify` | `yes` | listing enrolled fingers needs **no** prompt |
| `…device.enroll` | `auth_self_keep` | `Claim()` raises a polkit dialog for your **own** password |
| `…device.setusername` | `auth_admin_keep` | never used — the panel only ever touches the current user |

`/var/lib/fprint` is `drwx------ root root`, so enrolled prints **cannot** be
read from the filesystem as the user. Everything goes through D-Bus.

### 20c. The panel's Fingerprint group

Sensor (name · scan type · enroll stages), what is enrolled, a finger picker
with **Enroll**, **Delete all prints**, an **Unlock hyprlock with fingerprint**
switch, and a read-only `sudo` row.

Three rules it enforces:

1. **Claim → EnrollStart → EnrollStop → Release, on every path out**, including
   errors and closing the window mid-enrolment (`close-request`). A claim left
   behind means the next `Super+L` has no fingerprint until fprintd times it
   out.
2. **The switch refuses to enable with zero fingers enrolled**, which would
   otherwise give a lock screen asking for a finger it can never match.
   Deleting the last print also switches it back off.
3. **It refuses to touch `hyprlock.conf` if that file already has its own
   `auth` block**, rather than produce a config with two.

Not polled on the 2 s tick: enrolled prints change only when the panel changes
them, and a timed `ListEnrolledFingers` would race the `EnrollStatus` signals.

### 20d. The hyprlock block

`hyprlock.conf` is **not** in `hyprland.conf`'s `source` list, so writing it does
**not** trigger Hyprland's auto-reload (which would snap the monitors to the
`monitors.conf` boot geometry). hyprlock reads it at launch, so a change applies
at the next lock. The panel owns a marker-delimited block and writes it
atomically:

```
# >>> triton-panel: fingerprint unlock >>>
auth {
    fingerprint {
        enabled = true
        ready_message = (Touch finger to unlock)
        present_message = Scanning fingerprint
        retry_delay = 250
    }
}
# <<< triton-panel: fingerprint unlock <<<
```

⚠ **Corrected 2026-11-01.** The verb used to come from the device's reported
`scan-type`, which is **`swipe`** here — and that turned out to be *wrong*, so
the block said "Swipe finger to unlock" for a pad that cannot be swiped. It now
comes from `info["gesture"]`, the physical sensor type (§20j): `Touch` for an
area pad, `Swipe` only for a real strip. Never rebuild this from `scan-type`.

⚠ The panel writes the **live** file. `configs/hypr/hyprlock.conf` then differs
and must be pulled back into the repo by hand — the panel says so in a toast.

### 20e. Verify — results 2026-10-31

| check | result |
|---|---|
| reader detected | ElanTech Fingerprint Sensor · `swipe` · **6** enroll stages |
| `ListEnrolledFingers` with nothing enrolled | fprintd **raises** rather than returning `[]`; translated to "none", every other error reported as a real failure |
| group renders | all six rows; switch **insensitive** with "Enroll a finger first" |
| no claim leaked | after each panel run the device still answers — a leak would fail with "already claimed" |
| block write | enable → disable → enable is idempotent (exactly one marker block); disable removes it cleanly |
| hand-written `auth` block present | refused with "edit it by hand" |

⚠ Enrolment itself was untested at this date. It then failed repeatedly for
three sessions — see §20g for the diagnosis that turned out to be wrong, and
§20l for the enrolment that succeeded on 2026-11-01.

### 20f. The enrolment window — added 2026-11-01

Enrolling used to report through **one subtitle on a combo row**. That is how
every failed attempt across three sessions produced no usable account of why:
the only surviving evidence was fprintd's own journal, read the next morning. The
**Enroll** button now opens a dedicated window (`EnrollWindow`) that owns the
claim for its whole lifetime.

What it shows:

| element | what it is for |
|---|---|
| **contact strip** | the last 12 s of fprintd's `finger-present` property drawn as blocks, with every result marked on the same time axis — green accepted, amber gesture, red driver |
| **stage pills + `n / 6`** | advanced **only** by `enroll-stage-passed` |
| **status + hint** | the current result in words, with advice that escalates after the same reason repeats three times |
| **tally** | `11 attempts · 6x Too fast · 3x No usable detail` |
| **attempt log** | timestamped rows, **mirrored to stderr** so `journalctl --user` keeps them |
| **banner** | shown when the reader's USB id is a known driver/sensor mismatch |

Seven rules in the code worth keeping:

1. **Results are classified `gesture` / `driver` / `fatal`, and the UI says
   which.** This is the point of the window. Telling someone to "try again,
   slower" when the driver could not speak to the sensor is how they end up
   swiping forty times at a reader that was never going to answer. An
   *undocumented* result string is treated as `driver`, not as a gesture.
2. **No target speed is baked in.** The window measures the user's own contacts
   and labels the ones that passed (`last accepted 0.35s`). The right dwell for
   a given sensor is not something this panel could honestly claim to know.
3. **A rejected attempt does not advance the counter**, because it genuinely
   does not.
4. **`Claim` is async.** It raises a polkit prompt and blocks for as long as a
   human takes to type a password; synchronously it froze the window before it
   had painted a frame. `EnrollStart`/`EnrollStop`/`Release` stay synchronous.
5. **A result closes the open contact at that instant** rather than waiting for
   an off-transition — a result can arrive while the driver still reports the
   finger down.
6. **The result vocabulary comes from the interface spec**, not from memory.
   The first version was missing `enroll-too-fast`, `enroll-duplicate` and
   `enroll-unknown-error` and printed the raw D-Bus string;
   `enroll-unknown-error` is exactly what this machine produces.
7. **A `driver` terminal restarts the enrolment instead of ending the
   session** (added §20k). The fault ends fprintd's enrolment, not the claim,
   so `EnrollStop` + `EnrollStart` keeps going without a second polkit prompt.
   It must run **before** `_stop()`, which would disconnect `g-signal` and
   leave the window hung with nothing in the log. Two caps, and the UI says
   which one tripped.

Source of truth for the vocabulary:
`/usr/share/dbus-1/interfaces/net.reactivated.Fprint.Device.xml`.

**Verified 2026-11-01** by driving `_handle_result` with synthetic results —
the path a real finger had never reached:

| check | result |
|---|---|
| every `enroll-*` in the spec is mapped, and nothing invented | ✅ both directions |
| rejection does not advance the stage | ✅ `passed` stays 0 |
| `last accepted` is measured, not constant | ✅ 0.35 s from the simulated contact |
| advice escalates on the third identical reason | ✅ |
| result arrives while the finger is still down | ✅ contact closed at that instant |
| driver fault does not blame the gesture | ✅ retry **and** terminal branch |
| unknown result string | ✅ classified `driver` |
| happy path 6/6 → `enroll-completed` | ✅ |
| cairo draw with and without data | ✅ no exception |
| teardown | ✅ no timer and no signal handler left behind |

⚠ Not verified: the **visual layout** (the session was locked when the
screenshot was attempted) and live `g-properties-changed` delivery of
`finger-present`, which needs a real finger.

### 20g. Why enrolment fails on this machine — 2026-11-01

⚠ **Revised by §20j**, written later the same day: a second round of attempts
produced journal lines this section did not have, which narrow its "no gesture
changes that" claim and add the image-device state machine. Read both.

`journalctl -u fprintd` across every attempt so far:

```
Device reported an error during enroll: The driver encountered a protocol error with the device.
Failed to detect minutiae: No minutiae found
Device reported an error during identify for enroll: The driver encountered a protocol error with the device.
```

**Not one `too-short` or `too-fast` in the lot.** These are
`FP_DEVICE_ERROR_PROTO` — driver and sensor disagreeing about the protocol. No
gesture changes that. The panel's polkit → Claim → EnrollStart path is proven
healthy by the same journals: hyprpolkitagent opened its dialog, the enrolment
ran, and `journalctl --user` holds no Python traceback.

Upstream context: `04f3:0c4f` **is** listed in libfprint's supported-devices
table under `elan`, but field reports for this family are consistently negative,
and the sibling `04f3:0c4b` has the identical symptom documented — the in-tree
driver claims the id and then speaks an older protocol than the sensor
revision. linux-hardware.org records no working driver for `04f3:0c4f`.

**USB autosuspend is ruled out** (tested 2026-11-01). `usbcore.autosuspend=2`
is set and the reader reads `power/control=auto`, which looked like a candidate:
it is a USB 1.1 full-speed device, and a suspend/resume inside a driver command
sequence is a classic source of protocol errors. It is not the cause here,
because an open file descriptor pins the device awake:

```
$ cat /sys/bus/usb/devices/3-9/power/runtime_status      # suspended
$ exec 3< /dev/bus/usb/003/003 ; sleep 5
$ cat /sys/bus/usb/devices/3-9/power/runtime_status      # active
$ exec 3<&- ; sleep 4
$ cat /sys/bus/usb/devices/3-9/power/runtime_status      # suspended
```

libfprint holds the device open for the whole duration of a claim, so it cannot
autosuspend mid-enrolment. **Do not add a `power/control=on` udev rule for this**
— one was written and then deleted once this test came back. If the status ever
reads `suspended` *while* an enrolment is running, this conclusion is wrong and
worth revisiting.

That leaves one lead: **a TOD driver.** Elan ships a closed-source *Touch OEM
Driver* used through `libfprint-tod`; that is how `04f3:0c4b` was made to work.
As of 2026-11-01 **no confirmed `0c4f` support was found** in
`libfprint-2-tod1-elan` or any community fork, so this is a search, not a
recipe. After installing one, check the id list in
`/usr/lib/udev/rules.d/60-libfprint-2-tod1-elan.rules` before swiping anything.

~~Until one of those lands the honest status is: the reader is detected, fully
wired, and cannot enrol.~~ **Wrong — superseded by §20l.** The reader enrolled
on 2026-11-01 with no driver change at all, and no TOD was ever installed. This
paragraph is left standing because the reasoning that produced it is the thing
worth not repeating: see §20l.

### 20h. Revert

Turn the switch off (removes the block), then `fprintd-delete $USER`. To drop
fingerprint `sudo` as well, remove the `pam_fprintd` line chwd put in
`/etc/pam.d/sudo` — validate with care, that file is lockout-class.

### 20i. Docs updated

2026-10-31: `../ACTUAL-CONFIGURATION.md` §15 new row; `../CLAUDE.md`;
`../triton-panel/README.md`; this section.

2026-11-01: §20f/§20g added; the `elanmoc` claim in the intro corrected to
`elan`; `../ACTUAL-CONFIGURATION.md` §15 row changed from "never used" to "cannot
enrol". A `configs/udev/rules.d/` autosuspend rule was written and then deleted
when the test in §20g ruled the hypothesis out.

2026-11-01 (second pass): §20j added and §20g annotated as revised by it.
`triton-panel/triton-panel` gained `EnrollWindow._cycle_hint()` — the lift
instruction the state machine requires, which the window never gave — and then
`AREA_SENSORS` + `info["gesture"]`, after the sensor was checked against the
chassis and the driver's `scan-type = swipe` turned out to be wrong: all seven
instruction sites and `hyprlock_set()` now read `gesture`, and §20d's claim
that the verb comes from `scan-type` was corrected. New `triton-panel/fp-debug.sh`
(the debug harness; not installed anywhere, run from the checkout).

2026-11-01 (fourth pass): **§20l added — it enrolled.** `§20` heading
⛔→✅; `§20g`'s closing verdict struck through as superseded; `§20` intro,
`§20e` note and `§20j`'s "test that has never been run" annotated; `§20k`'s
"zero captures accepted" closed out. `../CLAUDE.md`'s fingerprint bullet rewritten
(the old ⛔ rule actively blocked the fix); `../ACTUAL-CONFIGURATION.md` §15 row
resolved; `../triton-panel/README.md` headline rewritten. The enrolment window's
pre-emptive driver banner and `ELAN_PROTOCOL_MISMATCH` deleted.

2026-11-01 (third pass): §20k added — the first press-gesture run's numbers (8
captures, 0 accepted), what was really ending each session (`enroll-unknown-error`
with `done = True`, not the `enroll-retry-scan` it was reported as), and the
restart loop that keeps the claim so a driver fault no longer costs a polkit
password. New `triton-panel/test-enroll.py` (40 assertions). §20j read-out table
annotated. `../ACTUAL-CONFIGURATION.md` §15 row extended.
`../ACTUAL-CONFIGURATION.md` §15 fingerprint row and `../CLAUDE.md`'s fingerprint
bullet updated; `../triton-panel/README.md` enrolment section updated.

### 20j. The lift step, the reference clients, and the test still unrun — 2026-11-01 (second pass)

§20g was written from the **summary** lines in `journalctl -u fprintd`. A second
round of attempts the same morning produced lines that had not appeared before,
and they move the diagnosis in **both** directions. Read this after §20g.

#### The new journal lines, verbatim

```
Nov 01 09:44:35 fprintd[2504]: Device reported an error during enroll: The driver encountered a protocol error with the device.
Nov 01 09:44:55 fprintd[2504]: Internal state machine issue: transition from FPI_IMAGE_DEVICE_STATE_AWAIT_FINGER_ON to FPI_IMAGE_DEVICE_STATE_AWAIT_FINGER_OFF should not happen!
Nov 01 09:45:05 fprintd[2504]: Internal state machine issue: transition from FPI_IMAGE_DEVICE_STATE_AWAIT_FINGER_ON to FPI_IMAGE_DEVICE_STATE_AWAIT_FINGER_OFF should not happen!
Nov 01 09:45:08 fprintd[2504]: Device reported an error during enroll: The driver encountered a protocol error with the device.
Nov 01 09:45:50 fprintd[2504]: Failed to detect minutiae: No minutiae found
Nov 01 09:46:23 fprintd[2504]: Device reported an error during identify for enroll: The driver encountered a protocol error with the device.
```

#### What they add

**1. The reader runs on libfprint's image-device layer, and the driver is
driving it out of order.** The `FPI_IMAGE_DEVICE_STATE_*` names come from
`fpi-image-device.c`, so `elan` here is an *image* driver: it captures frames,
stitches them, and hands a picture to NBIS for minutiae extraction. That layer
has one fixed cycle, and libfprint's own reference manual lists the only valid
transitions:

| from | to | triggered by |
|---|---|---|
| `IDLE` | `AWAIT_FINGER_ON` | libfprint, when it wants a capture |
| `AWAIT_FINGER_ON` | `CAPTURE` | driver calls `fpi_image_device_report_finger_status()` — finger arrived |
| `CAPTURE` | `AWAIT_FINGER_OFF` | driver calls `fpi_image_device_image_captured()` |
| `AWAIT_FINGER_OFF` | `IDLE` | driver calls `fpi_image_device_report_finger_status()` — finger **gone** |

`AWAIT_FINGER_ON → AWAIT_FINGER_OFF` is **not in that table**, which is why
libfprint prints "should not happen". The `elan` driver told libfprint the
finger was gone while libfprint was still waiting for it to *arrive*. Nothing
above the D-Bus boundary can cause or fix this — but record it, because it is
the mechanism behind the complaint *"I cannot lift my finger and finish the
enrolment"*: the lift is a real, mandatory step in the protocol, and on this
machine the driver mishandles it.

**2. `No minutiae found` means an image really was captured.** That message is
NBIS failing on a picture it was given — so the capture path *does* complete
sometimes, and what fails afterwards is minutiae extraction on an image that is
too small or has no ridge detail. §20g's *"no gesture changes that"* stands for
the `PROTO` lines and is **too absolute as a blanket claim**. Both readings are
live until the debug run below separates them. Do not flip the other way
either: six of these attempts still died in the driver.

#### The lift/place cycle belongs to libfprint, not to any UI

This is the answer to "how should an enrol/detect interface work", and it is
the same answer in every client, because the interesting part is not in the
client at all:

* **The cycle is mandatory.** Per the table above, the next capture cannot
  start until the driver has reported the finger **gone**. A finger left
  resting on the sensor stalls the run with **no error message** — which is
  exactly what "it does not go on to the next stage" looks like.
* **No client can skip or hurry it.** `EnrollStart` is called **once** for the
  whole enrolment, not once per stage. The client then just listens to
  `EnrollStatus` and counts `enroll-stage-passed` up to `num-enroll-stages`
  (6 here). There is no per-stage method to call.
* **`finger-present` is advisory.** It is a property to *display*, never to
  drive the flow.

Reference clients, read 2026-11-01:

| client | reacts to | tells the user when to lift? |
|---|---|---|
| `fprintd-enroll` (fprintd's own CLI) | `EnrollStatus` only | via the status string only |
| `gnome-control-center` `cc-fingerprint-dialog.c` | `EnrollStatus` + `notify::finger-present` (for styling) + ScreenSaver `ActiveChanged` | yes — status strings, plus the fallback *"Repeatedly lift and place your finger on the reader to enroll your fingerprint"* |
| hyprlock 0.9.6 | fprintd `VerifyStatus` over D-Bus | verify only, no enrolment |

And fprintd's canonical wording, from `enroll_result_str_to_msg()` in
`fingerprint-strings.h` (the same table `pam_fprintd` ships — the strings are
in `/usr/lib/security/pam_fprintd.so` on this machine):

| result | press sensor | swipe sensor |
|---|---|---|
| `enroll-stage-passed`, `enroll-retry-scan` | **"Lift then touch again"** | **"Swipe your finger again"** |
| `enroll-remove-and-retry` | "Remove your finger, and try touching the sensor again" | "Remove your finger, and try swiping your finger again" |
| `enroll-too-fast` | "Finger scan was too fast, try again" | "Swipe was too fast, try again" |
| `enroll-finger-not-centered` | "Your finger was not centered, try touching the sensor again" | "Your finger was not centered, try swiping your finger again" |

Note what the **success** row says: upstream's reply to a *passed* stage is
"lift then touch again". The lift is the instruction, on every single stage.

#### What Triton Panel was missing — fixed 2026-11-01

The enrolment window said, on a passed stage:

> Same finger, same part of the pad, once more.

It never said to **lift**. That is the one instruction the state machine
actually requires, and this panel was the only client of the three above that
omitted it. Now a single `_cycle_hint()` on `EnrollWindow` produces it from the
device's `scan-type`, and it is used on `enroll-stage-passed`, on every
`gesture` retry, and in the "How this works" guide (whose swipe branch also
never mentioned lifting).

⚠ This is **not** the thing `../CLAUDE.md` warns against ("don't fix it with UI
copy telling the user to swipe differently"). That warning is about blaming the
gesture for a driver fault, and it still holds: the gesture/driver/fatal
classification is untouched, and a `driver` result still says in so many words
that no gesture will help. Stating a **precondition of the protocol** is a
different thing from giving technique advice.

#### The remaining hypothesis: a press sensor driven as a swipe sensor

Upstream analysis of the sibling **`04f3:0903`** argues that the physical part
is a static **press/area** pad (a small capacitive square, ~96×96 or 144×64),
while `elan.c` classifies the family as `FP_SCAN_TYPE_SWIPE` and runs
multi-frame motion assembly (`fpi_assemble_frames`). A static press produces no
displacement between frames, assembly yields nothing usable, and extraction
ends in *"No minutiae found"*. The same write-up claims a timed-out command is
not followed by a clear-halt or endpoint reset, so later transfers fail with
protocol errors, and that the only recovery is a USB unbind/rebind plus an
`fprintd` restart.

How well it fits this machine: the `No minutiae found` line, the `PROTO` lines
*after* a timeout, and the out-of-order finger reporting are all consistent
with it. What does **not** carry over for free: that is `0903`, not `0c4f`, the
claims are the author's own with no upstream fix behind them, and our
`scan-type` reads `swipe` (that author's read `press`) — from the suspect
driver, so it proves nothing either way.

**Settled by eye the same day: it is an area pad.** The part in this chassis is
a ~1 cm square in the corner of the touchpad. There is nothing to slide a
finger *along*, so `scan-type = swipe` is not merely "unconfirmed" as §20g had
it — it is **wrong**, and the press-sensor reading now has this machine's
hardware behind it rather than an analogy to `0903`.

What that changed in the panel:

| before | after |
|---|---|
| every verb built from `info["scan_type"]` | built from `info["gesture"]`, the physical type — `AREA_SENSORS = {"04f3:0c4f"}` keys it by **USB id**, never by the driver's reported name |
| guide: *"Slide the finger across the sensor in one continuous motion"* | the press branch, prefixed by a line saying what the driver claims, that it is wrong, and why |
| `_cycle_hint()`: *"then swipe again"* | *"then touch it again"* |
| `ready_message = (Swipe finger to unlock)` | `(Touch finger to unlock)` — §20d corrected, it asserted the opposite |
| sensor row: `… · swipe` | `… · swipe → really press` |

`scan_type` is **kept and still displayed**: what the driver claims is evidence
about the driver. It is simply never used to build an instruction again. Note
nothing was enrolled and the hyprlock switch was off, so no block carrying the
wrong verb was ever on disk — neither live nor in `configs/hypr/hyprlock.conf`.

What is still open is **frame counts**, and that is what the run below is for.

#### The test that has never been run

⚠ **Superseded by §20l.** The panel went on to enrol successfully, which
answers *"panel or driver?"* without this run. `fp-debug.sh` is still the right
tool if the protocol errors ever bite on **verify** rather than enrol — keep it
for that.

Every failed attempt so far went through Triton Panel, so *"panel or driver?"*
is still formally open, and the journal has only ever shown summary lines.
Both gaps close in one run. The script lives in the repo at
**`triton-panel/fp-debug.sh`** (next to `triton-ctl`) — it is not installed
anywhere, run it from the checkout.

⚠ **Run it from a terminal inside the Hyprland session, not from a bare tty.**
`Claim()` goes through polkit and the agent here is `hyprpolkitagent`, started
by `autostart.conf` *inside* the session. On `Ctrl+Alt+F2` there is no agent and
`fprintd-enroll` dies on an authorization error that reads exactly like a driver
fault. The script refuses to run without `WAYLAND_DISPLAY`/`DISPLAY` for that
reason, and warns if the agent is not up. "Close the panel" means close its
window.

What it does: refuses to run while Triton Panel holds the claim (matched on the
installed path `.local/bin/triton-panel` — a bare `pgrep -f triton-panel` also
matches the shell that launched the script from the `triton-panel/` directory),
writes
`Environment=G_MESSAGES_DEBUG=all` as a drop-in **under `/run`** (so it cannot
survive a reboot and needs no revert — do **not** use `systemctl edit`, it
opens an editor), restarts `fprintd`, captures `journalctl -u fprintd -f` to a
file, runs the **reference** client `fprintd-enroll -f right-index-finger`, and
removes the drop-in on every exit path.

```bash
./fp-debug.sh press     # flat, hold ~2s, LIFT CLEAR, wait for the prompt
./fp-debug.sh swipe     # ROLL edge to edge without losing contact, then lift
./fp-debug.sh rebind    # recover a wedged reader; no enrolment
```

Run both, separately — the comparison is the point, and now that the pad is
known the two runs mean something specific: `press` is what the **hardware**
wants, and `swipe` (a *roll* across the pad, since there is nowhere to swipe
along) manufactures the inter-frame displacement the **driver** wants. How to
read the result:

| what the debug log shows | reading |
|---|---|
| frame counts climbing, `TOO_SHORT` / assembly retries before each failure | gesture-and-geometry shaped; the press-sensor hypothesis gains |
| `PROTO` immediately after a device command, no frames at all | driver shaped; §20g stands |
| `fprintd-enroll` gets **further** than the panel ever did | the panel is the suspect; re-open §20f |
| `fprintd-enroll` fails **identically** | the panel is exonerated; stop looking at it |
| `press` keeps giving `No minutiae found` but the **roll** produces frames or a passed stage | the swipe-driver-on-an-area-pad reading is confirmed; the fix is a driver (a TOD, or an `elanpress`-style fork), never a gesture |
| `calibrat` lines failing repeatedly | `elan_calibrate`'s strict delta threshold, a third candidate |

Note since §20k: the panel now **restarts the session itself** after a driver
terminal, so a session no longer ends on the first `PROTO`. If it does hand you
a "Try again" button, one of the two caps tripped and the hint says which — it
is never the panel giving up on `No usable detail`, which has never stopped
anything.

`rebind` exists because a `PROTO` error may leave the USB endpoint halted, in
which case **every later attempt in the same session is doomed regardless of
gesture** — worth clearing before each run. Note the counter-evidence already
in hand: the `No minutiae found` at 09:45:50 arrived *after* two `PROTO` errors,
so the wedge is not always permanent.

#### Minor, noticed in the same journal

`EnrollStop` and `Release` were each refused with *"Device was not claimed
before use"* at 09:46:27, after a real run — `_stop()` reached D-Bus twice.
Harmless (fprintd just declines), and "safe to call twice" is true panel-side.
Only worth fixing if `_stop` is touched for another reason.

### 20k. The press gesture captures, the session kept dying, and the restart loop — 2026-11-01 (third pass)

First run after §20j's copy fix, enrolling right index through the panel with
the **press** gesture. `journalctl -u fprintd`, 10:19:02 → 10:21:34, counted:

| events in one 85-second session | count |
|---|---|
| `Failed to detect minutiae: No minutiae found` | **8** |
| `Device reported an error during identify for enroll: … protocol error` | 4 |
| `Device reported an error during enroll: … protocol error` | 3 |
| `enroll-stage-passed` | **0** |

Two things in that table matter.

**The press gesture works, as far as capture goes.** Eight images were
assembled and handed to NBIS, against **one** in the whole morning of swipe
attempts (§20j). That is the area-pad reading confirming itself a second time,
by behaviour this time rather than by looking at the chassis.

**And not one capture passed.** Every image was rejected for having no usable
minutiae. libfprint wants roughly ten minutiae to accept a stage, and a ~1 cm
pad does not give many — this is the small-sensor limit upstream describes,
now reached on real data. So the blocker has moved: it is no longer "nothing
is captured", it is "what is captured is too thin to count".

#### What was actually ending the session

Reported as: *"when the status is 'No usable detail' it should not stop the
program, we should continue until the 6 needed measurements."*

`No usable detail` is this panel's title for **`enroll-retry-scan`**, which
fprintd sends with `done = False`. It never stopped anything — the handler's
`if not done:` branch logs it and returns, and the run continues. What ended
each session was the **next** line down the journal: `Device reported an error
during enroll` is fprintd's `enroll_cb` catching a non-retry `GError`, and it
emits **`enroll-unknown-error` with `done = True`** — terminal. Three of those
in 85 seconds, and the old code answered each one with `_stop(release=True)`:
`EnrollStop`, `Release`, button to "Try again". Because the **claim** went back
too, "Try again" meant a fresh `Claim()` and therefore **another polkit password
prompt**. That is what made it feel like the program stopping: it did stop, on
a driver fault, and restarting cost a password each time.

#### The restart loop

A driver fault ends fprintd's *enrollment*; it does not end the *claim*, which
the window owns for its whole lifetime. So the window now restarts the
enrolment itself — `EnrollStop` then `EnrollStart`, claim untouched, no polkit
prompt — and keeps the tally and attempt log accumulating across restarts.

Three things in `_restart_enrollment()` worth keeping:

1. **It must not go through `_stop()`.** `_stop` disconnects the `g-signal`
   handler, so restarting after it would leave the next `EnrollStatus` with
   nowhere to go: the window would look hung with *nothing in the log*, which
   is worse than stopping. The restart branch therefore runs **before**
   `_stop` in the terminal path and touches neither handler nor tick.
2. **The stage count genuinely goes back to zero, and the UI says so.**
   fprintd discards the partial enrolment when the operation fails, so the
   next `EnrollStart` really does start at 0. A quiet reset would read as a
   glitch, so the hint names it: *"fprintd discarded the 3 stages already
   captured, so the count is back to 0 of 6."*
3. **Two caps, for the two failure shapes in the journal**, and the UI says
   which one tripped — "the panel gave up" and "the panel decided your gesture
   was wrong" look identical from outside and only one of them is ever true:

| cap | what it catches | on tripping |
|---|---|---|
| `MAX_DRY_RESTARTS = 3` | the fault arriving back-to-back with **no finger contact** between restarts — a wedged USB endpoint, which a restart cannot clear | stops, and points at `./fp-debug.sh rebind` |
| `MAX_RESTARTS = 15` | a hard ceiling, so an unattended window cannot loop for an hour | stops, saying it is not the gesture |

Contact between faults (the shape actually seen: PROTO every 2–4 captures with
real presses in between) resets the dry counter, so a working session is never
cut short. `fatal` results — `enroll-duplicate`, `enroll-data-full`,
`enroll-failed` — are **not** auto-restarted; looping on a duplicate or full
storage is pointless.

#### What this does and does not buy

It removes the password prompts and lets a session keep producing data. At the
time of writing it had not made a capture *pass* — zero accepted out of eight.

✅ **Ten minutes later one did, and then all six did.** 10:30:27 → 10:31:21:
two `No minutiae found`, **no protocol errors at all**, six stages accepted,
finger enrolled. So the restart loop was not what closed it — the instructions
were — but the loop is what kept a session alive long enough to get there.
§20l.

#### Verified 2026-11-01 — `triton-panel/test-enroll.py`

40 assertions, run with `python3 -I test-enroll.py` from `triton-panel/`. It
stubs the widgets and the D-Bus proxy and drives `_handle_result` with
synthetic `EnrollStatus` events — the path a real finger reaches only by
accident. Kept in the repo this time; §20f's equivalent harness was thrown
away and had to be rebuilt.

| check | result |
|---|---|
| a retry credits no stage, counts an attempt, does not stop | ✅ |
| retry status reads `… — still going, 0 of 6` | ✅ (the reported confusion) |
| a terminal driver fault calls exactly `EnrollStop` + `EnrollStart` | ✅ |
| `_stop` not called, both handlers and the tick still alive | ✅ |
| no `Claim`, so no second password prompt | ✅ |
| the **next** status after a restart still lands and credits a stage | ✅ `passed == 1` |
| a restart that loses stages names how many | ✅ |
| dry cap trips at 3 and points at `rebind` | ✅ |
| contact between faults resets the dry counter — 6 restarts, never stopped | ✅ |
| hard ceiling stops without blaming the gesture | ✅ |
| `enroll-duplicate` / `-data-full` / `-failed` not restarted | ✅ |
| a failing `EnrollStart` on restart releases and degrades cleanly | ✅ |
| success path still completes and releases | ✅ |
| tally shows restarts, singular and plural | ✅ |

⚠ Still not verified: the visual layout, and live `g-properties-changed`
delivery of `finger-present` (needs a real finger — the contact strip's data
source).

### 20l. ✅ It enrolled — and why §20g was wrong — 2026-11-01

```
$ fprintd-list isalgado
Fingerprints for user isalgado on ElanTech Fingerprint Sensor (swipe):
 - #0: right-index-finger
```

(`(swipe)` there is the **driver's claim**, not the hardware — §20j. The pad is
a press sensor and `fprintd-list` has no way to know better.)

The run, from `journalctl -u fprintd`, 10:30:27 → 10:31:21 (~54 s):

| events | count |
|---|---|
| `Failed to detect minutiae: No minutiae found` | 2 |
| `Device reported an error during enroll: … protocol error` | **0** |
| stages accepted | **6 of 6** |

No driver was changed. No TOD was installed. `libfprint 1.94.100` and the
in-tree `elan` driver are exactly what §20g declared incapable.

#### What changed, and what cannot be credited

Two instruction fixes went in earlier the same day:

1. **The gesture verb.** The driver declares `scan-type = swipe`; the part is a
   ~1 cm square pad. The window had been telling the user to *slide a finger
   across* a sensor that cannot be slid across. Fixed by `AREA_SENSORS` →
   `info["gesture"]` (§20j).
2. **The lift between stages.** libfprint's image-device cycle will not begin
   the next capture until the driver reports the finger **gone**, and the
   window never said so — it said *"Same finger, same part of the pad, once
   more."* Fixed by `_cycle_hint()` (§20j).

⚠ **Both were already in place for the 10:19 run that got 0 out of 8**
(§20k). The 6/6 run at 10:30 was the *same binary*, plus §20k's restart loop —
which never fired, because that run had **no protocol errors at all**. So the
code cannot be credited with the 6/6: what differed between 0/8 and 6/6 is
**not recorded**. Candidates, none distinguishable from here: the user's own
coverage and dwell converging, finger condition, or the device's state after
that morning's fifth `fprintd` restart. The corrected instructions are
necessary — the old ones asked for an impossible motion — but they have not
been shown sufficient.

**The reproducibility test is enrolling a second finger.** If that also reaches
6/6, the instructions were the fix. If it takes another twenty attempts, the
remaining variable is the pad's minutiae yield and the honest status is
"enrols, unreliably".

The §20k restart loop earns its place regardless: before it, every protocol
error ended the run and cost another polkit password, which is what made the
earlier sessions unworkable.

#### The inference that cost three sessions

§20g argued:

> **Not one `too-short` or `too-fast` in the lot.** These are
> `FP_DEVICE_ERROR_PROTO` — driver and sensor disagreeing about the protocol.
> No gesture changes that.

The premise was true and the conclusion did not follow. On an **area pad driven
as a swipe sensor**, a gesture failure does not surface as `too-short` or
`too-fast` — those come from a driver that is tracking a swipe it can measure.
It surfaces as frames with no displacement, nothing to assemble, and
**`No minutiae found` → `enroll-retry-scan`**. That line was in the journal the
whole time, in §20g's own quoted output, filed under the driver story.

Worse, the conclusion was promoted to a rule. `../CLAUDE.md` carried *"This is not
a technique problem, so don't 'fix' it with UI copy telling the user to swipe
differently"* — which is precisely the fix, and the instruction file blocked it
for three sessions.

#### Three rules that generalise

1. **A driver-reported property is evidence about the driver, not about the
   hardware.** `scan-type` came from the same code that could not drive the
   sensor. Check the chassis.
2. **`No minutiae found` is a geometry result.** Image captured, too little
   ridge detail to use. Sensor size, coverage and motion reach it; it is not a
   verdict about the bus.
3. **`FP_DEVICE_ERROR_PROTO` here is intermittent, not blocking.** It still
   appears. The successful run had none of it. "Appears in the journal" and
   "prevents the operation" are different claims and §20g merged them.

The gesture/driver/fatal classification in `_handle_result` was **right** and
stays. What was wrong were two of its inputs.

#### Downstream, now that a finger exists

* **`pam_fprintd` in `/etc/pam.d/sudo` is live.** `chwd` put
  `auth sufficient pam_fprintd.so` there long ago (§20a) and it starts working
  the moment a print exists — which was 10:31. ⚠ Its prompt is built from the
  driver's `scan-type`, not from the panel's `gesture`, so `sudo` now says
  *"Swipe your right index finger across ElanTech Fingerprint Sensor"*. **Touch
  the pad.** It is `sufficient`, so pressing Enter falls through to the
  password and there is no lockout path. The panel still never edits that file.
* **The hyprlock switch was enabled 2026-11-01 10:31:40**, right after the
  enrolment, and the live `hyprlock.conf` now carries the managed block with
  `ready_message = (Touch finger to unlock)` — the corrected verb. As §20d
  warns, that write lands on the **live** file only, so
  `configs/hypr/hyprlock.conf` had drifted; it was pulled back into the mirror
  the same day. ⚠ Matching itself is **unmeasured**: a protocol error during
  *verify* is a real possibility and no `fprintd-verify` has been run. hyprlock
  keeps password auth on regardless, so there is no lockout path either way.

#### Still true from §20g / §20j

USB autosuspend remains ruled out (don't add the udev rule). The invalid
`AWAIT_FINGER_ON → AWAIT_FINGER_OFF` transition is still a real `elan` bug.
`fp-debug.sh` is still the right harness if the protocol errors ever bite on
verify.

#### Panel change

The enrolment window's pre-emptive banner — *"Known driver problem on
04f3:0c4f … Enrollment may fail with a driver fault no gesture can fix"* — was
**removed**, along with the `ELAN_PROTOCOL_MISMATCH` set that fed it. It stated
as fact the thing this section disproves, and it told the user nothing they
could act on. Per-result reporting in `_handle_result` already says whose
problem each attempt was.

### 20m. Verify measured for the first time — it fails 4/4 — 2026-11-01 (fifth pass)

§20l closed with matching **unmeasured** and `fprintd-verify` unrun. It was run
four times, 11:22–11:30:

| run | result | journal during the run |
|---|---|---|
| 1 | `verify-no-match (done)` | — |
| 2 | `verify-retry-scan` → `verify-disconnected (done)` | `Device reported an error during verify: … protocol error` |
| 3 | `verify-no-match (done)` | `Failed to detect minutiae: No minutiae found` ×1 |
| 4 | `verify-retry-scan` → `verify-disconnected (done)` | `No minutiae found` ×4, protocol error ×3 |

**Zero matches.** The enrolled `right-index-finger` template never matched the
finger it was enrolled from. Four findings, each with its evidence:

1. **`verify-disconnected` is not a disconnect.** The sensor enumerated **once**
   this boot, `usb 3-9` at 11:21:50, and there is **no** disconnect, re-enumerate,
   reset or `xhci` error afterwards — including across the 11:22:25→11:22:34
   s2idle. Every `verify-disconnected` has a matching `FP_DEVICE_ERROR_PROTO`
   line at the same second. fprintd translates a protocol error during *verify*
   into `verify-disconnected` and ends the session. So this is CLAUDE.md rule (3)
   — intermittent, not blocking — surfacing under a name that invites the wrong
   fix. ⚠ **Do not chase USB power management for this.** Autosuspend was already
   ruled out in §20g and the device never left the bus.

2. **⚠ The error asymmetry between enrol and verify is the thing that makes the
   feature unreliable.** At enrolment §20k's restart loop absorbs a protocol
   error (`EnrollStop` + `EnrollStart`, claim kept). At verify there is no such
   loop: hyprlock maps an unrecognised error to **"Fingerprint auth disabled
   (unknown error)"** and stops offering the fingerprint for the rest of that
   lock. **2 of 4 runs** hit it. Even once matching works, roughly every other
   lock would fall back to the password.

3. **`No minutiae found` dominates, and it is still a capture result.** Rule (2)
   again: geometry, not a driver verdict. Verify is **strictly harder than
   enrol** — enrolment stitches 6 accepted captures into the template, verify
   gets **one** capture per touch with no stitching — so the placement that
   passed 6/6 at 10:30 is not sufficient here. This is the small-sensor limit of
   §20k (~1 cm pad) showing up on the read side.

4. **No driver swap is available — the door is closed.** `elanmoc`
   (match-on-chip, which would move matching into the sensor and remove the
   minutiae problem entirely) **is** present in `libfprint 1.94.100`, but
   `04f3:0c4f` is in the **`elan`** image-driver id table, and the live device
   reports `has_storage = False` → host-side NBIS matching. Confirmed by probe,
   not inferred.

#### The stage count: 6 is right, 5 was a bad read

A probe via `FPrint.Context().enumerate()` returned `get_nr_enroll_stages() = 5`,
against the **6** recorded in §20e and the 6/6 of §20l. fprintd's own D-Bus
property is authoritative and says **6**:

```
gdbus call --system --dest net.reactivated.Fprint \
  --object-path /net/reactivated/Fprint/Device/0 \
  --method org.freedesktop.DBus.Properties.GetAll net.reactivated.Fprint.Device
# → {'num-enroll-stages': <6>, 'scan-type': <'swipe'>, …}
```

The 5 came from reading the property on a device that was only **enumerated,
never opened** — libfprint's image-device base class finalises the stage count at
open. **Don't "correct" the 6.** This is CLAUDE.md rule (1) in a new costume: a
property read in the wrong device state is evidence about the read, not about the
hardware. The panel is safe here — it reads `num-enroll-stages` over D-Bus from
fprintd, which opens the device.

#### Next step: a second finger, additively

The reproducibility test CLAUDE.md already asks for is now also the fix to try,
and it costs nothing to attempt:

```bash
fprintd-enroll -f left-index-finger     # or the panel's Fingerprint group
fprintd-verify                          # no -f → verifies against ANY enrolled finger
```

⚠ **Do not delete `right-index-finger` to do this.** It is the artifact of three
failed sessions, enrolling is additive, and `fprintd-verify` with no `-f` tries
every enrolled template — so a second finger puts two templates in play while
losing nothing. Only if the new finger verifies reliably **and** the old one
never does is re-enrolling the old one worth the risk, and that is the user's
call, not an automated step.

Technique, which verify demands more of than enrolment did: the **same** region
of the pad each time, flat, centred, held still until the message changes, lifted
fully between attempts. Touch — never swipe (§20j).

If the protocol errors are what persists after a second finger, the harness is
`triton-panel/fp-debug.sh`, kept for exactly this case since §20l.

### 20n. The question §20m could not answer, and the `verify` mode — 2026-11-01

§20m's recommendation — *enrol a second finger* — was challenged on the obvious
grounds: **the correct finger was already being used.** That objection is right,
and the recommendation was mis-framed. Enrolling a *different* finger is a
**control experiment**, not a fix: it cannot improve matching for the finger you
actually want to unlock with. §20m presented it as the next step without saying
so.

What §20m actually established is that two causes remain indistinguishable from
the summary journal:

| | hypothesis | its fix |
|---|---|---|
| **H1** | the stored template is marginal — 6 accepted captures with 2 rejections, on a ~1 cm pad | re-enrol (**destructive**) |
| **H2** | the *verify* captures are too thin — one capture per touch, no stitching, under the NBIS floor | none exists |

The asymmetry matters: H1's fix destroys the artifact of three sessions, and
H2's fix does not exist. **So neither may be acted on before measuring**, and
the only thing that separates them is the per-capture debug output.

#### `fp-debug.sh verify`

`fp-debug.sh` already did all the setup — the `G_MESSAGES_DEBUG=all` drop-in
under `/run`, the journal capture, the tty/polkit-agent guard, the
"panel must not hold the claim" guard, and a cleanup that removes the drop-in on
every exit path. It was **enrol-only**. It gained a `verify` mode that reuses all
of it and runs `fprintd-verify` instead. It enrols nothing, deletes nothing and
writes nothing, so it is safe to re-run freely. The read-out table is in the
script's own banner: a minutiae **count** well under the template's → H2;
healthy counts with `verify-no-match` → H1; protocol errors and little else →
neither, run `rebind` first.

⚠ If the `elan` driver prints no per-capture count, **record that** instead of
inferring one — the script's summary says so explicitly. This is the §20g
failure mode: an absent log line is not a measurement.

#### `sudo` now stalls on the reader — handled, not worked around

`pam_fprintd` in `/etc/pam.d/sudo` went live the moment a print existed (§20l),
so **every `sudo` now waits on the reader first**, prompting *"Swipe your right
index finger"* — the prompt is built from the driver's `scan-type`, so it names
a gesture the pad cannot perform — and blocking ~30 s before falling through to
the password. This was hit for real while inspecting `/var/lib/fprint`: the
command returned `Verification timed out`. `fp-debug.sh` makes six `sudo` calls,
so it now runs **one `sudo -v` up front** to cache the ticket, which also keeps
PAM from competing with the run for the device claim. `pam_fprintd` is
`sufficient`, so Enter falls through to the password. **Don't edit PAM for
this.**

#### The non-destructive fresh template: same finger, second slot

The finger *name* is only a **label**. fprintd accepts a fixed enum of slot
names (confirmed against `/usr/lib/fprintd`), and **nothing ties
`left-index-finger` to a physically left index finger.** So a fresh template of
the **correct** finger can be enrolled into a second slot:

```bash
fprintd-enroll -f left-index-finger    # enrolled with the RIGHT index
fprintd-verify                         # no -f -> tries EVERY enrolled template
```

That is what answers H1 without touching `right-index-finger` — and it is the
reproducibility test §20l asked for, finally pointed at something useful.
⚠ **Still do not delete `right-index-finger`.** Only if the debug run shows
healthy captures *and* a fresh template matches is the old one the proven
culprit, and removing it is the user's call at that point.

#### Status

Both steps are **unrun** — each needs a finger at the sensor. Order: measure
(`./fp-debug.sh verify`) before enrolling anything, because the measurement
decides whether the second step is worth the time at all.

---

### 20o. Measure matching before touching the print: the calibration phase — ✅ APPLIED 2026-11-01 (sixth pass)

§20n left two steps, both needing a finger at the sensor, and §20m's
recommendation had been mis-framed. The shape that came out of that: **the
panel should not treat "enrolled" as the goal.** A 6/6 enrolment whose template
matches nothing is exactly what happened on 2026-11-01, and *every number the
enrolment window showed read as success* — because they were all enrolment
signals, and enrolment passing says almost nothing about matching.

So `EnrollWindow` gained a **calibration phase** that runs first.

#### What it does

`VerifyStart("any")` in a loop, classifying each attempt by the one
distinction that matters:

| bucket | results | what it means |
|---|---|---|
| **scored** | `verify-match`, `verify-no-match` | the sensor produced an image **and** libfprint extracted minutiae, so the matcher ran and returned a number |
| **rejected** | `verify-retry-scan`, `-swipe-too-short`, `-too-fast`, `-finger-not-centered`, `-remove-and-retry` | the capture never reached the matcher |
| **driver** | `verify-disconnected`, `verify-unknown-error` | the device faulted; says nothing about the hand |

Why that split is the useful one: **a high scored rate with `no-match` every
time is evidence about the template (H1), not about the placement** — the hand
is delivering readable ridges and the stored print is what cannot be matched.
That is the one case where re-enrolling is worth doing. A low scored rate is
placement or the small-sensor ceiling (H2), and re-enrolling from captures that
thin would just build another unmatchable template. The window says so in as
many words, and in that state it labels the button **"Enroll anyway"** rather
than recommending it.

Driver faults are deliberately **kept out of the rolling window**. Counting
them would drag the score down for something the user cannot act on — the same
conflation of "driver" with "gesture" that sent §20g chasing the wrong thing
for three sessions.

#### The gate

At least **10** attempts, and at least **8 of the last 10** scored. A *rolling*
window, not a cumulative total, so the score reflects the placement the user
has converged on instead of being dragged down forever by the fumbling at the
start — finding a repeatable placement and then enrolling from it is the whole
point. ~~Then the enrol phase opens with *"use the SAME placement that passed
calibration on every stage"*, because a template stitched from six different
parts of the finger is precisely what one verify capture cannot match.~~

⚠ **That sentence was wrong — corrected the same day in §20q.** An enrolled
NBIS print is a `GPtrArray` of per-stage minutiae sets and `fpi_print_bz3_match`
succeeds on the **first** stored set to clear the threshold: one-of-N, not a
composite. Six identical placements therefore waste five of the six slots, and
six *different* regions are what make the template matchable. The error was
conflating the `elan` driver's frame stitching **within** a capture (§20j) with
how libfprint stores stages **across** an enrolment. The enrol phase now names
a different region after every stage. Kept here rather than deleted, because
the reasoning that produced it is the thing not to repeat.

**Not configurable.** A knob here would invite tuning the threshold until it
passes, which is the one thing that would make the measurement worthless.

#### ⚠ What "scored" is NOT

It is an **inference** about libfprint's flow — extraction fails → retry;
extraction succeeds → bozorth3 → match/no-match. It is consistent with the
2026-11-01 journal (one `No minutiae found` followed by a `verify-no-match` in
the same run) but it is **not** confirmed against a per-capture minutiae count;
`./fp-debug.sh verify` is the only thing that would print one. So the UI says
**"scored", never "good"**, and the card states what the number is and is not
evidence of. If a debug run ever contradicts it, the claim is already labelled
as the inference it is and nothing has to be retracted. This is §20g in
miniature: **a missing log line is not a measurement.**

#### Safety properties

* **Calibration writes nothing.** Verify neither enrols nor deletes, so it is
  safe to repeat indefinitely. The card says this.
* **The occupied-slot warning.** Enrolling into a slot that already holds a
  print **overwrites** it. The window now says so up front when the chosen
  finger is already enrolled, and points out that *the slot name is only a
  label* — so a free slot can hold the same physical finger, which is the
  non-destructive way to build a fresh template (§20n). The panel still never
  deletes anything on its own.
* **The verify loop honours fprintd's state machine.** `VerifyStop` is required
  before the next `VerifyStart` once a `VerifyStatus` has arrived with
  `done = True` — and **both** `verify-match` and `verify-no-match` are
  `done = True`. A retry is `done = False`, leaves the verify **open** with
  fprintd already waiting, and must **not** be cycled or the operation is
  thrown away mid-flight. That asymmetry is invisible from the UI and is
  exactly what a later edit breaks silently, so it is the first thing the
  regression test asserts.
* **No restart ceiling, but no spin either.** A calibration run is a deliberate
  loop the user ends, so it has no cap — except `MAX_CAL_DRY = 4` consecutive
  driver faults *with no finger contact between them*, which is a wedged
  endpoint rather than a placement problem and points at `fp-debug.sh rebind`.
* **`VerifyFingerSelected` is not an outcome.** fprintd emits it before the
  result to name the template it is about to score against; it is logged as an
  info row and never counted as an attempt.
* **One claim path.** Both phases claim identically, so the
  close-while-polkit-is-still-up release invariant is implemented once.
  `_stop()` now stops the operation the claim was actually being used for
  (`VerifyStop` vs `EnrollStop`) before releasing.

#### Verify — results 2026-11-01

| check | result |
|---|---|
| `test-enroll.py` | **81 assertions, ALL PASS** (was 40) |
| the loop invariant | `done=False` → no D-Bus call; `done=True` → exactly `["VerifyStop", "VerifyStart"]` |
| `no-match` bucketing | counts as **scored**, marked in blue, `cal_matched` stays 0 |
| driver fault bucketing | kept out of `cal_log`, still counted as an attempt, loop continues |
| dry-fault cap | stops at 4 and names `rebind`; contact between faults resets it |
| gate, rolling | `[True]*8` → not ready (under the floor); `[True]*8+[False]*2` → ready; `[False]*20+[True]*10` → ready |
| widget construction | smoke-tested for both an occupied and a free slot |
| deployed | `install -Dm755 triton-panel/triton-panel ~/.local/bin/triton-panel` |

⚠ **A real sensor session is still unrun** — it needs a finger, so it is the
user's to do. Nothing above measures the hardware; it measures the panel.

⚠ **And one of the properties above is asserted, not observed.** The
`VerifyStop` → `VerifyStart` cycle on a **held claim** is checked against a
stub in `test-enroll.py`; that fprintd *accepts* it on a verify has **not**
been seen. The only evidence that a Stop/Start on a held claim works at all is
§20k's enrol restart loop (`EnrollStop` + `EnrollStart`), and that was
*enrolment*. The four `fprintd-verify` runs of §20m each did exactly one
`VerifyStart` → terminal result → exit, so the loop itself has never touched
the daemon. The first real-finger calibration run is what closes that gap —
if the cycle is refused, the symptom will be a `VerifyStart failed` row
pointing at `fp-debug.sh rebind`, and the fix is to re-`Claim` per attempt
rather than keep the claim.

#### A bug the smoke test caught

`_calibration_card()` called `_update_cal()`, which paints the buttons — but
the cards are built **before** the bottom bar, so `start_button` did not exist
yet and construction crashed. The initial paint moved to the end of `_build()`,
and `_update_cal()` now reads both buttons through `getattr` so a future
reorder degrades instead of crashing. Worth recording because it was invisible
to `test-enroll.py`: the stubs hand it buttons that always exist, which is
precisely the thing the real constructor does not.

#### ⚠ Second defect, same day: it was measuring the panel's own loop

See §20r. Until that fix, every `done = True` re-armed the verify immediately,
so a finger left **resting** on the pad was re-captured every 1–3 s and each
garbage image appended another reject to the rolling window. The gate then
reported "Captures are too thin" about a placement the user had made **once**.
This section's claim that calibration measures *placement* was false whenever
the finger stayed down. The verify is now re-armed on the **lift**.

#### Defect in this section's own work, fixed same day: the Stages card went inert

Reported immediately: *"Stages ya no hace nada."* Correct, and it was caused by
adding the calibration card **without deciding who owned the shared status
labels**. `status_label`, `hint_label` and `tally_label` had always lived inside
the card titled **Stages**, where they read as part of it — but they were being
used as the window's *global* status surface. A second phase exposed that:

| symptom | cause |
|---|---|
| stage pills and count frozen at `0 / 6` through a whole calibration | correct — calibration captures no stages — but nothing *said* so, so the card read as broken |
| a calibration retry message (*"the capture had no readable ridges…"*) rendering under a heading about enrolment stages | `hint_label` was shared but visually owned by the Stages card |
| the attempts tally empty during calibration | `tally_label` renders `self.tally`, the **enrolment** tally; `cal_tally` was collected from the first version and **rendered nowhere** |
| the idle hint saying *"Press Start"* | there is no Start button any more — calibration split it into *Calibrate placement* and *Enroll* |

Fixed by separating the surfaces:

* **`_status_box()`** — `status_label` + `hint_label` moved out into the
  window's own headline, above the contact strip, owned by whichever phase is
  running. No longer inside any card.
* **`stages_note`** — a new line in the Stages card that says why the pills are
  not moving: *"Not in use — calibration measures matching and captures no
  stages"* while calibrating, *"One pill per accepted capture"* while idle, and
  **nothing** while enrolling or once stages have real history. The card was
  deliberately **not hidden**: a card that appears and vanishes makes the window
  jump, and it jumps precisely when the user is looking at their hand.
* **`cal_tally_label`** — the calibration card renders `cal_tally` at last:
  `4 attempts · 3x Scored, did not match · 1x No usable detail`.
* **`_set_idle_text`** now names the buttons that exist.
* `count_label` shows `— / 6` rather than `0 / 6` when no enrolment is running,
  so a dash means "not applicable" and a zero means "started, none accepted".

`_build` order matters and is commented: the status box and cards are built
first, then the buttons, then `_update_cal()` (needs the buttons) and
`_set_idle_text()` (needs `stages_note`). This is the third instance of the same
class of bug — a paint method running before the widgets it paints exist — and
the first two were caught only by a real construction smoke test, never by the
stubs.

Verification: `test-enroll.py` **115 assertions, all passing**, including a
direct regression for what was reported — *the calibration tally is rendered,
not just collected* — and that `stages_note` is correct in all four phase
states. A four-phase label dump (window opened → mid-calibration → calibrated →
enrolling) confirmed every surface in the live widget tree, which is the check
the stubs cannot do.

#### How to use it

```bash
triton-panel          # Fingerprint group -> pick the finger -> Enroll
```

1. **Calibrate placement** — touch the pad as if unlocking, 10+ times. Watch
   the scored rate.
2. If it says **"Matching works"**, stop: the print is usable and nothing needs
   re-enrolling.
3. If it says **"Calibrated — and nothing matched"**, the template is the
   suspect. Enrol **into a free slot** (the slot name is only a label — use the
   right index in, say, the Left index slot) with the placement that just
   passed, then calibrate again: `VerifyStart("any")` scores against both
   prints, so a match proves the new template fixed it.
4. Only then, if the fresh print works and the old one never does, is deleting
   `right-index-finger` justified — and that stays a deliberate action in the
   main Fingerprint group.
5. If it says **"Captures are too thin"**, do **not** enrol. Run
   `./fp-debug.sh verify` for the underlying counts.


### 20p. A Test button for a stored print — ✅ APPLIED 2026-11-01 (seventh pass)

The Fingerprint group could enrol, delete and switch hyprlock on, and it could
not answer the one question §20m turned into the important one: **does a stored
print actually match?** "Enrolled" and "works" are genuinely different states
here — §20l proved a print could be stored, §20m found it matched nothing — and
the group displayed only the first.

**Test a stored print** is a new row with a one-shot verify: `Claim` →
`VerifyStart("any")` → one `VerifyStatus` → report → `VerifyStop` → `Release`.
The verdict lands in the row's own subtitle.

It is deliberately **not** the calibration loop of §20o. Calibration measures
*placement* over many attempts to decide whether re-enrolling is worth it; this
answers *"does the print I have work?"* once, and it is the thing to press
before going anywhere near the enrolment window.

`"any"` rather than a finger name, which is what `fprintd-verify` with no `-f`
does: it scores against every enrolled template and `VerifyFingerSelected`
names whichever one fprintd picked, so a match reports *which* print worked.
⚠ What **hyprlock** passes is *not* established. Its binary does contain the
string `any` — visible only with `strings -n 3`, since three characters is
under the default minimum — but a three-character string turns up in a binary
for many reasons, and that is weak evidence, not confirmation. What can
honestly be said is that this mirrors **fprintd's own client**.

#### The hazard is the claim, not the verdict

fprintd grants **one claim at a time**, and a claim left behind leaves the next
`Super+L` with no fingerprint until fprintd times it out — the invariant
`EnrollWindow` was already built around. A verify that nobody ever touches
**does not end on its own**, so this path releases on *every* exit:

| exit | released by |
|---|---|
| a terminal `VerifyStatus` | `_test_end` from the result branch |
| **Cancel** (the button becomes Cancel while running) | `_on_fp_test` |
| Cancel pressed while polkit's dialog is still up | `_on_test_claimed` — the claim is granted server-side anyway, so it is released there; when Cancel ran there was nothing to release yet |
| the panel window closing | `_on_close`, next to the existing enrolment-window release |
| **nobody touches the sensor** | `TEST_TIMEOUT_MS = 30000` |

The hard timeout is a correctness requirement, not a nicety: without it a
forgotten test silently disables fingerprint unlock until fprintd gives up.

A retry result (`done = False`) must **not** release — fprintd keeps the verify
open and is already waiting for another finger — so those update the subtitle
and return. Same `done` asymmetry as §20o, enforced in a second place.

#### What it says

* **match** → `✓ Matched — Right index. This print works.` plus a toast.
* **no match** → `✗ No match.` and then the §20o framing: the sensor got
  readable ridges and the matcher scored them below the threshold, **so this
  points at the stored print, not your finger**, and calibration is where to
  measure it properly.
* **driver fault** → the `VERIFY_RESULTS` hint and `./fp-debug.sh rebind`. No
  "not your finger" appended: every driver hint already says whose problem it
  is, and a second copy read as the panel protesting too much.
* The row is **insensitive with nothing enrolled** ("Enroll a finger first"),
  since `VerifyStart` would fail with `NoEnrolledPrints`.
* `_fp_busy()` now covers the test control, so the enrolment window and a test
  cannot both reach for the claim.
* ⚠ `_refresh_fingerprint` is **not reachable while a test holds the claim**
  (its callers are startup, `_enroll_finished` and `_on_fp_delete`, and the
  latter two are behind disabled buttons), which is why its `elif not
  self._testing` guard is enough to protect the in-progress subtitle. If a
  future caller adds a path that *is* reachable mid-test, check first whether
  `ListEnrolledFingers` is allowed against a claim held by the same caller —
  that is undocumented here, and §20e only established that it raises when
  nothing is enrolled.

#### Verify — results 2026-11-01

| check | result |
|---|---|
| `test-enroll.py` | **107 assertions, ALL PASS** (81 before this, 40 originally) |
| retry (`done=False`) | **no** D-Bus call, still testing, subtitle updated |
| match | `["VerifyStop", "Release"]`, button back to "Test", names the finger, toast |
| no-match | released; subtitle says "stored print, not your finger" |
| driver fault | released; points at `rebind`; does not blame the hand |
| timeout | released, timer cleared |
| Cancel | released; `_test_end` twice is harmless |
| claim granted after Cancel | `["Release"]` only — never subscribed, never used |
| failing `VerifyStart` | released, not left in the testing state |
| widget construction | group smoke-tested against the live reader; `_fp_busy` locks the row |

⚠ **Still unrun against a real finger** — every check above is the panel, not
the sensor. The first press of **Test** is also the first time the live
`VerifyStart` path in this panel meets the daemon.


### 20q. One-of-N, not a composite: why §20o's enrolment advice was backwards — ✅ APPLIED 2026-11-01 (eighth pass)

Enrolment was still hard — *"obtengo pocas mediciones correctas del sensor"* —
so other projects were read for ideas. The most useful finding was not in any
of them: it was in libfprint's own print handling, and it **reverses** what
§20o told the user to do with their hand.

#### The finding

An enrolled NBIS print is **not one merged template**. It is a `GPtrArray` of
per-stage minutiae sets — `FpPrint` exposes it as **`fpi-prints`**, plural
(confirmed by introspection on this machine), and `fpi_print_add_print` appends
one entry per call:

```c
g_ptr_array_add (print->prints, g_memdup2 (add->prints->pdata[0], sizeof (struct xyt_struct)));
```

And `fpi_print_bz3_match` loops over **every** stored entry, returning on the
**first** one that clears the threshold:

```c
for (i = 0; i < template->prints->len; i++)
    score = bozorth_to_gallery (probe_len, pstruct, gstruct);
    if (score >= bz3_threshold)
      return FPI_MATCH_SUCCESS;
```

**That is a one-of-N match.** The bz3 threshold defaults to **40** and is
runtime-settable by a driver through `fpi_image_device_set_bz3_threshold()`
(the symbol is present in the installed `libfprint-2.so.2`).

#### What follows, and the mistake it exposes

| | |
|---|---|
| six **identical** placements | six near-duplicate candidates — **five of the six slots wasted** |
| six **different** regions | six independent chances for one verify capture to overlap one of them |

On a ~1 cm pad, where no single capture can hold much of the finger, that is
the difference between a template that can be matched and one that cannot. It
is also why phone enrolment asks you to shift the finger and then do the edges.

⚠ **§20o told the user the opposite** — *"Use the SAME placement that passed
calibration on every stage… A template stitched from six different parts of
the finger is what a single verify capture cannot match."* The second sentence
is false, and the reason it was written is worth keeping: it **conflated two
different things** —

* the `elan` driver stitching **frames** by displacement **within one capture**
  (§20j's finding — real), with
* how libfprint stores stages **across an enrolment** (not stitching at all).

The first is a property of this driver. The second is a property of libfprint,
and nothing about it merges the stages. Same family of error as §20g: a true
fact about one layer carried into a conclusion about another.

The **calibration** advice stays correct — it measures one placement's
readability. What changed is what you do with that placement afterwards:
**enrol around it, not at it six times.**

#### Applied in the panel

* `ENROLL_REGIONS` — six regions: centre, higher, lower, rolled left, rolled
  right, centre held longer.
* `_stage_hint()` replaces `_cycle_hint()` in the accepted-stage branch, so
  after every stage the window names **the next region** and says why
  (*"each stage is stored as its own candidate and unlocking succeeds if ANY
  one of them matches"*). No per-stage libfprint hook is needed — `self.passed`
  is enough, which §20j had already established is all any client gets.
* `_region_for()` indexes **modulo** the list and stops at the device's own
  stage count, so a reader reporting 5 or 8 stages instead of this one's 6
  still gets a region for each and never invents a seventh.
* The "SAME placement" copy in `_begin_enroll`, and *"keep using exactly this
  placement for every stage"* in the calibration card, are both replaced.

`test-enroll.py`: **130 assertions, all passing** — including that each stage
names a *different* next region, that the last stage falls back to the plain
cycle hint instead of inventing a stage 7, and the `stages=5` / `stages=8`
off-by-one cases.

#### Ideas from other projects, ranked by how well they are verified

⚠ Read the verification column before acting on any of these. They are listed
because they were asked for, not because they are established.

| idea | where from | verified how | relevance here |
|---|---|---|---|
| **bz3 threshold is 40 and a driver can lower it** | libfprint reference manual + `fpi_image_device_set_bz3_threshold` in the local `.so` | **Confirmed.** Default documented upstream; symbol present locally | Our `verify-no-match` means *scored below 40*. Lowering it is the most direct lever on matching — at a **false-accept cost**, and it needs a patched libfprint (an `fpi_` internal, no env var, no fprintd knob) |
| **`FP_SCAN_TYPE_PRESS` instead of SWIPE for elan** | [FCsab/Elan-04f3-0c6e fix](https://github.com/FCsab/Elan-04f3-0c6e-fingerprint-reader-fix) README; an [openSUSE `libfprint_elan.patch`](https://build.opensuse.org/projects/home:abuenameh/packages/libfprint/files/libfprint_elan.patch?expand=0) | **Two independent sources claim it; neither diff was read** (the README shows no code, the openSUSE file returned 403) | Exactly our confirmed physical diagnosis (§20j). Would remove the motion-assembly path a still press cannot feed — the direct cause of `No minutiae found` |
| **Image-based presence detection** — infer finger presence from image data instead of the hardware status byte | same 0c6e fork's README | **One README, code not read** | Would address §20j's *invalid* `AWAIT_FINGER_ON → AWAIT_FINGER_OFF` transition and the runs that stall with no error at all |
| **SIFT matcher replacing bozorth3** | same 0c6e fork's README | **One README, code not read** | The most interesting idea here: image-feature matching does not need a minutiae count, which is §20k's floor on a ~1 cm pad |
| **12 enrol presses instead of 6** | same 0c6e fork's README | **One README, code not read** | Now *motivated* rather than arbitrary: with one-of-N matching, more stages means more independent candidates |
| **Frame-assembly overflow fix** | [pbogut/libfprint](https://github.com/pbogut/libfprint) | Repo description only | We do see bozorth3 `qq[] overflow` warning strings in the local library |
| **`ELAN_NOT_ROTATED` quirk** | [iafilatov/libfprint `elan.h`](https://github.com/iafilatov/libfprint/blob/elan-github-msg/libfprint/drivers/elan.h) | Header read, but its id table is **0x0c01–0x0c33** and ours is **0x0c4f** | A **hypothesis only**: if frames are rotated on a device that should not be, assembly is garbage. What upstream does for 0c4f is unknown |
| **Enrol on Windows, verify on Linux** works for a sibling | [Elan-Fingerprint-0c4c-PoC issue](https://github.com/depau/Elan-Fingerprint-0c4c-PoC/issues/4) | A single issue comment | Weak, but it points the same way as everything above: the *enrolment data* is the weak link, not the matching |
| Same `No minutiae found` on sibling Elan `04f3:0c4d` | [Manjaro forum thread](https://forum.manjaro.org/t/fingerprint-enrollment-fails-on-manjaro-gnome-with-04f3-0c4d-sensor/169884) | Thread shows **no resolution** | Confirms the symptom is family-wide, offers no fix |

Nothing was found that targets **`04f3:0c4f`** specifically, and **no
match-on-chip driver covers it** (§20m).

#### ⚠ Everything in Layer B needs a patched libfprint — not started

The last six rows all mean *rebuild libfprint with a patch*. That was **not
done**, and it should not be done casually:

* `libfprint` is behind `pam_fprintd` in `/etc/pam.d/sudo` **and** hyprlock's
  unlock path. A broken build degrades both. (`pam_fprintd` is `sufficient`, so
  the password still works — that is the only reason this is recoverable.)
* It is a system package, so a `pacman -Syu` silently reverts the patch and the
  behaviour changes under you. Pinning it in `IgnorePkg` then freezes security
  updates to it.
* Rollback path to name **before** starting: the cached package,
  `sudo pacman -U /var/cache/pacman/pkg/libfprint-1.94.100-1.1-x86_64.pkg.tar.zst`.

If it is attempted, the order that matches the evidence is: **(1)** scan type
to press — it is the one change our own hardware diagnosis predicts; **(2)**
lower the bz3 threshold, measurable immediately with the panel's Test button;
**(3)** the 0c6e fork's presence detection and SIFT matcher, which are the
largest change and the least verified. Measure with `./fp-debug.sh verify`
between each, and the Test button after each.

#### Free thing to do first

The per-stage coverage change above costs nothing and is already deployed.
**Re-enrol into a free slot with it** (§20n: the slot name is only a label, so
a free slot can hold the right index finger) and press **Test**. If one-of-N
coverage is what was missing, that is where it shows up — and it needs no
patched library.


### 20r. One press is one measurement — ✅ APPLIED 2026-11-01 (ninth pass)

Reported: *"sale mucho el mensaje captures are too thin, **y yo no retiro el
dedo**."* That second clause is the whole diagnosis. The panel was reporting a
dozen failed measurements from a finger that had been placed **once**.

#### The evidence

`journalctl -u fprintd`, the user's own calibration session — **44 seconds** of
this, alternating every 1–3 s:

```
13:26:52  Failed to detect minutiae: No minutiae found
13:26:53  Device reported an error during verify: … protocol error
13:26:55  Failed to detect minutiae: No minutiae found
13:26:55  Device reported an error during verify: … protocol error
13:26:57  Failed to detect minutiae: No minutiae found
13:26:57  Device reported an error during verify: … protocol error
…                                        (through 13:27:36)
```

No human places a finger twenty times in forty-four seconds. The chain:

1. every `VerifyStatus` with `done = True` — which includes the protocol
   errors — called `_verify_cycle()` **immediately**;
2. each fresh `VerifyStart` captured the **same resting finger**;
3. a resting finger gives `elan`'s assembly nothing, so → `No minutiae found`
   → `verify-retry-scan` → **`cal_log.append(False)`**;
4. ten of those filled the rolling window in ~20 s, all from **one contact**;
5. the gate then announced **"Captures are too thin"** — about a placement the
   user had made once and never released.

So the message was not merely unhelpful, it was **measuring the panel's own
loop**. §20o's claim that calibration measures *placement* was false whenever
the finger stayed down.

⚠ `MAX_CAL_DRY` did not trip, and **was right not to**: it counts consecutive
driver faults *with no finger contact between them*, and here the finger was
very much there. It guards a wedged endpoint with nobody touching it. This was
the opposite case — a resting finger and a spinning loop — and nothing guarded
it.

#### ⚠ The fix below was itself a regression — see §20s

Making the **re-arm** wait for the lift left the device deaf for up to three
seconds after every result, and the user's touches were lost in the blackout
(*"a veces no detecta mi dedo"*). Counting and arming are different decisions
with opposite failure modes: a missed count is a wrong measurement, a missed
re-arm is a lost touch. The verify is now **always re-armed at once** and only
the *counting* waits on the lift. Read this section for the counting bug it
correctly identified; read §20s for how the arming was put back.

#### The fix: re-arm on the lift, not on `done`

Which is also what libfprint's own image-device cycle waits for
(`AWAIT_FINGER_OFF`, §20j). Three behaviours, by how much the reader can tell
us:

| condition | behaviour |
|---|---|
| `finger-present` supported **and** a lift seen since the last counted result | count it, re-arm |
| `finger-present` supported, **no** lift | **not counted** — `cal_log`, `cal_attempts` and the tally untouched, no `VerifyStart`. Status: *"Lift the finger clear"*, logged once per contact as `Same contact — not counted` |
| `finger-present` **never reported** by this reader | the old behaviour: count and re-arm at once, because there is no lift to gate on |

⚠ **The `CAL_REARM_MS = 3000` timer is not optional.** §20j recorded this
driver emitting an *invalid* `AWAIT_FINGER_ON → AWAIT_FINGER_OFF` transition —
it mishandles the lift — so `finger-present: false` may never arrive. Waiting
forever would hang calibration in silence, which is the §20j stall in a new
costume. The timer re-arms anyway, treats it as a lift for counting, and logs
**`Re-armed by timer`** so a later reader can tell *"the driver reported the
lift"* from *"we stopped waiting for it"*.

#### The trap that hid this

The lift is hooked on the real `finger-present → False` transition in
`_on_properties_changed`, **not** on `close_open_contact()`.
`close_open_contact()` is called artificially from the result handlers on
*every* result, whether or not the finger moved — which is exactly why a dozen
results from one unbroken press each came back with a **plausible-looking
contact duration**. The instrument that was supposed to make this visible was
reporting it as normal.

#### Also fixed: a journal line that reads like a claim leak and is not one

The same journal carried:

```
13:21:00  Authorization denied … to call method 'EnrollStop' … Device was not claimed before use
13:21:00  Authorization denied … to call method 'Release'    … Device was not claimed before use
```

A second `_stop()` — the one from close-request, after `_idle_buttons()` had
already reset `phase` — found `phase == "idle"`, guessed `EnrollStop`, and
asked fprintd to stop and release a device it no longer held. Harmless, every
error caught, but it is the single most misleading line this subsystem can
print: a claim leak is the one failure mode §20p is built around. Now `_stop`
records `_last_phase` and sets `_released`, so the second call is a **no-op**
and the line is gone.

#### Verify — results 2026-11-01

| check | result |
|---|---|
| `test-enroll.py` | **154 assertions, ALL PASS** (130 before) |
| a second result from the same press | `cal_log` untouched, `cal_attempts` stays 1, **no** `VerifyStart`, status says *Lift* |
| logging | `Same contact — not counted` appears **once per contact**, not once per result |
| the lift | re-arms `["VerifyStop", "VerifyStart"]` and the next press counts |
| `done` alone | does **not** re-arm; `_cal_rearm_pending` is set instead |
| reader with no `finger-present` | **not** gated — both results counted, re-armed at once |
| the timer | re-arms, counts again rather than hanging, and logs that it was the timer |
| `_stop` twice | second call is a no-op; no `Release` on an unclaimed device |

⚠ The existing tests had to be **rewritten to model the lift** — six of them
fired several `done = True` results in a row with no lift between, which was
only ever valid under the assumption this section removes. They now go through
a `press()` helper that lifts afterwards, like a hand does.


### 20s. §20r made the device deaf — counting and arming are different decisions — ✅ APPLIED 2026-11-01 (tenth pass)

Reported one minute after §20r shipped: *"ahora está peor: a veces no detecta
mi dedo."* Correct, and it was a regression I introduced.

#### The two journals, side by side

**Before §20r** (13:26:52 → 13:27:36, one continuous press):

```
13:26:52  No minutiae found
13:26:53  protocol error
13:26:55  No minutiae found        <- events every 1-3 s
13:26:55  protocol error
13:26:57  No minutiae found
13:26:57  protocol error
```

**After §20r** (13:34:31 → 13:35:16):

```
13:34:31  No minutiae found        <- the ONLY one in 45 seconds
13:34:32  protocol error
13:34:35  protocol error           <- +3 s
13:34:39  protocol error           <- +4 s
13:34:44  protocol error           <- +5 s
13:34:57  protocol error           <- +13 s
13:35:02  protocol error           <- +5 s
13:35:16  protocol error           <- +14 s
```

The gaps are `CAL_REARM_MS`, and the collapse from ~10 `No minutiae found` to
**one** is the finding: the device was not capturing, because no verify was
armed when the finger arrived. **The panel had gone deaf for up to three
seconds after every result**, and the user's touches fell into the blackout.

#### What was wrong in §20r, in one sentence

It coupled two decisions that have **opposite failure modes**:

| decision | cost of getting it wrong |
|---|---|
| miss a **count** | the measurement is wrong — recoverable, and visible in the tally |
| miss a **re-arm** | the touch is **lost**, and the hardware looks broken |

§20r made the re-arm wait on the lift to fix a counting bug. The verify is now
**always re-armed immediately**, for every bucket, and the lift gate decides
*only* whether a result is counted. `_arm_rearm`, `_on_rearm_timeout`,
`_cal_rearm_pending`, `_cancel_rearm` and `CAL_REARM_MS` are **deleted**, not
left dormant.

~~| `finger-present` supported, **no** lift | not counted … no `VerifyStart` |~~
⚠ That row of §20r's table is superseded: the suppression branch now still
re-arms before returning.

#### How "is this a new press?" is decided now

It cannot use the strip's open contact. `close_open_contact()` shuts it
**artificially on every result**, which is the same trap that made a dozen
results from one press each show a plausible duration — §20r named that trap
and then the first draft of this fix walked back into it. Two signals instead:

1. **Any `finger-present` transition since the last counted result.** A new
   press has to be *detected* to be captured at all, so the **ON** edge is the
   best available evidence that something moved — and it does not depend on the
   OFF edge, which §20j recorded this driver emitting *invalidly*.
2. **A wall-clock escape, `SAME_PRESS_S = 2.0`.** A result arriving later than
   that after the last counted one is counted regardless, so an unreliable
   `finger-present` can never suppress the measurement *forever*. It logs
   **`Counted without a reported lift`**, because "the driver reported a lift"
   and "we assumed one" must stay distinguishable.

A reader that never reports contact at all (`strip.supported is not True`) is
still not gated, as in §20r.

#### `fp-debug.sh presence` — the trace that should have come first

Two bugs in a row came from **guessing** at `finger-present`: §20r counted one
press as a dozen placements, and its fix made the device deaf. Neither would
have been written if this had existed, so it exists now:

```bash
./fp-debug.sh presence          # PASSES=4 by default
```

It needs **no sudo, no drop-in and no fprintd restart** — `finger-present`
arrives as an ordinary `PropertiesChanged` on the system bus, and skipping the
restart means the trace sees the daemon in the state the panel actually meets.
Every presence change is printed with a millisecond timestamp, interleaved with
each `VerifyStatus`, and the summary counts the two edges. Read it as:

| what the trace shows | conclusion |
|---|---|
| `true` with no matching `false` after a real lift | the driver does not report the lift; anything gated on it is unreliable (the §20j bug) |
| both edges, promptly | the signal is good and the panel can trust it |
| no `finger-present` lines at all | the reader never reports contact; the panel already detects this and stops gating |

⚠ **Still unrun.** It needs a finger. Until it is, `SAME_PRESS_S` is carrying
the design, and whether that is necessary or merely harmless is **not known**.

#### Verify — results 2026-11-01

| check | result |
|---|---|
| `test-enroll.py` | **154 assertions, ALL PASS** |
| suppression still re-arms | a same-press repeat ×3 → `cal_log` untouched **and** `["VerifyStop","VerifyStart"]` ×3 — never deaf |
| a terminal result | re-arms at once, no waiting |
| ON edge alone | counts the next result without any reported lift |
| the wall-clock escape | a fast repeat is suppressed; the same result 3 s later is counted and logged as assumed |
| reader with no `finger-present` | not gated |
| `_stop` twice | still a no-op |
| tests rewritten | §20r's two tests for the deleted waiting behaviour are **replaced**, not disabled |


#### Not changed

`hyprlock.conf` is untouched — the wiring is complete and correct, and §20e/§20l
already verified every link in it: the managed block is live and mirrored,
`hyprlock 0.9.6` carries `CFingerprint`/`VerifyStart` and the four
`auth:fingerprint:*` keys, `fprintd.service` runs,
`net.reactivated.fprint.device.verify` is `allow_active = yes` against an
`Active=yes` seat0 wayland session, and all three lock paths (`Super+L`,
hypridle `lock_cmd`, `loginctl lock-session`) launch hyprlock, which reads the
file at start. **Nothing in the configuration is missing.** What is missing is a
template that matches. Password auth stays on in hyprlock and `pam_fprintd` is
`sufficient` in `sudo`, so there is no lockout path in any of this.


### 20t. The three-minute clock: libfprint's thermal model is what breaks the locks — 2026-11-03 (eleventh pass)

Reported: *"hay brechas en la toma y detección de fingerprints."* Measured, and
the headline gap is a **clock**. It fires with **no finger anywhere near the
pad**, it is deterministic, and every earlier pass of this runbook missed it
because every earlier measurement session was **shorter than three minutes**.

#### A third error class, not in §20g–§20s

`journalctl -u fprintd` on 2026-11-03 carries a line no earlier pass ever
quoted — **seven times** before any of this was understood:

```
08:28:47  Device reported an error during verify: Device disabled to prevent overheating.
09:10:48  Device reported an error during verify: Device disabled to prevent overheating.
09:23:06  …  09:56:19  …  10:29:08  …  12:08:59  …  13:05:58
```

That string is libfprint's `FP_DEVICE_ERROR_TOO_HOT`. Look at the deltas
against the `fprintd.service` start that precedes each one: **+3:00, +3:00,
+3:00, +3:00, +3:01**. A sensor does not overheat on a schedule.

#### Measured here, with nothing touching the pad

`./fp-debug.sh thermal` (added by this section — it needs **no finger**, which
makes it the only instrument in this subsystem that can be run unattended):

| what | measured 2026-11-03 |
|---|---|
| armed at | 14:33:30, one `VerifyStart("any")`, left armed, pad untouched |
| `finger-present` | **never** reported — not once in the whole run |
| trip | **+180.1 s** → `VerifyStatus result='verify-disconnected' done=True` |
| journal at the same second | `Device disabled to prevent overheating.` |
| re-arm while hot | accepted by fprintd, then **refused in 0.0 s** — four probes, 20 s apart |
| usable again | still refused at **+180 s** after the trip, accepted at **+212 s** → cooldown is in **(180, 212] s**; the model predicts **205 s** |

So the reader is dead for **another ~3.5 minutes** after every three minutes
of being armed, and the refusal is **instant** — which is why it presents as
nothing happening rather than as an error. Under continuous arming the duty
cycle settles at roughly **2 min alive / 3.5 min dead**: from WARM the next
trip is `180 · ln(0.5/0.269) ≈ 111 s` away, not a fresh 180.

#### Why it is a model and not a thermometer

Primary source, `libfprint/fp-device-private.h` (upstream 1.94.10; the running
build is 1.94.100):

```c
#define TEMP_COLD_THRESH (0.26894142136999512075)   /* 1 / (e + 1) */
#define TEMP_WARM_HOT_THRESH (1.0 - TEMP_COLD_THRESH)
#define TEMP_HOT_WARM_THRESH (0.5)
#define DEFAULT_TEMP_HOT_SECONDS (3 * 60)
#define DEFAULT_TEMP_COLD_SECONDS (9 * 60)
```

There is no thermometer in this. `fpi_device_update_temp()` keeps an
exponential **estimate** of duty cycle: the ratio rises toward 1 with a time
constant of `temp_hot_seconds` while the device is in an operation and decays
with `temp_cold_seconds` while it is idle. The thresholds are chosen so that
`COLD → HOT` takes **exactly one time constant** — hence the 180 s measured
above, to within 0.1 s. Recovery is `HOT → WARM` at ratio 0.5, i.e.
`540 · ln(0.731/0.5) ≈ 205 s`, which is what the probe measured.

⚠ **An armed verify counts as "active" even though nothing is happening.**
Waiting for a finger is what burns the budget. That is the whole finding.

⚠ The match-on-chip press drivers in the tree (`goodixmoc`, `synaptics`,
`fpcmoc`, `elanmoc`) are **reported** to opt out with
`dev_class->temp_hot_seconds = -1`; `elan` is an `FpImageDevice` and does not.
That opt-out is **secondary source — the diffs were not read.** What is
first-hand is the trip above: on this machine, on this driver, the model is on.

#### fprintd throws the distinction away — `verify-disconnected` is a three-way ambiguity

`src/device.c`, `verify_result_to_name()` (fprintd 1.94.5, the installed
version):

| libfprint error | D-Bus result string |
|---|---|
| `FP_DEVICE_ERROR_PROTO` | `verify-disconnected` |
| `FP_DEVICE_ERROR_REMOVED` | `verify-disconnected` |
| **`FP_DEVICE_ERROR_TOO_HOT`** | `verify-disconnected` |
| anything else | `verify-unknown-error` |

The enrol side collapses the same three into `enroll-disconnected`.

So **no D-Bus client can tell a thermal lockout from a protocol error from a
real unplug** — not hyprlock, not this panel. Only `journalctl -u fprintd`
carries the difference, and fprintd 1.94.5 exposes **no** `temperature`
property on `net.reactivated.Fprint.Device` (introspected: `name`,
`num-enroll-stages`, `scan-type`, `finger-present`, `finger-needed`, and
nothing else).

⚠ §20m read `verify-disconnected` as *"the intermittent protocol error under a
misleading name"*. For that day's journal that was **correct** — every instance
there paired with an `FP_DEVICE_ERROR_PROTO` line at the same second. It is now
**incomplete**: the same string has a second, deterministic cause, and the rule
is *read the journal line, never the D-Bus string.*

#### What it does to hyprlock — this is the reported symptom, in full

hyprlock arms **one** verify when the screen locks and leaves it armed;
`auth:fingerprint:retry_delay` is used **only** on `verify-no-match`
(`src/auth/Fingerprint.cpp`, read at `v0.9.6` and at `main`). Three minutes
later the thermal model fires, and:

```cpp
case MATCH_DISCONNECTED:
    m_sFailureReason   = "Fingerprint device disconnected";
    m_sDBUSState.abort = true;
    break;
```

```cpp
void CFingerprint::terminate() {
    if (!m_sDBUSState.abort)
        releaseDevice();
}
```

| consequence | |
|---|---|
| no re-arm | `MATCH_DISCONNECTED` has no retry path. Only a suspend/resume (`PrepareForSleep`) ever calls `startVerify()` again |
| wrong message | the screen says *"Fingerprint device disconnected"* about a sensor that never left the USB bus |
| the claim is **not released** | `abort` suppresses `releaseDevice()`, so fprintd stays claimed until hyprlock **exits** |
| the invitation stays up | `ready_message = (Touch finger to unlock)` keeps asking for a gesture that cannot be answered |

**Therefore: every lock you come back to more than ~3 minutes after it started
has no fingerprint, before your hand is anywhere near the pad.** hypridle locks
at `timeout = 300` (5 min idle), so the locks you *return* to are exactly the
ones that have been armed past the budget. The locks where fingerprint can work
are the ones you unlock within three minutes of locking — which is why it has
ever seemed to work at all.

Corroborated independently in today's journal: `fprintd.service` deactivates
**30–41 s** after each hyprlock death (30 s idle timer + the claim dropping
only when the process vanished) — 08:47:29 crash → 08:48:10 deactivated,
11:59:20 → 11:59:50. The claim was held for the whole lock, exactly as the
`abort` path implies.

⚠ **Upstream `main` is identical** — no too-hot case, no backoff, no stop when
the display blanks. Waiting for a hyprlock release is **not** an option here.
(Other lockers hit the same wall and fixed it in the locker: omarchy
[#16740](https://github.com/omacom/omarchy/issues/16740) measured 1,809 failed
PAM sessions in one 12-minute lock and fixed it with a 2-minute scan window
plus exponential backoff.)

#### What it does to Triton Panel

| path | what happens at 180 s | verdict |
|---|---|---|
| **calibration** | re-arms immediately for every bucket (§20s, and that is correct) → trips → `verify-disconnected` → bucket `driver` → `_cal_dry` increments with no contact → `MAX_CAL_DRY = 4` → *"That is a wedged endpoint, not your placement. Close this window and run ./fp-debug.sh rebind."* | **wrong advice.** It is a cooldown. A rebind resets the model as a side effect, which would make the wrong instruction appear to work |
| **enrolment** | `enroll-disconnected` → *"The device vanished mid-enrollment."* §20k's restart loop then burns `MAX_DRY_RESTARTS = 3` instantly against a hot device | **an enrolment that takes longer than three minutes cannot finish.** The 6/6 run of §20l took ~54 s; that it was *under budget* was never noticed as one of its conditions |
| **Test a stored print** (§20p) | 30 s hard cap, one press | **safe**, and the only path that always was |

⚠ This is the fourth time a number in this window has been about the panel
rather than about the hand (§20o, §20r, §20s, now this).

#### The phantom measurement: `verify-swipe-too-short` every 10 s on an empty pad

The same no-finger probe produced **17** of these in 180 s, one every 10.0 s,
with `finger-present` never once true:

```
14:33:40  verify-swipe-too-short  done=False  (+10.1s since arm)
14:33:50  verify-swipe-too-short  done=False  (+20.2s since arm)
…                                             (17 of them, then the trip)
```

Mechanism, from the driver's own header: `ELAN_CMD_TIMEOUT 10000` with
`ELAN_MIN_FRAMES 7` — a capture that times out having assembled too few frames
is `FP_DEVICE_RETRY_TOO_SHORT`, which fprintd renames
`verify-swipe-too-short`, a **retry** (`done = False`) that leaves the verify
open. It is the driver's idle heartbeat, not a report about anybody's finger.

In this panel that string is bucket `rejected`, so **`cal_log.append(False)`
every ten seconds**: `CAL_MIN = 10` is reached in ~100 s and the gate announces
**"Captures are too thin"** about a pad nobody has touched. The lift gate does
not stop it — `ContactStrip.supported` stays `None` until a presence property
is actually seen, so `gated` is `False` and §20s's suppression branch is never
even reached.

⚠ And the hint attached to the string — *"Stay on the sensor longer -- do not
lift partway"* — is advice built from a result the hardware emits with **no
sensor contact at all**. That is rule (1) of `../CLAUDE.md` for the third time:
a driver-reported result is evidence about the driver.

~~⚠ **The counting rule was deliberately NOT changed by this pass.** Whether a
`rejected` result with no reported contact means *"nobody touched"* or *"this
reader cannot report contact"* is decided by one unrun measurement —
`./fp-debug.sh presence`, still unrun since §20s, still needing a finger. §20s
chose not to gate a reader that never reports presence, and reversing that
choice on an inference is how §20r became §20s. **Run `presence` first.**~~

✅ **`presence` was run the same day — §20u has the measurement and the rule
change.** The answer was *"nobody touched"*, and it was not close: four real
touches all reported `finger-present`, both phantoms reported none. Kept above
because the restraint was the right call — the rule moved on a measurement, not
on this inference.

#### hyprlock segfaulted three times today — correlated, not explained

```
08:47:29  hyprlock[13593]: segfault at 55e73812c1b0 ip 000055e73812c1b0 … error 15
09:23:39  hyprlock[47224]: segfault at 56285757dcd0 ip 000056285757dcd0 … error 15
11:59:20  hyprlock[78378]: segfault at 556d6c2267d0 ip 0000556d6c2267d0 … error 15
```

What is **established**: all three are in locks where the thermal trip had
already fired; `ip` equals the fault address with `SEGV_ACCERR` and a
single-frame stack, i.e. a jump through a pointer that is not code; each is
followed 30–41 s later by `fprintd.service` deactivating, so the claim outlived
the crash; and 11:59:20 follows a `pam_unix` failure at 11:59:16, which fits
*retype the password, unlock, die at teardown*.

⚠ What is **not established**: that the fingerprint path caused it. The
mechanism worth testing first is hyprlock's own
`addTimer(RETRYDELAY, …, this)` on the `verify-no-match` path — a 250 ms timer
holding a raw `this` into `CFingerprint`, which would be exactly this crash if
it fires during teardown. **Not backtraced** (`#0` is garbage; frames 1+ need
`coredumpctl debug` with debuginfod). No session exposure either way: Hyprland
keeps the session locked if its locker dies, and these deaths line up with the
unlock.

#### Options, ranked by how well they are verified

| option | verified how | hazard |
|---|---|---|
| **Keep every measuring session under ~2.5 min** and treat the budget as a hard limit for enrolment and calibration | first-hand, measured above | none. This is the one free change, and it reframes every "enrolment is hard" report in §20k–§20q |
| **Turn the hyprlock switch off** until a locker-side fix exists | the behaviour is read in hyprlock's source at `v0.9.6` *and* `main` | loses nothing that currently works: past 3 min it is already dead, and the prompt stops inviting a gesture that cannot succeed |
| **Patch hyprlock** — stop the verify after ~2 min, re-arm on input, back off fast failures (omarchy's shape) | the upstream fix in another locker is merged and reported working; **no diff written here** | reverts on `paru -Syu`; `IgnorePkg` freezes a lock screen's security updates. Blast radius is far smaller than §20q's libfprint patch: password auth is untouched |
| **Re-measure `verify-disconnected` from the journal instead of the D-Bus string**, in the panel | the mapping is read in fprintd's source; journal is readable unprivileged here | an extra dependency on journal access; it is the only way a client can tell the three causes apart |
| **`temp_hot_seconds = -1` for `elan`**, as the match-on-chip drivers are said to do | ⚠ secondary source only | needs a patched libfprint — §20q's hazards apply in full, and it removes a protection whose physical basis here is unknown |

#### Applied by this pass

* **`triton-panel/fp-debug.sh thermal`** — the measurement above, repeatable,
  no sudo, no finger, no fprintd restart (a restart would reset the very model
  being measured). Prints the trip, every refusal and the cooldown.
* **The panel reads the journal instead of guessing.** `_journal_too_hot()`
  runs `journalctl -u fprintd -n 5 -o cat --since <this arm>` — unprivileged
  here, ~30 ms — and that verdict **outranks** every inference, because it is
  the only place the real error name exists. Only when it cannot tell does the
  panel fall back to (a) the session's cumulative **armed** time or (b) a fault
  that arrived in under a second, i.e. a refusal that read nothing. The log
  line names which of the three decided, so *"fprintd said so"* and *"we
  inferred it"* stay distinguishable.
* **The lockout no longer sends anyone to `fp-debug.sh rebind`.** It is kept
  out of `_cal_dry` and `MAX_DRY_RESTARTS`, and the window names the model and
  the wait instead. ⚠ But two cooldowns that resume straight back into an
  instant refusal **stop** being called thermal: that is the point where a
  wedged endpoint looks identical, so the window says so and names the journal
  as the way to tell.
* **The armed budget is not reset at a phase boundary.** libfprint's model
  decays with a 540 s constant and knows nothing about the panel's phases, so a
  100 s calibration followed by *Enroll anyway* trips **65 s into the
  enrolment** — and a per-phase reset would read that as a driver fault. For
  the same reason a cooldown resumes the estimate at the **WARM**-equivalent
  (`THERMAL_HOT_S - 111`), not at zero.
* **The budget is on screen in both phases** (the calibration and enrolment
  tally lines, from the first second, because it is already burning), with a
  one-time warning at 150 s and a per-second countdown while cooling.
* The `verify-disconnected` / `enroll-disconnected` copy no longer says the
  reader disconnected, because on this machine it never has; it names all
  three errors the string can mean.

#### Verify — results 2026-11-03

| check | result |
|---|---|
| `./fp-debug.sh thermal` | trip at **+180.1 s** with no finger, uncontaminated (`finger-present` never fired once); cooldown in **(180, 212] s** |
| `test-enroll.py` | **200 assertions, ALL PASS** (154 before) — twelve new blocks for the lockout, incl. the calibrate→enrol budget carry, the journal outranking the inference both ways, the WARM resume and the futility cap |
| widget construction | re-smoke-tested for an occupied **and** a free slot, every paint method called — the only thing that has ever caught this panel's paint-before-widget bug class |
| `./fp-debug.sh thermal` plumbing | claim → arm → 10 s retry → cap → release, exercised with `HOT_CAP=15` |
| journal line at the trip | `Device disabled to prevent overheating.` — same string as the morning's locks |

---


### 20u. The ten-second phantom was never a finger — `presence` decides it — ✅ APPLIED 2026-11-03 (twelfth pass)

§20t found the phantom and refused to act on it, because the one measurement
that could tell *"nobody touched the pad"* from *"this reader cannot report
contact"* had been unrun since §20s. It was run: **40 seconds, one finger,
`./fp-debug.sh presence`**. The separation is total.

#### The measurement

```
16:11:20.175  finger-present: true        <- a real touch
16:11:21.378  finger-needed: false
16:11:21.379  finger-present: false
16:11:21.381  VerifyStatus verify-retry-scan   false      (1.20s of contact)

16:11:31.562  VerifyStatus verify-swipe-too-short false   <- +10.17s, NO presence
16:11:41.595  VerifyStatus verify-swipe-too-short false   <- +10.03s, NO presence
```

| | real touch | phantom |
|---|---|---|
| count in this run | 4 | 2 |
| `finger-present` ON edge before the result | **4 of 4** | **0 of 2** |
| spacing | when the finger landed | **10.17 s / 10.03 s** — `ELAN_CMD_TIMEOUT 10000` |
| journal line | `Failed to detect minutiae: No minutiae found` | **nothing at all** |

Two independent witnesses, then, and the second is worth keeping in mind for
any later pass: **fprintd logs nothing for a phantom.** A result that reaches
D-Bus with no journal line behind it did not come from a capture.

#### What changed, and what it costs

The discriminator is the reader's own report, so this is **not** an inference
of §20t's kind — nothing here says "looks like". A `*-swipe-too-short` with no
`finger-present` ON edge since the last accounted-for result is the driver
idling, and it is kept out of the rolling window, the tally, the attempt count
and the strip. Both result paths are gated, because the enrolment side was
doing something worse than dragging a score down: its repeats counter drove
the line *"the driver may simply not handle this sensor"* — a verdict about the
hardware, assembled out of the hardware idling.

What the rule trades away, stated plainly because §20s's restraint was about
exactly this: §20j's wall-clock escape hatch **no longer applies to these two
result strings** on a reader known to report presence. If a genuine
sub-`ELAN_MIN_FRAMES` tap ever emits no presence, one reject goes uncounted out
of a rolling ten. The behaviour it replaces was measured: ten false rejects —
a full `CAL_WINDOW` — per 100 s of reading the screen, ending in **"Captures
are too thin"** about a hand that was never there.

⚠ **The gate has to work before the first touch**, which is the one place this
pass needed a device fact rather than a live observation. `ContactStrip.supported`
only becomes `True` when a presence property arrives, i.e. on the first touch —
and the phantoms that most need discarding are precisely the ones that land
while the window is still being read. So `PRESENCE_SENSORS` keys *"this reader
publishes `finger-present`"* by **USB id**, exactly as `AREA_SENSORS` keys the
physical gesture, and for the same reason: it is a measured fact about the part,
not a property the driver volunteers (`../CLAUDE.md` rule 1). A reader in
neither set keeps §20s's behaviour untouched — no gate, nothing suppressed.

The phantom count is shown on the live tally line (`N reader timeouts
ignored`) rather than in the log, which is written **once**: one of these
arrives every 10 s for as long as the window is open, so a line per event would
bury the real results and a status repaint would stomp the instruction being
read.

#### Two other things that same 40 seconds settled

⚠ **A `verify-disconnected` that was *not* thermal, at 25 s armed.** At
16:11:42 the journal says `Device reported an error during verify: The driver
encountered a protocol error with the device.` — and the **very next arm
worked**, 1.1 s later. That is `../CLAUDE.md` rule 5 happening in the wild on
the first `verify-disconnected` seen after §20t: one string, three errors, and
the first one met was the one §20t was *not* about. `_looks_thermal(25)`
returns `False` on it — the journal verdict outranks everything, and the armed
budget agrees anyway — so §20t's machinery correctly left it to §20k's restart
loop. Had the panel inferred *thermal* from the string, it would have sat out a
215 s cooldown that did not exist.

⚠ **The remaining failure is matching, not detection.** Three of the four real
touches produced `verify-no-match`, not `verify-retry-scan`: presence detected,
image assembled, minutiae extracted, matcher ran, **scored below the bz3
threshold of 40**. So the original report — *gaps in the capture and detection
of fingerprints* — has now been answered in full and the two halves came apart:
**detection** was the clock (§20t) plus these phantoms, both now handled;
**capture** is §20m's thread, unchanged and still real, and this run moves
verify from 4/4 to **7/7 failures** with the failure mode sharpened — it is the
template and the ~1 cm pad (§20q's one-of-N storage is the lever), not the
hand, and not the gesture.

#### A session the same afternoon, and three things it proved

16:42, reported as *"intenté registrar mi dedo pero me rechaza muchos dedos
para registro"*. The journal is unambiguous about what it was **not**:

```
16:33:52  fprintd started
16:36:52  Device disabled to prevent overheating.        <- +180.0s, no capture logged
16:42:04  triton-panel launched (elephant/Walker)         <- a DIFFERENT window
16:42:21  Failed to detect minutiae: No minutiae found
16:42:21  ...protocol error with the device.
   …      22x No minutiae found + 32x protocol error in 83 s, then nothing
```

⚠ **Read the verb: every line says `during verify`, so the enrolment never
started.** What was rejecting was the §20o calibration — which is *advice*, not
a gate (`start_button` is always sensitive and relabels `Enroll anyway`). A
user watching it reject for 83 s has no way to know that from the window.

**1. The calibrate-then-enrol flow does not fit the budget.** §20t established
the 180 s ceiling and §20u's panel work shows it on screen, but neither drew
the consequence: calibration is a **verify loop with no termination condition**
except the gate opening, so it will spend the entire budget by design, and the
enrolment that follows gets whatever is left. §20l's successful 6/6 took
**54 s** — it would not fit after a calibration that ran to the gate. ⚠ So for
an *enrolment attempt*, skip the calibration: it is a measurement, and the
measurement costs the thing the enrolment needs.

**2. The thermal model lives in the daemon, not in the window.** The trip
landed **180.0 s after `fprintd` started**, and libfprint keeps the estimate on
the `FpDevice`, which outlives any one client's claim. So a **fresh daemon is a
fresh budget** — and a new window's `armed Ns of 180s` counter is a **lower
bound**, because whatever the previous client spent (a lock screen, a `sudo`, an
earlier window) is already charged and invisible to it. ⚠ `fp-debug.sh rebind`
restarts `fprintd` as a side effect, which makes it the only available way to
zero the model. (That a second window inherits the charge follows from the
source, not from a separate measurement.)

**3. ⚠ Launched from Walker, the panel's attempt log goes nowhere.** It mirrors
every result to stderr *specifically* so a session can be reconstructed
(§20g), but `elephant` starts it through `systemd-run` and the transient unit's
output is not in the user journal — so the one artefact that distinguishes H1
from H2 (the tally: how many attempts **scored**) was unavailable for the
session above, and the fprintd journal **cannot** substitute: it logs
`No minutiae found` and errors, and is silent for `verify-no-match` — proven by
the presence run, whose three no-matches left no line at all. **Run the panel
from a terminal when diagnosing.**

What the 83 s does prove on its own: **32 protocol errors**, each ~0.4 s after
a failed capture — the §20j retry → invalid-transition pattern — against
**zero** in §20l's 6/6. That ratio remains the sharpest available discriminator
between a run that can succeed and one that cannot, and it is still unexplained.

#### Verify

| check | result |
|---|---|
| `test-enroll.py` | **246 assertions, ALL PASS** (200 before) — eleven new blocks |
| the phantom is not a measurement | window, tally, attempt count, strip and hint all untouched; ten of them keep `_cal_gate()` at `window == 0` |
| the same string after a real touch | still counted as a rejected placement, still given the gesture hint |
| the press is spent | a counted result clears the ON edge, so a timeout 10 s later is a phantom again |
| a reader outside `PRESENCE_SENSORS` | §20j's escape hatch intact — counted, not discarded |
| before the first touch | gated from the USB id alone, with `ContactStrip.supported is None` |
| ordering, asserted against the source | the phantom check runs before `close_open_contact()` (or the strip invents a contact) and before the same-press gate |
| ⚠ never deaf | a *terminal* phantom is still re-armed in calibration and is **not** suppressed at all on the enrol side, where it has to reach the restart machinery — a suppression branch that skips the re-arm is how §20r happened, and `done` is where it would come back |
| `test-battery.py` | all passed |
| widget construction | SMOKE OK, occupied and free slot |
| `check-doc-refs.sh` | 0 errors |

Nothing in the live configuration was changed by this pass either —
`hyprlock.conf` untouched, password auth on, `pam_fprintd` still `sufficient`.

---


### 20v. An enrolment deletes the old print before its first stage — and the same-press gate was eating driver faults — ✅ APPLIED 2026-11-03 (thirteenth pass)

§20u's advice was followed and produced two findings, one of them a loss.

#### The print of 2026-11-01 is gone, and starting the enrolment is what took it

Reported as *"ya he registrado una huella"*. `fprintd-list` says
**`User isalgado has no fingers enrolled`**. The chain is decisive:

| time | evidence |
|---|---|
| 16:45 | `fprintd-list` → `#0: right-index-finger` |
| 17:15:47–17:16:17 | the panel logs `Scoring against — Right index` over and over — that string comes from `VerifyFingerSelected`, so **the print still existed** |
| 17:16:20 | `Claiming the reader — to enroll` (polkit prompt at 17:16:20.55) |
| 17:16:23 | `Enrollment started — right-index-finger` ← **last line in any log** |
| — | no `during enroll` journal line, no stage, no crash (`coredumpctl` empty) |
| 17:18 | `fprintd-list` → **no fingers enrolled** |

Not a manual delete: `_on_fp_delete` calls `hyprlock_set(False, …)` when the
last print goes, `hyprlock_set(False, …)` **splices the managed block out**,
and the block is still in the live `hyprlock.conf` with `enabled = true`.

The mechanism, read in fprintd 1.94.5's `src/device.c` rather than inferred —
`fprint_device_enroll_start`:

```
store.print_data_load (priv->dev, finger, session->username, &existing_print);
if (existing_print)
  if (!delete_enrolled_fingers (rdev, session->username, finger, &error))
```

…and `delete_enrolled_fingers` calls `store.print_data_delete`. The new print
is written **only** in `enroll_cb`, by `store.print_data_save (print)`.

⚠ **So "overwrites" was the wrong word, and it is the word the panel used.**
The old print is destroyed at `EnrollStart`, *before the first stage*, and an
enrolment that is abandoned or that fails leaves the slot **empty**. §20m's
*"⚠ do not delete `right-index-finger`"* protected the wrong verb: enrolling
into it is exactly as destructive as deleting it, and quieter. The warning
label now says so, naming the two source calls.

#### The same-press gate was holding driver faults — and hiding the thermal lockout

The pasted log contains, fourteen times:

```
info: Same contact — not counted — Reader cut off; lift the finger to measure again
```

`Reader cut off` is the title of `verify-disconnected`. So across 32 s **every
single suppression was a driver fault** — §20s's gate caught no actual repeat
press at all. `if unmoved and quiet:` was written for placement evidence and
tested against it, but it never excluded bucket `driver`. Three consequences:

1. the user was told to *"take the finger right off the pad"* about a reader
   that had stopped reading — rule (1) again, an instruction built from the
   wrong layer;
2. `_cal_dry` never incremented, so `MAX_CAL_DRY` could not fire;
3. ⚠ **and the thermal check never ran.** It lives in the terminal
   `bucket == "driver"` branch *below* that `return`, so a §20t lockout with a
   finger resting on the pad would have been suppressed as "the same press"
   for the whole 215 s cooldown, saying *"lift the finger clear"* and never
   entering it. A hole straight through the eleventh pass, opened by the
   tenth, and invisible to 246 assertions because every test of the gate fed
   it a *placement* result.

Fixed with one predicate, `placement = bucket != "driver"`, gating **both**
suppression branches and the press-evidence reset — a driver fault measured no
press, so it must not *spend* the evidence that one happened either, or the
next real result inside `SAME_PRESS_S` is suppressed as a repeat of a press
that was never counted. Driver faults now reach the tally, which is an
improvement in itself: a storm of them is visible instead of hidden behind one
*"Same contact"* line (`_cal_noted_no_lift` had suppressed even the logging
after the first).

#### What the session did prove about the hand

Of 13 counted calibration attempts, **6 scored** and all 6 were
`verify-no-match` — the same finger scoring below 40 against its own template,
six times. That is H1, and it means re-enrolling was the correct call and
nothing usable was lost. ⚠ But **7 of 13 were `rejected`** (`No usable detail`
— no readable ridges), so H2 is still present: re-enrolling addresses the
template only, and the capture ceiling of §20k/§20m is untouched. Contact
durations were consistent, 1.21–1.31 s.

⚠ Live state after this pass: **zero prints enrolled**, the hyprlock switch
still **on** — a combination the panel's own delete path forbids and that no
code path produces, so it can only be reached the way it was. `pam_fprintd`
stays `sufficient`, and with no print it now falls straight through, so `sudo`
no longer waits ~30 s on the reader.

#### Then the window blocked the recovery three more ways

With the print gone the user went back in, and the next 25 minutes produced
three more defects — each one a message or an offer that was wrong about the
layer it was describing.

**1. Calibrate was offered — as the *suggested* action — with zero prints.**
Calibration is a **verify** loop: it scores the finger against a stored
template. With nothing enrolled fprintd refuses before the reader is touched:

```
17:44:13  VerifyStart failed — GDBus.Error:net.reactivated.Fprint.Error.
          NoEnrolledPrints: No fingerprints enrolled
```

…five times in 12 s, because `_update_cal` put `suggested-action` on Calibrate
whenever the gate was not open, and *"not open"* and *"impossible"* are not the
same state. ⚠ And the failure branch answered it with *"the reader may be
wedged — run ./fp-debug.sh rebind"* — §20g's exact mistake, sending someone to
reset a USB endpoint over empty storage. Now: Calibrate is **insensitive**
without a print, Enroll takes `suggested-action` and the plain label `Enroll`,
the card says why, and `NoEnrolledPrints` gets its own message that names
rebind **only to rule it out**.

**2. `Device was not claimed before use`, twice, from an untouched window.**

```
17:42:35  Authorization denied to :1.13800 to call method 'EnrollStop' …
17:42:35  Authorization denied to :1.13800 to call method 'Release' …
```

`_on_close_request` calls `_stop(release=True)` unconditionally, and the guard
there was `not self._released` — which starts `False` meaning *"nothing
released yet"* and so **conflates "we hold a claim" with "we never claimed
one"**. Open the Enroll window, close it without pressing anything, and it
fires `EnrollStop` + `Release` at a device nobody claimed. §20r fixed the
*second* `_stop()`; this was the *first* one on a window that never claimed.
Fixed with an explicit `_claimed`, set in `_on_claimed`, cleared on every
release. ⚠ It matters beyond tidiness: §20r named this *"the single most
misleading line this subsystem can print"*, because it reads exactly like a
claim leak and is the opposite of one — and the journal is one of only two
evidence channels here.

**3. ⚠ The attempt log reaches no journal, and that is what cost the print.**
§20u recorded the gap; this pass proves it was load-bearing. Two panel
sessions (17:23:00–17:26:43 and 17:35:14–17:39:31, both launched by Walker)
left **no trace anywhere**, and whether either completed an enrolment is now
unknowable — because fprintd's journal is silent for an accepted enrol stage,
and the only other witness went into a `systemd-run` unit whose output is not
collected. A `DeleteEnrolledFingers` at 17:40:27 (`Offending API user is
python3` — the panel's Delete button) may therefore have removed a *working*
print, and nothing can now say. So `_log()` writes every line to a **file** as
well as stderr: `$XDG_STATE_HOME/triton-panel/panel-<ts>.log` (override with
`TRITON_PANEL_LOG_DIR`), line-buffered so a killed panel keeps what it printed,
newest `LOG_KEEP = 20` retained, and the path is announced **in the window's own
log pane** — a log nobody can find is the same as no log.

⚠ One consequence of that delete, and the only good news in it: the panel's own
`_on_fp_delete` turned the hyprlock switch **off** when the last print went, so
the managed block is gone from the live `hyprlock.conf` and the lock screen has
stopped inviting a finger it cannot read. The repo mirror has been pulled back
to match.

#### Verify

| check | result |
|---|---|
| `test-enroll.py` | **282 assertions, ALL PASS** (246 before) — ten new blocks |
| no print → no Calibrate | button insensitive, not suggested, Enroll leads and is labelled `Enroll` |
| `NoEnrolledPrints` | no `./fp-debug.sh rebind` in the hint; rebind named only to rule it out |
| any other `VerifyStart` failure | the wedged-reader advice is intact |
| a window that never claimed | `_stop(release=True)` makes **no** D-Bus calls at all |
| a window that did claim | still `VerifyStop` + `Release`, and `_claimed` goes false |
| the log file | written, found by `log_file_path()`, contains the line, honours `TRITON_PANEL_LOG_DIR` |
| the lockout scenario | fed `verify-disconnected` in exactly the state the gate used to fire in → `_enter_thermal` runs, status is **not** "Lift the finger clear" |
| the gate still works | `verify-retry-scan` in that same state is still suppressed, and still re-armed (§20s) |
| a PROTO fault | tallied, out of the rolling window, press evidence untouched, reaches the dry-fault accounting |
| the escape hatch | no *"Counted without a reported lift"* line about a fault |
| mechanism | read verbatim from fprintd 1.94.5 `src/device.c`, not inferred |
| `test-battery.py` / widgets / `check-doc-refs.sh` | passing / SMOKE OK / 0 errors |

---


### 20w. The blocker: a protocol error between stages, and fprintd discards the partial enrolment — ✅ CEILING APPLIED 2026-11-03 (fourteenth pass)

§20v's log file paid for itself inside the hour. Reported as *"solo me acepta
la primera ingresada y al levantar el dedo la borra"* — and that is precisely
what happens. Ten cycles in 44 s, from `panel-20261103-181106.log`:

```
18:11:18  stage:  Accepted — stage 1 of 6, 1.29s of contact
18:11:18  driver: Reader cut off
18:11:18  info:   Restarted enrollment (1) — fprintd discarded 1 stage(s)
18:11:20  stage:  Accepted — stage 1 of 6, 1.24s of contact
18:11:22  driver: Reader cut off
18:11:22  info:   Restarted enrollment (2) — fprintd discarded 1 stage(s)
…                                            (10 of them; stage 2 never once)
```

The journal for the same 44 s, nothing else in it:

| count | line |
|---|---|
| 7 | `Device reported an error during enroll: …protocol error…` |
| 3 | `Device reported an error during **identify for enroll**: …protocol error…` |
| 6 | `Failed to detect minutiae: No minutiae found` |

**So the capture is not the problem here.** Contact was 1.20–1.40 s every time,
six stages were *accepted*, minutiae were extracted. A protocol error then ends
the operation, fprintd discards the partial enrolment (§20v read `enroll_cb`:
the print is written **only** on completion), and §20k's restart loop starts
again at stage 1.

⚠ **Not "on the lift", though that is how it feels.** The accept is logged *at*
the lift — `close_open_contact()` runs when the capture completes — so the lift
has already happened by then, and the 5-second gaps (18:11:33→38, 18:11:42→46)
rule the lift out. What is common to all ten is that the fault arrives while
the driver is **arming the next capture on an empty pad**. §20j recorded
exactly that state transition misbehaving
(`FPI_IMAGE_DEVICE_STATE_AWAIT_FINGER_ON` → `…AWAIT_FINGER_OFF`,
*"should not happen"*), so it is the obvious candidate — ⚠ but that line is
**not in this journal at all** (0 occurrences today; it is debug level and
needs `G_MESSAGES_DEBUG=all`). **Hypothesis, not mechanism**, and the rule here
is not to build an instruction on one.

#### Why calibration survives this and enrolment cannot

The asymmetry §20m noticed but did not locate. A calibration result is
`done = True` and the loop answers with a **fresh** `VerifyStart` — there is no
accumulated state to lose, so a protocol error costs one attempt. An
enrolment is **one operation spanning six captures**, and fprintd throws the
whole partial template away on the first fault. So the *same* error rate is a
nuisance to calibration and fatal to enrolment.

⚠ And this finally explains §20l's 6/6 in full: that run logged **zero**
protocol errors, so §20k's restart loop never fired. It was the state the
device happened to be in, not the technique — which is why §20l's *"necessary
but not shown sufficient"* was the right caution and why a second finger never
reproduced it.

#### A tax nobody had noticed: fprintd identifies before every EnrollStart

`during identify for enroll` is fprintd's **duplicate check**, and the gate on
it, read verbatim in 1.94.5's `fprint_device_enroll_start`, is the device
feature **alone**:

```c
if (fp_device_has_feature (priv->dev, FP_DEVICE_FEATURE_IDENTIFY))
  {
    g_autoptr(GPtrArray) all_prints = load_all_prints (rdev);
    fp_device_identify (priv->dev, all_prints, …, enroll_identify_cb, rdev);
  }
```

There is **no check that any print exists** — `all_prints` is passed whatever
its length. So with zero prints enrolled it still runs, and every restart
costs a full extra device operation: 10 restarts here meant ~20 operations in
44 s, of which **3 of the 10 faults came from the identify rather than the
enrol**. It is not the cause, but it doubles the exposure per retry.

#### Applied: a ceiling on restarts that make no progress

`MAX_DRY_RESTARTS` cannot see this — it counts faults with no finger
**contact**, a wedged endpoint, and here contact is perfect. `MAX_RESTARTS = 15`
let the counter reset in front of the user for a minute. Added
`MAX_STALLED_RESTARTS = 3`, which fires only when `_best_passed == 1`:

* **exactly one**, because that is the measured pattern — a stage is accepted
  and the run never gets past it;
* **not `0`**: §20l's 6/6 needed this loop to survive protocol errors arriving
  *before* any stage passed, and the message would be a lie about such a run
  (*"every accepted stage"* when none was);
* **not `> 1`**: that is the genuinely intermittent case `MAX_RESTARTS` is for.

⚠ The first draft used `<= 1` and **two existing tests caught it** — the dry-cap
test and the contact-resets-the-dry-counter test both feed faults with no stage
ever accepted. `_best_passed` is a high-water mark cleared only in
`_begin_enroll`, never on a restart.

The message names the layer and exactly one next step, and **deliberately does
not mention `rebind`**: nothing is wedged when the captures are being accepted.

#### Where this leaves it — ranked, and none applied beyond the ceiling

1. ⚠ **`./fp-debug.sh press` with `G_MESSAGES_DEBUG=all`.** Unrun since §20j
   and now it has one specific thing to decide: whether the fault follows the
   re-arm, and whether the invalid state transition is there. **Nothing below
   is worth doing before this.**
2. **`FP_SCAN_TYPE_PRESS` for `elan`** (§20q). Now the best-motivated candidate
   it has ever been: a reproducible fault while arming a capture on an area pad
   is what a swipe/motion state machine running on the wrong sensor type would
   produce. ⚠ Needs a patched libfprint and reverts on `paru -Syu` — but the
   blast radius is the smallest it has been: password auth is on, and the
   hyprlock block is **gone** (§20v), so nothing but `sudo`'s `sufficient`
   `pam_fprintd` sits behind it.
3. **Accept that this reader is not usable** and leave the switch off. Stated
   plainly because four passes of panel work have not moved it and the fault is
   below the panel in every measurement taken.

#### Verify

| check | result |
|---|---|
| `test-enroll.py` | **303 assertions, ALL PASS** (282 before) — five new blocks |
| the measured pattern | accepted → fault × 3 → stopped; hint names *stage 1*, says the captures are ACCEPTED, no `rebind`, points at `./fp-debug.sh press` |
| a run making progress | three stages banked → the stalled ceiling never fires, restarts continue |
| a run with no stage ever | old governors intact (this is the regression the first draft broke) |
| `MAX_RESTARTS` | still the backstop once `_best_passed > 1` |
| the high-water mark | survives a restart; cleared only in `_begin_enroll`, asserted against the source |
| `test-battery.py` / widgets / doc refs / live system | passing / SMOKE OK / 0 errors / 19 pass 0 fail |

---


### 20x. The cause, in the driver: a documented status byte treated as a fatal error — ⚠ PATCH WRITTEN, NOT APPLIED 2026-11-03 (fifteenth pass)

§20w isolated the blocker and ranked `./fp-debug.sh press` first. Reading the
driver turned out to be cheaper than measuring it, and it gives the mechanism
outright. `libfprint/drivers/elan.c`, `capture_run_state`, the **only**
`FP_DEVICE_ERROR_PROTO` site in the whole driver:

```c
case CAPTURE_READ_DATA:
  /* 0x55 - finger present
   * 0xff - device not calibrated (probably) */
  if (self->last_read && self->last_read[0] == 0x55)
    { … capture … }
  else if (self->dev_type == ELAN_0C58 && self->last_read &&
           (self->last_read[0] == 0x00 || self->last_read[0] == 0xaf))
    {
      /* 0x00 - not ready
       * 0xaf - finger removed or sensor busy (seen on 0x0c58) */
      fpi_ssm_jump_to_state_delayed (ssm, CAPTURE_WAIT_FINGER, 10);
    }
  else
    { … fpi_ssm_mark_failed (ssm, fpi_device_error_new (FP_DEVICE_ERROR_PROTO)); }
```

⚠ **The retry is gated on `dev_type == ELAN_0C58`.** For every other device —
`0c4f` carries `ELAN_ALL_DEV`, i.e. no quirk bit at all — a `0x00` or `0xaf`
response becomes a **fatal** protocol error. And the driver's own comment says
what those bytes mean: `0x00` *not ready*, `0xaf` ***finger removed or sensor
busy***.

That is the bug, and it accounts for every observation this subsystem has
collected:

| observation | explained by |
|---|---|
| the fault lands **between** stages, while the next capture is arming | that is when the sensor is busy and the finger has just gone |
| the user's words, *"al levantar el dedo la borra"* | `0xaf` is literally *finger removed* |
| 0–5 s after the accept, not instant | it depends when the next `pre_scan_cmd` lands on a settling sensor |
| calibration **survives** the same error rate | each verify is an independent operation; there is no partial state to discard |
| enrolment cannot | one operation across six captures, discarded whole on the first fault (§20v) |
| §20l's 6/6 with **zero** protocol errors | the sensor happened to answer `0x55` at all six transitions. Luck, not technique — which is exactly the caution §20l insisted on |
| no `too-short`/`too-fast`, ever (§20g) | they come from a different path entirely |

#### The patch, and why it is three lines

`patches/libfprint-elan-0c4f-busy-retry.patch` adds a unique `driver_data` bit
for `0c4f` and lets it take the same retry. ⚠ It does **not** widen the test to
all devices: those bytes are almost certainly transient everywhere and
upstream gated it narrowly out of caution, but widening it would change
behaviour for hardware nobody here can test.

Every `dev_type` site was audited against bit 4, and the audit is the part that
could fail silently, so it is a test (`tests/check-libfprint-patch.sh`) rather
than a paragraph: `ELAN_NOT_ROTATED` is bit 1 and is the only `&` test;
`ELAN_0C42` and `ELAN_0C58` are equality tests; `ELAN_CALIBRATION_ATTEMPTS`
keys on `0C58` and still returns the default 10; the open-time
`switch (self->dev_type)` matches only `ELAN_0907`; and the one command whose
`.devices` is not `ELAN_ALL_DEV` is also `ELAN_0907`, which stays skipped
either way. Verified: the patch applies cleanly to a pristine `v1.94.100`
checkout, 7 checks pass.

⚠ **The scan-type change was deliberately NOT bundled.**
`dev_class->scan_type = FP_SCAN_TYPE_SWIPE` is one line at elan.c:1018 and
§20q has wanted it changed since the eighth pass — but it addresses a
*different* failure (`No minutiae found`, the capture-quality thread of §20m),
and shipping two changes at once makes the result uninterpretable. One change,
one measurement. That discipline is what §20r → §20s cost.

Also recorded so nobody re-finds it: there **is** an `elanpress` driver with a
pull request moving `0c4f` onto it, reporting a completed 12-stage enrolment
and a `verify-match` — but it lives in the `filip-rs/libfprint` fork and
⚠ `elanpress` is **not in the installed library** (`FpiDeviceElan`,
`FpiDeviceElanmoc`, `FpiDeviceElanSpi` are; there is no `elanpress` symbol).
Taking it would mean replacing the system libfprint with a fork, which is a far
larger step than three lines against the stock driver — worth keeping as the
fallback if the patch below does not work.

#### ⚠ Why it is not applied

~~Building needs `meson`, `gobject-introspection`, `gtk-doc` and `umockdev`,
**none installed**, and installing packages against a refreshed database is the
partial upgrade `../CLAUDE.md` forbids — with an upgrade backlog outstanding.
So the honest order is: the pre-upgrade gate, a full `paru -Syu`, the reboot,
and only then the build.~~ `../patches/README.md` has the commands, including a
test path that installs **nothing**: build in `/tmp` and point `fprintd` at it
with a drop-in under `/run`, which is tmpfs, so a reboot undoes the whole
experiment.

✅ **The upgrade ran 2026-11-03 18:47** — 662 packages, kernel 7.3.1, NVIDIA
615.78.08 (`../CHANGELOG.md`, `updates.md` *Issue history*). The backlog is
therefore gone and the database and the installed set are in step. What is still
owed before a build is the **reboot** and the four packages, which are **still
missing**; `ninja` is the only one of the five already present:

```bash
paru -Syu --needed meson gobject-introspection gtk-doc umockdev
```

The full `-Syu` form is kept deliberately even though a plain `-S` would now be
safe: the rule in `../CLAUDE.md` is worth more than the keystrokes it costs, and
it is the form that cannot become a partial upgrade if the database has moved
since the last transaction.

⚠ ~~After the upgrade libfprint may not be 1.94.100 any more — run
`./tests/check-libfprint-patch.sh` with `LIBFPRINT_SRC` before trusting the
hunks.~~ ✅ **libfprint did not move.** The 662-package upgrade left
`libfprint 1.94.100-1.1` and `fprintd 1.94.5-2.1` untouched, so the hunks hold
exactly as verified. 1.94.100 is also **upstream's newest tag** — so no
*released* version carries this fix, and the two real options are carrying the
patch locally or sending it upstream. ⚠ Upstream's default branch was **not**
checked: the `git fetch origin main` that would have answered it failed on the
branch name (it is not `main`), so "unfixed upstream" is true of releases only. Re-run the checker after the *next*
upgrade that moves the package.

Safety, unchanged and worth restating because a libfprint patch sits under
everything: `pam_fprintd` is `sufficient` in `/etc/pam.d/sudo`, so Enter falls
through to the password, and the hyprlock fingerprint block is **absent**
(§20v). There is no lockout path even if the patched library is broken.

#### The order to try things in, and why the first one goes alone

1. **This patch, by itself.** It is the only candidate whose mechanism was
   *read* in the source rather than inferred; it is three lines against the
   stock driver; and it is the cheapest run that produces a fact this subsystem
   has never collected — a **completed, region-rotated six-stage template**.
   ⚠ Every verify failure on record (7/7, §20m) was against the single
   2026-11-01 template, built under the same-placement instruction §20q later
   retracted. So "verify does not work here" has never actually been tested
   against a good template, and until it has, §20m's ceiling is a measurement
   of one bad print.
2. **Then `FP_SCAN_TYPE_SWIPE` → `PRESS`** (§20q, `elan.c:1018`) — one more
   line, still the stock driver — and **only if** the enrolment completes and
   verify still fails. It is not bundled with step 1 on purpose: one change,
   one measurement, or neither result means anything.
3. **Only then the `elanpress` fork.** It replaces a system library sitting
   under `pam_fprintd` with a third-party driver whose diff was never seen from
   here, its author's test boxes were unticked, and a good part of what it
   reportedly fixes *is* step 2. ⚠ Being reported working on the same `0c4f` is
   not a reason to reach for it before the two smaller changes.

⚠ **Expect step 1 to fix the enrolment and not the matching.** They are
different failures, and the panel's log separates them in one read:
`Reader cut off` is what this patch targets, `No usable detail` is not. A run
that finally completes an enrolment and *still* fails to verify is step 1
succeeding, not step 1 failing.

#### What the next measurement will be

Not `press` any more. If the patch is loaded, the enrolment either survives the
stage-to-stage gap or it does not, and the panel's own log says which in one
read: `Accepted — stage 2 of 6` is the whole result. If the protocol errors
persist, §20w's ranking stands and the fork's `elanpress` is next.

#### Verify

| check | result |
|---|---|
| mechanism | read in `elan.c` at the single PROTO site, quoted above — not inferred |
| `tests/check-libfprint-patch.sh` | **7 passed, 0 failed** with a checkout; 5 passed, 2 skipped without one |
| applies to pristine v1.94.100 | yes, `git apply --check` clean |
| flag audit | 5 flags, `ELAN_0C4F` unique, no `&` test and no command mask reaches it |
| compiled | ⚠ **no** — `fpi-enums.h` is generated by meson, which is not installed. The patch is reviewed and verified structurally, **not** built |
| live system | untouched; no package installed, no drop-in written |

---

## Issue history

Moved here 2026-11-03 from `../ACTUAL-CONFIGURATION.md` §15, verbatim. Those table
cells had grown into multi-kilobyte incident analyses; §15 is now a status table
and the reasoning lives beside the runbook it explains.

### Enrolment cannot survive one stage: a protocol error between captures

⚠ **Open 2026-11-03 — the blocker, isolated at last, and it is below the
panel.** From `panel-20261103-181106.log`: a stage is **Accepted** (1.20–1.40 s
of contact, minutiae extracted), a protocol error ends the operation seconds
later, fprintd discards the partial enrolment, §20k's loop restarts at stage 1
— **ten times in 44 s, never once reaching stage 2**. Journal for the same
window: 7 × `during enroll` protocol error, 3 × `during **identify for
enroll**`, 6 × `No minutiae found`, nothing else. So capture is not the issue
here; the enrolment cannot survive the gap between two stages. ⚠ Not *on the
lift*, though it feels that way — the accept is logged at the lift and two of
the ten faults came 5 s later; what they share is arriving while the driver
**arms the next capture on an empty pad**, which is the state §20j saw
transition invalidly — ⚠ but that line is debug level and **absent** from this
journal, so it stays a hypothesis. This explains §20l's 6/6 completely: that
run had **zero** protocol errors, so the restart loop never fired — device
state, not technique. Also found, in fprintd's source: the duplicate
`fp_device_identify` before every `enroll_start` is gated on
`fp_device_has_feature(FP_DEVICE_FEATURE_IDENTIFY)` **alone**, with no check
that any print exists, so each restart costs a full extra device operation.
✅ Applied: `MAX_STALLED_RESTARTS = 3`, firing only when `_best_passed == 1`
(not 0 — §20l needed the loop before any stage passed; not >1 — that is
`MAX_RESTARTS`), with a message that names the layer and points at
`./fp-debug.sh press` and deliberately **not** at `rebind`, since nothing is
wedged. ⚠ Still unrun and now the only thing worth doing first:
`./fp-debug.sh press` with `G_MESSAGES_DEBUG=all`. §20j, §20k, §20l, §20q,
§20w

### The window blocked its own recovery three ways

✅ **Resolved 2026-11-03 (§20v).** With zero prints enrolled the Enroll window
still offered **Calibrate** — and marked it the *suggested* action — although
calibration is a verify loop that fprintd refuses outright
(`NoEnrolledPrints`); it was hit five times in 12 s and the failure branch
answered *"the reader may be wedged — run ./fp-debug.sh rebind"*, §20g's exact
mistake. Calibrate is now insensitive without a print, Enroll leads, and that
refusal has its own message naming rebind only to rule it out. ⚠ Separately,
`_on_close_request` → `_stop(release=True)` guarded on `not self._released`,
which starts `False` and so conflated *"we hold a claim"* with *"we never
claimed one"* — opening the window and closing it fired `EnrollStop` +
`Release` at an unclaimed device and fprintd logged **`Device was not claimed
before use` twice**, the line §20r called the most misleading this subsystem
can print; fixed with an explicit `_claimed`. ⚠ And the attempt log now goes to
a **file** (`$XDG_STATE_HOME/triton-panel/panel-<ts>.log`, `TRITON_PANEL_LOG_DIR`
to override, path shown in the window) because stderr reaches no journal under
Walker: two sessions on this day left no trace at all, so whether either
enrolled a working print before the 17:40:27 delete is permanently unknowable.
`test-enroll.py` 246 → **282 assertions**. §20g, §20r, §20v

### Starting an enrolment destroys the print in that slot

⚠ **Open 2026-11-03 — one print lost; the panel's warning is fixed, the trap
is upstream.** fprintd 1.94.5's `fprint_device_enroll_start` does
`store.print_data_load` and, if a print exists, `delete_enrolled_fingers` →
`store.print_data_delete` — **before the first stage**. The new print is
written only on completion, in `enroll_cb` via `store.print_data_save`. So an
enrolment into an occupied slot that is abandoned or fails leaves the slot
**empty**, and that is how the 6/6 print of 2026-11-01 was lost at 17:16:23:
the calibration logged `Scoring against — Right index` until 17:16:17 (so it
existed), the enrolment started at 17:16:23, produced no stage and no journal
line, and nothing has been enrolled since. Not a manual delete — that path
removes the hyprlock block, which is still live with `enabled = true`. The
window had said enrolling *"OVERWRITES"* the slot, which reads as *on success*;
it now names both source calls and says the deletion happens at the start. ⚠
Remaining live state: **zero prints**, hyprlock switch still **on** — a pairing
the panel's own delete path forbids. `pam_fprintd` is `sufficient` and with no
print falls straight through, so `sudo` no longer waits on the reader. ⚠ Not
hardened further: a confirmation dialog for an occupied slot is the obvious
next step and was **not** built unasked. §20m, §20v

### The same-press gate was eating driver faults, lockout included

✅ **Resolved 2026-11-03 (§20v).** §20s's *"is this a new press?"* gate
(`if unmoved and quiet:`) was written for placement evidence and never
excluded bucket `driver`. In a real 32 s session **every** suppression was a
`verify-disconnected` — the gate caught no repeat press at all. It told the
user to lift a finger off a reader that had stopped reading; it kept `_cal_dry`
at zero so `MAX_CAL_DRY` could not fire; and ⚠ it **hid the thermal lockout**,
whose check lives in the terminal `driver` branch below that `return`, so a
§20t cooldown with a finger resting on the pad would have spun for the whole
215 s saying *"lift the finger clear"* and never entered it. Invisible to 246
assertions because every existing test of the gate fed it a placement result.
Fixed with `placement = bucket != "driver"` gating both suppression branches
**and** the press-evidence reset — a fault measured no press, so it must not
spend the evidence that one happened. Driver faults now reach the tally, so a
storm is visible instead of hidden behind a single *"Same contact"* line.
`test-enroll.py` 246 → **261 assertions**. §20s, §20t, §20v

### The panel scored an untouched pad every ten seconds

✅ **Resolved 2026-11-03 (§20u).** `elan` arms each capture with
`ELAN_CMD_TIMEOUT 10000` and needs `ELAN_MIN_FRAMES 7` frames to call it an
image, so an **untouched** pad times out every 10 s and libfprint renders that
as `FP_DEVICE_RETRY_TOO_SHORT` → `*-swipe-too-short` — bucket `rejected` in
this panel, so ten of them filled the whole `CAL_WINDOW` per 100 s of reading
the screen and the gate announced **"Captures are too thin"** about a hand that
was never there; on the enrol side the repeats counter turned three of them
into *"the driver may simply not handle this sensor"*. Found by §20t, which
**deliberately did not act on it** — whether a `rejected` result with no
reported contact means *"nobody touched"* or *"this reader cannot report
contact"* was decided by one unrun measurement, and reversing §20s's choice on
an inference is exactly how §20r became §20s. `./fp-debug.sh presence` was then
run: **four real touches reported `finger-present` before their result, both
phantoms reported none**, spaced 10.17 s and 10.03 s; the journal is a second
witness, logging `Failed to detect minutiae` for a real short capture and
**nothing** for a phantom. So the rule moved on a measurement: a
`*-swipe-too-short` with no presence ON edge since the last accounted-for
result is kept out of the window, tally, attempt count and strip in **both**
paths, and the count is shown on the live tally line instead of in the log,
which is written once. ⚠ The one device fact this needed is
`PRESENCE_SENSORS` — *"this reader publishes `finger-present`"* keyed by **USB
id**, like `AREA_SENSORS`, because `ContactStrip.supported` only learns on the
first touch and the phantoms that matter land before it; a reader in neither
set keeps §20s's behaviour, escape hatch and all. Trade stated: §20j's
wall-clock escape no longer covers these two strings on a known reader, costing
one uncounted reject out of ten if a genuine sub-7-frame tap ever emits no
presence. `test-enroll.py` 200 → **246 assertions**. Same run settled two more
things: a `verify-disconnected` at **25 s armed** was `PROTO`, not the lockout,
and recovered on the next arm 1.1 s later — rule 5 live, and `_looks_thermal`
correctly declined it; and **three of four real touches failed as
`verify-no-match`** with minutiae extracted, so verify is now 7/7 failures and
the remaining problem is the **template**, not detection. §20t, §20u

### Fingerprint unlock dies ~3 min into every lock

⚠ **Open 2026-11-03.** The reported *"brechas en la toma y detección"* is a
**clock**, measured with a new no-finger instrument (`fp-debug.sh thermal`):
libfprint carries a **time-based thermal model** — `DEFAULT_TEMP_HOT_SECONDS
(3 * 60)` / `DEFAULT_TEMP_COLD_SECONDS (9 * 60)`, a duty-cycle estimate with no
thermometer in it — and **an armed verify counts as use even while it waits for
a finger**. One `VerifyStart`, pad untouched, `finger-present` never reported
once: cut off at **180.1 s** with `FP_DEVICE_ERROR_TOO_HOT`, every re-arm then
refused in **0.0 s**, usable again between **180 s and 212 s** after the trip
(the model predicts 205 s). Under continuous arming that settles at roughly
**2 min alive / 3.5 min dead**. fprintd 1.94.5 then **throws the distinction
away**: `verify_result_to_name()` maps `TOO_HOT`, `PROTO` **and** `REMOVED` onto
the same `verify-disconnected` string (enrol side: `enroll-disconnected`), and
it publishes no `temperature` property — so **no D-Bus client can tell a
cooldown from a protocol error from a real unplug**, and only
`journalctl -u fprintd` can. ⚠ That makes §20m's reading of
`verify-disconnected` correct for its own journal but **incomplete**: read the
journal line, never the string. hyprlock arms **one** verify at lock and leaves
it armed (`retry_delay` is used only on `verify-no-match`), reads
`verify-disconnected` as `MATCH_DISCONNECTED` → *"Fingerprint device
disconnected"*, sets `abort`, **never re-arms** (only a suspend/resume does) and
**skips `releaseDevice()`**, so the claim is held until the process exits —
corroborated by `fprintd.service` deactivating 30–41 s after each hyprlock
death. Therefore **every lock returned to more than ~3 minutes after it started
has no fingerprint before a hand is anywhere near the pad**, while
`ready_message = (Touch finger to unlock)` keeps inviting the gesture; hypridle
locks at `timeout = 300`, so those are exactly the locks that matter, and the
ones that ever seemed to work were unlocked inside the budget. ⚠ Upstream
hyprlock `main` is identical — no too-hot case, no backoff, no stop when the
display blanks — so waiting for a release is not an option. The same no-finger
run exposed a second artefact: **`verify-swipe-too-short` every 10.0 s on an
empty pad**, 17 of them before the trip — the driver's own
`ELAN_CMD_TIMEOUT 10000` with `ELAN_MIN_FRAMES 7`, i.e.
`FP_DEVICE_RETRY_TOO_SHORT`, a retry (`done = False`) that leaves the verify
open. In the panel that string is bucket `rejected`, so it appended a `False`
to the rolling window every ten seconds and **"Captures are too thin" could be
announced about a pad nobody had touched** (`ContactStrip.supported` stays
`None` until a presence property is seen, so §20s's lift gate is never even
reached) — and its hint, *"Stay on the sensor longer"*, is advice built from a
result the hardware emits with no contact at all: rule (1) of `../CLAUDE.md`
again. ⚠ **The counting rule was deliberately NOT changed**: whether such a
result means "nobody touched" or "this reader cannot report contact" is decided
by `./fp-debug.sh presence`, **still unrun** since §20s, and reversing §20s's
choice on an inference is exactly how §20r became §20s — *`presence` was then
run the same day and answered "nobody touched", 4 real touches with presence
against 2 phantoms without; the rule moved in §20u.* **Applied instead:**
`fp-debug.sh thermal` (no sudo, no finger, no fprintd restart — a restart would
reset the model being measured); the panel **reads `journalctl -u fprintd`** for the real error name and
falls back to the session's cumulative **armed** time or an instant refusal
only when the journal cannot tell, keeps it out of
`MAX_CAL_DRY` and `MAX_DRY_RESTARTS`, **waits the cooldown out with a countdown
instead of re-arming into a spin** (while hot, §20s's always-re-arm rule turns
every instant refusal into another arm), shows the armed budget from the first
second, warns once before the budget runs out, says an enrolment has to **fit
inside three minutes** (the 6/6 run of §20l took ~54 s — that it was under
budget was never noticed as one of its conditions), and **no longer sends anyone
to `fp-debug.sh rebind` for a cooldown**; `*-disconnected` copy now names all
three causes. `test-enroll.py` 154 → **200 assertions, all passing**; widget
construction re-smoke-tested for an occupied and a free slot. Nothing in the
live configuration was changed — `hyprlock.conf` is untouched, password auth
stays on, `pam_fprintd` stays `sufficient`, so there is still no lockout path.
⚠ Also seen, **correlated and not explained**: hyprlock **segfaulted three
times** on 2026-11-03, all in locks where the trip had already fired, each with
`ip` equal to the fault address and a single-frame stack (a jump through a
pointer that is not code) — the mechanism worth testing first is hyprlock's own
`addTimer(RETRYDELAY, …, this)` on the no-match path firing during teardown.
**Not backtraced**; no session exposure either way, since Hyprland keeps the
session locked if its locker dies. Ranked options, none of which has been
applied beyond the two free ones: keep every session under ~2.5 min; turn the
hyprlock switch off until a locker-side fix exists; patch hyprlock (a 2-minute
scan window plus backoff, the shape another locker already merged — reverts on
`paru -Syu`, but password auth is untouched so the blast radius is far smaller
than §20q's libfprint patch); read the real error back from the journal;
⚠ `temp_hot_seconds = -1` for `elan` as the match-on-chip drivers are *said*
to do — secondary source, needs a patched libfprint, and removes a protection
whose physical basis here is unknown. §20t, §20u

### Fingerprint reader never used

✅ **Resolved 2026-11-01 — `right-index-finger` enrolled.** Wired 2026-10-31; enrolment then failed for three sessions and was wrongly diagnosed as a hard driver block — the **ELAN `04f3:0c4f`** reader is bound by libfprint's in-tree **`elan`** driver (not `elanmoc`: the reported name *ElanTech Fingerprint Sensor* is `elan`'s `full_name`) and `fprintd 1.94.5`/`libfprint 1.94.100` were already installed; `fprintd-list` answered *ElanTech Fingerprint Sensor* (`swipe`, 6 enroll stages). Nothing worked only because **no finger was ever enrolled**. Two things already existed: `chwd` had put `auth sufficient pam_fprintd.so` in `/etc/pam.d/sudo`, and hyprlock 0.9.6 drives fprintd **over D-Bus itself** (`auth:fingerprint:*`), so unlocking needs **no PAM edit** — which is the whole lockout risk avoided. There is nothing else to unlock: this machine boots via `getty@tty1` autologin with no display manager, so hyprlock is the only gate. Triton Panel gains a **Fingerprint** group — sensor, enrolled list, finger picker + Enroll, Delete, an *Unlock hyprlock with fingerprint* switch writing a marker-delimited block in `hyprlock.conf` (not a `source`d file, so no Hyprland auto-reload), and a read-only `sudo` row it never edits. Guards: Claim→EnrollStart→EnrollStop→Release on every path incl. `close-request` (a leaked claim leaves the next `Super+L` without fingerprint); the switch refuses to enable with zero prints; it refuses to touch `hyprlock.conf` if that file already has its own `auth` block. **2026-11-01 — enrolment cannot succeed.** Every attempt dies with `The driver encountered a protocol error with the device` + `No minutiae found`; **not one** `too-short`/`too-fast`, i.e. `FP_DEVICE_ERROR_PROTO`, not technique. The panel's polkit→Claim→EnrollStart path is proven healthy by the same journals. `04f3:0c4f` is listed upstream under `elan` but field reports for the family are negative and the sibling `04f3:0c4b` has the identical documented symptom — the driver claims the id and speaks an older protocol than the sensor. USB autosuspend was tested and **ruled out** — an open fd pins the device `active` and libfprint holds it open for the whole claim, so it cannot suspend mid-enrolment (don't add a `power/control=on` rule; one was written and deleted). That leaves one lead: a TOD driver covering `0c4f`, and none was found as of this date. Meanwhile Triton Panel gained a dedicated **enrolment window** that classifies every result as gesture/driver/fatal, charts `finger-present` contact against each outcome, and mirrors the attempt log to stderr — which is how this was diagnosed at all. **Second pass the same day (§20j)** added two journal lines §20g lacked: `Internal state machine issue: transition from FPI_IMAGE_DEVICE_STATE_AWAIT_FINGER_ON to FPI_IMAGE_DEVICE_STATE_AWAIT_FINGER_OFF should not happen!` — an **invalid** transition per libfprint's own table, i.e. `elan` reporting the finger gone while libfprint was still waiting for it to arrive — and `Failed to detect minutiae: No minutiae found`, which proves an image **is** assembled and handed to NBIS sometimes, so the capture path is not uniformly dead and §20g's "no gesture changes that" is too absolute as a blanket claim. Also established: the **lift between stages is mandatory** — the image-device cycle `AWAIT_FINGER_ON → CAPTURE → AWAIT_FINGER_OFF → IDLE` will not start the next capture until the driver reports the finger gone, and a finger left resting stalls the run with no message — which the enrolment window never said; fixed with `EnrollWindow._cycle_hint()`, derived from `scan-type`, matching fprintd's own *"Lift then touch again"* for a passed stage. Reference clients read and compared (`fprintd-enroll`, `cc-fingerprint-dialog.c`, hyprlock): all react only to `EnrollStatus`, `EnrollStart` is called **once** for the whole enrolment, there is no per-stage method, and `finger-present` is display-only — so the lift/place cycle is owned by libfprint, not by any UI. That hypothesis — a **press/area sensor driven as a swipe sensor**, from upstream's analysis of the sibling `04f3:0903` — was then **confirmed against this chassis**: the part is a ~1 cm square pad in the corner of the touchpad, so `scan-type = swipe` is **wrong**, not just unconfirmed, and `No minutiae found` follows directly (a press on an area pad gives `elan`'s multi-frame motion assembly no displacement to stitch). Consequence in the panel: `AREA_SENSORS` keys the physical type by **USB id**, `fprint_device()` exposes it as `info["gesture"]`, and all seven instruction sites plus `hyprlock_set()` build from `gesture` (`Touch finger to unlock`, not `Swipe`) while `scan_type` stays visible as the driver's claim; §20d, which asserted the verb should come from `scan-type`, was corrected. Nothing was enrolled and the switch was off, so no block with the wrong verb ever reached disk. **Third pass (§20k):** the first press-gesture run captured **8 images in 85 s** (vs 1 in the whole morning of swipes) and had **0 accepted** — too few minutiae on a ~1 cm pad, so the blocker moved from "nothing is captured" to "what is captured is too thin to count". Each session was being ended by `enroll-unknown-error`/`done = True` (fprintd's `enroll_cb` on a non-retry error), **not** by the `enroll-retry-scan` it appeared to be, and the old code released the claim so every retry cost another polkit password. The enrolment window now restarts itself — `EnrollStop` + `EnrollStart` with the claim kept, before `_stop()` so the `g-signal` subscription survives — capped by `MAX_DRY_RESTARTS = 3` (a wedged endpoint faulting with no finger contact → points at `fp-debug.sh rebind`) and `MAX_RESTARTS = 15`; `fatal` results are never restarted. New regression test `triton-panel/test-enroll.py` (40 assertions, stubbed widgets + D-Bus). **Fourth pass (§20l) — it enrolled.** 10:30:27–10:31:21, ~54 s: **2** `No minutiae found`, **0** protocol errors, **6/6** accepted. No driver changed, no TOD installed — `libfprint 1.94.100` + the in-tree `elan` driver, exactly what §20g called incapable. The two instruction corrections made earlier the same day (press verb from the physical sensor type; the mandatory lift between stages) are **necessary but not shown sufficient**: they were already in place for the 10:19 run that got **0 of 8**, and the 6/6 run was the *same binary* plus §20k's restart loop, which never fired because that run had no protocol errors at all. What differed between 0/8 and 6/6 is **not recorded** — coverage/dwell converging, finger condition, or device state after that morning's fifth `fprintd` restart, none distinguishable after the fact. Enrolling a second finger is the reproducibility test. The restart loop earns its place regardless: before it, every protocol error ended the run and cost another polkit password. §20g's inference — *"no `too-short`/`too-fast` ⇒ not a gesture problem"* — was the error: on an area pad driven as a swipe sensor the gesture failure surfaces as `No minutiae found` → `enroll-retry-scan`, a line that was in §20g's own quoted journal and got filed under the driver story; that conclusion then became a `../CLAUDE.md` rule which blocked the fix for three sessions. `FP_DEVICE_ERROR_PROTO` is **intermittent, not blocking**. Downstream now live: `pam_fprintd` in `/etc/pam.d/sudo` works from the moment a print exists — ⚠ its prompt comes from the driver's `scan-type`, so `sudo` says *"Swipe…"* when the pad must be **touched**; it is `sufficient`, so Enter still falls through to the password. The hyprlock switch was enabled 10:31:40 and the managed block is live + mirrored. ⚠ **Fifth pass the same day (§20m) measured *verify* for the first time: it fails 4/4** — 2× `verify-no-match`, 2× `verify-retry-scan` → `verify-disconnected`, **zero** matches against the finger the template was enrolled from. Three things follow. (a) `verify-disconnected` is **not** a disconnect: the sensor enumerated once this boot (`usb 3-9`, 11:21:50) with no disconnect, reset or `xhci` error after it — including across an s2idle — and every instance pairs with an `FP_DEVICE_ERROR_PROTO` line at the same second, so it is rule (3)'s intermittent protocol error under a misleading name; **don't chase USB power management**, already ruled out in §20g. (b) The enrol/verify **error asymmetry** is what makes the feature unreliable: §20k's restart loop absorbs a protocol error during enrolment, but at verify hyprlock maps it to *"Fingerprint auth disabled (unknown error)"* and stops offering the fingerprint for the rest of that lock — 2 of 4 runs hit it. (c) `No minutiae found` dominates and is still a capture result (rule 2), because **verify is strictly harder than enrol**: enrolment stitches 6 accepted captures into the template, verify gets **one** per touch — the ~1 cm small-sensor limit of §20k showing up on the read side. A driver swap is **not** available: `elanmoc` (match-on-chip) is in `libfprint 1.94.100` but `04f3:0c4f` is in the **`elan`** image-driver table and the live device reports `has_storage = False`, i.e. host-side NBIS matching — probed, not inferred. Also corrected: a probe returned `get_nr_enroll_stages() = 5` against the recorded **6**; fprintd's D-Bus `num-enroll-stages` says **6** and is authoritative — the 5 came from reading the property on a device only *enumerated*, never *opened* (libfprint finalises it at open), so **don't "correct" the 6**. Next step is additive and must stay that way: enrol a **second** finger (`fprintd-enroll -f left-index-finger`) — the reproducibility test §20l already asked for — and re-run `fprintd-verify` with no `-f`, which tries every enrolled template; ⚠ **do not delete `right-index-finger`** to do it. Nothing in the configuration is missing — every link was verified — what is missing is a template that matches; password auth stays on in hyprlock and `pam_fprintd` is `sufficient` in `sudo`, so there is no lockout path. The enrolment window's pre-emptive driver banner and `ELAN_PROTOCOL_MISMATCH` were deleted as disproven. Still unrun: enrolment through `fprintd-enroll` with `G_MESSAGES_DEBUG=all`, the only test that separates "panel" from "driver" and shows frame counts — script and read-out table in §20j. **Sixth pass the same day (§20o) — the panel stops treating "enrolled" as the goal.** The failure of 2026-11-01 was a 6/6 enrolment whose template matched nothing while **every number in the enrolment window read as success** — they were all *enrolment* signals, and enrolment passing says almost nothing about matching. `EnrollWindow` gained a **calibration phase** that runs first: `VerifyStart("any")` in a loop, bucketing each attempt as **scored** (`verify-match`/`verify-no-match` — an image was produced *and* minutiae extracted, so the matcher ran), **rejected** (the capture never reached the matcher) or **driver**. That split is the point: a high scored rate with `no-match` every time is evidence about the **template** (H1), not the placement, and is the only case where re-enrolling is worth doing; a low scored rate is placement or the small-sensor ceiling (H2), where re-enrolling would just build another unmatchable template — so the window says exactly that and labels the button *"Enroll anyway"* instead of recommending it. Driver faults are **kept out** of the rolling window, because counting them would blame the hand for something it cannot fix — the §20g conflation again. Gate: ≥10 attempts and ≥8 of the last 10 scored, **rolling** so a converged placement is not dragged down by the fumbling at the start, and **not configurable** (a knob invites tuning until it passes, which would make the measurement worthless). The enrol phase then opens with *"use the SAME placement that passed calibration on every stage"*, since a template stitched from six different parts of the finger is precisely what one verify capture cannot match. Calibration **writes nothing** — verify neither enrols nor deletes — and the window now warns that enrolling into an **occupied slot overwrites** it, pointing out that the slot name is only a **label**, so a free slot can hold the same physical finger (the non-destructive fresh-template path). fprintd's state machine is honoured: `VerifyStop` is required before the next `VerifyStart` once a status arrives with `done = True` — and **both** match and no-match are `done = True` — while a retry is `done = False`, leaves the verify open, and must **not** be cycled; that asymmetry is invisible from the UI and is the first thing the regression test asserts. No restart ceiling (it is a deliberate loop) except `MAX_CAL_DRY = 4` consecutive faults with no contact between them → `fp-debug.sh rebind`. `VerifyFingerSelected` is logged as info, never as an attempt. `test-enroll.py` is now **81 assertions, all passing** (was 40); a smoke test of real widget construction caught a crash the stubs could not see — `_calibration_card()` painted buttons that the bottom bar had not built yet. Deployed to `~/.local/bin/triton-panel`. ⚠ **A real sensor session is still unrun**: all of the above measures the panel, not the hardware. `fp-debug.sh` also gained a `verify` mode (§20n) for the per-capture minutiae counts, and ⚠ `pam_fprintd` now makes **every `sudo` wait on the reader** (~30 s, prompt says "Swipe", it is `sufficient` so Enter falls through) — hit for real while inspecting `/var/lib/fprint`. **Seventh pass (§20p): a Test button.** The group could enrol, delete and switch hyprlock on, and could not answer the question §20m made the important one — *does a stored print actually match?* **Test a stored print** runs a one-shot `Claim` → `VerifyStart("any")` → `VerifyStatus` → `VerifyStop` → `Release` and puts the verdict in the row's subtitle, naming the matching finger from `VerifyFingerSelected`; `any` is what `fprintd-verify` does and hyprlock's binary carries the same literal (visible only with `strings -n 3`). The hazard it is built around is the **claim**, not the verdict: fprintd grants one at a time, a leaked claim leaves the next `Super+L` with no fingerprint, and a verify nobody touches never ends — so it releases on the result, on Cancel, on Cancel pressed while polkit is still up (released in the claim callback, since the claim is granted server-side anyway), on the window closing, and on a hard 30 s timeout, which is a correctness requirement rather than a nicety. A no-match reports *the stored print, not your finger*. `test-enroll.py` 81 → **115 assertions, all passing**. ⚠ **A defect in §20o's own work, reported and fixed the same day:** the **Stages** card went inert, because the calibration card was added without deciding who owned the shared status labels — `status_label`/`hint_label`/`tally_label` had always lived *inside* the Stages card while being used as the window's *global* status surface. So a calibration retry message rendered under a heading about enrolment stages, the pills sat frozen at `0 / 6` with nothing saying why, `cal_tally` was collected from the first version and **rendered nowhere**, and the idle hint still said *"Press Start"* — a button calibration had split in two. Fixed by separating the surfaces: status and hint moved to the window's own headline above the cards; a new `stages_note` says why the pills are idle (the card is **not** hidden — one that appears and vanishes makes the window jump exactly when the user is watching their hand); a new `cal_tally_label` renders the calibration breakdown; `count_label` shows `— / 6` when no enrolment is running, so a dash means *not applicable* and a zero means *started, none accepted*. Third instance of one bug class — a paint method running before the widgets it paints exist — and all three were caught by a real construction smoke test, never by the stubs. ⚠ Still unrun against a real finger — the first press of Test is also the first time this panel's live verify path meets the daemon. **Eighth pass (§20q): §20o's enrolment advice was backwards.** Enrolment was still hard, so other projects were read for ideas — and the most useful finding was in libfprint itself. An enrolled NBIS print is **not one merged template**: it is a `GPtrArray` of per-stage minutiae sets (`FpPrint` exposes `fpi-prints`, plural; `fpi_print_add_print` appends one per stage) and `fpi_print_bz3_match` loops over **every** stored set, returning on the **first** to clear the bz3 threshold — **one-of-N, not a composite**. So six identical placements waste five of the six slots, while six *different* regions are six independent chances for one verify capture to overlap one of them, which on a ~1 cm pad is the difference between a matchable template and an unmatchable one. §20o had said to use the **same** placement every stage, conflating the `elan` driver's frame stitching **within** a capture (§20j) with how libfprint stores stages **across** an enrolment — the same layer-confusion as §20g, and the wrong sentence is kept struck-through in §20o rather than deleted. The panel now has `ENROLL_REGIONS` (centre, higher, lower, rolled left, rolled right, centre held longer) and names the next region after every accepted stage, indexed modulo the list and capped at the device's own stage count; `test-enroll.py` **130 assertions**. Also established: the **bz3 threshold is 40**, runtime-settable by a driver via `fpi_image_device_set_bz3_threshold()` (symbol present locally) — so `verify-no-match` means *scored below 40*, and lowering it is the most direct lever on matching, at a false-accept cost and only via a patched libfprint. Ideas gathered from forks, ⚠ **ranked by verification and none applied**: `FP_SCAN_TYPE_PRESS` for elan (two sources claim it, neither diff readable), image-based presence detection, a **SIFT matcher** replacing bozorth3 (which would remove the minutiae floor entirely), and 12 enrol presses — the last three from one fork's README with no code read. No fix exists for `04f3:0c4f` specifically. ⚠ All of those need a **patched libfprint**, which sits behind both `pam_fprintd` in `sudo` and hyprlock, reverts on `pacman -Syu`, and was deliberately **not started**; rollback is the cached package. **Ninth pass (§20r): calibration was measuring the panel's own loop.** Reported as *"sale mucho 'captures are too thin', **y yo no retiro el dedo**"* — and that second clause was the diagnosis. The journal shows **44 s** of `No minutiae found` / protocol error alternating every 1–3 s: every `VerifyStatus` with `done = True` (protocol errors included) re-armed the verify **immediately**, each fresh `VerifyStart` captured the **same resting finger**, each garbage image appended another reject to the rolling window, and ten of those filled it in ~20 s from **one contact** — so the gate announced "Captures are too thin" about a placement made once. ⚠ `MAX_CAL_DRY` did **not** trip and was right not to: it counts driver faults with *no* finger contact, a wedged endpoint; this was the opposite case and nothing guarded it. Fixed by re-arming on the **lift**, which is what libfprint's own image-device cycle waits for (`AWAIT_FINGER_OFF`, §20j): a result with no lift since the last counted one is not a measurement — `cal_log` and the tally untouched, no `VerifyStart`, status *"Lift the finger clear"*, logged once per contact. A reader that never reports `finger-present` is **not** gated (no lift to wait for), and `CAL_REARM_MS = 3000` re-arms regardless since §20j recorded this driver mishandling the lift — that path logs `Re-armed by timer` so it stays distinguishable. ⚠ The trap that hid all of it: `close_open_contact()` is called artificially on **every** result, so a dozen results from one unbroken press each carried a plausible-looking contact duration — the lift is now hooked on the real `finger-present → False` transition instead. Also fixed: a second `_stop()` after `_idle_buttons()` found `phase == "idle"`, guessed `EnrollStop`, and made fprintd log *"Device was not claimed before use"* — harmless, but the single most misleading line this subsystem can print, since a claim leak is the failure mode §20p is built around; `_stop` now records `_last_phase` and `_released` and the second call is a no-op. `test-enroll.py` 130 → **154 assertions**, six of them rewritten to model the lift through a `press()` helper. **Tenth pass (§20s): §20r was itself a regression — the device went deaf.** Reported as *"ahora está peor: a veces no detecta mi dedo"*, and the journals prove it: before §20r, events every 1–3 s with ~10 `No minutiae found`; after, gaps of **3/4/5/13/14 s** and **one** `No minutiae found` in 45 s — no verify was armed when the finger arrived, so touches were simply lost in the `CAL_REARM_MS` blackout. The error: §20r **coupled two decisions with opposite failure modes** — a missed *count* is a wrong measurement (recoverable, visible in the tally), a missed *re-arm* is a **lost touch** that makes the hardware look broken. Now the verify is **always re-armed immediately** for every bucket and only the *counting* waits on the lift; `_arm_rearm`, `_on_rearm_timeout`, `_cal_rearm_pending` and `CAL_REARM_MS` are **deleted**, not left dormant. "Is this a new press?" no longer uses the strip's open contact — `close_open_contact()` shuts it artificially on every result, the very trap §20r had named and the first draft of this fix walked back into — but any `finger-present` **transition** since the last counted result (the **ON** edge, which does not depend on the OFF edge §20j recorded this driver emitting *invalidly*) plus a wall-clock escape `SAME_PRESS_S = 2.0` that logs `Counted without a reported lift` so driver-reported and assumed stay distinguishable. Also added: **`fp-debug.sh presence`** — a millisecond-timestamped trace of every presence change interleaved with each `VerifyStatus`, needing no sudo, no drop-in and no fprintd restart (so it sees the daemon in the state the panel meets). ⚠ It is the tool that **should have existed before any of this**: two bugs in a row came from guessing at `finger-present`. ⚠ **Still unrun** — until it is, `SAME_PRESS_S` is carrying the design and whether that is necessary or merely harmless is unknown. *Run 2026-11-03 (§20u): `finger-present` is reliable on this reader in both directions, so `SAME_PRESS_S` is now the escape hatch rather than the mechanism — and the ON edge it was hedging became the discriminator for the 10 s phantoms.* `test-enroll.py` **154 assertions**, with §20r's two tests for the deleted waiting behaviour replaced rather than disabled. §20f/§20g/§20j/**§20m/§20n/§20o/§20p/§20q/§20r/§20s**
