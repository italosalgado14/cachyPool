# Updates — keeping a rolling release from reverting this machine's fixes

**Machine:** Acer Predator PT516-52s (`triton500se`) · **Written:** 2026-11-03
**Stack:** CachyOS (Arch-based, rolling) · `pacman` 7.1 · `paru` 2.1.0-3 · `snap-pac` 3.0.1-3
**CPU tier:** `x86-64-v3` — the `[cachyos-v3]` repos are the correct ones; `v4` is not supported

This runbook exists because an update is **the only routine operation on this machine that
can silently revert a documented fix**. Not the upgrade itself — the upgrade is one command
— but the three things around it that fail without saying anything:

1. a DKMS module does not rebuild → the 80 % charge cap stops working, and nothing reports it
2. a `.pacnew` is accepted wholesale → a hand-edited line is gone and the file still looks fine
3. a live file drifts from its repo mirror → the docs describe a machine that no longer exists

`../tests/check-live-system.sh` is the mechanical answer to all three. Run it, don't remember.

---

## 1. The procedure

```bash
# ── BEFORE ────────────────────────────────────────────────────────────────────
./tests/check-live-system.sh --strict      # the gate. Must be clean.
checkupdates | wc -l                        # how big is this?
checkupdates | grep -E 'linux-cachyos|nvidia|hyprland|aquamarine|mesa|systemd'

# ── THE TRANSACTION ───────────────────────────────────────────────────────────
paru -Syu                                   # repo + AUR together. Never -Sy, never -S <pkg>.
sudo snapper -c root list | tail -3         # write down the pre-snapshot number

# ── AFTER, BEFORE REBOOTING ───────────────────────────────────────────────────
./tests/check-live-system.sh                # catches a failed DKMS build while the old
                                            # kernel is still running and the session is alive
DIFFPROG='vim -d' pacdiff -s -3       # merge .pacnew (see §2)

reboot                                      # a new kernel requires it

# ── AFTER THE REBOOT ──────────────────────────────────────────────────────────
./tests/check-live-system.sh                # must be clean again
```

~~⚠ **The gate does not pass on this machine yet, and it is right not to.** `--strict` treats
the 12 unmerged `.pacnew` files and the disabled `paccache.timer` as fatal, and both are the
real current state. Clearing them needs root (§2a, §5) and is the one part of this runbook not
yet applied. Until then, run the gate without `--strict` to read the inventory.~~

✅ **`paccache.timer` is enabled** since 2026-11-03 (§5a), so that half is cleared. ⚠ The
other half is not: **11 `.pacnew` files** are still pending after the 2026-11-03 upgrade —
that upgrade added none, they are the audit's own backlog (§2a, §2b). Until they are merged,
run the gate without `--strict` to read the inventory.

⚠ **Between a kernel upgrade and its reboot the gate reports two further FAILs that are the
expected state, not breakage** — the running kernel's DKMS modules and the NVIDIA
module/package pair. Read the Issue history entry below before acting on either; "fixing"
them by installing something is the partial upgrade §1a forbids.

