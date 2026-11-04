# cachyPool

Documentation and dotfiles for a single machine: an **Acer Predator PT516-52s** (Triton 500
SE, hostname `triton500se`) running **CachyOS + Hyprland on Wayland** with an NVIDIA RTX
3080 Ti that turns out not to render the session.

This is **not a software project** — there is no build, test, or lint pipeline. It is a
version-tracked record of how this machine is set up, what is broken, how to fix it, and how
to drive it day to day. `configs/` mirrors the live dotfiles so they can be tracked in git.
The one piece of real source is `triton-panel/`, a GTK4 app for this laptop's own hardware.

## Where to look

| You want | Go to |
|---|---|
| What the machine **is** right now | `ACTUAL-CONFIGURATION.md` |
| What **changed** and when | `CHANGELOG.md` |
| How to **drive** it — keybindings, workflows | `shortcuts.md` |
| How a subsystem **works, breaks and gets fixed** | `runbooks/` → start at `runbooks/README.md` |
| Superseded material, kept for the record | `archive/` → `archive/README.md` |
| Rules for Claude Code in this repo | `CLAUDE.md` |

```
cachyPool/
├── ACTUAL-CONFIGURATION.md     ← the snapshot: hardware, OS, packages, daemons, §15 todo list
├── CHANGELOG.md                ← append-only history, newest first
├── shortcuts.md                ← daily driving
├── CLAUDE.md                   ← rules + pointers (no narrative)
├── runbooks/                   ← one file per subsystem, sole owner of its ground
│   ├── bluetooth.md  boot-suspend.md  desktop-apps.md  fingerprint.md
│   └── gpu-video.md  monitors.md  power-battery.md  triton-panel.md
├── archive/                    ← install-era docs and applied-once remediation
├── triton-panel/               ← GTK4 hardware panel (source + 2 regression tests)
├── tests/                      ← regression tests, incl. check-doc-refs.sh for the docs and
│                                 check-live-system.sh for the machine itself
└── configs/                    ← mirror of live dotfiles (hypr, waybar, kitty, …)
```

## Documentation guidelines

Six conventions, adopted 2026-11-03 when the docs were restructured. They exist because the
previous shape failed in a specific, measurable way: the history had grown to **13 KB inside
one metadata line**, a single table cell had reached **22.7 KB**, and the sections those two
pushed down the page went four months without a refresh — reporting a kernel, a driver and a
monitor layout that had all been replaced. Each guideline removes one of the incentives that
produced that.

**1. Three kinds of document, and every file is exactly one.**
*State* (`ACTUAL-CONFIGURATION.md`) says what is true now and carries no history.
*Runbook* (`runbooks/*.md`) carries the reasoning: failure mode → diagnosis → fix →
verification. *Daily use* (`shortcuts.md`) is the usage reference. A file that drifts into
being two of these is the bug that started all of this.

**2. One owner per subsystem — scope, not rank.**
This repo used to need a seven-deep "source-of-truth hierarchy" because several documents
claimed the same ground. The one document that never needed ranking was `runbooks/bluetooth.md`: sole
owner of one subsystem, self-contained. Ranking was treating the symptom. If two files cover
the same subject, fix the ownership instead of ordering them.

**3. History is append-only and lives in `CHANGELOG.md`.**
Never in a document's header, never as prose inside a table cell. This is the load-bearing
one: when appending to a header costs nothing and refreshing the body costs real work,
everybody appends to the header and the body rots. New live state goes in exactly two places
— one changelog entry and the owning runbook.

**4. Section numbers survive a move.**
`runbooks/` and `archive/` keep the numbers their sections had in the file they came from, so
numbering inside a file is deliberately not contiguous. Any `§N` reference in any doc, script
comment or commit message still resolves: `grep -rn '§20g' runbooks/ archive/`. A new runbook
numbers its own sections from §1.

**5. Nothing is deleted.**
Superseded material moves to `archive/` with a banner, never corrected into agreement with
the present — that would make it compete with the snapshot instead of dating itself. The
reason is concrete: the most valuable thing in this repo is a *retracted* conclusion
(`runbooks/fingerprint.md` §20g), wrong but built on a true premise, which is exactly why the
eventual fix is understandable.

**6. `CLAUDE.md` is rules, not narrative.**
Imperatives plus a pointer to the runbook that holds the reasoning. A narrative `CLAUDE.md`
hides its rules inside the story, which is how a badly-derived one survived three sessions of
blocking a fix.

These were applied in that order, and the order was chosen so the cheapest irreversible step
came first: extract the changelog (1), split into runbooks (2), slim the snapshot (3), cut
`CLAUDE.md` to rules (4), rewrite this file (5), banner the archive (6). The move itself, with
a table mapping every old section to its new file, is the first entry in `CHANGELOG.md`.

## The system at a glance

