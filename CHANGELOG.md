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