⚠ **The `pacdiff` step may move to after the reboot, and the block's order is not a rule.**
What must come before the reboot is the *checker*, because a failed DKMS build is cheapest to
fix while the old kernel is still running. `pacdiff` only has to precede the **next upgrade**
(§2's gate). Defer it past the reboot when nothing pending is read at boot, which is worth
checking rather than assuming: a `.pacnew` for `/etc/mkinitcpio.conf*`, `/etc/fstab`,
`/etc/crypttab` or anything under `/etc/default/limine` is read at boot and should be merged
first. The 2026-11-03 run deferred it; see the Issue history.

**Cadence: weekly.** This is not a style preference. The 2026-09-26 → 2026-11-03 gap produced
a 648-package queue, 12 unmerged `.pacnew` files and a kernel + NVIDIA + Hyprland + DKMS jump
all in one transaction. Weekly turns that into 40–80 packages you can actually read.

**Never unattended.** No timer, no cron, no `paru -Syu --noconfirm` in a script. The kernel,
`linux-cachyos-nvidia-open`, the DKMS modules and Hyprland all move under a *live session*;
an upgrade you are not watching is how you meet a black screen at the next boot with no idea
which of 600 packages did it.

Automate **noticing**, not applying: a `custom/updates` module in `configs/waybar/config.jsonc`
running `checkupdates; paru -Qua`. Five weeks passed unnoticed because nothing on screen said
anything.

### 1a. Why `-Syu` and never `-Sy`

In any single upgrade the kernel and its out-of-tree NVIDIA module move together and must
land together:

```
linux-cachyos              7.2.8-1   → 7.3.1-1
linux-cachyos-nvidia-open  7.2.8-1   → 7.3.1-1      ← version-locked to the kernel
nvidia-utils          615.71.09-1    → 615.78.08-2  ← userspace, must match the module
```

`pacman -Sy` or `pacman -S <pkg>` refreshes the database and installs *one* thing against it.
That leaves the loaded module and its userspace at different versions, KMS fails, and Hyprland
black-screens — and since `../CLAUDE.md` forbids `nvidia-drm.modeset=1` on the cmdline (KMS
comes from the driver default plus early module loading), there is no cmdline knob to recover
with. `../tests/check-live-system.sh` compares `/sys/module/nvidia/version` against
`pacman -Q nvidia-utils` precisely to catch this state.

For the same reason: **never `IgnorePkg` the kernel or NVIDIA.** A permanent hold on one half
of a version-locked pair is a partial upgrade in slow motion.

### 1b. `paru` configuration

There is no `~/.config/paru/paru.conf` on this machine, so everything is default. Worth having:

```ini
[options]
NewsOnUpgrade      # prints upstream manual-intervention notices during the sysupgrade
CombinedUpgrade    # one refresh, one combined repo+AUR menu, then it runs through
BatchInstall       # queue AUR builds, install them together
SudoLoop           # keeps sudo alive through a long DKMS build
```

`NewsOnUpgrade` is the one that earns its place on a queue this size: it surfaces the
"you must do X before upgrading" notices at the moment they apply, not after.

---

## 2. The `.pacnew` files that carry this machine's edits

A `.pacnew` appears when a package ships a new version of a file **you have modified**. pacman
never overwrites your version — it parks the new one beside it and says nothing more. Accepting
one wholesale is how a documented fix disappears.

> **Gate: the pending `.pacnew` count must be 0 before an upgrade starts.** An unmerged
> `.pacnew` is the previous upgrade's unfinished homework, and twelve of them is not twelve
> postponed decisions — it is twelve fixes sitting unguarded. `../tests/check-live-system.sh`
> checks this and `--strict` makes it fatal.

Use `pacdiff`, never `mv`:

```bash
DIFFPROG='vim -d' pacdiff -s -3
```

`-3` is a three-way merge: it pulls the **original** version of the file out of
`/var/cache/pacman/pkg` and shows you base / yours / theirs, which turns "which hunk is mine?"
from archaeology into reading. It only works while the original package is still cached — see
§5 for why `paccache -k3`, not `-k1`.

Two things about the invocation, both learned the hard way on 2026-11-03:

* **`-s` means pacdiff escalates per operation, so do not prefix it with `sudo`.** Running
  `sudo … pacdiff -s` escalates twice and buys nothing.
* **The editor is `vim`. `nvim` is not installed on this machine** (`vim`, `nano`, `micro`,
  `kate`, `code` are), and `vim -d` is also pacdiff's own default, so `DIFFPROG` can be dropped
  entirely. `MERGEPROG` defaults to `git merge-file -p` and git is present.

pacdiff prompts per file: `(V)iew, (M)erge, (S)kip, (R)emove, (O)verwrite, (Q)uit`. **M** keeps
your line and takes theirs; **R** discards the `.pacnew` and keeps your file as-is; **O** takes
theirs wholesale.

⚠ **`M` needs a package version *older* than the installed one in the cache**, because that is
the common ancestor your edited file derives from. With only one version cached, pacdiff answers
`Unable to find an older package to base merge on` and `M` is simply unavailable — checked
2026-11-03: all four files in §2a have a base (`pacman` ×2, `sudo` ×2, `limine-snapper-sync` ×4,
`glibc` ×3), and the two that have none are `cachyos-*-mirrorlist` and `filesystem`, which are
`R` cases anyway. This is the concrete reason for `paccache -k3` over `-k1` in §5a: pruning to
one version silently removes the merge base for every future `.pacnew`.

⚠ Every escalation in that session hits `pam_fprintd` first — the prompt says *"Swipe your
right index finger"*, the pad must be **touched**, and verify currently fails (`fingerprint.md`
§20m). It is `sufficient`, so **press Enter immediately** to fall through to the password
instead of waiting out the reader each time.

### 2a. Known deltas — the lines that must survive

| File | Keep (ours) | Take (theirs) |
|---|---|---|
| `/etc/pacman.conf` | `[cachyos-v3]`, `[cachyos-extra-v3]`, `[cachyos-core-v3]`, `[cachyos]`, `[multilib]`, `ParallelDownloads = 10`, `ILoveCandy`, `VerbosePkgLists`, `DisableDownloadTimeout` | `CheckSpace` — currently commented out here, and worth enabling |
| `/etc/pam.d/sudo` | `auth sufficient pam_fprintd.so # chwd-fprintd` — fingerprint `sudo`, put there by `chwd` | `session optional pam_systemd.so class=none` |
| `/etc/limine-snapper-sync.conf` | `MAX_SNAPSHOT_ENTRIES=8` | `EXCLUDE_SNAPSHOT_ENTRIES="Windows*, windows*"` |
| `/etc/locale.gen` | `en_US.UTF-8 UTF-8` (enabled by Calamares at install) | nothing |

Dropping the `[cachyos-*-v3]` sections is the quietest of these failures: pacman keeps working,
nothing errors, and the machine simply stops receiving `x86-64-v3`-optimised packages. There
is no message. The only symptom is that `pacman -Si <pkg>` starts answering `extra` instead of
`cachyos-extra-v3`.

### 2b. Files to **delete**, not merge

| File | Why |
|---|---|
| `/etc/pacman.d/mirrorlist`, `cachyos-mirrorlist`, `cachyos-v3-mirrorlist`, `cachyos-v4-mirrorlist` | `cachyos-rate-mirrors.timer` is **enabled** and regenerates these weekly. The packaged list is stale by definition. |
| `/etc/resolv.conf` | NetworkManager writes this at runtime (`nameserver 127.0.0.53`). The `.pacnew` is the empty stock stub. |
| `/etc/tpm2-tss/fapi-profiles/*.json` | `tpm2-tss` is installed only as a dependency of `fwupd`/`gnupg`/`libsecret`; the FAPI profiles are unused here. Accept them. |