| | |
|---|---|
| Hardware | Acer Predator PT516-52s · i9-12900H · RTX 3080 Ti Laptop (16 GB) · 31 GiB DDR5 |
| OS | CachyOS (Arch-based, rolling) · kernel `7.2.8-1-cachyos` (BORE) · LTS `6.18.52-1` |
| Compositor | Hyprland 0.56.2 on Wayland (KDE Plasma installed as fallback) |
| NVIDIA | Open GSP driver 615.71.09 · KMS enabled · **offload-only, does not render the session** |
| GPU in use | The **Intel iGPU** drives the compositor and all three monitors |
| Bootloader | **Limine** (not GRUB) · btrfs root with Snapper snapshots |
| Display manager | **None** — `getty@tty1` autologin → fish → `exec start-hyprland` |
| Shell | `/bin/fish` (login shell) |
| Battery | Replacement Getac `AP20BHU` fitted 2026-10-31 · 80% charge cap **proven** |
| Theme | Catppuccin Mocha · JetBrainsMono Nerd Font |

### Monitor layout (left-to-right)

Logical pixels, static 3-across `desktop` profile:

```
eDP-1                    (laptop 16",         0–2048px, scale 1.25, 240Hz)
desc:Xiaomi …Mi Monitor  (27" 4K,          2048–5120px, scale 1.25,  60Hz)  ← primary, WS 1
desc:Invalid Vendor …RTK (portable QHD 16", 5120–7168px, scale 1.25, 120Hz)
```

Workspaces (`configs/hypr/monitors.conf`): WS 1–3 → Xiaomi, 4–5 → eDP-1, 6–9 → portable.

**Never bind anything to `DP-1`/`DP-2`.** Both externals are DP tunnels over one Thunderbolt
connector, so whichever trains first takes the low number — they float with plug order.
Monitors *and* workspaces are matched by EDID `desc:`. The live layout is chosen by a
debounced hotplug daemon; see `runbooks/monitors.md`.

## Hyprland config architecture

`configs/hypr/hyprland.conf` is a thin entrypoint that sources modular files:

```
hyprland.conf → env.conf → monitors.conf → input.conf → look.conf
             → keybindings.conf → windowrules.conf → autostart.conf
```

Plus three sibling daemons with their own configs: `hyprpaper.conf`, `hyprlock.conf`,
`hypridle.conf`. When editing behaviour, find the right modular file rather than dumping
everything into `hyprland.conf`.

## Working with config changes

`configs/` is a **mirror**, not the live config — there is no sync automation, so keep both in
step by hand.

```bash
cp configs/hypr/<file>.conf ~/.config/hypr/<file>.conf   # push to live
hyprctl reload                                           # apply without logout
cp ~/.config/hypr/<file>.conf configs/hypr/<file>.conf   # pull a live edit back
```

`hyprctl reload` re-reads all sourced files but does **not** reload `hyprpaper`, `hypridle` or
`hyprlock` — restart those individually (`pkill hyprpaper; hyprpaper & disown`). Two system
paths are mirrored too (`configs/modprobe.d/`, `configs/systemd/logind.conf.d/`); push them
with `sudo install -Dm644` and always check the live copy exists before trusting the repo.

## Hardware gotchas

Easy to break, hard to debug. Full rules in `CLAUDE.md`, reasoning in the runbooks.

- **NVIDIA + Wayland needs KMS** — driver-default `modeset` plus early module loading from
  `/etc/mkinitcpio.conf.d/10-chwd.conf`. Do not add `nvidia-drm.modeset=1` to the cmdline.
- **The dGPU is offload-only and frequently dead after suspend/resume** (GSP re-init failure).
  Never assume it is available.
- **Limine, not GRUB** — cmdline edits go in `/etc/default/limine`, then
  `sudo limine-mkinitcpio`. Direct edits to `/boot/limine.conf` get wiped.
- **Fans and the 5-state platform profile only exist** because `acer_wmi` is forced with
  `predator_v4=1`. Fan *reading* only, no PWM, no keyboard RGB.
- **`env.conf` only reaches processes Hyprland spawns** — Walker-launched apps never see it,
  which is why Firefox's video-decode pause lives in its profile `user.js`.
- **`Super+Shift+Q` restarts the compositor**, it does not log out. To really log out:
  `Ctrl+Alt+F2`, then `loginctl terminate-user isalgado`.

## Replicating this setup

`ACTUAL-CONFIGURATION.md` §17 has the rebuild sequence: install CachyOS (Hyprland + KDE,
btrfs, Limine) → `sudo cachyos-chwd -a` for NVIDIA → verify KMS → install the Hyprland stack
→ restore `configs/` into `~/.config/` → apply `runbooks/boot-suspend.md` §10 for the
autologin boot path.

---

*Dates in this repo are in the 2026 timeline. When live state changes: one entry in
`CHANGELOG.md` and an update to the owning runbook.*