`cachyos-v4-mirrorlist` is irrelevant on this CPU in either direction — this machine is
`x86-64-v3`.

### 2c. `/etc/systemd/system.conf` — the delta is already dead

⚠ **Corrected 2026-11-03.** This file was previously believed to carry the Thunderbolt
shutdown-hang fix as `DefaultTimeoutStopSec=15s`. It does carry that line, and **the line has
no effect**:

```
$ systemd-analyze cat-config systemd/system.conf
# /etc/systemd/system.conf
DefaultTimeoutStopSec=15s                      ← ours, overridden
# /usr/lib/systemd/system.conf.d/00-timeout.conf
DefaultTimeoutStopSec=10s                      ← cachyos-settings, wins

$ systemctl show -p DefaultTimeoutStopUSec --value
10s
```

Any drop-in under a `system.conf.d/` directory overrides the main `system.conf`, including a
**packaged** one under `/usr/lib/`. `cachyos-settings` ships `00-timeout.conf` and it wins.

Two consequences, and they point opposite ways:

* **The outcome is fine.** 10 s is stricter than the 15 s that was asked for, so the shutdown
  hang that `boot-suspend.md` §6 describes stays fixed — by CachyOS, not by us.
* **`/etc/systemd/system.conf.pacnew` is therefore safe to accept wholesale**, because the only
  line it removes is already inert. It leaves the known-delta table above.

If this machine ever needs a timeout value of its own, it must go in
`/etc/systemd/system.conf.d/10-triton.conf` — the `/etc/` drop-in tier is the only one that
beats a packaged drop-in — and be mirrored at `configs/systemd/system.conf.d/`, the pattern
`configs/systemd/logind.conf.d/` already uses. Editing `system.conf` directly cannot work.

---

## 3. Moving premises

Some open items in `../ACTUAL-CONFIGURATION.md` §15 are not waiting on an idea. They are
waiting on a **version**, and an upgrade moves that version without telling anyone. The
premise shifts, the recorded conclusion stays, and the note quietly becomes wrong.

Check this list after any upgrade that touches the named package.

| Item | Premise | Moves when |
|---|---|---|
| i915 NULL deref in `__gen8_ppgtt_clear`; Firefox hardware decode paused in `user.js` | found on kernel **7.0.12** | ⚠ **moved, and three times unobserved**: 7.0.12 → 7.2.8 → **7.3.1, running since the 2026-11-04 reboot**. The premise is two kernels old and the `user.js` pause has never been retested against it → `gpu-video.md` §12 |
| `hyprpaper.conf` must use block syntax | parser bug in hyprpaper **0.8.4** | ⚠ **moved: `hyprpaper 0.8.5-3.1` is installed** and has been running since the 2026-11-04 reboot. Flat `wallpaper =` lines were never retried against it, so the workaround now rests on a version that is no longer here. Retry one flat line before calling the block syntax a requirement → `../ACTUAL-CONFIGURATION.md` §15 |
| hyprlang → Lua config | deprecated upstream since Hyprland **0.55** | ✅ **arrived and done** — 0.57.1 removed the parser outright; migrated 2026-11-03 and **cold-boot verified 2026-11-04**. See §4 |
| The LTS entry has never been boot-tested | `linux-cachyos-lts` **6.18.52** | ⚠ **moved: `6.18.55-2` is installed**, modules present in `/usr/lib/modules`. Upgraded on every cycle and still never booted once — the escape hatch is three versions past the one the note was written for → `boot-suspend.md` §0 |
| NVIDIA GSP "Reset required" after s2idle resume | driver **615.71.09** | ⚠ **moved: `615.78.08` is running**, module and `nvidia-utils` in parity since the 2026-11-04 reboot. No suspend has been taken on it yet, so the recorded conclusion describes a driver that is no longer loaded and the retest is owed → `boot-suspend.md`, *Issue history* |
| Fingerprint verify fails 4/4; a patched `libfprint` was considered and not started | `libfprint` **1.94.100** | ✅ **did not move** — `1.94.100-1.1` survived the 662-package upgrade and is still upstream's newest tag, so `patches/libfprint-elan-0c4f-busy-retry.patch` applies unchanged. A local build is still **reverted by every `-Syu`** → `fingerprint.md` §20q, §20x |

---

## 4. `hyprlang` is gone — the config is Lua ✅ MIGRATED 2026-11-03

**0.57.1 removed the `hyprlang` config parser.** This section spent three sessions as a
pending item whose removal release was "not known". It arrived inside the 662-package upgrade
of 2026-11-03 and was found *after* that upgrade's reboot, by a desktop with no bar, no
wallpaper, no keybinds, one monitor and a stock example config. See §4g for what this section
predicted wrongly, which is the part worth reading twice.

How it presents — the only line that matters is the second one:

```
$ grep '\[cfg\]' hyprland.log
[cfg] Regular config at /home/isalgado/.config/hypr/hyprland.lua
WARN: No config file found; attempting to generate.
```

0.56.2 logged `Lua config not found, using legacy config at …/hyprland.conf`. In 0.57.1 that
fallback **does not exist**: with no `hyprland.lua`, Hyprland writes
`/usr/share/hypr/hyprland.lua` into `~/.config/hypr/` and runs *that*. The whole modular
`.conf` tree is read by nobody, in silence — `hyprctl configerrors` is clean the entire time.

Three measurements that close the question:

* `Hyprland --verify-config -c ~/.config/hypr/hyprland.conf` answers
  `hyprland.conf:2: unexpected symbol near '/'` — even an explicit `--config` goes to the
  **Lua** parser. There is no flag back to hyprlang.
* `strings /usr/bin/Hyprland` no longer contains `using legacy config`. It does contain
  `RIP hyprlang`. The still-linked `libhyprlang.so.2` is only the ABI check
  (`Hyprlang: built against {}, system has {}`).
* `hyprctl keyword <anything>` → **`unknown request`**. Not 0.56's *"keyword can't work with
  non-legacy parsers, use eval"* — the request itself is gone. `hyprctl eval` answers `ok`.

### 4a. The blocker is not the config text

> **Pre-migration analysis, kept as it was written.** It is right about the mechanics
> and wrong about three things — the auto-reload, the missing hotplug events and the
> A/B — all of which §4g records. Read §4c–§4g for what actually happened.

The 13 files under `configs/hypr/` total 485 lines and use five variables (`$mainMod` ×48,
`$term`, `$launcher`, `$browser`, `$filemanager`). That is a mechanical rewrite.

The blocker is in the binary:

```
keyword can't work with non-legacy parsers. Use eval.
eval is only supported with the lua config manager
```

**`hyprctl keyword` does not work under a Lua config.** Every piece of this machine's monitor
and power automation goes through it: `apply_<mode>` and `apply_from_profile`, `edp_mode()` —
the sole owner of eDP-1's refresh rate — and `apply_monitor_tf()`, whose disable→re-enable
cycle is the only correct way to rotate a panel. So migrating is not a config rewrite, it is a
rewrite of `configs/hypr/scripts/monitor-mode.sh` from `hyprctl keyword` to `hyprctl eval`
(`monitors.md` §16, `power-battery.md` §19).

### 4b. What else changes

> **Pre-migration analysis, kept as it was written.** It is right about the mechanics
> and wrong about three things — the auto-reload, the missing hotplug events and the
> A/B — all of which §4g records. Read §4c–§4g for what actually happened.

| Now | After |
|---|---|
| `source = ~/.config/hypr/env.conf` | `require("env")` — **its own scope per file** |
| `$mainMod = SUPER` | `local mainMod = "SUPER"`, and with per-file scopes it must be returned/required, not assumed global. This is the only real *semantic* change. |
| `bind = $mainMod, Return, exec, $term` | `hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))` |
| `general { }`, `decoration { }` | `hl.config({ general = { gaps_in = 5 } })` |
| `windowrule`, `workspace`, `layerrule` | `hl.window_rule({})`, `hl.workspace_rule({})`, `hl.layer_rule({})` |
| `exec-once = …` | `hl.on("hyprland.start", function() hl.exec_cmd(…) end)` |

The modular 8-file split is an **asset** here: `require` gives each file its own scope, so a
Lua error takes out one file instead of the session.

Two things survive the move, both verified in the 0.56.2 binary:

* **Emergency mode** — *"A lua config error resulted in no binds being registered. Emergency
  binds active: SUPER + Q"*. Document this before writing a line of Lua.
* **Auto-reload** — `[lua] file {} modified, reloading`, plus `misc:disable_autoreload`. The
  hazard `../CLAUDE.md` already records (writing a sourced config snaps the screens back to
  boot geometry) applies unchanged.

⚠ **Untested, and it decides how autostart is written:** whether a *reload* re-fires
`hyprland.start`. Today `exec-once` is guaranteed to run once per session, so the daemons in
`autostart.conf` are started exactly once. If a reload re-fires the event, every `hl.exec_cmd`
in that handler runs again and hyprpaper, hyprpolkitagent and elephant duplicate. The A/B in
§4c must check this **before** any `exec_cmd` is put in a `hyprland.start` handler.

And one idea that is **ruled out**: `hl.on` exposes only `hyprland.start` and
`hyprland.shutdown` in the stubs. There are no hotplug events, so `monitor-autoswitch.sh`
cannot become Lua event handlers.

### 4c. What was done — the record

Written fresh against the stub API rather than translated line by line, in the same modular
shape as before (`configs/hypr/hyprland.lua` + `configs/hypr/lua/*.lua`, 13 files). The
entrypoint sets `package.path` from its own location via `debug.getinfo`, which is what makes
`Hyprland --verify-config -c <repo>/configs/hypr/hyprland.lua` verify the **repo's** modules
instead of silently reading the live ones.

| Was | Is |
|---|---|
| `env.conf` | `lua/env.lua` — `hl.env(name, value)` |
| `monitors.conf` geometry | `lua/monitors.lua` — `hl.monitor({output, mode, position, scale})` |
| `monitors.conf` workspace lines | `lua/workspaces.lua` — **per-monitor blocks**, §21 of `monitors.md` |
| `input.conf` | `lua/input.lua` — note `tap_to_click`, not `tap-to-click` |
| `look.conf` | `lua/look.lua` — `hl.config{}`, `hl.curve()`, `hl.animation{}` |
| `windowrules.conf` | `lua/windowrules.lua` — `hl.window_rule({match = {...}, …})` |
| `keybindings.conf` (58 `bind*` lines) | `lua/bindings-{apps,tiling,utilities,clipboard}.lua` (137 binds, 118 described) |
| `autostart.conf` | `lua/autostart.lua` — `hl.on("hyprland.start", …)` |
| — | `lua/qconsole.lua`, `lua/bind.lua` (the description-carrying wrapper) |
| `monitor-mode.sh edp-rate` | `scripts/edp-rate.sh` — same logic, same three guards, applied with `hyprctl eval` |

**Cold-boot measured 2026-11-04.** `hyprctl reload` cannot fire `hl.on("hyprland.start")`
(§4d), so the autostart path is exercised only by a real session start — and 0.57.1's own
upgrade reboot came up on *upstream's example config*, before this one existed. The 09:05 boot
is the first such start this repo has **measured**: `hyprctl configerrors` clean and all
**twelve** `autostart.lua` entries up — elephant (with the `XDG_SESSION_TYPE` push), walker,
waybar, mako, hyprpaper, hypridle, hyprpolkitagent, swayosd, both `wl-paste` watchers,
nm-applet and `power-autoswitch.sh` — with `scripts/edp-rate.sh` resolving 240 Hz off
`BAT1=Charging`. The three that run as `--user` units (elephant, hyprpolkitagent, swayosd)
were checked with `systemctl --user is-active`, the rest with `pgrep`. Whether an interim
logout on 2026-11-03 had already exercised the handler is **not recorded**, so this is the
first measurement, not provably the first occurrence.

The keymap was not ported but **replaced** with Omarchy's, which has itself migrated to Lua
(branch `quattro`, all `.lua`) and therefore served as the reference implementation for this
binary. `../shortcuts.md` §1 holds the map; the cheatsheet is now **generated** from the binds'
own `description` fields, so it cannot drift.

### 4d. Gotchas found while doing it

* **`hyprctl reload` does NOT re-fire `hl.on("hyprland.start")`.** §4b flagged this as the
  untested question that decides how autostart is written; the answer is the *opposite* of
  the risk feared. Nothing duplicates — but nothing restarts either, so after a push the
  daemons must be started by hand or the session logged out.
* **A write to a `.lua` does not reload anything.** Measured on a module and on the
  entrypoint: the log does not move. See §4g.
* **A wrong config key is accepted in silence.** `/usr/share/hypr/stubs/hl.meta.lua` is
  generated from the running binary and is the only ground truth; its `HL.ConfigKey` list is
  where the dash-to-underscore renames show up.
* **The dispatchers are declared untyped** (`fun(...)`), so an uncertain one is cheapest to
  test with `hyprctl eval` against the live session. That is how
  `hl.dsp.window.set_prop({prop = "alpha"})` turned out to answer *Invalid prop name* — the
  per-window transparency toggle goes through `hl.dsp.window.tag` plus an `opacity` rule
  instead.
* **Punctuation keysyms work in lower case** (`grave`, `slash`, `comma`); named keys in upper
  (`BACKSPACE`, `PRINT`, `Delete`). Omarchy's own warning about `comma` vs `COMMA` is the
  only documentation of this.

### 4e. What this left parked — not broken, not deleted

`monitor-mode.sh` (five layout profiles, `apply_monitor_tf()`, the fingerprint handshake),
`monitor-autoswitch.sh` (debounced hotplug), `monitor-menu.sh` and `hyprmon-edit.sh` all drive
the layout through `hyprctl keyword monitor`. They are **not started**; `lua/monitors.lua` is
the only owner of geometry now, so there is no profile switching and no hotplug reconcile.
The one piece that could not wait — the refresh rate following the power source — was pulled
out into `scripts/edp-rate.sh`. `monitors.md` §16, `power-battery.md` §19.

### 4f. Revert

```bash
cp /usr/share/hypr/hyprland.lua ~/.config/hypr/hyprland.lua   # back to the stock example
hyprctl reload
```

That is a revert to *upstream's* config, not to the old one: the `.conf` tree cannot be
restored, because no binary that reads it is installed any more. A real rollback means
downgrading — `hyprland-0.56.2-3.1`, `aquamarine-0.15.1-1.1`, `hyprlock-0.9.6-3.1`,
`hyprland-guiutils-0.2.2-4.1` are all in `/var/cache/pacman/pkg` (which is why §5 says not to
prune the cache) — and moving `hyprland.lua` aside, because in 0.56.2 a Lua config also wins
when it exists. Emergency mode survives either way: a Lua error that registers no binds leaves
`SUPER + Q` alive, verified in 0.57.1's `strings`.

### 4g. What this section predicted wrongly

Kept per `../CLAUDE.md`'s rule that retracted reasoning stays visible, because each of these
cost real time:

* **"A `hyprland.lua`, when present, wins; when absent, the legacy parser runs. So the
  migration is an A/B you control."** (old §4c) — false from 0.57.1. When absent, Hyprland
  *generates* one. There is no A/B and no opt-out; the upgrade decides.
* **"Auto-reload — `[lua] file {} modified, reloading`."** (old §4b) — not in 0.57.1.
  Writing a `.lua` changes nothing until an explicit `hyprctl reload`.
* **"`hl.on` exposes only `hyprland.start` and `hyprland.shutdown` in the stubs. There are no
  hotplug events, so `monitor-autoswitch.sh` cannot become Lua event handlers."** (old §4b) —
  false. 0.57.1's stub lists `monitor.added`, `monitor.removed`, `monitor.layout_changed` and
  `monitor.focused`, among ~38 events. The autoswitcher **can** become a Lua handler, and
  `lua/qconsole.lua` already uses two of those events. This is the most useful of the three
  errors to have corrected.
* **"0.57.0 is in the pending queue and no release note confirms it."** — the removal landed
  in 0.57.1, and the way to have known was not a release note but
  `strings /usr/bin/Hyprland | grep -i 'legacy config'` on the package **before** installing
  it. §1 of this runbook now has somewhere to put that check.
---

## 5. Hygiene

### 5a. `paccache.timer` — ✅ **enabled 2026-11-03** (was disabled)

The package cache holds **7282 packages / 15 GB**. But do not prune it to nothing: the cache is
both the three-way merge base for `pacdiff -3` (§2) and the only downgrade path for a bad
package.

```bash
sudo systemctl enable --now paccache.timer     # runs paccache -r, keeps 3 versions
```

✅ Done — `../tests/check-live-system.sh` PASSes on it as of 2026-11-03. The reasoning
above is why the timer runs `paccache -r` (keep 3) and not a full prune: `-k3` is what
leaves `pacdiff -3` a merge base and `pacman -U` a downgrade path.

### 5b. `snap-pac` — mark the upgrade snapshots important

`/etc/snap-pac.ini` is entirely commented out, i.e. all defaults. The snapper `root` config has
`NUMBER_LIMIT="50"` and `NUMBER_LIMIT_IMPORTANT="15"` as **separate quotas**, and
`TIMELINE_CREATE="no"` — so pacman snapshots are the *only* snapshots, and a kernel upgrade's
snapshot currently competes with 50 ordinary transactions for its place.

```ini
[root]
important_packages = ["linux-cachyos", "linux-cachyos-lts", "nvidia-utils"]
important_commands = ["pacman -Syu"]
```

That single change is the highest-value edit in this runbook for making the rollback real.

### 5c. Orphans

`pacman -Qtdq` lists 12. Review them individually; do not pipe them into `-Rns` unseen.

---

## 6. Rollback — and the fact that it has never been tested

`snap-pac`'s hooks (`05-snap-pac-pre`, `zz-snap-pac-post`) wrap **every** pacman transaction in
a pre/post btrfs snapshot, and `limine-snapper-sync.service` is **enabled**, which turns those
snapshots into bootable Limine entries. `MAX_SNAPSHOT_ENTRIES=8` caps the menu at the last 8.

```bash
sudo snapper -c root list          # the numbers; the pre-snapshot is the handle
limine-snapper-list                # what is actually offered at boot
limine-snapper-info <number>
limine-snapper-restore <number>
```

⚠ **No snapshot entry on this machine has ever been booted.** This is the same unverified-escape-hatch
shape as the LTS entry in `boot-suspend.md` §0: the mechanism is installed, enabled and
plausible, and that is not the same as working. Booting a snapshot entry is read-only and
costs one reboot — the cheapest open item in this repo.

### 6a. What a snapshot does and does not cover

⚠ Verified 2026-11-03 — this is narrower than it looks. snapper's `root` config snapshots the
subvolume mounted at `/`, which is `/dev/nvme0n1p2[/@]`. Everything else on this machine is
either a separate subvolume or a different filesystem:

```
/            nvme0n1p2[/@]       btrfs   ← snapshotted
├─/home      nvme0n1p2[/@home]   btrfs   ← NOT
├─/root      nvme0n1p2[/@root]   btrfs   ← NOT
├─/srv       nvme0n1p2[/@srv]    btrfs   ← NOT
├─/var/cache nvme0n1p2[/@cache]  btrfs   ← NOT
├─/var/log   nvme0n1p2[/@log]    btrfs   ← NOT
├─/var/tmp   nvme0n1p2[/@tmp]    btrfs   ← NOT
└─/boot      nvme0n1p1           vfat    ← NOT (the ESP)
```

So a rollback **does** restore `/etc`, `/usr` and — this is the one worth knowing —
`/usr/lib/modules/`, which means the kernel's modules come back with it.

It does **not** restore:

* **`/boot`**, a vfat ESP. The newer kernel's image and initramfs stay there. That is exactly
  what `limine-mkinitcpio-hook` and `limine-snapper-sync` exist to keep consistent, and why
  `/boot/limine.conf` must never be hand-edited (`../CLAUDE.md`) — they rewrite it.
* **`/home`**, so **nothing under `~/.config` is rolled back.** A snapshot will not undo a bad
  edit to the live Hyprland config, hyprlock, waybar or kitty. That is what `configs/` in this
  repo is for; the two recovery mechanisms cover different halves of the machine and neither
  substitutes for the other.
* **`/var/cache`**, which is a feature here: a rollback leaves `/var/cache/pacman/pkg` intact,
  so the downgrade path and the `pacdiff -3` merge base survive it (§2, §5a).
* **`/var/log`**, so the journal from the failed boot is still readable after rolling back —
  also a feature, and the reason a post-mortem is possible at all.

---

## 7. Verification

`../tests/check-live-system.sh` is read-only, needs no sudo, and exits non-zero on a broken
invariant. It covers what this machine loses *silently*:

| Check | Why it is in there |
|---|---|
| `dkms status` for the running **and** the installed kernel | the DKMS hook builds at install time, so a failed build is visible **before** you reboot into the new kernel |
| `/sys/bus/wmi/drivers/acer-wmi-battery/health_mode` == 1 | the only node that answers "is the charge cap on?". `BAT1` exposes no `charge_control_*` — do not check for one |
| `/sys/module/acer_wmi/parameters/predator_v4` == `Y`, a platform-profile node, an `acer` hwmon | all three vanish together if the forced quirk stops applying → `power-battery.md` §17 |
| effective `DefaultTimeoutStopSec` ≤ 15 s, **and which file supplies it** | reading `/etc/systemd/system.conf` is not evidence — see §2c |
| `/sys/module/nvidia/version` == `pacman -Q nvidia-utils` | the partial-upgrade signature, read without waking the dGPU |
| `configs/` vs the live system, file by file | the manifest lives in the script. Effective-line drift is a failure; comment-only drift is a note; `vlcrc` and `hyprlock.conf` drift by design and never fail |
| `.pacnew` count, `checkupdates`, `paccache.timer`, `limine-snapper-sync`, snap-pac hooks | §2, §5, §6 |
| `KERNEL_CMDLINE[default]` carries `thunderbolt.host_reset=0` and `mem_sleep_default=s2idle` | these apply to **every** Limine entry including LTS → `boot-suspend.md` §0 |

---

## Issue history

### 2026-11-04 — the reboot the 662-package upgrade was owed, and the premises it moved

Booted 09:05 on `7.3.1-1-cachyos`. `../tests/check-live-system.sh`: **19 passed, 0 failed**,
one warning (the 11 `.pacnew`) and six notes. The two FAILs that the 2026-11-03 entry below
records as "not faults" are **both gone**, as that entry predicted they would be: `dkms
acer-wmi-battery (running)` and `kernel is the installed one` now PASS on `7.3.1-1-cachyos`.
The `reboot owed` WARN that explained them is gone with them.

What the reboot **proved**, none of which a `reload` or a live module poke could:

* `predator_v4=Y` after a real `acer_wmi` load, `platform_profile` present, `acer` hwmon at
  `hwmon5`, `health_mode=1` — the forced module parameter survives a boot, which is the only
  way it is ever set (`0444`, load-time only). `power-battery.md` §17.
* `nvidia` module and `nvidia-utils` both **615.78.08**: the version lock held across the
  upgrade, so KMS came up and Hyprland did not black-screen.
* The Lua config's `hyprland.start` handler fires on a cold boot — §4c.
* The only warning in the boot journal is the already-documented benign `DP-0` EDID line.

What it **moved**, and this is the part §3 exists for: four of that table's six rows now
describe versions that are not loaded any more — kernel 7.3.1 (i915), hyprpaper 0.8.5, NVIDIA
615.78.08 (GSP), `linux-cachyos-lts` 6.18.55. None of the four conclusions was re-measured;
each is now a note about a version this machine no longer runs. `libfprint` is the one that
held still, which is the only reason `patches/` still applies.

What the reboot did **not** clear, in the order the dependency chain forces:

1. The **11 `.pacnew`** are untouched. `/etc/pam.d/sudo.pacnew` was diffed and is exactly as
   §2a describes: it drops `auth sufficient pam_fprintd.so # chwd-fprintd` (keep it) and adds
   `session optional pam_systemd.so class=none` (adopt it).
2. `meson`, `gobject-introspection`, `gtk-doc`, `umockdev` — still **none installed**, so the
   libfprint patch is still unbuilt. `hyprpicker` is still missing too, and one
   `paru -Syu --needed` closes both. 2 ordinary updates pending (chrome 157, vscode 1.145).
3. The **rollback path still has never booted** — `linux-cachyos-lts` 6.18.55 is installed
   with its modules in place and remains unexercised. `boot-suspend.md` §0.
4. **Three mirrored files drifted, repo → live**, comments only and no behaviour: the live
   `/etc/modprobe.d/acer-wmi-predator-v4.conf` is still the **Spanish** draft the repo
   replaced with English, and it plus `/etc/modprobe.d/acer-wmi-battery.conf` and the
   now-inert `~/.config/hypr/env.conf` still cite the dissolved
   `finish-installation-commands.md`. The repo copy is the correct one in all three cases, so
   this is a push: `sudo install -Dm644` for the two under `/etc/modprobe.d/`. The live-system
   check reports these as notes, not failures, which is why they survived the restructure.

Not verifiable from this boot, and recorded as such so it is not mistaken for verified: the
dock was disconnected (only `eDP-1` enumerated), so `lua/monitors.lua` and the per-monitor
workspace `BLOCKS` are still untested against the externals; no suspend has been taken, so
GSP on 615.78.08 is unmeasured; the battery was at 54 % charging, so the 80 % cut-off was not
reached; and the AC↔battery **transition** is still untried.

### 2026-11-03 — the first upgrade through this procedure, and the two FAILs that are not faults

662 packages, started 18:47:56, five weeks after the previous one. The procedure in §1 was
followed as written. What it caught, and what it should say next time:

**The pre-reboot run of `../tests/check-live-system.sh` is the step that earned its place**,
and it is also the step most likely to be misread. It reported two FAILs:

| FAIL | what it actually means |
|---|---|
| `dkms acer-wmi-battery (running) — not installed for 7.2.8-1-cachyos` | the transaction **removed the running kernel's module tree**. `/usr/lib/modules` now holds only `6.18.55-2-cachyos-lts` and `7.3.1-1-cachyos`, and `dkms status` shows the module built and installed for **both**. Nothing to rebuild. ⚠ The FAIL's own text, *"the charge cap is dead"*, is **wrong in this state**: `acer_wmi_battery` is still loaded from before the upgrade and the same report PASSes `health_mode` = `1` three lines earlier. What is gone is the ability to *reload* it. |
| `nvidia module 615.71.09, package 615.78.08 — partial upgrade` | the loaded module is the old one; the new one cannot load into a kernel whose modules are gone. The string *partial upgrade* is the checker describing a mismatch, **not** an accusation that `-S` was used. |

⚠ **Both clear on reboot, and the wrong response to either is to install something.** That is
the only way to turn this expected state into the real partial upgrade §1a describes. A future
version of the checker should distinguish *reboot owed* from *invariant broken* — it already
emits the `reboot owed` WARN that explains both FAILs, three lines above them.

**11 `.pacnew` files pending, and this upgrade created none of them.** The newest is dated
**2026-10-17**; the oldest, `/etc/resolv.conf.pacnew`, is from 2025. They are the audit's
backlog minus `cachyos-mirrorlist.pacnew`, which is no longer on disk — §2b names it among
the four to delete rather than merge, and when it went is not recorded here. 662 packages
moved without one file this machine has edited being replaced, which is worth knowing: the
`.pacnew` count is a backlog, **not** a per-upgrade symptom.

⚠ A correction that cost nothing here and would have cost a session later:
`/etc/pam.d/sudo` is owned by **`sudo`**, not by `pam` — `pacman -Qo` says so — and its
`.pacnew` is dated **2026-06-17**. `pam 1.7.2 → 1.7.3` moving in this transaction is not
what put it there. It remains the most consequential of the 11 for exactly the reason §2a
already tabulated: it **drops** the `pam_fprintd` line and **adds**
`session optional pam_systemd.so class=none`.

**What did not move:** `libfprint 1.94.100-1.1` and `fprintd 1.94.5-2.1`, so the patch in
`../patches/` still applies to the installed source as verified
(`../runbooks/fingerprint.md` §20x). 1.94.100 is upstream's newest tag.

⚠ **Still owed at the time of writing:** the reboot, the post-reboot gate, and the `.pacnew`
merge — in that order, which is **not** the order §1's block prints. §1 puts `pacdiff` before
`reboot`, and the reason it gives for the pre-reboot step is to catch a failed DKMS build
while the old session is alive; that reason belongs to the *checker*, not to `pacdiff`. On
this run the merge was deferred because none of the 11 pending files is read at boot, and a
mis-merged `/etc/pam.d/sudo` or `/etc/pacman.conf` surfaces at the next `sudo` or the next
upgrade rather than at the next boot. See the note under §1.

### 2026-11-03 — the first audit, and what five weeks of drift looked like

Written after `../ACTUAL-CONFIGURATION.md` was brought back in line with the live system. The
state found:

* **648 repo updates pending**, last full upgrade **2026-09-26**.
* **12 `.pacnew` files** accumulated, the oldest from **April 2026**. Four of them sat on top of
  hand-edited lines.
* `paccache.timer` disabled, **15 GB / 7282 packages** cached.
* `/etc/snap-pac.ini` at defaults — the kernel snapshot had no protected quota.
* The rollback path fully installed and **never once exercised**.

Three findings changed what this runbook says, rather than merely being recorded by it:

1. **`/etc/systemd/system.conf`'s `DefaultTimeoutStopSec=15s` has never been in effect**, because
   `cachyos-settings` ships `/usr/lib/systemd/system.conf.d/00-timeout.conf` with `10s` and a
   drop-in beats the main file. Found by the first run of `../tests/check-live-system.sh`, which
   failed on it. The shutdown fix is satisfied anyway, more strictly, by CachyOS — so the
   conclusion was wrong and the outcome was fine, which is the combination least likely to be
   noticed. §2c.
2. **`hyprctl keyword` does not survive the Lua config migration**, which moves that item from
   "rewrite 485 lines" to "rewrite the automation layer". §4a.
3. **Three comments under `configs/` still pointed at the dissolved `finish-installation-commands.md`.**
   `../tests/check-doc-refs.sh` had never looked at them — its file list stopped at `.md`, `.sh`
   and `.py` — even though `../CLAUDE.md` requires those comments to be maintained like any other
   document. The checker was widened to every tracked text file and the three were re-pointed.

Nothing was upgraded in this session. The procedure above was written first, deliberately, so
the 648-package transaction runs against a gate and a verifier instead of against hope.
